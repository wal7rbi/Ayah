import CryptoKit
import Foundation
import SQLite3

public enum LocationRepositoryError: Error, Sendable {
    case cannotOpenDatabase(String)
    case cannotReadChecksum(String)
    case checksumMismatch
    case queryFailed(String)
}

/// Read-only access to the bundled GeoNames subset
/// (`Resources/GeoNames/cities_filtered.sqlite`, ARCHITECTURE.md §12).
/// Mirrors `QuranRepository`'s raw-SQLite pattern rather than
/// `Persistence/SQLiteConnection`: this is immutable, bundled, read-only
/// data like `quran.sqlite`, not app-owned mutable state — it just
/// carries a bundle-file checksum so corrupt or substituted city and
/// timezone data fails closed before it can affect prayer calculations.
public final class LocationRepository {
    private let db: OpaquePointer?
    private let cachedCities: [City]

    private static let cityColumns =
        "geoname_id, name, name_arabic, country_code, latitude, longitude, timezone, population"

    public init(databasePath: String, checksumPath: String? = nil) throws {
        let interval = PerformanceSignposts.begin("LocationRepositoryInitialization")
        defer { PerformanceSignposts.end("LocationRepositoryInitialization", interval) }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            // See SQLiteConnection.init's identical guard for why this
            // close is needed: sqlite3_open_v2 can allocate a handle even
            // on failure, and since `init` throws before `self.db` is
            // ever set, `deinit` never runs to close it otherwise.
            sqlite3_close(handle)
            throw LocationRepositoryError.cannotOpenDatabase(message)
        }
        let cities: [City]
        do {
            if let checksumPath {
                try Self.verifyFileChecksum(databasePath: databasePath, checksumPath: checksumPath)
            }
            cities = try Self.loadAllCities(db: handle)
        } catch {
            sqlite3_close(handle)
            throw error
        }
        self.db = handle
        self.cachedCities = cities
    }

    deinit {
        sqlite3_close(db)
    }

    /// All bundled cities, largest population first — a sensible default
    /// order for a future city picker.
    public func cities() -> [City] {
        cachedCities
    }

    public func city(id: Int) -> City? {
        cachedCities.first { $0.id == id }
    }

    private static func loadAllCities(db: OpaquePointer?) throws -> [City] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "SELECT \(cityColumns) FROM cities ORDER BY population DESC;",
            -1, &stmt, nil
        ) == SQLITE_OK else {
            throw LocationRepositoryError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var results: [City] = []
        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW:
                results.append(try city(from: stmt))
            case SQLITE_DONE:
                guard !results.isEmpty else {
                    throw LocationRepositoryError.queryFailed("cities table was empty")
                }
                return results
            default:
                throw LocationRepositoryError.queryFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    /// `name`/`country_code`/`timezone` are expected non-null for every
    /// bundled row, but `sqlite3_column_text` returns a null pointer for a
    /// NULL column regardless of the data's expected shape —
    /// `String(cString:)` traps on that. This data has no checksum guard
    /// the way `quran.sqlite` does, so a corrupted bundle must fail this
    /// load (surfaced by `AppDelegate` as a non-critical "city data
    /// unavailable" alert) rather than crash the app.
    private static func requiredText(_ stmt: OpaquePointer?, _ index: Int32) throws -> String {
        guard sqlite3_column_type(stmt, index) == SQLITE_TEXT,
              let text = sqlite3_column_text(stmt, index)
        else {
            throw LocationRepositoryError.queryFailed("required text column \(index) was not TEXT")
        }
        let value = String(cString: text)
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocationRepositoryError.queryFailed("required text column \(index) was empty")
        }
        return value
    }

    private static func city(from stmt: OpaquePointer?) throws -> City {
        guard sqlite3_column_type(stmt, 0) == SQLITE_INTEGER,
              sqlite3_column_type(stmt, 7) == SQLITE_INTEGER,
              [SQLITE_FLOAT, SQLITE_INTEGER].contains(sqlite3_column_type(stmt, 4)),
              [SQLITE_FLOAT, SQLITE_INTEGER].contains(sqlite3_column_type(stmt, 5))
        else {
            throw LocationRepositoryError.queryFailed("city row contained an invalid numeric column type")
        }
        let id64 = sqlite3_column_int64(stmt, 0)
        let population64 = sqlite3_column_int64(stmt, 7)
        guard let id = Int(exactly: id64), id > 0,
              let population = Int(exactly: population64), population >= 0
        else {
            throw LocationRepositoryError.queryFailed("city id or population was outside the valid range")
        }
        let latitude = sqlite3_column_double(stmt, 4)
        let longitude = sqlite3_column_double(stmt, 5)
        guard latitude.isFinite, (-90...90).contains(latitude),
              longitude.isFinite, (-180...180).contains(longitude)
        else {
            throw LocationRepositoryError.queryFailed("city coordinates were outside the valid range")
        }
        let countryCode = try requiredText(stmt, 3)
        guard countryCode.count == 2,
              countryCode == countryCode.uppercased()
        else {
            throw LocationRepositoryError.queryFailed("city country code was invalid")
        }
        let timeZoneIdentifier = try requiredText(stmt, 6)
        guard TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw LocationRepositoryError.queryFailed("city timezone identifier was invalid")
        }
        let nameArabic: String?
        if sqlite3_column_type(stmt, 2) == SQLITE_NULL {
            nameArabic = nil
        } else {
            nameArabic = try requiredText(stmt, 2)
        }
        return City(
            id: id,
            name: try requiredText(stmt, 1),
            nameArabic: nameArabic,
            countryCode: countryCode,
            coordinates: Coordinates(latitude: latitude, longitude: longitude),
            timeZoneIdentifier: timeZoneIdentifier,
            population: population
        )
    }

    private static func verifyFileChecksum(databasePath: String, checksumPath: String) throws {
        guard let expected = try? String(contentsOfFile: checksumPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !expected.isEmpty
        else {
            throw LocationRepositoryError.cannotReadChecksum(checksumPath)
        }
        guard let data = FileManager.default.contents(atPath: databasePath) else {
            throw LocationRepositoryError.cannotOpenDatabase(databasePath)
        }
        let actual = "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw LocationRepositoryError.checksumMismatch
        }
    }
}
