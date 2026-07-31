import Foundation

public struct DownloadConfiguration: Sendable {
    public let expectedLength: Int
    public let expectedHashes: [String: String]
    public let maximumSize: Int
    public let maximumRedirects: Int
    public let allowedHosts: [String]
    public let requireTLS: Bool
    public let timeoutInterval: TimeInterval
    public let maximumRetries: Int
    public let retryBaseDelay: TimeInterval
    public let diskSpaceMultiplier: Double

    public init(
        expectedLength: Int,
        expectedHashes: [String: String],
        maximumSize: Int = 500 * 1024 * 1024,
        maximumRedirects: Int = 5,
        allowedHosts: [String] = [],
        requireTLS: Bool = true,
        timeoutInterval: TimeInterval = 300,
        maximumRetries: Int = 3,
        retryBaseDelay: TimeInterval = 1.0,
        diskSpaceMultiplier: Double = 2.0
    ) {
        self.expectedLength = expectedLength
        self.expectedHashes = expectedHashes
        self.maximumSize = maximumSize
        self.maximumRedirects = maximumRedirects
        self.allowedHosts = allowedHosts
        self.requireTLS = requireTLS
        self.timeoutInterval = timeoutInterval
        self.maximumRetries = maximumRetries
        self.retryBaseDelay = retryBaseDelay
        self.diskSpaceMultiplier = diskSpaceMultiplier
    }
}
