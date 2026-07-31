import Foundation
import LumenCore

public enum BundleReplacer {

    public static func validateDestination(_ bundlePath: String) throws {
        let url = URL(fileURLWithPath: bundlePath)
        let fm = FileManager.default

        // Reject symlinked destination components
        var current = "/"
        for component in bundlePath.split(separator: "/") {
            current += component + "/"
            let attrs = try? fm.attributesOfItem(atPath: current)
            if let type = attrs?[.type] as? FileAttributeType, type == .typeSymbolicLink {
                throw LumenError.destinationMismatch(
                    expected: bundlePath,
                    actual: "Symlinked path component: \(current)"
                )
            }
        }

        // Confirm parent is writable
        let parent = url.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path) else {
            throw LumenError.notWritable(parent.path)
        }

        // Confirm on local writable volume
        let values = try url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsReadOnlyKey])
        guard values.volumeIsLocal == true else {
            throw LumenError.notWritable("Not a local volume: \(bundlePath)")
        }
        guard values.volumeIsReadOnly == false else {
            throw LumenError.notWritable("Read-only volume: \(bundlePath)")
        }
    }

    public static func createBackup(
        of bundlePath: String,
        transactionID: String
    ) throws -> String {
        let fm = FileManager.default
        let backupPath = bundlePath + ".backup.\(transactionID)"

        guard !fm.fileExists(atPath: backupPath) else {
            throw LumenError.backupFailed("Backup already exists: \(backupPath)")
        }

        try fm.copyItem(atPath: bundlePath, toPath: backupPath)
        return backupPath
    }

    public static func replaceBundle(
        at destinationPath: String,
        with candidatePath: String
    ) throws {
        let fm = FileManager.default
        let destURL = URL(fileURLWithPath: destinationPath)
        let candidateURL = URL(fileURLWithPath: candidatePath)

        // Use FileManager.replaceItem for atomic replacement on the same volume
        do {
            _ = try fm.replaceItemAt(
                destURL,
                withItemAt: candidateURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } catch {
            throw LumenError.replacementFailed("\(error)")
        }
    }

    public static func restoreBackup(
        from backupPath: String,
        to destinationPath: String
    ) throws {
        let fm = FileManager.default

        // Remove the failed new bundle
        if fm.fileExists(atPath: destinationPath) {
            try fm.removeItem(atPath: destinationPath)
        }

        // Move backup back
        try fm.moveItem(atPath: backupPath, toPath: destinationPath)
    }

    public static func deleteBackup(at backupPath: String) {
        try? FileManager.default.removeItem(atPath: backupPath)
    }

    public static func checkDiskSpace(
        at path: String,
        requiredBytes: Int64
    ) throws {
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        guard available >= requiredBytes else {
            throw LumenError.insufficientDiskSpace(required: requiredBytes, available: available)
        }
    }
}
