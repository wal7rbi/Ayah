import Foundation
import XCTest
@testable import AyahKit

final class VerseSchedulerTests: XCTestCase {
    /// See `QuranIntegrityTests.quranResourcesDir` for why this is
    /// resolved via `#filePath` rather than an SPM package resource.
    private static var quranResourcesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Quran")
    }

    private func makeQuranRepository() throws -> QuranRepository {
        let dir = Self.quranResourcesDir
        let dbPath = dir.appendingPathComponent("quran.sqlite").path
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw XCTSkip("quran.sqlite not found at \(dbPath) — run Scripts/import_quran first")
        }
        return try QuranRepository(
            databasePath: dbPath,
            checksumPath: dir.appendingPathComponent("CHECKSUM").path
        )
    }

    private func makeMemorizationRepository() throws -> MemorizationRepository {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("ayah_user.sqlite")
        return try MemorizationRepository(databasePath: dbURL.path)
    }

    private func makeSettingsStore(_ settings: AppSettings) throws -> SettingsStore {
        let suiteName = "com.ayah.tests.\(UUID().uuidString)"
        let store = SettingsStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        store.settings = settings
        return store
    }

    private func makeScheduler(
        settings: AppSettings,
        memorizationRepository: MemorizationRepository? = nil,
        randomDouble: @escaping () -> Double = { 0 },
        randomInt: @escaping (ClosedRange<Int>) -> Int = { $0.lowerBound }
    ) throws -> (VerseScheduler, MemorizationRepository) {
        let quranRepository = try makeQuranRepository()
        let memRepo = try memorizationRepository ?? makeMemorizationRepository()
        let scheduler = VerseScheduler(
            quranRepository: quranRepository,
            memorizationRepository: memRepo,
            settingsStore: try makeSettingsStore(settings),
            randomDouble: randomDouble,
            randomInt: randomInt
        )
        return (scheduler, memRepo)
    }

    func testFallsBackToGeneralPoolWhenNoMemorizationSetsExist() throws {
        let (scheduler, _) = try makeScheduler(
            settings: AppSettings(versesPerDisplay: 2, memorizationWeightPercent: 100),
            randomDouble: { 0 } // would always pick memorization pool if any sets existed
        )

        let ayahs = try XCTUnwrap(scheduler.selectNextVerses().nilIfEmpty)
        XCTAssertEqual(ayahs.count, 2)
        XCTAssertEqual(ayahs[1].ayahNumber, ayahs[0].ayahNumber + 1)
        XCTAssertEqual(ayahs[1].surahNumber, ayahs[0].surahNumber)
    }

    func testWeightZeroAlwaysUsesGeneralPoolEvenWithEnabledSets() throws {
        let memRepo = try makeMemorizationRepository()
        _ = try memRepo.create(surahNumber: 1, startAyah: 1, endAyah: 7)

        let (scheduler, _) = try makeScheduler(
            settings: AppSettings(versesPerDisplay: 1, memorizationWeightPercent: 0),
            memorizationRepository: memRepo,
            randomDouble: { 0 }
        )

        // With weight 0%, `randomDouble() < 0` is always false regardless
        // of what randomDouble returns, so this must never draw from the
        // (otherwise always-eligible) memorization set.
        for _ in 0..<20 {
            let ayahs = scheduler.selectNextVerses()
            XCTAssertEqual(ayahs.count, 1)
        }
    }

    func testSequentialSetStartsAtCursorAndAdvancesIt() throws {
        let memRepo = try makeMemorizationRepository()
        let set = try memRepo.create(surahNumber: 1, startAyah: 1, endAyah: 6, repetitionMode: .sequential)

        let (scheduler, repo) = try makeScheduler(
            settings: AppSettings(versesPerDisplay: 2, memorizationWeightPercent: 100),
            memorizationRepository: memRepo,
            randomDouble: { 0 }
        )

        let first = scheduler.selectNextVerses()
        XCTAssertEqual(first.map(\.ayahNumber), [1, 2])
        XCTAssertEqual(repo.fetchAll().first(where: { $0.id == set.id })?.cursorAyah, 3)

        let second = scheduler.selectNextVerses()
        XCTAssertEqual(second.map(\.ayahNumber), [3, 4])
        XCTAssertEqual(repo.fetchAll().first(where: { $0.id == set.id })?.cursorAyah, 5)
    }

    func testSequentialSetWrapsCursorAfterReachingEnd() throws {
        let memRepo = try makeMemorizationRepository()
        let set = try memRepo.create(surahNumber: 1, startAyah: 5, endAyah: 6, repetitionMode: .sequential)
        try memRepo.updateCursor(id: set.id, cursorAyah: 6)

        let (scheduler, repo) = try makeScheduler(
            settings: AppSettings(versesPerDisplay: 3, memorizationWeightPercent: 100),
            memorizationRepository: memRepo,
            randomDouble: { 0 }
        )

        let ayahs = scheduler.selectNextVerses()
        XCTAssertEqual(ayahs.map(\.ayahNumber), [6], "must not spill past the set's own endAyah")
        XCTAssertEqual(repo.fetchAll().first(where: { $0.id == set.id })?.cursorAyah, 5)
    }

    func testRandomModeSetStaysWithinItsOwnRangeAndDoesNotAdvanceCursor() throws {
        let memRepo = try makeMemorizationRepository()
        let set = try memRepo.create(surahNumber: 1, startAyah: 6, endAyah: 7, repetitionMode: .random)

        let (scheduler, repo) = try makeScheduler(
            settings: AppSettings(versesPerDisplay: 3, memorizationWeightPercent: 100),
            memorizationRepository: memRepo,
            randomDouble: { 0 },
            randomInt: { $0.upperBound } // picks the last ayah in whatever range is asked
        )

        let ayahs = scheduler.selectNextVerses()
        XCTAssertEqual(ayahs.map(\.ayahNumber), [7], "must not spill past the set's own endAyah")
        XCTAssertNil(repo.fetchAll().first(where: { $0.id == set.id })?.cursorAyah, "random mode never writes a cursor")
    }
}

private extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}
