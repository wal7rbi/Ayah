import Foundation
import XCTest
@testable import AyahKit

final class RecoveryTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let name = "com.ayah.recovery-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return defaults
    }

    private func repository() throws -> MemorizationRepository {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try MemorizationRepository(databasePath: directory.appendingPathComponent("user.sqlite").path)
    }

    private func quran() throws -> QuranRepository {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let resources = root.appendingPathComponent("Resources/Quran")
        return try QuranRepository(databasePath: resources.appendingPathComponent("quran.sqlite").path,
                                   checksumPath: resources.appendingPathComponent("CHECKSUM").path)
    }

    func testUnavailableMemorizationStillSelectsVerifiedQuran() throws {
        let quran = try quran()
        let store = SettingsStore(defaults: try defaults())
        store.settings.memorizationWeightPercent = 100
        let scheduler = VerseScheduler(quranRepository: quran, memorizationRepository: nil,
                                       settingsStore: store)
        let verses = scheduler.selectNextVerses()
        XCTAssertFalse(verses.isEmpty)
        for verse in verses {
            XCTAssertEqual(quran.ayah(surah: verse.surahNumber, ayah: verse.ayahNumber), verse)
        }
    }

    func testSuccessfulCursorSaveDoesNotHideAnUnrelatedReadFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("user.sqlite").path
        let repository = try MemorizationRepository(databasePath: path)
        let set = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)
        // Al-Fatiha has 7 ayahs, so this row fails decoding and the whole read reports an error.
        try SQLiteConnection(path: path).execute("""
            INSERT INTO memorization_sets
              (id, surah_number, start_ayah, end_ayah, is_enabled, repetition_mode, created_at)
            VALUES ('corrupt', 1, 1, 8, 1, 'sequential', '2026-01-01T00:00:00.000Z');
            """)
        let access = MemorizationAccess(repository: repository)
        _ = access.fetchEnabled()
        let readFailure = try XCTUnwrap(access.errorMessage)
        try access.updateCursor(id: set.id, cursorAyah: 2)
        XCTAssertEqual(access.errorMessage, readFailure)
    }

    func testRetryTransitionsFromFailureToSharedRepositoryWithoutLosingProgress() throws {
        enum Failure: Error { case unavailable }
        let repository = try repository()
        let set = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)
        try repository.updateCursor(id: set.id, cursorAyah: 4)
        var attempts = 0
        let access = MemorizationAccess(repository: nil) {
            attempts += 1
            if attempts == 1 { throw Failure.unavailable }
            return repository
        }
        XCTAssertNotNil(access.errorMessage)
        access.retry()
        XCTAssertNil(access.repository)
        XCTAssertNotNil(access.errorMessage)
        access.retry()
        XCTAssertTrue(access.repository === repository)
        XCTAssertNil(access.errorMessage)
        XCTAssertEqual(access.fetchEnabled().first?.cursorAyah, 4)
        try access.updateCursor(id: set.id, cursorAyah: 5)
        XCTAssertEqual(repository.fetchAll().first?.cursorAyah, 5)
        access.retry()
        XCTAssertEqual(attempts, 2, "An already open repository should not be reopened")
    }

    func testMalformedSettingsRecoverySurvivesEditsAndAnotherMalformedBlob() throws {
        let defaults = try defaults()
        let key = "com.ayah.appSettings"
        let original = Data("original malformed settings".utf8)
        defaults.set(original, forKey: key)
        let store = SettingsStore(defaults: defaults)
        XCTAssertNotNil(store.lastLoadError)
        XCTAssertEqual(defaults.data(forKey: key + ".recovery"), original)
        store.settings.versesPerDisplay = 4
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.versesPerDisplay, 4)
        XCTAssertEqual(defaults.data(forKey: key + ".recovery"), original)
        defaults.set(Data("another malformed value".utf8), forKey: key)
        XCTAssertNotNil(SettingsStore(defaults: defaults).lastLoadError)
        XCTAssertEqual(defaults.data(forKey: key + ".recovery"), original)
    }

    func testLegacySettingsDefaultNewFieldsWithoutInventingLocationQuality() throws {
        let defaults = try defaults()
        defaults.set(Data("""
        {"versesPerDisplay":4,"selectedCityID":12345,
         "currentLocationCoordinates":{"latitude":24.7,"longitude":46.7},
         "currentLocationTimeZoneIdentifier":"Asia/Riyadh"}
        """.utf8), forKey: "com.ayah.appSettings")
        let store = SettingsStore(defaults: defaults)
        XCTAssertNil(store.lastLoadError)
        XCTAssertEqual(store.settings.versesPerDisplay, 4)
        XCTAssertEqual(store.settings.selectedCityID, 12345)
        XCTAssertNotNil(store.settings.currentLocationCoordinates)
        XCTAssertNil(store.settings.currentLocationMeasuredAt)
        XCTAssertNil(store.settings.currentLocationHorizontalAccuracy)
    }
}
