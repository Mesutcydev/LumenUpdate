import Foundation
import LumenCore
import LumenTUF
import LumenDownload

/// Fetches TUF metadata and target artifacts from a remote repository over
/// HTTP(S). The origin URL is validated against the TLS and allowed-host policy
/// before each request; fetched metadata is additionally protected by TUF
/// signature verification in the pipeline, and target downloads flow through
/// the streaming `Downloader` (which enforces the full redirect policy).
///
/// No cookies, credentials, or shared browser state are used.
public struct HTTPMetadataFetcher: MetadataFetching {
    private let baseURL: URL
    private let allowedHosts: [String]
    private let requireTLS: Bool
    private let session: URLSession

    /// - Parameters:
    ///   - baseURL: Repository root (e.g. `https://updates.example.com`).
    ///   - allowedHosts: Hosts downloads may use. Defaults to the base URL's host.
    ///   - requireTLS: Reject non-HTTPS URLs (default true; disable only for local test servers).
    ///   - timeoutInterval: Per-request timeout.
    public init(
        baseURL: URL,
        allowedHosts: [String] = [],
        requireTLS: Bool = true,
        timeoutInterval: TimeInterval = 60
    ) {
        self.baseURL = baseURL
        self.allowedHosts = allowedHosts.isEmpty ? [baseURL.host].compactMap { $0 } : allowedHosts
        self.requireTLS = requireTLS

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval * 2
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 4
        self.session = URLSession(configuration: config)
    }

    public func fetchMetadata(_ name: String) async throws -> Data {
        let url = baseURL.appendingPathComponent("metadata").appendingPathComponent(name)
        return try await fetch(url, maxSize: MetadataSizeLimits.totalMetadataFetch)
    }

    public func fetchTarget(_ path: String) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        // No in-memory cap: the streaming Downloader is the preferred target
        // path and verifies hash + length while writing to disk.
        return try await fetch(url, maxSize: nil)
    }

    public func sourceURL(forTarget path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    /// The allowed hosts this fetcher is pinned to (exposed for building a
    /// matching DownloadConfiguration for the streaming target download).
    public var pinnedHosts: [String] { allowedHosts }

    public var tlsRequired: Bool { requireTLS }

    private func fetch(_ url: URL, maxSize: Int?) async throws -> Data {
        try DownloadPolicy.validateURL(url, allowedHosts: allowedHosts, requireTLS: requireTLS)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw LumenError.repositoryUnreachable("Cannot fetch \(url.lastPathComponent): \(error)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw LumenError.repositoryInvalidResponse("Non-HTTP response from \(url)")
        }
        guard (200...299).contains(http.statusCode) else {
            throw LumenError.repositoryInvalidResponse("HTTP \(http.statusCode) fetching \(url.lastPathComponent)")
        }
        if let maxSize, data.count > maxSize {
            throw LumenError.metadataTooLarge(role: url.lastPathComponent, size: data.count, limit: maxSize)
        }
        return data
    }
}
