import Foundation
import LumenCore

public struct UpdateConfiguration: Sendable {
    public let repositoryURL: URL
    public let productID: String
    public let channel: String
    public let trustRootResource: String
    public let automaticCheckInterval: TimeInterval?
    public let allowedHosts: [String]
    public let requireTLS: Bool

    public init(
        repositoryURL: URL,
        productID: String,
        channel: String = "stable",
        trustRootResource: String = "root",
        automaticCheckInterval: TimeInterval? = 86400,
        allowedHosts: [String] = [],
        requireTLS: Bool = true
    ) {
        self.repositoryURL = repositoryURL
        self.productID = productID
        self.channel = channel
        self.trustRootResource = trustRootResource
        self.automaticCheckInterval = automaticCheckInterval
        self.allowedHosts = allowedHosts
        self.requireTLS = requireTLS
    }
}
