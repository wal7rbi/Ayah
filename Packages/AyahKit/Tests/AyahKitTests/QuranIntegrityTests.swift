import Foundation
import SQLite3
import XCTest
@testable import AyahKit

/// Structural integrity of the bundled `quran.sqlite`, read independently
/// via the raw SQLite3 C API (not through a repository layer — that's
/// Stage 4). Mirrors `Scripts/verify_quran`'s checks on the specific
/// assertions named in `ARCHITECTURE.md`'s Stage 3 exit criterion:
/// 114 surahs, 6236 ayahs, ordering, and checksum.
final class QuranIntegrityTests: XCTestCase {
    /// `Resources/Quran/` lives at the repo root, outside any SPM target's
    /// source tree, so it can't be declared as a package resource. Resolve
    /// it relative to this file's own path instead — this always reads the
    /// live, single-source-of-truth file rather than a bundled copy that
    /// could go stale after a re-import.
    private static var quranResourcesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // QuranIntegrityTests.swift -> AyahKitTests/
            .deletingLastPathComponent() // -> Tests/
            .deletingLastPathComponent() // -> AyahKit/
            .deletingLastPathComponent() // -> Packages/
            .deletingLastPathComponent() // -> repo root
            .appendingPathComponent("Resources/Quran")
    }

    private func loadDatabase() throws -> (surahs: [Surah], ayahs: [QuranAyah]) {
        let dbURL = Self.quranResourcesDir.appendingPathComponent("quran.sqlite")
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw XCTSkip("quran.sqlite not found at \(dbURL.path) — run Scripts/import_quran first")
        }

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }

        var surahs: [Surah] = []
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(
            db,
            "SELECT number, name_arabic, name_transliterated, ayah_count FROM surahs ORDER BY number;",
            -1, &stmt, nil
        ), SQLITE_OK)
        while sqlite3_step(stmt) == SQLITE_ROW {
            surahs.append(Surah(
                number: Int(sqlite3_column_int(stmt, 0)),
                nameArabic: String(cString: sqlite3_column_text(stmt, 1)),
                nameTransliterated: String(cString: sqlite3_column_text(stmt, 2)),
                ayahCount: Int(sqlite3_column_int(stmt, 3))
            ))
        }
        sqlite3_finalize(stmt)

        var ayahs: [QuranAyah] = []
        stmt = nil
        XCTAssertEqual(sqlite3_prepare_v2(
            db,
            """
            SELECT id, surah_number, ayah_number, juz_number, page_number, uthmanic_text, searchable_text
            FROM ayahs ORDER BY id;
            """,
            -1, &stmt, nil
        ), SQLITE_OK)
        while sqlite3_step(stmt) == SQLITE_ROW {
            ayahs.append(QuranAyah(
                id: Int(sqlite3_column_int(stmt, 0)),
                surahNumber: Int(sqlite3_column_int(stmt, 1)),
                ayahNumber: Int(sqlite3_column_int(stmt, 2)),
                juzNumber: Int(sqlite3_column_int(stmt, 3)),
                pageNumber: Int(sqlite3_column_int(stmt, 4)),
                uthmanicText: String(cString: sqlite3_column_text(stmt, 5)),
                searchableText: String(cString: sqlite3_column_text(stmt, 6))
            ))
        }
        sqlite3_finalize(stmt)

        return (surahs, ayahs)
    }

    func testSurahAndAyahCounts() throws {
        let (surahs, ayahs) = try loadDatabase()
        XCTAssertEqual(surahs.count, 114)
        XCTAssertEqual(ayahs.count, 6236)
    }

    func testGlobalIDsAreContiguous() throws {
        let (_, ayahs) = try loadDatabase()
        for (index, ayah) in ayahs.enumerated() {
            XCTAssertEqual(ayah.id, index + 1, "global id gap/duplicate at position \(index)")
        }
    }

    func testAyahNumbersAreContiguousWithinEachSurah() throws {
        let (surahs, ayahs) = try loadDatabase()
        let ayahsBySurah = Dictionary(grouping: ayahs, by: \.surahNumber)
        for surah in surahs {
            let numbers = Set((ayahsBySurah[surah.number] ?? []).map(\.ayahNumber))
            XCTAssertEqual(numbers, Set(1...surah.ayahCount), "surah \(surah.number) has gaps or duplicates")
        }
    }

    /// Exercises the real runtime integrity-checking code path (the one
    /// `QuranRepository` runs at app launch, see ARCHITECTURE.md §8)
    /// against the actual bundled data, rather than reimplementing the
    /// checksum a second time in this file.
    func testChecksumMatches() throws {
        let (surahs, ayahs) = try loadDatabase()
        let checksumURL = Self.quranResourcesDir.appendingPathComponent("CHECKSUM")
        let expected = try String(contentsOf: checksumURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertNoThrow(try QuranIntegrityChecker.verify(surahs: surahs, ayahs: ayahs, expectedChecksum: expected))
    }
}
