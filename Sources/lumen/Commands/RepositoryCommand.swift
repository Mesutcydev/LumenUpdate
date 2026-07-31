import ArgumentParser
import Foundation
import LumenCore
import LumenCrypto
import LumenTUF

struct RepositoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "repository",
        abstract: "Verify and inspect update repositories",
        subcommands: [Verify.self]
    )

    struct Verify: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "verify",
            abstract: "Verify a repository's metadata using the client verification library"
        )

        @Argument(help: "Repository URL or local path")
        var repository: String

        @Option(name: .long, help: "Path to trusted root metadata (1.root.json)")
        var root: String

        @Option(name: .long, help: "Product ID to verify")
        var productID: String

        @Option(name: .long, help: "Channel to verify")
        var channel: String = "stable"

        func run() throws {
            let fm = FileManager.default
            let rootPath = NSString(string: root).expandingTildeInPath

            guard fm.fileExists(atPath: rootPath) else {
                throw ValidationError("Root metadata not found: \(rootPath)")
            }

            print("Verifying repository: \(repository)")
            print("  Root:      \(rootPath)")
            print("  Product:   \(productID)")
            print("  Channel:   \(channel)")
            print("")

            // Load and bootstrap root
            let rootData = try Data(contentsOf: URL(fileURLWithPath: rootPath))
            let trustRoot = try TrustRootBootstrap.bootstrap(from: rootData)
            print("✓ Root metadata valid (version \(trustRoot.version))")

            // Determine base path
            let basePath: String
            if repository.hasPrefix("http://") || repository.hasPrefix("https://") {
                print("⚠️  HTTP repository verification requires the downloader (Phase 3).")
                print("    For now, use a local repository path.")
                throw ExitCode.failure
            } else {
                basePath = NSString(string: repository).expandingTildeInPath
            }

            let metadataDir = "\(basePath)/metadata"

            // Load timestamp
            let timestampPath = "\(metadataDir)/timestamp.json"
            guard fm.fileExists(atPath: timestampPath) else {
                throw ValidationError("timestamp.json not found at \(timestampPath)")
            }
            let timestampData = try Data(contentsOf: URL(fileURLWithPath: timestampPath))
            print("✓ timestamp.json loaded (\(timestampData.count) bytes)")

            // Parse timestamp to find snapshot version
            let timestampDecoded = try MetadataDecoder.decodeSignedTimestamp(timestampData)
            guard let snapshotMeta = timestampDecoded.metadata.signed.meta["snapshot.json"] else {
                throw ValidationError("timestamp.json does not reference snapshot.json")
            }

            // Load snapshot
            let snapshotPath = "\(metadataDir)/\(snapshotMeta.version).snapshot.json"
            guard fm.fileExists(atPath: snapshotPath) else {
                throw ValidationError("Snapshot not found: \(snapshotPath)")
            }
            let snapshotData = try Data(contentsOf: URL(fileURLWithPath: snapshotPath))
            print("✓ \(snapshotMeta.version).snapshot.json loaded (\(snapshotData.count) bytes)")

            // Parse snapshot to find targets version
            let snapshotDecoded = try MetadataDecoder.decodeSignedSnapshot(snapshotData)
            guard let targetsMeta = snapshotDecoded.metadata.signed.meta["targets.json"] else {
                throw ValidationError("snapshot.json does not reference targets.json")
            }

            // Load targets
            let targetsPath = "\(metadataDir)/\(targetsMeta.version).targets.json"
            guard fm.fileExists(atPath: targetsPath) else {
                throw ValidationError("Targets not found: \(targetsPath)")
            }
            let targetsData = try Data(contentsOf: URL(fileURLWithPath: targetsPath))
            print("✓ \(targetsMeta.version).targets.json loaded (\(targetsData.count) bytes)")

            // Run full verification
            let host = HostProfile(
                productID: productID,
                bundleIdentifier: productID,
                currentBundleVersion: 0,
                architecture: "arm64",
                macOSVersion: "14.0",
                channel: channel
            )

            let inputs = VerificationInputs(
                trustRoot: trustRoot,
                timestampData: timestampData,
                snapshotData: snapshotData,
                targetsData: targetsData,
                host: host
            )

            let result = try TUFVerifier.verify(inputs: inputs)
            print("")
            print("✓ Repository verification PASSED")
            print("  Resolved target: \(result.resolvedTarget.path)")
            print("  Bundle version:  \(result.resolvedTarget.custom.bundleVersion)")
            print("  Short version:   \(result.resolvedTarget.custom.shortVersion)")
            print("  Architecture:    \(result.resolvedTarget.custom.architectures.joined(separator: ", "))")
        }
    }
}
