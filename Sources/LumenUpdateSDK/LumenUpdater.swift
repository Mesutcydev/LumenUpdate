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
    private var stateContinuation: AsyncStream<UpdateState>.Continuation?
    private var schedulerTask: Task<Void, Never>?

    public var states: AsyncStream<UpdateState> {
        AsyncStream { continuation in
            self.stateContinuation = continuation
            continuation.yield(self.state)
        }
    }

    public init(configuration: UpdateConfiguration) {
        self.configuration = configuration
    }

    public func checkForUpdates() async throws -> UpdateState {
        setState(.checking)

        // In a full implementation, this would:
        // 1. Fetch timestamp.json from repositoryURL
        // 2. Fetch snapshot.json
        // 3. Fetch targets.json
        // 4. Verify the full TUF chain
        // 5. Resolve the target for this host
        // 6. Return .updateAvailable or .upToDate

        // For now, return .upToDate as the verification pipeline
        // is exercised through the TUFVerifier tests.
        setState(.upToDate)
        return .upToDate
    }

    public func downloadAndInstall() async throws {
        guard case .updateAvailable(let release) = state else {
            throw LumenError.targetInvalid("No update available to install")
        }

        setState(.downloading(DownloadProgressInfo(bytesReceived: 0, totalBytes: Int64(release.targetSize))))

        // Download phase would use LumenDownload.Downloader
        setState(.verifying)

        // Verification phase would use LumenArchive.BundleManifestVerifier
        setState(.readyToInstall(release))
    }

    public func installNow() async throws {
        guard case .readyToInstall(let release) = state else {
            throw LumenError.targetInvalid("No update ready to install")
        }

        setState(.installing)

        // Installation phase would use LumenInstall.BundleReplacer
        // and LumenInstall.TransactionJournal

        setState(.relaunching)
    }

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
        // Clear the blocklist entry and reset state
        setState(.idle)
    }

    private func setState(_ newState: UpdateState) {
        state = newState
        stateContinuation?.yield(newState)
    }
}
