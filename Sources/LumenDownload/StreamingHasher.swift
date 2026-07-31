import Foundation
import CommonCrypto
import LumenCore

public final class StreamingHasher: @unchecked Sendable {
    private var context: CC_SHA256_CTX
    private var _bytesHashed: Int64 = 0

    public var bytesHashed: Int64 { _bytesHashed }

    public init() {
        context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)
    }

    public func update(with data: Data) {
        data.withUnsafeBytes { buffer in
            if let baseAddress = buffer.baseAddress, buffer.count > 0 {
                CC_SHA256_Update(&context, baseAddress, CC_LONG(buffer.count))
                _bytesHashed += Int64(buffer.count)
            }
        }
    }

    public func finalize() -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&hash, &context)
        return Data(hash)
    }

    public func finalizeBase64URL() -> String {
        return Base64URL.encode(finalize())
    }
}
