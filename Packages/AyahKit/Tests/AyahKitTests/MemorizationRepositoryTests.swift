import Foundation
import XCTest
@testable import AyahKit

final class MemorizationRepositoryTests: XCTestCase {
    private func makeRepository() throws -> (MemorizationRepository, URL) {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("ayah_user.sqlite")
        let repository = try MemorizationRepository(databasePath: dbURL.path)
        return (repository, dbURL)
    }

    func testCreateRejectsInvalidRange() throws {
        let (repository, _) = try makeRepository()
        XCTAssertThrowsError(try repository.create(surahNumber: 1, startAyah: 5, endAyah: 2)) { error in
            XCTAssertEqual(error as? MemorizationRepositoryError, .invalidRange)
        }
    }

    func testCreateAndFetchAll() throws {
        let (repository, _) = try makeRepository()
        let set = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)

        let all = repository.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, set.id)
        XCTAssertEqual(all.first?.surahNumber, set.surahNumber)
        XCTAssertEqual(all.first?.startAyah, set.startAyah)
        XCTAssertEqual(all.first?.endAyah, set.endAyah)
        XCTAssertEqual(all.first?.isEnabled, set.isEnabled)
        XCTAssertEqual(all.first?.repetitionMode, set.repetitionMode)
    }

    func testFetchEnabledExcludesDisabledSets() throws {
        let (repository, _) = try makeRepository()
        let enabled = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)
        _ = try repository.create(surahNumber: 2, startAyah: 1, endAyah: 5, isEnabled: false)

        let fetched = repository.fetchEnabled()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, enabled.id)
    }

    func testUpdatePersistsChanges() throws {
        let (repository, _) = try makeRepository()
        var set = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)
        set.isEnabled = false
        set.cursorAyah = 3

        try repository.update(set)

        let refetched = try XCTUnwrap(repository.fetchAll().first)
        XCTAssertFalse(refetched.isEnabled)
        XCTAssertEqual(refetched.cursorAyah, 3)
    }

    func testDeleteRemovesSet() throws {
        let (repository, _) = try makeRepository()
        let set = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)

        try repository.delete(id: set.id)

        XCTAssertTrue(repository.fetchAll().isEmpty)
    }

    func testUpdateCursorAdvancesWalkPosition() throws {
        let (repository, _) = try makeRepository()
        let set = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)

        try repository.updateCursor(id: set.id, cursorAyah: 4)

        XCTAssertEqual(repository.fetchAll().first?.cursorAyah, 4)
    }

    func testCreateRejectsSurahNumberOutsideOneToOneFourteen() throws {
        let (repository, _) = try makeRepository()
        XCTAssertThrowsError(try repository.create(surahNumber: 0, startAyah: 1, endAyah: 1)) { error in
            XCTAssertEqual(error as? MemorizationRepositoryError, .invalidSurahNumber)
        }
        XCTAssertThrowsError(try repository.create(surahNumber: 115, startAyah: 1, endAyah: 1)) { error in
            XCTAssertEqual(error as? MemorizationRepositoryError, .invalidSurahNumber)
        }
    }

    func testCreateRejectsAyahBeyondTheSelectedSurah() throws {
        let (repository, _) = try makeRepository()
        XCTAssertThrowsError(try repository.create(surahNumber: 1, startAyah: 1, endAyah: 8)) { error in
            XCTAssertEqual(error as? MemorizationRepositoryError, .ayahOutsideSurah)
        }
        XCTAssertNoThrow(try repository.create(surahNumber: 2, startAyah: 286, endAyah: 286))
    }

    func testUpdateRejectsAyahBeyondTheSelectedSurahAndPreservesStoredRow() throws {
        let (repository, _) = try makeRepository()
        var set = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)
        set.endAyah = 8

        XCTAssertThrowsError(try repository.update(set)) { error in
            XCTAssertEqual(error as? MemorizationRepositoryError, .ayahOutsideSurah)
        }
        XCTAssertEqual(repository.fetchAll().first?.endAyah, 7)
    }

    /// Regression test: `create`/`update`/`updateCursor` used to
    /// force-convert `surahNumber`/`startAyah`/`endAyah`/`cursorAyah`
    /// straight into `Int32` for `sqlite3_bind_int`, which traps (crashes
    /// the process) on a value outside `Int32`'s range. A caller passing
    /// a malformed value (numeric-entry bug, imported/restored backup)
    /// must get a catchable error instead of crashing the app.
    func testCreateRejectsAyahValuesOutOfInt32Range() throws {
        let (repository, _) = try makeRepository()
        let tooLarge = Int(Int32.max) + 1
        XCTAssertThrowsError(try repository.create(surahNumber: 1, startAyah: 1, endAyah: tooLarge)) { error in
            XCTAssertEqual(error as? MemorizationRepositoryError, .valueOutOfRange)
        }
        XCTAssertThrowsError(try repository.create(surahNumber: 1, startAyah: tooLarge, endAyah: tooLarge)) { error in
            XCTAssertEqual(error as? MemorizationRepositoryError, .valueOutOfRange)
        }
    }

    func testUpdateCursorRejectsValuesOutOfRange() throws {
        let (repository, _) = try makeRepository()
        let set = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)

        XCTAssertThrowsError(try repository.updateCursor(id: set.id, cursorAyah: 0)) { error in
            XCTAssertEqual(error as? MemorizationRepositoryError, .valueOutOfRange)
        }
        XCTAssertThrowsError(
            try repository.updateCursor(id: set.id, cursorAyah: Int(Int32.max) + 1)
        ) { error in
            XCTAssertEqual(error as? MemorizationRepositoryError, .valueOutOfRange)
        }
        XCTAssertThrowsError(try repository.updateCursor(id: set.id, cursorAyah: 8)) { error in
            XCTAssertEqual(error as? MemorizationRepositoryError, .valueOutOfRange)
        }
        XCTAssertThrowsError(try repository.updateCursor(id: "missing", cursorAyah: 1)) { error in
            XCTAssertEqual(error as? MemorizationRepositoryError, .notFound)
        }

        // Confirm nothing was written by the rejected calls above.
        XCTAssertNil(repository.fetchAll().first?.cursorAyah)
    }

    /// Regression test: `fetchAll()`/`fetchEnabled()` used to swallow any
    /// query failure via `try?` and return `[]`, which is indistinguishable
    /// from "the user genuinely has no memorization sets." A real failure
    /// must now be observable via `lastFetchError`.
    func testFetchFailureIsObservableInsteadOfLookingLikeAnEmptyTable() throws {
        let (repository, dbURL) = try makeRepository()
        _ = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)
        XCTAssertNil(repository.lastFetchError)

        // Corrupt the schema out from under the repository, via a second
        // connection to the same file, to force a real query failure.
        let corruptor = try SQLiteConnection(path: dbURL.path)
        try corruptor.execute("DROP TABLE memorization_sets;")

        XCTAssertTrue(repository.fetchAll().isEmpty)
        XCTAssertNotNil(repository.lastFetchError)

        XCTAssertTrue(repository.fetchEnabled().isEmpty)
        XCTAssertNotNil(repository.lastFetchError)
    }

    /// Regression test: `rowToSet` used to force-convert `id`/
    /// `repetition_mode`/`created_at` straight into `String(cString:)`,
    /// which traps on a NULL column. `ayah_user.sqlite` has no checksum
    /// guard the way `quran.sqlite` does, so a hand-edited/corrupted file
    /// violating its own `NOT NULL` schema must surface as a catchable
    /// error via `lastFetchError`, not a crash.
    func testFetchAllRejectsACorruptedRowInsteadOfCrashing() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("ayah_user.sqlite")
        let seedConnection = try SQLiteConnection(path: dbURL.path)
        // Same shape as the real schema but without the NOT NULL
        // constraints, so a NULL can actually be inserted (a real
        // NOT NULL column would reject this insert outright).
        try seedConnection.execute("""
            CREATE TABLE memorization_sets (
              id                   TEXT,
              surah_number         INTEGER,
              start_ayah           INTEGER,
              end_ayah             INTEGER,
              is_enabled           INTEGER,
              repetition_mode      TEXT,
              cursor_ayah          INTEGER,
              created_at           TEXT,
              last_shown_at        TEXT,
              ease_factor          REAL,
              review_interval_days INTEGER
            );
            """)
        try seedConnection.execute("""
            INSERT INTO memorization_sets
              (id, surah_number, start_ayah, end_ayah, is_enabled, repetition_mode, created_at)
            VALUES (NULL, 1, 1, 7, 1, 'sequential', '2026-01-01T00:00:00Z');
            """)

        // `MemorizationRepository.init`'s `CREATE TABLE IF NOT EXISTS` is a
        // no-op against the already-existing (looser) table above, so the
        // corrupted row survives into the repository under test.
        let repository = try MemorizationRepository(databasePath: dbURL.path)

        XCTAssertTrue(repository.fetchAll().isEmpty)
        XCTAssertEqual(repository.lastFetchError as? MemorizationRepositoryError, .corruptedRow)
    }

    func testFetchAllRejectsSemanticallyImpossiblePersistedRange() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("ayah_user.sqlite")
        let seedConnection = try SQLiteConnection(path: dbURL.path)
        try seedConnection.execute("""
            CREATE TABLE memorization_sets (
              id TEXT, surah_number INTEGER, start_ayah INTEGER, end_ayah INTEGER,
              is_enabled INTEGER, repetition_mode TEXT, cursor_ayah INTEGER,
              created_at TEXT, last_shown_at TEXT, ease_factor REAL,
              review_interval_days INTEGER
            );
            INSERT INTO memorization_sets
              (id, surah_number, start_ayah, end_ayah, is_enabled, repetition_mode, created_at)
            VALUES ('corrupt', 1, 1, 8, 1, 'sequential', '2026-01-01T00:00:00.000Z');
            """)

        let repository = try MemorizationRepository(databasePath: dbURL.path)
        XCTAssertTrue(repository.fetchAll().isEmpty)
        XCTAssertEqual(repository.lastFetchError as? MemorizationRepositoryError, .corruptedRow)
    }

    func testFetchAllRejectsWrongSQLiteTypesInsteadOfCoercingThem() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("ayah_user.sqlite")
        let seedConnection = try SQLiteConnection(path: dbURL.path)
        try seedConnection.execute("""
            CREATE TABLE memorization_sets (
              id TEXT, surah_number INTEGER, start_ayah INTEGER, end_ayah INTEGER,
              is_enabled INTEGER, repetition_mode TEXT, cursor_ayah INTEGER,
              created_at TEXT, last_shown_at TEXT, ease_factor REAL,
              review_interval_days INTEGER
            );
            INSERT INTO memorization_sets
              (id, surah_number, start_ayah, end_ayah, is_enabled, repetition_mode, created_at)
            VALUES ('wrong-type', 'not-a-number', 1, 7, 1, 'sequential', '2026-01-01T00:00:00.000Z');
            """)
        let repository = try MemorizationRepository(databasePath: dbURL.path)
        XCTAssertTrue(repository.fetchAll().isEmpty)
        XCTAssertEqual(repository.lastFetchError as? MemorizationRepositoryError, .corruptedRow)
    }

    func testDataSurvivesReopeningTheSameDatabaseFile() throws {
        let (repository, dbURL) = try makeRepository()
        _ = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)

        let reopened = try MemorizationRepository(databasePath: dbURL.path)
        XCTAssertEqual(reopened.fetchAll().count, 1)
    }
}
