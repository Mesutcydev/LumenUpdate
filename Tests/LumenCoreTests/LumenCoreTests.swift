import XCTest

@testable import LumenCore
import LumenTesting

final class LumenCoreTests: XCTestCase {
    func testPackageSkeletonImports() {
        _ = LumenCore.self
        _ = LumenTesting.FixtureNamespace()
        XCTAssertTrue(true)
    }
}
