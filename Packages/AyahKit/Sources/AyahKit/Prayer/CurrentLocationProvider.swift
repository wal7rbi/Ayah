import CoreLocation
import Foundation

public enum LocationProviderError: Error, Sendable, Equatable {
    case authorizationDenied
    case underlyingFailure(String)
    case requestAlreadyInProgress
    case requestCancelled
    case requestTimedOut
    case invalidCoordinates
    case staleMeasurement
    case inaccurateMeasurement
}

/// The slice of `CLLocationManager` `CurrentLocationProvider` actually
/// calls, abstracted so tests can drive the one-shot-request flow with a
/// fake instead of a real `CLLocationManager` (whose `authorizationStatus`
/// and permission-prompt behavior are environment-dependent and not safe
/// to exercise from a `swift test` process — mirrors the fake-shape
/// `LocationProviding` already gives *consumers* of this provider, one
/// level deeper).
protocol CLLocationManagerProviding: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorization()
    func requestLocation()
}

extension CLLocationManager: CLLocationManagerProviding {}

/// A single on-demand location fix — the "Location Services ... explicit,
/// opt-in convenience feature" ARCHITECTURE.md §12 deferred. Deliberately
/// one-shot rather than a continuous subscription: matches §18's
/// no-continuous-background-work priority, and matches the rest of the
/// app's "fetch once, cache in `AppSettings`, let the user refresh
/// manually" pattern (`CurrentLocationViewModel` in the App target owns
/// the caching/caller side of that).
///
/// Note this does not make location resolution itself offline: Macs have
/// no GPS chip, so `CLLocationManager` resolves position via nearby Wi-Fi
/// access points through macOS's own `locationd`, which can involve
/// network traffic outside Ayah's sandboxed process entirely. Ayah's own
/// entitlements never gain `network.client` — see
/// `com.apple.security.personal-information.location` in
/// `Ayah.entitlements` versus the sandbox's network keys — but this
/// distinction is real and must stay disclosed in the UI that calls this,
/// not silently glossed over as "fully offline" the way the bundled
/// GeoNames city picker is.
/// Metadata is optional only for legacy coordinate-only providers. Core Location
/// always returns its original measurement time and horizontal accuracy.
public struct LocationFix: Sendable, Equatable {
    public let coordinates: Coordinates
    public let measuredAt: Date?
    public let horizontalAccuracy: Double?

    public init(coordinates: Coordinates, measuredAt: Date? = nil, horizontalAccuracy: Double? = nil) {
        self.coordinates = coordinates
        self.measuredAt = measuredAt
        self.horizontalAccuracy = horizontalAccuracy
    }
}

@MainActor
public protocol LocationProviding: AnyObject {
    func requestOneShotLocation() async throws -> Coordinates
    func requestOneShotLocationFix() async throws -> LocationFix
}

public extension LocationProviding {
    func requestOneShotLocationFix() async throws -> LocationFix {
        LocationFix(coordinates: try await requestOneShotLocation())
    }
}

@MainActor
public final class CurrentLocationProvider: NSObject, LocationProviding {
    private let manager: CLLocationManagerProviding
    private let now: () -> Date
    private let timeoutNanoseconds: UInt64
    /// A person reading the permission dialog needs longer than a GPS fix does.
    private let authorizationTimeoutNanoseconds: UInt64
    private var continuation: CheckedContinuation<LocationFix, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var isRequestingLocation = false

    public override init() {
        now = Date.init
        manager = CLLocationManager()
        timeoutNanoseconds = 30_000_000_000
        authorizationTimeoutNanoseconds = 120_000_000_000
        super.init()
        manager.delegate = self
    }

    init(manager: CLLocationManagerProviding, timeoutNanoseconds: UInt64 = 30_000_000_000,
         authorizationTimeoutNanoseconds: UInt64 = 120_000_000_000, now: @escaping () -> Date = Date.init) {
        self.now = now
        self.manager = manager
        self.timeoutNanoseconds = timeoutNanoseconds
        self.authorizationTimeoutNanoseconds = authorizationTimeoutNanoseconds
        super.init()
        manager.delegate = self
    }

    public func requestOneShotLocation() async throws -> Coordinates {
        try await requestOneShotLocationFix().coordinates
    }

    public func requestOneShotLocationFix() async throws -> LocationFix {
        guard continuation == nil else {
            throw LocationProviderError.requestAlreadyInProgress
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                if Task.isCancelled {
                    finish(.failure(LocationProviderError.requestCancelled))
                    return
                }
                switch manager.authorizationStatus {
                case .notDetermined:
                    startTimeout(authorizationTimeoutNanoseconds)
                    manager.requestWhenInUseAuthorization()
                case .denied, .restricted:
                    finish(.failure(LocationProviderError.authorizationDenied))
                case .authorizedAlways, .authorizedWhenInUse:
                    beginLocationRequestIfPending()
                @unknown default:
                    finish(.failure(LocationProviderError.authorizationDenied))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(LocationProviderError.requestCancelled))
            }
        }
    }

    private func beginLocationRequestIfPending() {
        guard continuation != nil, !isRequestingLocation else { return }
        isRequestingLocation = true
        startTimeout(timeoutNanoseconds)
        manager.requestLocation()
    }

    /// Replaces any running timeout, so granting permission restarts the clock for the fix.
    private func startTimeout(_ nanoseconds: UInt64) {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            finish(.failure(LocationProviderError.requestTimedOut))
        }
    }

    private func finish(_ result: Result<LocationFix, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        isRequestingLocation = false
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(with: result)
    }
}

// Xcode 16's CoreLocation overlay still declares these delegate requirements
// as nonisolated, while newer SDKs carry actor annotations. `@preconcurrency`
// preserves this class's main-actor isolation and defers the older overlay's
// protocol-isolation check to runtime, where CLLocationManager delivers its
// delegate callbacks on the manager's run loop.
extension CurrentLocationProvider: @preconcurrency CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch self.manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            // Core Location calls this delegate method when a manager is
            // created and whenever authorization changes. Authorization is
            // capability, not user intent: only a still-pending explicit
            // request may start location access.
            beginLocationRequestIfPending()
        case .denied, .restricted:
            finish(.failure(LocationProviderError.authorizationDenied))
        default:
            break
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard continuation != nil, !locations.isEmpty else { return }
        let referenceNow = now()
        let location = locations.sorted { $0.timestamp > $1.timestamp }.first { location in
            let age = referenceNow.timeIntervalSince(location.timestamp)
            return age >= -60 && age <= 300
                && location.horizontalAccuracy.isFinite
                && (0...5000).contains(location.horizontalAccuracy)
                && CLLocationCoordinate2DIsValid(location.coordinate)
        } ?? locations[locations.count - 1]
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            finish(.failure(LocationProviderError.invalidCoordinates))
            return
        }
        let age = referenceNow.timeIntervalSince(location.timestamp)
        guard age.isFinite, age >= -60, age <= 300 else {
            finish(.failure(LocationProviderError.staleMeasurement))
            return
        }
        guard location.horizontalAccuracy.isFinite,
              (0...5000).contains(location.horizontalAccuracy) else {
            finish(.failure(LocationProviderError.inaccurateMeasurement))
            return
        }
        finish(.success(LocationFix(
            coordinates: Coordinates(latitude: latitude, longitude: longitude),
            measuredAt: location.timestamp, horizontalAccuracy: location.horizontalAccuracy
        )))
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(LocationProviderError.underlyingFailure(error.localizedDescription)))
    }
}
