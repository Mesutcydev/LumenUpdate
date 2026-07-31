import XCTest
import LumenCore
@testable import LumenArchive

final class PathNormalizerTests: XCTestCase {

    func testNormalizesSimplePath() throws {
        XCTAssertEqual(try PathNormalizer.normalize("Contents/MacOS/MyApp"), "Contents/MacOS/MyApp")
    }

    func testNormalizesDotComponents() throws {
        XCTAssertEqual(try PathNormalizer.normalize("Contents/./MacOS/./MyApp"), "Contents/MacOS/MyApp")
    }

    func testRejectsDotDotTraversal() {
        XCTAssertThrowsError(try PathNormalizer.normalize("Contents/../../../etc/passwd")) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "archive.pathTraversal")
        }
    }

    func testRejectsAbsolutePath() {
        XCTAssertThrowsError(try PathNormalizer.normalize("/etc/passwd")) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "archive.pathTraversal")
        }
    }

    func testRejectsNULCharacter() {
        XCTAssertThrowsError(try PathNormalizer.normalize("Contents/\0MacOS")) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "archive.pathTraversal")
        }
    }

    func testRejectsEmptyPath() {
        XCTAssertThrowsError(try PathNormalizer.normalize("")) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "archive.pathTraversal")
        }
    }

    func testRejectsDotDotOnly() {
        XCTAssertThrowsError(try PathNormalizer.normalize("..")) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "archive.pathTraversal")
        }
    }

    func testIsWithinStagingRoot() {
        XCTAssertTrue(PathNormalizer.isWithinStagingRoot("Contents/MacOS/MyApp", stagingRoot: "/tmp/staging"))
        XCTAssertFalse(PathNormalizer.isWithinStagingRoot("../etc/passwd", stagingRoot: "/tmp/staging"))
    }
}

final class ArchiveEntryValidatorTests: XCTestCase {

    func testRejectsSetuidFile() {
        var seen = Set<String>()
        var totalSize: Int64 = 0
        let entry = ArchiveEntryInfo(path: "Contents/MacOS/evil", type: .file, mode: 0o4755, size: 100)
        XCTAssertThrowsError(try ArchiveEntryValidator.validateEntry(
            entry, limits: .default, stagingRoot: "/tmp/staging",
            seenPaths: &seen, totalUncompressedSize: &totalSize
        )) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "archive.setuidNotAllowed")
        }
    }

    func testRejectsSetgidFile() {
        var seen = Set<String>()
        var totalSize: Int64 = 0
        let entry = ArchiveEntryInfo(path: "Contents/MacOS/evil", type: .file, mode: 0o2755, size: 100)
        XCTAssertThrowsError(try ArchiveEntryValidator.validateEntry(
            entry, limits: .default, stagingRoot: "/tmp/staging",
            seenPaths: &seen, totalUncompressedSize: &totalSize
        )) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "archive.setuidNotAllowed")
        }
    }

    func testRejectsDeviceFile() {
        var seen = Set<String>()
        var totalSize: Int64 = 0
        let entry = ArchiveEntryInfo(path: "Contents/dev", type: .device, mode: 0o600, size: 0)
        XCTAssertThrowsError(try ArchiveEntryValidator.validateEntry(
            entry, limits: .default, stagingRoot: "/tmp/staging",
            seenPaths: &seen, totalUncompressedSize: &totalSize
        )) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "archive.deviceFileNotAllowed")
        }
    }

    func testRejectsSocketFile() {
        var seen = Set<String>()
        var totalSize: Int64 = 0
        let entry = ArchiveEntryInfo(path: "Contents/sock", type: .socket, mode: 0o600, size: 0)
        XCTAssertThrowsError(try ArchiveEntryValidator.validateEntry(
            entry, limits: .default, stagingRoot: "/tmp/staging",
            seenPaths: &seen, totalUncompressedSize: &totalSize
        )) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "archive.socketNotAllowed")
        }
    }

    func testRejectsFIFOFile() {
        var seen = Set<String>()
        var totalSize: Int64 = 0
        let entry = ArchiveEntryInfo(path: "Contents/fifo", type: .fifo, mode: 0o600, size: 0)
        XCTAssertThrowsError(try ArchiveEntryValidator.validateEntry(
            entry, limits: .default, stagingRoot: "/tmp/staging",
            seenPaths: &seen, totalUncompressedSize: &totalSize
        )) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "archive.fifoNotAllowed")
        }
    }

    func testRejectsHardlink() {
        var seen = Set<String>()
        var totalSize: Int64 = 0
        let entry = ArchiveEntryInfo(path: "Contents/link", type: .hardlink, mode: 0o644, size: 0)
        XCTAssertThrowsError(try ArchiveEntryValidator.validateEntry(
            entry, limits: .default, stagingRoot: "/tmp/staging",
            seenPaths: &seen, totalUncompressedSize: &totalSize
        )) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "archive.hardlinkNotAllowed")
        }
    }

    func testRejectsDuplicateEntry() {
        var seen = Set<String>()
        var totalSize: Int64 = 0
        let entry = ArchiveEntryInfo(path: "Contents/MacOS/MyApp", type: .file, mode: 0o755, size: 100)
        XCTAssertNoThrow(try ArchiveEntryValidator.validateEntry(
            entry, limits: .default, stagingRoot: "/tmp/staging",
            seenPaths: &seen, totalUncompressedSize: &totalSize
        ))
        XCTAssertThrowsError(try ArchiveEntryValidator.validateEntry(
            entry, limits: .default, stagingRoot: "/tmp/staging",
            seenPaths: &seen, totalUncompressedSize: &totalSize
        )) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "archive.duplicateEntry")
        }
    }

    func testRejectsExcessiveSize() {
        var seen = Set<String>()
        var totalSize: Int64 = 0
        let limits = ArchiveValidationLimits(maxUncompressedSize: 100)
        let entry = ArchiveEntryInfo(path: "Contents/big", type: .file, mode: 0o644, size: 200)
        XCTAssertThrowsError(try ArchiveEntryValidator.validateEntry(
            entry, limits: limits, stagingRoot: "/tmp/staging",
            seenPaths: &seen, totalUncompressedSize: &totalSize
        )) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "archive.excessiveSize")
        }
    }

    func testRejectsExcessiveNesting() {
        var seen = Set<String>()
        var totalSize: Int64 = 0
        let limits = ArchiveValidationLimits(maxNestingDepth: 3)
        let deepPath = "a/b/c/d/e/file.txt"
        let entry = ArchiveEntryInfo(path: deepPath, type: .file, mode: 0o644, size: 10)
        XCTAssertThrowsError(try ArchiveEntryValidator.validateEntry(
            entry, limits: limits, stagingRoot: "/tmp/staging",
            seenPaths: &seen, totalUncompressedSize: &totalSize
        )) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "archive.excessiveNesting")
        }
    }

    func testAcceptsValidFile() {
        var seen = Set<String>()
        var totalSize: Int64 = 0
        let entry = ArchiveEntryInfo(path: "Contents/MacOS/MyApp", type: .file, mode: 0o755, size: 1024)
        XCTAssertNoThrow(try ArchiveEntryValidator.validateEntry(
            entry, limits: .default, stagingRoot: "/tmp/staging",
            seenPaths: &seen, totalUncompressedSize: &totalSize
        ))
        XCTAssertEqual(totalSize, 1024)
    }

    func testRejectsExcessiveEntryCount() {
        XCTAssertThrowsError(try ArchiveEntryValidator.validateEntryCount(
            100_000, limits: ArchiveValidationLimits(maxEntries: 50_000)
        )) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "archive.excessiveEntries")
        }
    }
}

final class BundleManifestVerifierTests: XCTestCase {

    func testLoadsValidManifest() throws {
        let json = """
        {
          "schemaVersion": 1,
          "bundleIdentifier": "com.example.app",
          "bundleVersion": 42,
          "entries": [
            {"path": "Contents/MacOS/App", "type": "file", "mode": 493, "size": 100, "sha256": "abc"}
          ]
        }
        """
        let manifest = try BundleManifestVerifier.loadManifest(from: Data(json.utf8))
        XCTAssertEqual(manifest.bundleIdentifier, "com.example.app")
        XCTAssertEqual(manifest.bundleVersion, 42)
        XCTAssertEqual(manifest.entries.count, 1)
    }

    func testRejectsInvalidManifestJSON() {
        XCTAssertThrowsError(try BundleManifestVerifier.loadManifest(from: Data("not json".utf8))) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "archive.invalid")
        }
    }

    func testVerifiesManifestHash() throws {
        let data = Data("test manifest".utf8)
        let hash = Base64URL.encode(LumenSHA256.hash(data: data))
        XCTAssertNoThrow(try BundleManifestVerifier.verifyManifestHash(data, expectedHash: hash))
    }

    func testRejectsWrongManifestHash() {
        let data = Data("test manifest".utf8)
        XCTAssertThrowsError(try BundleManifestVerifier.verifyManifestHash(data, expectedHash: "wronghash")) { error in
            guard let e = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(e.code, "install.bundleManifestMismatch")
        }
    }
}
