import ArgumentParser
import Foundation
import LumenCore
import LumenCrypto
import LumenTUF
#if canImport(CryptoKit)
import CryptoKit
#endif
import Crypto

struct KeyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "key",
        abstract: "Generate and manage Ed25519 signing keys",
        subcommands: [Generate.self, List.self]
    )

    struct Generate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "generate",
            abstract: "Generate a new Ed25519 signing key"
        )

        @Option(name: .long, help: "Role for this key: root, targets, snapshot, timestamp")
        var role: String = "targets"

        @Option(name: .long, help: "Output directory for the key file")
        var output: String = "~/.lumen/keys"

        @Flag(name: .long, help: "Overwrite existing key file")
        var force: Bool = false

        func run() throws {
            let validRoles = ["root", "targets", "snapshot", "timestamp"]
            guard validRoles.contains(role) else {
                throw ValidationError("Invalid role '\(role)'. Must be one of: \(validRoles.joined(separator: ", "))")
            }

            let outputDir = NSString(string: output).expandingTildeInPath
            try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

            let privateKey = Curve25519.Signing.PrivateKey()
            let publicKey = privateKey.publicKey.rawRepresentation
            let keyID = SignatureVerifier.keyID(forPublicKey: publicKey)

            let keyFile = "\(outputDir)/\(role)-\(keyID.prefix(8)).key"
            let pubFile = "\(outputDir)/\(role)-\(keyID.prefix(8)).pub"

            if FileManager.default.fileExists(atPath: keyFile) && !force {
                throw ValidationError("Key file already exists: \(keyFile). Use --force to overwrite.")
            }

            // Write private key (raw 32 bytes, base64url-encoded)
            let privB64 = Base64URL.encode(privateKey.rawRepresentation)
            try privB64.write(toFile: keyFile, atomically: true, encoding: .utf8)

            // Set restrictive permissions on private key
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile)

            // Write public key
            let pubB64 = Base64URL.encode(publicKey)
            try pubB64.write(toFile: pubFile, atomically: true, encoding: .utf8)

            print("Generated \(role) key:")
            print("  Key ID:     \(keyID)")
            print("  Private key: \(keyFile)")
            print("  Public key:  \(pubFile)")
            print("")
            print("⚠️  Keep the private key secure. Never commit it to version control.")
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List available signing keys"
        )

        @Option(name: .long, help: "Key directory to scan")
        var directory: String = "~/.lumen/keys"

        func run() throws {
            let dir = NSString(string: directory).expandingTildeInPath
            let fm = FileManager.default

            guard fm.fileExists(atPath: dir) else {
                print("No key directory found at \(dir)")
                print("Run 'lumen key generate' to create keys.")
                return
            }

            let contents = try fm.contentsOfDirectory(atPath: dir)
            let keyFiles = contents.filter { $0.hasSuffix(".key") }.sorted()

            if keyFiles.isEmpty {
                print("No keys found in \(dir)")
                return
            }

            print("Keys in \(dir):")
            for file in keyFiles {
                let role = String(file.prefix(while: { $0 != "-" }))
                let keyIDPrefix = file
                    .replacingOccurrences(of: "\(role)-", with: "")
                    .replacingOccurrences(of: ".key", with: "")
                print("  \(role)  \(keyIDPrefix)  (\(file))")
            }
        }
    }
}
