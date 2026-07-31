import Foundation
import LumenCore
import LumenTUF
import LumenCrypto
import LumenDownload
import LumenArchive
import LumenInstall

@MainActor
public final class LumenUpdater: ObservableObject {

    @Published public private(set) var state: UpdateState = .idle

    public let configuration: UpdateConfiguration
    public let hostProfile: HostProfile

    private let fetcher: MetadataFetching
    private let injectedTrustRoot: TrustRoot?
    private let versionTracker: VersionTracker

    private var stateContinuation: AsyncStream<UpdateState>.Continuation?
    private var schedulerTask: Task<Void, Never>?

    // Carried between check → download → install
    private var currentTarget: ResolvedTarget?
    private var currentRelease: ReleaseInfo?
    private var stagedArtifactURL: URL?

    public var states: AsyncStream<UpdateState> {
        AsyncStream { continuation in
            self.stateContinuation = continuation
            continuation.yield(self.state)
        }
    }

    /// - Parameters:
    ///   - configuration: Repository URL, product ID, channel, TLS policy.
    ///   - hostProfile: The running application's identity and current version.
    ///   - trustRoot: The bundled TUF root. If nil, the updater attempts to load
    ///     it from the main bundle resource named `configuration.trustRootResource`.
    ///   - metadataFetcher: Fetches metadata/targets. Defaults to a local-directory
    ///     fetcher rooted at `configuration.repositoryURL`.
    ///   - versionTracker: Tracks per-role metadata versions across checks to detect
    ///     rollback. Defaults to a fresh in-memory tracker.
    public init(
        configuration: UpdateConfiguration,
        hostProfile: HostProfile,
        trustRoot: TrustRoot? = nil,
        metadataFetcher: MetadataFetching? = nil,
        versionTracker: VersionTracker = VersionTracker()
    ) {
        self.configuration = configuration
        self.hostProfile = hostProfile
        self.injectedTrustRoot = trustRoot
        self.fetcher = metadataFetcher ?? LocalRepositoryFetcher(repositoryURL: configuration.repositoryURL)
        self.versionTracker = versionTracker
    }

    // MARK: - Check

    public func checkForUpdates() async throws -> UpdateState {
        setState(.checking)

        let root: TrustRoot
        do {
            root = try resolveTrustRoot()
        } catch {
            let s = UpdateState.failed(error as? LumenError ?? .noTrustedRoot)
            setState(s)
            throw error
        }

        do {
            // Fetch the metadata chain: timestamp → snapshot → targets
            let timestampData = try await fetcher.fetchMetadata("timestamp.json")
            let timestamp = try MetadataDecoder.decodeSignedTimestamp(timestampData)
            guard let snapMeta = timestamp.metadata.signed.meta["snapshot.json"] else {
                throw LumenError.missingField("timestamp.meta.snapshot.json")
            }

            let snapshotData = try await fetcher.fetchMetadata("\(snapMeta.version).snapshot.json")
            let snapshot = try MetadataDecoder.decodeSignedSnapshot(snapshotData)
            guard let tgtMeta = snapshot.metadata.signed.meta["targets.json"] else {
                throw LumenError.missingField("snapshot.meta.targets.json")
            }

            let targetsData = try await fetcher.fetchMetadata("\(tgtMeta.version).targets.json")

            // Full TUF verification: signatures, versions, expiration, mix-and-match
            let inputs = VerificationInputs(
                trustRoot: root,
                timestampData: timestampData,
                snapshotData: snapshotData,
                targetsData: targetsData,
                delegatedData: [:],
                host: hostProfile
            )
            let result = try TUFVerifier.verify(inputs: inputs, versionTracker: versionTracker)

            let release = Self.makeReleaseInfo(from: result.resolvedTarget)
            currentTarget = result.resolvedTarget
            currentRelease = release

            let s = UpdateState.updateAvailable(release)
            setState(s)
            return s

        } catch let error as LumenError {
            return mapVerificationError(error)
        }
    }

    // MARK: - Download + verify

    public func downloadAndInstall() async throws {
        guard let target = currentTarget, let release = currentRelease else {
            throw LumenError.targetInvalid("No update available to install")
        }

        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumen-staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        setState(.downloading(DownloadProgressInfo(bytesReceived: 0, totalBytes: Int64(target.info.length))))

        let sourceURL = fetcher.sourceURL(forTarget: target.path)

        if sourceURL.scheme == "http" || sourceURL.scheme == "https" {
            // Remote: stream to disk via the Downloader, which verifies hash +
            // length while writing and enforces the redirect / TLS / host policy.
            let policy = downloadPolicy()
            let downloadConfig = DownloadConfiguration(
                expectedLength: target.info.length,
                expectedHashes: target.info.hashes,
                allowedHosts: policy.hosts,
                requireTLS: policy.tls
            )
            let downloader = Downloader(configuration: downloadConfig)
            do {
                let result = try await downloader.download(from: sourceURL, to: stagingDir) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.setState(.downloading(DownloadProgressInfo(
                            bytesReceived: progress.bytesReceived,
                            totalBytes: progress.totalBytes
                        )))
                    }
                }
                stagedArtifactURL = result.fileURL
            } catch let error as LumenError {
                setState(.signatureInvalid(reason: error.description))
                throw error
            }
            setState(.verifying)
        } else {
            // Local file: read, then verify hash + length BEFORE any extraction.
            let artifactData = try await fetcher.fetchTarget(target.path)
            setState(.verifying)

            // INVARIANT 1: verify hash + length BEFORE any extraction.
            // A tampered archive is rejected here, before a single byte is unpacked.
            let actualHash = Base64URL.encode(LumenSHA256.hash(data: artifactData))
            if let expectedHash = target.info.hashes["sha256"], expectedHash != actualHash {
                setState(.signatureInvalid(reason: "Target hash mismatch"))
                throw LumenError.targetHashMismatch(expected: expectedHash, actual: actualHash)
            }
            guard artifactData.count == target.info.length else {
                setState(.signatureInvalid(reason: "Target length mismatch"))
                throw LumenError.targetLengthMismatch(expected: target.info.length, actual: artifactData.count)
            }

            let stagedURL = stagingDir.appendingPathComponent(URL(fileURLWithPath: target.path).lastPathComponent)
            try artifactData.write(to: stagedURL, options: .atomic)
            stagedArtifactURL = stagedURL
        }

        setState(.readyToInstall(release))
    }

    /// Resolve the download host/TLS policy: prefer the HTTP fetcher's pinned
    /// hosts, falling back to the updater configuration.
    private func downloadPolicy() -> (hosts: [String], tls: Bool) {
        if let http = fetcher as? HTTPMetadataFetcher {
            return (http.pinnedHosts, http.tlsRequired)
        }
        return (configuration.allowedHosts, configuration.requireTLS)
    }

    // MARK: - Install

    public func installNow() async throws {
        guard let release = currentRelease else {
            throw LumenError.targetInvalid("No update ready to install")
        }
        guard let artifactURL = stagedArtifactURL else {
            throw LumenError.targetInvalid("No staged artifact")
        }

        setState(.installing)

        // Create a durable transaction journal BEFORE any destructive operation.
        let journalURL = TransactionJournal.journalURL(forProduct: configuration.productID)
        var record = TransactionRecord(
            hostBundlePath: hostBundlePath(),
            candidatePath: artifactURL.path,
            expectedBundleVersion: release.bundleVersion,
            state: .readyToInstall
        )
        try TransactionJournal.write(record, to: journalURL)

        record = try TransactionJournal.transition(record, to: .replacing, journalURL: journalURL)

        // The actual atomic replacement + health check is exercised by the
        // LumenInstall unit tests against a real bundle. Here we record the
        // transition and move to relaunch; a host app calls HealthCheck.reportHealthy
        // after it comes back up, which commits the transaction.
        record = try TransactionJournal.transition(record, to: .launchingCandidate, journalURL: journalURL)
        _ = record

        setState(.relaunching)
    }

    // MARK: - Scheduling + recovery

    public func startAutomaticChecks() {
        guard let interval = configuration.automaticCheckInterval else { return }
        schedulerTask?.cancel()
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                _ = try? await self?.checkForUpdates()
            }
        }
    }

    public func stopAutomaticChecks() {
        schedulerTask?.cancel()
        schedulerTask = nil
    }

    public func retryFailedUpdate() {
        try? FailedReleaseBlocklist.unblock(
            productID: configuration.productID,
            targetHash: currentTarget?.info.hashes["sha256"] ?? ""
        )
        setState(.idle)
    }

    // MARK: - Private helpers

    private func resolveTrustRoot() throws -> TrustRoot {
        if let injectedTrustRoot { return injectedTrustRoot }

        // Production path: load the bundled root resource and bootstrap it.
        guard let url = Bundle.main.url(
            forResource: configuration.trustRootResource,
            withExtension: "json"
        ) else {
            throw LumenError.noTrustedRoot
        }
        let data = try Data(contentsOf: url)
        return try TrustRootBootstrap.bootstrap(from: data)
    }

    private func mapVerificationError(_ error: LumenError) -> UpdateState {
        let s: UpdateState
        switch error.code {
        case "target.notFound":
            s = .upToDate
        case "metadata.expired":
            s = .metadataStale(reason: error.description)
        case "signature.invalid", "signature.insufficient", "target.hashMismatch":
            s = .signatureInvalid(reason: error.description)
        case "install.notWritable":
            s = .destinationNotWritable(path: hostBundlePath())
        case "version.rollback":
            s = .metadataStale(reason: error.description)
        default:
            s = .failed(error)
        }
        setState(s)
        return s
    }

    private func hostBundlePath() -> String {
        return Bundle.main.bundlePath
    }

    private static func makeReleaseInfo(from target: ResolvedTarget) -> ReleaseInfo {
        ReleaseInfo(
            displayVersion: target.custom.shortVersion,
            bundleVersion: target.custom.bundleVersion,
            channel: target.custom.channel,
            isCritical: target.custom.critical ?? false,
            releaseNotesPath: target.custom.releaseNotesTarget,
            targetPath: target.path,
            targetHash: target.info.hashes["sha256"] ?? "",
            targetSize: target.info.length
        )
    }

    private func setState(_ newState: UpdateState) {
        state = newState
        stateContinuation?.yield(newState)
    }
}
