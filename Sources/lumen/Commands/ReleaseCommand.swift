import ArgumentParser
import Foundation
import LumenCore
import LumenCrypto
import LumenTUF
import Crypto

struct ReleaseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Create signed release metadata (targets, snapshot, timestamp)",
        subcommands: [Create.self]
    )

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a new release with signed TUF metadata"
        )

        @Option(name: .long, help: "Path to the archive artifact (.aar)")
        var artifact: String

        @Option(name: .long, help: "Path to the bundle manifest JSON")
        var manifest: String

        @Option(name: .long, help: "Path to release notes markdown file")
        var notes: String?

        @Option(name: .long, help: "Path to targets private key file")
        var targetsKey: String

        @Option(name: .long, help: "Path to snapshot private key file")
        var snapshotKey: String

        @Option(name: .long, help: "Path to timestamp private key file")
        var timestampKey: String

        @Option(name: .long, help: "Product ID (bundle identifier)")
        var productID: String

        @Option(name: .long, help: "Release channel")
        var channel: String = "stable"

        @Option(name: .long, help: "Output directory for metadata")
        var output: String = "./repository/metadata"

        func run() throws {
            let fm = FileManager.default
            let artifactPath = NSString(string: artifact).expandingTildeInPath
            let manifestPath = NSString(string: manifest).expandingTildeInPath

            guard fm.fileExists(atPath: artifactPath) else {
                throw ValidationError("Artifact not found: \(artifactPath)")
            }
            guard fm.fileExists(atPath: manifestPath) else {
                throw ValidationError("Manifest not found: \(manifestPath)")
            }

            let artifactData = try Data(contentsOf: URL(fileURLWithPath: artifactPath))
            let artifactHash = Base64URL.encode(LumenSHA256.hash(data: artifactData))
            let manifestData = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
            let manifestHash = Base64URL.encode(LumenSHA256.hash(data: manifestData))

            // Load manifest to get version info
            let bundleManifest = try JSONDecoder().decode(BundleManifest.self, from: manifestData)

            // Load signing keys
            let targetsPrivData = try loadPrivateKey(targetsKey)
            let targetsSigningKey = try Curve25519.Signing.PrivateKey(rawRepresentation: targetsPrivData)
            let targetsKeyID = SignatureVerifier.keyID(forPublicKey: targetsSigningKey.publicKey.rawRepresentation)

            let snapshotPrivData = try loadPrivateKey(snapshotKey)
            let snapshotSigningKey = try Curve25519.Signing.PrivateKey(rawRepresentation: snapshotPrivData)
            let snapshotKeyID = SignatureVerifier.keyID(forPublicKey: snapshotSigningKey.publicKey.rawRepresentation)

            let timestampPrivData = try loadPrivateKey(timestampKey)
            let timestampSigningKey = try Curve25519.Signing.PrivateKey(rawRepresentation: timestampPrivData)
            let timestampKeyID = SignatureVerifier.keyID(forPublicKey: timestampSigningKey.publicKey.rawRepresentation)

            let outputDir = NSString(string: output).expandingTildeInPath
            try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

            // Detect architecture from artifact name
            let artifactName = URL(fileURLWithPath: artifactPath).lastPathComponent
            let arch = artifactName.contains("arm64") ? "arm64" : artifactName.contains("x86_64") ? "x86_64" : "universal"

            // Build target path
            let targetPath = "sha256.\(artifactHash.prefix(16)).\(productID)-\(bundleManifest.bundleVersion)-\(arch).aar"

            // Copy artifact to targets directory
            let targetsDir = "\(outputDir)/../targets"
            try fm.createDirectory(atPath: targetsDir, withIntermediateDirectories: true)
            let targetDest = "\(targetsDir)/\(targetPath)"
            try fm.copyItem(atPath: artifactPath, toPath: targetDest)

            // Build custom metadata
            let custom = LumenTargetCustom(
                productID: productID,
                bundleIdentifier: bundleManifest.bundleIdentifier,
                bundleVersion: bundleManifest.bundleVersion,
                shortVersion: "\(bundleManifest.bundleVersion)",
                minimumSystemVersion: "13.0",
                architectures: [arch],
                channel: channel,
                archiveFormat: "apple-archive",
                bundleManifestSHA256: manifestHash,
                releaseNotesTarget: notes != nil ? "notes/\(bundleManifest.bundleVersion).md" : nil,
                critical: false,
                rollout: nil
            )

            // === Create targets metadata ===
            let targetsMeta = TUFTargetsMetadata(
                version: 1,
                expires: ISO8601DateFormatter.lumen.string(from: Date().addingTimeInterval(90 * 86400)),
                targets: [targetPath: TUFTargetInfo(length: artifactData.count, hashes: ["sha256": artifactHash], custom: custom)],
                delegations: nil
            )
            let targetsCanonical = try MetadataDecoder.canonicalizeForSigning(targetsMeta)
            let targetsSig = try targetsSigningKey.signature(for: targetsCanonical)
            let targetsEnvelope: [String: Any] = [
                "signatures": [["keyid": targetsKeyID, "sig": Base64URL.encode(targetsSig)]],
                "signed": try JSONSerialization.jsonObject(with: targetsCanonical, options: [])
            ]
            let targetsData = try CanonicalJSON.encode(targetsEnvelope)
            let targetsOutPath = "\(outputDir)/1.targets.json"
            try targetsData.write(to: URL(fileURLWithPath: targetsOutPath))

            // === Create snapshot metadata ===
            let snapshotMeta = TUFSnapshotMetadata(
                version: 1,
                expires: ISO8601DateFormatter.lumen.string(from: Date().addingTimeInterval(7 * 86400)),
                meta: ["targets.json": TUFSnapshotMetadata.MetaEntry(
                    version: 1,
                    length: targetsData.count,
                    hashes: ["sha256": Base64URL.encode(LumenSHA256.hash(data: targetsData))]
                )]
            )
            let snapshotCanonical = try MetadataDecoder.canonicalizeForSigning(snapshotMeta)
            let snapshotSig = try snapshotSigningKey.signature(for: snapshotCanonical)
            let snapshotEnvelope: [String: Any] = [
                "signatures": [["keyid": snapshotKeyID, "sig": Base64URL.encode(snapshotSig)]],
                "signed": try JSONSerialization.jsonObject(with: snapshotCanonical, options: [])
            ]
            let snapshotData = try CanonicalJSON.encode(snapshotEnvelope)
            let snapshotOutPath = "\(outputDir)/1.snapshot.json"
            try snapshotData.write(to: URL(fileURLWithPath: snapshotOutPath))

            // === Create timestamp metadata ===
            let timestampMeta = TUFTimestampMetadata(
                version: 1,
                expires: ISO8601DateFormatter.lumen.string(from: Date().addingTimeInterval(86400)),
                meta: ["snapshot.json": TUFTimestampMetadata.MetaEntry(
                    version: 1,
                    length: snapshotData.count,
                    hashes: ["sha256": Base64URL.encode(LumenSHA256.hash(data: snapshotData))]
                )]
            )
            let timestampCanonical = try MetadataDecoder.canonicalizeForSigning(timestampMeta)
            let timestampSig = try timestampSigningKey.signature(for: timestampCanonical)
            let timestampEnvelope: [String: Any] = [
                "signatures": [["keyid": timestampKeyID, "sig": Base64URL.encode(timestampSig)]],
                "signed": try JSONSerialization.jsonObject(with: timestampCanonical, options: [])
            ]
            let timestampData = try CanonicalJSON.encode(timestampEnvelope)
            let timestampOutPath = "\(outputDir)/timestamp.json"
            try timestampData.write(to: URL(fileURLWithPath: timestampOutPath))

            // Copy release notes if provided
            if let notesPath = notes {
                let notesDir = "\(outputDir)/../notes"
                try fm.createDirectory(atPath: notesDir, withIntermediateDirectories: true)
                let expandedNotes = NSString(string: notesPath).expandingTildeInPath
                try fm.copyItem(atPath: expandedNotes, toPath: "\(notesDir)/\(bundleManifest.bundleVersion).md")
            }

            print("Release created:")
            print("  Target:     \(targetPath)")
            print("  Targets:    \(targetsOutPath)")
            print("  Snapshot:   \(snapshotOutPath)")
            print("  Timestamp:  \(timestampOutPath)")
            print("  Artifact:   \(targetDest)")
            print("")
            print("Next: lumen publish --repository ./repository")
        }

        private func loadPrivateKey(_ path: String) throws -> Data {
            let expanded = NSString(string: path).expandingTildeInPath
            let b64 = try String(contentsOfFile: expanded, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            return try Base64URL.decode(b64)
        }
    }
}
