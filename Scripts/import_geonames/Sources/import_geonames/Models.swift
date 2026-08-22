import Foundation

struct CityRecord {
    let geonameID: Int
    let name: String
    /// GeoNames' `alternateNamesV2` dump, `isolanguage == "ar"` rows only
    /// — `nil` when GeoNames has no Arabic-tagged alternate name for this
    /// city (see `ArabicNames.swift`). Not every Arabic-speaking-country
    /// city has one; this reduces the "names aren't Arabic" gap, it
    /// doesn't close it entirely.
    let nameArabic: String?
    let countryCode: String
    let latitude: Double
    let longitude: Double
    let timezone: String
    let population: Int
}
