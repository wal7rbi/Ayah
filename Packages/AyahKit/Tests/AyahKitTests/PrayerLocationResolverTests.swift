import Foundation
import XCTest
@testable import AyahKit

/// `PrayerLocationResolver` is the single implementation of "which
/// location are prayer times for?", shared by `PrayerAlertScheduler`
/// (when alerts fire) and `PopoverContentView` (what times are shown).
/// These two disagreeing is the failure this type exists to prevent, so
/// every branch of the rule is covered here.
final class PrayerLocationResolverTests: XCTestCase {
    // See PrayerCalculatorTests.swift for why `Coordinates` is constructed
    // inline rather than as a standalone typed property.
    private func makeCity(
        id: Int = 108410,
        timeZoneIdentifier: String = "Asia/Riyadh"
    ) -> City {
        City(
            id: id,
            name: "Riyadh",
            nameArabic: "الرياض",
            countryCode: "SA",
            coordinates: Coordinates(latitude: 24.68773, longitude: 46.72185),
            timeZoneIdentifier: timeZoneIdentifier,
            population: 4_205_961
        )
    }

    // MARK: - City source

    func testCitySourceResolvesTheCityCoordinatesAndItsOwnTimeZone() throws {
        let city = makeCity()
        let settings = AppSettings(selectedCityID: city.id, prayerLocationSource: .city)

        let resolved = try XCTUnwrap(PrayerLocationResolver.resolve(settings: settings, city: city))

        XCTAssertEqual(resolved.coordinates, city.coordinates)
        XCTAssertEqual(resolved.timeZone, TimeZone(identifier: "Asia/Riyadh"))
    }

    /// A `selectedCityID` that isn't in the bundled database — e.g. a
    /// GeoNames id that a later import dropped. Resolving to the Mac's
    /// own zone here would show plausible-looking times for the wrong
    /// place, so this must fail closed.
    func testCitySourceReturnsNilWhenTheSelectedIDIsNotInTheDatabase() throws {
        let repository = try makeBundledRepository()
        let settings = AppSettings(selectedCityID: -1, prayerLocationSource: .city)

        XCTAssertNil(PrayerLocationResolver.resolve(settings: settings, locationRepository: repository))
    }

    func testCitySourceReturnsNilWhenNoCityHasBeenSelected() {
        let settings = AppSettings(selectedCityID: nil, prayerLocationSource: .city)

        XCTAssertNil(PrayerLocationResolver.resolve(settings: settings, city: nil))
    }

    /// `LocationRepository` validates every `timeZoneIdentifier` as it
    /// loads, so this is unreachable through a real repository — it is
    /// covered via the city-taking seam so the guard can't silently rot
    /// into a `TimeZone.current` fallback later.
    func testCitySourceReturnsNilWhenTheCityTimeZoneDoesNotParse() {
        let city = makeCity(timeZoneIdentifier: "Not/AZone")
        let settings = AppSettings(selectedCityID: city.id, prayerLocationSource: .city)

        XCTAssertNil(PrayerLocationResolver.resolve(settings: settings, city: city))
    }

    /// The `.city` branch must not fall through to a cached one-shot fix
    /// that happens to still be stored from an earlier opt-in.
    func testCitySourceIgnoresCachedCurrentLocationCoordinates() {
        let settings = AppSettings(
            selectedCityID: nil,
            prayerLocationSource: .city,
            currentLocationCoordinates: Coordinates(latitude: 51.5, longitude: -0.12),
            currentLocationTimeZoneIdentifier: "Europe/London"
        )

        XCTAssertNil(PrayerLocationResolver.resolve(settings: settings, city: nil))
    }

    // MARK: - Current-location source

    func testCurrentLocationSourceResolvesCachedCoordinatesAndCapturedZone() throws {
        let settings = AppSettings(
            prayerLocationSource: .currentLocation,
            currentLocationCoordinates: Coordinates(latitude: 51.5, longitude: -0.12),
            currentLocationTimeZoneIdentifier: "Europe/London"
        )

        let resolved = try XCTUnwrap(PrayerLocationResolver.resolve(settings: settings, city: nil))

        XCTAssertEqual(resolved.coordinates.latitude, 51.5, accuracy: 0.0001)
        XCTAssertEqual(resolved.coordinates.longitude, -0.12, accuracy: 0.0001)
        XCTAssertEqual(resolved.timeZone, TimeZone(identifier: "Europe/London"))
    }

    func testCurrentLocationSourceReturnsNilWithNoCachedFix() {
        let settings = AppSettings(
            prayerLocationSource: .currentLocation,
            currentLocationCoordinates: nil
        )

        XCTAssertNil(PrayerLocationResolver.resolve(settings: settings, city: nil))
    }

    /// A fix cached before the zone was captured alongside it. The Mac's
    /// own zone is the correct fallback *here specifically*, because
    /// these coordinates came from this Mac in the first place — unlike
    /// the city branch, where the system zone is unrelated to the
    /// selected city.
    func testCurrentLocationSourceFallsBackToTheSystemZoneWhenNoneWasCaptured() throws {
        let settings = AppSettings(
            prayerLocationSource: .currentLocation,
            currentLocationCoordinates: Coordinates(latitude: 21.42, longitude: 39.83),
            currentLocationTimeZoneIdentifier: nil
        )

        let resolved = try XCTUnwrap(PrayerLocationResolver.resolve(settings: settings, city: nil))

        XCTAssertEqual(resolved.timeZone.identifier, TimeZone.current.identifier)
    }

    /// The `.currentLocation` branch must not fall through to a city the
    /// user picked before switching sources.
    func testCurrentLocationSourceIgnoresTheSelectedCity() {
        let city = makeCity()
        let settings = AppSettings(
            selectedCityID: city.id,
            prayerLocationSource: .currentLocation,
            currentLocationCoordinates: nil
        )

        XCTAssertNil(PrayerLocationResolver.resolve(settings: settings, city: city))
    }

    // MARK: - Repository-backed path

    /// The `locationRepository:` overload is the one the app actually
    /// calls; this proves it reaches the same result as the seam above
    /// when given a real bundled city.
    func testRepositoryOverloadResolvesABundledCity() throws {
        let repository = try makeBundledRepository()
        let riyadh = try XCTUnwrap(repository.cities().first { $0.name == "Riyadh" && $0.countryCode == "SA" })
        let settings = AppSettings(selectedCityID: riyadh.id, prayerLocationSource: .city)

        let resolved = try XCTUnwrap(
            PrayerLocationResolver.resolve(settings: settings, locationRepository: repository)
        )

        XCTAssertEqual(resolved.coordinates, riyadh.coordinates)
        XCTAssertEqual(resolved.timeZone.identifier, riyadh.timeZoneIdentifier)
    }

    func testRepositoryOverloadReturnsNilWithNoRepository() {
        let settings = AppSettings(selectedCityID: 108410, prayerLocationSource: .city)

        XCTAssertNil(PrayerLocationResolver.resolve(settings: settings, locationRepository: nil))
    }

    /// See `LocationRepositoryTests.geoNamesResourcesDir` for why this is
    /// resolved via `#filePath` rather than an SPM package resource.
    private func makeBundledRepository() throws -> LocationRepository {
        let dbPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/GeoNames/cities_filtered.sqlite")
            .path
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw XCTSkip("cities_filtered.sqlite not found at \(dbPath) — run Scripts/import_geonames first")
        }
        return try LocationRepository(databasePath: dbPath)
    }
}
