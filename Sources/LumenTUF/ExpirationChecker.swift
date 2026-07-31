// ExpirationChecker.swift
// Validates metadata expiration per SPEC.md §7.

import Foundation

public enum ExpirationChecker {

    /// Validate that metadata is not expired.
    /// - Parameters:
    ///   - expires: ISO 8601 timestamp from metadata
    ///   - now: Current time (injectable for testing)
    ///   - role: Role name for error messages
    ///   - clockSkew: Allowed clock skew in seconds (default: 0)
    /// - Throws: LumenError.expiredMetadata if expired
    public static func checkExpiration(
        expires: String,
        now: Date = Date(),
        role: String,
        clockSkew: TimeInterval = 0
    ) throws {
        guard let expiresDate = ISO8601DateFormatter.lumen.date(from: expires) else {
            throw LumenError.invalidExpiration("Cannot parse '\(expires)' as ISO 8601")
        }
        // With clock skew tolerance, expired = (now - clockSkew) > expiresDate
        let adjustedNow = now.addingTimeInterval(-clockSkew)
        if adjustedNow > expiresDate {
            throw LumenError.expiredMetadata(
                role: role,
                expiredAt: expires,
                now: ISO8601DateFormatter.lumen.string(from: now)
            )
        }
    }
}

/// ISO 8601 date formatter configured for Lumen's needs.
extension ISO8601DateFormatter {
    public static let lumen: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
