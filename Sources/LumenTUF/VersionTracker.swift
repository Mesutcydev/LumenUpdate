// VersionTracker.swift
// Tracks the highest version of each TUF role and detects rollback/fast-forward attacks.

import Foundation

/// Per-role version tracker. Thread-safe.
public final class VersionTracker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.lumenupdate.version-tracker", attributes: .concurrent)
    private var versions: [String: Int] = [:]
    private var maxJump: Int  // maximum allowed version jump per role

    public init(maxJump: Int = 1000) {
        self.maxJump = maxJump
    }

    /// Get the stored version for a role, or 0 if never seen.
    public func version(forRole role: String) -> Int {
        return queue.sync { versions[role] ?? 0 }
    }

    /// Set the version for a role.
    public func setVersion(_ version: Int, forRole role: String) {
        queue.sync(flags: .barrier) { versions[role] = version }
    }

    /// Validate that a new version is acceptable (not a rollback, not a fast-forward).
    /// - Parameters:
    ///   - newVersion: The version of the new metadata
    ///   - role: The role name
    /// - Throws: LumenError.versionRollback if newVersion <= stored
    ///           LumenError.versionFastForward if newVersion - stored > maxJump
    public func validateVersion(_ newVersion: Int, forRole role: String) throws {
        let stored = version(forRole: role)
        guard newVersion > stored else {
            throw LumenError.versionRollback(role: role, received: newVersion, stored: stored)
        }
        if stored > 0 && (newVersion - stored) > maxJump {
            throw LumenError.versionFastForward(role: role, received: newVersion, stored: stored, maxJump: maxJump)
        }
    }

    /// Accept a new version (after successful verification).
    public func acceptVersion(_ newVersion: Int, forRole role: String) {
        setVersion(newVersion, forRole: role)
    }

    /// Reset all version tracking.
    public func reset() {
        queue.sync(flags: .barrier) { versions.removeAll() }
    }

    /// Export current state for persistence.
    public func export() -> [String: Int] {
        return queue.sync { versions }
    }

    /// Import state from persistence.
    public func `import`(_ state: [String: Int]) {
        queue.sync(flags: .barrier) { versions = state }
    }
}
