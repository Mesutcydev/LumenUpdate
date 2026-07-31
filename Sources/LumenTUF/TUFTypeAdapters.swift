// TUFTypeAdapters.swift
// Shared conversion helpers between TUF types and LumenCrypto raw types.
// Extracted to eliminate duplication between TUFVerifier and TrustRoot.

import Foundation
import LumenCrypto

enum TUFTypeAdapters {
    static func convertSignatures(_ sigs: [TUFSignature]) throws -> [RawSignature] {
        return try sigs.map { sig in
            let sigData = try Base64URL.decode(sig.sig)
            return RawSignature(keyid: sig.keyid, signature: sigData)
        }
    }

    static func convertKeys(_ keys: [String: TUFKey]) throws -> [String: RawPublicKey] {
        var result: [String: RawPublicKey] = [:]
        for (keyid, key) in keys {
            let keyData = try Base64URL.decode(key.keyval.publicKey)
            result[keyid] = RawPublicKey(
                keyid: keyid,
                keyData: keyData,
                keytype: key.keytype,
                scheme: key.scheme
            )
        }
        return result
    }
}
