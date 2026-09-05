import AyahKit
import AppKit
import Combine
import Foundation
import SwiftUI

/// Drives the notch panel's collapsed/expanded state and whatever it's
/// currently displaying — a verse batch or a prayer alert (see
/// `NotchDisplayContent`). Selection, weighting across memorization sets,
/// and the self-rearming display timer all live in `VerseScheduler`;
/// prayer-alert timing and ayah selection live in `PrayerAlertScheduler`.
/// Scheduler callbacks arrive on the main actor. This view model publishes
/// their result for `NotchContentView` and starts/stops
/// `VerseScheduler` live as the Settings UI's "Show verses in notch"
/// toggle (`AppSettings.isVerseDisplayEnabled`) changes.
///
/// Per ARCHITECTURE.md §3, expand/collapse fires on discrete events — "a
/// verse becoming due, or a user click" — now also "a prayer alert
/// becoming due" — so new content auto-expands the notch here, not just a
/// manual tap.
@MainActor
final class NotchViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var collapsedSize = CGSize(width: 200, height: 32)
    @Published private(set) var content: NotchDisplayContent = .none
    @Published private(set) var isDisplayEnabled: Bool

    private let verseScheduler: VerseScheduler?
    private let prayerAlertScheduler: PrayerAlertScheduler?
    private let settingsStore: SettingsStore
    private let lastShownStore: LastShownStore
    private let quranRepository: QuranRepository?
    private let surahsByNumber: [Int: Surah]
    private var settingsCancellable: AnyCancellable?
    private var autoCollapseTask: Task<Void, Never>?
    private var shouldDeferInitialVerseSelection = false
    /// How long newly-due content stays expanded before the notch
    /// collapses itself again. An init parameter rather than a constant
    /// only so `AyahTests` can drive the auto-collapse path without
    /// spending 12 seconds of wall clock per test; production callers use
    /// the default.
    private let autoCollapseDelay: Duration

    private static let expandSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    private static var motionAnimation: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : expandSpring
    }

    init(
        quranRepository: QuranRepository?,
        verseScheduler: VerseScheduler?,
        prayerAlertScheduler: PrayerAlertScheduler?,
        settingsStore: SettingsStore,
        lastShownStore: LastShownStore,
        autoCollapseDelay: Duration = .seconds(12)
    ) {
        self.autoCollapseDelay = autoCollapseDelay
        self.verseScheduler = verseScheduler
        self.prayerAlertScheduler = prayerAlertScheduler
        self.settingsStore = settingsStore
        self.lastShownStore = lastShownStore
        self.quranRepository = quranRepository
        self.isDisplayEnabled = settingsStore.settings.isVerseDisplayEnabled
        self.surahsByNumber = Dictionary(
            uniqueKeysWithValues: (quranRepository?.surahs() ?? []).map { ($0.number, $0) }
        )
        let restoredContent = NotchDisplayContent.resolve(
            lastShownStore.record,
            quranRepository: quranRepository
        )
        self.content = restoredContent ?? .none
        // Keep restored content without selecting or advancing an unseen batch.
        self.shouldDeferInitialVerseSelection = restoredContent != nil
    }

    /// Starts observing `isVerseDisplayEnabled` and applies its current
    /// value immediately — this is the one-time hookup `NotchController`
    /// calls at attach; subsequent toggles from the Settings UI flow
    /// through the same `sink`.
    func startDisplayTimer() {
        guard settingsCancellable == nil else { return }
        settingsCancellable = settingsStore.$settings
            .removeDuplicates { $0.isVerseDisplayEnabled == $1.isVerseDisplayEnabled }
            .sink { [weak self] settings in
                self?.setDisplayEnabled(settings.isVerseDisplayEnabled, settings: settings)
            }
    }

    /// Starts `PrayerAlertScheduler` — the other one-time hookup
    /// `NotchController` calls at attach. Internal gating on
    /// `arePrayerNotificationsEnabled` happens inside the scheduler
    /// itself, the same way `VerseScheduler` is unconditionally started
    /// here and `isVerseDisplayEnabled` is what actually gates it.
    func startPrayerAlerts() {
        prayerAlertScheduler?.start { [weak self] display in
            self?.showPrayerAlert(display)
        }
    }

    private func setDisplayEnabled(_ enabled: Bool, settings: AppSettings) {
        isDisplayEnabled = enabled
        guard enabled else {
            verseScheduler?.stop()
            shouldDeferInitialVerseSelection = false
            // Leave an in-progress prayer alert alone if the verse toggle
            // happens to be flipped off mid-display.
            if case .verses = content {
                cancelAutoCollapse()
                content = .none
                withAnimation(Self.motionAnimation) { isExpanded = false }
            }
            return
        }
        let selectImmediately = !shouldDeferInitialVerseSelection
        shouldDeferInitialVerseSelection = false
        verseScheduler?.start(selectImmediately: selectImmediately, initialSettings: settings) { [weak self] ayahs in
            self?.showVerses(ayahs)
        }
    }

    private func showVerses(_ ayahs: [QuranAyah]) {
        guard let first = ayahs.first else { return }
        content = .verses(ayahs, surahsByNumber[first.surahNumber])
        lastShownStore.save(.verses(LastShownVerseRecord(
            ayahIDs: ayahs.map(\.id),
            shownAt: Date()
        )))
        expandAndAutoCollapse()
    }

    private func showPrayerAlert(_ display: PrayerAlertDisplay) {
        let surah = display.ayah.flatMap { surahsByNumber[$0.surahNumber] }
        content = .prayerAlert(display.event, ayah: display.ayah, surah: surah)
        lastShownStore.save(.prayerAlert(LastShownPrayerAlertRecord(
            prayerKey: display.event.prayerKey,
            fireDate: display.event.fireDate,
            reminderOffsetMinutes: display.event.offsetMinutes,
            ayahID: display.ayah?.id,
            shownAt: Date()
        )))
        expandAndAutoCollapse()
    }

    /// Re-resolves the compact record on every replay. This both rechecks
    /// Quran availability and leaves the record's original `shownAt`
    /// timestamp untouched.
    func replayLastShown() {
        guard let resolved = NotchDisplayContent.resolve(
            lastShownStore.record,
            quranRepository: quranRepository
        ) else { return }
        content = resolved
        expandAndAutoCollapse()
    }

    private func expandAndAutoCollapse() {
        cancelAutoCollapse()
        withAnimation(Self.motionAnimation) { isExpanded = true }
        let delay = autoCollapseDelay
        autoCollapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.autoCollapseTask = nil
            withAnimation(Self.motionAnimation) { self?.isExpanded = false }
        }
    }

    /// Routes manual taps through here rather than letting the view mutate
    /// `isExpanded` directly, because the two directions are not symmetric.
    /// A tap that *expands* arms a whole fresh delay: it must not inherit
    /// whatever is left of a pending one and get yanked shut mid-read, and
    /// it must not arm nothing at all — on a physical notch the collapsed
    /// pill is always on screen, so tapping it is the ordinary way to
    /// re-read the last card, and leaving that with no timer stranded the
    /// card on screen indefinitely. A tap that *collapses* cancels the
    /// pending task outright, since there is nothing left to dismiss.
    func toggleExpanded() {
        guard isExpanded else {
            expandAndAutoCollapse()
            return
        }
        cancelAutoCollapse()
        withAnimation(Self.motionAnimation) { isExpanded = false }
    }

    private func cancelAutoCollapse() {
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
    }
}
