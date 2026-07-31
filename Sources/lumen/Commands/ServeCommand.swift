import ArgumentParser
import Foundation

struct ServeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start a local HTTP server for development and testing"
    )

    @Option(name: .long, help: "Repository directory to serve")
    var repository: String = "./repository"

    @Option(name: .long, help: "Port to listen on")
    var port: Int = 8080

    func run() throws {
        let repoPath = NSString(string: repository).expandingTildeInPath
        let fm = FileManager.default

        guard fm.fileExists(atPath: repoPath) else {
            throw ValidationError("Repository not found: \(repoPath)")
        }

        print("Serving repository at http://localhost:\(port)")
        print("  Root: \(repoPath)")
        print("")
        print("  Metadata: http://localhost:\(port)/metadata/")
        print("  Targets:  http://localhost:\(port)/targets/")
        print("")
        print("Press Ctrl+C to stop.")

        // Use Python's http.server for simplicity
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "http.server", "\(port)", "--directory", repoPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()
    }
}
