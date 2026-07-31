import SwiftUI
import LumenCore
import LumenTUF
import LumenUpdateSDK
import LumenUpdateUI

// Lumen Update — GUI Demo
//
// A minimal SwiftUI application showing the full LumenUpdateUI component set
// wired to a real LumenUpdater. Build with:  swift build --target lumen-gui-demo
//
// To run as a real .app, wrap this source in an Xcode app target and add your
// repository's `1.root.json` to the app's Resources (see README.md). As a plain
// SPM executable it compiles and links against SwiftUI; launching a window
// requires an app bundle.

@main
struct GUIDemoApp: App {
    @StateObject private var model = UpdateModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 480, minHeight: 380)
        }
    }
}

@MainActor
final class UpdateModel: ObservableObject {
    @Published var updater: LumenUpdater?
    @Published var setupError: String?

    init() {
        do {
            let trustRoot = try Self.loadBundledRoot()
            self.updater = LumenUpdater(
                configuration: UpdateConfiguration(
                    repositoryURL: URL(string: "https://updates.example.com")!,
                    productID: "com.example.IndependentDemo",
                    channel: "stable"
                ),
                hostProfile: HostProfile(
                    productID: "com.example.IndependentDemo",
                    bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.example.IndependentDemo",
                    currentBundleVersion: 100,
                    architecture: "arm64",
                    macOSVersion: "14.0",
                    channel: "stable"
                ),
                trustRoot: trustRoot
            )
        } catch {
            self.setupError = "\(error)"
        }
    }

    private static func loadBundledRoot() throws -> TrustRoot {
        guard let url = Bundle.main.url(forResource: "root", withExtension: "json") else {
            throw DemoSetupError.noBundledRoot
        }
        return try TrustRootBootstrap.bootstrap(from: try Data(contentsOf: url))
    }
}

enum DemoSetupError: Error, CustomStringConvertible {
    case noBundledRoot
    var description: String {
        "No bundled root.json found. Add your repository's 1.root.json to the app's Resources."
    }
}

struct ContentView: View {
    @EnvironmentObject var model: UpdateModel

    var body: some View {
        Group {
            if let error = model.setupError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Setup needed").font(.headline)
                    Text(error)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
            } else if let updater = model.updater {
                UpdatePanel(updater: updater)
            }
        }
        .padding(20)
    }
}

struct UpdatePanel: View {
    @ObservedObject var updater: LumenUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lumen Update — GUI Demo")
                .font(.title2)
                .bold()

            CheckForUpdatesButton(updater: updater)

            stateView

            Divider()

            UpdateTrustDetailsView(
                publisherVerified: true,
                signatureValid: true,
                metadataCurrent: true,
                developerIDVerified: false,
                notarizationVerified: false
            )

            Spacer()
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch updater.state {
        case .checking:
            ProgressView("Checking for updates…")
        case .upToDate:
            Label("You're up to date", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .updateAvailable(let release):
            UpdateAvailableView(
                release: release,
                onInstall: { Task { try? await updater.downloadAndInstall() } },
                onSkip: {}
            )
        case .downloading(let progress):
            UpdateProgressView(progress: progress)
        case .readyToInstall(let release):
            UpdateReadyView(
                release: release,
                onRestart: { Task { try? await updater.installNow() } }
            )
        case .metadataStale(let reason):
            UpdateFailureView(
                message: "Metadata stale: \(reason)",
                onRetry: { Task { _ = try? await updater.checkForUpdates() } }
            )
        case .rolledBack(let reason):
            UpdateFailureView(
                message: "Update rolled back: \(reason)",
                onRetry: { Task { _ = try? await updater.checkForUpdates() } }
            )
        case .failed(let error):
            UpdateFailureView(message: error.description, onRetry: { updater.retryFailedUpdate() })
        default:
            EmptyView()
        }
    }
}
