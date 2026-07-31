// LumenTUFTFTests.swift
// Comprehensive tests for the TUF verification pipeline.

import XCTest
import LumenCore
import LumenCrypto
import LumenTUF
import LumenTesting

final class TUFVerifierTests: XCTestCase {

    // MARK: - Valid repository acceptance

    func testValidRepositoryIsAccepted() throws {
        let bundle = try TestFixtures.makeRoot()

        // Create target payload
        let targetPayload = Data(repeating: 0x42, count: 1000)
        let targetHash = TestFixtures.sha256Base64(targetPayload)

        // Create targets
        let targetsData = try TestFixtures.makeTargets(
            productID: "com.example.testapp",
            bundleVersion: 2,
            signedBy: bundle.targetsKey,
            bundleManifestSHA256: targetHash
        )

        // Create snapshot
        let snapshotData = try TestFixtures.makeSnapshot(
            targetsLength: targetsData.count,
            targetsHash: TestFixtures.sha256Base64(targetsData),
            signedBy: bundle.snapshotKey
        )

        // Create timestamp
        let timestampData = try TestFixtures.makeTimestamp(
            snapshotLength: snapshotData.count,
            snapshotHash: TestFixtures.sha256Base64(snapshotData),
            signedBy: bundle.timestampKey
        )

        let host = HostProfile(
            productID: "com.example.testapp",
            bundleIdentifier: "com.example.testapp",
            currentBundleVersion: 1,
            architecture: "arm64",
            macOSVersion: "14.0",
            channel: "stable"
        )

        let inputs = VerificationInputs(
            trustRoot: bundle.trustRoot,
            timestampData: timestampData,
            snapshotData: snapshotData,
            targetsData: targetsData,
            host: host
        )

        let result = try TUFVerifier.verify(inputs: inputs)
        XCTAssertEqual(result.resolvedTarget.custom.productID, "com.example.testapp")
        XCTAssertEqual(result.resolvedTarget.custom.bundleVersion, 2)
    }

    // MARK: - Invalid signature rejection

    func testInvalidSignatureIsRejected() throws {
        let bundle = try TestFixtures.makeRoot()

        // Create timestamp signed with a different key
        let attackerKey = try TestFixtures.TestKey()
        let timestampData = try TestFixtures.makeTimestamp(
            snapshotLength: 100,
            snapshotHash: "fakehash",
            signedBy: attackerKey
        )

        let snapshotData = try TestFixtures.makeSnapshot(
            targetsLength: 100,
            targetsHash: "fakehash",
            signedBy: bundle.snapshotKey
        )

        let targetsData = try TestFixtures.makeTargets(
            signedBy: bundle.targetsKey
        )

        let host = HostProfile(
            productID: "com.example.testapp",
            bundleIdentifier: "com.example.testapp",
            currentBundleVersion: 1,
            architecture: "arm64",
            macOSVersion: "14.0",
            channel: "stable"
        )

        let inputs = VerificationInputs(
            trustRoot: bundle.trustRoot,
            timestampData: timestampData,
            snapshotData: snapshotData,
            targetsData: targetsData,
            host: host
        )

        XCTAssertThrowsError(try TUFVerifier.verify(inputs: inputs)) { error in
            guard let lumenError = error as? LumenError else {
                XCTFail("Expected LumenError, got \(error)")
                return
            }
            // Should fail with signature.insufficient or signature.unknownKey
            XCTAssertTrue(
                lumenError.code == "signature.insufficient" || lumenError.code == "signature.unknownKey",
                "Expected signature error, got: \(lumenError.code) - \(lumenError.description)"
            )
        }
    }

    // MARK: - Expired metadata rejection

    func testExpiredTimestampIsRejected() throws {
        let bundle = try TestFixtures.makeRoot()

        // Create expired timestamp
        let expiredDate = ISO8601DateFormatter.lumen.string(from: Date().addingTimeInterval(-86400))
        let timestampData = try TestFixtures.makeTimestamp(
            snapshotLength: 100,
            snapshotHash: "fakehash",
            expires: expiredDate,
            signedBy: bundle.timestampKey
        )

        let snapshotData = try TestFixtures.makeSnapshot(
            targetsLength: 100,
            targetsHash: "fakehash",
            signedBy: bundle.snapshotKey
        )

        let targetsData = try TestFixtures.makeTargets(
            signedBy: bundle.targetsKey
        )

        let host = HostProfile(
            productID: "com.example.testapp",
            bundleIdentifier: "com.example.testapp",
            currentBundleVersion: 1,
            architecture: "arm64",
            macOSVersion: "14.0",
            channel: "stable"
        )

        let inputs = VerificationInputs(
            trustRoot: bundle.trustRoot,
            timestampData: timestampData,
            snapshotData: snapshotData,
            targetsData: targetsData,
            host: host
        )

        XCTAssertThrowsError(try TUFVerifier.verify(inputs: inputs)) { error in
            guard let lumenError = error as? LumenError else { XCTFail("Expected LumenError"); return }
            XCTAssertEqual(lumenError.code, "metadata.expired", "Expected expired error, got: \(lumenError.code)")
        }
    }

    // MARK: - Hash mismatch rejection (mix-and-match)

    func testHashMismatchIsRejected() throws {
        let bundle = try TestFixtures.makeRoot()

        let targetsData = try TestFixtures.makeTargets(
            signedBy: bundle.targetsKey
        )

        // Snapshot claims different hash for targets.json
        let snapshotData = try TestFixtures.makeSnapshot(
            targetsLength: targetsData.count,
            targetsHash: Base64URL.encode(Data(repeating: 0xAA, count: 32)),
            signedBy: bundle.snapshotKey
        )

        let timestampData = try TestFixtures.makeTimestamp(
            snapshotLength: snapshotData.count,
            snapshotHash: TestFixtures.sha256Base64(snapshotData),
            signedBy: bundle.timestampKey
        )

        let host = HostProfile(
            productID: "com.example.testapp",
            bundleIdentifier: "com.example.testapp",
            currentBundleVersion: 1,
            architecture: "arm64",
            macOSVersion: "14.0",
            channel: "stable"
        )

        let inputs = VerificationInputs(
            trustRoot: bundle.trustRoot,
            timestampData: timestampData,
            snapshotData: snapshotData,
            targetsData: targetsData,
            host: host
        )

        XCTAssertThrowsError(try TUFVerifier.verify(inputs: inputs)) { error in
            guard let lumenError = error as? LumenError else { XCTFail("Expected LumenError"); return }
            XCTAssertEqual(lumenError.code, "target.hashMismatch", "Expected hash mismatch, got: \(lumenError.code)")
        }
    }

    // MARK: - Length mismatch rejection

    func testLengthMismatchIsRejected() throws {
        let bundle = try TestFixtures.makeRoot()

        let targetsData = try TestFixtures.makeTargets(
            signedBy: bundle.targetsKey
        )

        let snapshotData = try TestFixtures.makeSnapshot(
            targetsLength: targetsData.count + 100,  // wrong length
            targetsHash: TestFixtures.sha256Base64(targetsData),
            signedBy: bundle.snapshotKey
        )

        let timestampData = try TestFixtures.makeTimestamp(
            snapshotLength: snapshotData.count,
            snapshotHash: TestFixtures.sha256Base64(snapshotData),
            signedBy: bundle.timestampKey
        )

        let host = HostProfile(
            productID: "com.example.testapp",
            bundleIdentifier: "com.example.testapp",
            currentBundleVersion: 1,
            architecture: "arm64",
            macOSVersion: "14.0",
            channel: "stable"
        )

        let inputs = VerificationInputs(
            trustRoot: bundle.trustRoot,
            timestampData: timestampData,
            snapshotData: snapshotData,
            targetsData: targetsData,
            host: host
        )

        XCTAssertThrowsError(try TUFVerifier.verify(inputs: inputs)) { error in
            guard let lumenError = error as? LumenError else { XCTFail("Expected LumenError"); return }
            XCTAssertEqual(lumenError.code, "target.lengthMismatch", "Expected length mismatch, got: \(lumenError.code)")
        }
    }
}

final class VersionTrackerTests: XCTestCase {

    func testAcceptsHigherVersion() throws {
        let tracker = VersionTracker()
        try tracker.validateVersion(5, forRole: "timestamp")
        tracker.acceptVersion(5, forRole: "timestamp")
        XCTAssertEqual(tracker.version(forRole: "timestamp"), 5)
    }

    func testRejectsRollback() {
        let tracker = VersionTracker()
        tracker.setVersion(5, forRole: "timestamp")
        XCTAssertThrowsError(try tracker.validateVersion(3, forRole: "timestamp")) { error in
            guard let lumenError = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(lumenError.code, "version.rollback")
        }
    }

    func testRejectsFastForward() {
        let tracker = VersionTracker(maxJump: 10)
        tracker.setVersion(1, forRole: "timestamp")
        XCTAssertThrowsError(try tracker.validateVersion(100, forRole: "timestamp")) { error in
            guard let lumenError = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(lumenError.code, "version.fastForward")
        }
    }

    func testExportAndImport() {
        let tracker = VersionTracker()
        tracker.setVersion(5, forRole: "timestamp")
        tracker.setVersion(3, forRole: "snapshot")
        let exported = tracker.export()

        let newTracker = VersionTracker()
        newTracker.import(exported)
        XCTAssertEqual(newTracker.version(forRole: "timestamp"), 5)
        XCTAssertEqual(newTracker.version(forRole: "snapshot"), 3)
    }
}

final class ExpirationTests: XCTestCase {

    func testAcceptsUnexpiredMetadata() throws {
        let futureDate = ISO8601DateFormatter.lumen.string(from: Date().addingTimeInterval(3600))
        XCTAssertNoThrow(try ExpirationChecker.checkExpiration(expires: futureDate, role: "timestamp"))
    }

    func testRejectsExpiredMetadata() {
        let pastDate = ISO8601DateFormatter.lumen.string(from: Date().addingTimeInterval(-3600))
        XCTAssertThrowsError(try ExpirationChecker.checkExpiration(expires: pastDate, role: "timestamp")) { error in
            guard let lumenError = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(lumenError.code, "metadata.expired")
        }
    }

    func testRejectsInvalidDate() {
        XCTAssertThrowsError(try ExpirationChecker.checkExpiration(expires: "not-a-date", role: "timestamp")) { error in
            guard let lumenError = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(lumenError.code, "metadata.invalidExpiration")
        }
    }
}

final class CanonicalJSONTests: XCTestCase {

    func testCanonicalizesObjectWithSortedKeys() throws {
        let value: [String: Any] = ["b": 2, "a": 1, "c": 3]
        let canonical = try CanonicalJSON.encodeToString(value)
        XCTAssertEqual(canonical, "{\"a\":1,\"b\":2,\"c\":3}")
    }

    func testCanonicalizesNestedObject() throws {
        let value: [String: Any] = ["z": ["y": 2, "x": 1], "a": "test"]
        let canonical = try CanonicalJSON.encodeToString(value)
        XCTAssertTrue(canonical.contains("\"a\":\"test\""))
        XCTAssertTrue(canonical.contains("\"z\":{\"x\":1,\"y\":2}"))
    }

    func testCanonicalizesArray() throws {
        let value: [Any] = [3, 1, 2]
        let canonical = try CanonicalJSON.encodeToString(value)
        XCTAssertEqual(canonical, "[3,1,2]")
    }

    func testEscapesSpecialCharacters() throws {
        let value: [String: Any] = ["key": "value with \"quotes\" and \\backslash"]
        let canonical = try CanonicalJSON.encodeToString(value)
        XCTAssertTrue(canonical.contains("\\\""))
        XCTAssertTrue(canonical.contains("\\\\"))
    }
}

final class SignatureVerifierTests: XCTestCase {

    func testValidSignatureIsAccepted() throws {
        let key = try TestFixtures.TestKey()
        let message = Data("hello world".utf8)
        let signature = try TestFixtures.sign(message, with: key)
        let isValid = try SignatureVerifier.verify(signature: signature, canonicalBytes: message, publicKey: key.publicKey)
        XCTAssertTrue(isValid)
    }

    func testInvalidSignatureIsRejected() throws {
        let key = try TestFixtures.TestKey()
        let message = Data("hello world".utf8)
        let signature = try TestFixtures.sign(message, with: key)
        let tamperedMessage = Data("hello WORLD".utf8)
        let isValid = try SignatureVerifier.verify(signature: signature, canonicalBytes: tamperedMessage, publicKey: key.publicKey)
        XCTAssertFalse(isValid)
    }

    func testKeyIDIsStable() throws {
        let key = try TestFixtures.TestKey()
        let keyID1 = SignatureVerifier.keyID(forPublicKey: key.publicKey)
        let keyID2 = SignatureVerifier.keyID(forPublicKey: key.publicKey)
        XCTAssertEqual(keyID1, keyID2)
        XCTAssertFalse(keyID1.isEmpty)
    }
}

final class Base64URLTests: XCTestCase {

    func testRoundTrip() throws {
        let original = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD])
        let encoded = Base64URL.encode(original)
        let decoded = try Base64URL.decode(encoded)
        XCTAssertEqual(original, decoded)
    }

    func testEncodingHasNoPadding() {
        let data = Data([0x00, 0x01, 0x02])
        let encoded = Base64URL.encode(data)
        XCTAssertFalse(encoded.contains("="))
    }

    func testDecodingRejectsInvalid() {
        XCTAssertThrowsError(try Base64URL.decode("!!!not valid base64!!!"))
    }
}

final class SHA256Tests: XCTestCase {

    func testKnownVector() {
        // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        let empty = Data()
        let hash = LumenSHA256.hash(data: empty)
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testKnownVectorHello() {
        // SHA-256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
        let hello = Data("hello".utf8)
        let hash = LumenSHA256.hash(data: hello)
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
}

final class TrustedStateTests: XCTestCase {

    func testCreateAndSave() throws {
        let state = TrustedState(
            trustRoot: TrustedState.PersistedTrustRoot(version: 1, canonicalBytes: Data("test".utf8))
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_state_\(UUID().uuidString).json")
        try TrustedStateStore.save(state, to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: url)
    }

    func testLoadReturnsNilForMissingFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent_\(UUID().uuidString).json")
        let state = try TrustedStateStore.load(from: url)
        XCTAssertNil(state)
    }

    func testRoundTrip() throws {
        let original = TrustedState(
            trustRoot: TrustedState.PersistedTrustRoot(version: 1, canonicalBytes: Data("test".utf8)),
            versions: ["timestamp": 5, "snapshot": 3],
            blockedTargets: [
                TrustedState.BlockedTarget(productID: "com.example", hash: "abc", reason: "test", blockedAt: Date())
            ]
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_state_\(UUID().uuidString).json")
        try TrustedStateStore.save(original, to: url)
        let loaded = try TrustedStateStore.load(from: url)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.versions, original.versions)
        XCTAssertEqual(loaded?.blockedTargets.count, 1)
        try? FileManager.default.removeItem(at: url)
    }
}

final class TrustRootTests: XCTestCase {

    func testBootstrapValidRoot() throws {
        let bundle = try TestFixtures.makeRoot()
        XCTAssertEqual(bundle.trustRoot.version, 1)
    }

    func testBootstrapRejectsTamperedRoot() throws {
        let bundle = try TestFixtures.makeRoot()
        var tampered = bundle.rawSignedBytes
        // Flip a bit somewhere
        let byteIndex = tampered.count / 2
        tampered[byteIndex] ^= 0xFF
        XCTAssertThrowsError(try TrustRootBootstrap.bootstrap(from: tampered))
    }
}

final class TargetResolverTests: XCTestCase {

    func testResolvesMatchingTarget() throws {
        let custom = LumenTargetCustom(
            productID: "com.example.app",
            bundleIdentifier: "com.example.app",
            bundleVersion: 2,
            shortVersion: "1.1.0",
            minimumSystemVersion: "13.0",
            architectures: ["arm64"],
            channel: "stable",
            archiveFormat: "apple-archive",
            bundleManifestSHA256: "abc",
            releaseNotesTarget: nil,
            critical: false,
            rollout: nil
        )
        let target = TUFTargetInfo(length: 1000, hashes: ["sha256": "abc"], custom: custom)
        let targets = TUFTargetsMetadata(
            version: 1,
            expires: ISO8601DateFormatter.lumen.string(from: Date().addingTimeInterval(86400)),
            targets: ["path": target],
            delegations: nil
        )

        let host = HostProfile(
            productID: "com.example.app",
            bundleIdentifier: "com.example.app",
            currentBundleVersion: 1,
            architecture: "arm64",
            macOSVersion: "14.0",
            channel: "stable"
        )

        let resolved = try TargetResolver.resolve(
            targets: targets,
            delegatedTargets: [:],
            host: host
        )
        XCTAssertEqual(resolved.custom.bundleVersion, 2)
    }

    func testRejectsLowerVersion() throws {
        let custom = LumenTargetCustom(
            productID: "com.example.app",
            bundleIdentifier: "com.example.app",
            bundleVersion: 1,  // NOT higher than host
            shortVersion: "1.0.0",
            minimumSystemVersion: "13.0",
            architectures: ["arm64"],
            channel: "stable",
            archiveFormat: "apple-archive",
            bundleManifestSHA256: "abc",
            releaseNotesTarget: nil,
            critical: false,
            rollout: nil
        )
        let target = TUFTargetInfo(length: 1000, hashes: ["sha256": "abc"], custom: custom)
        let targets = TUFTargetsMetadata(
            version: 1,
            expires: ISO8601DateFormatter.lumen.string(from: Date().addingTimeInterval(86400)),
            targets: ["path": target],
            delegations: nil
        )

        let host = HostProfile(
            productID: "com.example.app",
            bundleIdentifier: "com.example.app",
            currentBundleVersion: 5,
            architecture: "arm64",
            macOSVersion: "14.0",
            channel: "stable"
        )

        XCTAssertThrowsError(try TargetResolver.resolve(targets: targets, delegatedTargets: [:], host: host)) { error in
            guard let lumenError = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(lumenError.code, "target.lowerVersion")
        }
    }

    func testRejectsWrongArchitecture() throws {
        let custom = LumenTargetCustom(
            productID: "com.example.app",
            bundleIdentifier: "com.example.app",
            bundleVersion: 2,
            shortVersion: "1.1.0",
            minimumSystemVersion: "13.0",
            architectures: ["x86_64"],  // host is arm64
            channel: "stable",
            archiveFormat: "apple-archive",
            bundleManifestSHA256: "abc",
            releaseNotesTarget: nil,
            critical: false,
            rollout: nil
        )
        let target = TUFTargetInfo(length: 1000, hashes: ["sha256": "abc"], custom: custom)
        let targets = TUFTargetsMetadata(
            version: 1,
            expires: ISO8601DateFormatter.lumen.string(from: Date().addingTimeInterval(86400)),
            targets: ["path": target],
            delegations: nil
        )

        let host = HostProfile(
            productID: "com.example.app",
            bundleIdentifier: "com.example.app",
            currentBundleVersion: 1,
            architecture: "arm64",
            macOSVersion: "14.0",
            channel: "stable"
        )

        XCTAssertThrowsError(try TargetResolver.resolve(targets: targets, delegatedTargets: [:], host: host)) { error in
            guard let lumenError = error as? LumenError else { XCTFail(); return }
            XCTAssertEqual(lumenError.code, "target.notFound")
        }
    }

    func testMacOSVersionComparison() {
        XCTAssertTrue(TargetResolver.macOSVersion("14.0", isAtLeast: "13.0"))
        XCTAssertTrue(TargetResolver.macOSVersion("14.5", isAtLeast: "14.5"))
        XCTAssertTrue(TargetResolver.macOSVersion("14.5.1", isAtLeast: "14.5"))
        XCTAssertFalse(TargetResolver.macOSVersion("13.0", isAtLeast: "14.0"))
        XCTAssertFalse(TargetResolver.macOSVersion("13.5", isAtLeast: "13.6"))
    }
}

final class LumenErrorTests: XCTestCase {

    func testErrorCodesAreStable() {
        XCTAssertEqual(LumenError.targetHashMismatch(expected: "a", actual: "b").code, "target.hashMismatch")
        XCTAssertEqual(LumenError.expiredMetadata(role: "x", expiredAt: "y", now: "z").code, "metadata.expired")
        XCTAssertEqual(LumenError.versionRollback(role: "x", received: 1, stored: 2).code, "version.rollback")
        XCTAssertEqual(LumenError.insufficientSignatures(role: "x", required: 2, provided: 1).code, "signature.insufficient")
    }

    func testErrorDescriptionsAreNonEmpty() {
        let error = LumenError.targetHashMismatch(expected: "expected_hash", actual: "actual_hash")
        XCTAssertFalse(error.description.isEmpty)
        XCTAssertTrue(error.description.contains("expected_hash"))
    }
}
