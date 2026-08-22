import Foundation
import SQLite3
import XCTest
@testable import AyahKit

/// Proves the integrity mechanism `QuranIntegrityTests.swift` only ever
/// exercises on the happy path actually *rejects* corrupted/tampered data,
/// through the real production entry points (`QuranRepository.init` and
/// `QuranIntegrityChecker.verify`) rather than a reimplemented check.
/// Every case that touches a database file first copies the bundled
/// `quran.sqlite` to a throwaway temp path — the real bundled file is
/// never opened read-write or mutated.
final class QuranTamperingTests: XCTestCase {
    private enum TestSetupError: Error {
        case sqliteOpenFailed
        case sqliteExecFailed(String)
    }

    /// Same resolution as `QuranIntegrityTests.quranResourcesDir` —
    /// duplicated rather than shared, matching this codebase's existing
    /// belt-and-suspenders convention for Quran-integrity-critical code
    /// (see `QuranChecksum.swift`'s doc comment).
    private static var quranResourcesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // QuranTamperingTests.swift -> AyahKitTests/
            .deletingLastPathComponent() // -> Tests/
            .deletingLastPathComponent() // -> AyahKit/
            .deletingLastPathComponent() // -> Packages/
            .deletingLastPathComponent() // -> repo root
            .appendingPathComponent("Resources/Quran")
    }

    private static var realChecksumPath: String {
        quranResourcesDir.appendingPathComponent("CHECKSUM").path
    }

    private static func copyBundledDatabaseToTemp() throws -> URL {
        let source = quranResourcesDir.appendingPathComponent("quran.sqlite")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("quran.sqlite not found at \(source.path) — run Scripts/import_quran first")
        }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }

    private static func exec(_ sql: String, on db: OpaquePointer?) throws {
        var errMsg: UnsafeMutablePointer<Int8>?
        guard sqlite3_exec(db, sql, nil, nil, &errMsg) == SQLITE_OK else {
            let message = errMsg.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errMsg)
            throw TestSetupError.sqliteExecFailed(message)
        }
    }

    /// Opens `url` read-write (unlike production, which only ever opens
    /// `SQLITE_OPEN_READONLY`) purely to construct a tampered fixture.
    private static func tamperFirstAyahText(at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw TestSetupError.sqliteOpenFailed }
        defer { sqlite3_close(db) }
        try exec("UPDATE ayahs SET uthmanic_text = uthmanic_text || 'TAMPERED' WHERE id = 1;", on: db)
    }

    /// A structurally-valid database (same schema `SQLiteWriter.swift`
    /// writes) but with far fewer rows than the real Quran — used to
    /// exercise the count-guard path distinct from the checksum path.
    private static func buildUndersizedFixtureDatabase(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw TestSetupError.sqliteOpenFailed }
        defer { sqlite3_close(db) }
        try exec(
            """
            CREATE TABLE surahs (
              number              INTEGER PRIMARY KEY,
              name_arabic         TEXT NOT NULL,
              name_transliterated TEXT NOT NULL,
              ayah_count          INTEGER NOT NULL
            );
            CREATE TABLE ayahs (
              id               INTEGER PRIMARY KEY,
              surah_number     INTEGER NOT NULL REFERENCES surahs(number),
              ayah_number      INTEGER NOT NULL,
              juz_number       INTEGER NOT NULL,
              page_number      INTEGER NOT NULL,
              uthmanic_text    TEXT NOT NULL,
              searchable_text  TEXT NOT NULL,
              UNIQUE (surah_number, ayah_number)
            );
            INSERT INTO surahs VALUES (1, 'الفاتحة', 'Al-Fatihah', 1);
            INSERT INTO ayahs VALUES (1, 1, 1, 1, 1, 'placeholder', 'placeholder');
            """,
            on: db
        )
    }

    /// Exactly 114 dummy surahs / 6236 dummy ayahs — big enough to pass
    /// `QuranIntegrityChecker.verify`'s hardcoded count guards without
    /// needing the real bundled database, so the checksum-comparison
    /// logic itself can be unit-tested in isolation, fast and offline.
    private static func makeSyntheticFullSizeFixture() -> (surahs: [Surah], ayahs: [QuranAyah]) {
        let surahs = (1...114).map {
            Surah(number: $0, nameArabic: "سورة \($0)", nameTransliterated: "Surah \($0)", ayahCount: 1)
        }
        let ayahs = (1...6236).map {
            QuranAyah(
                id: $0,
                surahNumber: 1,
                ayahNumber: $0,
                juzNumber: 1,
                pageNumber: 1,
                uthmanicText: "نص تجريبي \($0)",
                searchableText: "نص تجريبي \($0)"
            )
        }
        return (surahs, ayahs)
    }

    // MARK: - Real production path: QuranRepository.init against copied/tampered files

    func testApprovedCopyPassesIntegrityCheck() throws {
        let tempDB = try Self.copyBundledDatabaseToTemp()
        defer { try? FileManager.default.removeItem(at: tempDB) }

        let repo = try QuranRepository(databasePath: tempDB.path, checksumPath: Self.realChecksumPath)
        XCTAssertEqual(repo.surahs().count, 114)
    }

    func testTamperedByteFailsChecksumVerification() throws {
        let tempDB = try Self.copyBundledDatabaseToTemp()
        defer { try? FileManager.default.removeItem(at: tempDB) }
        try Self.tamperFirstAyahText(at: tempDB)

        XCTAssertThrowsError(
            try QuranRepository(databasePath: tempDB.path, checksumPath: Self.realChecksumPath)
        ) { error in
            XCTAssertEqual(error as? QuranIntegrityError, .checksumMismatch)
        }
    }

    func testTruncatedFileFailsToLoad() throws {
        let tempDB = try Self.copyBundledDatabaseToTemp()
        defer { try? FileManager.default.removeItem(at: tempDB) }

        let handle = try FileHandle(forWritingTo: tempDB)
        try handle.truncate(atOffset: 100) // SQLite's header is exactly 100 bytes — no schema page survives
        try handle.close()

        XCTAssertThrowsError(
            try QuranRepository(databasePath: tempDB.path, checksumPath: Self.realChecksumPath)
        )
    }

    func testReplacementWithUndersizedDatabaseFailsSurahCountCheck() throws {
        let tempDB = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: tempDB) }
        try Self.buildUndersizedFixtureDatabase(at: tempDB)

        XCTAssertThrowsError(
            try QuranRepository(databasePath: tempDB.path, checksumPath: Self.realChecksumPath)
        ) { error in
            XCTAssertEqual(error as? QuranIntegrityError, .surahCountMismatch(expected: 114, actual: 1))
        }
    }

    /// Defense-in-depth check, independent of app logic: the exact
    /// `SQLITE_OPEN_READONLY` mode `QuranRepository` uses truly refuses
    /// writes at the SQLite/OS level, not merely by convention.
    func testBundledDatabaseCannotBeWrittenThroughReadOnlyHandle() throws {
        let tempDB = try Self.copyBundledDatabaseToTemp()
        defer { try? FileManager.default.removeItem(at: tempDB) }

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(tempDB.path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }

        var errMsg: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, "UPDATE ayahs SET uthmanic_text = 'x' WHERE id = 1;", nil, nil, &errMsg)
        sqlite3_free(errMsg)

        XCTAssertEqual(
            result, SQLITE_READONLY,
            "quran.sqlite must remain unwritable through the same read-only open mode QuranRepository uses"
        )
    }

    // MARK: - Pure algorithm tests: QuranIntegrityChecker.verify in isolation, no real DB

    func testPureVerifyAcceptsCorrectChecksum() {
        let (surahs, ayahs) = Self.makeSyntheticFullSizeFixture()
        let checksum = QuranIntegrityChecker.checksum(surahs: surahs, ayahs: ayahs)
        XCTAssertNoThrow(try QuranIntegrityChecker.verify(surahs: surahs, ayahs: ayahs, expectedChecksum: checksum))
    }

    func testPureVerifyRejectsTamperedAyahText() {
        let (surahs, ayahs) = Self.makeSyntheticFullSizeFixture()
        let checksum = QuranIntegrityChecker.checksum(surahs: surahs, ayahs: ayahs)

        var tamperedAyahs = ayahs
        let original = tamperedAyahs[0]
        tamperedAyahs[0] = QuranAyah(
            id: original.id,
            surahNumber: original.surahNumber,
            ayahNumber: original.ayahNumber,
            juzNumber: original.juzNumber,
            pageNumber: original.pageNumber,
            uthmanicText: original.uthmanicText + " TAMPERED",
            searchableText: original.searchableText
        )

        XCTAssertThrowsError(
            try QuranIntegrityChecker.verify(surahs: surahs, ayahs: tamperedAyahs, expectedChecksum: checksum)
        ) { error in
            XCTAssertEqual(error as? QuranIntegrityError, .checksumMismatch)
        }
    }

    func testPureVerifyRejectsWrongSurahCount() {
        let (surahs, ayahs) = Self.makeSyntheticFullSizeFixture()
        let checksum = QuranIntegrityChecker.checksum(surahs: surahs, ayahs: ayahs)
        let shortSurahs = Array(surahs.dropLast())

        XCTAssertThrowsError(
            try QuranIntegrityChecker.verify(surahs: shortSurahs, ayahs: ayahs, expectedChecksum: checksum)
        ) { error in
            XCTAssertEqual(error as? QuranIntegrityError, .surahCountMismatch(expected: 114, actual: 113))
        }
    }

    func testPureVerifyRejectsWrongAyahCount() {
        let (surahs, ayahs) = Self.makeSyntheticFullSizeFixture()
        let checksum = QuranIntegrityChecker.checksum(surahs: surahs, ayahs: ayahs)
        let shortAyahs = Array(ayahs.dropLast())

        XCTAssertThrowsError(
            try QuranIntegrityChecker.verify(surahs: surahs, ayahs: shortAyahs, expectedChecksum: checksum)
        ) { error in
            XCTAssertEqual(error as? QuranIntegrityError, .ayahCountMismatch(expected: 6236, actual: 6235))
        }
    }
}
