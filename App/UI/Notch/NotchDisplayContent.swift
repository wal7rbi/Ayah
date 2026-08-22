import AyahKit

/// The one thing the notch's expanded card can currently be showing —
/// mutually exclusive by construction. `VerseScheduler` and
/// `PrayerAlertScheduler` are two independent self-rearming timers that
/// can each fire while the notch is already expanded showing the other's
/// content; a single enum makes "exactly one active content kind, or
/// none" true by construction instead of needing an ad hoc priority rule
/// between two nullable optionals that could otherwise both be non-nil at
/// once.
enum NotchDisplayContent: Equatable {
    case none
    case verses([QuranAyah], Surah?)
    case prayerAlert(PrayerAlertEvent, ayah: QuranAyah?, surah: Surah?)
}
