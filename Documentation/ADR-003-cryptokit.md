# ADR-003: CryptoKit and Swift Crypto for Cryptographic Operations

**Status:** Accepted
**Date:** 2026-07-31
**Deciders:** Lumen Architecture Team

## Context

Lumen needs cryptographic operations for:
- **Ed25519 signature verification** (TUF metadata and targets)
- **SHA-256 hashing** (target file integrity, bundle manifest integrity)
- **Key generation** (CLI for publisher keys)
- **Key import/export** (CLI for publisher key management)

The framework must run on:
- **macOS client** (the application being updated)
- **macOS CLI** (publisher tool for packaging, signing, publishing)
- **Linux CI** (cross-platform CI for the CLI)

Cryptographic implementations must be:
- **Audited** and formally verified
- **Constant-time** to prevent side-channel attacks
- **Well-maintained** with security updates
- **API-stable** for the long-term support window of Lumen

## Decision

- **macOS client:** Use Apple's **CryptoKit** framework.
- **CLI (cross-platform):** Use Apple's **Swift Crypto** package (open source, https://github.com/apple/swift-crypto).
- **Never implement cryptographic primitives directly.**

The LumenCrypto module provides a thin wrapper around these libraries to abstract the platform difference and provide a consistent API.

## Consequences

### Positive
- **Both implementations are maintained by Apple** and formally audited.
- **CryptoKit uses hardware-accelerated primitives** where available (e.g., AES-NI, ARMv8 crypto extensions).
- **Swift Crypto is API-compatible with CryptoKit** (largely), making the wrapper thin.
- **No risk of subtle cryptographic bugs** in custom code.
- **Cross-platform CI can run on Linux** using Swift Crypto.
- **Long-term support** from Apple for both implementations.

### Negative
- **Dependency on Apple's cryptographic implementations.** If Apple deprecates CryptoKit or Swift Crypto, Lumen must adapt.
- **Swift Crypto may lag behind CryptoKit** in some features (though Ed25519 and SHA-256 are well-supported in both).
- **Cannot use other cryptographic libraries** without good reason (e.g., for post-quantum algorithms).
- **Swift Crypto is not audited to the same level as CryptoKit** (it uses BoringSSL under the hood on Linux, which is audited, but the Swift wrapper is less mature).

## Alternatives Considered

### Alternative 1: OpenSSL
**Description:** Use OpenSSL directly via C interop.

**Rejected because:**
- C library with a long history of memory-safety vulnerabilities.
- Requires careful FFI integration, which is error-prone in Swift.
- Constant-time guarantees have varied across OpenSSL versions.
- Adds a large dependency (OpenSSL is ~1 MB).
- License complexity (OpenSSL/Apache License).

### Alternative 2: BoringSSL
**Description:** Use Google's BoringSSL, a fork of OpenSSL.

**Rejected because:**
- Same C library issues as OpenSSL.
- Not designed for easy distribution (Google uses it internally).
- Not available as a Swift package.

### Alternative 3: libsodium
**Description:** Use libsodium via SwiftSodium or similar wrapper.

**Rejected because:**
- Another C library, adds dependency surface.
- Not maintained by a major platform vendor.
- Less integration with Apple's security features.

### Alternative 4: Custom Ed25519 implementation
**Description:** Implement Ed25519 from scratch in Swift.

**Rejected because:**
- Never implement cryptographic primitives. Subtle bugs are catastrophic.
- Side-channel resistance is extremely difficult to get right.
- No formal verification.
- Maintenance burden for the Lumen team.

### Alternative 5: Use CommonCrypto (deprecated)
**Description:** Use Apple's older CommonCrypto library.

**Rejected because:**
- Deprecated in favor of CryptoKit.
- No Ed25519 support.
- C API, not idiomatic Swift.

## Implementation Notes

The LumenCrypto module provides:

```swift
public protocol Signing {
    func sign(_ data: Data, with key: SigningKey) throws -> Data
    func verify(_ signature: Data, of data: Data, with publicKey: VerifyingKey) throws -> Bool
}

public protocol Hashing {
    func sha256(_ data: Data) -> Data
    func sha256(stream: InputStream) throws -> Data
}
```

On Apple platforms, these are implemented using CryptoKit. On Linux, they use Swift Crypto. The public API is identical.

## References

- CryptoKit: https://developer.apple.com/documentation/cryptokit
- Swift Crypto: https://github.com/apple/swift-crypto
- [KEY_MANAGEMENT.md](../KEY_MANAGEMENT.md) — Key sources and procedures
- [SECURITY_INVARIANTS.md](../SECURITY_INVARIANTS.md) — Invariants related to crypto
