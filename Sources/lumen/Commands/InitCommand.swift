import ArgumentParser
import Foundation

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize a new Lumen update repository"
    )

    @Option(name: .long, help: "Product ID (bundle identifier)")
    var productID: String

    @Option(name: .long, help: "Output directory for the repository")
    var output: String = "./UpdateRepository"

    func run() throws {
        let fm = FileManager.default
        let outputPath = NSString(string: output).expandingTildeInPath

        guard !fm.fileExists(atPath: outputPath) else {
            throw ValidationError("Directory already exists: \(outputPath)")
        }

        try fm.createDirectory(atPath: "\(outputPath)/metadata/delegated", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: "\(outputPath)/targets", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: "\(outputPath)/notes", withIntermediateDirectories: true)

        let config = """
        {
          "productID": "\(productID)",
          "channels": ["stable", "beta", "nightly"],
          "archiveFormat": "apple-archive",
          "minimumSystemVersion": "13.0"
        }
        """
        try config.write(toFile: "\(outputPath)/lumen.json", atomically: true, encoding: .utf8)

        print("Initialized Lumen repository at \(outputPath)")
        print("")
        print("  \(outputPath)/")
        print("  ├── lumen.json          # Repository configuration")
        print("  ├── metadata/")
        print("  │   └── delegated/      # Per-channel delegated targets")
        print("  ├── targets/            # Update archives (.aar)")
        print("  └── notes/              # Release notes")
        print("")
        print("Next steps:")
        print("  1. lumen key generate --role root")
        print("  2. lumen key generate --role targets")
        print("  3. lumen key generate --role snapshot")
        print("  4. lumen key generate --role timestamp")
        print("  5. lumen root create --root-key <root.key> --targets-key <targets.pub> ...")
        print("  6. lumen package ./MyApp.app")
        print("  7. lumen release create --artifact <archive> --manifest <manifest> ...")
        print("  8. lumen publish --repository \(outputPath) --destination <dest>")
    }
}
