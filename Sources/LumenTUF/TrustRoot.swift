// TrustRoot.swift
// Root trust bootstrap and validation.
//
// The first root metadata is bundled with the application. It is self-signed
// (signed by the keys it defines for the root role). After bootstrap, root
// rotation is supported via signed root metadata with a higher version.

import Foundation
import LumenCrypto

public struct TrustRoot: Codable, Equatable, Sendable {
    public let metadata: TUFRootMetadata
    public let canonicalBytes: Data
    public let version: Int

    public init(metadata: TUFRootMetadata, canonicalBytes: Data) {
        self.metadata = metadata
        self.canonicalBytes = canonicalBytes
        self.version = metadata.version
    }
}

public enum TrustRootBootstrap {

    /// Bootstrap a trust root from bundled raw metadata bytes.
    /// The bundled root is verified against itself (self-signed) using the
    /// root keys defined in the metadata.
    public static func bootstrap(from data: Data) throws -> TrustRoot {
        let decoded = try MetadataDecoder.decodeSignedRoot(data)
        let envelope = decoded.metadata
        let signedCanonical = try canonicalizeSigned(envelope.signed)

        // The root is self-signed: signatures must be from keys in roles.root.keyids
        try SignatureVerifier.verifyThreshold(
            signatures: try TUFTypeAdapters.convertSignatures(envelope.signatures),
            canonicalBytes: signedCanonical,
            trustedKeys: try TUFTypeAdapters.convertKeys(envelope.signed.keys),
            requiredKeyids: envelope.signed.roles.root.keyids,
            threshold: envelope.signed.roles.root.threshold,
            roleName: "root"
        )

        return TrustRoot(metadata: envelope.signed, canonicalBytes: signedCanonical)
    }

    /// Validate a new root metadata against a trusted root.
    /// The new root MUST be signed by the OLD root's keys (for root rotation).
    /// After validation, the new root's version MUST be > the old root's version.
    public static func validateRotation(
        newData: Data,
        oldRoot: TrustRoot
    ) throws -> TrustRoot {
        // Version must be strictly greater
        guard oldRoot.version > 0 else {
            throw LumenError.noTrustedRoot
        }

        let decoded = try MetadataDecoder.decodeSignedRoot(newData)
        let envelope = decoded.metadata

        guard envelope.signed.version > oldRoot.version else {
            throw LumenError.versionRollback(
                role: "root",
                received: envelope.signed.version,
                stored: oldRoot.version
            )
        }

        // Per TUF §5.3.4: the new root MUST be signed by BOTH the old root's
        // keys AND the new root's own keys. Verifying only the old root would
        // let a compromised old key publish a root the new keys never endorsed.
        let signedCanonical = try canonicalizeSigned(envelope.signed)

        // 1. Verify against the OLD root's keys
        try SignatureVerifier.verifyThreshold(
            signatures: try TUFTypeAdapters.convertSignatures(envelope.signatures),
            canonicalBytes: signedCanonical,
            trustedKeys: try TUFTypeAdapters.convertKeys(oldRoot.metadata.keys),
            requiredKeyids: oldRoot.metadata.roles.root.keyids,
            threshold: oldRoot.metadata.roles.root.threshold,
            roleName: "root (old)"
        )

        // 2. Verify against the NEW root's own keys
        try SignatureVerifier.verifyThreshold(
            signatures: try TUFTypeAdapters.convertSignatures(envelope.signatures),
            canonicalBytes: signedCanonical,
            trustedKeys: try TUFTypeAdapters.convertKeys(envelope.signed.keys),
            requiredKeyids: envelope.signed.roles.root.keyids,
            threshold: envelope.signed.roles.root.threshold,
            roleName: "root (new)"
        )

        return TrustRoot(metadata: envelope.signed, canonicalBytes: signedCanonical)
    }

    /// Compute canonical bytes for a signed metadata object (the `signed` field only).
    /// This is what signatures are computed over.
    public static func canonicalizeSigned<T: Encodable>(_ value: T) throws -> Data {
        return try MetadataDecoder.canonicalizeForSigning(value)
    }
}
