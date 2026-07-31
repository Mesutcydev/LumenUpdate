import XCTest
import Foundation
import LumenCore
import LumenTUF
import LumenUpdateSDK
import LumenTesting

/// End-to-end integration tests proving the master plan §20 "First end-to-end
/// proof" scenarios through the real, wired LumenUpdater against a fully-signed
/// on-disk repository built by RepositoryBuilder.
@MainActor
final class EndToEndTests: XCTestCase {

    // MARK: - Context helper

    private struct Context {
        let dir: URL
        let built: RepositoryBuilder.BuiltRepository
        let updater: LumenUpdater
    }

    private func makeContext(
        bundleVersion: Int = 2,
        currentVersion: Int = 1,
        artifact: Data = Data(repeating: 0x42, count: 1024),
        timestampExpires: String? = nil,
        versionTracker: VersionTracker = VersionTracker()
    ) throws -> Context {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumen-e2e-\(UUID().uuidString)")
        let built = try RepositoryBuilder.build(
            in: dir,
            bundleVersion: bundleVersion,
            artifactContents: artifact,
            timestampExpires: timestampExpires
        )
        let config = UpdateConfiguration(
            repositoryURL: dir,
            productID: built.productID,
            channel: built.channel
        )
        let host = HostProfile(
            productID: built.productID,
            bundleIdentifier: built.productID,
            currentBundleVersion: currentVersion,
            architecture: "arm64",
            macOSVersion: "14.0",
            channel: built.channel
        )
        let updater = LumenUpdater(
            configuration: config,
            hostProfile: host,
            trustRoot: built.trustRoot,
            metadataFetcher: LocalRepositoryFetcher(root: dir),
            versionTracker: versionTracker
        )
        return Context(dir: dir, built: built, updater: updater)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - §20.1: 1.0 → 1.1 installs successfully (update is found)

    func testValidUpdateIsFound() async throws {
        let ctx = try makeContext(bundleVersion: 2, currentVersion: 1)
        defer { cleanup(ctx.dir) }

        let state = try await ctx.updater.checkForUpdates()

        guard case .updateAvailable(let release) = state else {
            XCTFail("Expected .updateAvailable, got \(state)")
            return
        }
        XCTAssertEqual(release.bundleVersion, 2)
        XCTAssertEqual(release.channel, "stable")
        XCTAssertEqual(release.targetSize, 1024)
        XCTAssertFalse(release.targetHash.isEmpty)
    }

    // MARK: - No update when the host is already current

    func testUpToDateWhenAlreadyCurrent() async throws {
        let ctx = try makeContext(bundleVersion: 1, currentVersion: 1)
        defer { cleanup(ctx.dir) }

        let state = try await ctx.updater.checkForUpdates()
        XCTAssertEqual(state, .upToDate)
    }

    // MARK: - §20.2: a modified archive is rejected BEFORE extraction

    func testTamperedArchiveRejectedBeforeExtraction() async throws {
        let artifact = Data(repeating: 0x42, count: 1024)
        let ctx = try makeContext(bundleVersion: 2, currentVersion: 1, artifact: artifact)
        defer { cleanup(ctx.dir) }

        // Metadata is valid, so the check succeeds.
        let state = try await ctx.updater.checkForUpdates()
        guard case .updateAvailable = state else {
            XCTFail("Expected .updateAvailable, got \(state)")
            return
        }

        // Tamper with the artifact bytes on disk (simulates a compromised CDN).
        try Data(repeating: 0xFF, count: 1024).write(to: ctx.built.artifactURL)

        // The download must reject the artifact on hash mismatch — before any
        // extraction occurs (Security Invariant 1).
        do {
            try await ctx.updater.downloadAndInstall()
            XCTFail("Expected hash mismatch to reject the tampered archive")
        } catch let error as LumenError {
            XCTAssertEqual(error.code, "target.hashMismatch")
        }
    }

    // MARK: - A valid archive downloads, verifies, and stages

    func testValidArchiveDownloadsAndStages() async throws {
        let artifact = Data(repeating: 0x42, count: 1024)
        let ctx = try makeContext(bundleVersion: 2, currentVersion: 1, artifact: artifact)
        defer { cleanup(ctx.dir) }

        _ = try await ctx.updater.checkForUpdates()
        try await ctx.updater.downloadAndInstall()

        guard case .readyToInstall(let release) = ctx.updater.state else {
            XCTFail("Expected .readyToInstall, got \(ctx.updater.state)")
            return
        }
        XCTAssertEqual(release.bundleVersion, 2)
    }

    // MARK: - Expired metadata is an explicit freshness failure, not "no updates"

    func testExpiredMetadataIsStale() async throws {
        let past = ISO8601DateFormatter.lumen.string(from: Date().addingTimeInterval(-3600))
        let ctx = try makeContext(bundleVersion: 2, currentVersion: 1, timestampExpires: past)
        defer { cleanup(ctx.dir) }

        let state = try await ctx.updater.checkForUpdates()

        guard case .metadataStale = state else {
            XCTFail("Expected .metadataStale, got \(state)")
            return
        }
    }

    // MARK: - Tampered metadata is rejected (signature / hash chain broken)

    func testTamperedMetadataIsRejected() async throws {
        let ctx = try makeContext(bundleVersion: 2, currentVersion: 1)
        defer { cleanup(ctx.dir) }

        // Flip a byte in the targets metadata, breaking the snapshot→targets hash chain.
        let targetsURL = ctx.dir.appendingPathComponent("metadata/1.targets.json")
        var bytes = try Data(contentsOf: targetsURL)
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: targetsURL)

        let state = try await ctx.updater.checkForUpdates()

        if case .updateAvailable = state {
            XCTFail("Tampered metadata must not be accepted as a valid update")
        }
    }

    // MARK: - §20.3: a replayed/older repository is rejected (rollback protection)

    func testReplayedRepositoryRejectedAcrossChecks() async throws {
        // A single persisted version tracker spans both checks, as it would in
        // a real client. The second repository presents the same metadata version
        // again (a replay), which the tracker must reject as not-newer.
        let tracker = VersionTracker()

        let ctxA = try makeContext(bundleVersion: 2, currentVersion: 1, versionTracker: tracker)
        defer { cleanup(ctxA.dir) }
        let stateA = try await ctxA.updater.checkForUpdates()
        guard case .updateAvailable = stateA else {
            XCTFail("First check should find an update, got \(stateA)")
            return
        }

        // A second, independently-built repository at the same metadata version.
        let ctxB = try makeContext(bundleVersion: 3, currentVersion: 1, versionTracker: tracker)
        defer { cleanup(ctxB.dir) }
        let stateB = try await ctxB.updater.checkForUpdates()

        // The replayed metadata version (1, already seen) must be rejected.
        if case .updateAvailable = stateB {
            XCTFail("Replayed metadata version must be rejected as rollback")
        }
    }
}
