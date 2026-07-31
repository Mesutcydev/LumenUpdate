# Lumen Update — Threat Model

**Version:** 0.1 (Phase 0)
**Date:** 2026-07-31
**Status:** Accepted

This document defines the threat model for the Lumen Update framework. It establishes the attacker capabilities Lumen defends against, the trust boundaries within the system, and the threats that are explicitly out of scope.

---

## 1. Attacker Capabilities (In Scope)

Lumen MUST defend against the following attacker capabilities. These are the threat model that all security invariants and protocol decisions are derived from.

### 1.1 Network Adversary
An attacker who can:
- **Control the CDN or update server.** The HTTP origin serving `metadata/` and `targets/` is treated as fully adversarial. An attacker with server access may serve arbitrary metadata, any target payload, and arbitrary headers.
- **Control DNS or intercept HTTPS** (e.g., via a rogue CA, BGP hijack, or local network position). DNS responses and TLS termination may be under attacker control, but the attacker does NOT hold a valid CA-issued certificate for the publisher's domain *unless* the CA itself is compromised.
- **Replay old metadata.** The attacker may capture and replay previously served valid metadata, including expired or stale versions.
- **Serve infinite or oversized responses.** The attacker may stream arbitrarily large data in an attempt to exhaust disk space, memory, or time.
- **Redirect requests to unapproved hosts.** The attacker may attempt to move the client to attacker-controlled infrastructure even after the client has selected a target.

### 1.2 Cryptographic Adversary
An attacker who can:
- **Compromise a timestamp or snapshot key.** These are online keys and may be leaked from a CI runner or compromised automation host.
- **Forge signatures** with a key not in the trusted root. (This MUST be computationally infeasible given the use of Ed25519.)
- **Substitute a target with another valid file for the wrong product.** The attacker may try to confuse a client into installing a target that is validly signed but intended for a different product, channel, architecture, or version.

### 1.3 Local Adversary
An attacker who can:
- **Create malicious archive paths, symlinks, or duplicate entries.** An attacker who can influence the contents of a target archive (e.g., by compromising the build pipeline before signing) may attempt path traversal (`../`), symlink escape, or archive-bomb attacks.
- **Terminate the application or helper during any install transition.** The attacker (or a benign crash) may kill the host application or the LumenInstaller helper at any point during the install state machine.
- **Fill available disk space** to cause the installer to fail mid-transaction.
- **Race file-system operations with a local process.** A local process may attempt to swap files, replace the candidate directory, or tamper with the transaction journal.

---

## 2. Trust Boundaries

Lumen is built on a layered trust model. The following zones are defined:

```
┌────────────────────────────────────────────────────────┐
│  UNTRUSTED NETWORK ZONE                                │
│  - CDN, update server, DNS, HTTPS terminator          │
│  - All metadata and target bytes from the network      │
│  - Treated as adversarial                              │
└──────────────────────────┬─────────────────────────────┘
                           │ (signed metadata + targets)
                           ▼
┌────────────────────────────────────────────────────────┐
│  SEMI-TRUSTED REPOSITORY ZONE                          │
│  - Verified metadata (after signature threshold check)│
│  - Verified target hash (after hash check)             │
│  - Still subject to rollback, freeze, mix-and-match   │
│    checks before trust is upgraded                     │
└──────────────────────────┬─────────────────────────────┘
                           │ (verified metadata + target)
                           ▼
┌────────────────────────────────────────────────────────┐
│  TRUSTED LOCAL STATE ZONE                              │
│  - Persisted trusted root metadata                    │
│  - Persisted version map (per-role version numbers)   │
│  - Trusted key IDs (from root metadata)               │
│  - Application Support directory on local volume      │
└──────────────────────────┬─────────────────────────────┘
                           │ (trusted metadata)
                           ▼
┌────────────────────────────────────────────────────────┐
│  TRUSTED HOST APPLICATION                              │
│  - The application that bundles the initial root       │
│  - Embedded LumenInstaller helper                     │
│  - Public keys only (no private keys)                  │
└──────────────────────────┬─────────────────────────────┘
                           │ (install transaction)
                           ▼
┌────────────────────────────────────────────────────────┐
│  TRUSTED INSTALLER HELPER (LumenInstaller)             │
│  - Embedded in host application bundle                │
│  - NOT downloaded dynamically                         │
│  - Independently re-verifies before replacement        │
│  - Writes transaction journal before each transition  │
└────────────────────────────────────────────────────────┘
```

### 2.1 Zone Rules

- **Untrusted Network → Semi-Trusted Repository:** A byte becomes semi-trusted only after the corresponding metadata file passes signature threshold verification, version checks, and expiration checks.
- **Semi-Trusted Repository → Trusted Local State:** Metadata is only persisted to local state after all of the above plus rollback, mix-and-match, and freeze checks.
- **Trusted Local State → Host Application:** The host application bundles the initial root metadata. Compromise of the host application is a separate threat (see §4).
- **Host Application → Installer Helper:** The helper is trusted because it is part of the application bundle. If the application is unsigned, the user must approve it before first install; this is the publisher-key trust model.

---

## 3. What Lumen Cannot Protect Against (Out of Scope)

Lumen explicitly does NOT defend against:

- **An already-compromised Mac.** If the operating system or kernel is compromised, the attacker can read memory, intercept IPC, and bypass any application-level security.
- **Modification of the unsigned host application and its embedded public keys.** If the application is unsigned or ad-hoc-signed, an attacker who can write to the application bundle can replace the bundled root metadata and public keys. Lumen's accountless mode protects primarily against repository, network, and release-pipeline attacks — not local administrator compromise.
- **Local administrator compromise.** A user or process with root or administrator access can modify the application, the persisted trusted state, and the LumenInstaller helper. Lumen's security model assumes the user's account is not compromised.
- **Physical access to the machine.** An attacker with physical access can read the disk, modify firmware, or replace the application.
- **Compromise of the build environment before signing.** If the build pipeline is compromised before the publisher signs the metadata, the attacker can publish any release. Defense is in the build environment (CI hardening, reproducible builds, out-of-band review).

---

## 4. Attack Classes (TUF-Derived)

Lumen's protocol is derived from TUF, which formally addresses the following attack classes. For each, Lumen's defense is:

### 4.1 Rollback Attack
**Attack:** The attacker serves an older, validly-signed version of metadata to revert the client to a known-vulnerable state.
**Defense:** Each role's metadata has a `version` field. The client tracks the highest version it has accepted per role. Any metadata with a `version` <= the stored version is rejected.

### 4.2 Freeze Attack
**Attack:** The attacker serves a timestamp or snapshot with a very long expiration, then stops serving updates. The client believes the repository is current and never refreshes.
**Defense:** Short expiration times (timestamp: 1 day, snapshot: 7 days). The client treats expired metadata as an explicit failure, not "no updates available." The user is notified.

### 4.3 Endless Data Attack
**Attack:** The attacker serves an arbitrarily large metadata file in an attempt to exhaust memory or disk.
**Defense:** Hard size limits per role (root: 16 KB, timestamp: 4 KB, snapshot: 16 KB, targets: 64 KB, delegated: 64 KB). Total metadata fetch is capped at 100 KB.

### 4.4 Wrong-Target Attack
**Attack:** The attacker substitutes a target that is validly signed but intended for a different product, channel, architecture, or minimum macOS version.
**Defense:** The TargetInfo `custom` object contains `productID`, `bundleIdentifier`, `channel`, `architectures`, and `minimumSystemVersion`. The client rejects any target that does not match the host application's profile. Target path is bound to SHA-256 hash of the payload.

### 4.5 Mix-and-Match Attack
**Attack:** The attacker combines metadata from different repository snapshots to create a valid-looking repository that the client has never seen.
**Defense:** The snapshot metadata is signed and references the targets metadata by exact version. The client verifies that the targets.json version matches what the snapshot claims, and that the snapshot version matches what the timestamp claims. The version chain (timestamp → snapshot → targets) is verified end-to-end.

### 4.6 Key Compromise
**Attack:** The attacker compromises a key for one role (e.g., timestamp) and uses it to serve arbitrary metadata.
**Defense:** Threshold signatures (root: 2-of-3, targets: 1-of-2). Compromise of a single key is insufficient. Root key rotation is supported via signed root metadata version increment. Each role's key is rotated independently.

### 4.7 Arbitrary Key Attack
**Attack:** The attacker introduces a new key not in the trusted root and signs metadata with it.
**Defense:** All signatures must be from keyids present in the root metadata's `roles` section. Unknown keyids are rejected.

---

## 5. Out-of-Scope Threats (Explicitly Not Defended)

- **Compromise of Apple Developer ID infrastructure.** Apple Developer ID is an additional trust layer, not a foundation of Lumen. If Apple's signing infrastructure is compromised, the Apple Enhanced mode is affected, but the Independent mode is not.
- **macOS kernel-level attacks.** Lumen is an application-level framework.
- **Hardware implants.** Lumen assumes the hardware is not malicious.
- **Side-channel attacks on cryptographic operations.** CryptoKit and Swift Crypto are responsible for side-channel resistance; Lumen uses them correctly (constant-time comparisons where required for signature verification).
- **Social engineering of the user.** Lumen provides clear UI about what trust checks have passed, but cannot prevent a user from approving an obviously malicious update.

---

## 6. Threat Model Summary

| Threat | In Scope? | Lumen Defense |
|---|---|---|
| Compromised CDN | Yes | Signature threshold, hash verification, version tracking |
| Compromised DNS / HTTPS interception | Yes | TLS required in production, certificate validation |
| Replay of old metadata | Yes | Version tracking, rollback detection |
| Infinite metadata | Yes | Size limits, streaming parser |
| Compromised timestamp key | Yes | Short expiry, root rotation, incident response |
| Wrong-target substitution | Yes | Custom target metadata validation |
| Malicious archive | Yes | Path normalization, bundle manifest verification |
| Install-time termination | Yes | Transaction journal, atomic replacement, rollback |
| Disk full | Yes | Disk-space preflight |
| File-system race | Yes | Same-volume replacement, OS-level atomic ops |
| Compromised Mac | No | Out of scope |
| Modified unsigned host app | No | Out of scope (accountless trade-off) |
| Apple Developer ID compromise | Partial | Affects Apple Enhanced mode only |
| Kernel attack | No | Out of scope |

---

## 7. Cross-References

- [SECURITY_INVARIANTS.md](./SECURITY_INVARIANTS.md) — The 10 invariants derived from this threat model
- [SPEC.md](./SPEC.md) — Protocol specification that implements the defenses
- [KEY_MANAGEMENT.md](./KEY_MANAGEMENT.md) — Key ceremony and rotation procedures
- [INCIDENT_RESPONSE.md](./INCIDENT_RESPONSE.md) — Playbooks for when defenses are breached
