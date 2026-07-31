import XCTest
import Foundation
import LumenCore
import LumenTUF
import LumenUpdateSDK
import LumenTesting

// MARK: - Local HTTP test server

/// Serves a directory over HTTP using python3's http.server, for exercising
/// the remote download path in tests without a real CDN.
final class LocalHTTPServer {
    let baseURL: URL
    private let process: Process

    init(directory: URL) throws {
        let port = try Self.findFreePort()
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "http.server", "\(port)", "--bind", "127.0.0.1", "--directory", directory.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        self.process = process
    }

    func waitUntilReady() async throws {
        let session = URLSession(configuration: .default)
        let deadline = Date().addingTimeInterval(15)
        let probe = baseURL.appendingPathComponent("metadata/timestamp.json")
        while Date() < deadline {
            if let (_, response) = try? await session.data(from: probe),
               let http = response as? HTTPURLResponse,
               (200...299).contains(http.statusCode) {
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw HTTPTestError.serverNotReady
    }

    func stop() {
        process.terminate()
    }

    private static func findFreePort() throws -> Int {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { throw HTTPTestError.socketFailed }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(sock)
            throw HTTPTestError.socketFailed
        }

        var assigned = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = getsockname(sock, $0, &len)
            }
        }
        let port = Int(UInt16(bigEndian: assigned.sin_port))
        close(sock)
        return port
    }
}

enum HTTPTestError: Error {
    case serverNotReady
    case socketFailed
}

// MARK: - Integration tests over HTTP

@MainActor
final class HTTPIntegrationTests: XCTestCase {
    private let fm = FileManager.default
    private let productID = "com.example.httpapp"

    private func buildRepo(version: Int, artifact: Data) throws -> (URL, RepositoryBuilder.BuiltRepository) {
        let dir = fm.temporaryDirectory.appendingPathComponent("http-repo-\(UUID().uuidString)")
        let built = try RepositoryBuilder.build(in: dir, productID: productID, bundleVersion: version, artifactContents: artifact)
        return (dir, built)
    }

    private func makeUpdater(baseURL: URL, trustRoot: TrustRoot, currentVersion: Int) -> LumenUpdater {
        let fetcher = HTTPMetadataFetcher(baseURL: baseURL, requireTLS: false)
        let config = UpdateConfiguration(repositoryURL: baseURL, productID: productID, channel: "stable")
        let host = HostProfile(
            productID: productID,
            bundleIdentifier: productID,
            currentBundleVersion: currentVersion,
            architecture: "arm64",
            macOSVersion: "14.0",
            channel: "stable"
        )
        return LumenUpdater(configuration: config, hostProfile: host, trustRoot: trustRoot, metadataFetcher: fetcher)
    }

    func testFullUpdateFlowOverHTTP() async throws {
        let artifact = Data(repeating: 0x42, count: 4096)
        let (repoDir, built) = try buildRepo(version: 2, artifact: artifact)
        defer { try? fm.removeItem(at: repoDir) }

        let server = try LocalHTTPServer(directory: repoDir)
        defer { server.stop() }
        try await server.waitUntilReady()

        let updater = makeUpdater(baseURL: server.baseURL, trustRoot: built.trustRoot, currentVersion: 1)

        // Metadata chain fetched + verified over HTTP.
        let state = try await updater.checkForUpdates()
        guard case .updateAvailable(let release) = state else {
            XCTFail("Expected .updateAvailable, got \(state)")
            return
        }
        XCTAssertEqual(release.bundleVersion, 2)

        // Target streamed + hash-verified over HTTP via the Downloader.
        try await updater.downloadAndInstall()
        guard case .readyToInstall = updater.state else {
            XCTFail("Expected .readyToInstall, got \(updater.state)")
            return
        }
    }

    func testTamperedArchiveRejectedOverHTTP() async throws {
        let artifact = Data(repeating: 0x42, count: 4096)
        let (repoDir, built) = try buildRepo(version: 2, artifact: artifact)
        defer { try? fm.removeItem(at: repoDir) }

        // Compromise the served artifact after metadata was signed.
        try Data(repeating: 0xFF, count: 4096).write(to: built.artifactURL)

        let server = try LocalHTTPServer(directory: repoDir)
        defer { server.stop() }
        try await server.waitUntilReady()

        let updater = makeUpdater(baseURL: server.baseURL, trustRoot: built.trustRoot, currentVersion: 1)
        _ = try await updater.checkForUpdates()

        do {
            try await updater.downloadAndInstall()
            XCTFail("Tampered archive over HTTP was NOT rejected")
        } catch let error as LumenError {
            XCTAssertEqual(error.code, "target.hashMismatch")
        }
    }
}

// MARK: - Unit tests (no server required)

final class HTTPFetcherPolicyTests: XCTestCase {

    func testRejectsNonTLSWhenRequired() async {
        let fetcher = HTTPMetadataFetcher(baseURL: URL(string: "http://updates.example.com")!, requireTLS: true)
        do {
            _ = try await fetcher.fetchMetadata("timestamp.json")
            XCTFail("Expected TLS rejection")
        } catch let error as LumenError {
            XCTAssertEqual(error.code, "repository.invalidResponse")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsDisallowedHost() async {
        let fetcher = HTTPMetadataFetcher(
            baseURL: URL(string: "https://evil.example.com")!,
            allowedHosts: ["trusted.example.com"],
            requireTLS: true
        )
        do {
            _ = try await fetcher.fetchMetadata("timestamp.json")
            XCTFail("Expected host rejection")
        } catch let error as LumenError {
            XCTAssertEqual(error.code, "repository.redirectDisallowed")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDefaultsAllowedHostsToBaseHost() {
        let fetcher = HTTPMetadataFetcher(baseURL: URL(string: "https://updates.example.com")!)
        XCTAssertEqual(fetcher.pinnedHosts, ["updates.example.com"])
        XCTAssertTrue(fetcher.tlsRequired)
    }

    func testSourceURLConstruction() {
        let fetcher = HTTPMetadataFetcher(baseURL: URL(string: "https://updates.example.com")!)
        XCTAssertEqual(
            fetcher.sourceURL(forTarget: "targets/foo.aar").absoluteString,
            "https://updates.example.com/targets/foo.aar"
        )
    }
}
