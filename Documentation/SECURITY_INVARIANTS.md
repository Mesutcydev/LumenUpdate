# Lumen Update — Security Invariants

**Version:** 0.1 (Phase 0)
**Date:** 2026-07-31
**Status:** Accepted

This document enumerates the 10 security invariants that the Lumen Update framework MUST enforce. Each invariant is derived from the [THREAT_MODEL.md](./THREAT_MODEL.md) and is backed by a testable assertion. A violation of any invariant is a critical security defect.

---

## Invariant 1: No Archive Extraction Before Complete Target Verification

**Statement:** The update archive MUST NOT be extracted, even partially, until the target's signature, hash, length, bundle manifest, and bundle metadata have all been verified against trusted TUF metadata.

**Rationale:** If extraction begins before verification, a malicious archive can write files outside the staging directory, create symlinks that resolve outside the bundle, or place setuid binaries. The archive is untrusted until the target metadata is verified.

**Testable Assertion:**
```
For any update flow:
  - The first call to AppleArchive.extract must occur AFTER
    target.verifySignature() == true
    AND target.verifyHash() == true
    AND target.verifyLength() == true
    AND bundleManifest.verifyHash() == true
  - Any failure in the above chain must abort before extract() is called
```

**Enforced In:** `LumenTUF/Verifier.swift`, `LumenArchive/Extractor.swift`

**Failure Mode:** Path traversal, symlink escape, setuid binary execution, disk exhaustion.

---

## Invariant 2: Installer Independently Repeats Verification

**Statement:** The LumenInstaller helper MUST independently re-verify the target's signature, hash, length, and bundle manifest after the host application has terminated. It MUST NOT trust the host application's "verified" result alone.

**Rationale:** Between the host's verification and the helper's replacement, an attacker could tamper with the staged update. The helper, as a separately-launched process, re-derives the trust decision from the persisted metadata and the staged bytes.

**Testable Assertion:**
```
For any install transaction:
  - Helper.verifyTarget() must be called BEFORE Helper.replaceBundle()
  - Helper.verifyTarget() must perform ALL of:
    - signature threshold check
    - hash check (SHA-256)
    - length check
    - bundle manifest hash check
  - Helper must NOT read or trust any "verified" flag from the host
```

**Enforced In:** `LumenInstall/Helper.swift`

**Failure Mode:** A malicious process that modifies the staged update between host termination and helper execution.

---

## Invariant 3: Installer Cannot Accept Arbitrary Destination

**Statement:** The LumenInstaller helper MUST only replace the application bundle whose path is recorded in the transaction journal. It MUST reject any attempt to specify a different destination.

**Rationale:** If the helper accepted an arbitrary destination, a compromised host or a malicious transaction could direct it to replace `/usr/bin/sudo` or any other path. The helper is restricted to the single bundle recorded at transaction creation.

**Testable Assertion:**
```
For any install transaction:
  - Helper.replaceBundle() must validate that
    transaction.targetPath == process.bundlePath
  - Any mismatch must abort with error "destinationMismatch"
  - Helper MUST NOT accept a destination parameter from CLI, env, or
    untrusted IPC; the destination is read from the transaction journal
    which is written by the trusted host
```

**Enforced In:** `LumenInstall/Helper.swift`, `LumenInstall/Transaction.swift`

**Failure Mode:** Replacement of an arbitrary path on the file system.

---

## Invariant 4: No Update May Lower the Last Trusted Metadata or Bundle Version

**Statement:** Once a client has accepted a version of any TUF role or a target's `bundleVersion`, the client MUST NOT accept a lower version from the same or any other repository, except via an explicit root rotation that is itself verified.

**Rationale:** Rollback attacks rely on tricking the client into accepting an older, known-vulnerable state. Version tracking per role and per product prevents this.

**Testable Assertion:**
```
For any update flow:
  - Verifier.verifyMetadata(role, newMeta) must reject newMeta.version
    <= trustedState.lastVersion(role)
  - Verifier.verifyTarget(target) must reject target.custom.bundleVersion
    <= trustedState.lastBundleVersion(productID)
  - Root rotation must increment the version AND be signed by the
    threshold of OLD root keys (not the new ones)
```

**Enforced In:** `LumenTUF/VersionTracker.swift`, `LumenTUF/Verifier.swift`

**Failure Mode:** Rollback to a vulnerable or malicious older version.

---

## Invariant 5: Expired Metadata Is an Explicit Freshness Failure, Not "No Updates Available"

**Statement:** When any role's metadata is expired (current time > `expires`), the client MUST treat this as an explicit freshness failure with a distinct error code and user-visible message. It MUST NOT silently treat expired metadata as "no updates available."

**Rationale:** Freeze attacks rely on the client accepting stale metadata as current. By making expiration an explicit, visible failure, the user is alerted and the client refuses to act on stale data.

**Testable Assertion:**
```
For any update flow:
  - Verifier.checkExpiration(role, metadata) must return
    .expired(now > metadata.expires) when applicable
  - The user-facing error must be distinguishable from "no updates"
  - The client must NOT proceed to target selection on expired metadata
  - Optional: a configurable clock skew tolerance (default: 0)
```

**Enforced In:** `LumenTUF/Expiration.swift`, `LumenTUF/Verifier.swift`

**Failure Mode:** Silent acceptance of stale metadata, leading to freeze attacks.

---

## Invariant 6: Previous App Remains Recoverable Until New App Reports Healthy

**Statement:** The installer MUST preserve the old application bundle as a backup in the same volume until the new application has launched and reported health. Only after explicit health acknowledgement is the backup deleted.

**Rationale:** If the new application crashes, is incompatible, or fails to launch, the user must be able to fall back to the old version. A failed update must never leave the system in a state where neither version is usable.

**Testable Assertion:**
```
For any install transaction:
  - Helper.replaceBundle() must create a backup of the old bundle
    BEFORE the replacement
  - Helper.deleteBackup() must only be called after
    Health.reportHealthy() has been received
  - On crash or timeout, the backup must remain on disk
  - A manual recovery command must be able to restore the backup
```

**Enforced In:** `LumenInstall/Helper.swift`, `LumenInstall/HealthCheck.swift`

**Failure Mode:** A failed update that leaves no recoverable version.

---

## Invariant 7: Failed Update Is Locally Blocked Until Newer Trusted Metadata or Explicit Retry

**Statement:** If an update fails (signature invalid, hash mismatch, install failure, crash before health acknowledgement), the client MUST NOT automatically retry the same target. It MUST block that specific target until newer trusted metadata is received OR the user explicitly requests a retry.

**Rationale:** Automatic retry of a known-bad update is a security and user-experience defect. The user must make an informed decision to retry.

**Testable Assertion:**
```
For any update flow:
  - On any verification or install failure, TrustedState.blockedTargets
    must be updated with {productID, targetHash, reason}
  - Verifier.selectTarget() must skip any target whose hash is in
    blockedTargets
  - The block is cleared when:
    - Newer metadata is received (different version) AND verified
    - User explicitly calls LumenUpdater.retryFailedUpdate()
```

**Enforced In:** `LumenCore/TrustedState.swift`, `LumenTUF/Verifier.swift`

**Failure Mode:** Repeated failed updates, user frustration, potential attack amplification.

---

## Invariant 8: Release Notes Are Signed Content; No Arbitrary HTML or JavaScript

**Statement:** Release notes are signed TUF target content. They MUST be rendered as plain text or restricted Markdown. The client MUST NOT execute JavaScript, load remote resources, or render arbitrary HTML from release notes.

**Rationale:** Release notes are an attack surface. A signed target could include `<script>` or `<iframe>` tags that execute when rendered. The renderer must sanitize all content.

**Testable Assertion:**
```
For any release notes display:
  - ReleaseNotesRenderer.render() must strip or escape:
    - <script> tags
    - event handlers (onclick, onerror, etc.)
    - javascript: URLs
    - <iframe>, <object>, <embed> tags
  - Only allow: headings, paragraphs, lists, links (with safe URLs),
    bold, italic, code blocks
  - Remote image loading must be optional and user-controlled
```

**Enforced In:** `LumenUpdateUI/ReleaseNotesRenderer.swift`

**Failure Mode:** XSS, malicious link serving, JavaScript execution in the host application.

---

## Invariant 9: Redirects Cannot Move Downloads to Unapproved Host

**Statement:** The downloader MUST enforce an allowed-host policy. A redirect to a host not in the target's signed `custom.allowedHosts` (or the default approved hosts) MUST be rejected.

**Rationale:** A compromised CDN or MITM attacker could redirect the download to attacker-controlled infrastructure. The target's host list is part of the signed metadata.

**Testable Assertion:**
```
For any download:
  - Downloader.followRedirect() must check the Location header's host
    against approvedHosts
  - approvedHosts is:
    - The original repository host (default)
    - Plus any hosts listed in target.custom.allowedHosts
  - Any redirect to a non-approved host must abort with error
    "unapprovedRedirect"
  - HTTPS is required; HTTP must be rejected in production
```

**Enforced In:** `LumenDownload/Downloader.swift`

**Failure Mode:** Download of a malicious payload from attacker-controlled server.

---

## Invariant 10: Quarantine and Provenance Never Silently Removed to Avoid Gatekeeper

**Statement:** Lumen MUST NOT remove quarantine attributes, xattrs, or provenance information from the staged or installed bundle. Any Gatekeeper interaction MUST be explicit and user-visible.

**Rationale:** Lumen is not a Gatekeeper bypass. Silently removing quarantine to avoid macOS warnings would deceive the user about the trust state of the application. The user must see and approve any Gatekeeper dialogs.

**Testable Assertion:**
```
For any install:
  - Installer MUST NOT call xattr -d com.apple.quarantine on the
    staged or installed bundle
  - Installer MUST NOT strip com.apple.provenance
  - Any Gatekeeper intervention must result in
    UpdateState.manualRecoveryRequired, not silent install
  - The UI must clearly indicate "this application is not Apple-
    notarized" if applicable
```

**Enforced In:** `LumenInstall/Helper.swift`, `LumenUpdateUI/UpdateReadyView.swift`

**Failure Mode:** Deceptive installation of untrusted code, loss of user agency.

---

## Summary Table

| # | Invariant | Primary Module | Test Location |
|---|---|---|---|
| 1 | No extraction before verification | LumenArchive | Tests/LumenArchiveTests/InvariantTests.swift |
| 2 | Installer independent re-verification | LumenInstall | Tests/LumenInstallTests/HelperTests.swift |
| 3 | No arbitrary destination | LumenInstall | Tests/LumenInstallTests/HelperTests.swift |
| 4 | No version rollback | LumenTUF | Tests/LumenTUFTests/VersionTrackerTests.swift |
| 5 | Expired = explicit failure | LumenTUF | Tests/LumenTUFTests/ExpirationTests.swift |
| 6 | Previous app recoverable | LumenInstall | Tests/LumenInstallTests/RollbackTests.swift |
| 7 | Failed update blocked | LumenCore | Tests/LumenCoreTests/TrustedStateTests.swift |
| 8 | Signed release notes only | LumenUpdateUI | Tests/LumenUpdateUITests/RendererTests.swift |
| 9 | No unapproved redirects | LumenDownload | Tests/LumenDownloadTests/RedirectPolicyTests.swift |
| 10 | No silent quarantine removal | LumenInstall | Tests/LumenInstallTests/QuarantineTests.swift |

---

## Cross-References

- [THREAT_MODEL.md](./THREAT_MODEL.md) — Source of these invariants
- [SPEC.md](./SPEC.md) — Protocol implementation
- [KEY_MANAGEMENT.md](./KEY_MANAGEMENT.md) — Key rotation supports invariants 4 and 7
- [INCIDENT_RESPONSE.md](./INCIDENT_RESPONSE.md) — What to do when an invariant is violated
