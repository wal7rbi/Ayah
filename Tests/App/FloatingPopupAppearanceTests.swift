import AppKit
import AyahKit
import SwiftUI
import XCTest
@testable import Ayah

@MainActor
final class FloatingPopupAppearanceTests: XCTestCase {
    func testFloatingCardIsBlackRoundedAndKeepsContentWhileClosing() throws {
        let name = "com.ayah.appearance-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let lastShown = LastShownStore(defaults: defaults)
        lastShown.save(.prayerAlert(LastShownPrayerAlertRecord(
            prayerKey: "fajr", fireDate: Date(), reminderOffsetMinutes: 5, ayahID: nil, shownAt: Date())))
        let model = NotchViewModel(quranRepository: nil, verseScheduler: nil, prayerAlertScheduler: nil,
                                   settingsStore: SettingsStore(defaults: defaults), lastShownStore: lastShown)
        // Collapsed state is also the closing slide: the card must remain intact until orderOut.
        model.isExpanded = false
        let view = NSHostingView(rootView: NotchContentView(viewModel: model, mode: .floatingCard))
        view.frame = CGRect(origin: .zero, size: NotchMetrics.expandedSize)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let sx = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let sy = CGFloat(bitmap.pixelsHigh) / view.bounds.height
        func color(_ x: CGFloat, _ y: CGFloat) throws -> NSColor {
            try XCTUnwrap(bitmap.colorAt(x: Int(x * sx), y: Int(y * sy))?.usingColorSpace(.deviceRGB))
        }
        let background = try color(30, 30)
        XCTAssertEqual(background.alphaComponent, 1, accuracy: 0.01)
        XCTAssertLessThan(background.redComponent, 0.01)
        XCTAssertLessThan(background.greenComponent, 0.01)
        XCTAssertLessThan(background.blueComponent, 0.01)
        for (x, y) in [(CGFloat(0), CGFloat(0)), (479, 0), (0, 219), (479, 219)] {
            XCTAssertLessThan(try color(x, y).alphaComponent, 0.1)
        }
        var whitePixels = 0
        for y in 60..<160 {
            for x in 80..<400 {
                if try color(CGFloat(x), CGFloat(y)).redComponent > 0.6 { whitePixels += 1 }
            }
        }
        XCTAssertGreaterThan(whitePixels, 50, "Prayer text remains visible during the closing slide")
        let attachment = XCTAttachment(data: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])),
                                       uniformTypeIdentifier: "public.png")
        attachment.name = "Black floating prayer popup"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCollapsedFloatingTabRendersArabicLabelInsideCompactBounds() throws {
        let name = "com.ayah.tab-appearance-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = NotchViewModel(quranRepository: nil, verseScheduler: nil, prayerAlertScheduler: nil,
                                  settingsStore: SettingsStore(defaults: defaults),
                                  lastShownStore: LastShownStore(defaults: defaults))
        model.isExpanded = false
        let view = NotchHoverHostingView(viewModel: model, mode: .floatingTab)
        view.frame = CGRect(origin: .zero, size: FloatingPopupMetrics.tabSize)
        view.layoutSubtreeIfNeeded()
        view.updateTrackingAreas()
        XCTAssertEqual(view.bounds.size, CGSize(width: 64, height: 24))
        let tracking = try XCTUnwrap(view.trackingAreas.first { $0.options.contains(.activeAlways) })
        XCTAssertTrue(tracking.options.contains(.inVisibleRect))
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        var whitePixels = 0
        var blackPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if color.alphaComponent > 0.9 {
                    if color.redComponent > 0.6 { whitePixels += 1 }
                    if color.redComponent < 0.01 { blackPixels += 1 }
                }
            }
        }
        XCTAssertGreaterThan(whitePixels, 10, "The collapsed tab has a visible Arabic label")
        XCTAssertGreaterThan(blackPixels, 300, "The tab has an opaque black background")
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0.1)
    }

    func testResizingKeepsTrackingAreaAndIgnoresFalseExit() throws {
        let name = "com.ayah.hover-resize-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let timer = HoverTimer()
        // Hover only reveals existing content, so restore a prayer alert first.
        let lastShown = LastShownStore(defaults: defaults)
        lastShown.save(.prayerAlert(LastShownPrayerAlertRecord(
            prayerKey: "asr", fireDate: Date(timeIntervalSince1970: 2_000),
            reminderOffsetMinutes: 5, ayahID: nil, shownAt: Date(timeIntervalSince1970: 1_000)
        )))
        let model = NotchViewModel(quranRepository: nil, verseScheduler: nil, prayerAlertScheduler: nil,
                                   settingsStore: SettingsStore(defaults: defaults),
                                   lastShownStore: lastShown, interactionTimer: timer)
        let panel = NotchPanel(contentRect: CGRect(x: 200, y: 400, width: 64, height: 24),
                               viewModel: model, mode: .floatingTab)
        defer { panel.hide() }
        let view = try XCTUnwrap(panel.contentView as? NotchHoverHostingView)
        var pointer = NSPoint(x: 232, y: 424)
        view.pointerLocation = { pointer }
        panel.show()
        view.updateTrackingAreas()
        let area = try XCTUnwrap(view.trackingAreas.first { $0.owner === view })
        let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseExited, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        view.mouseEntered(with: event)
        XCTAssertEqual(timer.actions.count, 1)
        timer.actions[0]()
        XCTAssertTrue(model.isExpanded)
        for height in stride(from: CGFloat(30), through: 220, by: 10) {
            panel.place(at: CGRect(x: 232 - 240, y: 424 - height, width: 480, height: height))
            view.updateTrackingAreas()
            XCTAssertTrue(view.trackingAreas.contains { $0 === area })
            view.mouseExited(with: event)
        }
        XCTAssertEqual(timer.actions.count, 1, "Resize exits under a stationary pointer must not arm dismissal")
        XCTAssertTrue(model.isExpanded)
        pointer = NSPoint(x: 800, y: 100)
        // No second mouseExited is delivered after the resize-generated exit.
        // The movement monitor / animation completion must recover the position.
        view.reconcilePointerPosition()
        XCTAssertEqual(timer.actions.count, 2, "Movement outside must dismiss even without another exit event")
        timer.actions[1]()
        XCTAssertFalse(model.isExpanded)
        // A queued entry from the old geometry must not reopen the card.
        view.mouseEntered(with: event)
        XCTAssertEqual(timer.actions.count, 2)
    }

    private final class HoverTimer: OneShotTimerScheduling {
        private final class Token: OneShotTimerToken { func cancel() {} }
        var actions: [@MainActor () -> Void] = []
        func schedule(after interval: TimeInterval, leeway: TimeInterval,
                      action: @escaping @MainActor () -> Void) -> any OneShotTimerToken {
            actions.append(action)
            return Token()
        }
    }

}
