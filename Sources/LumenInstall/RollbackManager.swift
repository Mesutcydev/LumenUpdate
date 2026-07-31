import Foundation
import LumenCore

public enum RollbackManager {

    public static func recoverFromCrash(
        journalURL: URL,
        productID: String
    ) throws -> InstallerState {
        guard let record = try TransactionJournal.read(from: journalURL) else {
            return .idle
        }

        switch record.state {
        case .committed, .idle, .failed:
            return record.state

        case .replacing, .launchingCandidate, .awaitingHealthAcknowledgement:
            // Crash during or after replacement: attempt rollback
            if let backupPath = record.backupPath,
               FileManager.default.fileExists(atPath: backupPath) {
                try BundleReplacer.restoreBackup(
                    from: backupPath,
                    to: record.hostBundlePath
                )
                BundleReplacer.deleteBackup(at: backupPath)
                let recovered = try TransactionJournal.transition(
                    record, to: .rollbackPending, journalURL: journalURL,
                    failureReason: "Crash recovery: rolled back from \(record.state.rawValue)"
                )
                _ = recovered
                return .rollbackPending
            } else {
                let recovered = try TransactionJournal.transition(
                    record, to: .manualRecoveryRequired, journalURL: journalURL,
                    failureReason: "Crash recovery: no backup available"
                )
                _ = recovered
                return .manualRecoveryRequired
            }

        case .rollbackPending:
            // Previous rollback was pending; check if backup still exists
            if let backupPath = record.backupPath,
               FileManager.default.fileExists(atPath: backupPath) {
                try BundleReplacer.restoreBackup(
                    from: backupPath,
                    to: record.hostBundlePath
                )
                BundleReplacer.deleteBackup(at: backupPath)
            }
            return .rollbackPending

        case .manualRecoveryRequired:
            return .manualRecoveryRequired

        default:
            // Pre-replacement states: just clean up
            if let backupPath = record.backupPath {
                BundleReplacer.deleteBackup(at: backupPath)
            }
            TransactionJournal.clear(at: journalURL)
            return .idle
        }
    }

    public static func manualRecovery(
        journalURL: URL
    ) throws {
        guard let record = try TransactionJournal.read(from: journalURL) else {
            throw LumenError.manualRecoveryRequired("No transaction journal found")
        }

        if let backupPath = record.backupPath,
           FileManager.default.fileExists(atPath: backupPath) {
            try BundleReplacer.restoreBackup(
                from: backupPath,
                to: record.hostBundlePath
            )
            BundleReplacer.deleteBackup(at: backupPath)
            TransactionJournal.clear(at: journalURL)
        } else {
            throw LumenError.manualRecoveryRequired("No backup available for manual recovery")
        }
    }
}
