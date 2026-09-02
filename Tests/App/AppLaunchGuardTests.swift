import AppKit
import XCTest
@testable import Ayah

/// `AyahTests` is app-hosted, so XCTest injects it into a real running
/// `Ayah` process. `AppDelegate.applicationDidFinishLaunching` therefore
/// has to recognise a test run and stand down — otherwise every test in
/// this bundle would execute alongside a fully launched app that had
/// already opened its panel, started both schedulers against their real
/// repositories, and begun writing to the user's real preferences.
///
/// That guard is invisible in normal use, so it gets its own check here:
/// if the detection it relies on ever stops working, this fails loudly
/// instead of the suite quietly acquiring a live app underneath it.
@MainActor
final class AppLaunchGuardTests: XCTestCase {
    func testTheHostAppDidNotLaunchItsUI() {
        XCTAssertFalse(
            NSApp.windows.contains { $0 is NotchPanel },
            "The host app launched for real during a test run — AppDelegate's test guard is not working."
        )
    }
}
