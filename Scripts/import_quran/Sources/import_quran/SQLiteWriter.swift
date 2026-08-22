import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteWriterError: Error, CustomStringConvertible {
    case open(String)
    case exec(String)
    case prepare(String)
    case step(String)

    var description: String {
        switch self {
        case .open(let m): return "sqlite3_open failed: \(m)"
        case .exec(let m): return "sqlite3_exec failed: \(m)"
        case .prepare(let m): return "sqlite3_prepare_v2 failed: \(m)"
        case .step(let m): return "sqlite3_step failed: \(m)"
        }
    }
}

/// Writes the immutable Quran schema (see ARCHITECTURE.md §7) to a fresh
/// SQLite file. Any existing file at `path` is deleted first.
func writeQuranDatabase(
    path: String,
    surahs: [SurahRecord],
    ayahs: [AyahRecord],
    meta: [(String, String)]
) throws {
    if FileManager.default.fileExists(atPath: path) {
        try FileManager.default.removeItem(atPath: path)
    }

    var db: OpaquePointer?
    guard sqlite3_open(path, &db) == SQLITE_OK else {
        throw SQLiteWriterError.open(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_close(db) }

    func exec(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<Int8>?
        guard sqlite3_exec(db, sql, nil, nil, &errMsg) == SQLITE_OK else {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errMsg)
            throw SQLiteWriterError.exec(msg)
        }
    }

    try exec("""
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
    CREATE TABLE meta (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
    """)

    try exec("BEGIN TRANSACTION;")

    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(
        db,
        "INSERT INTO surahs (number, name_arabic, name_transliterated, ayah_count) VALUES (?, ?, ?, ?);",
        -1, &stmt, nil
    ) == SQLITE_OK else {
        throw SQLiteWriterError.prepare(String(cString: sqlite3_errmsg(db)))
    }
    for surah in surahs {
        sqlite3_bind_int(stmt, 1, Int32(surah.number))
        sqlite3_bind_text(stmt, 2, surah.nameArabic, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, surah.nameTransliterated, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 4, Int32(surah.ayahCount))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteWriterError.step(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_reset(stmt)
    }
    sqlite3_finalize(stmt)

    stmt = nil
    guard sqlite3_prepare_v2(
        db,
        """
        INSERT INTO ayahs (id, surah_number, ayah_number, juz_number, page_number, uthmanic_text, searchable_text)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """,
        -1, &stmt, nil
    ) == SQLITE_OK else {
        throw SQLiteWriterError.prepare(String(cString: sqlite3_errmsg(db)))
    }
    for ayah in ayahs {
        sqlite3_bind_int(stmt, 1, Int32(ayah.id))
        sqlite3_bind_int(stmt, 2, Int32(ayah.surahNumber))
        sqlite3_bind_int(stmt, 3, Int32(ayah.ayahNumber))
        sqlite3_bind_int(stmt, 4, Int32(ayah.juzNumber))
        sqlite3_bind_int(stmt, 5, Int32(ayah.pageNumber))
        sqlite3_bind_text(stmt, 6, ayah.uthmanicText, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, ayah.searchableText, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteWriterError.step(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_reset(stmt)
    }
    sqlite3_finalize(stmt)

    stmt = nil
    guard sqlite3_prepare_v2(db, "INSERT INTO meta (key, value) VALUES (?, ?);", -1, &stmt, nil) == SQLITE_OK else {
        throw SQLiteWriterError.prepare(String(cString: sqlite3_errmsg(db)))
    }
    for (key, value) in meta {
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, value, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteWriterError.step(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_reset(stmt)
    }
    sqlite3_finalize(stmt)

    try exec("COMMIT;")
    try exec("CREATE INDEX idx_ayahs_juz  ON ayahs(juz_number);")
    try exec("CREATE INDEX idx_ayahs_page ON ayahs(page_number);")
}
