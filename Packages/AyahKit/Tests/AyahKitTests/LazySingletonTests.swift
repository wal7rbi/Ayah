import XCTest
@testable import AyahKit

/// Regression coverage for the `StatusItemController.showCityPicker()`
/// orphaned-window bug: reopening a lazily-created window/controller used
/// to create a second instance instead of reusing the first, leaving the
/// old one on screen and making callbacks act on the wrong instance.
/// `App/` (where the real `NSWindowController` subclasses live) has no
/// test target, so this exercises the same reuse mechanism `StatusItemController`
/// now uses for both its window controllers, via a plain, AppKit-free type.
final class LazySingletonTests: XCTestCase {
    private final class Dummy {}

    func testGetOrCreateReusesTheSameInstanceOnRepeatedCalls() {
        let slot = LazySingleton<Dummy>()
        var creationCount = 0

        let first = slot.getOrCreate {
            creationCount += 1
            return Dummy()
        }
        let second = slot.getOrCreate {
            creationCount += 1
            return Dummy()
        }
        let third = slot.getOrCreate {
            creationCount += 1
            return Dummy()
        }

        XCTAssertTrue(first === second, "a repeated getOrCreate call must return the existing instance, not an orphaned new one")
        XCTAssertTrue(second === third)
        XCTAssertEqual(creationCount, 1, "the factory closure must never run more than once across repeated calls")
    }

    func testCurrentAlwaysReflectsTheSingleReusedInstance() {
        let slot = LazySingleton<Dummy>()
        XCTAssertNil(slot.current, "no instance should exist before the first getOrCreate call")

        let created = slot.getOrCreate { Dummy() }
        XCTAssertTrue(slot.current === created)

        // A second call (simulating reopening the window) must leave
        // `current` pointing at the same instance — this is what a
        // closure capturing `self?.slot.current` (as the city picker's
        // onSelect does) relies on to always act on the right instance.
        _ = slot.getOrCreate { Dummy() }
        XCTAssertTrue(slot.current === created)
    }
}
