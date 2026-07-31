import ArgumentParser
import Foundation
import LumenCore
import LumenTUF

struct PublishCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish",
        abstract: "Publish repository metadata to a static hosting destination"
    )

    @Option(name: .long, help: "Path to the local repository directory")
    var repository: String = "./repository"

    @Option(name: .long, help: "Destination: local path, s3://bucket, r2://bucket, or github://owner/repo")
    var destination: String

    func run() throws {
        let repoPath = NSString(string: repository).expandingTildeInPath
        let fm = FileManager.default

        guard fm.fileExists(atPath: repoPath) else {
            throw ValidationError("Repository not found: \(repoPath)")
        }

        let metadataDir = "\(repoPath)/metadata"
        let targetsDir = "\(repoPath)/targets"

        guard fm.fileExists(atPath: metadataDir) else {
            throw ValidationError("Repository metadata directory not found: \(metadataDir)")
        }

        print("Publishing repository from \(repoPath)")
        print("  Destination: \(destination)")

        if destination.hasPrefix("s3://") || destination.hasPrefix("r2://") {
            print("")
            print("⚠️  S3/R2 publishing requires the AWS CLI or wrangler.")
            print("    Use: aws s3 sync \(repoPath) \(destination)")
            print("    Or:  wrangler r2 object put ...")
            print("")
            print("    Publishing order (for atomicity):")
            print("    1. Upload targets/ (immutable artifacts)")
            print("    2. Upload metadata/delegated/ (if any)")
            print("    3. Upload metadata/N.targets.json")
            print("    4. Upload metadata/N.snapshot.json")
            print("    5. Upload metadata/timestamp.json LAST")
            throw ExitCode.success
        }

        if destination.hasPrefix("github://") {
            print("")
            print("⚠️  GitHub Releases publishing requires the gh CLI.")
            print("    Use: gh release create <tag> --repo <owner/repo> <artifacts>")
            throw ExitCode.success
        }

        // Local directory publish (copy)
        let destPath = NSString(string: destination).expandingTildeInPath
        try fm.createDirectory(atPath: destPath, withIntermediateDirectories: true)

        // Copy in the correct order for atomicity
        let itemsToCopy = ["targets", "metadata"]
        for item in itemsToCopy {
            let src = "\(repoPath)/\(item)"
            let dst = "\(destPath)/\(item)"
            if fm.fileExists(atPath: dst) {
                try fm.removeItem(atPath: dst)
            }
            try fm.copyItem(atPath: src, toPath: dst)
        }

        print("")
        print("Published to \(destPath)")
        print("  metadata/timestamp.json")
        print("  metadata/1.snapshot.json")
        print("  metadata/1.targets.json")

        // List targets
        if let targets = try? fm.contentsOfDirectory(atPath: targetsDir) {
            for t in targets.sorted() {
                print("  targets/\(t)")
            }
        }
    }
}
