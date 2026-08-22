import Adhan
import Foundation

// Adhan Swift's `CalculationMethod`/`Madhab` are simple, immutable
// value-type enums (String/Int raw values, no reference state) but don't
// declare `Sendable` themselves — safe to mark retroactively so
// `AppSettings` (which stores them directly, see ARCHITECTURE.md §9/§11)
// can itself conform to `Sendable`.
extension CalculationMethod: @unchecked @retroactive Sendable {}
extension Madhab: @unchecked @retroactive Sendable {}

/// Wraps Adhan Swift (ARCHITECTURE.md §9) for offline prayer-time
/// calculation. `calculationMethod`/`asrMadhab` are Adhan Swift's own
/// public `CalculationMethod`/`Madhab` types, reused directly rather than
/// mirrored — both are already exactly the enums a future settings picker
/// needs (§9's full method list, §11's "Asr calculation" control), so a
/// parallel wrapper enum would just be upkeep for no benefit.
public enum PrayerCalculator {
    /// Computes today's five prayers plus sunrise for the given Gregorian
    /// calendar date and coordinates. Returns `nil` only in the same
    /// cases Adhan Swift's own `PrayerTimes` initializer does — solar
    /// time being undeterminable for the given date/location — so callers
    /// should treat `nil` the same way Adhan Swift's own contract does.
    /// `timeZone` has no default: Adhan Swift interprets the `date:`
    /// `DateComponents` it's handed via its own UTC-based calendar
    /// internally (see `PrayerTimes.swift`'s `.gregorianUTC`), so the
    /// caller must supply year/month/day as experienced *at the target
    /// location*, not the Mac's system timezone — falling back to
    /// `TimeZone.current` silently would reproduce exactly the bug this
    /// parameter exists to prevent (see ARCHITECTURE.md §9's "Update").
    public static func prayerTimes(
        on date: Date,
        coordinates: Coordinates,
        calculationMethod: CalculationMethod,
        asrMadhab: Madhab,
        timeZone: TimeZone
    ) -> Adhan.PrayerTimes? {
        var parameters = calculationMethod.params
        parameters.madhab = asrMadhab

        // Umm al-Qura's Isha interval is a fixed 90 minutes after Maghrib
        // — except during Ramadan, when it extends to 120 minutes
        // (90 + 30). Adhan Swift has no Hijri calendar awareness and
        // cannot apply this itself (ARCHITECTURE.md §10).
        if calculationMethod == .ummAlQura, isRamadan(on: date, timeZone: timeZone) {
            parameters.adjustments.isha += 30
        }

        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        let dateComponents = gregorian.dateComponents([.year, .month, .day], from: date)
        let adhanCoordinates = Adhan.Coordinates(
            latitude: coordinates.latitude,
            longitude: coordinates.longitude
        )

        return Adhan.PrayerTimes(
            coordinates: adhanCoordinates,
            date: dateComponents,
            calculationParameters: parameters
        )
    }

    private static func isRamadan(on date: Date, timeZone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = timeZone
        return calendar.component(.month, from: date) == 9
    }
}
