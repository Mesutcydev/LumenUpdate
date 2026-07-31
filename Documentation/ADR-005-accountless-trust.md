# ADR-005: Accountless Distribution via Publisher-Key Verification

**Status:** Accepted
**Date:** 2026-07-31
**Deciders:** Lumen Architecture Team

## Context

Many macOS developers do not have or do not want to use an Apple Developer ID. They may be:
- **Indie developers** who cannot justify the $99/year Apple Developer Program fee
- **Open-source maintainers** who distribute outside the Mac App Store
- **Developers whose Apple Developer Program membership has lapsed** (e.g., company dissolved, account terminated)
- **Hobbyists** who want to distribute small utilities

These developers still need secure application updates. Apple's Gatekeeper is a trust mechanism that requires Developer ID signing and notarization, but it is **not the only way to verify update integrity**.

Gatekeeper provides:
- Code signature verification (the binary is signed by a known Developer ID)
- Notarization verification (Apple has scanned the binary for malware)
- Quarantine attribute handling (downloaded files are quarantined)

Gatekeeper does NOT provide:
- Update integrity (Gatekeeper doesn't verify that an update is the "latest" or "correct" version)
- Rollback protection (Gatekeeper doesn't track versions)
- Key rotation (Gatekeeper keys are Apple's; developers cannot rotate them)
- Release channel separation (Gatekeeper doesn't distinguish stable from beta)

The cryptographic update protocol (TUF) provides all of these. Lumen's accountless mode uses **publisher-key verification**: the user trusts the publisher's signing key (bundled in the app), not Apple.

## Decision

Lumen supports three trust profiles, as defined in the master plan:

1. **Independent Mode** (accountless)
   - TUF metadata verification
   - Ed25519 signatures
   - Target hashes
   - Extracted bundle manifest verification
   - **No Apple verification required**

2. **Apple Enhanced Mode**
   - Everything in Independent Mode
   - Plus: code-signature verification
   - Plus: Team ID check
   - Plus: designated-requirement check
   - Plus: notarization check
   - Developer ID is **optional** (not required)

3. **Managed Mode**
   - Custom root trust
   - Private repositories
   - Organizational policies
   - Mirrors and staging

**Apple signing is an additional trust layer, never the foundation of the update protocol.**

Lumen's accountless mode is described as **"publisher-key verification"**, not Apple verification. Lumen does not promise that one Gatekeeper approval will automatically cover every later unsigned replacement; that behavior needs clean-machine testing for every supported macOS release.

## Consequences

### Positive
- **Indie developers can ship secure updates** without an Apple Developer Program membership.
- **Open-source applications can self-distribute** with TUF-grade security.
- **Developers with lapsed accounts** can continue distributing securely.
- **Privacy:** No Apple-mediated telemetry or tracking. The update protocol is end-to-end between publisher and user.
- **Works with ad-hoc signed applications** (signed with a developer's local key, not a Developer ID).
- **Works with unsigned applications** (the user is informed and must explicitly approve).
- **TUF protection** against rollback, freeze, mix-and-match, wrong-target, and key compromise attacks — independent of Apple.

### Negative
- **Gatekeeper will show warnings** for unsigned or ad-hoc-signed applications on first launch.
- **Users must approve unnotarized software** through Privacy & Security (the modern flow, not the old Control-click flow).
- **New users may not understand** "publisher-key verification" vs Apple verification.
- **Cannot promise "Apple-trusted"** for unsigned applications. Lumen is not a Gatekeeper bypass.
- **Documentation must be honest** about Gatekeeper behavior, which varies by macOS version.
- **Reputation risk:** If Lumen is associated with malware distribution (because it allows unsigned apps), legitimate developers may suffer. Lumen must be clear about the trust model.

## Alternatives Considered

### Alternative 1: Require Developer ID for all updates
**Description:** Lumen only works with Developer ID-signed applications.

**Rejected because:**
- Excludes indie developers and is anti-competitive.
- Apple's Developer Program is a business decision; developers should not be forced into it.
- Many open-source projects explicitly avoid Apple Developer Program membership.
- The TUF protocol provides strong security without Apple involvement.

### Alternative 2: Trick Gatekeeper into trusting unsigned apps
**Description:** Use undocumented APIs or hacks to bypass Gatekeeper.

**Rejected because:**
- Lumen is **not a Gatekeeper bypass**. This is dishonest and fragile.
- Apple actively patches bypass techniques, breaking the update flow.
- Could result in Lumen being flagged as malware by Apple's notarization service.
- Violates [SECURITY_INVARIANTS.md](../SECURITY_INVARIANTS.md) invariant 10: quarantine never silently removed.
- Undermines user trust and macOS security model.

### Alternative 3: Use a custom kernel extension to bypass signing
**Description:** Install a kernel extension (kext) that disables code signing checks.

**Rejected because:**
- Requires root authorization (out of scope for v1.0).
- Apple deprecated kexts in favor of system extensions, and system extensions still require approval.
- Adding a kext to the system is a major security risk.
- Apple would likely reject the app from notarization if it bundles a kext.

### Alternative 4: Ship only notarized binaries and require Apple ID
**Description:** Same as Alternative 1; use Apple Developer ID as the trust anchor.

**Rejected because:** Same reasons as Alternative 1.

### Alternative 5: Use a "blessed" notary service other than Apple
**Description:** Establish a third-party notary service that verifies and signs applications.

**Rejected for v1 because:**
- Requires building and maintaining a notary service.
- Requires users to trust the third party.
- Adds complexity and cost.
- May be added in a future phase as a Managed Mode feature.

## Communication Guidelines

Lumen's documentation and UI MUST be honest about the trust model:

### What Lumen Says
- "Lumen verifies updates using publisher-key verification. The publisher's signing key is bundled with the application."
- "Lumen protects against compromised update servers, network attacks, and rollback attacks."
- "For accountless distribution, users will see a Gatekeeper warning on first launch. This is expected. Approve the application through Privacy & Security."

### What Lumen Does NOT Say
- "Lumen bypasses Gatekeeper."
- "Lumen makes your application Apple-trusted."
- "Lumen suppresses macOS security warnings."
- "One approval covers all future updates." (Behavior varies by macOS version; needs clean-machine testing.)

### User-Facing Trust UI

The standard update UI separates trust indicators:

```
✓ Publisher verified (TUF metadata)
✓ Update signature valid (Ed25519)
✓ Repository metadata current (not expired)
— Apple Developer ID verified: not available (accountless mode)
— Apple notarization verified: not available (accountless mode)
```

This is NOT collapsed into a vague green "Secure" badge. Each trust check is shown separately.

## Migration from Developer ID

If a developer later obtains an Apple Developer ID, they can:
1. Sign the application with their Developer ID
2. Submit for notarization
3. Switch to Apple Enhanced Mode
4. The TUF trust chain is unchanged; Apple verification is added on top

The user does not need to reinstall the application; the next update will verify the new code signature.

## References

- [THREAT_MODEL.md](../THREAT_MODEL.md) — What Lumen protects against
- [SECURITY_INVARIANTS.md](../SECURITY_INVARIANTS.md) — Invariant 10: no silent quarantine removal
- [SPEC.md](../SPEC.md) — Protocol details
- [KEY_MANAGEMENT.md](../KEY_MANAGEMENT.md) — Publisher key management
- Apple Developer ID: https://developer.apple.com/support/developer-id/
