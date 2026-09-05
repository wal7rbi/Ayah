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
        quranRepository: QuranRepository? = nil,
        randomDouble: @escaping () -> Double = { 0 },
        randomInt: @escaping (ClosedRange<Int>) -> Int = { $0.lowerBound }
    ) throws -> (VerseScheduler, MemorizationRepository) {
        let quranRepository = try quranRepository ?? makeQuranRepository()
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
        let quranRepository = try makeQuranRepository()
        let (scheduler, _) = try makeScheduler(
            settings: AppSettings(versesPerDisplay: 2, memorizationWeightPercent: 100),
            quranRepository: quranRepository,
            randomDouble: { 0 } // would always pick memorization pool if any sets existed
        )

        let ayahs = try XCTUnwrap(scheduler.selectNextVerses().nilIfEmpty)

        // The general pool's starting ayah comes from
        // `QuranRepository.randomAyah()`, which does not route through the
        // injected `randomInt` — so unlike the memorization path this one is
        // genuinely random, and the start can be the last ayah of its surah.
        // A batch is clamped so it never spills past that surah, which
        // legitimately yields a single ayah for 114 of the 6,236 possible
        // starts. Assert the clamp rather than a fixed count: the old
        // unconditional `count == 2` failed on roughly 2% of runs, which
        // reddened CI at random and said nothing about the code.
        let surah = try XCTUnwrap(quranRepository.surahs().first { $0.number == ayahs[0].surahNumber })
        let remainingInSurah = surah.ayahCount - ayahs[0].ayahNumber + 1
        XCTAssertEqual(ayahs.count, min(2, remainingInSurah))

        for (earlier, later) in zip(ayahs, ayahs.dropFirst()) {
            XCTAssertEqual(later.ayahNumber, earlier.ayahNumber + 1)
            XCTAssertEqual(later.surahNumber, earlier.surahNumber)
        }
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
