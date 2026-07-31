import Foundation
import LumenCore

public enum InstallerState: String, Codable, Sendable, CaseIterable {
    case idle
    case checking
    case updateAvailable
    case downloading
    case verifying
    case staging
    case readyToInstall
    case awaitingHostTermination
    case replacing
    case launchingCandidate
    case awaitingHealthAcknowledgement
    case committed
    case rollbackPending
    case manualRecoveryRequired
    case failed
}

public struct TransactionRecord: Codable, Equatable, Sendable {
    public let transactionID: String
    public let hostBundlePath: String
    public let candidatePath: String
    public let candidateExtractedPath: String?
    public let backupPath: String?
    public let expectedBundleVersion: Int
    public let state: InstallerState
    public let createdAt: Date
    public let updatedAt: Date
    public let failureReason: String?

    public init(
        transactionID: String = UUID().uuidString,
        hostBundlePath: String,
        candidatePath: String,
        candidateExtractedPath: String? = nil,
        backupPath: String? = nil,
        expectedBundleVersion: Int,
        state: InstallerState = .idle,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        failureReason: String? = nil
    ) {
        self.transactionID = transactionID
        self.hostBundlePath = hostBundlePath
        self.candidatePath = candidatePath
        self.candidateExtractedPath = candidateExtractedPath
        self.backupPath = backupPath
        self.expectedBundleVersion = expectedBundleVersion
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.failureReason = failureReason
    }

    public func withState(_ newState: InstallerState, failureReason: String? = nil) -> TransactionRecord {
        TransactionRecord(
            transactionID: transactionID,
            hostBundlePath: hostBundlePath,
            candidatePath: candidatePath,
            candidateExtractedPath: candidateExtractedPath,
            backupPath: backupPath,
            expectedBundleVersion: expectedBundleVersion,
            state: newState,
            createdAt: createdAt,
            updatedAt: Date(),
            failureReason: failureReason ?? self.failureReason
        )
    }

    public func withBackupPath(_ path: String) -> TransactionRecord {
        TransactionRecord(
            transactionID: transactionID,
            hostBundlePath: hostBundlePath,
            candidatePath: candidatePath,
            candidateExtractedPath: candidateExtractedPath,
            backupPath: path,
            expectedBundleVersion: expectedBundleVersion,
            state: state,
            createdAt: createdAt,
            updatedAt: Date(),
            failureReason: failureReason
        )
    }

    public func withExtractedPath(_ path: String) -> TransactionRecord {
        TransactionRecord(
            transactionID: transactionID,
            hostBundlePath: hostBundlePath,
            candidatePath: candidatePath,
            candidateExtractedPath: path,
            backupPath: backupPath,
            expectedBundleVersion: expectedBundleVersion,
            state: state,
            createdAt: createdAt,
            updatedAt: Date(),
            failureReason: failureReason
        )
    }
}
