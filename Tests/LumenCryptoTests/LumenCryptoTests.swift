import XCTest

@testable import LumenCrypto
import LumenTesting

final class LumenCryptoTests: XCTestCase {
    func testPackageSkeletonImports() {
        _ = LumenCrypto.self
        _ = LumenTesting.FixtureNamespace()
        XCTAssertFalse(false)
    }
}
