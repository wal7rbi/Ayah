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
        _ = try makeRepository()
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
