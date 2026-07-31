import XCTest
import Foundation
import LumenCore
@testable import LumenArchive

/// Verifies the real Apple Archive framework round-trips files through
/// encode → decode, and that SafeExtractor routes `.aar` correctly and
/// enforces security rules on the extracted tree.
final class AppleArchiveTests: XCTestCase {

    private let fm = FileManager.default

    private func tempDir(_ label: String) -> URL {
        fm.temporaryDirectory.appendingPathComponent("aar-\(label)-\(UUID().uuidString)")
    }

    func testRoundTripPreservesFileContents() throws {
        let sourceDir = tempDir("src")
        let archiveURL = tempDir("archive").appendingPathComponent("bundle.aar")
        let stagingDir = tempDir("stage")
        defer {
            try? fm.removeItem(at: sourceDir)
            try? fm.removeItem(at: archiveURL.deletingLastPathComponent())
            try? fm.removeItem(at: stagingDir)
        }

        // Build a fake .app bundle structure.
        let macosDir = sourceDir.appendingPathComponent("MyApp.app/Contents/MacOS")
        try fm.createDirectory(at: macosDir, withIntermediateDirectories: true)
        let executableData = Data("#!/bin/sh\necho hello lumen\n".utf8)
        try executableData.write(to: macosDir.appendingPathComponent("MyApp"))
        let infoData = Data("<plist>info</plist>".utf8)
        try infoData.write(to: sourceDir.appendingPathComponent("MyApp.app/Contents/Info.plist"))

        // Encode to a real .aar via the Apple Archive framework.
        try AppleArchiveCodec.encode(directory: sourceDir, to: archiveURL)
        XCTAssertTrue(fm.fileExists(atPath: archiveURL.path))

        // Extract via SafeExtractor (must route .aar to AppleArchiveCodec).
        _ = try SafeExtractor.extract(archiveURL: archiveURL, to: stagingDir)

        // The files must survive with byte-identical contents.
        let extractedExec = stagingDir.appendingPathComponent("MyApp.app/Contents/MacOS/MyApp")
        let extractedInfo = stagingDir.appendingPathComponent("MyApp.app/Contents/Info.plist")
        XCTAssertEqual(try Data(contentsOf: extractedExec), executableData)
        XCTAssertEqual(try Data(contentsOf: extractedInfo), infoData)
    }

    func testFormatDetection() {
        XCTAssertTrue(AppleArchiveCodec.isAppleArchive(URL(fileURLWithPath: "/tmp/foo.aar")))
        XCTAssertTrue(AppleArchiveCodec.isAppleArchive(URL(fileURLWithPath: "/tmp/foo.AAR")))
        XCTAssertFalse(AppleArchiveCodec.isAppleArchive(URL(fileURLWithPath: "/tmp/foo.tar.gz")))
        XCTAssertFalse(AppleArchiveCodec.isAppleArchive(URL(fileURLWithPath: "/tmp/foo.zip")))
    }

    func testSetuidBinaryRejectedAfterExtraction() throws {
        let sourceDir = tempDir("setuid-src")
        let archiveURL = tempDir("setuid-archive").appendingPathComponent("bundle.aar")
        let stagingDir = tempDir("setuid-stage")
        defer {
            try? fm.removeItem(at: sourceDir)
            try? fm.removeItem(at: archiveURL.deletingLastPathComponent())
            try? fm.removeItem(at: stagingDir)
        }

        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let evilPath = sourceDir.appendingPathComponent("evil")
        try Data("malicious-binary".utf8).write(to: evilPath)
        // Set the setuid bit; Apple Archive's "MOD" key preserves it through the round trip.
        try fm.setAttributes([.posixPermissions: 0o4755], ofItemAtPath: evilPath.path)

        try AppleArchiveCodec.encode(directory: sourceDir, to: archiveURL)

        // The post-extraction security scan must reject the setuid file.
        XCTAssertThrowsError(try SafeExtractor.extract(archiveURL: archiveURL, to: stagingDir)) { error in
            guard let e = error as? LumenError else {
                XCTFail("Expected LumenError, got \(error)")
                return
            }
            XCTAssertEqual(e.code, "archive.setuidNotAllowed")
        }
    }
}
