import Foundation
import SQLite3

public enum MemorizationRepositoryError: Error, Equatable, Sendable {
    case invalidRange
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

    public init(databasePath: String) throws {
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

    @discardableResult
    public func create(
        surahNumber: Int,
        startAyah: Int,
        endAyah: Int,
        repetitionMode: MemorizationSet.RepetitionMode = .sequential,
        isEnabled: Bool = true
    ) throws -> MemorizationSet {
        guard startAyah <= endAyah else {
            throw MemorizationRepositoryError.invalidRange
        }
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

    public func fetchAll() -> [MemorizationSet] {
        (try? connection.query(
            "SELECT \(Self.columns) FROM memorization_sets ORDER BY created_at;",
            map: Self.rowToSet
        )) ?? []
    }

    public func fetchEnabled() -> [MemorizationSet] {
        (try? connection.query(
            "SELECT \(Self.columns) FROM memorization_sets WHERE is_enabled = 1 ORDER BY created_at;",
            map: Self.rowToSet
        )) ?? []
    }

    public func update(_ set: MemorizationSet) throws {
        guard set.startAyah <= set.endAyah else {
            throw MemorizationRepositoryError.invalidRange
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
        try connection.run("UPDATE memorization_sets SET cursor_ayah = ? WHERE id = ?;") { stmt in
            sqlite3_bind_int(stmt, 1, Int32(cursorAyah))
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

    private static func rowToSet(_ stmt: OpaquePointer?) -> MemorizationSet {
        MemorizationSet(
            id: String(cString: sqlite3_column_text(stmt, 0)),
            surahNumber: Int(sqlite3_column_int(stmt, 1)),
            startAyah: Int(sqlite3_column_int(stmt, 2)),
            endAyah: Int(sqlite3_column_int(stmt, 3)),
            isEnabled: sqlite3_column_int(stmt, 4) != 0,
            repetitionMode: MemorizationSet.RepetitionMode(
                rawValue: String(cString: sqlite3_column_text(stmt, 5))
            ) ?? .sequential,
            cursorAyah: optionalInt(stmt, 6),
            createdAt: isoFormatter.date(from: String(cString: sqlite3_column_text(stmt, 7))) ?? Date(),
            lastShownAt: optionalText(stmt, 8).flatMap { isoFormatter.date(from: $0) },
            easeFactor: optionalDouble(stmt, 9),
            reviewIntervalDays: optionalInt(stmt, 10)
        )
    }

    private static func optionalInt(_ stmt: OpaquePointer?, _ index: Int32) -> Int? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, index))
    }

    private static func optionalDouble(_ stmt: OpaquePointer?, _ index: Int32) -> Double? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, index)
    }

    private static func optionalText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL, let text = sqlite3_column_text(stmt, index) else {
            return nil
        }
        return String(cString: text)
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
