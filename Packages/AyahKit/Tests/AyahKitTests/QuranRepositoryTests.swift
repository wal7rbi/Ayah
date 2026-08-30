import Foundation
import SQLite3
import XCTest
@testable import AyahKit

final class QuranRepositoryTests: XCTestCase {
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

    private func makeRepository() throws -> QuranRepository {
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

    func testInitSucceedsAgainstBundledData() throws {
        _ = try makeRepository()
    }

    func testInitFailsWithWrongChecksum() throws {
        let dir = Self.quranResourcesDir
        let dbPath = dir.appendingPathComponent("quran.sqlite").path
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw XCTSkip("quran.sqlite not found at \(dbPath) — run Scripts/import_quran first")
        }

        let bogusChecksumFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try "sha256:0000000000000000000000000000000000000000000000000000000000000000"
            .write(to: bogusChecksumFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: bogusChecksumFile) }

        XCTAssertThrowsError(
            try QuranRepository(databasePath: dbPath, checksumPath: bogusChecksumFile.path)
        ) { error in
            XCTAssertEqual(error as? QuranIntegrityError, .checksumMismatch)
        }
    }

    func testInitRejectsNullRequiredTextInsteadOfCrashing() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let databasePath = temporaryDirectory.appendingPathComponent("quran.sqlite").path
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databasePath, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(
            database,
            """
            CREATE TABLE surahs(number INTEGER, name_arabic TEXT, name_transliterated TEXT, ayah_count INTEGER);
            CREATE TABLE ayahs(id INTEGER, surah_number INTEGER, ayah_number INTEGER, juz_number INTEGER,
                               page_number INTEGER, uthmanic_text TEXT, searchable_text TEXT);
            INSERT INTO surahs VALUES(1, NULL, 'Al-Fatihah', 7);
            """,
            nil,
            nil,
            nil
        ), SQLITE_OK)

        let checksumPath = temporaryDirectory.appendingPathComponent("CHECKSUM")
        try "sha256:unused".write(to: checksumPath, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try QuranRepository(databasePath: databasePath, checksumPath: checksumPath.path)
        ) { error in
            guard case QuranRepositoryError.corruptedColumn("surahs.name_arabic") = error else {
                return XCTFail("Expected a corrupted-column error, got \(error)")
            }
        }
    }

    func testFirstAyahIsAlFatihahOpening() throws {
        let repository = try makeRepository()
        let ayah = try XCTUnwrap(repository.ayah(surah: 1, ayah: 1))
        XCTAssertEqual(ayah.id, 1)
        XCTAssertEqual(ayah.juzNumber, 1)
        XCTAssertEqual(ayah.pageNumber, 1)
        XCTAssertFalse(ayah.uthmanicText.isEmpty)
        XCTAssertEqual(ayah.uthmanicText, repository.ayah(id: 1)?.uthmanicText)
    }

    func testOutOfRangeAyahReturnsNil() throws {
        let repository = try makeRepository()
        XCTAssertNil(repository.ayah(surah: 1, ayah: 999))
        XCTAssertNil(repository.ayah(id: 0))
        XCTAssertNil(repository.ayah(id: 6237))
    }

    /// Regression test: `ayah(surah:ayah:)`/`ayah(id:)` used to force-convert
    /// their `Int` parameters straight into `Int32` for `sqlite3_bind_int`,
    /// which traps (crashes the process) on a value outside `Int32`'s
    /// range. A value this large can never be a real surah/ayah/id, so it
    /// must be treated the same as any other "no such ayah" lookup.
    func testInt32OverflowingLookupReturnsNilInsteadOfCrashing() throws {
        let repository = try makeRepository()
        XCTAssertNil(repository.ayah(surah: Int.max, ayah: 1))
        XCTAssertNil(repository.ayah(surah: 1, ayah: Int.max))
        XCTAssertNil(repository.ayah(id: Int.max))
        XCTAssertNil(repository.ayah(id: Int.min))
    }

    func testSurahsReturnsAllOneHundredFourteen() throws {
        let repository = try makeRepository()
        let surahs = repository.surahs()
        XCTAssertEqual(surahs.count, 114)
        XCTAssertEqual(surahs.first?.number, 1)
        XCTAssertEqual(surahs.last?.number, 114)
    }

    func testRandomAyahReturnsAValidAyah() throws {
        let repository = try makeRepository()
        let ayah = try XCTUnwrap(repository.randomAyah())
        XCTAssertTrue((1...6236).contains(ayah.id))
    }

    func testRandomAyahSearchableTextContainsReturnsAMatchingAyah() throws {
        let repository = try makeRepository()
        let ayah = try XCTUnwrap(repository.randomAyah(searchableTextContains: "صلاة"))
        XCTAssertTrue(ayah.searchableText.contains("صلاة"))
        XCTAssertFalse(ayah.uthmanicText.isEmpty)
    }

    func testRandomAyahSearchableTextContainsCanReturnDifferentAyahs() throws {
        let repository = try makeRepository()
        let ids = Set((0..<20).compactMap { _ in repository.randomAyah(searchableTextContains: "صلاة")?.id })
        XCTAssertGreaterThanOrEqual(ids.count, 2)
    }
}
