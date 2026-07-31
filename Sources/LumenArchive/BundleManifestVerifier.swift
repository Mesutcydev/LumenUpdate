import Foundation
import LumenCore

public struct BundleManifestEntry: Codable, Equatable, Sendable {
    public let path: String
    public let type: String
    public let mode: Int
    public let size: Int
    public let sha256: String

    public init(path: String, type: String, mode: Int, size: Int, sha256: String) {
        self.path = path
        self.type = type
        self.mode = mode
        self.size = size
        self.sha256 = sha256
    }
}

public struct BundleManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let bundleIdentifier: String
    public let bundleVersion: Int
    public let entries: [BundleManifestEntry]

    public init(schemaVersion: Int, bundleIdentifier: String, bundleVersion: Int, entries: [BundleManifestEntry]) {
        self.schemaVersion = schemaVersion
        self.bundleIdentifier = bundleIdentifier
        self.bundleVersion = bundleVersion
        self.entries = entries
    }
}

public enum BundleManifestVerifier {

    public static func verify(
        extractedDirectory: URL,
        manifest: BundleManifest
    ) throws {
        let fm = FileManager.default
        var manifestPaths = Set<String>()

        for entry in manifest.entries {
            manifestPaths.insert(entry.path)

            let filePath = extractedDirectory.appendingPathComponent(entry.path)

            guard fm.fileExists(atPath: filePath.path) else {
                throw LumenError.bundleManifestMismatch
            }

            let attributes = try fm.attributesOfItem(atPath: filePath.path)
            let fileSize = attributes[.size] as? Int ?? 0

            guard fileSize == entry.size else {
                throw LumenError.bundleManifestMismatch
            }

            let fileData = try Data(contentsOf: filePath)
            let fileHash = Base64URL.encode(LumenSHA256.hash(data: fileData))

            guard fileHash == entry.sha256 else {
                throw LumenError.bundleManifestMismatch
            }
        }

        // Check for extra files not in the manifest
        guard let enumerator = fm.enumerator(at: extractedDirectory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw LumenError.bundleManifestMismatch
        }

        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.path.replacingOccurrences(of: extractedDirectory.path + "/", with: "")
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }

            guard manifestPaths.contains(relativePath) else {
                throw LumenError.bundleManifestMismatch
            }
        }
    }

    public static func loadManifest(from data: Data) throws -> BundleManifest {
        do {
            return try JSONDecoder().decode(BundleManifest.self, from: data)
        } catch {
            throw LumenError.archiveInvalid("Cannot decode bundle manifest: \(error)")
        }
    }

    public static func verifyManifestHash(_ data: Data, expectedHash: String) throws {
        let actualHash = Base64URL.encode(LumenSHA256.hash(data: data))
        guard actualHash == expectedHash else {
            throw LumenError.bundleManifestMismatch
        }
    }
}
