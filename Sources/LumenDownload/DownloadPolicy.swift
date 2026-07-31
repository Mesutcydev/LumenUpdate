import Foundation
import LumenCore

public enum DownloadPolicy {

    public static func validateURL(
        _ url: URL,
        allowedHosts: [String],
        requireTLS: Bool
    ) throws {
        guard let scheme = url.scheme?.lowercased() else {
            throw LumenError.repositoryInvalidResponse("URL has no scheme: \(url)")
        }

        if requireTLS && scheme != "https" {
            throw LumenError.repositoryInvalidResponse("TLS required but URL uses \(scheme): \(url)")
        }

        if !allowedHosts.isEmpty {
            guard let host = url.host else {
                throw LumenError.repositoryInvalidResponse("URL has no host: \(url)")
            }
            guard allowedHosts.contains(host) else {
                throw LumenError.redirectDisallowed(from: "original", to: host)
            }
        }
    }

    public static func validateRedirect(
        from originalURL: URL,
        to redirectURL: URL,
        allowedHosts: [String],
        requireTLS: Bool,
        redirectCount: Int,
        maxRedirects: Int
    ) throws {
        guard redirectCount < maxRedirects else {
            throw LumenError.repositoryInvalidResponse("Too many redirects (\(redirectCount) >= \(maxRedirects))")
        }

        try validateURL(redirectURL, allowedHosts: allowedHosts, requireTLS: requireTLS)

        if let originalHost = originalURL.host, let redirectHost = redirectURL.host {
            if !allowedHosts.isEmpty && !allowedHosts.contains(redirectHost) {
                throw LumenError.redirectDisallowed(from: originalHost, to: redirectHost)
            }
        }
    }
}
