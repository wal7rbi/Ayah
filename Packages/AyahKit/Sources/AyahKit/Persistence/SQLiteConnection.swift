import Foundation
import SQLite3

public enum SQLiteConnectionError: Error, Equatable, Sendable {
    case cannotOpenDatabase(String)
    case queryFailed(String)
}

/// A small read-write SQLite wrapper for local, user-editable data
/// (`ayah_user.sqlite` — see ARCHITECTURE.md §15). Deliberately separate
/// from `QuranRepository`'s own raw SQLite calls: that repository is
/// read-only bundled data verified by a checksum, while this wrapper
/// exists specifically for mutable app-owned data, so the two can never
/// be confused.
public final class SQLiteConnection {
    private let db: OpaquePointer?

    public init(path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        if !directory.isEmpty {
            try? FileManager.default.createDirectory(
                atPath: directory, withIntermediateDirectories: true
            )
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            // sqlite3_open_v2 can allocate a handle even on failure (used
            // above just to read the error message); since `init` throws
            // here, `self.db` is never set and `deinit` never runs, so
            // this handle must be closed explicitly or it leaks for the
            // process lifetime. sqlite3_close(nil) is a documented no-op.
            sqlite3_close(handle)
            throw SQLiteConnectionError.cannotOpenDatabase(message)
        }
        self.db = handle
    }

    deinit {
        sqlite3_close(db)
    }

    public func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteConnectionError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Runs an INSERT/UPDATE/DELETE with bound parameters.
    public func run(_ sql: String, bind: (OpaquePointer?) -> Void = { _ in }) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteConnectionError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteConnectionError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Runs a SELECT with bound parameters, mapping each row.
    public func query<T>(
        _ sql: String,
        bind: (OpaquePointer?) -> Void = { _ in },
        map: (OpaquePointer?) throws -> T
    ) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteConnectionError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt)
        var results: [T] = []
        // `sqlite3_step` returning anything other than SQLITE_ROW doesn't
        // necessarily mean "no more rows" — a schema change out from
        // under this connection, a lock, or an I/O error surfaces here
        // as SQLITE_ERROR/SQLITE_MISUSE, not at `sqlite3_prepare_v2` time
        // (prepare can succeed against a schema that's since become
        // invalid). Treating anything-but-ROW as "done" silently turned a
        // real query failure into a successful empty result.
        stepLoop: while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW:
                results.append(try map(stmt))
            case SQLITE_DONE:
                break stepLoop
            default:
                throw SQLiteConnectionError.queryFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
        return results
    }
}
