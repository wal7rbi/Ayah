import Combine
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

    @MainActor
    func testDeferredStartAndIntervalChangesDoNotAdvanceUnseenVerses() throws {
        let repo = try makeMemorizationRepository()
        let set = try repo.create(surahNumber: 1, startAyah: 1, endAyah: 7, repetitionMode: .sequential)
        let settings = try makeSettingsStore(AppSettings(
            displayInterval: 900, versesPerDisplay: 1, memorizationWeightPercent: 100
        ))
        let timer = ManualOneShotTimer()
        let scheduler = VerseScheduler(
            quranRepository: try makeQuranRepository(), memorizationRepository: repo,
            settingsStore: settings, randomDouble: { 0 }, randomInt: { $0.lowerBound },
            timerScheduling: timer
        )
        var displayed: [[Int]] = []
        scheduler.start(selectImmediately: false) { displayed.append($0.map(\.ayahNumber)) }
        XCTAssertNil(repo.fetchAll().first { $0.id == set.id }?.cursorAyah)
        XCTAssertTrue(displayed.isEmpty)
        let initial = try XCTUnwrap(timer.entries.last)
        XCTAssertEqual(initial.interval, 900)
        settings.settings.displayInterval = 1800
        let longer = try XCTUnwrap(timer.entries.last)
        XCTAssertEqual(longer.interval, 1800)
        settings.settings.displayInterval = 300
        let shorter = try XCTUnwrap(timer.entries.last)
        XCTAssertEqual(shorter.interval, 300)
        XCTAssertTrue(initial.isCancelled)
        XCTAssertTrue(longer.isCancelled)
        initial.fire()
        longer.fire()
        XCTAssertTrue(displayed.isEmpty)
        XCTAssertNil(repo.fetchAll().first { $0.id == set.id }?.cursorAyah)
        shorter.fire()
        XCTAssertEqual(displayed, [[1]])
        XCTAssertEqual(repo.fetchAll().first { $0.id == set.id }?.cursorAyah, 2)
        let next = try XCTUnwrap(timer.entries.last)
        XCTAssertEqual(next.interval, 300)
        let count = timer.entries.count
        settings.settings.versesPerDisplay = 2
        XCTAssertEqual(timer.entries.count, count, "Unrelated settings must not reset the deadline.")
        scheduler.stop()
        next.fire()
        XCTAssertEqual(displayed, [[1]])
        XCTAssertEqual(timer.entries.count, count)
        scheduler.start { displayed.append($0.map(\.ayahNumber)) }
        XCTAssertEqual(displayed, [[1], [2, 3]])
        scheduler.stop()
    }

    @MainActor
    func testStartingFromPublishedSnapshotUsesNewSelectionAndInterval() throws {
        let timer = ManualOneShotTimer()
        let settings = try makeSettingsStore(AppSettings(isVerseDisplayEnabled: false, displayInterval: 900))
        let repository = try makeMemorizationRepository()
        _ = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)
        let scheduler = VerseScheduler(quranRepository: try makeQuranRepository(),
                                      memorizationRepository: repository, settingsStore: settings,
                                      randomDouble: { 0 }, timerScheduling: timer)
        var shown: [[Int]] = []
        let subscription = settings.$settings
            .removeDuplicates { $0.isVerseDisplayEnabled == $1.isVerseDisplayEnabled }
            .sink { snapshot in
                guard snapshot.isVerseDisplayEnabled else { return }
                scheduler.start(initialSettings: snapshot) { shown.append($0.map(\.ayahNumber)) }
            }
        var next = settings.settings
        next.isVerseDisplayEnabled = true
        next.displayInterval = 300
        next.versesPerDisplay = 1
        next.memorizationWeightPercent = 100
        settings.settings = next
        XCTAssertEqual(shown, [[1]])
        XCTAssertEqual(timer.entries.last?.interval, 300)
        settings.settings.displayInterval = 900
        XCTAssertEqual(timer.entries.last?.interval, 900)
        XCTAssertEqual(shown, [[1]], "Changing intervals does not advance the cursor")
        scheduler.stop()
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testStoppingInsideDeliveryDoesNotRearm() throws {
        let timer = ManualOneShotTimer()
        let scheduler = VerseScheduler(
            quranRepository: try makeQuranRepository(),
            memorizationRepository: try makeMemorizationRepository(),
            settingsStore: try makeSettingsStore(AppSettings()), timerScheduling: timer
        )
        scheduler.start(selectImmediately: false) { _ in scheduler.stop() }
        try XCTUnwrap(timer.entries.last).fire()
        XCTAssertEqual(timer.entries.count, 1)
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
