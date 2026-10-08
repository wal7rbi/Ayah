import CoreLocation
import Foundation
import XCTest
@testable import AyahKit

@MainActor
final class ReviewProbeTests: XCTestCase {
    final class Manager: CLLocationManagerProviding {
        weak var delegate: CLLocationManagerDelegate?
        var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
        var requested = false
        func requestWhenInUseAuthorization() {}
        func requestLocation() { requested = true }
    }
    func testOldInvalidAccuracyLocationIsAccepted() async throws {
        let manager = Manager()
        let provider = CurrentLocationProvider(manager: manager)
        let request = Task { try await provider.requestOneShotLocation() }
        while !manager.requested { await Task.yield() }
        let old = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 24.7, longitude: 46.7), altitude: 0, horizontalAccuracy: -1, verticalAccuracy: -1, timestamp: Date(timeIntervalSince1970: 0))
        provider.locationManager(CLLocationManager(), didUpdateLocations: [old])
        let result = try await request.value
        XCTAssertEqual(result.latitude, 24.7)
        print("REVIEW CONFIRMED: a 1970 location with negative horizontal accuracy is accepted")
    }
    func testPolarSummerHasNoPrayerEvents() {
        let date = ISO8601DateFormatter().date(from: "2026-06-21T12:00:00Z")!
        let events = PrayerAlertScheduler.prayerAlertEvents(for: date, coordinates: Coordinates(latitude: 69.6492, longitude: 18.9553), calculationMethod: .ummAlQura, asrMadhab: .shafi, reminderMinutes: 5, timeZone: TimeZone(identifier: "Europe/Oslo")!, now: date)
        XCTAssertTrue(events.isEmpty)
        print("REVIEW CONFIRMED: Tromso midsummer produces no prayer events")
    }
}
