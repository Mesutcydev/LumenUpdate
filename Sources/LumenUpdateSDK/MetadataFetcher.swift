import Foundation
import LumenCore

/// Abstracts fetching TUF metadata and target artifacts from a repository.
/// Implementations may read from a local directory, an HTTP server, or a mirror.
///
/// All bytes returned are treated as UNTRUSTED until the TUF verification
/// pipeline validates their signatures, hashes, and lengths.
public protocol MetadataFetching: Sendable {
    /// Fetch a metadata file by name (e.g. "timestamp.json", "1.snapshot.json").
    /// Metadata files live under the repository's `metadata/` directory.
    func fetchMetadata(_ name: String) async throws -> Data

    /// Fetch a target artifact by its repository path (e.g. "targets/foo.aar").
    func fetchTarget(_ path: String) async throws -> Data

    /// The source URL for a target artifact at the given repository path.
    /// Drives streaming downloads via the Downloader actor: a file URL for
    /// local repositories, an https URL for remote ones.
    func sourceURL(forTarget path: String) -> URL
}

/// Reads metadata and targets from a local directory repository.
/// Used for development (`lumen serve`), testing, and local-file distribution.
public struct LocalRepositoryFetcher: MetadataFetching {
    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Create a fetcher from a repository URL. Accepts `file://` URLs and plain paths.
    public init(repositoryURL: URL) {
        if repositoryURL.isFileURL {
            self.root = repositoryURL
        } else {
            self.root = URL(fileURLWithPath: repositoryURL.path)
        }
    }

    public func fetchMetadata(_ name: String) async throws -> Data {
        let url = root.appendingPathComponent("metadata").appendingPathComponent(name)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw LumenError.repositoryUnreachable("Cannot read metadata \(name): \(error)")
        }
    }

    public func fetchTarget(_ path: String) async throws -> Data {
        let url = root.appendingPathComponent(path)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw LumenError.repositoryUnreachable("Cannot read target \(path): \(error)")
        }
    }

    public func sourceURL(forTarget path: String) -> URL {
        root.appendingPathComponent(path)
    }
}
