import XCTest
import LumenCore
@testable import LumenUpdateSDK

final class UpdateConfigurationTests: XCTestCase {

    func testDefaultConfiguration() {
        let config = UpdateConfiguration(
            repositoryURL: URL(string: "https://updates.example.com")!,
            productID: "com.example.app"
        )
        XCTAssertEqual(config.channel, "stable")
        XCTAssertEqual(config.trustRootResource, "root")
        XCTAssertEqual(config.automaticCheckInterval, 86400)
        XCTAssertTrue(config.requireTLS)
        XCTAssertTrue(config.allowedHosts.isEmpty)
    }

    func testCustomConfiguration() {
        let config = UpdateConfiguration(
            repositoryURL: URL(string: "https://updates.example.com")!,
            productID: "com.example.app",
            channel: "beta",
            trustRootResource: "custom-root",
            automaticCheckInterval: 3600,
            allowedHosts: ["updates.example.com", "cdn.example.com"],
            requireTLS: true
        )
        XCTAssertEqual(config.channel, "beta")
        XCTAssertEqual(config.trustRootResource, "custom-root")
        XCTAssertEqual(config.automaticCheckInterval, 3600)
        XCTAssertEqual(config.allowedHosts.count, 2)
    }
}

final class UpdateStateTests: XCTestCase {

    func testTerminalStates() {
        XCTAssertTrue(UpdateState.idle.isTerminal)
        XCTAssertTrue(UpdateState.upToDate.isTerminal)
        XCTAssertTrue(UpdateState.rolledBack(reason: "test").isTerminal)
        XCTAssertTrue(UpdateState.failed(.repositoryTimeout).isTerminal)
        XCTAssertFalse(UpdateState.checking.isTerminal)
        XCTAssertFalse(UpdateState.downloading(DownloadProgressInfo(bytesReceived: 0, totalBytes: 100)).isTerminal)
    }

    func testActionableStates() {
        let release = ReleaseInfo(
            displayVersion: "2.0",
            bundleVersion: 200,
            channel: "stable",
            isCritical: false,
            releaseNotesPath: nil,
            targetPath: "target.aar",
            targetHash: "abc",
            targetSize: 1000
        )
        XCTAssertTrue(UpdateState.updateAvailable(release).isActionable)
        XCTAssertTrue(UpdateState.readyToInstall(release).isActionable)
        XCTAssertTrue(UpdateState.manualInstallationRequired(reason: "test").isActionable)
        XCTAssertTrue(UpdateState.gatekeeperIntervention.isActionable)
        XCTAssertFalse(UpdateState.idle.isActionable)
        XCTAssertFalse(UpdateState.checking.isActionable)
    }

    func testReleaseInfoEquatable() {
        let release1 = ReleaseInfo(
            displayVersion: "2.0",
            bundleVersion: 200,
            channel: "stable",
            isCritical: false,
            releaseNotesPath: nil,
            targetPath: "target.aar",
            targetHash: "abc",
            targetSize: 1000
        )
        let release2 = ReleaseInfo(
            displayVersion: "2.0",
            bundleVersion: 200,
            channel: "stable",
            isCritical: false,
            releaseNotesPath: nil,
            targetPath: "target.aar",
            targetHash: "abc",
            targetSize: 1000
        )
        XCTAssertEqual(release1, release2)
    }

    func testDownloadProgressFraction() {
        let progress = DownloadProgressInfo(bytesReceived: 500, totalBytes: 1000)
        XCTAssertEqual(progress.fractionComplete, 0.5, accuracy: 0.001)
    }

    func testDownloadProgressZeroTotal() {
        let progress = DownloadProgressInfo(bytesReceived: 0, totalBytes: 0)
        XCTAssertEqual(progress.fractionComplete, 0.0)
    }
}

final class ReleaseNotesRendererTests: XCTestCase {

    func testStripsScriptTags() {
        let input = "Hello <script>alert('xss')</script> World"
        let output = ReleaseNotesRenderer.render(input)
        XCTAssertFalse(output.contains("<script>"))
        XCTAssertFalse(output.contains("alert"))
        XCTAssertTrue(output.contains("Hello"))
        XCTAssertTrue(output.contains("World"))
    }

    func testStripsEventHandlers() {
        let input = "Click <img onerror=\"alert('xss')\" src=\"x\">"
        let output = ReleaseNotesRenderer.render(input)
        XCTAssertFalse(output.contains("onerror"))
    }

    func testStripsJavascriptURLs() {
        let input = "Link: javascript:alert('xss')"
        let output = ReleaseNotesRenderer.render(input)
        XCTAssertFalse(output.contains("javascript:"))
    }

    func testPreservesPlainMarkdown() {
        let input = "# Release Notes\n\n- Fixed bug\n- Improved performance"
        let output = ReleaseNotesRenderer.render(input)
        XCTAssertTrue(output.contains("# Release Notes"))
        XCTAssertTrue(output.contains("- Fixed bug"))
    }

    func testStripsIframeTags() {
        let input = "Before <iframe src=\"https://evil.com\"></iframe> After"
        let output = ReleaseNotesRenderer.render(input)
        XCTAssertFalse(output.contains("<iframe"))
        XCTAssertTrue(output.contains("Before"))
        XCTAssertTrue(output.contains("After"))
    }
}
