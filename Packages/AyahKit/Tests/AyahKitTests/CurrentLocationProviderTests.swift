import CoreLocation
import Foundation
import XCTest
@testable import AyahKit

@MainActor
final class CurrentLocationProviderTests: XCTestCase {
    private final class FakeLocationManager: CLLocationManagerProviding {
        weak var delegate: CLLocationManagerDelegate?
        var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
        private(set) var requestLocationCallCount = 0
        private(set) var requestWhenInUseAuthorizationCallCount = 0

        func requestWhenInUseAuthorization() {
            requestWhenInUseAuthorizationCallCount += 1
        }

        func requestLocation() {
            requestLocationCallCount += 1
        }
    }

    /// Regression test for the leaked-continuation bug: calling
    /// `requestOneShotLocation()` again while one is already in flight
    /// used to silently overwrite `continuation`, abandoning the first
    /// caller's `Task` forever. It must now fail fast instead.
    func testSecondConcurrentRequestFailsInsteadOfLeakingTheFirst() async throws {
        let manager = FakeLocationManager()
        let provider = CurrentLocationProvider(manager: manager)

        let firstRequest = Task { try await provider.requestOneShotLocation() }
        await Task.yield()

        do {
            _ = try await provider.requestOneShotLocation()
            XCTFail("a second concurrent request should have thrown, not started a new fetch")
        } catch LocationProviderError.requestAlreadyInProgress {
            // expected
        }

        // The first request must still be alive and resolvable — proving
        // it was never silently dropped by the second call.
        provider.locationManager(
            CLLocationManager(),
            didUpdateLocations: [CLLocation(latitude: 24.7136, longitude: 46.6753)]
        )

        let coordinates = try await firstRequest.value
        XCTAssertEqual(coordinates.latitude, 24.7136, accuracy: 0.0001)
        XCTAssertEqual(coordinates.longitude, 46.6753, accuracy: 0.0001)
        XCTAssertEqual(manager.requestLocationCallCount, 1)
    }

    func testRequestSucceedsAgainAfterThePreviousOneCompletes() async throws {
        let manager = FakeLocationManager()
        let provider = CurrentLocationProvider(manager: manager)

        let firstRequest = Task { try await provider.requestOneShotLocation() }
        await Task.yield()
        provider.locationManager(
            CLLocationManager(),
            didUpdateLocations: [CLLocation(latitude: 21.3891, longitude: 39.8579)]
        )
        _ = try await firstRequest.value

        let secondRequest = Task { try await provider.requestOneShotLocation() }
        await Task.yield()
        provider.locationManager(
            CLLocationManager(),
            didUpdateLocations: [CLLocation(latitude: 21.4225, longitude: 39.8262)]
        )
        let coordinates = try await secondRequest.value

        XCTAssertEqual(coordinates.latitude, 21.4225, accuracy: 0.0001)
        XCTAssertEqual(manager.requestLocationCallCount, 2)
    }

    func testDeniedAuthorizationClearsContinuationSoARetryCanRunLater() async throws {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .denied
        let provider = CurrentLocationProvider(manager: manager)

        do {
            _ = try await provider.requestOneShotLocation()
            XCTFail("denied authorization should throw")
        } catch LocationProviderError.authorizationDenied {
            // expected
        }

        // Continuation must have been cleared on denial, not left set —
        // otherwise every future call would incorrectly see one "in
        // progress" and throw `requestAlreadyInProgress` forever.
        do {
            _ = try await provider.requestOneShotLocation()
            XCTFail("denied authorization should throw again on retry")
        } catch LocationProviderError.authorizationDenied {
            // expected — not .requestAlreadyInProgress
        }
    }

    func testRestrictedAuthorizationFailsWithoutRequestingLocation() async {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .restricted
        let provider = CurrentLocationProvider(manager: manager)

        do {
            _ = try await provider.requestOneShotLocation()
            XCTFail("restricted authorization should throw")
        } catch LocationProviderError.authorizationDenied {
            XCTAssertEqual(manager.requestLocationCallCount, 0)
        } catch {
            XCTFail("expected authorizationDenied, got \(error)")
        }
    }

    func testAuthorizationCallbackWithoutPendingUserRequestDoesNotAccessLocation() {
        let manager = FakeLocationManager()
        let provider = CurrentLocationProvider(manager: manager)

        provider.locationManagerDidChangeAuthorization(CLLocationManager())

        XCTAssertEqual(manager.requestLocationCallCount, 0)
    }

    func testRepeatedAuthorizationCallbacksRequestLocationOnlyOnceForPendingRequest() async throws {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .notDetermined
        let provider = CurrentLocationProvider(manager: manager)
        let request = Task { try await provider.requestOneShotLocation() }
        await Task.yield()

        manager.authorizationStatus = .authorizedAlways
        provider.locationManagerDidChangeAuthorization(CLLocationManager())
        provider.locationManagerDidChangeAuthorization(CLLocationManager())
        XCTAssertEqual(manager.requestLocationCallCount, 1)

        provider.locationManager(
            CLLocationManager(),
            didUpdateLocations: [CLLocation(latitude: 24.7136, longitude: 46.6753)]
        )
        _ = try await request.value
    }

    func testCancellationResumesPendingRequest() async {
        let manager = FakeLocationManager()
        let provider = CurrentLocationProvider(manager: manager)
        let request = Task { try await provider.requestOneShotLocation() }
        await Task.yield()

        request.cancel()

        do {
            _ = try await request.value
            XCTFail("a canceled request should throw")
        } catch LocationProviderError.requestCancelled {
            // expected
        } catch {
            XCTFail("expected requestCancelled, got \(error)")
        }
    }

    func testAuthorizedRequestTimesOutInsteadOfHangingForever() async {
        let manager = FakeLocationManager()
        let provider = CurrentLocationProvider(manager: manager, timeoutNanoseconds: 10_000_000)

        do {
            _ = try await provider.requestOneShotLocation()
            XCTFail("a request with no delegate result should time out")
        } catch LocationProviderError.requestTimedOut {
            // expected
        } catch {
            XCTFail("expected requestTimedOut, got \(error)")
        }
    }

    func testInvalidCoordinatesFailWithoutBeingReturned() async {
        let manager = FakeLocationManager()
        let provider = CurrentLocationProvider(manager: manager)
        let request = Task { try await provider.requestOneShotLocation() }
        await Task.yield()
        provider.locationManager(
            CLLocationManager(),
            didUpdateLocations: [CLLocation(latitude: 91, longitude: 46)]
        )

        do {
            _ = try await request.value
            XCTFail("invalid coordinates should throw")
        } catch LocationProviderError.invalidCoordinates {
            // expected
        } catch {
            XCTFail("expected invalidCoordinates, got \(error)")
        }
    }

    func testManagerFailureResumesPendingRequestAndAllowsRetry() async throws {
        let manager = FakeLocationManager()
        let provider = CurrentLocationProvider(manager: manager)
        let request = Task { try await provider.requestOneShotLocation() }
        await Task.yield()
        let managerError = NSError(domain: "CurrentLocationProviderTests", code: 17)
        provider.locationManager(CLLocationManager(), didFailWithError: managerError)

        do {
            _ = try await request.value
            XCTFail("manager failure should throw")
        } catch LocationProviderError.underlyingFailure(let message) {
            XCTAssertEqual(message, managerError.localizedDescription)
        } catch {
            XCTFail("expected underlyingFailure, got \(error)")
        }

        let retry = Task { try await provider.requestOneShotLocation() }
        await Task.yield()
        provider.locationManager(
            CLLocationManager(),
            didUpdateLocations: [CLLocation(latitude: 24.7136, longitude: 46.6753)]
        )
        _ = try await retry.value
    }
    func testMeasurementMetadataIsPreserved() async throws {
        let measuredAt = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = CurrentLocationProvider(manager: FakeLocationManager(), now: { measuredAt.addingTimeInterval(20) })
        let request = Task { try await provider.requestOneShotLocationFix() }
        await Task.yield()
        provider.locationManager(CLLocationManager(), didUpdateLocations: [
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 24, longitude: 46), altitude: 0,
                       horizontalAccuracy: 120, verticalAccuracy: -1, timestamp: measuredAt)
        ])
        let fix = try await request.value
        XCTAssertEqual(fix.measuredAt, measuredAt)
        XCTAssertEqual(fix.horizontalAccuracy, 120)
    }

    func testOldFutureAndInaccurateFixesAreRejected() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for (age, accuracy, expected) in [
            (301.0, 100.0, LocationProviderError.staleMeasurement),
            (-61.0, 100.0, .staleMeasurement),
            (0.0, -1.0, .inaccurateMeasurement),
            (0.0, 5001.0, .inaccurateMeasurement)
        ] {
            let provider = CurrentLocationProvider(manager: FakeLocationManager(), now: { now })
            let request = Task { try await provider.requestOneShotLocationFix() }
            await Task.yield()
            provider.locationManager(CLLocationManager(), didUpdateLocations: [
                CLLocation(coordinate: CLLocationCoordinate2D(latitude: 24, longitude: 46), altitude: 0,
                           horizontalAccuracy: accuracy, verticalAccuracy: -1,
                           timestamp: now.addingTimeInterval(-age))
            ])
            do {
                _ = try await request.value
                XCTFail("unusable fix must not be accepted")
            } catch {
                XCTAssertEqual(error as? LocationProviderError, expected)
            }
        }
    }

    func testWaitingForPermissionAlsoTimesOut() async {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .notDetermined
        let provider = CurrentLocationProvider(manager: manager, authorizationTimeoutNanoseconds: 10_000_000)
        do {
            _ = try await provider.requestOneShotLocationFix()
            XCTFail("permission request must be bounded")
        } catch {
            XCTAssertEqual(error as? LocationProviderError, .requestTimedOut)
        }
        XCTAssertEqual(manager.requestLocationCallCount, 0)
    }

    /// The short fix timeout must not cut off someone still reading the
    /// permission dialog, and must start fresh once permission is granted.
    func testPermissionWaitUsesItsOwnTimeoutThenFixTimeoutStartsFresh() async throws {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .notDetermined
        let provider = CurrentLocationProvider(manager: manager, timeoutNanoseconds: 20_000_000,
                                               authorizationTimeoutNanoseconds: 60_000_000_000)
        var result: Result<LocationFix, Error>?
        let request = Task { @MainActor in
            do { result = .success(try await provider.requestOneShotLocationFix()) } catch { result = .failure(error) }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(result, "still waiting on the permission dialog after the fix timeout elapsed")

        manager.authorizationStatus = .authorizedAlways
        provider.locationManagerDidChangeAuthorization(CLLocationManager())
        XCTAssertEqual(manager.requestLocationCallCount, 1)
        await request.value
        guard case .failure(let error)? = result else { return XCTFail("expected the fix to time out") }
        XCTAssertEqual(error as? LocationProviderError, .requestTimedOut)
    }

    func testBatchUsesFreshValidMeasurementInsteadOfLastStaleFix() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = CurrentLocationProvider(manager: FakeLocationManager(), now: { now })
        let request = Task { try await provider.requestOneShotLocationFix() }
        await Task.yield()
        let fresh = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 24, longitude: 46), altitude: 0,
                               horizontalAccuracy: 25, verticalAccuracy: -1, timestamp: now)
        let stale = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 21, longitude: 39), altitude: 0,
                               horizontalAccuracy: 25, verticalAccuracy: -1,
                               timestamp: now.addingTimeInterval(-600))
        provider.locationManager(CLLocationManager(), didUpdateLocations: [fresh, stale])
        let fix = try await request.value
        XCTAssertEqual(fix.coordinates.latitude, 24)
        XCTAssertEqual(fix.measuredAt, now)
    }

}
