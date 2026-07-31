// TUFMetadata.swift
// TUF metadata data models (Root, Targets, Snapshot, Timestamp, Delegation).
// All models conform to Codable and can be canonicalized via CanonicalJSON.

import Foundation

// MARK: - Signature

/// A single Ed25519 signature over canonical metadata bytes.
public struct TUFSignature: Codable, Equatable, Sendable, Hashable {
    public let keyid: String  // base64url-encoded SHA-256 of public key
    public let sig: String    // base64url-encoded Ed25519 signature (64 bytes)

    public init(keyid: String, sig: String) {
        self.keyid = keyid
        self.sig = sig
    }
}

// MARK: - Key

/// A public key used to verify TUF metadata signatures.
public struct TUFKey: Codable, Equatable, Sendable, Hashable {
    public let keytype: String   // "ed25519"
    public let scheme: String    // "ed25519"
    public let keyval: TUFKeyVal

    public struct TUFKeyVal: Codable, Equatable, Sendable, Hashable {
        public let publicKey: String  // base64url-encoded public key
        // Custom key field name in JSON is "public"
        private enum CodingKeys: String, CodingKey {
            case publicKey = "public"
        }

        public init(publicKey: String) {
            self.publicKey = publicKey
        }
    }

    public init(keytype: String, scheme: String, publicKey: String) {
        self.keytype = keytype
        self.scheme = scheme
        self.keyval = TUFKeyVal(publicKey: publicKey)
    }
}

// MARK: - Role Definition

/// Defines the keyids and threshold for signing a role.
public struct TUFRoleDefinition: Codable, Equatable, Sendable, Hashable {
    public let keyids: [String]
    public let threshold: Int

    public init(keyids: [String], threshold: Int) {
        self.keyids = keyids
        self.threshold = threshold
    }
}

// MARK: - Signed Envelope

/// Generic signed metadata wrapper. Every TUF role has a `signatures` array
/// containing Ed25519 signatures from the role's keys.
public struct TUFSigned<T: Codable & Sendable & Equatable & Hashable>: Codable, Equatable, Sendable {
    public let signatures: [TUFSignature]
    public let signed: T

    public init(signatures: [TUFSignature], signed: T) {
        self.signatures = signatures
        self.signed = signed
    }
}

// MARK: - Root Metadata

/// Root metadata defines the trusted keys and thresholds for all roles.
public struct TUFRootMetadata: Codable, Equatable, Sendable, Hashable {
    public let _type: String  // MUST be "Root"
    public let specVersion: String  // "1.0"
    public let version: Int
    public let expires: String  // ISO 8601
    public let keys: [String: TUFKey]  // keyid -> key
    public let roles: Roles

    public struct Roles: Codable, Equatable, Sendable, Hashable {
        public let root: TUFRoleDefinition
        public let snapshot: TUFRoleDefinition
        public let targets: TUFRoleDefinition
        public let timestamp: TUFRoleDefinition

        public init(
            root: TUFRoleDefinition,
            snapshot: TUFRoleDefinition,
            targets: TUFRoleDefinition,
            timestamp: TUFRoleDefinition
        ) {
            self.root = root
            self.snapshot = snapshot
            self.targets = targets
            self.timestamp = timestamp
        }
    }

    public init(version: Int, expires: String, keys: [String: TUFKey], roles: Roles) {
        self._type = "Root"
        self.specVersion = "1.0"
        self.version = version
        self.expires = expires
        self.keys = keys
        self.roles = roles
    }
}

// MARK: - Timestamp Metadata

/// Timestamp metadata proves repository freshness and references the snapshot.
public struct TUFTimestampMetadata: Codable, Equatable, Sendable, Hashable {
    public let _type: String  // "Timestamp"
    public let specVersion: String  // "1.0"
    public let version: Int
    public let expires: String  // ISO 8601
    public let meta: [String: MetaEntry]

    public struct MetaEntry: Codable, Equatable, Sendable, Hashable {
        public let version: Int
        public let length: Int
        public let hashes: [String: String]  // "sha256" -> base64url

        public init(version: Int, length: Int, hashes: [String: String]) {
            self.version = version
            self.length = length
            self.hashes = hashes
        }
    }

    public init(version: Int, expires: String, meta: [String: MetaEntry]) {
        self._type = "Timestamp"
        self.specVersion = "1.0"
        self.version = version
        self.expires = expires
        self.meta = meta
    }
}

// MARK: - Snapshot Metadata

/// Snapshot metadata references the targets metadata and all delegated roles.
public struct TUFSnapshotMetadata: Codable, Equatable, Sendable, Hashable {
    public let _type: String  // "Snapshot"
    public let specVersion: String  // "1.0"
    public let version: Int
    public let expires: String  // ISO 8601
    public let meta: [String: MetaEntry]

    public struct MetaEntry: Codable, Equatable, Sendable, Hashable {
        public let version: Int
        public let length: Int
        public let hashes: [String: String]  // "sha256" -> base64url

        public init(version: Int, length: Int, hashes: [String: String]) {
            self.version = version
            self.length = length
            self.hashes = hashes
        }
    }

    public init(version: Int, expires: String, meta: [String: MetaEntry]) {
        self._type = "Snapshot"
        self.specVersion = "1.0"
        self.version = version
        self.expires = expires
        self.meta = meta
    }
}

// MARK: - TargetInfo

/// Information about a target file: hash, length, and Lumen-specific custom metadata.
public struct TUFTargetInfo: Codable, Equatable, Sendable, Hashable {
    public let length: Int
    public let hashes: [String: String]  // "sha256" -> base64url
    public let custom: LumenTargetCustom?

    public init(length: Int, hashes: [String: String], custom: LumenTargetCustom?) {
        self.length = length
        self.hashes = hashes
        self.custom = custom
    }
}

/// Lumen-specific target metadata embedded in the TUF `custom` field.
public struct LumenTargetCustom: Codable, Equatable, Sendable, Hashable {
    public let productID: String
    public let bundleIdentifier: String
    public let bundleVersion: Int
    public let shortVersion: String
    public let minimumSystemVersion: String
    public let architectures: [String]
    public let channel: String
    public let archiveFormat: String  // "apple-archive" or "zip"
    public let bundleManifestSHA256: String
    public let releaseNotesTarget: String?
    public let critical: Bool?
    public let rollout: Rollout?

    public struct Rollout: Codable, Equatable, Sendable, Hashable {
        public let percentage: Int
        public let seed: String

        public init(percentage: Int, seed: String) {
            self.percentage = percentage
            self.seed = seed
        }
    }

    public init(
        productID: String,
        bundleIdentifier: String,
        bundleVersion: Int,
        shortVersion: String,
        minimumSystemVersion: String,
        architectures: [String],
        channel: String,
        archiveFormat: String,
        bundleManifestSHA256: String,
        releaseNotesTarget: String? = nil,
        critical: Bool? = nil,
        rollout: Rollout? = nil
    ) {
        self.productID = productID
        self.bundleIdentifier = bundleIdentifier
        self.bundleVersion = bundleVersion
        self.shortVersion = shortVersion
        self.minimumSystemVersion = minimumSystemVersion
        self.architectures = architectures
        self.channel = channel
        self.archiveFormat = archiveFormat
        self.bundleManifestSHA256 = bundleManifestSHA256
        self.releaseNotesTarget = releaseNotesTarget
        self.critical = critical
        self.rollout = rollout
    }
}

// MARK: - Delegation

/// A delegation from one role to another.
public struct TUFDelegation: Codable, Equatable, Sendable, Hashable {
    public let role: String  // delegated role name (e.g., "com.example.myapp-stable")
    public let keyids: [String]
    public let threshold: Int
    public let terminating: Bool
    public let paths: [String]  // glob patterns

    public init(role: String, keyids: [String], threshold: Int, terminating: Bool, paths: [String]) {
        self.role = role
        self.keyids = keyids
        self.threshold = threshold
        self.terminating = terminating
        self.paths = paths
    }
}

/// Delegations section of a Targets metadata.
public struct TUFDelegations: Codable, Equatable, Sendable, Hashable {
    public let keys: [String: TUFKey]?  // optional inline keys
    public let roles: [TUFDelegation]

    public init(keys: [String: TUFKey]?, roles: [TUFDelegation]) {
        self.keys = keys
        self.roles = roles
    }
}

// MARK: - Targets Metadata

/// Targets metadata describes the available target files and any delegations.
public struct TUFTargetsMetadata: Codable, Equatable, Sendable, Hashable {
    public let _type: String  // "Targets"
    public let specVersion: String  // "1.0"
    public let version: Int
    public let expires: String  // ISO 8601
    public let targets: [String: TUFTargetInfo]
    public let delegations: TUFDelegations?

    public init(
        version: Int,
        expires: String,
        targets: [String: TUFTargetInfo],
        delegations: TUFDelegations? = nil
    ) {
        self._type = "Targets"
        self.specVersion = "1.0"
        self.version = version
        self.expires = expires
        self.targets = targets
        self.delegations = delegations
    }
}

// MARK: - Size Limits

/// Per SPEC.md §6 metadata size limits.
public enum MetadataSizeLimits {
    public static let root: Int = 16 * 1024           // 16 KB
    public static let timestamp: Int = 4 * 1024       // 4 KB
    public static let snapshot: Int = 16 * 1024       // 16 KB
    public static let targets: Int = 64 * 1024        // 64 KB
    public static let delegated: Int = 64 * 1024      // 64 KB
    public static let totalMetadataFetch: Int = 100 * 1024  // 100 KB

    public static func limit(for role: MetadataRole) -> Int {
        switch role {
        case .root: return root
        case .timestamp: return timestamp
        case .snapshot: return snapshot
        case .targets: return targets
        case .delegatedTargets: return delegated
        }
    }
}
