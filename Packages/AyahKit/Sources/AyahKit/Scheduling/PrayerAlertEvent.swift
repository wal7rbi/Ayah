import Foundation

/// One prayer moment `PrayerAlertScheduler` should show in the notch —
/// the "what to show" half, kept as a pure value produced by
/// `PrayerAlertScheduler.prayerAlertEvents(...)`, mirroring the split
/// `VerseScheduler.selectNextVerses()` uses. Carries raw data rather than
/// pre-formatted text: `NotchContentView` builds the Arabic card text
/// itself from `prayerNameArabic`/`offsetMinutes`, the same way it
/// already builds verse/reference text from raw `QuranAyah`/`Surah` data
/// rather than consuming pre-formatted strings.
public struct PrayerAlertEvent: Equatable, Sendable {
    public let prayerKey: String
    public let prayerNameArabic: String
    public let fireDate: Date
    /// `0` = the exact prayer moment; `>0` = a reminder that many minutes
    /// before it.
    public let offsetMinutes: Int

    public var isReminder: Bool { offsetMinutes > 0 }

    public init(prayerKey: String, prayerNameArabic: String, fireDate: Date, offsetMinutes: Int) {
        self.prayerKey = prayerKey
        self.prayerNameArabic = prayerNameArabic
        self.fireDate = fireDate
        self.offsetMinutes = offsetMinutes
    }
}

/// `PrayerAlertEvent` plus the rotating "prayer" ayah resolved for this
/// specific firing — bundled together since `PrayerAlertScheduler` picks
/// the ayah at fire time and hands both to its callback in one shot.
public struct PrayerAlertDisplay: Equatable, Sendable {
    public let event: PrayerAlertEvent
    /// `nil` only if `QuranRepository` was unavailable this launch.
    public let ayah: QuranAyah?

    public init(event: PrayerAlertEvent, ayah: QuranAyah?) {
        self.event = event
        self.ayah = ayah
    }
}
