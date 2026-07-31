import Foundation
import LumenCore

public struct ArchiveEntryInfo: Sendable {
    public let path: String
    public let type: EntryType
    public let mode: Int
    public let size: Int64
    public let symlinkTarget: String?

    public enum EntryType: Sendable {
        case file
        case directory
        case symlink
        case hardlink
        case device
        case socket
        case fifo
    }

    public init(path: String, type: EntryType, mode: Int, size: Int64, symlinkTarget: String? = nil) {
        self.path = path
        self.type = type
        self.mode = mode
        self.size = size
        self.symlinkTarget = symlinkTarget
    }
}

public struct ArchiveValidationLimits: Sendable {
    public let maxEntries: Int
    public let maxNestingDepth: Int
    public let maxUncompressedSize: Int64
    public let maxPathLength: Int

    public init(
        maxEntries: Int = 50_000,
        maxNestingDepth: Int = 64,
        maxUncompressedSize: Int64 = 2 * 1024 * 1024 * 1024,
        maxPathLength: Int = 1024
    ) {
        self.maxEntries = maxEntries
        self.maxNestingDepth = maxNestingDepth
        self.maxUncompressedSize = maxUncompressedSize
        self.maxPathLength = maxPathLength
    }

    public static let `default` = ArchiveValidationLimits()
}

public enum ArchiveEntryValidator {

    public static func validateEntry(
        _ entry: ArchiveEntryInfo,
        limits: ArchiveValidationLimits,
        stagingRoot: String,
        seenPaths: inout Set<String>,
        totalUncompressedSize: inout Int64
    ) throws {
        // Path length check
        guard entry.path.count <= limits.maxPathLength else {
            throw LumenError.archivePathTraversal("Path too long (\(entry.path.count) > \(limits.maxPathLength)): \(entry.path.prefix(100))...")
        }

        // Normalize and validate path
        let normalized = try PathNormalizer.normalize(entry.path)

        // Duplicate detection
        guard !seenPaths.contains(normalized) else {
            throw LumenError.archiveDuplicateEntry(normalized)
        }
        seenPaths.insert(normalized)

        // Nesting depth check
        let depth = normalized.split(separator: "/").count
        guard depth <= limits.maxNestingDepth else {
            throw LumenError.archiveExcessiveNesting(actual: depth, limit: limits.maxNestingDepth)
        }

        // Type-specific validation
        switch entry.type {
        case .file:
            // Setuid/setgid check
            if entry.mode & 0o4000 != 0 {
                throw LumenError.archiveSetuidNotAllowed(normalized)
            }
            if entry.mode & 0o2000 != 0 {
                throw LumenError.archiveSetuidNotAllowed("setgid: \(normalized)")
            }
            totalUncompressedSize += entry.size
            guard totalUncompressedSize <= limits.maxUncompressedSize else {
                throw LumenError.archiveExcessiveSize(actual: totalUncompressedSize, limit: limits.maxUncompressedSize)
            }

        case .symlink:
            guard let target = entry.symlinkTarget else {
                throw LumenError.archiveSymlinkEscape("Symlink '\(normalized)' has no target")
            }
            try PathNormalizer.validateSymlinkTarget(target, entryPath: normalized, stagingRoot: stagingRoot)

        case .hardlink:
            throw LumenError.archiveHardlinkNotAllowed(normalized)

        case .device:
            throw LumenError.archiveDeviceFileNotAllowed(normalized)

        case .socket:
            throw LumenError.archiveSocketNotAllowed(normalized)

        case .fifo:
            throw LumenError.archiveFIFONotAllowed(normalized)

        case .directory:
            break
        }
    }

    public static func validateEntryCount(_ count: Int, limits: ArchiveValidationLimits) throws {
        guard count <= limits.maxEntries else {
            throw LumenError.archiveExcessiveEntries(actual: count, limit: limits.maxEntries)
        }
    }

    public static func validateSingleAppBundle(_ entries: [ArchiveEntryInfo], expectedBundleID: String?) throws {
        let appBundles = entries.filter { entry in
            let components = entry.path.split(separator: "/")
            return components.count >= 1 && components[0].hasSuffix(".app")
        }.map { entry in
            String(entry.path.split(separator: "/")[0])
        }

        let uniqueBundles = Set(appBundles)
        guard uniqueBundles.count <= 1 else {
            throw LumenError.archiveInvalid("Multiple .app bundles found: \(uniqueBundles.sorted().joined(separator: ", "))")
        }

        if let expectedBundleID, let bundleName = uniqueBundles.first {
            let expectedName = expectedBundleID.split(separator: ".").last.map(String.init) ?? ""
            let actualName = bundleName.replacingOccurrences(of: ".app", with: "")
            if !expectedName.isEmpty && actualName != expectedName && !bundleName.contains(expectedName) {
                // Soft check - bundle name doesn't have to match bundle ID exactly
            }
        }
    }
}
