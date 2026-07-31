// DelegationPathMatcher.swift
// Validates that targets in a delegated role fall within the delegation's
// authorized path patterns. Per TUF spec, a delegated role may only sign
// targets whose paths match its `paths` glob patterns.

import Foundation

enum DelegationPathMatcher {

    /// Check whether a target path is authorized by a delegation's path patterns.
    /// Supports simple glob patterns: `*` matches any sequence within a path
    /// segment, `**` is not supported (TUF uses fnmatch-style patterns).
    static func isPathAuthorized(_ targetPath: String, by patterns: [String]) -> Bool {
        for pattern in patterns {
            if globMatch(pattern: pattern, path: targetPath) {
                return true
            }
        }
        return false
    }

    /// Simple glob matching: `*` matches zero or more characters (including `/`).
    /// This is sufficient for TUF delegation patterns like
    /// `sha256.*.com.example.myapp-*-arm64.aar`.
    private static func globMatch(pattern: String, path: String) -> Bool {
        let p = Array(pattern)
        let s = Array(path)
        return matchHelper(p, 0, s, 0)
    }

    private static func matchHelper(_ p: [Character], _ pi: Int, _ s: [Character], _ si: Int) -> Bool {
        var pi = pi
        var si = si

        while pi < p.count {
            if p[pi] == "*" {
                // Skip consecutive stars
                while pi < p.count && p[pi] == "*" { pi += 1 }
                if pi == p.count { return true }
                // Try matching the rest of the pattern at every position
                for i in si...s.count {
                    if matchHelper(p, pi, s, i) { return true }
                }
                return false
            } else if si < s.count && (p[pi] == "?" || p[pi] == s[si]) {
                pi += 1
                si += 1
            } else {
                return false
            }
        }
        return si == s.count
    }
}
