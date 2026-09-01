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

    /// Resolves identifier-only persistence through the verified Quran
    /// repository. The menu-bar card and popup replay both call this exact
    /// path, so missing rows fail closed and their rendered content cannot
    /// diverge.
    static func resolve(
        _ record: LastShownRecord?,
        quranRepository: QuranRepository?
    ) -> NotchDisplayContent? {
        guard let record else { return nil }
        let surahsByNumber = Dictionary(
            uniqueKeysWithValues: (quranRepository?.surahs() ?? []).map { ($0.number, $0) }
        )

        switch record {
        case .verses(let value):
            guard let quranRepository else { return nil }
            let ayahs = value.ayahIDs.compactMap(quranRepository.ayah(id:))
            guard ayahs.count == value.ayahIDs.count,
                  let first = ayahs.first,
                  let surah = surahsByNumber[first.surahNumber] else { return nil }
            return .verses(ayahs, surah)

        case .prayerAlert(let value):
            guard let event = PrayerAlertEvent(
                prayerKey: value.prayerKey,
                fireDate: value.fireDate,
                offsetMinutes: value.reminderOffsetMinutes
            ) else { return nil }

            let ayah: QuranAyah?
            if let ayahID = value.ayahID {
                guard let resolved = quranRepository?.ayah(id: ayahID),
                      surahsByNumber[resolved.surahNumber] != nil else { return nil }
                ayah = resolved
            } else {
                ayah = nil
            }
            let surah = ayah.flatMap { surahsByNumber[$0.surahNumber] }
            return .prayerAlert(event, ayah: ayah, surah: surah)
        }
    }
}
