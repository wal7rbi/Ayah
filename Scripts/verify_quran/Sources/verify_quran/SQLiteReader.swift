import Foundation
import SQLite3

enum SQLiteReaderError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String)

    var description: String {
        switch self {
        case .open(let m): return "sqlite3_open failed: \(m)"
        case .prepare(let m): return "sqlite3_prepare_v2 failed: \(m)"
        }
    }
}

func readQuranDatabase(path: String) throws -> (surahs: [SurahRecord], ayahs: [AyahRecord]) {
    var db: OpaquePointer?
    guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        throw SQLiteReaderError.open(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_close(db) }

    var surahs: [SurahRecord] = []
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(
        db,
        "SELECT number, name_arabic, name_transliterated, ayah_count FROM surahs ORDER BY number;",
        -1, &stmt, nil
    ) == SQLITE_OK else {
        throw SQLiteReaderError.prepare(String(cString: sqlite3_errmsg(db)))
    }
    while sqlite3_step(stmt) == SQLITE_ROW {
        surahs.append(SurahRecord(
            number: Int(sqlite3_column_int(stmt, 0)),
            nameArabic: String(cString: sqlite3_column_text(stmt, 1)),
            nameTransliterated: String(cString: sqlite3_column_text(stmt, 2)),
            ayahCount: Int(sqlite3_column_int(stmt, 3))
        ))
    }
    sqlite3_finalize(stmt)

    var ayahs: [AyahRecord] = []
    stmt = nil
    guard sqlite3_prepare_v2(
        db,
        """
        SELECT id, surah_number, ayah_number, juz_number, page_number, uthmanic_text, searchable_text
        FROM ayahs ORDER BY id;
        """,
        -1, &stmt, nil
    ) == SQLITE_OK else {
        throw SQLiteReaderError.prepare(String(cString: sqlite3_errmsg(db)))
    }
    while sqlite3_step(stmt) == SQLITE_ROW {
        ayahs.append(AyahRecord(
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
