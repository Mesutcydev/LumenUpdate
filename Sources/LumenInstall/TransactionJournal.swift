import Foundation
import LumenCore

public enum TransactionJournal {

    public static func journalURL(forProduct productID: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("LumenUpdate/\(productID)/transaction.json")
    }

    public static func write(_ record: TransactionRecord, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)

        try data.write(to: url, options: .atomic)

        let dirFd = open(parent.path, O_RDONLY)
        if dirFd >= 0 {
            fsync(dirFd)
            close(dirFd)
        }
    }

    public static func read(from url: URL) throws -> TransactionRecord? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TransactionRecord.self, from: data)
    }

    public static func clear(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    public static func transition(
        _ record: TransactionRecord,
        to newState: InstallerState,
        journalURL: URL,
        failureReason: String? = nil
    ) throws -> TransactionRecord {
        let updated = record.withState(newState, failureReason: failureReason)
        try write(updated, to: journalURL)
        return updated
    }
}
