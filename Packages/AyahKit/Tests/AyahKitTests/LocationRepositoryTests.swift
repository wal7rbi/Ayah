import Foundation
import XCTest
@testable import AyahKit

final class LocationRepositoryTests: XCTestCase {
    /// See `QuranRepositoryTests.quranResourcesDir` for why this is
    /// resolved via `#filePath` rather than an SPM package resource.
    private static var geoNamesResourcesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/GeoNames")
    }

    private func makeRepository() throws -> LocationRepository {
        let dbPath = Self.geoNamesResourcesDir.appendingPathComponent("cities_filtered.sqlite").path
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw XCTSkip("cities_filtered.sqlite not found at \(dbPath) — run Scripts/import_geonames first")
        }
        return try LocationRepository(databasePath: dbPath)
    }

    func testInitSucceedsAgainstBundledData() throws {
        let dir = Self.geoNamesResourcesDir
        _ = try LocationRepository(
            databasePath: dir.appendingPathComponent("cities_filtered.sqlite").path,
            checksumPath: dir.appendingPathComponent("GEONAMES_CHECKSUM").path
        )
    }

    func testInitFailsWithWrongChecksum() throws {
        let dir = Self.geoNamesResourcesDir
        let checksum = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "sha256:0000000000000000000000000000000000000000000000000000000000000000"
            .write(to: checksum, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: checksum) }
        XCTAssertThrowsError(try LocationRepository(
            databasePath: dir.appendingPathComponent("cities_filtered.sqlite").path,
            checksumPath: checksum.path
        )) { error in
            guard case LocationRepositoryError.checksumMismatch = error else {
                return XCTFail("expected .checksumMismatch, got \(error)")
            }
        }
    }

    func testCitiesReturnsANonEmptyOrderedByPopulationDescending() throws {
        let repository = try makeRepository()
        let cities = repository.cities()
        XCTAssertFalse(cities.isEmpty)
        for i in 1..<cities.count {
            XCTAssertGreaterThanOrEqual(cities[i - 1].population, cities[i].population)
        }
    }

    func testRiyadhIsFoundWithCorrectCoordinatesAndTimezone() throws {
        let repository = try makeRepository()
        let riyadh = try XCTUnwrap(repository.cities().first { $0.name == "Riyadh" && $0.countryCode == "SA" })
        XCTAssertEqual(riyadh.coordinates.latitude, 24.68773, accuracy: 0.01)
        XCTAssertEqual(riyadh.coordinates.longitude, 46.72185, accuracy: 0.01)
        XCTAssertEqual(riyadh.timeZoneIdentifier, "Asia/Riyadh")
        XCTAssertEqual(repository.city(id: riyadh.id), riyadh)
    }

    /// ARCHITECTURE.md §12 / `City.displayName`: GeoNames' alternate-names
    /// dump tags a proper Arabic name for a majority-but-not-all subset of
    /// bundled cities (see `Resources/GeoNames/SOURCE.md` for the exact
    /// count) — Riyadh is one of the ones that has it.
    func testRiyadhHasAnArabicNameAndDisplayNamePrefersIt() throws {
        let repository = try makeRepository()
        let riyadh = try XCTUnwrap(repository.cities().first { $0.name == "Riyadh" && $0.countryCode == "SA" })
        XCTAssertEqual(riyadh.nameArabic, "الرياض")
        XCTAssertEqual(riyadh.displayName, "الرياض")
    }

    func testDisplayNameFallsBackToNameWhenNoArabicNameIsBundled() {
        let city = City(
            id: 1, name: "Example", nameArabic: nil, countryCode: "XX",
            coordinates: Coordinates(latitude: 0, longitude: 0),
            timeZoneIdentifier: "UTC", population: 0
        )
        XCTAssertEqual(city.displayName, "Example")
    }

    func testCityLookupByUnknownIDReturnsNil() throws {
        let repository = try makeRepository()
        XCTAssertNil(repository.city(id: -1))
    }

    /// Regression test: `loadAllCities` used to force-convert `name`/
    /// `country_code`/`timezone` straight into `String(cString:)`, which
    /// traps on a NULL column. This bundled data has no checksum guard the
    /// way `quran.sqlite` does, so a corrupted bundle violating its own
    /// `NOT NULL` schema must fail `init` with a catchable error, not crash.
    func testInitFailsOnACorruptedRowInsteadOfCrashing() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("cities_filtered.sqlite")
        let seedConnection = try SQLiteConnection(path: dbURL.path)
        // Same shape as the real schema but without the NOT NULL
        // constraints, so a NULL can actually be inserted (a real
        // NOT NULL column would reject this insert outright).
        try seedConnection.execute("""
            CREATE TABLE cities (
              geoname_id    INTEGER PRIMARY KEY,
              name          TEXT,
              name_arabic   TEXT,
              country_code  TEXT,
              latitude      REAL,
              longitude     REAL,
              timezone      TEXT,
              population    INTEGER
            );
            """)
        try seedConnection.execute("""
            INSERT INTO cities
              (geoname_id, name, name_arabic, country_code, latitude, longitude, timezone, population)
            VALUES (1, NULL, NULL, 'SA', 24.0, 46.0, 'Asia/Riyadh', 100);
            """)

        XCTAssertThrowsError(try LocationRepository(databasePath: dbURL.path)) { error in
            guard case LocationRepositoryError.queryFailed = error else {
                return XCTFail("expected .queryFailed, got \(error)")
            }
        }
    }

    func testInitRejectsInvalidCoordinatesAndTimezone() throws {
        for invalidValues in [
            "91.0, 46.0, 'Asia/Riyadh'",
            "24.0, 181.0, 'Asia/Riyadh'",
            "24.0, 46.0, 'Not/A_Time_Zone'"
        ] {
            let dbURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent("cities_filtered.sqlite")
            let connection = try SQLiteConnection(path: dbURL.path)
            try connection.execute("""
                CREATE TABLE cities (
                  geoname_id INTEGER, name TEXT, name_arabic TEXT, country_code TEXT,
                  latitude REAL, longitude REAL, timezone TEXT, population INTEGER
                );
                INSERT INTO cities VALUES (1, 'Example', NULL, 'SA', \(invalidValues), 100);
                """)
            XCTAssertThrowsError(try LocationRepository(databasePath: dbURL.path))
        }
    }

    func testAllCitiesBelongToTheDocumentedMuslimMajorityCountrySet() throws {
        // Not an exhaustive re-check of the country list (that's
        // Scripts/import_geonames' job) — a coarse sanity check that the
        // bundled data wasn't accidentally regenerated against the wrong
        // filter (e.g. the full unfiltered world dump).
        let repository = try makeRepository()
        let countryCodes = Set(repository.cities().map(\.countryCode))
        XCTAssertTrue(countryCodes.contains("SA"))
        XCTAssertLessThan(countryCodes.count, 60)
    }
}
