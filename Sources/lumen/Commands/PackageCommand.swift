import ArgumentParser
import Foundation
import LumenCore
import LumenTUF

struct PackageCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "package",
        abstract: "Package a .app bundle into an update archive with manifest"
    )

    @Argument(help: "Path to the .app bundle to package")
    var appPath: String

    @Option(name: .long, help: "Release channel: stable, beta, nightly")
    var channel: String = "stable"

    @Option(name: .long, help: "Output directory for the archive")
    var output: String = "."

    func run() throws {
        let expandedApp = NSString(string: appPath).expandingTildeInPath
        let fm = FileManager.default

        guard fm.fileExists(atPath: expandedApp) else {
            throw ValidationError("App bundle not found: \(expandedApp)")
        }

        guard expandedApp.hasSuffix(".app") else {
            throw ValidationError("Expected a .app bundle, got: \(expandedApp)")
        }

        let appURL = URL(fileURLWithPath: expandedApp)
        let appName = appURL.deletingPathExtension().lastPathComponent

        // Read Info.plist for bundle metadata
        let infoPlistPath = appURL.appendingPathComponent("Contents/Info.plist")
        guard let infoDict = NSDictionary(contentsOf: infoPlistPath) as? [String: Any] else {
            throw ValidationError("Cannot read Info.plist at \(infoPlistPath.path)")
        }

        let bundleID = infoDict["CFBundleIdentifier"] as? String ?? "unknown"
        let bundleVersion = infoDict["CFBundleVersion"] as? String ?? "0"
        let shortVersion = infoDict["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let minSystem = infoDict["LSMinimumSystemVersion"] as? String ?? "13.0"

        let bundleVersionInt = Int(bundleVersion) ?? 0

        print("Packaging \(appName):")
        print("  Bundle ID:      \(bundleID)")
        print("  Bundle Version: \(bundleVersion) (\(shortVersion))")
        print("  Min macOS:      \(minSystem)")
        print("  Channel:        \(channel)")

        // Detect architecture
        let machOPath = appURL.appendingPathComponent("Contents/MacOS/\(appName)")
        var architectures: [String] = []
        if fm.fileExists(atPath: machOPath.path) {
            // Simple arch detection via file command
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/file")
            process.arguments = ["-b", machOPath.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if output.contains("arm64") { architectures.append("arm64") }
            if output.contains("x86_64") { architectures.append("x86_64") }
        }
        if architectures.isEmpty { architectures = ["arm64"] }

        print("  Architectures:  \(architectures.joined(separator: ", "))")

        // Generate bundle manifest
        let manifest = try generateBundleManifest(appURL: appURL, bundleID: bundleID, bundleVersion: bundleVersionInt)
        let manifestData = try JSONEncoder().encode(manifest)
        let manifestHash = Base64URL.encode(LumenSHA256.hash(data: manifestData))

        let outputDir = NSString(string: output).expandingTildeInPath
        try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        let manifestPath = "\(outputDir)/\(appName)-\(shortVersion)-\(architectures.first ?? "universal").bundle-manifest.json"
        try manifestData.write(to: URL(fileURLWithPath: manifestPath))

        // Create archive using Apple Archive (tar for now, .aar in production)
        let archiveName = "\(appName)-\(shortVersion)-\(architectures.first ?? "universal").aar"
        let archivePath = "\(outputDir)/\(archiveName)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-czf", archivePath, "-C", appURL.deletingLastPathComponent().path, appURL.lastPathComponent]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ValidationError("Archive creation failed with exit code \(process.terminationStatus)")
        }

        let archiveData = try Data(contentsOf: URL(fileURLWithPath: archivePath))
        let archiveHash = Base64URL.encode(LumenSHA256.hash(data: archiveData))

        print("")
        print("Created:")
        print("  Archive:  \(archivePath) (\(archiveData.count) bytes)")
        print("  Manifest: \(manifestPath)")
        print("  SHA-256:  \(archiveHash)")
        print("  Manifest SHA-256: \(manifestHash)")
    }

    private func generateBundleManifest(appURL: URL, bundleID: String, bundleVersion: Int) throws -> BundleManifest {
        let fm = FileManager.default
        var entries: [BundleManifest.Entry] = []

        guard let enumerator = fm.enumerator(at: appURL, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
            throw ValidationError("Cannot enumerate app bundle")
        }

        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.path.replacingOccurrences(of: appURL.path + "/", with: "")
            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])

            guard resourceValues.isRegularFile == true else { continue }

            let data = try Data(contentsOf: fileURL)
            let hash = Base64URL.encode(LumenSHA256.hash(data: data))

            entries.append(BundleManifest.Entry(
                path: relativePath,
                type: "file",
                mode: 493,
                size: data.count,
                sha256: hash
            ))
        }

        return BundleManifest(
            schemaVersion: 1,
            bundleIdentifier: bundleID,
            bundleVersion: bundleVersion,
            entries: entries.sorted { $0.path < $1.path }
        )
    }
}

struct BundleManifest: Codable {
    let schemaVersion: Int
    let bundleIdentifier: String
    let bundleVersion: Int
    let entries: [Entry]

    struct Entry: Codable {
        let path: String
        let type: String
        let mode: Int
        let size: Int
        let sha256: String
    }
}
