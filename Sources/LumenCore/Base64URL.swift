// Base64URL.swift
// Base64URL encoding/decoding (RFC 4648 §5) for TUF signatures and hashes.
//
// TUF uses base64url encoding (with `-` and `_` instead of `+` and `/`)
// and no padding. This module provides encoding/decoding utilities.

import Foundation

public enum Base64URL {

    /// Encode data to a base64url string with no padding.
    public static func encode(_ data: Data) -> String {
        let standard = data.base64EncodedString()
        let urlSafe = standard
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return urlSafe
    }

    /// Decode a base64url string (with or without padding) to data.
    public static func decode(_ string: String) throws -> Data {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Add padding if missing
        let padding = s.count % 4
        if padding > 0 {
            s.append(String(repeating: "=", count: 4 - padding))
        }
        guard let data = Data(base64Encoded: s) else {
            throw LumenError.invalidBase64(string)
        }
        return data
    }

    /// Compute SHA-256 of data and return as base64url string.
    /// Uses CommonCrypto for portability.
    public static func sha256Base64URL(_ data: Data) -> String {
        return encode(LumenSHA256.hash(data: data))
    }
}
