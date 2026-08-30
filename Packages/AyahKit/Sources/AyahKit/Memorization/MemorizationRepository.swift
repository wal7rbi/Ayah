import Foundation
import SQLite3

public enum MemorizationRepositoryError: Error, Equatable, Sendable {
    case invalidRange
    case invalidSurahNumber
    case ayahOutsideSurah
    case valueOutOfRange
    /// A `NOT NULL` column (id, repetition_mode, created_at) came back
    /// NULL from a row — `ayah_user.sqlite` has no checksum guard the way
    /// `quran.sqlite` does, so a hand-edited or corrupted file can violate
    /// its own schema constraints.
    case corruptedRow
    case notFound
}

/// CRUD over `memorization_sets` in the local `ayah_user.sqlite` (see
/// ARCHITECTURE.md §7/§15/"Module responsibilities"). Creates the table
/// itself on first open (`CREATE TABLE IF NOT EXISTS`) rather than
/// requiring a separate migration step — there is exactly one schema
/// version so far.
public final class MemorizationRepository {
    private let connection: SQLiteConnection
    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter
    }()

    /// Canonical Hafs ayah counts for surahs 1...114. This is an
    /// independent structural invariant, not derived from mutable
    /// memorization rows, so corrupt persisted ranges are rejected before
    /// SwiftUI constructs a `ClosedRange` for the editor.
    private static let canonicalAyahCounts = [
        7, 286, 200, 176, 120, 165, 206, 75, 129, 109,
        123, 111, 43, 52, 99, 128, 111, 110, 98, 135,
        112, 78, 118, 64, 77, 227, 93, 88, 69, 60,
        34, 30, 73, 54, 45, 83, 182, 88, 75, 85,
        54, 53, 89, 59, 37, 35, 38, 29, 18, 45,
        60, 49, 62, 55, 78, 96, 29, 22, 24, 13,
        14, 11, 11, 18, 12, 12, 30, 52, 52, 44,
        28, 28, 20, 56, 40, 31, 50, 40, 46, 42,
        29, 19, 36, 25, 22, 17, 19, 26, 30, 20,
        15, 21, 11, 8, 8, 19, 5, 8, 8, 11,
        11, 8, 3, 9, 5, 4, 7, 3, 6, 3,
        5, 4, 5, 6,
    ]

    public init(databasePath: String) throws {
        let interval = PerformanceSignposts.begin("MemorizationRepositoryInitialization")
        defer { PerformanceSignposts.end("MemorizationRepositoryInitialization", interval) }
        self.connection = try SQLiteConnection(path: databasePath)
        try connection.execute("""
            CREATE TABLE IF NOT EXISTS memorization_sets (
              id                   TEXT PRIMARY KEY,
              surah_number         INTEGER NOT NULL,
              start_ayah           INTEGER NOT NULL,
              end_ayah             INTEGER NOT NULL,
              is_enabled           INTEGER NOT NULL DEFAULT 1,
              repetition_mode      TEXT NOT NULL DEFAULT 'sequential',
              cursor_ayah          INTEGER,
              created_at           TEXT NOT NULL,
              last_shown_at        TEXT,
              ease_factor          REAL,
              review_interval_days INTEGER
            );
            """)
    }

    /// Guards every `surahNumber`/`startAyah`/`endAyah` before it ever
    /// reaches `Int32(...)` in a `sqlite3_bind_int` call — those calls
    /// trap on an out-of-`Int32`-range `Int`, so this must run first for
    /// any caller-supplied value (a numeric-entry bug, an imported/restored
    /// backup, etc.), not just the in-range values the current Settings UI
    /// happens to always send.
    private static func validate(surahNumber: Int, startAyah: Int, endAyah: Int) throws {
        guard (1...Self.canonicalAyahCounts.count).contains(surahNumber) else {
            throw MemorizationRepositoryError.invalidSurahNumber
        }
        guard startAyah >= 1, endAyah >= 1 else {
            throw MemorizationRepositoryError.invalidRange
        }
        guard startAyah <= endAyah else {
            throw MemorizationRepositoryError.invalidRange
        }
        guard Int32(exactly: startAyah) != nil, Int32(exactly: endAyah) != nil else {
            throw MemorizationRepositoryError.valueOutOfRange
        }
        guard endAyah <= Self.canonicalAyahCounts[surahNumber - 1] else {
            throw MemorizationRepositoryError.ayahOutsideSurah
        }
    }

    @discardableResult
    public func create(
        surahNumber: Int,
        startAyah: Int,
        endAyah: Int,
        repetitionMode: MemorizationSet.RepetitionMode = .sequential,
        isEnabled: Bool = true
    ) throws -> MemorizationSet {
        try Self.validate(surahNumber: surahNumber, startAyah: startAyah, endAyah: endAyah)
        let set = MemorizationSet(
            surahNumber: surahNumber,
            startAyah: startAyah,
            endAyah: endAyah,
            isEnabled: isEnabled,
            repetitionMode: repetitionMode
        )
        try insert(set)
        return set
    }

    /// The error from the most recent `fetchAll()`/`fetchEnabled()` call,
    /// or `nil` if it succeeded. Both methods return `[]` on failure (so
    /// existing callers that only care about the list don't need to
    /// change), but a real query failure — a locked file, disk I/O error,
    /// a corrupted table — must stay distinguishable from "the user
    /// genuinely has no memorization sets"; check this after a fetch that
    /// unexpectedly comes back empty.
    public private(set) var lastFetchError: Error?

    public func fetchAll() -> [MemorizationSet] {
        do {
            let sets = try connection.query(
                "SELECT \(Self.columns) FROM memorization_sets ORDER BY created_at;",
                map: Self.rowToSet
            )
            lastFetchError = nil
            return sets
        } catch {
            lastFetchError = error
            return []
        }
    }

    public func fetchEnabled() -> [MemorizationSet] {
        do {
            let sets = try connection.query(
                "SELECT \(Self.columns) FROM memorization_sets WHERE is_enabled = 1 ORDER BY created_at;",
                map: Self.rowToSet
            )
            lastFetchError = nil
            return sets
        } catch {
            lastFetchError = error
            return []
        }
    }

    public func update(_ set: MemorizationSet) throws {
        try Self.validate(surahNumber: set.surahNumber, startAyah: set.startAyah, endAyah: set.endAyah)
        if let cursorAyah = set.cursorAyah {
            guard set.startAyah...set.endAyah ~= cursorAyah,
                  Int32(exactly: cursorAyah) != nil else {
                throw MemorizationRepositoryError.valueOutOfRange
            }
        }
        if let reviewIntervalDays = set.reviewIntervalDays,
           (reviewIntervalDays < 0 || Int32(exactly: reviewIntervalDays) == nil) {
            throw MemorizationRepositoryError.valueOutOfRange
        }
        if let easeFactor = set.easeFactor, !easeFactor.isFinite || easeFactor <= 0 {
            throw MemorizationRepositoryError.valueOutOfRange
        }
        try connection.run(
            """
            UPDATE memorization_sets SET
              surah_number = ?, start_ayah = ?, end_ayah = ?, is_enabled = ?,
              repetition_mode = ?, cursor_ayah = ?, last_shown_at = ?,
              ease_factor = ?, review_interval_days = ?
            WHERE id = ?;
            """
        ) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(set.surahNumber))
            sqlite3_bind_int(stmt, 2, Int32(set.startAyah))
            sqlite3_bind_int(stmt, 3, Int32(set.endAyah))
            sqlite3_bind_int(stmt, 4, set.isEnabled ? 1 : 0)
            sqlite3_bind_text(stmt, 5, set.repetitionMode.rawValue, -1, Self.transient)
            Self.bindOptionalInt(stmt, 6, set.cursorAyah)
            Self.bindOptionalText(stmt, 7, set.lastShownAt.map { Self.isoFormatter.string(from: $0) })
            Self.bindOptionalDouble(stmt, 8, set.easeFactor)
            Self.bindOptionalInt(stmt, 9, set.reviewIntervalDays)
            sqlite3_bind_text(stmt, 10, set.id, -1, Self.transient)
        }
    }

    public func delete(id: String) throws {
        try connection.run("DELETE FROM memorization_sets WHERE id = ?;") { stmt in
            sqlite3_bind_text(stmt, 1, id, -1, Self.transient)
        }
    }

    /// Advances a `.sequential` set's walk position — the only mutation
    /// `VerseScheduler` performs on its own each time it draws from a
    /// sequential memorization set.
    public func updateCursor(id: String, cursorAyah: Int) throws {
        guard cursorAyah >= 1, let cursor32 = Int32(exactly: cursorAyah) else {
            throw MemorizationRepositoryError.valueOutOfRange
        }
        let ranges = try connection.query(
            "SELECT start_ayah, end_ayah FROM memorization_sets WHERE id = ?;",
            bind: { sqlite3_bind_text($0, 1, id, -1, Self.transient) }
        ) { statement in
            (try Self.requiredInt(statement, 0), try Self.requiredInt(statement, 1))
        }
        guard let (startAyah, endAyah) = ranges.first else {
            throw MemorizationRepositoryError.notFound
        }
        guard startAyah >= 1, startAyah <= endAyah else {
            throw MemorizationRepositoryError.corruptedRow
        }
        guard (startAyah...endAyah).contains(cursorAyah) else {
            throw MemorizationRepositoryError.valueOutOfRange
        }
        try connection.run("UPDATE memorization_sets SET cursor_ayah = ? WHERE id = ?;") { stmt in
            sqlite3_bind_int(stmt, 1, cursor32)
            sqlite3_bind_text(stmt, 2, id, -1, Self.transient)
        }
    }

    private func insert(_ set: MemorizationSet) throws {
        try connection.run(
            """
            INSERT INTO memorization_sets
              (id, surah_number, start_ayah, end_ayah, is_enabled, repetition_mode,
               cursor_ayah, created_at, last_shown_at, ease_factor, review_interval_days)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        ) { stmt in
            sqlite3_bind_text(stmt, 1, set.id, -1, Self.transient)
            sqlite3_bind_int(stmt, 2, Int32(set.surahNumber))
            sqlite3_bind_int(stmt, 3, Int32(set.startAyah))
            sqlite3_bind_int(stmt, 4, Int32(set.endAyah))
            sqlite3_bind_int(stmt, 5, set.isEnabled ? 1 : 0)
            sqlite3_bind_text(stmt, 6, set.repetitionMode.rawValue, -1, Self.transient)
            Self.bindOptionalInt(stmt, 7, set.cursorAyah)
            sqlite3_bind_text(stmt, 8, Self.isoFormatter.string(from: set.createdAt), -1, Self.transient)
            Self.bindOptionalText(stmt, 9, set.lastShownAt.map { Self.isoFormatter.string(from: $0) })
            Self.bindOptionalDouble(stmt, 10, set.easeFactor)
            Self.bindOptionalInt(stmt, 11, set.reviewIntervalDays)
        }
    }

    private static let columns = """
        id, surah_number, start_ayah, end_ayah, is_enabled, repetition_mode, \
        cursor_ayah, created_at, last_shown_at, ease_factor, review_interval_days
        """

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// `id`, `repetition_mode`, and `created_at` are `NOT NULL` in the
    /// schema, but `sqlite3_column_text` returns a null pointer for a NULL
    /// column regardless — `String(cString:)` traps on that, so each must
    /// be checked before conversion rather than assumed safe from the
    /// schema constraint alone (a hand-edited/corrupted file, with no
    /// checksum guard here the way `quran.sqlite` has, can violate it).
    private static func rowToSet(_ stmt: OpaquePointer?) throws -> MemorizationSet {
        guard let id = try requiredText(stmt, 0), !id.isEmpty,
              let mode = try requiredText(stmt, 5),
              let createdAtValue = try requiredText(stmt, 7) else {
            throw MemorizationRepositoryError.corruptedRow
        }
        guard let repetitionMode = MemorizationSet.RepetitionMode(rawValue: mode),
              let createdAt = isoFormatter.date(from: createdAtValue) else {
            throw MemorizationRepositoryError.corruptedRow
        }
        let surahNumber = try requiredInt(stmt, 1)
        let startAyah = try requiredInt(stmt, 2)
        let endAyah = try requiredInt(stmt, 3)
        let enabledValue = try requiredInt(stmt, 4)
        guard enabledValue == 0 || enabledValue == 1 else {
            throw MemorizationRepositoryError.corruptedRow
        }
        let cursorAyah = try optionalInt(stmt, 6)
        let lastShownAt: Date?
        if let value = try optionalText(stmt, 8) {
            guard let parsed = isoFormatter.date(from: value) else {
                throw MemorizationRepositoryError.corruptedRow
            }
            lastShownAt = parsed
        } else {
            lastShownAt = nil
        }
        let easeFactor = try optionalDouble(stmt, 9)
        if let easeFactor, !easeFactor.isFinite || easeFactor <= 0 {
            throw MemorizationRepositoryError.corruptedRow
        }
        let reviewIntervalDays = try optionalInt(stmt, 10)
        if let reviewIntervalDays,
           (reviewIntervalDays < 0 || Int32(exactly: reviewIntervalDays) == nil) {
            throw MemorizationRepositoryError.corruptedRow
        }
        do {
            try validate(surahNumber: surahNumber, startAyah: startAyah, endAyah: endAyah)
        } catch {
            throw MemorizationRepositoryError.corruptedRow
        }
        if let cursorAyah, !(startAyah...endAyah).contains(cursorAyah) {
            throw MemorizationRepositoryError.corruptedRow
        }
        return MemorizationSet(
            id: id,
            surahNumber: surahNumber,
            startAyah: startAyah,
            endAyah: endAyah,
            isEnabled: enabledValue == 1,
            repetitionMode: repetitionMode,
            cursorAyah: cursorAyah,
            createdAt: createdAt,
            lastShownAt: lastShownAt,
            easeFactor: easeFactor,
            reviewIntervalDays: reviewIntervalDays
        )
    }

    private static func requiredInt(_ stmt: OpaquePointer?, _ index: Int32) throws -> Int {
        guard sqlite3_column_type(stmt, index) == SQLITE_INTEGER,
              let value = Int(exactly: sqlite3_column_int64(stmt, index)) else {
            throw MemorizationRepositoryError.corruptedRow
        }
        return value
    }

    private static func optionalInt(_ stmt: OpaquePointer?, _ index: Int32) throws -> Int? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        return try requiredInt(stmt, index)
    }

    private static func optionalDouble(_ stmt: OpaquePointer?, _ index: Int32) throws -> Double? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        guard [SQLITE_FLOAT, SQLITE_INTEGER].contains(sqlite3_column_type(stmt, index)) else {
            throw MemorizationRepositoryError.corruptedRow
        }
        return sqlite3_column_double(stmt, index)
    }

    private static func requiredText(_ stmt: OpaquePointer?, _ index: Int32) throws -> String? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        guard sqlite3_column_type(stmt, index) == SQLITE_TEXT,
              let text = sqlite3_column_text(stmt, index) else {
            throw MemorizationRepositoryError.corruptedRow
        }
        return String(cString: text)
    }

    private static func optionalText(_ stmt: OpaquePointer?, _ index: Int32) throws -> String? {
        try requiredText(stmt, index)
    }

    private static func bindOptionalInt(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value {
            sqlite3_bind_int(stmt, index, Int32(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private static func bindOptionalDouble(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private static func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, transient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
}
