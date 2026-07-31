# ADR-004: Embedded Installer Helper with Transaction Journal

**Status:** Accepted
**Date:** 2026-07-31
**Deciders:** Lumen Architecture Team

## Context

Application updates must be atomic: either the new version installs completely and reports healthy, or the old version remains usable. A failed mid-installation can leave the application unlaunchable, which is a critical user experience and security defect.

macOS provides `FileManager.replaceItem(at:withItemAt:backupItemName:options:resultingItemURL:)` for atomic file replacement on the same volume. This API:
- Replaces an item at a destination URL with a source item
- Optionally creates a backup of the original
- Preserves the original's resource forks and metadata
- Is atomic from the file system's perspective
- Returns the resulting item URL

However, the update process involves more than just file replacement:
1. The host application must download and verify the update
2. The host must terminate before the bundle is replaced (macOS may have files locked)
3. The replacement must be performed by a process that has write access to the destination
4. The new application must be verified to launch and function correctly
5. On failure, the old application must be restored

## Decision

Lumen uses an **embedded installer helper (`LumenInstaller`)** that is part of the host application bundle. The flow is:

```
Host Application
  1. Verifies TUF metadata and downloads update
  2. Stages update in private directory
  3. Verifies staged update (signature, hash, length, bundle manifest)
  4. Creates transaction journal with target bundle path
  5. Launches embedded LumenInstaller helper
  │
  ▼
LumenInstaller Helper
  6. Waits for host application termination
  7. Re-verifies staged update independently
  8. Creates backup of old bundle
  9. Replaces bundle via FileManager.replaceItem
  10. Launches candidate application with transaction ID
  11. Waits for health acknowledgement
  12. On health: deletes backup, commits transaction
  13. On failure: restores backup, marks transaction failed
```

**Key principle:** The installer helper is embedded in the host application bundle. It is **NEVER downloaded dynamically**. This prevents an attacker who controls the update server from replacing the installer itself.

## Consequences

### Positive
- **Atomic replacement** via `FileManager.replaceItem` ensures the file system is always in a consistent state.
- **Backup of old version** is preserved until the new version reports healthy.
- **Independent re-verification** by the helper enforces [SECURITY_INVARIANTS.md](../SECURITY_INVARIANTS.md) invariant 2.
- **Cannot replace arbitrary destination** enforces invariant 3 (destination is read from the transaction journal, not from CLI/env).
- **Health acknowledgement** ensures the new version actually works before the backup is deleted.
- **Crash recovery** via the transaction journal: on next launch, the helper or a recovery tool can detect an incomplete transaction and take corrective action.
- **No dynamic download** of the installer eliminates an attack vector.

### Negative
- **Larger application bundle** (includes the helper binary).
- **Process coordination complexity** (host termination handoff, health acknowledgement protocol).
- **Requires careful journal design** for crash recovery.
- **Helper must be a separate executable** (not a library) to run after the host terminates.
- **Race conditions** between host termination and helper launch must be handled.

## Alternatives Considered

### Alternative 1: Dynamically downloaded installer
**Description:** The host downloads the installer helper from the update server.

**Rejected because:**
- An attacker who controls the update server could replace the installer.
- The installer is no longer trusted by virtue of being in the original application.
- Violates the principle of "don't trust the network."
- Adds a separate verification step for the installer itself.

### Alternative 2: Self-replacing application
**Description:** The running application replaces its own bundle.

**Rejected because:**
- macOS may have files in the bundle locked while the application is running.
- The Code Directory Hash (CDHash) in the code signature is computed at load time; replacing signed files while running is fragile.
- No clear point at which to "commit" the transaction.
- Crash during self-replacement leaves the bundle in an unknown state.

### Alternative 3: External package manager (.pkg)
**Description:** Use macOS Installer (.pkg) to install updates.

**Rejected because:**
- Requires root authorization (out of scope for v1.0).
- Adds a separate trust chain (the package signature).
- More complex than necessary for a simple bundle replacement.
- pkg files are large and slow to install.

### Alternative 4: Sparkle-style relauncher in app bundle
**Description:** Bundle a relauncher tool in the app; the app quits, the relauncher replaces, then relaunches.

**Accepted as the basis** for the LumenInstaller helper, but with significant hardening:
- **Stricter verification:** LumenInstaller re-verifies everything; Sparkle's relauncher trusts the host.
- **Health acknowledgement:** Lumen waits for the new app to report healthy; Sparkle does not.
- **Transaction journal:** Lumen persists transaction state; Sparkle does not.
- **Atomic replacement:** Both use `FileManager.replaceItem` (Sparkle uses `NSFileManager` moveItemAtURL, which is less atomic).

## Implementation Details

### Transaction Journal Format

The transaction journal is a JSON file written to the user's Application Support directory:

```json
{
  "transactionID": "uuid",
  "hostBundlePath": "/Applications/MyApp.app",
  "candidatePath": "/private/var/.../staging/MyApp-2.0.3-arm64.aar",
  "candidateExtractedPath": "/private/var/.../staging/extracted",
  "backupPath": "/Applications/MyApp.app.backup.<uuid>",
  "createdAt": "2026-07-31T...",
  "state": "staged|replacing|launched|committed|rolledback",
  "expectedBundleVersion": 203
}
```

The journal is written BEFORE each state transition. On crash, the next launch of the helper (or a manual recovery tool) can read the journal and take corrective action.

### Health Acknowledgement Protocol

The updated application calls:

```swift
try await LumenHealth.reportHealthy(transactionID: "uuid")
```

This is an IPC call to the installer helper (via XPC or a local socket). The helper receives the health report and commits the transaction.

The health report is only considered valid if:
- The process PID matches the PID recorded when the candidate was launched
- The transaction ID matches
- The report is received within a timeout (e.g., 60 seconds)

On timeout or mismatch, the helper rolls back.

## References

- FileManager.replaceItem: https://developer.apple.com/documentation/foundation/filemanager/replaceitem
- [SECURITY_INVARIANTS.md](../SECURITY_INVARIANTS.md) — Invariants 2, 3, 6
- [SPEC.md](../SPEC.md) — Target metadata
- [THREAT_MODEL.md](../THREAT_MODEL.md) — Threats addressed
