import Foundation
import XCTest
@testable import AyahKit

final class LastShownStoreTests: XCTestCase {
    private static let storageKey = "com.ayah.lastShown"
    private let shownAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let fireDate = Date(timeIntervalSince1970: 1_800_000_300)

    private func makeIsolatedDefaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "com.ayah.last-shown-tests.\(UUID().uuidString)"))
    }

    func testFirstLaunchHasNoRecord() throws {
        let store = LastShownStore(defaults: try makeIsolatedDefaults())

        XCTAssertNil(store.record)
        XCTAssertNil(store.lastLoadError)
    }

    func testSavesAndRestoresOrderedVerseBatch() throws {
        let defaults = try makeIsolatedDefaults()
        let expected = LastShownRecord.verses(
            LastShownVerseRecord(ayahIDs: [103, 101, 102], shownAt: shownAt)
        )

        LastShownStore(defaults: defaults).save(expected)

        XCTAssertEqual(LastShownStore(defaults: defaults).record, expected)
    }

    func testSavesAndRestoresPrayerAlertWithAyah() throws {
        let defaults = try makeIsolatedDefaults()
        let expected = LastShownRecord.prayerAlert(LastShownPrayerAlertRecord(
            prayerKey: "asr",
            fireDate: fireDate,
            reminderOffsetMinutes: 10,
            ayahID: 622,
            shownAt: shownAt
        ))

        LastShownStore(defaults: defaults).save(expected)

        XCTAssertEqual(LastShownStore(defaults: defaults).record, expected)
    }

    func testSavesAndRestoresPrayerAlertWithoutAyah() throws {
        let defaults = try makeIsolatedDefaults()
        let expected = LastShownRecord.prayerAlert(LastShownPrayerAlertRecord(
            prayerKey: "maghrib",
            fireDate: fireDate,
            reminderOffsetMinutes: 0,
            ayahID: nil,
            shownAt: shownAt
        ))

        LastShownStore(defaults: defaults).save(expected)

        XCTAssertEqual(LastShownStore(defaults: defaults).record, expected)
    }

    func testNewRecordReplacesPreviousRecord() throws {
        let defaults = try makeIsolatedDefaults()
        let store = LastShownStore(defaults: defaults)
        store.save(.verses(LastShownVerseRecord(ayahIDs: [1, 2], shownAt: shownAt)))
        let replacement = LastShownRecord.prayerAlert(LastShownPrayerAlertRecord(
            prayerKey: "isha",
            fireDate: fireDate,
            reminderOffsetMinutes: 5,
            ayahID: nil,
            shownAt: shownAt.addingTimeInterval(60)
        ))

        store.save(replacement)

        XCTAssertEqual(store.record, replacement)
        XCTAssertEqual(LastShownStore(defaults: defaults).record, replacement)
    }

    func testMalformedJSONIsIgnoredAndObservable() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set(Data("not-json".utf8), forKey: Self.storageKey)

        let store = LastShownStore(defaults: defaults)

        XCTAssertNil(store.record)
        XCTAssertNotNil(store.lastLoadError)
    }

    func testUnsupportedSchemaIsIgnoredAndObservable() throws {
        let defaults = try makeIsolatedDefaults()
        let store = LastShownStore(defaults: defaults)
        store.save(.verses(LastShownVerseRecord(ayahIDs: [1], shownAt: shownAt)))
        let data = try XCTUnwrap(defaults.data(forKey: Self.storageKey))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = 999
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: Self.storageKey)

        let reloaded = LastShownStore(defaults: defaults)

        XCTAssertNil(reloaded.record)
        XCTAssertEqual(reloaded.lastLoadError as? LastShownStoreError, .unsupportedSchemaVersion(999))
    }

    func testPersistedVerseRecordContainsIDsButNoQuranText() throws {
        let defaults = try makeIsolatedDefaults()
        LastShownStore(defaults: defaults).save(
            .verses(LastShownVerseRecord(ayahIDs: [1, 2], shownAt: shownAt))
        )
        let data = try XCTUnwrap(defaults.data(forKey: Self.storageKey))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("ayahIDs"))
        XCTAssertTrue(json.contains("[1,2]"))
        XCTAssertFalse(json.contains("uthmanicText"))
        XCTAssertFalse(json.contains("searchableText"))
        XCTAssertFalse(json.contains("بسم الله"))
    }

    func testInvalidRecordsAreNotPersisted() throws {
        let defaults = try makeIsolatedDefaults()
        let store = LastShownStore(defaults: defaults)

        store.save(.verses(LastShownVerseRecord(ayahIDs: [], shownAt: shownAt)))

        XCTAssertNil(store.record)
        XCTAssertEqual(store.lastSaveError as? LastShownStoreError, .invalidRecord)
        XCTAssertNil(defaults.data(forKey: Self.storageKey))
    }
}
