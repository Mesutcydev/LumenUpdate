# Lumen Update — Key Management

**Version:** 0.1 (Phase 0)
**Date:** 2026-07-31
**Status:** Accepted

This document specifies the key hierarchy, key sources, rejected practices, and key management procedures for the Lumen Update framework. All keys are Ed25519 signing keys.

---

## 1. Key Hierarchy

Lumen uses the standard TUF four-role key hierarchy with Lumen-specific key counts and roles.

### 1.1 Root Keys
- **Count:** 3
- **Threshold:** 2-of-3
- **Storage:** Offline hardware (YubiKey, smart card, or air-gapped machine)
- **Lifetime:** 1 year (recommended), rotated annually
- **Purpose:** Sign root metadata; sign root rotation
- **Trust:** Highest. Root keys are the trust anchor. Loss or compromise of root keys requires a full re-bootstrapping.

### 1.2 Targets Keys
- **Count:** 2
- **Threshold:** 1-of-2
- **Storage:** Offline, held by release engineers
- **Lifetime:** 1 year, rotated on personnel change
- **Purpose:** Sign targets metadata and delegated role metadata
- **Trust:** High. Compromise allows publishing malicious releases.

### 1.3 Snapshot Keys
- **Count:** 1
- **Threshold:** 1-of-1
- **Storage:** Online, CI runner with restricted access
- **Lifetime:** 90 days, rotated quarterly
- **Purpose:** Sign snapshot metadata
- **Trust:** Medium. Compromise allows serving stale snapshots but not new targets.

### 1.4 Timestamp Keys
- **Count:** 1
- **Threshold:** 1-of-1
- **Storage:** Online, CI runner with restricted access
- **Lifetime:** 7 days, rotated weekly
- **Purpose:** Sign timestamp metadata
- **Trust:** Low (short-lived). Compromise allows claiming "no new updates" for up to one week, but cannot publish new targets.

### 1.5 Default Solo-Developer Profile

The CLI may offer a simpler solo-developer profile with a single key for all roles. This profile has weaker compromise resilience and MUST be documented as such.

**Solo Profile:**
- Root: 1-of-1
- Targets: 1-of-1
- Snapshot: 1-of-1
- Timestamp: 1-of-1
- **Total:** 1 key

The CLI MUST display a clear warning when generating a solo profile: "A single-key configuration provides no defense against key compromise. Consider using a multi-key configuration for production releases."

---

## 2. Allowed Key Sources

The CLI and tools MUST support the following key sources:

### 2.1 macOS Keychain
- Stored as a generic password item
- Keychain item name: `com.lumenupdate.signing.<keyID>`
- Access control: requires user authentication
- Retrieval: `security find-generic-password`

### 2.2 Encrypted Local Key File
- File format: age-encrypted or GPG-encrypted private key
- Path: `~/.lumen/keys/<keyID>.key.enc`
- Decryption key: derived from passphrase or hardware token
- File permissions: 0600

### 2.3 CI Secret Provider
- GitHub Actions Secrets, GitLab CI Variables, or environment variables
- Variable name: `LUMEN_SIGNING_KEY_<role>`
- Value: base64-encoded private key
- Access: only available to specific CI jobs

### 2.4 Interactive Standard Input
- Private key is piped or typed at the CLI prompt
- Used for one-time signing operations
- Not persisted to disk

### 2.5 Offline Removable Storage
- USB drive, SD card, or hardware security module
- Read-only after initial write
- Used for root keys and other high-value keys

---

## 3. Rejected Practices (Hard Rules)

The following practices are FORBIDDEN and MUST be rejected by the CLI with a clear error message:

### 3.1 Private Key as Command Argument
```
$ lumen sign --private-key <hex> metadata.json
ERROR: Passing a private key as a command argument is forbidden.
        Use --key-source keychain, --key-source file, or stdin.
```
Rationale: Command arguments are visible in process listings, shell history, and logs.

### 3.2 Private Key Stored Beside the Repository
The repository directory MUST NOT contain private keys. The CLI MUST refuse to sign if a private key file is found in the repository tree.
```
$ lumen sign metadata.json
ERROR: Private key file detected at ./keys/targets.key.
        Move the key to your keychain or ~/.lumen/keys/.
```
Rationale: Repository contents are often backed up, synced, and shared.

### 3.3 Private Key Committed to Git
The CLI MUST check for `.gitignore` entries for `*.key`, `*.pem`, `keys/`, etc. If a key file is tracked in git, the CLI MUST refuse to proceed.
```
$ lumen sign metadata.json
ERROR: Private key file targets.key is tracked in git.
        Remove it from tracking and add to .gitignore.
```
Rationale: Git history is permanent.

### 3.4 Private Key Printed in Logs
The CLI MUST redact private keys from all log output, even at debug verbosity.
```
[DEBUG] Signing with key id=abc123, public=MCowBQYDK2VwAyEA...
[DEBUG] Private key: <redacted>
```
Rationale: Logs are often shipped to centralized logging systems.

### 3.5 Private Key Embedded in the Application
The host application MUST contain only public keys (root metadata) and embedded LumenInstaller helper. Private keys are never embedded.
Rationale: The application bundle is distributed to all users.

---

## 4. Per-Key Metadata

Each key in the system MUST have the following metadata:

```json
{
  "keyID": "abc123...",
  "keytype": "ed25519",
  "scheme": "ed25519",
  "role": "root",
  "createdAt": "2026-01-15T00:00:00Z",
  "createdBy": "key-ceremony-2026-01-15",
  "status": "active",
  "rotatedFrom": null,
  "rotatedTo": "def456...",
  "revokedAt": null,
  "revokedReason": null,
  "storage": "yubikey-serial-12345",
  "recoveryProcedure": "docs/key-recovery/abc123.md"
}
```

Fields:
- **keyID:** SHA-256 hash of the public key, base64-encoded
- **keytype:** Always "ed25519" for Lumen
- **scheme:** Always "ed25519"
- **role:** "root", "targets", "snapshot", or "timestamp"
- **createdAt:** ISO 8601 timestamp
- **createdBy:** Reference to the key ceremony that created it
- **status:** "active", "rotated", or "revoked"
- **rotatedFrom:** keyID of the predecessor (if rotated)
- **rotatedTo:** keyID of the successor (if rotated)
- **revokedAt:** ISO 8601 timestamp (if revoked)
- **revokedReason:** Human-readable reason (if revoked)
- **storage:** Where the private key is stored
- **recoveryProcedure:** Path to recovery documentation

---

## 5. Key Rotation Procedures

### 5.1 Root Rotation
Root rotation is the most sensitive operation. It requires:
1. Generate new root key(s) on offline hardware
2. Create new root metadata with incremented version
3. Sign new root metadata with the OLD root keys (threshold of old keys, not new keys)
4. After publishing, optionally re-sign with new root keys
5. All clients automatically accept the new root when verified

**Procedure:** `lumen root rotate --new-key <keyID>`

### 5.2 Targets Rotation
1. Generate new targets key
2. Create new targets metadata signed by the OLD key
3. After clients have accepted the new key, the OLD key can be removed

**Procedure:** `lumen targets rotate --new-key <keyID>`

### 5.3 Snapshot Rotation
Automatic, no user action required. The CI runner generates a new key and re-signs snapshot metadata.

**Procedure:** `lumen snapshot rotate`

### 5.4 Timestamp Rotation
Automatic, rotated weekly. The CI runner generates a new key and re-signs timestamp metadata.

**Procedure:** `lumen timestamp rotate`

### 5.5 Overlap Period
When rotating targets, snapshot, or timestamp keys, the old key MUST remain valid for an overlap period to allow clients to update. Recommended overlap: 1 expiration period (e.g., 90 days for targets).

---

## 6. Key Recovery Procedures

### 6.1 Lost Root Key
If a root key is lost (not compromised):
- Use the remaining root keys (2-of-3 threshold) to sign a root rotation
- The new root metadata must include the new public key and be signed by the remaining old keys
- No security incident; proceed with normal rotation

### 6.2 Compromised Root Key
If a root key is compromised:
- **IMMEDIATE:** Treat as a security incident (see [INCIDENT_RESPONSE.md](./INCIDENT_RESPONSE.md))
- Use the remaining root keys to sign an emergency root rotation
- The rotation must explicitly revoke the compromised key
- Notify all users via release notes or security advisory
- Conduct a post-mortem

### 6.3 Lost Targets Key
If a targets key is lost:
- Use the second targets key (1-of-2) to sign a targets rotation
- No security incident if the loss is non-malicious

### 6.4 Compromised Targets Key
If a targets key is compromised:
- **IMMEDIATE:** Revoke the compromised key
- Use the second targets key (if still trusted) to sign a new targets metadata that does NOT include the compromised key
- If both keys are compromised, use the root to sign a new targets metadata
- Notify all users

### 6.5 Catastrophic Loss (All Root Keys Lost)
If all root keys are lost or compromised simultaneously:
- This is a trust anchor failure
- The Lumen client MUST refuse to update until a new root is manually installed
- A new application version with a new bundled root must be distributed out-of-band
- Users must manually approve the new application (Gatekeeper dialog)
- This is the bootstrapping problem; it is the reason root keys are stored on separate hardware

---

## 7. Key Ceremonies

A key ceremony is a documented, witnessed procedure for creating keys. Recommended steps:

1. **Preparation:** Document the ceremony, identify witnesses, prepare hardware
2. **Environment:** Air-gapped machine, no network connection, witnessed room
3. **Generation:** Generate keys on hardware tokens (YubiKey, smart card)
4. **Verification:** Verify public keys match across all tokens
5. **Backup:** Create encrypted backups stored in separate physical locations
6. **Metadata:** Record all key metadata in the key registry
7. **Testing:** Sign test metadata and verify
8. **Documentation:** Witnesses sign the ceremony document

The CLI provides `lumen key ceremony` to guide through this process.

---

## 8. CLI Commands

```bash
lumen key generate --role <root|targets|snapshot|timestamp>
lumen key list
lumen key import --source <keychain|file|stdin>
lumen key export --keyID <id> --destination <keychain|file>
lumen key rotate --role <role> --new-key <id>
lumen key revoke --keyID <id> --reason <reason>
```

---

## 9. Cross-References

- [THREAT_MODEL.md](./THREAT_MODEL.md) — Threats addressed by key management
- [SECURITY_INVARIANTS.md](./SECURITY_INVARIANTS.md) — Invariant 4: no version rollback, requires proper key rotation
- [INCIDENT_RESPONSE.md](./INCIDENT_RESPONSE.md) — Playbooks for compromised keys
- [SPEC.md](./SPEC.md) — Protocol details on signature thresholds and key IDs
