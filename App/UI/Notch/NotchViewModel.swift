import AyahKit
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
    private let surahsByNumber: [Int: Surah]
    private var settingsCancellable: AnyCancellable?
    private var autoCollapseTask: Task<Void, Never>?

    private static let expandSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    /// How long newly-due content stays expanded before the notch
    /// collapses itself again.
    private static let autoCollapseDelay: Duration = .seconds(12)

    init(
        quranRepository: QuranRepository?,
        verseScheduler: VerseScheduler?,
        prayerAlertScheduler: PrayerAlertScheduler?,
        settingsStore: SettingsStore
    ) {
        self.verseScheduler = verseScheduler
        self.prayerAlertScheduler = prayerAlertScheduler
        self.settingsStore = settingsStore
        self.isDisplayEnabled = settingsStore.settings.isVerseDisplayEnabled
        self.surahsByNumber = Dictionary(
            uniqueKeysWithValues: (quranRepository?.surahs() ?? []).map { ($0.number, $0) }
        )
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
                withAnimation(Self.expandSpring) { isExpanded = false }
            }
            return
        }
        verseScheduler?.start { [weak self] ayahs in
            Task { @MainActor in
                self?.showVerses(ayahs)
            }
        }
    }

    private func showVerses(_ ayahs: [QuranAyah]) {
        guard let first = ayahs.first else { return }
        content = .verses(ayahs, surahsByNumber[first.surahNumber])
        expandAndAutoCollapse()
    }

    private func showPrayerAlert(_ display: PrayerAlertDisplay) {
        let surah = display.ayah.flatMap { surahsByNumber[$0.surahNumber] }
        content = .prayerAlert(display.event, ayah: display.ayah, surah: surah)
        expandAndAutoCollapse()
    }

    private func expandAndAutoCollapse() {
        cancelAutoCollapse()
        withAnimation(Self.expandSpring) { isExpanded = true }
        autoCollapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.autoCollapseDelay)
            guard !Task.isCancelled else { return }
            self?.autoCollapseTask = nil
            withAnimation(Self.expandSpring) { self?.isExpanded = false }
        }
    }

    /// Routes manual taps through here (rather than the view mutating
    /// `isExpanded` directly) so a click cancels any pending auto-collapse
    /// instead of racing it.
    func toggleExpanded() {
        cancelAutoCollapse()
        withAnimation(Self.expandSpring) { isExpanded.toggle() }
    }

    private func cancelAutoCollapse() {
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
    }
}
