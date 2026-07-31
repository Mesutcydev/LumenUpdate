# Lumen Update — TUF Profile Specification

**Version:** 0.1 (Phase 0)
**Date:** 2026-07-31
**Status:** Accepted

This document defines the **Lumen TUF Profile** — a constrained, documented subset of [The Update Framework (TUF)](https://theupdateframework.io/) used by the Lumen Update framework. This specification is authoritative; all implementation MUST conform to it.

---

## 1. Overview

The Lumen TUF Profile implements the four required top-level TUF roles (Root, Targets, Snapshot, Timestamp) with Lumen-specific extensions for macOS application metadata. The profile is designed to be:

- **Compatible** with the TUF specification where possible
- **Constrained** to reduce the attack surface and implementation complexity
- **Documented** so independent implementers can build compatible clients
- **Auditable** for security review

### 1.1 Relationship to TUF Specification

This profile is a subset of [TUF Specification v1.0](https://theupdateframework.io/metadata/). It does NOT implement:
- Multi-repository consensus
- Hash bin delegation
- Succinct roles (full hash-based delegation is used instead)
- TAP (Transparent App Publishing) integration

It DOES implement all four required top-level roles, threshold signatures, key rotation, delegation, and standard TUF metadata fields.

### 1.2 Design Principles

1. **Simplicity over flexibility.** Every feature must justify its complexity.
2. **Defense in depth.** Multiple layers of verification (signature, hash, length, version, expiration).
3. **Auditability.** Every byte of metadata must be verifiable.
4. **Cross-platform compatibility.** CLI can run on macOS and Linux.

---

## 2. Roles and Metadata

### 2.1 Root Metadata

**File:** `metadata/<version>.root.json` (e.g., `1.root.json`, `2.root.json`)

**Schema:**
```json
{
  "_type": "Root",
  "spec_version": "1.0",
  "version": 1,
  "expires": "2027-07-31T00:00:00Z",
  "keys": {
    "<keyid>": {
      "keytype": "ed25519",
      "scheme": "ed25519",
      "keyval": {
        "public": "<base64-encoded-public-key>"
      }
    }
  },
  "roles": {
    "root": {
      "keyids": ["<keyid1>", "<keyid2>", "<keyid3>"],
      "threshold": 2
    },
    "snapshot": {
      "keyids": ["<keyid>"],
      "threshold": 1
    },
    "targets": {
      "keyids": ["<keyid1>", "<keyid2>"],
      "threshold": 1
    },
    "timestamp": {
      "keyids": ["<keyid>"],
      "threshold": 1
    }
  }
}
```

**Field Descriptions:**
- `_type`: MUST be `"Root"`.
- `spec_version`: MUST be `"1.0"`.
- `version`: Integer, monotonically increasing. MUST be > previous root version.
- `expires`: ISO 8601 timestamp. Recommended: 365 days from creation.
- `keys`: Map of keyid (SHA-256 of public key, base64) to key info.
- `roles`: Map of role name to keyids and threshold.

**Key ID Computation:**
```
keyid = base64(SHA-256(public_key_bytes))
```

**Signature Format:** The root metadata is signed by `threshold` of the root keys. The signature object is:
```json
{
  "keyid": "<keyid>",
  "sig": "<base64-encoded-signature>"
}
```

---

### 2.2 Timestamp Metadata

**File:** `metadata/timestamp.json` (only one version, always overwritten)

**Schema:**
```json
{
  "_type": "Timestamp",
  "spec_version": "1.0",
  "version": 42,
  "expires": "2026-08-01T00:00:00Z",
  "meta": {
    "snapshot.json": {
      "version": 8,
      "length": 1234,
      "hashes": {
        "sha256": "<base64-encoded-sha256>"
      }
    }
  }
}
```

**Field Descriptions:**
- `_type`: MUST be `"Timestamp"`.
- `version`: Integer, monotonically increasing. MUST be > previous timestamp version.
- `expires`: ISO 8601 timestamp. Recommended: 1 day from creation.
- `meta`: MUST contain exactly one entry: `snapshot.json`.

**Signed by:** Timestamp keys (1-of-1 by default).

**Expiration:** 1 day (short, to ensure freshness).

---

### 2.3 Snapshot Metadata

**File:** `metadata/<version>.snapshot.json` (e.g., `8.snapshot.json`)

**Schema:**
```json
{
  "_type": "Snapshot",
  "spec_version": "1.0",
  "version": 8,
  "expires": "2026-08-07T00:00:00Z",
  "meta": {
    "targets.json": {
      "version": 5,
      "length": 5678,
      "hashes": {
        "sha256": "<base64-encoded-sha256>"
      }
    },
    "delegated/com.example.myapp-stable.json": {
      "version": 3,
      "length": 2345,
      "hashes": {
        "sha256": "<base64-encoded-sha256>"
      }
    }
  }
}
```

**Field Descriptions:**
- `_type`: MUST be `"Snapshot"`.
- `version`: Integer, monotonically increasing.
- `expires`: ISO 8601 timestamp. Recommended: 7 days from creation.
- `meta`: Map of filename to version/length/hashes. MUST include `targets.json` and all delegated target files.

**Signed by:** Snapshot keys (1-of-1 by default).

---

### 2.4 Targets Metadata

**File:** `metadata/<version>.targets.json` (e.g., `8.targets.json`)

**Schema:**
```json
{
  "_type": "Targets",
  "spec_version": "1.0",
  "version": 5,
  "expires": "2026-10-29T00:00:00Z",
  "targets": {
    "sha256.<hash>.com.example.myapp-203-arm64.aar": {
      "length": 84219360,
      "hashes": {
        "sha256": "<base64-encoded-sha256>"
      },
      "custom": {
        "productID": "com.example.myapp",
        "bundleIdentifier": "com.example.myapp",
        "bundleVersion": 203,
        "shortVersion": "2.0.3",
        "minimumSystemVersion": "13.0",
        "architectures": ["arm64"],
        "channel": "stable",
        "archiveFormat": "apple-archive",
        "bundleManifestSHA256": "<base64-encoded-sha256>",
        "releaseNotesTarget": "notes/2.0.3.md",
        "critical": false,
        "rollout": {
          "percentage": 100,
          "seed": "release-203"
        }
      }
    }
  },
  "delegations": {
    "keys": {
      "<keyid>": {
        "keytype": "ed25519",
        "scheme": "ed25519",
        "keyval": {
          "public": "<base64-encoded-public-key>"
        }
      }
    },
    "roles": [
      {
        "role": "com.example.myapp-stable",
        "keyids": ["<keyid>"],
        "threshold": 1,
        "terminating": false,
        "paths": ["sha256.*.com.example.myapp-*-arm64.aar"]
      },
      {
        "role": "com.example.myapp-beta",
        "keyids": ["<keyid1>", "<keyid2>"],
        "threshold": 1,
        "terminating": false,
        "paths": ["sha256.*.com.example.myapp-*-arm64-beta.aar"]
      }
    ]
  }
}
```

**Field Descriptions:**
- `_type`: MUST be `"Targets"`.
- `version`: Integer, monotonically increasing.
- `expires`: ISO 8601 timestamp. Recommended: 90 days from creation.
- `targets`: Map of target path to TargetInfo.
- `delegations`: Optional. Map of delegation role to keys, threshold, and path patterns.

**Signed by:** Targets keys (1-of-2 by default).

---

### 2.5 Delegated Targets (Channels)

**File:** `metadata/delegated/<productID>-<channel>.json`

**Examples:**
- `metadata/delegated/com.example.myapp-stable.json`
- `metadata/delegated/com.example.myapp-beta.json`
- `metadata/delegated/com.example.myapp-nightly.json`

**Schema:** Same as Targets metadata, but typically without further delegations.

**Purpose:** Per-channel releases. A compromised nightly key CANNOT publish stable releases.

---

## 3. TargetInfo (Lumen Custom Metadata)

The `custom` object in TargetInfo contains Lumen-specific metadata:

```json
{
  "productID": "com.example.myapp",
  "bundleIdentifier": "com.example.myapp",
  "bundleVersion": 203,
  "shortVersion": "2.0.3",
  "minimumSystemVersion": "13.0",
  "architectures": ["arm64"],
  "channel": "stable",
  "archiveFormat": "apple-archive",
  "bundleManifestSHA256": "<base64-encoded-sha256>",
  "releaseNotesTarget": "notes/2.0.3.md",
  "critical": false,
  "rollout": {
    "percentage": 100,
    "seed": "release-203"
  }
}
```

**Field Descriptions:**

| Field | Type | Required | Description |
|---|---|---|---|
| `productID` | string | Yes | Unique product identifier |
| `bundleIdentifier` | string | Yes | macOS bundle identifier |
| `bundleVersion` | integer | Yes | Monotonic version (CFBundleVersion) |
| `shortVersion` | string | Yes | Display version (CFBundleShortVersionString) |
| `minimumSystemVersion` | string | Yes | Minimum macOS version (e.g., "13.0") |
| `architectures` | array | Yes | Supported architectures: ["arm64"], ["x86_64"], or ["arm64", "x86_64"] |
| `channel` | string | Yes | "stable", "beta", or "nightly" |
| `archiveFormat` | string | Yes | "apple-archive" (v1) or "zip" (future) |
| `bundleManifestSHA256` | string | Yes | SHA-256 of the bundle manifest (hex or base64) |
| `releaseNotesTarget` | string | No | Path to signed release notes |
| `critical` | boolean | No | If true, update is mandatory |
| `rollout` | object | No | Staged rollout configuration |
| `rollout.percentage` | integer | No | Percentage of users to update (0-100) |
| `rollout.seed` | string | No | Deterministic seed for rollout selection |

**Validation Rules:**
- `productID` MUST match the host application's product ID.
- `bundleIdentifier` MUST match the host application's bundle identifier.
- `bundleVersion` MUST be > the host application's current bundle version.
- `architectures` MUST include the host's architecture.
- `minimumSystemVersion` MUST be <= the host's macOS version.
- `channel` MUST match the host's configured channel.

---

## 4. Canonical JSON Serialization (RFC 8785 JCS)

All signed metadata MUST be canonicalized using **RFC 8785 JSON Canonicalization Scheme (JCS)** before signing and verification.

### 4.1 Canonicalization Rules

1. **Object keys** are sorted lexicographically by Unicode code point.
2. **No insignificant whitespace.** No spaces, no newlines, no indentation.
3. **Numbers** are serialized per ECMAScript:
   - Integers without leading zeros
   - No trailing zeros after decimal point
   - Use shortest representation that round-trips
4. **Strings** are UTF-8 encoded with JSON escaping:
   - Quote, backslash, and control characters escaped
   - Non-ASCII characters MAY be escaped as `\uXXXX` (optional but recommended)
5. **Arrays** preserve order.
6. **No duplicate keys.**

### 4.2 Example

Input:
```json
{
  "version": 5,
  "expires": "2026-10-29T00:00:00Z",
  "targets": {}
}
```

Canonical form:
```json
{"expires":"2026-10-29T00:00:00Z","targets":{},"version":5}
```

### 4.3 Implementation

Lumen uses a dedicated RFC 8785 JCS implementation (NOT `JSONEncoder`). The canonicalization function is:

```swift
public func canonicalJSON(_ value: Any) -> Data
```

**Test vectors:** See [Tests/Fixtures/test-vectors/](../Tests/Fixtures/test-vectors/) for canonicalization test cases.

---

## 5. Target Naming Convention

Target artifacts follow this naming convention:

```
sha256.<hash>.<productID>-<bundleVersion>-<arch>.<ext>
```

**Examples:**
- `sha256.abc123...com.example.myapp-203-arm64.aar`
- `sha256.def456...com.example.myapp-203-universal.aar`

**Components:**
- `sha256.`: Prefix indicating the file is named by its SHA-256 hash
- `<hash>`: SHA-256 hash of the file content (hex or base64)
- `<productID>`: Product identifier
- `<bundleVersion>`: Monotonic version number
- `<arch>`: Architecture: `arm64`, `x86_64`, or `universal`
- `<ext>`: File extension: `aar` (Apple Archive) or `zip`

**Rationale:** Hash-based naming ensures:
- The target path is bound to the content
- Immutable uploads (no overwrite of existing paths)
- Caching is safe

---

## 6. Metadata Size Limits

| Role | Max Size |
|------|----------|
| Root | 16 KB |
| Timestamp | 4 KB |
| Snapshot | 16 KB |
| Targets | 64 KB |
| Delegated Targets | 64 KB |
| **Total metadata fetch** | **100 KB** |

If any metadata file exceeds its limit, the client MUST reject it with `error(.metadataTooLarge)`.

---

## 7. Expiration Policies

| Role | Recommended Expiration | Rationale |
|------|------------------------|-----------|
| Root | 365 days | Long because requires user action to rotate |
| Targets | 90 days | Balance between freshness and key rotation overhead |
| Snapshot | 7 days | Must be refreshed weekly |
| Timestamp | 1 day | Short for freshness; prevents freeze attacks |
| Delegated | 14 days | Per-channel flexibility |

**Configurable clock skew tolerance:** Default 0 seconds. Clients MAY allow a small tolerance (e.g., 60 seconds) to account for clock drift, but this MUST be explicit and documented.

---

## 8. Verification Pipeline

The client MUST verify metadata in this order:

1. **Load bundled root metadata.** The first version of root metadata is bundled with the application and self-signed.

2. **Fetch and verify timestamp.json.**
   - Fetch `metadata/timestamp.json` over HTTPS
   - Verify size <= 4 KB
   - Canonicalize JSON (RFC 8785 JCS)
   - Verify each signature against root.trusted timestamp keys
   - Verify threshold met
   - Verify version > stored timestamp version (rollback check)
   - Verify not expired
   - Store new timestamp version

3. **Fetch and verify snapshot.json (version from timestamp).**
   - Construct filename: `<version>.snapshot.json`
   - Verify size matches timestamp.meta["snapshot.json"].length
   - Verify SHA-256 hash matches timestamp.meta["snapshot.json"].hashes.sha256
   - Verify size <= 16 KB
   - Verify each signature against root.trusted snapshot keys
   - Verify threshold met
   - Verify version > stored snapshot version
   - Verify not expired
   - Store new snapshot version

4. **Fetch and verify targets.json (version from snapshot).**
   - Construct filename: `<version>.targets.json`
   - Verify size matches snapshot.meta["targets.json"].length
   - Verify SHA-256 hash matches snapshot.meta["targets.json"].hashes.sha256
   - Verify size <= 64 KB
   - Verify each signature against root.trusted targets keys
   - Verify threshold met
   - Verify version > stored targets version
   - Verify not expired

5. **Fetch and verify delegated targets (if any).**
   - For each delegation in targets.json.delegations.roles:
     - Fetch the delegated metadata file (version from snapshot)
     - Verify size and hash against snapshot.meta
     - Verify signatures against delegation keys
     - Verify threshold met
     - Verify not expired

6. **Select target.**
   - Iterate targets in the appropriate delegated role
   - For each target, validate against host application profile:
     - productID match
     - bundleIdentifier match
     - bundleVersion > current
     - architectures include host arch
     - minimumSystemVersion <= host OS
     - channel match
   - Return the selected target

7. **Verify target hash and length.**
   - Target hash and length are verified AFTER download (streaming SHA-256)
   - These are enforced by the downloader, not the metadata verifier

---

## 9. Channel Delegation

The targets role delegates to per-channel roles:

| Delegated Role | Key Holder | Purpose |
|----------------|------------|---------|
| `<productID>-stable` | Release engineer | Production releases |
| `<productID>-beta` | Beta testers + release engineer | Beta releases |
| `<productID>-nightly` | CI automation | Nightly builds |

**Security property:** A compromised nightly key CANNOT publish stable releases because:
1. The nightly key is NOT in the delegation for the stable role
2. The snapshot metadata references the stable delegated metadata by version
3. The stable delegated metadata is signed by the release engineer's key

---

## 10. Signature Format

Ed25519 signatures over canonical JSON:

```json
{
  "keyid": "<keyid>",
  "sig": "<base64-encoded-ed25519-signature>"
}
```

**Computation:**
```
canonical = canonicalJSON(metadata_without_signatures)
signature = ed25519_sign(private_key, canonical)
```

**Verification:**
```
canonical = canonicalJSON(metadata_without_signatures)
is_valid = ed25519_verify(public_key, canonical, signature)
```

**Threshold verification:** The metadata is valid if at least `threshold` signatures from the trusted keyids are valid.

---

## 11. Cross-References

- [THREAT_MODEL.md](./THREAT_MODEL.md) — Attacks addressed by this protocol
- [SECURITY_INVARIANTS.md](./SECURITY_INVARIANTS.md) — Invariants enforced by the verifier
- [KEY_MANAGEMENT.md](./KEY_MANAGEMENT.md) — Key hierarchy and rotation
- [INCIDENT_RESPONSE.md](./INCIDENT_RESPONSE.md) — Emergency operations
- [ADR-001-tuf-profile.md](./ADR-001-tuf-profile.md) — Why full TUF vs TUF-lite
