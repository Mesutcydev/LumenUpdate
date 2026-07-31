// TargetResolver.swift
// Resolves delegated targets and selects a target matching the host application.

import Foundation

/// Host application profile used for target selection.
public struct HostProfile: Sendable, Equatable, Hashable {
    public let productID: String
    public let bundleIdentifier: String
    public let currentBundleVersion: Int
    public let architecture: String       // "arm64" or "x86_64"
    public let macOSVersion: String       // "13.0", "14.5", etc.
    public let channel: String            // "stable", "beta", "nightly"

    public init(
        productID: String,
        bundleIdentifier: String,
        currentBundleVersion: Int,
        architecture: String,
        macOSVersion: String,
        channel: String
    ) {
        self.productID = productID
        self.bundleIdentifier = bundleIdentifier
        self.currentBundleVersion = currentBundleVersion
        self.architecture = architecture
        self.macOSVersion = macOSVersion
        self.channel = channel
    }
}

/// A resolved target with its full metadata.
public struct ResolvedTarget: Sendable, Equatable, Hashable {
    public let path: String
    public let info: TUFTargetInfo
    public let custom: LumenTargetCustom

    public init(path: String, info: TUFTargetInfo, custom: LumenTargetCustom) {
        self.path = path
        self.info = info
        self.custom = custom
    }
}

public enum TargetResolver {

    /// Resolve a target matching the host profile from a (potentially delegated) targets metadata.
    ///
    /// Selection algorithm:
    /// 1. Start with the root targets metadata.
    /// 2. If the host's channel is configured, find a delegation matching the channel
    ///    (e.g., "<productID>-<channel>") and use that delegated targets metadata.
    /// 3. Iterate targets in the selected metadata and find one matching the host profile.
    /// 4. Validate the target's custom metadata against the host profile.
    public static func resolve(
        targets: TUFTargetsMetadata,
        delegatedTargets: [String: TUFTargetsMetadata],
        host: HostProfile,
        now: Date = Date()
    ) throws -> ResolvedTarget {
        // Step 1: Find the appropriate delegated role for the host's channel
        let effectiveTargets: TUFTargetsMetadata
        let roleName = "\(host.productID)-\(host.channel)"

        if let delegated = delegatedTargets[roleName] {
            effectiveTargets = delegated
        } else {
            // Fall back to root targets if no delegation for this channel
            effectiveTargets = targets
        }

        // Step 2: Verify the effective targets metadata is not expired
        try ExpirationChecker.checkExpiration(expires: effectiveTargets.expires, now: now, role: "targets")

        // Step 3: Iterate and find a matching target
        for (path, info) in effectiveTargets.targets {
            guard let custom = info.custom else { continue }

            // Product ID must match
            guard custom.productID == host.productID else {
                continue
            }

            // Bundle identifier must match
            guard custom.bundleIdentifier == host.bundleIdentifier else {
                continue
            }

            // Channel must match
            guard custom.channel == host.channel else {
                continue
            }

            // Architecture must include host architecture
            guard custom.architectures.contains(host.architecture) else {
                continue
            }

            // Minimum OS check
            if !macOSVersion(host.macOSVersion, isAtLeast: custom.minimumSystemVersion) {
                continue
            }

            // Bundle version must be higher than current
            guard custom.bundleVersion > host.currentBundleVersion else {
                throw LumenError.targetLowerVersion(received: custom.bundleVersion, stored: host.currentBundleVersion)
            }

            return ResolvedTarget(path: path, info: info, custom: custom)
        }

        throw LumenError.targetNotFound("No target matches host profile for product \(host.productID) channel \(host.channel)")
    }

    /// Compare macOS versions. Returns true if `host` >= `required`.
    /// Versions are dotted like "13.0", "14.5.1".
    public static func macOSVersion(_ host: String, isAtLeast required: String) -> Bool {
        let hostParts = host.split(separator: ".").compactMap { Int($0) }
        let requiredParts = required.split(separator: ".").compactMap { Int($0) }
        let maxLen = max(hostParts.count, requiredParts.count)
        for i in 0..<maxLen {
            let h = i < hostParts.count ? hostParts[i] : 0
            let r = i < requiredParts.count ? requiredParts[i] : 0
            if h > r { return true }
            if h < r { return false }
        }
        return true  // equal
    }
}
