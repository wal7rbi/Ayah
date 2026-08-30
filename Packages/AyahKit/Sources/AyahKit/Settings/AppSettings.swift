import Adhan
import Foundation

/// Which of the two prayer-location inputs `AppSettings` is currently
/// configured to use — see `prayerLocationSource`.
public enum PrayerLocationSource: String, Codable, Sendable {
    case city
    case currentLocation
}

/// The Quran-display, prayer-time, and prayer-alert settings
/// `VerseScheduler`, `PrayerCalculator`, and `PrayerAlertScheduler` read.
/// Theme settings still belong to their own later build stage (see
/// ARCHITECTURE.md phased build order) and are not anticipated here.
public struct AppSettings: Codable, Equatable, Sendable {
    public var isVerseDisplayEnabled: Bool
    /// Seconds between verse displays.
    public var displayInterval: TimeInterval
    /// "Verses per display" (ARCHITECTURE.md's "Verses per display"
    /// section) — default 2, adjustable 1–5.
    public var versesPerDisplay: Int
    /// Probability (0-100) that a display draws from enabled memorization
    /// sets rather than the general 6236-ayah pool. Default 70, per
    /// ARCHITECTURE.md's "Weighted verse selection" section.
    public var memorizationWeightPercent: Int

    /// ARCHITECTURE.md §9 — defaults to Umm al-Qura. Adhan Swift's own
    /// enum, reused directly rather than mirrored (see `PrayerCalculator`).
    public var prayerCalculationMethod: CalculationMethod
    /// ARCHITECTURE.md §11 — the "Asr calculation" control. Default is
    /// the majority position (`.shafi`, which Adhan Swift's own doc
    /// comment notes also covers Maliki, Hanbali, and Ja'fari views).
    public var asrMadhab: Madhab
    /// GeoNames `geonameid` of the city prayer times are calculated for
    /// — `nil` until the user picks one via the city picker (see
    /// `LocationRepository`). Only read when `prayerLocationSource` is
    /// `.city`.
    public var selectedCityID: Int?
    /// Which of `selectedCityID` / `currentLocationCoordinates` is
    /// currently active — ARCHITECTURE.md §12's "Location Services could
    /// be added later as an explicit, opt-in convenience feature" (now
    /// built, see `CurrentLocationProvider`). Defaults to `.city` so
    /// existing behavior is unchanged until a user explicitly opts in.
    public var prayerLocationSource: PrayerLocationSource
    /// The last coordinates fetched via `CurrentLocationProvider` — a
    /// one-shot fetch cached here on each tap of "use current location",
    /// not a live subscription (§18: no continuous background work).
    /// Only read when `prayerLocationSource` is `.currentLocation`.
    public var currentLocationCoordinates: Coordinates?
    /// The system IANA time-zone identifier captured with the one-shot
    /// location. Keeping it alongside the coordinates avoids silently
    /// recalculating cached prayer times in a different zone after travel.
    public var currentLocationTimeZoneIdentifier: String?
    /// When `currentLocationCoordinates` was last fetched — shown in the
    /// Settings UI so a stale fix (e.g. after traveling) is visible
    /// rather than silently reused forever.
    public var currentLocationFetchedAt: Date?
    /// ARCHITECTURE.md §13's opt-in toggle — off by default, matching the
    /// same "explicit opt-in" pattern as `prayerLocationSource`. Gates
    /// `PrayerAlertScheduler`'s in-notch prayer alerts; unlike the
    /// `UNUserNotificationCenter`-based scheduler this field originally
    /// gated, turning it on no longer triggers any OS permission prompt —
    /// alerts are shown entirely in-process, in the notch.
    public var arePrayerNotificationsEnabled: Bool
    /// An optional *additional* reminder, in minutes before each prayer —
    /// `PrayerAlertScheduler` always shows an alert at the prayer's exact
    /// time regardless of this value; `0` means no extra reminder,
    /// anything else (the Settings UI offers 5/10/15 as a single-select
    /// dropdown, not a multi-select) also shows one that many minutes
    /// earlier. Not modeled as `Int?` deliberately: an
    /// `Optional` here would make "user explicitly picked none" and "this
    /// field didn't exist yet in an old settings blob" indistinguishable
    /// after decoding, since `JSONEncoder` omits `nil`-valued keys
    /// entirely — both cases would decode to the same "missing key"
    /// shape. `0` as an in-band sentinel sidesteps that ambiguity. Default
    /// `5`, matching the example this was built from ("5 minutes before,
    /// and on time").
    public var prayerNotificationReminderMinutes: Int

    public init(
        isVerseDisplayEnabled: Bool = true,
        displayInterval: TimeInterval = 900,
        versesPerDisplay: Int = 2,
        memorizationWeightPercent: Int = 70,
        prayerCalculationMethod: CalculationMethod = .ummAlQura,
        asrMadhab: Madhab = .shafi,
        selectedCityID: Int? = nil,
        prayerLocationSource: PrayerLocationSource = .city,
        currentLocationCoordinates: Coordinates? = nil,
        currentLocationTimeZoneIdentifier: String? = nil,
        currentLocationFetchedAt: Date? = nil,
        arePrayerNotificationsEnabled: Bool = false,
        prayerNotificationReminderMinutes: Int = 5
    ) {
        self.isVerseDisplayEnabled = isVerseDisplayEnabled
        self.displayInterval = displayInterval
        self.versesPerDisplay = versesPerDisplay
        self.memorizationWeightPercent = memorizationWeightPercent
        self.prayerCalculationMethod = prayerCalculationMethod
        self.asrMadhab = asrMadhab
        self.selectedCityID = selectedCityID
        self.prayerLocationSource = prayerLocationSource
        self.currentLocationCoordinates = currentLocationCoordinates
        self.currentLocationTimeZoneIdentifier = currentLocationTimeZoneIdentifier
        self.currentLocationFetchedAt = currentLocationFetchedAt
        self.arePrayerNotificationsEnabled = arePrayerNotificationsEnabled
        self.prayerNotificationReminderMinutes = prayerNotificationReminderMinutes
    }

    /// A hand-written `init(from:)` (the compiler still synthesizes
    /// `encode(to:)` and `CodingKeys` for us, since only decoding is
    /// customized here) so that evolving this struct's schema — adding a
    /// field, renaming one, or changing one's type, as the
    /// prayer-notification lead-time field has now done twice
    /// (`Int` → `Set<Int>` → renamed back to a plain `Int`,
    /// `prayerNotificationReminderMinutes`) — degrades one field to its
    /// default instead of silently discarding a user's entire settings
    /// (city, calculation method, memorization weight, ...) the moment
    /// `SettingsStore`'s `JSONDecoder().decode(AppSettings.self, from:)`
    /// hits any single incompatible/missing key. This is a real bug, not
    /// a hypothetical: it fired mid-development the first time that
    /// field's type changed, silently resetting a real, already-fetched
    /// `currentLocationCoordinates` fix back to `nil`. Every stored
    /// property must be decoded through `decode(_:default:)` below,
    /// including ones that look unrelated to whatever's changing —
    /// skipping one reintroduces the same failure mode for that field.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decode<T: Decodable>(_ key: CodingKeys, default defaultValue: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? defaultValue
        }

        isVerseDisplayEnabled = decode(.isVerseDisplayEnabled, default: true)
        let decodedInterval: TimeInterval = decode(.displayInterval, default: 900)
        displayInterval = decodedInterval.isFinite && (60...86_400).contains(decodedInterval) ? decodedInterval : 900
        let decodedVerses: Int = decode(.versesPerDisplay, default: 2)
        versesPerDisplay = (1...5).contains(decodedVerses) ? decodedVerses : 2
        let decodedWeight: Int = decode(.memorizationWeightPercent, default: 70)
        memorizationWeightPercent = (0...100).contains(decodedWeight) ? decodedWeight : 70
        let decodedMethod: CalculationMethod = decode(.prayerCalculationMethod, default: .ummAlQura)
        prayerCalculationMethod = decodedMethod == .other ? .ummAlQura : decodedMethod
        asrMadhab = decode(.asrMadhab, default: .shafi)
        let decodedCityID: Int? = decode(.selectedCityID, default: nil)
        selectedCityID = decodedCityID.flatMap { $0 > 0 ? $0 : nil }
        prayerLocationSource = decode(.prayerLocationSource, default: .city)
        let decodedCoordinates: Coordinates? = decode(.currentLocationCoordinates, default: nil)
        currentLocationCoordinates = decodedCoordinates.flatMap {
            $0.latitude.isFinite && (-90...90).contains($0.latitude)
                && $0.longitude.isFinite && (-180...180).contains($0.longitude) ? $0 : nil
        }
        let decodedTimeZone: String? = decode(.currentLocationTimeZoneIdentifier, default: nil)
        currentLocationTimeZoneIdentifier = decodedTimeZone.flatMap {
            TimeZone(identifier: $0) == nil ? nil : $0
        }
        currentLocationFetchedAt = decode(.currentLocationFetchedAt, default: nil)
        arePrayerNotificationsEnabled = decode(.arePrayerNotificationsEnabled, default: false)
        let decodedReminder: Int = decode(.prayerNotificationReminderMinutes, default: 5)
        prayerNotificationReminderMinutes = (0...180).contains(decodedReminder) ? decodedReminder : 5
    }
}
