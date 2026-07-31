import SwiftUI
import LumenUpdateSDK

public struct CheckForUpdatesButton: View {
    @ObservedObject var updater: LumenUpdater

    public init(updater: LumenUpdater) {
        self.updater = updater
    }

    public var body: some View {
        Button("Check for Updates") {
            Task {
                _ = try? await updater.checkForUpdates()
            }
        }
        .disabled(updater.state == .checking || updater.state == .downloading(DownloadProgressInfo(bytesReceived: 0, totalBytes: 0)))
    }
}

public struct UpdateAvailableView: View {
    let release: ReleaseInfo
    let onInstall: () -> Void
    let onSkip: () -> Void

    public init(release: ReleaseInfo, onInstall: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.release = release
        self.onInstall = onInstall
        self.onSkip = onSkip
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Update Available")
                .font(.headline)

            Text("Version \(release.displayVersion) is available.")
                .font(.body)

            if release.isCritical {
                Label("Critical Update", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }

            HStack {
                Button("Install") { onInstall() }
                    .buttonStyle(.borderedProminent)

                Button("Later") { onSkip() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}

public struct UpdateProgressView: View {
    let progress: DownloadProgressInfo

    public init(progress: DownloadProgressInfo) {
        self.progress = progress
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Downloading Update...")
                .font(.headline)

            ProgressView(value: progress.fractionComplete) {
                Text("\(Int(progress.fractionComplete * 100))%")
            }

            Text("\(progress.bytesReceived) of \(progress.totalBytes) bytes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

public struct UpdateReadyView: View {
    let release: ReleaseInfo
    let onRestart: () -> Void

    public init(release: ReleaseInfo, onRestart: @escaping () -> Void) {
        self.release = release
        self.onRestart = onRestart
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ready to Install")
                .font(.headline)

            Text("Version \(release.displayVersion) has been downloaded and verified. Restart to install.")
                .font(.body)

            Button("Restart & Install") { onRestart() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

public struct UpdateFailureView: View {
    let message: String
    let onRetry: () -> Void

    public init(message: String, onRetry: @escaping () -> Void) {
        self.message = message
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Update Failed", systemImage: "xmark.circle.fill")
                .font(.headline)
                .foregroundColor(.red)

            Text(message)
                .font(.body)

            Button("Retry") { onRetry() }
                .buttonStyle(.bordered)
        }
        .padding()
    }
}

public struct UpdateTrustDetailsView: View {
    let publisherVerified: Bool
    let signatureValid: Bool
    let metadataCurrent: Bool
    let developerIDVerified: Bool
    let notarizationVerified: Bool

    public init(
        publisherVerified: Bool,
        signatureValid: Bool,
        metadataCurrent: Bool,
        developerIDVerified: Bool = false,
        notarizationVerified: Bool = false
    ) {
        self.publisherVerified = publisherVerified
        self.signatureValid = signatureValid
        self.metadataCurrent = metadataCurrent
        self.developerIDVerified = developerIDVerified
        self.notarizationVerified = notarizationVerified
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trust Details")
                .font(.headline)

            TrustRow(label: "Publisher verified", verified: publisherVerified)
            TrustRow(label: "Update signature valid", verified: signatureValid)
            TrustRow(label: "Repository metadata current", verified: metadataCurrent)
            TrustRow(label: "Apple Developer ID verified", verified: developerIDVerified)
            TrustRow(label: "Apple notarization verified", verified: notarizationVerified)
        }
        .padding()
    }

    private struct TrustRow: View {
        let label: String
        let verified: Bool

        var body: some View {
            HStack {
                Image(systemName: verified ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundColor(verified ? .green : .secondary)
                Text(label)
                    .font(.caption)
            }
        }
    }
}
