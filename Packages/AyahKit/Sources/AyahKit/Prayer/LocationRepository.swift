import Foundation
import SQLite3

public enum LocationRepositoryError: Error, Sendable {
    case cannotOpenDatabase(String)
    case queryFailed(String)
}

/// Read-only access to the bundled GeoNames subset
/// (`Resources/GeoNames/cities_filtered.sqlite`, ARCHITECTURE.md §12).
/// Mirrors `QuranRepository`'s raw-SQLite pattern rather than
/// `Persistence/SQLiteConnection`: this is immutable, bundled, read-only
/// data like `quran.sqlite`, not app-owned mutable state — it just
/// doesn't carry Quran data's checksum ceremony (§8), since city lookup
/// isn't the app's #1 correctness priority the way Quran text is.
public final class LocationRepository {
    private let db: OpaquePointer?
    private let cachedCities: [City]

    private static let cityColumns =
        "geoname_id, name, name_arabic, country_code, latitude, longitude, timezone, population"

    public init(databasePath: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            throw LocationRepositoryError.cannotOpenDatabase(message)
        }
        self.db = handle
        self.cachedCities = try Self.loadAllCities(db: handle)
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
        while sqlite3_step(stmt) == SQLITE_ROW {
            let nameArabic = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            results.append(City(
                id: Int(sqlite3_column_int(stmt, 0)),
                name: String(cString: sqlite3_column_text(stmt, 1)),
                nameArabic: nameArabic,
                countryCode: String(cString: sqlite3_column_text(stmt, 3)),
                coordinates: Coordinates(
                    latitude: sqlite3_column_double(stmt, 4),
                    longitude: sqlite3_column_double(stmt, 5)
                ),
                timeZoneIdentifier: String(cString: sqlite3_column_text(stmt, 6)),
                population: Int(sqlite3_column_int(stmt, 7))
            ))
        }
        return results
    }
}
