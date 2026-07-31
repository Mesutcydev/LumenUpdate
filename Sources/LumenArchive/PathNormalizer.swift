import Foundation
import LumenCore

public enum PathNormalizer {

    public static func normalize(_ path: String) throws -> String {
        if path.isEmpty {
            throw LumenError.archivePathTraversal("Empty path")
        }

        if path.contains("\0") {
            throw LumenError.archivePathTraversal("NUL character in path: \(path)")
        }

        if path.hasPrefix("/") {
            throw LumenError.archivePathTraversal("Absolute path not allowed: \(path)")
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        var normalized: [String] = []

        for component in components {
            let c = String(component)
            if c.isEmpty || c == "." {
                continue
            }
            if c == ".." {
                throw LumenError.archivePathTraversal("Path traversal via '..': \(path)")
            }
            normalized.append(c)
        }

        let result = normalized.joined(separator: "/")
        if result.isEmpty {
            throw LumenError.archivePathTraversal("Path normalizes to empty: \(path)")
        }

        return result
    }

    public static func isWithinStagingRoot(_ normalizedPath: String, stagingRoot: String) -> Bool {
        let fullPath = (stagingRoot as NSString).appendingPathComponent(normalizedPath)
        let resolvedStaging = (stagingRoot as NSString).standardizingPath
        let resolvedFull = (fullPath as NSString).standardizingPath
        return resolvedFull.hasPrefix(resolvedStaging + "/") || resolvedFull == resolvedStaging
    }

    public static func validateSymlinkTarget(_ target: String, entryPath: String, stagingRoot: String) throws {
        let normalizedTarget = try normalize(target)

        let entryDir = (entryPath as NSString).deletingLastPathComponent
        let resolvedTarget: String
        if normalizedTarget.hasPrefix("/") {
            throw LumenError.archiveSymlinkEscape("Symlink '\(entryPath)' has absolute target: \(target)")
        } else {
            resolvedTarget = (entryDir as NSString).appendingPathComponent(normalizedTarget)
        }

        let canonicalResolved = try normalize(resolvedTarget)
        guard isWithinStagingRoot(canonicalResolved, stagingRoot: stagingRoot) else {
            throw LumenError.archiveSymlinkEscape("Symlink '\(entryPath)' escapes staging: \(target)")
        }
    }
}
