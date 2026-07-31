# Lumen Update

> **Lumen is not a Gatekeeper bypass.** Accountless mode provides publisher-key verification, not Apple verification.

A secure, Swift-native macOS update framework that works with signed, ad-hoc-signed, or unsigned applications — without requiring an Apple Developer account. Lumen is a credible, product-level alternative to Sparkle built on a documented TUF profile.

## Status

**Release Marker:** `0.1 — Verify`

Phase 0 (Security Specification) and Phase 1 (Verify-Only Protocol Core) are complete. No downloader, installer, or UI yet — these are planned for Phases 2–6.

## Why Lumen?

Sparkle already supports Ed25519-signed update archives, pre-extraction verification, signed feeds, automatic updates, custom interfaces, sandboxed applications, and key rotation. Lumen differentiates through six product-level advantages:

1. **Accountless distribution as a first-class mode** — not an unsupported edge case.
2. **TUF-compatible repository security** — protection against rollback, freeze, mix-and-match, wrong-target, and compromised online-key attacks.
3. **Transactional installation with automatic rollback** — including health verification after relaunch.
4. **A restricted installer** — no arbitrary shell scripts, packages, root helpers, or destination paths.
5. **A modern Swift API and native SwiftUI experience** — structured concurrency, observable update states, `Sendable` models.
6. **A complete publisher workflow** — release packaging, signing, static hosting, migration, diagnostics, and key recovery.

## Trust Profiles

| Mode | Update verification | Apple verification | Intended use |
|---|---|---|---|
| **Independent** | TUF metadata, Ed25519 signatures, target hashes | None required | Indie developers, open-source apps, terminated Developer accounts |
| **Apple Enhanced** | Everything in Independent plus code-signature, Team ID, designated-requirement, notarization checks | Developer ID optional | Commercial apps with an active Apple account |
| **Managed** | Custom root trust, private repositories, mirrors, organizational policies | Optional | Internal tools and enterprise deployment |

## Hard Scope Boundary (v1.0)

Updates only: standard `.app` bundles, on local writable volumes, owned by the current user, full update archives, non-sandboxed apps, macOS 13+. Out of scope: `.pkg` installers, launch daemons, root authorization, system extensions, delta updates, iCloud/Dropbox paths, silent quarantine removal, disabling Gatekeeper.

## Repository Layout

```
LumenUpdate/
├── Package.swift
├── Sources/
│   ├── LumenCore/        # Shared types, errors, canonical JSON, base64url, SHA-256, trusted state
│   ├── LumenTUF/         # TUF metadata models, decoder, verifier, resolver, version tracker
│   ├── LumenCrypto/      # Ed25519 signature verification (CryptoKit on macOS)
│   └── LumenTesting/     # Test fixtures with real key generation
├── Tests/
│   └── ...               # 37 unit tests, 100% pass rate
├── Documentation/
│   ├── SPEC.md           # Lumen TUF Profile (authoritative protocol spec)
│   ├── THREAT_MODEL.md
│   ├── SECURITY_INVARIANTS.md
│   ├── KEY_MANAGEMENT.md
│   ├── INCIDENT_RESPONSE.md
│   └── ADR-*.md          # 5 architecture decision records
└── Tests/Fixtures/test-vectors/  # 22 signed protocol test vectors
```

## Building

Requires Swift 5.9+ and macOS 13+.

```bash
swift build
swift test
```

## Cryptography

- **Ed25519** for metadata and target-signing roles (CryptoKit on macOS, Swift Crypto on Linux)
- **SHA-256** for target files and extracted bundle contents
- **RFC 8785 JCS** canonical JSON for all signed metadata

## Security Invariants

The 10 non-negotiable security invariants are documented in [`Documentation/SECURITY_INVARIANTS.md`](./Documentation/SECURITY_INVARIANTS.md). Each is backed by a testable assertion.

## Phased Roadmap

- [x] **Phase 0** — Security specification (threat model, TUF profile, ADRs, test vectors)
- [x] **Phase 1** — Verify-only protocol core (TUF decoder, root bootstrap, signature verification, version tracking, expiration, delegation, target resolution, full pipeline, trusted state)
- [ ] Phase 2 — Publisher CLI and repository creation
- [ ] Phase 3 — Fault-tolerant downloader
- [ ] Phase 4 — Safe archive staging
- [ ] Phase 5 — Transactional installer and rollback
- [ ] Phase 6 — Public SDK and native UI
- [ ] Phase 7 — Accountless distribution and Sparkle migration
- [ ] Phase 8 — Security hardening
- [ ] Phase 9 — Stable 1.0

## License

TBD
