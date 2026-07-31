// TUFVerifier.swift
// Complete TUF metadata verification pipeline.
//
// Per SPEC.md §8, the verifier orchestrates:
// 1. Root → timestamp → snapshot → targets → delegated targets
// 2. Signature threshold verification at each step
// 3. Version tracking and rollback detection
// 4. Expiration checking
// 5. Mix-and-match detection (snapshot references targets by version)

import Foundation
import LumenCrypto

public struct VerificationInputs: Sendable {
    public let trustRoot: TrustRoot
    public let timestampData: Data
    public let snapshotData: Data
    public let targetsData: Data
    public let delegatedData: [String: Data]  // role name -> metadata bytes
    public let host: HostProfile
    public let now: Date

    public init(
        trustRoot: TrustRoot,
        timestampData: Data,
        snapshotData: Data,
        targetsData: Data,
        delegatedData: [String: Data] = [:],
        host: HostProfile,
        now: Date = Date()
    ) {
        self.trustRoot = trustRoot
        self.timestampData = timestampData
        self.snapshotData = snapshotData
        self.targetsData = targetsData
        self.delegatedData = delegatedData
        self.host = host
        self.now = now
    }
}

public struct VerificationResult: Sendable {
    public let resolvedTarget: ResolvedTarget
    public let newVersions: [String: Int]
    public let trustRootVersion: Int

    public init(resolvedTarget: ResolvedTarget, newVersions: [String: Int], trustRootVersion: Int) {
        self.resolvedTarget = resolvedTarget
        self.newVersions = newVersions
        self.trustRootVersion = trustRootVersion
    }
}

public enum TUFVerifier {

    public static func verify(
        inputs: VerificationInputs,
        versionTracker: VersionTracker = VersionTracker()
    ) throws -> VerificationResult {
        let root = inputs.trustRoot

        // M3: Enforce total metadata size limit (SPEC.md §6: 100 KB)
        let totalSize = inputs.timestampData.count + inputs.snapshotData.count
            + inputs.targetsData.count
            + inputs.delegatedData.values.reduce(0) { $0 + $1.count }
        guard totalSize <= MetadataSizeLimits.totalMetadataFetch else {
            throw LumenError.metadataTooLarge(
                role: "total",
                size: totalSize,
                limit: MetadataSizeLimits.totalMetadataFetch
            )
        }

        // Work on a snapshot of versions so a partial failure doesn't poison
        // the tracker. Only commit at the very end after ALL checks pass.
        let pendingVersions = versionTracker.export()
        func pendingVersion(_ role: String) -> Int { pendingVersions[role] ?? 0 }
        func validatePending(_ newVersion: Int, _ role: String) throws {
            let stored = pendingVersion(role)
            guard newVersion > stored else {
                throw LumenError.versionRollback(role: role, received: newVersion, stored: stored)
            }
        }

        // === Step 1: Verify timestamp ===
        let timestampDecoded = try MetadataDecoder.decodeSignedTimestamp(inputs.timestampData)
        let timestampCanonical = try TrustRootBootstrap.canonicalizeSigned(timestampDecoded.metadata.signed)

        // Verify timestamp signatures
        try SignatureVerifier.verifyThreshold(
            signatures: try TUFTypeAdapters.convertSignatures(timestampDecoded.metadata.signatures),
            canonicalBytes: timestampCanonical,
            trustedKeys: try TUFTypeAdapters.convertKeys(root.metadata.keys),
            requiredKeyids: root.metadata.roles.timestamp.keyids,
            threshold: root.metadata.roles.timestamp.threshold,
            roleName: "timestamp"
        )

        // Version check (against pending snapshot, not live tracker)
        try validatePending(timestampDecoded.metadata.signed.version, "timestamp")

        // Expiration check
        try ExpirationChecker.checkExpiration(
            expires: timestampDecoded.metadata.signed.expires,
            now: inputs.now,
            role: "timestamp"
        )

        // === Step 2: Verify snapshot (version from timestamp) ===
        let timestampSnapshotMeta = timestampDecoded.metadata.signed.meta["snapshot.json"]
        guard let snapshotMeta = timestampSnapshotMeta else {
            throw LumenError.missingField("timestamp.meta.snapshot.json")
        }
        guard snapshotMeta.version >= 1 else {
            throw LumenError.invalidVersion("snapshot version \(snapshotMeta.version)")
        }
        try verifyFileIntegrity(
            data: inputs.snapshotData,
            expectedLength: snapshotMeta.length,
            expectedHashes: snapshotMeta.hashes,
            role: "snapshot"
        )

        let snapshotDecoded = try MetadataDecoder.decodeSignedSnapshot(inputs.snapshotData)
        let snapshotCanonical = try TrustRootBootstrap.canonicalizeSigned(snapshotDecoded.metadata.signed)

        // Verify snapshot signatures
        try SignatureVerifier.verifyThreshold(
            signatures: try TUFTypeAdapters.convertSignatures(snapshotDecoded.metadata.signatures),
            canonicalBytes: snapshotCanonical,
            trustedKeys: try TUFTypeAdapters.convertKeys(root.metadata.keys),
            requiredKeyids: root.metadata.roles.snapshot.keyids,
            threshold: root.metadata.roles.snapshot.threshold,
            roleName: "snapshot"
        )

        // Version check (against pending snapshot)
        try validatePending(snapshotDecoded.metadata.signed.version, "snapshot")

        // Mix-and-match check: snapshot version must match what timestamp claimed
        guard snapshotDecoded.metadata.signed.version == snapshotMeta.version else {
            throw LumenError.repositoryInvalidResponse(
                "Snapshot version mismatch: timestamp says \(snapshotMeta.version), got \(snapshotDecoded.metadata.signed.version)"
            )
        }

        // Expiration check
        try ExpirationChecker.checkExpiration(
            expires: snapshotDecoded.metadata.signed.expires,
            now: inputs.now,
            role: "snapshot"
        )

        // === Step 3: Verify targets (version from snapshot) ===
        let snapshotTargetsMeta = snapshotDecoded.metadata.signed.meta["targets.json"]
        guard let targetsMeta = snapshotTargetsMeta else {
            throw LumenError.missingField("snapshot.meta.targets.json")
        }
        try verifyFileIntegrity(
            data: inputs.targetsData,
            expectedLength: targetsMeta.length,
            expectedHashes: targetsMeta.hashes,
            role: "targets"
        )

        let targetsDecoded = try MetadataDecoder.decodeSignedTargets(inputs.targetsData)
        let targetsCanonical = try TrustRootBootstrap.canonicalizeSigned(targetsDecoded.metadata.signed)

        // Verify targets signatures
        try SignatureVerifier.verifyThreshold(
            signatures: try TUFTypeAdapters.convertSignatures(targetsDecoded.metadata.signatures),
            canonicalBytes: targetsCanonical,
            trustedKeys: try TUFTypeAdapters.convertKeys(root.metadata.keys),
            requiredKeyids: root.metadata.roles.targets.keyids,
            threshold: root.metadata.roles.targets.threshold,
            roleName: "targets"
        )

        // Version check (against pending snapshot)
        try validatePending(targetsDecoded.metadata.signed.version, "targets")

        // Mix-and-match check
        guard targetsDecoded.metadata.signed.version == targetsMeta.version else {
            throw LumenError.repositoryInvalidResponse(
                "Targets version mismatch: snapshot says \(targetsMeta.version), got \(targetsDecoded.metadata.signed.version)"
            )
        }

        // Expiration check
        try ExpirationChecker.checkExpiration(
            expires: targetsDecoded.metadata.signed.expires,
            now: inputs.now,
            role: "targets"
        )

        // === Step 4: Verify delegated targets (if any) ===
        var delegatedMetadata: [String: TUFTargetsMetadata] = [:]
        let channelRole = "\(inputs.host.productID)-\(inputs.host.channel)"

        for (role, data) in inputs.delegatedData {
            // The snapshot must reference this delegated metadata
            guard let meta = snapshotDecoded.metadata.signed.meta[role] else {
                throw LumenError.invalidMetadataFormat("Delegated role \(role) not referenced in snapshot")
            }
            try verifyFileIntegrity(
                data: data,
                expectedLength: meta.length,
                expectedHashes: meta.hashes,
                role: role
            )
            let decoded = try MetadataDecoder.decodeSignedTargets(data, isDelegated: true)
            let canonical = try TrustRootBootstrap.canonicalizeSigned(decoded.metadata.signed)

            // Find the delegation definition in the parent targets metadata
            guard let delegation = targetsDecoded.metadata.signed.delegations?.roles.first(where: { $0.role == role }) else {
                throw LumenError.delegationNotFound(role)
            }

            // Build the trusted keys for this delegation (inline + parent)
            var delegationKeys: [String: TUFKey] = decoded.metadata.signed.delegations?.keys ?? [:]
            for kid in delegation.keyids {
                if delegationKeys[kid] == nil {
                    // Fall back to root keys
                    if let rootKey = root.metadata.keys[kid] {
                        delegationKeys[kid] = rootKey
                    }
                }
            }

            try SignatureVerifier.verifyThreshold(
                signatures: try TUFTypeAdapters.convertSignatures(decoded.metadata.signatures),
                canonicalBytes: canonical,
                trustedKeys: try TUFTypeAdapters.convertKeys(delegationKeys),
                requiredKeyids: delegation.keyids,
                threshold: delegation.threshold,
                roleName: role
            )

            try ExpirationChecker.checkExpiration(
                expires: decoded.metadata.signed.expires,
                now: inputs.now,
                role: role
            )

            // H3: Verify every target in this delegated role falls within
            // the delegation's authorized path patterns. A delegated role
            // signing targets outside its paths is a security violation.
            for targetPath in decoded.metadata.signed.targets.keys {
                guard DelegationPathMatcher.isPathAuthorized(targetPath, by: delegation.paths) else {
                    throw LumenError.delegationPathMismatch(role: role, path: targetPath)
                }
            }

            delegatedMetadata[role] = decoded.metadata.signed
        }

        // === Step 5: Resolve target ===
        let resolved = try TargetResolver.resolve(
            targets: targetsDecoded.metadata.signed,
            delegatedTargets: delegatedMetadata,
            host: inputs.host,
            now: inputs.now
        )

        // If the host's channel uses a delegated role, ensure it was provided
        if let _ = targetsDecoded.metadata.signed.delegations?.roles.first(where: { $0.role == channelRole }) {
            guard delegatedMetadata[channelRole] != nil else {
                throw LumenError.delegationNotFound(channelRole)
            }
        }

        // === Update version tracker ===
        versionTracker.acceptVersion(timestampDecoded.metadata.signed.version, forRole: "timestamp")
        versionTracker.acceptVersion(snapshotDecoded.metadata.signed.version, forRole: "snapshot")
        versionTracker.acceptVersion(targetsDecoded.metadata.signed.version, forRole: "targets")

        return VerificationResult(
            resolvedTarget: resolved,
            newVersions: versionTracker.export(),
            trustRootVersion: root.version
        )
    }

    /// Verify a file's length and hashes match the expected values.
    public static func verifyFileIntegrity(
        data: Data,
        expectedLength: Int,
        expectedHashes: [String: String],
        role: String
    ) throws {
        guard data.count == expectedLength else {
            throw LumenError.targetLengthMismatch(expected: expectedLength, actual: data.count)
        }
        for (alg, expected) in expectedHashes {
            switch alg {
            case "sha256":
                let actual = Base64URL.encode(LumenSHA256.hash(data: data))
                guard actual == expected else {
                    throw LumenError.targetHashMismatch(expected: expected, actual: actual)
                }
            default:
                throw LumenError.unsupportedKeyType("Unsupported hash algorithm: \(alg)")
            }
        }
    }
}
