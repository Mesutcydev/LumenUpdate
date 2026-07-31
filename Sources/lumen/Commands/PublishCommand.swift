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

    @Option(name: .long, help: "Destination: local path, s3://bucket/prefix, r2://bucket/prefix, or github://owner/repo")
    var destination: String

    @Option(name: .long, help: "Release tag (github:// destination only)")
    var tag: String = "latest"

    private var fm: FileManager { FileManager.default }

    func run() throws {
        let repoPath = NSString(string: repository).expandingTildeInPath
        guard fm.fileExists(atPath: repoPath) else {
            throw ValidationError("Repository not found: \(repoPath)")
        }
        let metadataDir = "\(repoPath)/metadata"
        guard fm.fileExists(atPath: metadataDir) else {
            throw ValidationError("Repository metadata directory not found: \(metadataDir)")
        }

        print("Publishing repository from \(repoPath)")
        print("  Destination: \(destination)")

        if destination.hasPrefix("s3://") || destination.hasPrefix("r2://") {
            try publishS3Compatible(repoPath: repoPath)
        } else if destination.hasPrefix("github://") {
            try publishGitHub(repoPath: repoPath)
        } else {
            try publishLocal(repoPath: repoPath)
        }
    }

    // MARK: - Local directory

    private func publishLocal(repoPath: String) throws {
        let destPath = NSString(string: destination).expandingTildeInPath
        try fm.createDirectory(atPath: destPath, withIntermediateDirectories: true)

        // Copy in atomicity order: immutable targets first, metadata after.
        for item in ["targets", "metadata"] {
            let src = "\(repoPath)/\(item)"
            guard fm.fileExists(atPath: src) else { continue }
            let dst = "\(destPath)/\(item)"
            if fm.fileExists(atPath: dst) { try fm.removeItem(atPath: dst) }
            try fm.copyItem(atPath: src, toPath: dst)
        }

        print("")
        print("Published to \(destPath)")
        try listPublished(repoPath: repoPath)
    }

    // MARK: - S3 / R2 (S3-compatible)

    private func publishS3Compatible(repoPath: String) throws {
        try requireCLI("aws", hint: "Install the AWS CLI: https://aws.amazon.com/cli/  (R2 works via AWS_ENDPOINT_URL)")

        // r2://bucket → s3://bucket; R2 is S3-compatible (set AWS_ENDPOINT_URL to
        // https://<account-id>.r2.cloudflarestorage.com).
        let dest = destination.hasPrefix("r2://")
            ? "s3://" + destination.dropFirst("r2://".count)
            : destination

        // 1. Immutable target artifacts (order irrelevant).
        let targetsDir = "\(repoPath)/targets"
        if fm.fileExists(atPath: targetsDir) {
            try runShell("aws", ["s3", "sync", targetsDir, "\(dest)/targets/", "--no-progress"])
        }

        // 2. Delegated metadata (if any).
        let delegatedDir = "\(repoPath)/metadata/delegated"
        if fm.fileExists(atPath: delegatedDir) {
            try runShell("aws", ["s3", "sync", delegatedDir, "\(dest)/metadata/delegated/", "--no-progress"])
        }

        // 3. Versioned metadata, then 4. timestamp.json LAST (atomicity).
        let metadataFiles = try orderedMetadataFiles(repoPath: repoPath)
        for file in metadataFiles {
            try runShell("aws", ["s3", "cp", "\(repoPath)/metadata/\(file)", "\(dest)/metadata/\(file)", "--no-progress"])
        }

        print("")
        print("Published to \(dest)")
        try listPublished(repoPath: repoPath)
    }

    // MARK: - GitHub Releases

    private func publishGitHub(repoPath: String) throws {
        try requireCLI("gh", hint: "Install the GitHub CLI: https://cli.github.com/")

        let repo = String(destination.dropFirst("github://".count))
        guard repo.contains("/") else {
            throw ValidationError("github:// destination must be github://owner/repo")
        }

        // Collect artifacts + metadata as release assets.
        var assets: [String] = []
        let targetsDir = "\(repoPath)/targets"
        if let targets = try? fm.contentsOfDirectory(atPath: targetsDir) {
            assets += targets.map { "\(targetsDir)/\($0)" }
        }
        let metadataFiles = try orderedMetadataFiles(repoPath: repoPath)
        assets += metadataFiles.map { "\(repoPath)/metadata/\($0)" }

        // Create-or-update the release, uploading the assets.
        var args = ["release", "create", tag, "--repo", repo, "--title", "Lumen update \(tag)", "--notes", "Published by lumen publish"]
        args.append(contentsOf: assets)
        do {
            try runShell("gh", args)
        } catch {
            // Release may already exist — upload assets to it instead.
            print("  Release '\(tag)' exists; uploading assets…")
            try runShell("gh", ["release", "upload", tag, "--repo", repo, "--clobber"] + assets)
        }

        print("")
        print("Published to https://github.com/\(repo)/releases/tag/\(tag)")
    }

    // MARK: - Helpers

    /// Metadata files in atomicity order: targets/snapshot first, timestamp LAST.
    private func orderedMetadataFiles(repoPath: String) throws -> [String] {
        let metadataDir = "\(repoPath)/metadata"
        let all = try fm.contentsOfDirectory(atPath: metadataDir)
            .filter { $0.hasSuffix(".json") }
        // timestamp.json must be uploaded last so clients never see a fresh
        // timestamp pointing at metadata that isn't fully uploaded yet.
        return all.sorted { a, b in
            if a == "timestamp.json" { return false }
            if b == "timestamp.json" { return true }
            return a < b
        }
    }

    private func listPublished(repoPath: String) throws {
        let metadataDir = "\(repoPath)/metadata"
        if let meta = try? fm.contentsOfDirectory(atPath: metadataDir) {
            for m in meta.filter({ $0.hasSuffix(".json") }).sorted() {
                print("  metadata/\(m)")
            }
        }
        if let targets = try? fm.contentsOfDirectory(atPath: "\(repoPath)/targets") {
            for t in targets.sorted() {
                print("  targets/\(t)")
            }
        }
    }

    private func requireCLI(_ name: String, hint: String) throws {
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        check.arguments = [name]
        check.standardOutput = Pipe()
        check.standardError = Pipe()
        try check.run()
        check.waitUntilExit()
        guard check.terminationStatus == 0 else {
            throw ValidationError("'\(name)' is required for this destination but was not found. \(hint)")
        }
    }

    @discardableResult
    private func runShell(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [launchPath] + arguments
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw ValidationError("\(launchPath) failed (exit \(process.terminationStatus)): \(output)")
        }
        return output
    }
}
