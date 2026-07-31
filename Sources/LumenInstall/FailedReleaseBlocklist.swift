import Foundation
import LumenCore

public struct BlockedRelease: Codable, Equatable, Sendable {
    public let productID: String
    public let targetHash: String
    public let bundleVersion: Int
    public let reason: String
    public let blockedAt: Date

    public init(productID: String, targetHash: String, bundleVersion: Int, reason: String) {
        self.productID = productID
        self.targetHash = targetHash
        self.bundleVersion = bundleVersion
        self.reason = reason
        self.blockedAt = Date()
    }
}

public enum FailedReleaseBlocklist {

    public static func blocklistURL(forProduct productID: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("LumenUpdate/\(productID)/blocklist.json")
    }

    public static func load(forProduct productID: String) throws -> [BlockedRelease] {
        let url = blocklistURL(forProduct: productID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([BlockedRelease].self, from: data)
    }

    public static func block(
        productID: String,
        targetHash: String,
        bundleVersion: Int,
        reason: String
    ) throws {
        var blocklist = try load(forProduct: productID)
        let entry = BlockedRelease(
            productID: productID,
            targetHash: targetHash,
            bundleVersion: bundleVersion,
            reason: reason
        )
        blocklist.append(entry)
        try save(blocklist, forProduct: productID)
    }

    public static func isBlocked(
        productID: String,
        targetHash: String
    ) throws -> Bool {
        let blocklist = try load(forProduct: productID)
        return blocklist.contains { $0.targetHash == targetHash }
    }

    public static func unblock(
        productID: String,
        targetHash: String
    ) throws {
        var blocklist = try load(forProduct: productID)
        blocklist.removeAll { $0.targetHash == targetHash }
        try save(blocklist, forProduct: productID)
    }

    public static func clearAll(forProduct productID: String) throws {
        try save([], forProduct: productID)
    }

    private static func save(_ blocklist: [BlockedRelease], forProduct productID: String) throws {
        let url = blocklistURL(forProduct: productID)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(blocklist)
        try data.write(to: url, options: .atomic)
    }
}
