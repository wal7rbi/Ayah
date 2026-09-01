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
/// This view model hops each scheduler's callback back onto the main
/// actor, republishes the result for `NotchContentView`, and starts/stops
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
    private var shouldSkipInitialScheduledVerses = false

    private static let expandSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    private static var motionAnimation: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : expandSpring
    }
    /// How long newly-due content stays expanded before the notch
    /// collapses itself again.
    private static let autoCollapseDelay: Duration = .seconds(12)

    init(
        quranRepository: QuranRepository?,
        verseScheduler: VerseScheduler?,
        prayerAlertScheduler: PrayerAlertScheduler?,
        settingsStore: SettingsStore,
        lastShownStore: LastShownStore
    ) {
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
        // `VerseScheduler.start` emits once immediately before arming its
        // interval. Preserve a valid restored item through launch by
        // ignoring only that first emission; the next scheduled deadline
        // still records and displays new content normally.
        self.shouldSkipInitialScheduledVerses = restoredContent != nil
    }

    /// Starts observing `isVerseDisplayEnabled` and applies its current
    /// value immediately — this is the one-time hookup `NotchController`
    /// calls at attach; subsequent toggles from the Settings UI flow
    /// through the same `sink`.
    func startDisplayTimer() {
        settingsCancellable = settingsStore.$settings
            .map(\.isVerseDisplayEnabled)
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.setDisplayEnabled(enabled)
            }
    }

    /// Starts `PrayerAlertScheduler` — the other one-time hookup
    /// `NotchController` calls at attach. Internal gating on
    /// `arePrayerNotificationsEnabled` happens inside the scheduler
    /// itself, the same way `VerseScheduler` is unconditionally started
    /// here and `isVerseDisplayEnabled` is what actually gates it.
    func startPrayerAlerts() {
        prayerAlertScheduler?.start { [weak self] display in
            Task { @MainActor in
                self?.showPrayerAlert(display)
            }
        }
    }

    private func setDisplayEnabled(_ enabled: Bool) {
        isDisplayEnabled = enabled
        guard enabled else {
            verseScheduler?.stop()
            // Leave an in-progress prayer alert alone if the verse toggle
            // happens to be flipped off mid-display.
            if case .verses = content {
                cancelAutoCollapse()
                content = .none
                withAnimation(Self.motionAnimation) { isExpanded = false }
            }
            return
        }
        verseScheduler?.start { [weak self] ayahs in
            Task { @MainActor in
                self?.showScheduledVerses(ayahs)
            }
        }
    }

    private func showScheduledVerses(_ ayahs: [QuranAyah]) {
        if shouldSkipInitialScheduledVerses {
            shouldSkipInitialScheduledVerses = false
            return
        }
        showVerses(ayahs)
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
        autoCollapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.autoCollapseDelay)
            guard !Task.isCancelled else { return }
            self?.autoCollapseTask = nil
            withAnimation(Self.motionAnimation) { self?.isExpanded = false }
        }
    }

    /// Routes manual taps through here (rather than the view mutating
    /// `isExpanded` directly) so a click cancels any pending auto-collapse
    /// instead of racing it.
    func toggleExpanded() {
        cancelAutoCollapse()
        withAnimation(Self.motionAnimation) { isExpanded.toggle() }
    }

    private func cancelAutoCollapse() {
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
    }
}
