import XCTest
import LumenCore
@testable import LumenSparkleMigration

final class AppcastImporterTests: XCTestCase {

    let sampleAppcast = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <title>MyApp Updates</title>
        <item>
          <title>Version 2.0</title>
          <pubDate>Mon, 01 Jan 2026 00:00:00 +0000</pubDate>
          <sparkle:version>200</sparkle:version>
          <sparkle:shortVersionString>2.0</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
          <sparkle:releaseNotesLink>https://example.com/notes/2.0.html</sparkle:releaseNotesLink>
          <enclosure url="https://example.com/MyApp-2.0.zip"
                     length="10485760"
                     type="application/octet-stream"
                     sparkle:version="200"
                     sparkle:shortVersionString="2.0"
                     sparkle:edSignature="abc123signature" />
        </item>
        <item>
          <title>Version 1.5</title>
          <pubDate>Mon, 01 Dec 2025 00:00:00 +0000</pubDate>
          <enclosure url="https://example.com/MyApp-1.5.zip"
                     length="8388608"
                     sparkle:version="150"
                     sparkle:shortVersionString="1.5" />
        </item>
      </channel>
    </rss>
    """

    func testParsesAppcastTitle() throws {
        let appcast = try AppcastImporter.parse(xmlString: sampleAppcast)
        XCTAssertEqual(appcast.title, "MyApp Updates")
    }

    func testParsesAppcastItems() throws {
        let appcast = try AppcastImporter.parse(xmlString: sampleAppcast)
        XCTAssertEqual(appcast.items.count, 2)
    }

    func testParsesItemFields() throws {
        let appcast = try AppcastImporter.parse(xmlString: sampleAppcast)
        let item = appcast.items[0]
        XCTAssertEqual(item.title, "Version 2.0")
        XCTAssertEqual(item.version, "200")
        XCTAssertEqual(item.shortVersion, "2.0")
        XCTAssertEqual(item.downloadURL, "https://example.com/MyApp-2.0.zip")
        XCTAssertEqual(item.length, 10485760)
        XCTAssertEqual(item.minimumSystemVersion, "13.0")
        XCTAssertEqual(item.edSignature, "abc123signature")
    }

    func testParsesSecondItem() throws {
        let appcast = try AppcastImporter.parse(xmlString: sampleAppcast)
        let item = appcast.items[1]
        XCTAssertEqual(item.version, "150")
        XCTAssertEqual(item.shortVersion, "1.5")
        XCTAssertEqual(item.downloadURL, "https://example.com/MyApp-1.5.zip")
    }

    func testConvertsToLumenTargets() throws {
        let appcast = try AppcastImporter.parse(xmlString: sampleAppcast)
        let targets = AppcastImporter.convertToLumenTargets(appcast, productID: "com.example.myapp")
        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets[0].version, 200)
        XCTAssertEqual(targets[0].shortVersion, "2.0")
        XCTAssertEqual(targets[1].version, 150)
    }

    func testRejectsInvalidXML() {
        XCTAssertThrowsError(try AppcastImporter.parse(xmlString: "not xml at all")) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "metadata.invalidFormat")
        }
    }

    func testHandlesEmptyAppcast() throws {
        let emptyAppcast = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0"><channel><title>Empty</title></channel></rss>
        """
        let appcast = try AppcastImporter.parse(xmlString: emptyAppcast)
        XCTAssertEqual(appcast.title, "Empty")
        XCTAssertEqual(appcast.items.count, 0)
    }
}

final class MigrationBridgeTests: XCTestCase {

    func testCreatesMigrationPlan() throws {
        let appcast = SparkleAppcast(title: "Test", items: [
            SparkleAppcastItem(title: "v2", version: "200", shortVersion: "2.0", downloadURL: "https://example.com/2.zip"),
            SparkleAppcastItem(title: "v1", version: "100", shortVersion: "1.0", downloadURL: "https://example.com/1.zip"),
        ])

        let plan = MigrationBridge.createMigrationPlan(
            appcast: appcast,
            productID: "com.example.app",
            lumenRootMetadata: Data("root".utf8)
        )

        XCTAssertEqual(plan.productID, "com.example.app")
        XCTAssertEqual(plan.bridgeVersion, 201)
        XCTAssertEqual(plan.steps.count, 7)
        XCTAssertEqual(plan.sparkleReleases.count, 2)
        XCTAssertEqual(plan.sparkleReleases[0].version, "200")
    }

    func testCannotMigrateWithoutSparkleKey() {
        XCTAssertFalse(MigrationBridge.canMigrateWithoutSparkleKey())
    }

    func testMigrationStepsAreOrdered() throws {
        let appcast = SparkleAppcast(title: "Test", items: [])
        let plan = MigrationBridge.createMigrationPlan(
            appcast: appcast,
            productID: "com.example.app",
            lumenRootMetadata: Data()
        )
        for (i, step) in plan.steps.enumerated() {
            XCTAssertEqual(step.order, i + 1)
        }
    }
}

final class MigrationDiagnosticsTests: XCTestCase {

    func testDiagnosesNonexistentBundle() {
        let diagnostics = MigrationDiagnosticsRunner.diagnose(bundlePath: "/nonexistent/path/MyApp.app")
        XCTAssertFalse(diagnostics.hasSparkleFramework)
        XCTAssertFalse(diagnostics.hasLumenFramework)
        XCTAssertFalse(diagnostics.hasBundledRoot)
        XCTAssertEqual(diagnostics.migrationState, .notStarted)
    }

    func testMigrationStateRawValues() {
        XCTAssertEqual(MigrationDiagnostics.MigrationState.notStarted.rawValue, "notStarted")
        XCTAssertEqual(MigrationDiagnostics.MigrationState.complete.rawValue, "complete")
        XCTAssertEqual(MigrationDiagnostics.MigrationState.bridgeReleaseInstalled.rawValue, "bridgeReleaseInstalled")
    }
}
