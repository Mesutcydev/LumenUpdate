// MetadataDecoder.swift
// Strict TUF metadata decoder with canonical JSON support.
//
// Per SPEC.md, all signed metadata MUST be decoded from canonical JSON (RFC 8785 JCS).
// The decoder takes raw bytes, enforces size limits, and produces a parsed metadata
// value plus the canonical bytes that should be used for signature verification.

import Foundation

/// Result of decoding metadata: the parsed value plus the canonical bytes
/// that were used (or should be used) for signature verification.
public struct DecodedMetadata<T: Codable & Sendable>: Sendable {
    public let metadata: T
    public let canonicalBytes: Data
    public let size: Int

    public init(metadata: T, canonicalBytes: Data) {
        self.metadata = metadata
        self.canonicalBytes = canonicalBytes
        self.size = canonicalBytes.count
    }
}

public enum MetadataDecoder {

    // MARK: - Root

    /// Decode root metadata from raw bytes, enforcing size limits.
    public static func decodeRoot(_ data: Data) throws -> DecodedMetadata<TUFRootMetadata> {
        try enforceSize(role: .root, data: data)
        let canonical = try canonicalizeJSONBytes(data)
        let metadata = try decodeFromCanonicalJSON(TUFRootMetadata.self, from: canonical)
        try validateRoot(metadata)
        return DecodedMetadata(metadata: metadata, canonicalBytes: canonical)
    }

    private static func validateRoot(_ meta: TUFRootMetadata) throws {
        guard meta._type == "Root" else {
            throw LumenError.invalidMetadataFormat("Expected _type 'Root', got '\(meta._type)'")
        }
        guard meta.specVersion == "1.0" else {
            throw LumenError.invalidMetadataFormat("Unsupported spec_version '\(meta.specVersion)', expected '1.0'")
        }
        guard meta.version >= 1 else {
            throw LumenError.invalidVersion("Root version must be >= 1, got \(meta.version)")
        }
        // Verify all referenced keyids exist in the keys map
        for (roleName, roleDef) in [
            ("root", meta.roles.root),
            ("snapshot", meta.roles.snapshot),
            ("targets", meta.roles.targets),
            ("timestamp", meta.roles.timestamp),
        ] {
            for keyid in roleDef.keyids {
                guard meta.keys[keyid] != nil else {
                    throw LumenError.invalidMetadataFormat("Role \(roleName) references unknown keyid \(keyid)")
                }
            }
            guard roleDef.threshold >= 1, roleDef.threshold <= roleDef.keyids.count else {
                throw LumenError.invalidMetadataFormat("Role \(roleName) has invalid threshold \(roleDef.threshold) for \(roleDef.keyids.count) keys")
            }
        }
    }

    // MARK: - Timestamp

    public static func decodeTimestamp(_ data: Data) throws -> DecodedMetadata<TUFTimestampMetadata> {
        try enforceSize(role: .timestamp, data: data)
        let canonical = try canonicalizeJSONBytes(data)
        let metadata = try decodeFromCanonicalJSON(TUFTimestampMetadata.self, from: canonical)
        guard metadata._type == "Timestamp" else {
            throw LumenError.invalidMetadataFormat("Expected _type 'Timestamp', got '\(metadata._type)'")
        }
        guard metadata.meta["snapshot.json"] != nil else {
            throw LumenError.missingField("timestamp.meta.snapshot.json")
        }
        return DecodedMetadata(metadata: metadata, canonicalBytes: canonical)
    }

    // MARK: - Snapshot

    public static func decodeSnapshot(_ data: Data) throws -> DecodedMetadata<TUFSnapshotMetadata> {
        try enforceSize(role: .snapshot, data: data)
        let canonical = try canonicalizeJSONBytes(data)
        let metadata = try decodeFromCanonicalJSON(TUFSnapshotMetadata.self, from: canonical)
        guard metadata._type == "Snapshot" else {
            throw LumenError.invalidMetadataFormat("Expected _type 'Snapshot', got '\(metadata._type)'")
        }
        guard metadata.meta["targets.json"] != nil else {
            throw LumenError.missingField("snapshot.meta.targets.json")
        }
        return DecodedMetadata(metadata: metadata, canonicalBytes: canonical)
    }

    // MARK: - Targets

    public static func decodeTargets(_ data: Data, isDelegated: Bool = false) throws -> DecodedMetadata<TUFTargetsMetadata> {
        let role: MetadataRole = isDelegated ? .delegatedTargets : .targets
        try enforceSize(role: role, data: data)
        let canonical = try canonicalizeJSONBytes(data)
        let metadata = try decodeFromCanonicalJSON(TUFTargetsMetadata.self, from: canonical)
        guard metadata._type == "Targets" else {
            throw LumenError.invalidMetadataFormat("Expected _type 'Targets', got '\(metadata._type)'")
        }
        return DecodedMetadata(metadata: metadata, canonicalBytes: canonical)
    }

    // MARK: - Signed Envelope

    /// Decode a signed envelope (signatures + signed payload) from canonical bytes.
    /// The canonical bytes used to verify signatures are the canonical encoding of
    /// ONLY the `signed` object (not the entire envelope).
    public static func decodeSignedRoot(_ data: Data) throws -> DecodedMetadata<TUFSigned<TUFRootMetadata>> {
        try enforceSize(role: .root, data: data)
        let canonical = try canonicalizeJSONBytes(data)
        let envelope = try decodeFromCanonicalJSON(TUFSigned<TUFRootMetadata>.self, from: canonical)
        try validateRoot(envelope.signed)
        return DecodedMetadata(metadata: envelope, canonicalBytes: canonical)
    }

    public static func decodeSignedTimestamp(_ data: Data) throws -> DecodedMetadata<TUFSigned<TUFTimestampMetadata>> {
        try enforceSize(role: .timestamp, data: data)
        let canonical = try canonicalizeJSONBytes(data)
        let envelope = try decodeFromCanonicalJSON(TUFSigned<TUFTimestampMetadata>.self, from: canonical)
        guard envelope.signed._type == "Timestamp" else {
            throw LumenError.invalidMetadataFormat("Expected _type 'Timestamp'")
        }
        return DecodedMetadata(metadata: envelope, canonicalBytes: canonical)
    }

    public static func decodeSignedSnapshot(_ data: Data) throws -> DecodedMetadata<TUFSigned<TUFSnapshotMetadata>> {
        try enforceSize(role: .snapshot, data: data)
        let canonical = try canonicalizeJSONBytes(data)
        let envelope = try decodeFromCanonicalJSON(TUFSigned<TUFSnapshotMetadata>.self, from: canonical)
        guard envelope.signed._type == "Snapshot" else {
            throw LumenError.invalidMetadataFormat("Expected _type 'Snapshot'")
        }
        return DecodedMetadata(metadata: envelope, canonicalBytes: canonical)
    }

    public static func decodeSignedTargets(_ data: Data, isDelegated: Bool = false) throws -> DecodedMetadata<TUFSigned<TUFTargetsMetadata>> {
        let role: MetadataRole = isDelegated ? .delegatedTargets : .targets
        try enforceSize(role: role, data: data)
        let canonical = try canonicalizeJSONBytes(data)
        let envelope = try decodeFromCanonicalJSON(TUFSigned<TUFTargetsMetadata>.self, from: canonical)
        guard envelope.signed._type == "Targets" else {
            throw LumenError.invalidMetadataFormat("Expected _type 'Targets'")
        }
        return DecodedMetadata(metadata: envelope, canonicalBytes: canonical)
    }

    // MARK: - Helpers

    private static func enforceSize(role: MetadataRole, data: Data) throws {
        if data.isEmpty {
            throw LumenError.metadataEmpty(role: role.rawValue)
        }
        let limit = MetadataSizeLimits.limit(for: role)
        if data.count > limit {
            throw LumenError.metadataTooLarge(role: role.rawValue, size: data.count, limit: limit)
        }
    }

    /// Parse JSON bytes into Any, canonicalize, and return canonical bytes.
    private static func canonicalizeJSONBytes(_ data: Data) throws -> Data {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw LumenError.invalidJSON("\(error)")
        }
        do {
            return try CanonicalJSON.encode(value)
        } catch {
            throw LumenError.invalidJSON("\(error)")
        }
    }

    /// Decode a Codable type from canonical JSON bytes.
    private static func decodeFromCanonicalJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw LumenError.invalidJSON("\(error)")
        }
    }

    /// Produce canonical bytes for a signed metadata object (the `signed` field only).
    /// Uses the same CanonicalJSON encoder that the publisher uses, so signing
    /// and verification always operate on identical bytes.
    public static func canonicalizeForSigning<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let raw = try encoder.encode(value)
        let parsed = try JSONSerialization.jsonObject(with: raw, options: [])
        return try CanonicalJSON.encode(parsed)
    }
}
