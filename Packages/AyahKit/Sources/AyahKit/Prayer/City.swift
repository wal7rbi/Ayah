import Foundation

/// A city from the bundled GeoNames subset (ARCHITECTURE.md §12) —
/// what `LocationRepository` looks up and the source of the
/// `Coordinates` a caller hands to `PrayerCalculator`.
///
/// `name` is GeoNames' own primary name field, used as-is: it is not
/// consistently Arabic-script even for Arabic-speaking countries (e.g.
/// Saudi entries are transliterated Latin — "Riyadh", not "الرياض").
/// `nameArabic`, where present, fixes this for display — see
/// `displayName` and `Resources/GeoNames/SOURCE.md` (only ~33% of
/// bundled cities have one; GeoNames' own alternate-name coverage, not
/// an import bug).
public struct City: Codable, Equatable, Sendable, Identifiable {
    /// GeoNames' own `geonameid` — stable across re-imports of the same
    /// upstream dump, so safe to persist (e.g. in a future settings
    /// "selected city" field) across app launches.
    public let id: Int
    public let name: String
    /// `nil` when GeoNames has no Arabic-tagged alternate name for this
    /// city — see `displayName`.
    public let nameArabic: String?
    /// ISO 3166-1 alpha-2, as supplied by GeoNames.
    public let countryCode: String
    public let coordinates: Coordinates
    /// IANA identifier, e.g. "Asia/Riyadh" — usable directly with
    /// `TimeZone(identifier:)`.
    public let timeZoneIdentifier: String
    public let population: Int

    public init(
        id: Int,
        name: String,
        nameArabic: String? = nil,
        countryCode: String,
        coordinates: Coordinates,
        timeZoneIdentifier: String,
        population: Int
    ) {
        self.id = id
        self.name = name
        self.nameArabic = nameArabic
        self.countryCode = countryCode
        self.coordinates = coordinates
        self.timeZoneIdentifier = timeZoneIdentifier
        self.population = population
    }

    /// `nameArabic` when GeoNames has one, else `name` — the single
    /// fallback rule every display site (city picker, Settings popover)
    /// should use rather than each re-implementing `?? name` itself.
    public var displayName: String {
        nameArabic ?? name
    }
}
