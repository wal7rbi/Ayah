import AyahKit
import Combine
import XCTest
@testable import Ayah

@MainActor
final class CurrentLocationViewModelTests: XCTestCase {
    private final class Provider: LocationProviding {
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
        let model = CurrentLocationViewModel(provider: Provider(), settingsStore: store)
        await model.fetchCurrentLocation()
        withExtendedLifetime(subscription) {
            XCTAssertEqual(updates.count, 1)
            XCTAssertEqual(updates.first?.prayerLocationSource, .currentLocation)
            XCTAssertEqual(updates.first?.currentLocationCoordinates?.latitude, 24.68773)
            XCTAssertEqual(updates.first?.currentLocationTimeZoneIdentifier, TimeZone.current.identifier)
            XCTAssertNotNil(updates.first?.currentLocationFetchedAt)
            XCTAssertFalse(model.isFetching)
            XCTAssertNil(model.errorMessage)
        }
    }
}
