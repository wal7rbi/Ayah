import Foundation
import SQLite3

enum SQLiteReaderError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String)
    case step(String)
    case corruptedColumn(String)

    var description: String {
        switch self {
        case .open(let m): return "sqlite3_open failed: \(m)"
        case .prepare(let m): return "sqlite3_prepare_v2 failed: \(m)"
        case .step(let m): return "sqlite3_step failed: \(m)"
        case .corruptedColumn(let name): return "required SQLite text column is invalid: \(name)"
        }
    }
}

func readQuranDatabase(path: String) throws -> (surahs: [SurahRecord], ayahs: [AyahRecord]) {
    var db: OpaquePointer?
    guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        sqlite3_close(db)
        throw SQLiteReaderError.open(message)
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
    do {
        surahRows: while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW:
                surahs.append(SurahRecord(
                    number: Int(sqlite3_column_int(stmt, 0)),
                    nameArabic: try requiredText(stmt, column: 1, name: "surahs.name_arabic"),
                    nameTransliterated: try requiredText(stmt, column: 2, name: "surahs.name_transliterated"),
                    ayahCount: Int(sqlite3_column_int(stmt, 3))
                ))
            case SQLITE_DONE:
                break surahRows
            default:
                throw SQLiteReaderError.step(String(cString: sqlite3_errmsg(db)))
            }
        }
    } catch {
        sqlite3_finalize(stmt)
        throw error
    }
    sqlite3_finalize(stmt)
    stmt = nil

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
    defer { sqlite3_finalize(stmt) }
    while true {
        switch sqlite3_step(stmt) {
        case SQLITE_ROW:
            ayahs.append(AyahRecord(
                id: Int(sqlite3_column_int(stmt, 0)),
                surahNumber: Int(sqlite3_column_int(stmt, 1)),
                ayahNumber: Int(sqlite3_column_int(stmt, 2)),
                juzNumber: Int(sqlite3_column_int(stmt, 3)),
                pageNumber: Int(sqlite3_column_int(stmt, 4)),
                uthmanicText: try requiredText(stmt, column: 5, name: "ayahs.uthmanic_text"),
                searchableText: try requiredText(stmt, column: 6, name: "ayahs.searchable_text")
            ))
        case SQLITE_DONE:
            return (surahs, ayahs)
        default:
            throw SQLiteReaderError.step(String(cString: sqlite3_errmsg(db)))
        }
    }
}

private func requiredText(_ statement: OpaquePointer?, column: Int32, name: String) throws -> String {
    guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
          let value = sqlite3_column_text(statement, column)
    else {
        throw SQLiteReaderError.corruptedColumn(name)
    }
    return String(cString: value)
}
