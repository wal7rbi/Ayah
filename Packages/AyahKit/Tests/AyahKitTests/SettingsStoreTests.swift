import Foundation
import XCTest
@testable import AyahKit

final class SettingsStoreTests: XCTestCase {
    // Mirrors `SettingsStore`'s own private `storageKey` — duplicated here
    // rather than exposed, since only this test needs to write raw JSON
    // directly into `UserDefaults` ahead of construction.
    private static let storageKey = "com.ayah.appSettings"

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "com.ayah.tests.\(UUID().uuidString)"
        return try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    func testDefaultsAppliedWhenNothingStored() throws {
        let store = SettingsStore(defaults: try makeIsolatedDefaults())
        XCTAssertEqual(store.settings, AppSettings())
    }

    func testChangesArePersistedAcrossStoreInstances() throws {
        let defaults = try makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        store.settings.versesPerDisplay = 4
        store.settings.memorizationWeightPercent = 30

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings.versesPerDisplay, 4)
        XCTAssertEqual(reloaded.settings.memorizationWeightPercent, 30)
    }

    /// Regression test for a real bug hit mid-development: changing
    /// the prayer-notification lead-time field's type (`Int` →
    /// `Set<Int>`) made the synthesized `Decodable` conformance throw on
    /// any previously-stored settings blob, and `SettingsStore.init`'s
    /// `try?` swallowed that failure by falling back to *entirely*
    /// default `AppSettings()` — silently discarding unrelated fields
    /// (city selection, calculation method, an already-fetched
    /// current-location fix) that had nothing to do with the field that
    /// actually changed. `AppSettings.init(from:)` now decodes each field
    /// independently with its own default fallback, so a blob shaped like
    /// an old schema version — including this field's old *name*,
    /// `prayerNotificationLeadMinutes`, since it was later renamed to
    /// `prayerNotificationReminderMinutes` too — should still restore
    /// whatever it can.
    func testOldSchemaBlobPreservesUnaffectedFieldsAndDefaultsOnlyTheChangedOne() throws {
        let defaults = try makeIsolatedDefaults()
        // Shaped like an old schema version: the now-renamed/retyped key
        // `prayerNotificationLeadMinutes` (a bare `Int`) rather than
        // today's `prayerNotificationReminderMinutes`.
        let oldSchemaJSON = """
        {"versesPerDisplay": 4, "selectedCityID": 12345, "prayerNotificationLeadMinutes": 5}
        """
        defaults.set(Data(oldSchemaJSON.utf8), forKey: Self.storageKey)

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.versesPerDisplay, 4)
        XCTAssertEqual(store.settings.selectedCityID, 12345)
        XCTAssertEqual(store.settings.prayerNotificationReminderMinutes, AppSettings().prayerNotificationReminderMinutes)
        XCTAssertEqual(store.settings.isVerseDisplayEnabled, AppSettings().isVerseDisplayEnabled)
    }

    func testMalformedTopLevelBlobIsObservable() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set(Data("not-json".utf8), forKey: Self.storageKey)
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings, AppSettings())
        XCTAssertNotNil(store.lastLoadError)
    }

    func testOutOfRangeFieldsAreIndependentlyDefaulted() throws {
        let defaults = try makeIsolatedDefaults()
        let json = """
        {
          "displayInterval": -1,
          "versesPerDisplay": 999,
          "memorizationWeightPercent": 101,
          "prayerCalculationMethod": "other",
          "selectedCityID": -5,
          "currentLocationCoordinates": {"latitude": 91, "longitude": 46},
          "currentLocationTimeZoneIdentifier": "Not/A_Time_Zone",
          "prayerNotificationReminderMinutes": 999
        }
        """
        defaults.set(Data(json.utf8), forKey: Self.storageKey)
        let settings = SettingsStore(defaults: defaults).settings
        let defaultsSettings = AppSettings()
        XCTAssertEqual(settings.displayInterval, defaultsSettings.displayInterval)
        XCTAssertEqual(settings.versesPerDisplay, defaultsSettings.versesPerDisplay)
        XCTAssertEqual(settings.memorizationWeightPercent, defaultsSettings.memorizationWeightPercent)
        XCTAssertEqual(settings.prayerCalculationMethod, .ummAlQura)
        XCTAssertNil(settings.selectedCityID)
        XCTAssertNil(settings.currentLocationCoordinates)
        XCTAssertNil(settings.currentLocationTimeZoneIdentifier)
        XCTAssertEqual(settings.prayerNotificationReminderMinutes, defaultsSettings.prayerNotificationReminderMinutes)
    }
}
