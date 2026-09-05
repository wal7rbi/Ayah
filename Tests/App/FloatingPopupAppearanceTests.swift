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
        let view = NSHostingView(rootView: NotchContentView(viewModel: model, isPhysicalNotch: false))
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
}
