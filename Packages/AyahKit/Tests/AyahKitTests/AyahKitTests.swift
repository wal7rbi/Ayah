import XCTest
@testable import AyahKit

final class AyahKitTests: XCTestCase {
    func testVersionMatchesStableRelease() {
        XCTAssertEqual(AyahKit.version, "1.0.0")
    }
}
