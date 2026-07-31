import Foundation
import LumenCore

public enum SafeExtractor {

    public static func extract(
        archiveURL: URL,
        to stagingDirectory: URL,
        limits: ArchiveValidationLimits = .default,
        expectedBundleID: String? = nil
    ) throws -> URL {
        let fm = FileManager.default

        try fm.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        // Use tar to list entries first for preflight validation
        let listProcess = Process()
        listProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        listProcess.arguments = ["-tzf", archiveURL.path]
        let listPipe = Pipe()
        listProcess.standardOutput = listPipe
        listProcess.standardError = Pipe()
        try listProcess.run()
        listProcess.waitUntilExit()

        guard listProcess.terminationStatus == 0 else {
            throw LumenError.archiveMalformed("Cannot list archive contents (exit \(listProcess.terminationStatus))")
        }

        let listing = String(data: listPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let entryPaths = listing.components(separatedBy: "\n").filter { !$0.isEmpty }

        try ArchiveEntryValidator.validateEntryCount(entryPaths.count, limits: limits)

        // Preflight: validate all paths before extraction
        var seenPaths = Set<String>()
        var totalSize: Int64 = 0

        for path in entryPaths {
            let normalized = try PathNormalizer.normalize(path)
            let depth = normalized.split(separator: "/").count
            guard depth <= limits.maxNestingDepth else {
                throw LumenError.archiveExcessiveNesting(actual: depth, limit: limits.maxNestingDepth)
            }
            guard !seenPaths.contains(normalized) else {
                throw LumenError.archiveDuplicateEntry(normalized)
            }
            seenPaths.insert(normalized)
        }

        // Extract to staging
        let extractProcess = Process()
        extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        extractProcess.arguments = ["-xzf", archiveURL.path, "-C", stagingDirectory.path]
        extractProcess.standardOutput = Pipe()
        extractProcess.standardError = Pipe()
        try extractProcess.run()
        extractProcess.waitUntilExit()

        guard extractProcess.terminationStatus == 0 else {
            throw LumenError.archiveMalformed("Extraction failed (exit \(extractProcess.terminationStatus))")
        }

        // Post-extraction validation: check for symlinks escaping staging
        try validateExtractedTree(stagingDirectory, stagingRoot: stagingDirectory.path)

        // Validate single .app bundle
        let contents = try fm.contentsOfDirectory(atPath: stagingDirectory.path)
        let appBundles = contents.filter { $0.hasSuffix(".app") }
        guard appBundles.count <= 1 else {
            throw LumenError.archiveInvalid("Multiple .app bundles: \(appBundles.joined(separator: ", "))")
        }

        return stagingDirectory
    }

    private static func validateExtractedTree(_ directory: URL, stagingRoot: String) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            return
        }

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            if resourceValues.isSymbolicLink == true {
                let target = try fm.destinationOfSymbolicLink(atPath: fileURL.path)
                let relativePath = fileURL.path.replacingOccurrences(of: stagingRoot + "/", with: "")

                if target.hasPrefix("/") {
                    throw LumenError.archiveSymlinkEscape("Absolute symlink: \(relativePath) -> \(target)")
                }

                // Resolve relative to the symlink's directory
                let symlinkDir = (relativePath as NSString).deletingLastPathComponent
                let resolvedTarget = (symlinkDir as NSString).appendingPathComponent(target)
                let normalized = try PathNormalizer.normalize(resolvedTarget)

                guard PathNormalizer.isWithinStagingRoot(normalized, stagingRoot: stagingRoot) else {
                    throw LumenError.archiveSymlinkEscape("Symlink escapes staging: \(relativePath) -> \(target)")
                }
            }
        }
    }

    public static func cleanup(_ stagingDirectory: URL) {
        try? FileManager.default.removeItem(at: stagingDirectory)
    }
}
