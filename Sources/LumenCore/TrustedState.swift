// TrustedState.swift
// Persistent storage for the trusted root, version tracking, and blocked targets.

import Foundation

/// Persistent state structure. Schema version 1.
public struct TrustedState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let trustRoot: PersistedTrustRoot
    public let versions: [String: Int]
    public let blockedTargets: [BlockedTarget]
    public let lastBundleVersion: [String: Int]  // productID -> version
    public let createdAt: Date
    public let updatedAt: Date

    public struct PersistedTrustRoot: Codable, Equatable, Sendable {
        public let version: Int
        public let canonicalBytes: Data

        public init(version: Int, canonicalBytes: Data) {
            self.version = version
            self.canonicalBytes = canonicalBytes
        }
    }

    public struct BlockedTarget: Codable, Equatable, Sendable, Hashable {
        public let productID: String
        public let hash: String
        public let reason: String
        public let blockedAt: Date

        public init(productID: String, hash: String, reason: String, blockedAt: Date) {
            self.productID = productID
            self.hash = hash
            self.reason = reason
            self.blockedAt = blockedAt
        }
    }

    public init(
        trustRoot: PersistedTrustRoot,
        versions: [String: Int] = [:],
        blockedTargets: [BlockedTarget] = [],
        lastBundleVersion: [String: Int] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = TrustedState.currentSchemaVersion
        self.trustRoot = trustRoot
        self.versions = versions
        self.blockedTargets = blockedTargets
        self.lastBundleVersion = lastBundleVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum TrustedStateStore {

    /// Load trusted state from disk. Returns nil if not present.
    public static func load(from url: URL) throws -> TrustedState? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LumenError.corruptedState("Cannot read state file: \(error)")
        }
        do {
            let state = try JSONDecoder.iso8601.decode(TrustedState.self, from: data)
            guard state.schemaVersion == TrustedState.currentSchemaVersion else {
                throw LumenError.stateMigrationRequired(
                    from: state.schemaVersion,
                    to: TrustedState.currentSchemaVersion
                )
            }
            return state
        } catch {
            throw LumenError.corruptedState("Cannot decode state: \(error)")
        }
    }

    /// Save trusted state to disk atomically with fsync.
    public static func save(_ state: TrustedState, to url: URL) throws {
        let encoder = JSONEncoder.iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)

        // Ensure parent directory exists
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        // Write atomically
        try data.write(to: url, options: .atomic)

        // fsync
        let fd = open(url.path, O_RDONLY)
        if fd >= 0 {
            fsync(fd)
            close(fd)
        }
    }

    /// Create initial state from a bootstrap trust root.
    public static func initialState(version: Int, canonicalBytes: Data) -> TrustedState {
        let persistedRoot = TrustedState.PersistedTrustRoot(
            version: version,
            canonicalBytes: canonicalBytes
        )
        return TrustedState(trustRoot: persistedRoot)
    }
}

extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
