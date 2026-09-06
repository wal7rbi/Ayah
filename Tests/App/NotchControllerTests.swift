import AppKit
import AyahKit
import XCTest
@testable import Ayah

@MainActor
final class NotchControllerTests: XCTestCase {
    private final class Panel: NotchPanelPresenting {
        var isVisible = false
        var frame = CGRect.zero
        var animations: [(CGRect, Bool, @MainActor () -> Void)] = []
        func place(at frame: CGRect) { self.frame = frame }
        func show() { isVisible = true }
        func hide() { isVisible = false }
        func animate(to frame: CGRect, opening: Bool, completion: @escaping @MainActor () -> Void) {
            self.frame = frame
            animations.append((frame, opening, completion))
        }
    }

    private let external = NotchScreen(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055), notchFrame: nil)
    private let builtIn = NotchScreen(
        frame: CGRect(x: -1512, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: -1512, y: 0, width: 1512, height: 950),
        notchFrame: CGRect(x: -856, y: 950, width: 200, height: 32))

    private func withViewModel(_ run: (NotchViewModel) throws -> Void) throws {
        let name = "com.ayah.presentation-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        settings.settings.isVerseDisplayEnabled = false
        let lastShown = LastShownStore(defaults: defaults)
        lastShown.save(.prayerAlert(LastShownPrayerAlertRecord(prayerKey: "fajr", fireDate: Date(),
                                                            reminderOffsetMinutes: 0, ayahID: nil, shownAt: Date())))
        let model = NotchViewModel(quranRepository: nil, verseScheduler: nil, prayerAlertScheduler: nil,
                                   settingsStore: settings, lastShownStore: lastShown)
        try run(model)
    }

    func testSwitchingDisplaysRetainsContentAndReplacesOnlyPresentation() throws {
        try withViewModel { model in
            var screens = [builtIn, external]
            var panels: [Panel] = []
            var modes: [Bool] = []
            let controller = NotchController(viewModel: model, screens: { screens }, makePanel: { _, physical in
                let panel = Panel(); panels.append(panel); modes.append(physical); return panel
            }, reduceMotion: { true })
            controller.attachToNotchIfAvailable()
            XCTAssertEqual(modes, [true])
            XCTAssertTrue(panels[0].isVisible)
            let content = model.content
            model.isExpanded = true
            screens = [external]
            controller.refreshPresentation()
            XCTAssertEqual(modes, [true, false])
            XCTAssertFalse(panels[0].isVisible)
            XCTAssertTrue(panels[1].isVisible)
            XCTAssertEqual(panels[1].frame.maxY, external.visibleFrame.maxY - 20)
            XCTAssertEqual(panels[1].frame.midX, external.frame.midX)
            XCTAssertEqual(model.content, content)
            XCTAssertTrue(model.isExpanded)
            controller.refreshPresentation()
            controller.attachToNotchIfAvailable()
            XCTAssertEqual(panels.count, 2)
            screens = [builtIn, external]
            controller.refreshPresentation()
            XCTAssertEqual(modes, [true, false, true])
            XCTAssertFalse(panels[1].isVisible)
            XCTAssertTrue(panels[2].isVisible)
        }
    }

    func testNewExpansionInvalidatesPendingCloseAndKeepsTextState() throws {
        try withViewModel { model in
            let panel = Panel()
            let controller = NotchController(viewModel: model, screens: { [self.external] },
                                              makePanel: { _, _ in panel }, reduceMotion: { false })
            controller.attachToNotchIfAvailable()
            XCTAssertFalse(panel.isVisible)
            model.isExpanded = true
            XCTAssertTrue(panel.isVisible)
            XCTAssertEqual(panel.animations.last?.1, true)
            model.isExpanded = false
            XCTAssertTrue(panel.isVisible, "Keep the window mounted until its whole-card slide finishes")
            let oldClose = try XCTUnwrap(panel.animations.last).2
            model.isExpanded = true
            oldClose()
            XCTAssertTrue(panel.isVisible)
            model.isExpanded = false
            let close = try XCTUnwrap(panel.animations.last)
            XCTAssertEqual(close.0.minY, external.frame.maxY, "Entire card must finish above the screen")
            close.2()
            XCTAssertFalse(panel.isVisible)
        }
    }

    func testNoScreenAndModeChangesInvalidateOldClose() throws {
        try withViewModel { model in
            var screens = [external]
            var panels: [Panel] = []
            let controller = NotchController(viewModel: model, screens: { screens }, makePanel: { _, _ in
                let panel = Panel(); panels.append(panel); return panel
            }, reduceMotion: { false })
            controller.attachToNotchIfAvailable()
            model.isExpanded = true
            model.isExpanded = false
            let close = try XCTUnwrap(panels[0].animations.last).2
            screens = []
            controller.refreshPresentation()
            XCTAssertFalse(panels[0].isVisible)
            model.isExpanded = true
            screens = [builtIn]
            controller.refreshPresentation()
            close()
            XCTAssertTrue(panels[1].isVisible)
            XCTAssertTrue(model.isExpanded)
        }
    }

    func testReducedMotionHasNoTravelOrDelayedDismissal() throws {
        try withViewModel { model in
            let panel = Panel()
            let controller = NotchController(viewModel: model, screens: { [self.external] },
                                              makePanel: { _, _ in panel }, reduceMotion: { true })
            controller.attachToNotchIfAvailable()
            model.isExpanded = true
            XCTAssertTrue(panel.isVisible)
            XCTAssertEqual(panel.frame.maxY, external.visibleFrame.maxY - 20)
            model.isExpanded = false
            XCTAssertFalse(panel.isVisible)
            XCTAssertTrue(panel.animations.isEmpty)
        }
    }
}
