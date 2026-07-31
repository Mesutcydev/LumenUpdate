// SHA256.swift
// SHA-256 hashing using CommonCrypto (available on all Apple platforms).
// v1.0 targets macOS only; Linux support is future work.

import Foundation
import CommonCrypto

public enum LumenSHA256 {
    /// Compute SHA-256 hash of data.
    public static func hash(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
}
