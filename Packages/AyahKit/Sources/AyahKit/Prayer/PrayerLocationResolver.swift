import Foundation

/// Where prayer times are calculated for: the coordinates *and* the
/// timezone those coordinates' calendar day must be read in.
///
/// The two travel together deliberately. `PrayerCalculator.prayerTimes`
/// needs year/month/day as experienced at the target location, not in the
/// Mac's own zone (ARCHITECTURE.md §9's "Update"), so a caller holding
/// only coordinates has half of what it needs and no way to know it.
///
/// A named struct rather than a tuple because `PopoverContentView`
/// imports both `Adhan` and `AyahKit`, where the bare name `Coordinates`
/// is ambiguous and cannot be module-qualified (`AyahKit.swift`'s marker
/// enum shadows the module name — see the Architecture section of
/// CLAUDE.md). A computed property needs an explicit type annotation, so
/// a tuple return would force that file to spell the ambiguous name.
/// `ResolvedPrayerLocation` exists in one module only, so it is always
/// spellable, and `.coordinates` is reached through it without ever
/// naming the ambiguous type.
public struct ResolvedPrayerLocation: Equatable, Sendable {
    public let coordinates: Coordinates
    public let timeZone: TimeZone

    public init(coordinates: Coordinates, timeZone: TimeZone) {
        self.coordinates = coordinates
        self.timeZone = timeZone
    }
}

/// The single implementation of "which location are prayer times for?".
///
/// This rule was previously written twice — once in
/// `PrayerAlertScheduler` (deciding when alerts fire) and once in
/// `PopoverContentView` (deciding what times the user is shown). Those
/// two must agree: when they disagree the popover shows one set of times
/// and the notch fires at another. That is not hypothetical — the
/// wrong-day timezone bug found in the 2026-08-23 audit lived in exactly
/// this logic and had to be fixed in both copies independently.
///
/// Pure and synchronous, taking `AppSettings` by value rather than a
/// `SettingsStore`, so it is testable with no Combine or persistence
/// involved — the same split `VerseScheduler.selectNextVerses` and
/// `PrayerAlertScheduler.prayerAlertEvents` already use.
public enum PrayerLocationResolver {
    public static func resolve(
        settings: AppSettings,
        locationRepository: LocationRepository?
    ) -> ResolvedPrayerLocation? {
        resolve(
            settings: settings,
            city: settings.selectedCityID.flatMap { locationRepository?.city(id: $0) }
        )
    }

    /// The lookup-free core, taking the already-resolved city.
    /// `@autoclosure` keeps `LocationRepository.city(id:)`'s linear scan
    /// of the bundled ~4,650-city cache behind the `.city` branch, as it
    /// was before this type existed.
    ///
    /// Also the seam the unparseable-timezone test needs:
    /// `LocationRepository` rejects an invalid `timeZoneIdentifier` when
    /// it loads the database, so no real repository can hand this
    /// function such a city, and the guard below would otherwise be
    /// untestable.
    static func resolve(
        settings: AppSettings,
        city: @autoclosure () -> City?
    ) -> ResolvedPrayerLocation? {
        switch settings.prayerLocationSource {
        case .city:
            // A bundled city carries its own IANA zone.
            guard let city = city(),
                  let timeZone = TimeZone(identifier: city.timeZoneIdentifier) else { return nil }
            return ResolvedPrayerLocation(coordinates: city.coordinates, timeZone: timeZone)
        case .currentLocation:
            // A one-shot fix caches the Mac's IANA zone alongside the
            // coordinates, so later travel doesn't reinterpret the old
            // fix on a different day.
            guard let coordinates = settings.currentLocationCoordinates else { return nil }
            let identifier = settings.currentLocationTimeZoneIdentifier ?? TimeZone.current.identifier
            guard let timeZone = TimeZone(identifier: identifier) else { return nil }
            return ResolvedPrayerLocation(coordinates: coordinates, timeZone: timeZone)
        }
    }
}
