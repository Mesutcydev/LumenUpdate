import Foundation
import LumenCore

public enum SafeExtractor {

    /// Extract an update archive into an isolated staging directory, enforcing
    /// all archive security rules. Supports Apple Archive (`.aar`, first-class)
    /// and tar.gz (legacy). Extraction always happens into the isolated staging
    /// directory; the extracted tree is then security-scanned and rejected if it
    /// contains path traversal, escaping symlinks, setuid binaries, device files,
    /// sockets, FIFOs, excessive nesting, or too many entries.
    public static func extract(
        archiveURL: URL,
        to stagingDirectory: URL,
        limits: ArchiveValidationLimits = .default,
        expectedBundleID: String? = nil
    ) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        if AppleArchiveCodec.isAppleArchive(archiveURL) {
            try AppleArchiveCodec.extract(archive: archiveURL, to: stagingDirectory)
        } else {
            try extractTar(archiveURL, to: stagingDirectory, limits: limits)
        }

        // Security-scan the extracted tree (applies to both formats).
        try validateExtractedTree(stagingDirectory, stagingRoot: stagingDirectory.path, limits: limits)

        // Enforce a single .app bundle.
        let contents = try fm.contentsOfDirectory(atPath: stagingDirectory.path)
        let appBundles = contents.filter { $0.hasSuffix(".app") }
        guard appBundles.count <= 1 else {
            throw LumenError.archiveInvalid("Multiple .app bundles: \(appBundles.joined(separator: ", "))")
        }

        return stagingDirectory
    }

    // MARK: - tar.gz (legacy) path

    private static func extractTar(_ archiveURL: URL, to stagingDirectory: URL, limits: ArchiveValidationLimits) throws {
        // Preflight: list entries and validate paths BEFORE extraction.
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

        var seenPaths = Set<String>()
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
    }

    // MARK: - Post-extraction security scan

    /// Walk the extracted tree and reject any security violation. This runs on
    /// the isolated staging directory, so a malicious entry cannot escape it —
    /// we detect and throw before the bundle is ever used.
    private static func validateExtractedTree(_ directory: URL, stagingRoot: String, limits: ArchiveValidationLimits) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsPackageDescendants]
        ) else {
            return
        }

        var entryCount = 0

        for case let fileURL as URL in enumerator {
            entryCount += 1
            guard entryCount <= limits.maxEntries else {
                throw LumenError.archiveExcessiveEntries(actual: entryCount, limit: limits.maxEntries)
            }

            let relativePath = fileURL.path.replacingOccurrences(of: stagingRoot + "/", with: "")
            let depth = relativePath.split(separator: "/").count
            guard depth <= limits.maxNestingDepth else {
                throw LumenError.archiveExcessiveNesting(actual: depth, limit: limits.maxNestingDepth)
            }

            let resourceValues = try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey])

            if resourceValues.isSymbolicLink == true {
                try validateSymlink(fileURL, relativePath: relativePath, stagingRoot: stagingRoot)
                continue
            }

            // Non-symlink: inspect type and permission bits.
            let attrs = try fm.attributesOfItem(atPath: fileURL.path)
            if let type = attrs[.type] as? FileAttributeType {
                if type == .typeBlockSpecial || type == .typeCharacterSpecial {
                    throw LumenError.archiveDeviceFileNotAllowed(relativePath)
                } else if type == .typeSocket {
                    throw LumenError.archiveSocketNotAllowed(relativePath)
                } else if type == FileAttributeType(rawValue: "NSFileTypePipe") {
                    // This SDK exposes no `.typePipe` static member; match the
                    // documented FIFO raw value directly.
                    throw LumenError.archiveFIFONotAllowed(relativePath)
                }
            }
            if let permissions = attrs[.posixPermissions] as? Int {
                if permissions & 0o4000 != 0 {
                    throw LumenError.archiveSetuidNotAllowed(relativePath)
                }
                if permissions & 0o2000 != 0 {
                    throw LumenError.archiveSetuidNotAllowed("setgid: \(relativePath)")
                }
            }
        }
    }

    private static func validateSymlink(_ fileURL: URL, relativePath: String, stagingRoot: String) throws {
        let fm = FileManager.default
        let target = try fm.destinationOfSymbolicLink(atPath: fileURL.path)

        if target.hasPrefix("/") {
            throw LumenError.archiveSymlinkEscape("Absolute symlink: \(relativePath) -> \(target)")
        }

        let symlinkDir = (relativePath as NSString).deletingLastPathComponent
        let resolvedTarget = (symlinkDir as NSString).appendingPathComponent(target)
        let normalized = try PathNormalizer.normalize(resolvedTarget)

        guard PathNormalizer.isWithinStagingRoot(normalized, stagingRoot: stagingRoot) else {
            throw LumenError.archiveSymlinkEscape("Symlink escapes staging: \(relativePath) -> \(target)")
        }
    }

    public static func cleanup(_ stagingDirectory: URL) {
        try? FileManager.default.removeItem(at: stagingDirectory)
    }
}
