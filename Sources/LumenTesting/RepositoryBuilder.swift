import Foundation
import LumenCore
import LumenCrypto
import LumenTUF

/// Builds a complete, correctly-signed TUF repository on disk for integration
/// testing and demos. All hashes and lengths are computed from the actual bytes,
/// so the repository passes the full client verification pipeline.
public enum RepositoryBuilder {

    public struct BuiltRepository: Sendable {
        public let directory: URL
        public let rootBundle: TestFixtures.RootBundle
        public let productID: String
        public let channel: String
        public let bundleVersion: Int
        public let targetPath: String
        public let artifactURL: URL
        public let artifactHash: String
        public let artifactSize: Int

        public var trustRoot: TrustRoot { rootBundle.trustRoot }
    }

    /// Build a signed repository containing a single target release.
    ///
    /// - Parameters:
    ///   - directory: Where to write `metadata/` and `targets/`.
    ///   - productID: Target product identifier.
    ///   - bundleVersion: The release's monotonic bundle version.
    ///   - channel: Release channel (stable/beta/nightly).
    ///   - artifactContents: The raw update archive bytes.
    ///   - timestampExpires / snapshotExpires / targetsExpires: override expirations
    ///     (used to build deliberately-expired repositories for testing).
    public static func build(
        in directory: URL,
        productID: String = "com.example.testapp",
        bundleVersion: Int = 2,
        channel: String = "stable",
        artifactContents: Data,
        timestampExpires: String? = nil,
        snapshotExpires: String? = nil,
        targetsExpires: String? = nil
    ) throws -> BuiltRepository {
        let fm = FileManager.default
        let metadataDir = directory.appendingPathComponent("metadata")
        let targetsDir = directory.appendingPathComponent("targets")
        try fm.createDirectory(at: metadataDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: targetsDir, withIntermediateDirectories: true)

        // 1. Root + keys
        let rootBundle = try TestFixtures.makeRoot()
        try rootBundle.rawSignedBytes.write(to: metadataDir.appendingPathComponent("1.root.json"))

        // 2. Real artifact hash + length
        let artifactHash = TestFixtures.sha256Base64(artifactContents)
        let artifactSize = artifactContents.count
        let targetPath = "targets/\(productID)-\(bundleVersion)-arm64.aar"
        let artifactURL = directory.appendingPathComponent(targetPath)
        try artifactContents.write(to: artifactURL)

        // 3. Targets metadata (signed by targets key)
        let custom = LumenTargetCustom(
            productID: productID,
            bundleIdentifier: productID,
            bundleVersion: bundleVersion,
            shortVersion: "\(bundleVersion).0.0",
            minimumSystemVersion: "13.0",
            architectures: ["arm64"],
            channel: channel,
            archiveFormat: "apple-archive",
            bundleManifestSHA256: artifactHash,
            releaseNotesTarget: nil,
            critical: false,
            rollout: nil
        )
        let targetInfo = TUFTargetInfo(
            length: artifactSize,
            hashes: ["sha256": artifactHash],
            custom: custom
        )
        let targetsMeta = TUFTargetsMetadata(
            version: 1,
            expires: targetsExpires ?? ISO8601DateFormatter.lumen.string(from: Date().addingTimeInterval(90 * 86400)),
            targets: [targetPath: targetInfo],
            delegations: nil
        )
        let targetsBytes = try signedEnvelope(targetsMeta, key: rootBundle.targetsKey)
        try targetsBytes.write(to: metadataDir.appendingPathComponent("1.targets.json"))

        // 4. Snapshot metadata (signed by snapshot key), referencing targets
        let snapshotMeta = TUFSnapshotMetadata(
            version: 1,
            expires: snapshotExpires ?? ISO8601DateFormatter.lumen.string(from: Date().addingTimeInterval(7 * 86400)),
            meta: [
                "targets.json": TUFSnapshotMetadata.MetaEntry(
                    version: 1,
                    length: targetsBytes.count,
                    hashes: ["sha256": TestFixtures.sha256Base64(targetsBytes)]
                )
            ]
        )
        let snapshotBytes = try signedEnvelope(snapshotMeta, key: rootBundle.snapshotKey)
        try snapshotBytes.write(to: metadataDir.appendingPathComponent("1.snapshot.json"))

        // 5. Timestamp metadata (signed by timestamp key), referencing snapshot
        let timestampMeta = TUFTimestampMetadata(
            version: 1,
            expires: timestampExpires ?? ISO8601DateFormatter.lumen.string(from: Date().addingTimeInterval(86400)),
            meta: [
                "snapshot.json": TUFTimestampMetadata.MetaEntry(
                    version: 1,
                    length: snapshotBytes.count,
                    hashes: ["sha256": TestFixtures.sha256Base64(snapshotBytes)]
                )
            ]
        )
        let timestampBytes = try signedEnvelope(timestampMeta, key: rootBundle.timestampKey)
        try timestampBytes.write(to: metadataDir.appendingPathComponent("timestamp.json"))

        return BuiltRepository(
            directory: directory,
            rootBundle: rootBundle,
            productID: productID,
            channel: channel,
            bundleVersion: bundleVersion,
            targetPath: targetPath,
            artifactURL: artifactURL,
            artifactHash: artifactHash,
            artifactSize: artifactSize
        )
    }

    /// Sign a metadata payload into a TUF signed envelope (signatures + signed).
    private static func signedEnvelope<T: Encodable>(_ metadata: T, key: TestFixtures.TestKey) throws -> Data {
        let canonical = try MetadataDecoder.canonicalizeForSigning(metadata)
        let sig = try TestFixtures.sign(canonical, with: key)
        let envelope: [String: Any] = [
            "signatures": [["keyid": key.keyID, "sig": Base64URL.encode(sig)]],
            "signed": try JSONSerialization.jsonObject(with: canonical, options: [])
        ]
        return try CanonicalJSON.encode(envelope)
    }
}
