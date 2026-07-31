import ArgumentParser
import Foundation
import LumenCore
import LumenCrypto
import LumenTUF
import Crypto

struct RootCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "root",
        abstract: "Create and rotate TUF root metadata",
        subcommands: [Create.self, Rotate.self]
    )

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create self-signed root metadata from key files"
        )

        @Option(name: .long, help: "Path to root private key file")
        var rootKey: String

        @Option(name: .long, help: "Path to targets public key file")
        var targetsKey: String

        @Option(name: .long, help: "Path to snapshot public key file")
        var snapshotKey: String

        @Option(name: .long, help: "Path to timestamp public key file")
        var timestampKey: String

        @Option(name: .long, help: "Root key threshold (default: 1)")
        var threshold: Int = 1

        @Option(name: .long, help: "Expiration in days from now (default: 365)")
        var expiresDays: Int = 365

        @Option(name: .long, help: "Output file path")
        var output: String = "1.root.json"

        func run() throws {
            let rootPrivB64 = try String(contentsOfFile: NSString(string: rootKey).expandingTildeInPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            let rootPrivData = try Base64URL.decode(rootPrivB64)
            let rootSigningKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rootPrivData)
            let rootPubData = rootSigningKey.publicKey.rawRepresentation
            let rootKeyID = SignatureVerifier.keyID(forPublicKey: rootPubData)

            let targetsPubData = try loadPublicKey(targetsKey)
            let targetsKeyID = SignatureVerifier.keyID(forPublicKey: targetsPubData)

            let snapshotPubData = try loadPublicKey(snapshotKey)
            let snapshotKeyID = SignatureVerifier.keyID(forPublicKey: snapshotPubData)

            let timestampPubData = try loadPublicKey(timestampKey)
            let timestampKeyID = SignatureVerifier.keyID(forPublicKey: timestampPubData)

            let keys: [String: TUFKey] = [
                rootKeyID: TUFKey(keytype: "ed25519", scheme: "ed25519", publicKey: Base64URL.encode(rootPubData)),
                targetsKeyID: TUFKey(keytype: "ed25519", scheme: "ed25519", publicKey: Base64URL.encode(targetsPubData)),
                snapshotKeyID: TUFKey(keytype: "ed25519", scheme: "ed25519", publicKey: Base64URL.encode(snapshotPubData)),
                timestampKeyID: TUFKey(keytype: "ed25519", scheme: "ed25519", publicKey: Base64URL.encode(timestampPubData)),
            ]

            let roles = TUFRootMetadata.Roles(
                root: TUFRoleDefinition(keyids: [rootKeyID], threshold: threshold),
                snapshot: TUFRoleDefinition(keyids: [snapshotKeyID], threshold: 1),
                targets: TUFRoleDefinition(keyids: [targetsKeyID], threshold: 1),
                timestamp: TUFRoleDefinition(keyids: [timestampKeyID], threshold: 1)
            )

            let expires = ISO8601DateFormatter.lumen.string(
                from: Date().addingTimeInterval(TimeInterval(expiresDays * 86400))
            )

            let rootMeta = TUFRootMetadata(version: 1, expires: expires, keys: keys, roles: roles)

            let signedCanonical = try MetadataDecoder.canonicalizeForSigning(rootMeta)
            let signature = try rootSigningKey.signature(for: signedCanonical)

            let envelope: [String: Any] = [
                "signatures": [["keyid": rootKeyID, "sig": Base64URL.encode(signature)]],
                "signed": try JSONSerialization.jsonObject(with: signedCanonical, options: [])
            ]
            let envelopeData = try CanonicalJSON.encode(envelope)

            let outputPath = NSString(string: output).expandingTildeInPath
            try envelopeData.write(to: URL(fileURLWithPath: outputPath))

            print("Created root metadata: \(outputPath)")
            print("  Version:    1")
            print("  Expires:    \(expires)")
            print("  Root key:   \(rootKeyID.prefix(16))...")
            print("  Targets:    \(targetsKeyID.prefix(16))...")
            print("  Snapshot:   \(snapshotKeyID.prefix(16))...")
            print("  Timestamp:  \(timestampKeyID.prefix(16))...")
        }

        private func loadPublicKey(_ path: String) throws -> Data {
            let expanded = NSString(string: path).expandingTildeInPath
            let b64 = try String(contentsOfFile: expanded, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            return try Base64URL.decode(b64)
        }
    }

    struct Rotate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "rotate",
            abstract: "Rotate root metadata to a new version"
        )

        @Option(name: .long, help: "Path to current root metadata")
        var currentRoot: String

        @Option(name: .long, help: "Path to OLD root private key (for signing)")
        var oldRootKey: String

        @Option(name: .long, help: "Path to NEW root private key")
        var newRootKey: String

        @Option(name: .long, help: "Output file path")
        var output: String

        func run() throws {
            print("Root rotation is a sensitive operation.")
            print("Ensure you have the old root key and the new root key available.")
            print("")
            print("Current root: \(currentRoot)")
            print("Old root key: \(oldRootKey)")
            print("New root key: \(newRootKey)")
            print("")
            print("⚠️  Root rotation requires signing with BOTH old and new root keys.")
            print("    See Documentation/KEY_MANAGEMENT.md for the full procedure.")
            throw ExitCode.failure
        }
    }
}
