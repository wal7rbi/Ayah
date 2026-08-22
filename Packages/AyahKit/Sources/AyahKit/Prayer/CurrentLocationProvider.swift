import CoreLocation
import Foundation

public enum LocationProviderError: Error, Sendable {
    case authorizationDenied
    case underlyingFailure(String)
}

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
@MainActor
public protocol LocationProviding: AnyObject {
    func requestOneShotLocation() async throws -> Coordinates
}

@MainActor
public final class CurrentLocationProvider: NSObject, LocationProviding {
    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<Coordinates, Error>?

    public override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
    }

    public func requestOneShotLocation() async throws -> Coordinates {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                continuation.resume(throwing: LocationProviderError.authorizationDenied)
                self.continuation = nil
            default:
                manager.requestLocation()
            }
        }
    }
}

extension CurrentLocationProvider: @MainActor CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            continuation?.resume(throwing: LocationProviderError.authorizationDenied)
            continuation = nil
        default:
            break
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, let continuation else { return }
        continuation.resume(returning: Coordinates(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ))
        self.continuation = nil
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: LocationProviderError.underlyingFailure(error.localizedDescription))
        continuation = nil
    }
}
