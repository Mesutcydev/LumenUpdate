import ArgumentParser
import Foundation

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check the health of your Lumen setup"
    )

    func run() throws {
        print("Lumen Doctor")
        print("============")
        print("")

        var issues = 0

        // Check Swift
        let swiftCheck = try runCommand("/usr/bin/swift", ["--version"])
        if swiftCheck.contains("Swift version") {
            print("✓ Swift: \(swiftCheck.components(separatedBy: "\n").first ?? "unknown")")
        } else {
            print("✗ Swift not found")
            issues += 1
        }

        // Check key directory
        let keyDir = NSString(string: "~/.lumen/keys").expandingTildeInPath
        if FileManager.default.fileExists(atPath: keyDir) {
            let keys = (try? FileManager.default.contentsOfDirectory(atPath: keyDir))?.filter { $0.hasSuffix(".key") } ?? []
            print("✓ Key directory: \(keyDir) (\(keys.count) keys)")
        } else {
            print("○ Key directory not found: \(keyDir)")
            print("  Run 'lumen key generate' to create keys.")
        }

        // Check for repository
        if FileManager.default.fileExists(atPath: "./repository/metadata") {
            print("✓ Repository: ./repository")
        } else if FileManager.default.fileExists(atPath: "./UpdateRepository/metadata") {
            print("✓ Repository: ./UpdateRepository")
        } else {
            print("○ No repository found in current directory")
            print("  Run 'lumen init --product-id <id>' to create one.")
        }

        // Check macOS version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        print("✓ macOS: \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")

        if osVersion.majorVersion < 13 {
            print("✗ Lumen requires macOS 13.0 or later")
            issues += 1
        }

        print("")
        if issues == 0 {
            print("All checks passed. Ready to publish updates.")
        } else {
            print("\(issues) issue(s) found. Fix them before publishing.")
            throw ExitCode.failure
        }
    }

    private func runCommand(_ path: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
