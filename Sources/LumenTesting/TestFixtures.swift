// TestFixtures.swift
// Helper code for generating test metadata (root, targets, snapshot, timestamp)
// with valid Ed25519 signatures.

import Foundation
import LumenCore
import LumenCrypto
import LumenTUF
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Generates signed TUF metadata for testing.
public enum TestFixtures {

    /// A generated test keypair.
    public struct TestKey: Sendable {
        public let privateKey: Data  // 32 bytes (seed)
        public let publicKey: Data   // 32 bytes
        public let keyID: String      // base64url(SHA-256(publicKey))

        public init() throws {
            #if canImport(CryptoKit)
            let signingKey = Curve25519.Signing.PrivateKey()
            #else
            let signingKey = Curve25519.Signing.PrivateKey()
            #endif
            self.privateKey = signingKey.rawRepresentation
            self.publicKey = signingKey.publicKey.rawRepresentation
            self.keyID = SignatureVerifier.keyID(forPublicKey: signingKey.publicKey.rawRepresentation)
        }
    }

    /// Sign canonical bytes with a test key.
    public static func sign(_ canonicalBytes: Data, with key: TestKey) throws -> Data {
        #if canImport(CryptoKit)
        let signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: key.privateKey)
        return try signingKey.signature(for: canonicalBytes)
        #else
        let signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: key.privateKey)
        return try signingKey.signature(for: canonicalBytes)
        #endif
    }

    // MARK: - Root metadata

    public struct RootBundle: Sendable {
        public let trustRoot: TrustRoot
        public let rootKey: TestKey
        public let targetsKey: TestKey
        public let snapshotKey: TestKey
        public let timestampKey: TestKey
        public let rawSignedBytes: Data
    }

    /// Generate a self-signed root metadata with 1-of-1 thresholds for all roles.
    public static func makeRoot(
        version: Int = 1,
        expires: String = ISO8601DateFormatter.lumen.string(from: Date().addingTimeInterval(365 * 24 * 3600))
    ) throws -> RootBundle {
        let rootKey = try TestKey()
        let targetsKey = try TestKey()
        let snapshotKey = try TestKey()
        let timestampKey = try TestKey()

        let keys: [String: TUFKey] = [
            rootKey.keyID: TUFKey(keytype: "ed25519", scheme: "ed25519", publicKey: Base64URL.encode(rootKey.publicKey)),
            targetsKey.keyID: TUFKey(keytype: "ed25519", scheme: "ed25519", publicKey: Base64URL.encode(targetsKey.publicKey)),
            snapshotKey.keyID: TUFKey(keytype: "ed25519", scheme: "ed25519", publicKey: Base64URL.encode(snapshotKey.publicKey)),
            timestampKey.keyID: TUFKey(keytype: "ed25519", scheme: "ed25519", publicKey: Base64URL.encode(timestampKey.publicKey)),
        ]

        let roles = TUFRootMetadata.Roles(
            root: TUFRoleDefinition(keyids: [rootKey.keyID], threshold: 1),
            snapshot: TUFRoleDefinition(keyids: [snapshotKey.keyID], threshold: 1),
            targets: TUFRoleDefinition(keyids: [targetsKey.keyID], threshold: 1),
            timestamp: TUFRoleDefinition(keyids: [timestampKey.keyID], threshold: 1)
        )

        let rootMeta = TUFRootMetadata(
            version: version,
            expires: expires,
            keys: keys,
            roles: roles
        )

        // Canonicalize the signed payload
        let signedCanonical = try MetadataDecoder.canonicalizeForSigning(rootMeta)

        // Sign with the root key
        let sig = try sign(signedCanonical, with: rootKey)
        let signatures = [TUFSignature(keyid: rootKey.keyID, sig: Base64URL.encode(sig))]

        // Encode the full signed envelope (signatures + signed) canonically
        let envelope: [String: Any] = [
            "signatures": [["keyid": rootKey.keyID, "sig": Base64URL.encode(sig)]],
            "signed": try JSONSerialization.jsonObject(with: signedCanonical, options: [])
        ]
        let envelopeData = try CanonicalJSON.encode(envelope)

        let trustRoot = try TrustRootBootstrap.bootstrap(from: envelopeData)

        return RootBundle(
            trustRoot: trustRoot,
            rootKey: rootKey,
            targetsKey: targetsKey,
            snapshotKey: snapshotKey,
            timestampKey: timestampKey,
            rawSignedBytes: envelopeData
        )
    }

    // MARK: - Timestamp metadata

    public static func makeTimestamp(
        version: Int = 1,
        snapshotVersion: Int = 1,
        snapshotLength: Int,
        snapshotHash: String,
        expires: String = ISO8601DateFormatter.lumen.string(from: Date().addingTimeInterval(86400)),
        signedBy: TestKey
    ) throws -> Data {
        let meta: [String: TUFTimestampMetadata.MetaEntry] = [
            "snapshot.json": TUFTimestampMetadata.MetaEntry(
                version: snapshotVersion,
                length: snapshotLength,
                hashes: ["sha256": snapshotHash]
            )
        ]
        let ts = TUFTimestampMetadata(version: version, expires: expires, meta: meta)
        let signedCanonical = try MetadataDecoder.canonicalizeForSigning(ts)
        let sig = try sign(signedCanonical, with: signedBy)
        let envelope: [String: Any] = [
            "signatures": [["keyid": signedBy.keyID, "sig": Base64URL.encode(sig)]],
            "signed": try JSONSerialization.jsonObject(with: signedCanonical, options: [])
        ]
        return try CanonicalJSON.encode(envelope)
    }

    // MARK: - Snapshot metadata

    public static func makeSnapshot(
        version: Int = 1,
        targetsVersion: Int = 1,
        targetsLength: Int,
        targetsHash: String,
        delegated: [String: (version: Int, length: Int, hash: String)] = [:],
        expires: String = ISO8601DateFormatter.lumen.string(from: Date().addingTimeInterval(7 * 86400)),
        signedBy: TestKey
    ) throws -> Data {
        var meta: [String: TUFSnapshotMetadata.MetaEntry] = [
            "targets.json": TUFSnapshotMetadata.MetaEntry(
                version: targetsVersion,
                length: targetsLength,
                hashes: ["sha256": targetsHash]
            )
        ]
        for (role, info) in delegated {
            meta[role] = TUFSnapshotMetadata.MetaEntry(
                version: info.version,
                length: info.length,
                hashes: ["sha256": info.hash]
            )
        }
        let snap = TUFSnapshotMetadata(version: version, expires: expires, meta: meta)
        let signedCanonical = try MetadataDecoder.canonicalizeForSigning(snap)
        let sig = try sign(signedCanonical, with: signedBy)
        let envelope: [String: Any] = [
            "signatures": [["keyid": signedBy.keyID, "sig": Base64URL.encode(sig)]],
            "signed": try JSONSerialization.jsonObject(with: signedCanonical, options: [])
        ]
        return try CanonicalJSON.encode(envelope)
    }

    // MARK: - Targets metadata

    public static func makeTargets(
        version: Int = 1,
        productID: String = "com.example.testapp",
        bundleIdentifier: String = "com.example.testapp",
        bundleVersion: Int = 2,
        architectures: [String] = ["arm64"],
        channel: String = "stable",
        expires: String = ISO8601DateFormatter.lumen.string(from: Date().addingTimeInterval(90 * 86400)),
        signedBy: TestKey,
        bundleManifestSHA256: String = "deadbeef",
        delegationRole: String? = nil,
        delegationKey: TestKey? = nil,
        archiveFormat: String = "apple-archive"
    ) throws -> Data {
        let custom = LumenTargetCustom(
            productID: productID,
            bundleIdentifier: bundleIdentifier,
            bundleVersion: bundleVersion,
            shortVersion: "1.1.0",
            minimumSystemVersion: "13.0",
            architectures: architectures,
            channel: channel,
            archiveFormat: archiveFormat,
            bundleManifestSHA256: bundleManifestSHA256,
            releaseNotesTarget: nil,
            critical: false,
            rollout: nil
        )

        let targetPath = "sha256.\(bundleManifestSHA256).\(productID)-\(bundleVersion)-arm64.aar"
        let targetInfo = TUFTargetInfo(
            length: 1000,
            hashes: ["sha256": bundleManifestSHA256],
            custom: custom
        )

        let targets = TUFTargetsMetadata(
            version: version,
            expires: expires,
            targets: [targetPath: targetInfo],
            delegations: nil
        )

        let signedCanonical = try MetadataDecoder.canonicalizeForSigning(targets)
        let sig = try sign(signedCanonical, with: signedBy)
        let envelope: [String: Any] = [
            "signatures": [["keyid": signedBy.keyID, "sig": Base64URL.encode(sig)]],
            "signed": try JSONSerialization.jsonObject(with: signedCanonical, options: [])
        ]
        return try CanonicalJSON.encode(envelope)
    }

    // MARK: - Helpers

    public static func sha256Base64(_ data: Data) -> String {
        return Base64URL.encode(LumenSHA256.hash(data: data))
    }
}
