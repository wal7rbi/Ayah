import AyahKit
import Combine
import XCTest
@testable import Ayah

@MainActor
final class CurrentLocationViewModelTests: XCTestCase {
    private final class Provider: LocationProviding {
        let measuredAt = Date(timeIntervalSince1970: 1_800_000_000)
        func requestOneShotLocationFix() async throws -> LocationFix {
            LocationFix(coordinates: try await requestOneShotLocation(), measuredAt: measuredAt, horizontalAccuracy: 75)
        }
        func requestOneShotLocation() async throws -> Coordinates {
            Coordinates(latitude: 24.68773, longitude: 46.72185)
        }
    }

    func testSuccessfulFetchPublishesOneCompleteLocationSnapshot() async throws {
        let name = "com.ayah.location-view-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        var updates: [AppSettings] = []
        let subscription = store.$settings.dropFirst().sink { updates.append($0) }
        let provider = Provider()
        let model = CurrentLocationViewModel(provider: provider, settingsStore: store)
        await model.fetchCurrentLocation()
        withExtendedLifetime(subscription) {
            XCTAssertEqual(updates.count, 1)
            XCTAssertEqual(updates.first?.prayerLocationSource, .currentLocation)
            XCTAssertEqual(updates.first?.currentLocationCoordinates?.latitude, 24.68773)
            XCTAssertEqual(updates.first?.currentLocationTimeZoneIdentifier, TimeZone.current.identifier)
            XCTAssertNotNil(updates.first?.currentLocationFetchedAt)
            XCTAssertEqual(updates.first?.currentLocationMeasuredAt, provider.measuredAt)
            XCTAssertEqual(updates.first?.currentLocationHorizontalAccuracy, 75)
            XCTAssertFalse(model.isFetching)
            XCTAssertNil(model.errorMessage)
        }
    }
    private final class StaleProvider: LocationProviding {
        func requestOneShotLocation() async throws -> Coordinates {
            throw LocationProviderError.staleMeasurement
        }
    }

    func testRejectedFixPreservesPreviouslySavedLocation() async throws {
        let name = "com.ayah.location-view-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        var settings = store.settings
        settings.currentLocationCoordinates = Coordinates(latitude: 21, longitude: 39)
        settings.currentLocationMeasuredAt = Date(timeIntervalSince1970: 1234)
        settings.currentLocationHorizontalAccuracy = 50
        store.settings = settings
        let model = CurrentLocationViewModel(provider: StaleProvider(), settingsStore: store)
        await model.fetchCurrentLocation()
        XCTAssertEqual(store.settings, settings)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isFetching)
    }

}
