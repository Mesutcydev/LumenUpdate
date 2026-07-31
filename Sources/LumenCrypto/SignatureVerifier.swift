// SignatureVerifier.swift
// Ed25519 signature verification with threshold support.
//
// Wraps CryptoKit (Apple platforms) and Swift Crypto (Linux) to provide
// a uniform Ed25519 verification API. All verifications use constant-time
// comparison. This module has no dependency on TUF types; it works with
// raw bytes and keyid strings.

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
import Crypto  // Swift Crypto (cross-platform)

/// A single signature over canonical bytes, identified by keyid.
public struct RawSignature: Sendable, Equatable, Hashable {
    public let keyid: String
    public let signature: Data  // 64 bytes for Ed25519

    public init(keyid: String, signature: Data) {
        self.keyid = keyid
        self.signature = signature
    }
}

/// A public key with its keyid.
public struct RawPublicKey: Sendable, Equatable, Hashable {
    public let keyid: String
    public let keyData: Data  // 32 bytes for Ed25519
    public let keytype: String  // "ed25519"
    public let scheme: String   // "ed25519"

    public init(keyid: String, keyData: Data, keytype: String = "ed25519", scheme: String = "ed25519") {
        self.keyid = keyid
        self.keyData = keyData
        self.keytype = keytype
        self.scheme = scheme
    }
}

public enum SignatureVerifier {

    /// Verify a single Ed25519 signature over canonical bytes.
    public static func verify(
        signature: Data,
        canonicalBytes: Data,
        publicKey: Data
    ) throws -> Bool {
        guard publicKey.count == 32 else {
            throw LumenError.cryptoFailure("Ed25519 public key must be 32 bytes, got \(publicKey.count)")
        }
        guard signature.count == 64 else {
            throw LumenError.invalidSignature("Ed25519 signature must be 64 bytes, got \(signature.count)")
        }

        #if canImport(CryptoKit)
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        return key.isValidSignature(signature, for: canonicalBytes)
        #else
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        return key.isValidSignature(signature, for: canonicalBytes)
        #endif
    }

    /// Verify a threshold of signatures from a set of trusted keys.
    ///
    /// - Parameters:
    ///   - signatures: The signatures to verify (each with its keyid)
    ///   - canonicalBytes: The canonical bytes that were signed
    ///   - trustedKeys: The set of trusted public keys (by keyid)
    ///   - requiredKeyids: The keyids authorized to sign this payload
    ///   - threshold: The minimum number of valid signatures required
    ///   - roleName: Used for error messages
    /// - Throws: LumenError.duplicateSignature, .unknownKey, .invalidSignature,
    ///           .insufficientSignatures
    public static func verifyThreshold(
        signatures: [RawSignature],
        canonicalBytes: Data,
        trustedKeys: [String: RawPublicKey],
        requiredKeyids: [String],
        threshold: Int,
        roleName: String
    ) throws {
        var validSignatures = 0
        var seenKeyids = Set<String>()

        for sig in signatures {
            guard !seenKeyids.contains(sig.keyid) else {
                throw LumenError.duplicateSignature(sig.keyid)
            }
            seenKeyids.insert(sig.keyid)

            // Per TUF spec: signatures from keys not in the role's keyids
            // MUST be ignored, not cause a hard failure. This prevents an
            // attacker from adding bogus signatures to DoS clients.
            guard requiredKeyids.contains(sig.keyid) else {
                continue
            }

            guard let key = trustedKeys[sig.keyid] else {
                continue
            }

            // The key MUST be Ed25519
            guard key.keytype == "ed25519" else {
                throw LumenError.unsupportedKeyType(key.keytype)
            }
            guard key.scheme == "ed25519" else {
                throw LumenError.unsupportedScheme(key.scheme)
            }

            // Verify the signature
            let isValid = (try? verify(signature: sig.signature, canonicalBytes: canonicalBytes, publicKey: key.keyData)) ?? false
            if isValid {
                validSignatures += 1
            }
        }

        guard validSignatures >= threshold else {
            throw LumenError.insufficientSignatures(
                role: roleName,
                required: threshold,
                provided: validSignatures
            )
        }
    }

    /// Compute the key ID for an Ed25519 public key:
    /// keyid = base64url(SHA-256(public_key_bytes))
    public static func keyID(forPublicKey publicKey: Data) -> String {
        return Base64URL.encode(LumenSHA256.hash(data: publicKey))
    }
}
