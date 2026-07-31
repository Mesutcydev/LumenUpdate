# Accountless Distribution Guide

**Lumen is not a Gatekeeper bypass.** Accountless mode provides publisher-key verification, not Apple verification.

---

## What "Accountless" Means

Accountless distribution means you can ship secure application updates **without an Apple Developer Program membership**. Lumen's Independent Mode uses:

- **TUF metadata** with Ed25519 signatures for update integrity
- **Target hashes** (SHA-256) for payload verification
- **Bundle manifests** for extracted content verification
- **Publisher-key verification** — the user trusts YOUR signing key, not Apple

This is NOT the same as Apple verification. Developer ID signing and notarization remain Apple trust mechanisms that require Apple Developer Program membership.

---

## What Users Will See

### First Install (Unsigned or Ad-hoc Signed App)

On macOS Ventura (13+) and later, users will see:

1. **Gatekeeper warning**: "App can't be opened because Apple cannot check it for malicious software."
2. **User action required**: Go to **System Settings → Privacy & Security**, scroll down, and click **"Open Anyway"**.
3. **Subsequent launches**: The app opens normally after the first approval.

On macOS Sonoma (14+) and later, the flow may differ:
- The "Open Anyway" button may appear directly in the Privacy & Security pane.
- Users may need to right-click (Control-click) the app and select "Open" from the context menu.

### Updates via Lumen

Once the app is installed and approved:
- Lumen verifies updates using the publisher's Ed25519 key (bundled in the app).
- The update is downloaded, verified, and installed transactionally.
- **No additional Gatekeeper dialogs** for updates installed by Lumen (the app is already approved).
- **Important**: This behavior needs clean-machine testing for every supported macOS release. Do not assume one approval covers all future unsigned replacements.

---

## What Lumen Does NOT Do

- **Does NOT bypass Gatekeeper.** Lumen never removes quarantine attributes or suppresses macOS security warnings.
- **Does NOT make unsigned apps "Apple-trusted".** Only Developer ID signing and notarization provide Apple trust.
- **Does NOT promise seamless first-install.** Users must manually approve unsigned/ad-hoc apps on first launch.
- **Does NOT guarantee one approval covers all updates.** Gatekeeper behavior varies by macOS version and must be tested.

---

## Trust Profiles

| Mode | Update Verification | Apple Verification | Gatekeeper Behavior |
|---|---|---|---|
| **Independent** | TUF + Ed25519 + SHA-256 | None | Warning on first launch; user must approve |
| **Apple Enhanced** | TUF + Ed25519 + SHA-256 + code signature + notarization | Developer ID | No warning (notarized) |
| **Managed** | Custom root trust | Optional | Depends on signing |

---

## Publisher Checklist for Accountless Distribution

1. **Generate signing keys**: `lumen key generate --role root`, `--role targets`, etc.
2. **Create root metadata**: `lumen root create ...`
3. **Bundle root.json** in your app's `Contents/Resources/`
4. **Embed LumenInstaller** helper in your app bundle
5. **Package your app**: `lumen package ./MyApp.app`
6. **Create a release**: `lumen release create ...`
7. **Publish**: `lumen publish --repository ./repo --destination <hosting>`
8. **Document first-install instructions** for your users (see below)

---

## First-Install Instructions (for your users)

Include these instructions on your download page:

> **Installing on macOS Ventura or later:**
>
> 1. Download the app.
> 2. Double-click to open. You'll see a warning: "Apple cannot check this app for malicious software."
> 3. Open **System Settings → Privacy & Security**.
> 4. Scroll down and click **"Open Anyway"** next to the app name.
> 5. Click **Open** in the confirmation dialog.
>
> The app will open normally. Future updates will install automatically without additional prompts.

---

## Clean-Machine Testing Matrix

Test on clean VMs for every supported macOS release:

| macOS Version | Unsigned App | Ad-hoc Signed | Developer ID | Notarized |
|---|---|---|---|---|
| 13.0 (Ventura) | Test | Test | Test | Test |
| 13.5 | Test | Test | Test | Test |
| 14.0 (Sonoma) | Test | Test | Test | Test |
| 14.5 | Test | Test | Test | Test |
| 15.0 (Sequoia) | Test | Test | Test | Test |

Record exact dialogs, button labels, and System Settings paths for each version.

---

## Cross-References

- [SPEC.md](./SPEC.md) — Lumen TUF Profile
- [THREAT_MODEL.md](./THREAT_MODEL.md) — What Lumen protects against
- [SECURITY_INVARIANTS.md](./SECURITY_INVARIANTS.md) — Invariant 10: quarantine never silently removed
- [ADR-005-accountless-trust.md](./ADR-005-accountless-trust.md) — Accountless mode rationale
