import Foundation
import SQLite3

public enum QuranRepositoryError: Error, Sendable {
    case cannotOpenDatabase(String)
    case cannotReadChecksum(String)
    case queryFailed(String)
}

/// Read-only access to the bundled `quran.sqlite`. Verifies data
/// integrity once at init via `QuranIntegrityChecker` and throws rather
/// than silently exposing unverified text — the caller is responsible
/// for surfacing that as a visible error (see ARCHITECTURE.md §8).
public final class QuranRepository {
    private let db: OpaquePointer?
    private let cachedSurahs: [Surah]

    private static let ayahColumns =
        "id, surah_number, ayah_number, juz_number, page_number, uthmanic_text, searchable_text"

    public init(databasePath: String, checksumPath: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            throw QuranRepositoryError.cannotOpenDatabase(message)
        }
        self.db = handle

        let surahs = try Self.loadAllSurahs(db: handle)
        let ayahs = try Self.loadAllAyahs(db: handle)

        guard let expectedChecksum = try? String(contentsOfFile: checksumPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            throw QuranRepositoryError.cannotReadChecksum(checksumPath)
        }
        try QuranIntegrityChecker.verify(surahs: surahs, ayahs: ayahs, expectedChecksum: expectedChecksum)

        self.cachedSurahs = surahs
    }

    deinit {
        sqlite3_close(db)
    }

    public func surahs() -> [Surah] {
        cachedSurahs
    }

    public func ayah(surah surahNumber: Int, ayah ayahNumber: Int) -> QuranAyah? {
        try? Self.queryOneAyah(
            db: db,
            sql: "SELECT \(Self.ayahColumns) FROM ayahs WHERE surah_number = ? AND ayah_number = ?;"
        ) {
            sqlite3_bind_int($0, 1, Int32(surahNumber))
            sqlite3_bind_int($0, 2, Int32(ayahNumber))
        }
    }

    public func ayah(id: Int) -> QuranAyah? {
        try? Self.queryOneAyah(
            db: db,
            sql: "SELECT \(Self.ayahColumns) FROM ayahs WHERE id = ?;"
        ) {
            sqlite3_bind_int($0, 1, Int32(id))
        }
    }

    /// Uniform random ayah from the whole Quran. Weighted selection
    /// (memorization sets vs. general pool) is `VerseScheduler`'s job in
    /// a later stage — this is deliberately the simplest possible
    /// selection, matching Stage 4's "minimal fixed-interval timer" scope.
    public func randomAyah() -> QuranAyah? {
        try? Self.queryOneAyah(
            db: db,
            sql: "SELECT \(Self.ayahColumns) FROM ayahs ORDER BY RANDOM() LIMIT 1;",
            bind: { _ in }
        )
    }

    /// Uniform-random ayah whose `searchable_text` contains `substring` —
    /// used to pick a rotating "prayer" ayah for the in-notch prayer-alert
    /// card. Must filter on `searchable_text`, never `uthmanic_text`:
    /// Uthmani orthography interleaves diacritics between every consonant
    /// and often renders an "اة" ending as a dagger-alef riding a
    /// preceding و rather than a literal alef, so a plain-spelled word
    /// like "الصلاة" can never substring-match `uthmanic_text`.
    /// `searchable_text` is KFGQPC's own pre-simplified plain-spelling
    /// column and is the only column this kind of query can match
    /// against — the row's `uthmanic_text` is still what's returned for
    /// display, per this file's rule that display text always comes from
    /// `uthmanic_text`.
    public func randomAyah(searchableTextContains substring: String) -> QuranAyah? {
        try? Self.queryOneAyah(
            db: db,
            sql: "SELECT \(Self.ayahColumns) FROM ayahs WHERE searchable_text LIKE ? ORDER BY RANDOM() LIMIT 1;"
        ) { stmt in
            sqlite3_bind_text(stmt, 1, "%\(substring)%", -1, Self.transient)
        }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func loadAllSurahs(db: OpaquePointer?) throws -> [Surah] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "SELECT number, name_arabic, name_transliterated, ayah_count FROM surahs ORDER BY number;",
            -1, &stmt, nil
        ) == SQLITE_OK else {
            throw QuranRepositoryError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var results: [Surah] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(Surah(
                number: Int(sqlite3_column_int(stmt, 0)),
                nameArabic: String(cString: sqlite3_column_text(stmt, 1)),
                nameTransliterated: String(cString: sqlite3_column_text(stmt, 2)),
                ayahCount: Int(sqlite3_column_int(stmt, 3))
            ))
        }
        return results
    }

    private static func loadAllAyahs(db: OpaquePointer?) throws -> [QuranAyah] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "SELECT \(ayahColumns) FROM ayahs ORDER BY id;",
            -1, &stmt, nil
        ) == SQLITE_OK else {
            throw QuranRepositoryError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var results: [QuranAyah] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(rowToAyah(stmt))
        }
        return results
    }

    private static func queryOneAyah(
        db: OpaquePointer?,
        sql: String,
        bind: (OpaquePointer?) -> Void
    ) throws -> QuranAyah? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw QuranRepositoryError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return rowToAyah(stmt)
    }

    private static func rowToAyah(_ stmt: OpaquePointer?) -> QuranAyah {
        QuranAyah(
            id: Int(sqlite3_column_int(stmt, 0)),
            surahNumber: Int(sqlite3_column_int(stmt, 1)),
            ayahNumber: Int(sqlite3_column_int(stmt, 2)),
            juzNumber: Int(sqlite3_column_int(stmt, 3)),
            pageNumber: Int(sqlite3_column_int(stmt, 4)),
            uthmanicText: String(cString: sqlite3_column_text(stmt, 5)),
            searchableText: String(cString: sqlite3_column_text(stmt, 6))
        )
    }
}
