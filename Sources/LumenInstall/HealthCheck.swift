import Foundation
import LumenCore

public enum HealthCheck {

    public struct HealthReport: Codable, Sendable {
        public let transactionID: String
        public let processID: Int32
        public let reportedAt: Date
        public let isHealthy: Bool

        public init(transactionID: String, processID: Int32, isHealthy: Bool) {
            self.transactionID = transactionID
            self.processID = processID
            self.reportedAt = Date()
            self.isHealthy = isHealthy
        }
    }

    public static func reportHealthy(transactionID: String) throws {
        let report = HealthReport(
            transactionID: transactionID,
            processID: ProcessInfo.processInfo.processIdentifier,
            isHealthy: true
        )
        try writeReport(report)
    }

    public static func reportUnhealthy(transactionID: String, reason: String) throws {
        let report = HealthReport(
            transactionID: transactionID,
            processID: ProcessInfo.processInfo.processIdentifier,
            isHealthy: false
        )
        try writeReport(report)
    }

    public static func readReport(forProduct productID: String) throws -> HealthReport? {
        let url = reportURL(forProduct: productID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HealthReport.self, from: data)
    }

    public static func clearReport(forProduct productID: String) {
        let url = reportURL(forProduct: productID)
        try? FileManager.default.removeItem(at: url)
    }

    private static func writeReport(_ report: HealthReport) throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LumenUpdate/health")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        let url = dir.appendingPathComponent("\(report.transactionID).json")
        try data.write(to: url, options: .atomic)
    }

    private static func reportURL(forProduct productID: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("LumenUpdate/health/\(productID).json")
    }
}
