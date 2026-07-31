# GUIDemo

A minimal **SwiftUI application** demonstrating the full `LumenUpdateUI`
component set wired to a real `LumenUpdater`.

## Build

```bash
swift build --target lumen-gui-demo
```

This compiles and links the demo against SwiftUI and the Lumen libraries,
proving the API is usable from a GUI app.

## Run as a real app

A plain SPM executable compiles but needs an **app bundle** to open a window.
To run it interactively:

1. Create a new **macOS App** project in Xcode (SwiftUI lifecycle).
2. Add the `LumenUpdate` package and link `LumenUpdateSDK` + `LumenUpdateUI`.
3. Copy `Examples/GUIDemo/main.swift` into the project (rename the `@main`
   struct to match, or remove Xcode's generated App file).
4. Add your repository's `1.root.json` to the app target's **Resources**
   (rename to `root.json`).
5. Set the repository URL and product ID in `UpdateModel.init`.
6. Run.

## What it shows

| Component | Purpose |
|:---|:---|
| `CheckForUpdatesButton` | Triggers `checkForUpdates()` |
| `UpdateAvailableView` | Install / skip prompt with version + critical badge |
| `UpdateProgressView` | Download progress bar |
| `UpdateReadyView` | Restart-to-install prompt |
| `UpdateFailureView` | Error + retry |
| `UpdateTrustDetailsView` | Separated trust indicators (publisher / signature / metadata / Developer ID / notarization) |

The trust indicators are deliberately **never collapsed into a single "Secure"
badge** — in Independent mode the Apple Developer ID and notarization rows show
as "not available", honestly.
