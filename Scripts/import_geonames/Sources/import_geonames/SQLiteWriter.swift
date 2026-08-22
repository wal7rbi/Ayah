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

/// Writes the bundled city-lookup schema (see ARCHITECTURE.md §12) to a
/// fresh SQLite file. Any existing file at `path` is deleted first.
func writeCitiesDatabase(
    path: String,
    cities: [CityRecord],
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
    CREATE TABLE cities (
      geoname_id    INTEGER PRIMARY KEY,
      name          TEXT NOT NULL,
      name_arabic   TEXT,
      country_code  TEXT NOT NULL,
      latitude      REAL NOT NULL,
      longitude     REAL NOT NULL,
      timezone      TEXT NOT NULL,
      population    INTEGER NOT NULL
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
        """
        INSERT INTO cities (geoname_id, name, name_arabic, country_code, latitude, longitude, timezone, population)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """,
        -1, &stmt, nil
    ) == SQLITE_OK else {
        throw SQLiteWriterError.prepare(String(cString: sqlite3_errmsg(db)))
    }
    for city in cities {
        sqlite3_bind_int(stmt, 1, Int32(city.geonameID))
        sqlite3_bind_text(stmt, 2, city.name, -1, SQLITE_TRANSIENT)
        if let nameArabic = city.nameArabic {
            sqlite3_bind_text(stmt, 3, nameArabic, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        sqlite3_bind_text(stmt, 4, city.countryCode, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 5, city.latitude)
        sqlite3_bind_double(stmt, 6, city.longitude)
        sqlite3_bind_text(stmt, 7, city.timezone, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 8, Int32(city.population))
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
    try exec("CREATE INDEX idx_cities_country ON cities(country_code);")
}
