import XCTest
@testable import AyahKit

final class AyahKitTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertFalse(AyahKit.version.isEmpty)
    }
}
