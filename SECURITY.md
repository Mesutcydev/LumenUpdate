# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | ✅        |
| 0.x     | ❌        |

## Reporting a Vulnerability

**Do NOT open a public GitHub issue for security vulnerabilities.**

### How to Report

1. **Email**: Send details to `security@lumenupdate.dev` (or the project maintainer's security contact).
2. **Encryption**: Use PGP/GPG if possible. The maintainer's public key is available on request.
3. **Include**:
   - Description of the vulnerability
   - Steps to reproduce
   - Affected version(s)
   - Potential impact
   - Suggested fix (if any)

### Response Timeline

- **Acknowledgement**: Within 48 hours
- **Initial assessment**: Within 7 days
- **Fix timeline**: Depends on severity
  - Critical: 7 days
  - High: 14 days
  - Medium: 30 days
  - Low: Next release

### Disclosure Policy

- We follow **coordinated disclosure**.
- We will work with you to understand and resolve the issue before any public disclosure.
- We will credit you in the security advisory (unless you prefer to remain anonymous).
- We aim to publish a security advisory for all confirmed vulnerabilities.

## Security Invariants

Lumen enforces 10 non-negotiable security invariants documented in [`Documentation/SECURITY_INVARIANTS.md`](./Documentation/SECURITY_INVARIANTS.md). A violation of any invariant is a critical security defect.

## Threat Model

See [`Documentation/THREAT_MODEL.md`](./Documentation/THREAT_MODEL.md) for the full threat model, including:
- Attacker capabilities (network, cryptographic, local)
- Trust boundaries
- Out-of-scope threats
- TUF-derived attack classes

## What Lumen Does NOT Protect Against

- Already-compromised Mac (kernel-level attacks)
- Modification of unsigned host application and embedded public keys
- Local administrator compromise
- Physical access to the machine
- Compromised build environment before signing

## Key Management

See [`Documentation/KEY_MANAGEMENT.md`](./Documentation/KEY_MANAGEMENT.md) for:
- Key hierarchy (root 2-of-3, targets 1-of-2, snapshot/timestamp online)
- Allowed and rejected key storage practices
- Rotation and recovery procedures

## Incident Response

See [`Documentation/INCIDENT_RESPONSE.md`](./Documentation/INCIDENT_RESPONSE.md) for playbooks covering:
- Compromised timestamp key
- Compromised targets key
- Compromised root key
- Compromised repository server
- Malicious release published

## Dependencies

Lumen has minimal dependencies:
- **swift-crypto** (apple/swift-crypto): Ed25519 and SHA-256 on Linux
- **swift-argument-parser** (apple/swift-argument-parser): CLI argument parsing (lumen CLI only)
- **CryptoKit** (Apple): Ed25519 and SHA-256 on macOS (system framework)
- **CommonCrypto** (Apple): SHA-256 on macOS (system framework)

All cryptographic operations use Apple's audited implementations. Lumen does NOT implement any cryptographic primitives directly.

## Fuzzing

Fuzzer harnesses are provided in `Fuzzers/`:
- `MetadataFuzzer`: TUF metadata parsing
- `ArchiveHeaderFuzzer`: Archive entry validation
- `PathNormalizationFuzzer`: Path traversal detection

These can be connected to libFuzzer or similar coverage-guided fuzzing engines.
