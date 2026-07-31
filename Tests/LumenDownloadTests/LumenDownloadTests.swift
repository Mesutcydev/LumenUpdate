import XCTest
import LumenCore
@testable import LumenDownload

final class DownloadPolicyTests: XCTestCase {

    func testRejectsNonTLSWhenRequired() {
        let url = URL(string: "http://example.com/update.aar")!
        XCTAssertThrowsError(try DownloadPolicy.validateURL(url, allowedHosts: [], requireTLS: true)) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "repository.invalidResponse")
        }
    }

    func testAcceptsTLSURL() {
        let url = URL(string: "https://example.com/update.aar")!
        XCTAssertNoThrow(try DownloadPolicy.validateURL(url, allowedHosts: [], requireTLS: true))
    }

    func testRejectsDisallowedHost() {
        let url = URL(string: "https://evil.com/update.aar")!
        XCTAssertThrowsError(try DownloadPolicy.validateURL(url, allowedHosts: ["example.com"], requireTLS: true)) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "repository.redirectDisallowed")
        }
    }

    func testAcceptsAllowedHost() {
        let url = URL(string: "https://example.com/update.aar")!
        XCTAssertNoThrow(try DownloadPolicy.validateURL(url, allowedHosts: ["example.com"], requireTLS: true))
    }

    func testRejectsExcessiveRedirects() {
        let from = URL(string: "https://a.com/1")!
        let to = URL(string: "https://b.com/2")!
        XCTAssertThrowsError(try DownloadPolicy.validateRedirect(
            from: from, to: to, allowedHosts: [], requireTLS: true,
            redirectCount: 5, maxRedirects: 5
        ))
    }
}

final class RetryClassifierTests: XCTestCase {

    func testClassifiesTimeoutAsTransient() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        XCTAssertEqual(RetryClassifier.classify(error), .transient)
    }

    func testClassifiesConnectionLostAsTransient() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
        XCTAssertEqual(RetryClassifier.classify(error), .transient)
    }

    func testClassifiesCancelledAsPermanent() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        XCTAssertEqual(RetryClassifier.classify(error), .permanent)
    }

    func testClassifiesHashMismatchAsPermanent() {
        let error = LumenError.targetHashMismatch(expected: "a", actual: "b")
        XCTAssertEqual(RetryClassifier.classify(error), .permanent)
    }

    func testClassifiesExpiredMetadataAsPermanent() {
        let error = LumenError.expiredMetadata(role: "timestamp", expiredAt: "x", now: "y")
        XCTAssertEqual(RetryClassifier.classify(error), .permanent)
    }

    func testExponentialBackoff() {
        XCTAssertEqual(RetryClassifier.delay(forAttempt: 0, baseDelay: 1.0), 1.0)
        XCTAssertEqual(RetryClassifier.delay(forAttempt: 1, baseDelay: 1.0), 2.0)
        XCTAssertEqual(RetryClassifier.delay(forAttempt: 2, baseDelay: 1.0), 4.0)
        XCTAssertEqual(RetryClassifier.delay(forAttempt: 3, baseDelay: 1.0), 8.0)
    }
}

final class StreamingHasherTests: XCTestCase {

    func testHashesEmptyData() {
        let hasher = StreamingHasher()
        let hash = hasher.finalizeBase64URL()
        let expected = Base64URL.encode(LumenSHA256.hash(data: Data()))
        XCTAssertEqual(hash, expected)
    }

    func testHashesIncrementally() {
        let hasher = StreamingHasher()
        hasher.update(with: Data("hello ".utf8))
        hasher.update(with: Data("world".utf8))
        let hash = hasher.finalizeBase64URL()
        let expected = Base64URL.encode(LumenSHA256.hash(data: Data("hello world".utf8)))
        XCTAssertEqual(hash, expected)
    }

    func testTracksBytesHashed() {
        let hasher = StreamingHasher()
        hasher.update(with: Data(repeating: 0, count: 100))
        hasher.update(with: Data(repeating: 0, count: 50))
        XCTAssertEqual(hasher.bytesHashed, 150)
    }
}

final class DownloadConfigurationTests: XCTestCase {

    func testDefaultConfiguration() {
        let config = DownloadConfiguration(
            expectedLength: 1000,
            expectedHashes: ["sha256": "abc"]
        )
        XCTAssertEqual(config.expectedLength, 1000)
        XCTAssertEqual(config.maximumRedirects, 5)
        XCTAssertTrue(config.requireTLS)
        XCTAssertEqual(config.maximumRetries, 3)
    }
}
