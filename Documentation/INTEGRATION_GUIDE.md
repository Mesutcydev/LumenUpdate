# Integrating Lumen Update

A step-by-step guide for shipping secure macOS application updates with Lumen —
from adding the package to publishing your first release. No Apple Developer
account required for Independent mode.

---

## 1. Add the package

In Xcode: **File → Add Package Dependencies…** → enter the repository URL, and
add the **`LumenUpdateSDK`** library (plus **`LumenUpdateUI`** if you want the
ready-made SwiftUI views).

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Mesutcydev/LumenUpdate.git", from: "1.0.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "LumenUpdateSDK", package: "LumenUpdate"),
            .product(name: "LumenUpdateUI", package: "LumenUpdate"),
        ]
    )
]
```

---

## 2. Create your signing keys and repository (publisher side)

Do this once, on a trusted machine. **Keep private keys off any server and out
of version control.**

```bash
# Scaffold a repository
lumen init --product-id com.example.myapp

# Generate one key per role
lumen key generate --role root
lumen key generate --role targets
lumen key generate --role snapshot
lumen key generate --role timestamp

# Create the self-signed root metadata
lumen root create \
  --root-key ~/.lumen/keys/root-*.key \
  --targets-key ~/.lumen/keys/targets-*.pub \
  --snapshot-key ~/.lumen/keys/snapshot-*.pub \
  --timestamp-key ~/.lumen/keys/timestamp-*.pub \
  --output ./UpdateRepository/metadata/1.root.json
```

The file `1.root.json` contains **only public keys** — this is the trust anchor
you bundle inside your app.

---

## 3. Bundle the root metadata in your app

Copy `1.root.json` into your app bundle as `Contents/Resources/root.json`. This
is the **only** trust material the app ships with — never a private key.

---

## 4. Create the updater

```swift
import LumenUpdateSDK
import LumenTUF

// Load the bundled root once.
let rootURL = Bundle.main.url(forResource: "root", withExtension: "json")!
let trustRoot = try TrustRootBootstrap.bootstrap(from: try Data(contentsOf: rootURL))

let updater = LumenUpdater(
    configuration: UpdateConfiguration(
        repositoryURL: URL(string: "https://updates.example.com")!,
        productID: "com.example.myapp",
        channel: "stable"
    ),
    hostProfile: HostProfile(
        productID: "com.example.myapp",
        bundleIdentifier: Bundle.main.bundleIdentifier!,
        currentBundleVersion: Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0,
        architecture: "arm64",                       // or detect at runtime
        macOSVersion: "14.0",                        // or detect at runtime
        channel: "stable"
    ),
    trustRoot: trustRoot
    // metadataFetcher defaults to a fetcher matching repositoryURL:
    //   - https://… → HTTPMetadataFetcher (remote)
    //   - file path → LocalRepositoryFetcher (local)
)
```

> For a **remote** repository, pass an `HTTPMetadataFetcher` (the default when
> `repositoryURL` is `https`). It enforces TLS, pins the allowed host, and caps
> total metadata at 100 KB. Target downloads stream to disk through the
> `Downloader` with SHA-256 verification.

---

## 5. Check for and install updates

```swift
// Check
switch try await updater.checkForUpdates() {
case .updateAvailable(let release):
    print("Version \(release.displayVersion) is available")
case .upToDate:
    print("You're on the latest version")
case .metadataStale(let reason):
    print("Repository metadata is stale: \(reason)")
default:
    break
}

// Download + verify (streams to disk, verifies SHA-256 before extraction)
try await updater.downloadAndInstall()

// Install (transactional: backs up the old app, replaces, awaits health)
try await updater.installNow()
```

### Observe state

```swift
for await state in updater.states {
    switch state {
    case .downloading(let progress):
        progressBar.fractionCompleted = progress.fractionComplete
    case .readyToInstall:
        showRestartPrompt()
    case .rolledBack(let reason):
        alert("Update rolled back: \(reason)")
    case .failed(let error):
        alert(error.description)
    default:
        break
    }
}
```

### Automatic checks

```swift
updater.startAutomaticChecks()   // uses configuration.automaticCheckInterval (default: daily)
// …
updater.stopAutomaticChecks()
```

---

## 6. Report health after relaunch

After your app restarts into the new version, confirm it's healthy so the
installer commits (deletes the backup). If you crash before this call, the
installer **rolls back** to the previous version automatically.

```swift
import LumenInstall

// Once your essential storage is open, migrations done, and UI can present:
try HealthCheck.reportHealthy(transactionID: /* the transaction id */)
```

---

## 7. Ready-made SwiftUI views

```swift
import LumenUpdateUI

struct SettingsView: View {
    @StateObject var updater: LumenUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CheckForUpdatesButton(updater: updater)

            switch updater.state {
            case .updateAvailable(let release):
                UpdateAvailableView(
                    release: release,
                    onInstall: { Task { try? await updater.downloadAndInstall() } },
                    onSkip: {}
                )
            case .downloading(let progress):
                UpdateProgressView(progress: progress)
            case .readyToInstall(let release):
                UpdateReadyView(release: release,
                    onRestart: { Task { try? await updater.installNow() } })
            case .failed(let error):
                UpdateFailureView(message: error.description,
                    onRetry: { updater.retryFailedUpdate() })
            default:
                EmptyView()
            }

            // Honest, separated trust indicators — never a vague "Secure" badge.
            UpdateTrustDetailsView(
                publisherVerified: true,
                signatureValid: true,
                metadataCurrent: true,
                developerIDVerified: false,   // Independent mode
                notarizationVerified: false
            )
        }
        .padding()
    }
}
```

---

## 8. Publish a release

```bash
# Package the .app into a signed update archive + manifest
lumen package ./build/MyApp.app --channel stable

# Create signed release metadata (targets + snapshot + timestamp)
lumen release create \
  --artifact ./MyApp-2.0.0-arm64.aar \
  --manifest ./MyApp-2.0.0-arm64.bundle-manifest.json \
  --targets-key ~/.lumen/keys/targets-*.key \
  --snapshot-key ~/.lumen/keys/snapshot-*.key \
  --timestamp-key ~/.lumen/keys/timestamp-*.key \
  --product-id com.example.myapp

# Publish (atomic order: targets → metadata → timestamp last)
lumen publish --repository ./UpdateRepository --destination ./hosting

# Verify the published repository with the same code your app uses
lumen repository verify ./hosting \
  --root ./UpdateRepository/metadata/1.root.json \
  --product-id com.example.myapp
```

---

## 9. Trust profiles at a glance

| Mode | You need | Users see |
|:---|:---|:---|
| **Independent** | Just your Lumen keys | A one-time Gatekeeper approval on first launch (unsigned/ad-hoc) |
| **Apple Enhanced** | Lumen keys + Developer ID + notarization | No Gatekeeper warning |
| **Managed** | Lumen keys + your org's root/policy | Depends on your signing |

See [`ACCOUNTLESS_DISTRIBUTION.md`](./ACCOUNTLESS_DISTRIBUTION.md) for honest
Gatekeeper behavior per macOS version, and
[`SPARKLE_MIGRATION.md`](./SPARKLE_MIGRATION.md) to migrate from Sparkle.

---

## 10. Security checklist

- [ ] Private keys are **never** in the app bundle, the repository, git, logs, or CLI args
- [ ] `root.json` (public keys only) is bundled as a resource
- [ ] Your app calls `HealthCheck.reportHealthy` after a successful relaunch
- [ ] You treat `metadataStale` / `signatureInvalid` as visible errors, not "no updates"
- [ ] You do **not** strip quarantine or bypass Gatekeeper
