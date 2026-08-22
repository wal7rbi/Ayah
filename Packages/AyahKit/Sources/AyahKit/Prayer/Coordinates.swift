import Foundation

/// A geographic coordinate pair. Kept as Ayah's own type rather than
/// re-exporting Adhan Swift's `Coordinates` (ARCHITECTURE.md §2 lists
/// this as its own file) so `City`/`LocationRepository` don't need to
/// import Adhan just to carry a lat/lon — only `PrayerCalculator` talks
/// to Adhan directly.
public struct Coordinates: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
