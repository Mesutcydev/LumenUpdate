// LumenCore.swift
// Lumen Update - Core types and shared interfaces

import Foundation

/// LumenCore provides shared types, errors, and protocol interfaces used across
/// all Lumen Update modules. It contains no TUF-specific logic; that lives in
/// LumenTUF. It contains no cryptographic primitives; those live in LumenCrypto.
public enum LumenCore {
}

// MARK: - Role Enum

/// TUF metadata roles. These are the four required top-level TUF roles.
public enum MetadataRole: String, Codable, Sendable, CaseIterable, Hashable {
    case root
    case timestamp
    case snapshot
    case targets
    case delegatedTargets  // logical role; file path is constructed

    /// The filename pattern for this role.
    /// - Root: `<version>.root.json`
    /// - Timestamp: `timestamp.json`
    /// - Snapshot: `<version>.snapshot.json`
    /// - Targets: `<version>.targets.json`
    public func filename(version: Int? = nil) -> String {
        switch self {
        case .root:
            return "\(version ?? 1).root.json"
        case .timestamp:
            return "timestamp.json"
        case .snapshot:
            return "\(version ?? 1).snapshot.json"
        case .targets:
            return "\(version ?? 1).targets.json"
        case .delegatedTargets:
            return ""  // delegated roles have arbitrary filenames
        }
    }
}

// MARK: - LumenError

/// All errors raised by Lumen modules. Each case has an associated code and
/// human-readable description. The code is stable for programmatic handling;
/// the description is for logging and user display.
public enum LumenError: Error, Equatable, Sendable, LocalizedError {
    // MARK: Metadata errors
    case invalidMetadataFormat(String)
    case invalidBase64(String)
    case invalidJSON(String)
    case missingField(String)
    case unsupportedKeyType(String)
    case unsupportedScheme(String)
    case metadataTooLarge(role: String, size: Int, limit: Int)
    case metadataEmpty(role: String)

    // MARK: Signature errors
    case invalidSignature(String)
    case insufficientSignatures(role: String, required: Int, provided: Int)
    case unknownKey(String)
    case duplicateSignature(String)

    // MARK: Version errors
    case versionRollback(role: String, received: Int, stored: Int)
    case versionFastForward(role: String, received: Int, stored: Int, maxJump: Int)
    case invalidVersion(String)

    // MARK: Expiration errors
    case expiredMetadata(role: String, expiredAt: String, now: String)
    case invalidExpiration(String)

    // MARK: Target errors
    case targetNotFound(String)
    case targetHashMismatch(expected: String, actual: String)
    case targetLengthMismatch(expected: Int, actual: Int)
    case targetProductMismatch(expected: String, actual: String)
    case targetChannelMismatch(expected: String, actual: String)
    case targetArchitectureMismatch(required: [String], available: [String])
    case targetUnsupportedMinOS(required: String, available: String)
    case targetLowerVersion(received: Int, stored: Int)
    case targetInvalid(String)

    // MARK: Delegation errors
    case delegationNotFound(String)
    case delegationExpired(String)
    case delegationInvalid(String)
    case delegationPathMismatch(role: String, path: String)

    // MARK: Repository errors
    case repositoryUnreachable(String)
    case repositoryTimeout
    case repositoryInvalidResponse(String)
    case repositoryNotModified
    case redirectDisallowed(from: String, to: String)

    // MARK: State errors
    case noTrustedRoot
    case corruptedState(String)
    case stateMigrationRequired(from: Int, to: Int)
    case blockedTarget(productID: String, hash: String)

    // MARK: Installation errors
    case destinationMismatch(expected: String, actual: String)
    case notWritable(String)
    case insufficientDiskSpace(required: Int64, available: Int64)
    case bundleManifestMismatch
    case backupFailed(String)
    case replacementFailed(String)
    case launchFailed(String)
    case healthTimeout(String)
    case manualRecoveryRequired(String)
    case quarantined(String)

    // MARK: Archive errors
    case archiveInvalid(String)
    case archivePathTraversal(String)
    case archiveSymlinkEscape(String)
    case archiveExcessiveSize(actual: Int64, limit: Int64)
    case archiveExcessiveEntries(actual: Int, limit: Int)
    case archiveExcessiveNesting(actual: Int, limit: Int)
    case archiveSetuidNotAllowed(String)
    case archiveDuplicateEntry(String)
    case archiveDeviceFileNotAllowed(String)
    case archiveSocketNotAllowed(String)
    case archiveFIFONotAllowed(String)
    case archiveHardlinkNotAllowed(String)
    case archiveMalformed(String)

    // MARK: Crypto errors
    case cryptoFailure(String)
    case keyGenerationFailed(String)
    case keyImportFailed(String)
    case keyNotFound(String)
    case keychainFailure(String)

    public var code: String {
        switch self {
        case .invalidMetadataFormat: return "metadata.invalidFormat"
        case .invalidBase64: return "metadata.invalidBase64"
        case .invalidJSON: return "metadata.invalidJSON"
        case .missingField: return "metadata.missingField"
        case .unsupportedKeyType: return "metadata.unsupportedKeyType"
        case .unsupportedScheme: return "metadata.unsupportedScheme"
        case .metadataTooLarge: return "metadata.tooLarge"
        case .metadataEmpty: return "metadata.empty"
        case .invalidSignature: return "signature.invalid"
        case .insufficientSignatures: return "signature.insufficient"
        case .unknownKey: return "signature.unknownKey"
        case .duplicateSignature: return "signature.duplicate"
        case .versionRollback: return "version.rollback"
        case .versionFastForward: return "version.fastForward"
        case .invalidVersion: return "version.invalid"
        case .expiredMetadata: return "metadata.expired"
        case .invalidExpiration: return "metadata.invalidExpiration"
        case .targetNotFound: return "target.notFound"
        case .targetHashMismatch: return "target.hashMismatch"
        case .targetLengthMismatch: return "target.lengthMismatch"
        case .targetProductMismatch: return "target.productMismatch"
        case .targetChannelMismatch: return "target.channelMismatch"
        case .targetArchitectureMismatch: return "target.architectureMismatch"
        case .targetUnsupportedMinOS: return "target.unsupportedMinOS"
        case .targetLowerVersion: return "target.lowerVersion"
        case .targetInvalid: return "target.invalid"
        case .delegationNotFound: return "delegation.notFound"
        case .delegationExpired: return "delegation.expired"
        case .delegationInvalid: return "delegation.invalid"
        case .delegationPathMismatch: return "delegation.pathMismatch"
        case .repositoryUnreachable: return "repository.unreachable"
        case .repositoryTimeout: return "repository.timeout"
        case .repositoryInvalidResponse: return "repository.invalidResponse"
        case .repositoryNotModified: return "repository.notModified"
        case .redirectDisallowed: return "repository.redirectDisallowed"
        case .noTrustedRoot: return "state.noTrustedRoot"
        case .corruptedState: return "state.corrupted"
        case .stateMigrationRequired: return "state.migrationRequired"
        case .blockedTarget: return "state.blockedTarget"
        case .destinationMismatch: return "install.destinationMismatch"
        case .notWritable: return "install.notWritable"
        case .insufficientDiskSpace: return "install.insufficientDiskSpace"
        case .bundleManifestMismatch: return "install.bundleManifestMismatch"
        case .backupFailed: return "install.backupFailed"
        case .replacementFailed: return "install.replacementFailed"
        case .launchFailed: return "install.launchFailed"
        case .healthTimeout: return "install.healthTimeout"
        case .manualRecoveryRequired: return "install.manualRecoveryRequired"
        case .quarantined: return "install.quarantined"
        case .archiveInvalid: return "archive.invalid"
        case .archivePathTraversal: return "archive.pathTraversal"
        case .archiveSymlinkEscape: return "archive.symlinkEscape"
        case .archiveExcessiveSize: return "archive.excessiveSize"
        case .archiveExcessiveEntries: return "archive.excessiveEntries"
        case .archiveExcessiveNesting: return "archive.excessiveNesting"
        case .archiveSetuidNotAllowed: return "archive.setuidNotAllowed"
        case .archiveDuplicateEntry: return "archive.duplicateEntry"
        case .archiveDeviceFileNotAllowed: return "archive.deviceFileNotAllowed"
        case .archiveSocketNotAllowed: return "archive.socketNotAllowed"
        case .archiveFIFONotAllowed: return "archive.fifoNotAllowed"
        case .archiveHardlinkNotAllowed: return "archive.hardlinkNotAllowed"
        case .archiveMalformed: return "archive.malformed"
        case .cryptoFailure: return "crypto.failure"
        case .keyGenerationFailed: return "crypto.keyGenerationFailed"
        case .keyImportFailed: return "crypto.keyImportFailed"
        case .keyNotFound: return "crypto.keyNotFound"
        case .keychainFailure: return "crypto.keychainFailure"
        }
    }

    public var description: String {
        switch self {
        case .invalidMetadataFormat(let s): return "Invalid metadata format: \(s)"
        case .invalidBase64(let s): return "Invalid base64 encoding: \(s)"
        case .invalidJSON(let s): return "Invalid JSON: \(s)"
        case .missingField(let s): return "Missing required field: \(s)"
        case .unsupportedKeyType(let s): return "Unsupported key type: \(s)"
        case .unsupportedScheme(let s): return "Unsupported scheme: \(s)"
        case .metadataTooLarge(let role, let size, let limit):
            return "Metadata for role \(role) is too large: \(size) bytes (limit: \(limit))"
        case .metadataEmpty(let role): return "Metadata for role \(role) is empty"
        case .invalidSignature(let s): return "Invalid signature: \(s)"
        case .insufficientSignatures(let role, let required, let provided):
            return "Insufficient signatures for role \(role): \(provided) of \(required) required"
        case .unknownKey(let s): return "Unknown key ID: \(s)"
        case .duplicateSignature(let s): return "Duplicate signature for key \(s)"
        case .versionRollback(let role, let received, let stored):
            return "Version rollback for role \(role): received \(received), stored \(stored)"
        case .versionFastForward(let role, let received, let stored, let maxJump):
            return "Version fast-forward for role \(role): received \(received), stored \(stored), max jump \(maxJump)"
        case .invalidVersion(let s): return "Invalid version: \(s)"
        case .expiredMetadata(let role, let expiredAt, let now):
            return "Metadata for role \(role) expired at \(expiredAt) (now: \(now))"
        case .invalidExpiration(let s): return "Invalid expiration: \(s)"
        case .targetNotFound(let s): return "Target not found: \(s)"
        case .targetHashMismatch(let expected, let actual):
            return "Target hash mismatch: expected \(expected), got \(actual)"
        case .targetLengthMismatch(let expected, let actual):
            return "Target length mismatch: expected \(expected), got \(actual)"
        case .targetProductMismatch(let expected, let actual):
            return "Target product mismatch: expected \(expected), got \(actual)"
        case .targetChannelMismatch(let expected, let actual):
            return "Target channel mismatch: expected \(expected), got \(actual)"
        case .targetArchitectureMismatch(let required, let available):
            return "Target architecture mismatch: required \(required), available \(available)"
        case .targetUnsupportedMinOS(let required, let available):
            return "Target requires macOS \(required), host is \(available)"
        case .targetLowerVersion(let received, let stored):
            return "Target version \(received) is not higher than stored \(stored)"
        case .targetInvalid(let s): return "Invalid target: \(s)"
        case .delegationNotFound(let s): return "Delegation not found: \(s)"
        case .delegationExpired(let s): return "Delegation expired: \(s)"
        case .delegationInvalid(let s): return "Invalid delegation: \(s)"
        case .delegationPathMismatch(let role, let path):
            return "Path \(path) not matched by delegation \(role)"
        case .repositoryUnreachable(let s): return "Repository unreachable: \(s)"
        case .repositoryTimeout: return "Repository request timed out"
        case .repositoryInvalidResponse(let s): return "Invalid repository response: \(s)"
        case .repositoryNotModified: return "Repository not modified"
        case .redirectDisallowed(let from, let to):
            return "Redirect from \(from) to \(to) is not allowed"
        case .noTrustedRoot: return "No trusted root metadata available"
        case .corruptedState(let s): return "Corrupted local state: \(s)"
        case .stateMigrationRequired(let from, let to):
            return "State migration required: schema \(from) to \(to)"
        case .blockedTarget(let productID, let hash):
            return "Target \(hash) for product \(productID) is locally blocked"
        case .destinationMismatch(let expected, let actual):
            return "Destination mismatch: expected \(expected), got \(actual)"
        case .notWritable(let s): return "Not writable: \(s)"
        case .insufficientDiskSpace(let required, let available):
            return "Insufficient disk space: need \(required) bytes, have \(available)"
        case .bundleManifestMismatch: return "Extracted bundle does not match manifest"
        case .backupFailed(let s): return "Backup failed: \(s)"
        case .replacementFailed(let s): return "Bundle replacement failed: \(s)"
        case .launchFailed(let s): return "Candidate launch failed: \(s)"
        case .healthTimeout(let s): return "Health acknowledgement timed out: \(s)"
        case .manualRecoveryRequired(let s): return "Manual recovery required: \(s)"
        case .quarantined(let s): return "Bundle is quarantined: \(s)"
        case .archiveInvalid(let s): return "Invalid archive: \(s)"
        case .archivePathTraversal(let s): return "Archive contains path traversal: \(s)"
        case .archiveSymlinkEscape(let s): return "Archive symlink escape: \(s)"
        case .archiveExcessiveSize(let actual, let limit):
            return "Archive uncompressed size \(actual) exceeds limit \(limit)"
        case .archiveExcessiveEntries(let actual, let limit):
            return "Archive has \(actual) entries, limit is \(limit)"
        case .archiveExcessiveNesting(let actual, let limit):
            return "Archive nesting depth \(actual) exceeds limit \(limit)"
        case .archiveSetuidNotAllowed(let s): return "Archive contains setuid file: \(s)"
        case .archiveDuplicateEntry(let s): return "Archive has duplicate entry: \(s)"
        case .archiveDeviceFileNotAllowed(let s): return "Archive contains device file: \(s)"
        case .archiveSocketNotAllowed(let s): return "Archive contains socket: \(s)"
        case .archiveFIFONotAllowed(let s): return "Archive contains FIFO: \(s)"
        case .archiveHardlinkNotAllowed(let s): return "Archive contains hard link: \(s)"
        case .archiveMalformed(let s): return "Malformed archive: \(s)"
        case .cryptoFailure(let s): return "Cryptographic operation failed: \(s)"
        case .keyGenerationFailed(let s): return "Key generation failed: \(s)"
        case .keyImportFailed(let s): return "Key import failed: \(s)"
        case .keyNotFound(let s): return "Key not found: \(s)"
        case .keychainFailure(let s): return "Keychain operation failed: \(s)"
        }
    }

    public var errorDescription: String? { description }
}
