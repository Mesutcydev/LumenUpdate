import XCTest
import LumenCore
@testable import LumenInstall

final class TransactionRecordTests: XCTestCase {

    func testCreatesRecordWithDefaultState() {
        let record = TransactionRecord(
            hostBundlePath: "/Applications/MyApp.app",
            candidatePath: "/tmp/candidate.aar",
            expectedBundleVersion: 42
        )
        XCTAssertEqual(record.state, .idle)
        XCTAssertFalse(record.transactionID.isEmpty)
        XCTAssertNil(record.backupPath)
        XCTAssertNil(record.failureReason)
    }

    func testWithStateTransition() {
        let record = TransactionRecord(
            hostBundlePath: "/Applications/MyApp.app",
            candidatePath: "/tmp/candidate.aar",
            expectedBundleVersion: 42
        )
        let updated = record.withState(.downloading)
        XCTAssertEqual(updated.state, .downloading)
        XCTAssertEqual(updated.transactionID, record.transactionID)
        XCTAssertNil(updated.failureReason)
    }

    func testWithStateAndFailureReason() {
        let record = TransactionRecord(
            hostBundlePath: "/Applications/MyApp.app",
            candidatePath: "/tmp/candidate.aar",
            expectedBundleVersion: 42
        )
        let failed = record.withState(.failed, failureReason: "Hash mismatch")
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.failureReason, "Hash mismatch")
    }

    func testWithBackupPath() {
        let record = TransactionRecord(
            hostBundlePath: "/Applications/MyApp.app",
            candidatePath: "/tmp/candidate.aar",
            expectedBundleVersion: 42
        )
        let withBackup = record.withBackupPath("/Applications/MyApp.app.backup.123")
        XCTAssertEqual(withBackup.backupPath, "/Applications/MyApp.app.backup.123")
        XCTAssertEqual(withBackup.state, record.state)
    }

    func testCodableRoundTrip() throws {
        let record = TransactionRecord(
            hostBundlePath: "/Applications/MyApp.app",
            candidatePath: "/tmp/candidate.aar",
            expectedBundleVersion: 42,
            state: .replacing
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TransactionRecord.self, from: data)

        XCTAssertEqual(decoded.transactionID, record.transactionID)
        XCTAssertEqual(decoded.state, .replacing)
        XCTAssertEqual(decoded.expectedBundleVersion, 42)
    }
}

final class TransactionJournalTests: XCTestCase {

    func testWriteAndRead() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test-journal-\(UUID().uuidString).json")

        let record = TransactionRecord(
            hostBundlePath: "/Applications/MyApp.app",
            candidatePath: "/tmp/candidate.aar",
            expectedBundleVersion: 42
        )

        try TransactionJournal.write(record, to: url)
        let loaded = try TransactionJournal.read(from: url)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.transactionID, record.transactionID)
        XCTAssertEqual(loaded?.state, .idle)

        try? FileManager.default.removeItem(at: url)
    }

    func testReadReturnsNilForMissingFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).json")
        let loaded = try TransactionJournal.read(from: url)
        XCTAssertNil(loaded)
    }

    func testTransitionUpdatesState() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test-journal-\(UUID().uuidString).json")

        let record = TransactionRecord(
            hostBundlePath: "/Applications/MyApp.app",
            candidatePath: "/tmp/candidate.aar",
            expectedBundleVersion: 42
        )
        try TransactionJournal.write(record, to: url)

        let updated = try TransactionJournal.transition(record, to: .downloading, journalURL: url)
        XCTAssertEqual(updated.state, .downloading)

        let loaded = try TransactionJournal.read(from: url)
        XCTAssertEqual(loaded?.state, .downloading)

        try? FileManager.default.removeItem(at: url)
    }

    func testClearRemovesJournal() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test-journal-\(UUID().uuidString).json")

        let record = TransactionRecord(
            hostBundlePath: "/Applications/MyApp.app",
            candidatePath: "/tmp/candidate.aar",
            expectedBundleVersion: 42
        )
        try TransactionJournal.write(record, to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        TransactionJournal.clear(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

final class InstallerStateTests: XCTestCase {

    func testAllStatesAreCodable() throws {
        for state in InstallerState.allCases {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(InstallerState.self, from: data)
            XCTAssertEqual(decoded, state)
        }
    }

    func testStateRawValues() {
        XCTAssertEqual(InstallerState.idle.rawValue, "idle")
        XCTAssertEqual(InstallerState.committed.rawValue, "committed")
        XCTAssertEqual(InstallerState.rollbackPending.rawValue, "rollbackPending")
        XCTAssertEqual(InstallerState.manualRecoveryRequired.rawValue, "manualRecoveryRequired")
    }
}

final class FailedReleaseBlocklistTests: XCTestCase {

    func testBlockAndCheck() throws {
        let productID = "com.test.blocklist.\(UUID().uuidString)"

        try FailedReleaseBlocklist.block(
            productID: productID,
            targetHash: "abc123",
            bundleVersion: 5,
            reason: "test failure"
        )

        XCTAssertTrue(try FailedReleaseBlocklist.isBlocked(productID: productID, targetHash: "abc123"))
        XCTAssertFalse(try FailedReleaseBlocklist.isBlocked(productID: productID, targetHash: "other"))

        try FailedReleaseBlocklist.clearAll(forProduct: productID)
    }

    func testUnblock() throws {
        let productID = "com.test.unblock.\(UUID().uuidString)"

        try FailedReleaseBlocklist.block(
            productID: productID,
            targetHash: "def456",
            bundleVersion: 10,
            reason: "test"
        )
        XCTAssertTrue(try FailedReleaseBlocklist.isBlocked(productID: productID, targetHash: "def456"))

        try FailedReleaseBlocklist.unblock(productID: productID, targetHash: "def456")
        XCTAssertFalse(try FailedReleaseBlocklist.isBlocked(productID: productID, targetHash: "def456"))
    }

    func testEmptyBlocklistReturnsFalse() throws {
        let productID = "com.test.empty.\(UUID().uuidString)"
        XCTAssertFalse(try FailedReleaseBlocklist.isBlocked(productID: productID, targetHash: "anything"))
    }
}

final class HealthCheckTests: XCTestCase {

    func testReportAndReadHealthy() throws {
        let txID = UUID().uuidString
        try HealthCheck.reportHealthy(transactionID: txID)

        // Health reports are keyed by transaction ID in the health directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let healthURL = appSupport.appendingPathComponent("LumenUpdate/health/\(txID).json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: healthURL.path))

        let data = try Data(contentsOf: healthURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(HealthCheck.HealthReport.self, from: data)

        XCTAssertTrue(report.isHealthy)
        XCTAssertEqual(report.transactionID, txID)

        try? FileManager.default.removeItem(at: healthURL)
    }
}
