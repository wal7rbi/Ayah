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
    @Published private(set) var showFloatingTab: Bool
    private var hoverEnabled: Bool
    private var hoverSettingsCancellable: AnyCancellable?
    private let interactionTimer: any OneShotTimerScheduling
    private var autoCollapseTask: (any OneShotTimerToken)?
    private var hoverTask: (any OneShotTimerToken)?
    private var autoGeneration = 0
    private var hoverGeneration = 0
    private var pointerInside = false
    private var suppressHoverUntilExit = false
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
        autoCollapseDelay: Duration = .seconds(12),
        interactionTimer: (any OneShotTimerScheduling)? = nil
    ) {
        self.autoCollapseDelay = autoCollapseDelay
        self.interactionTimer = interactionTimer ?? NotchInteractionTimer()
        self.hoverEnabled = settingsStore.settings.openOnHover
        self.showFloatingTab = settingsStore.settings.showFloatingTab
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
        hoverSettingsCancellable = settingsStore.$settings
            .sink { [weak self] settings in
                guard let self else { return }
                if self.hoverEnabled != settings.openOnHover {
                    self.hoverEnabled = settings.openOnHover
                    self.resetPointerInteraction()
                }
                if self.showFloatingTab != settings.showFloatingTab {
                    self.showFloatingTab = settings.showFloatingTab
                }
            }
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
                cancelHover()
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
        cancelHover()
        withAnimation(Self.motionAnimation) { isExpanded = true }
        let generation = autoGeneration
        let components = autoCollapseDelay.components
        let delay = Double(components.seconds) + Double(components.attoseconds) / 1e18
        autoCollapseTask = interactionTimer.schedule(after: delay, leeway: 0) { [weak self] in
            guard let self, self.autoGeneration == generation else { return }
            self.autoCollapseTask?.cancel()
            self.autoCollapseTask = nil
            if !self.pointerInside || !self.hoverEnabled { self.collapse() }
        }
    }

    func pointerChanged(_ inside: Bool) {
        guard pointerInside != inside else { return }
        pointerInside = inside
        cancelHover()
        if !inside { suppressHoverUntilExit = false }
        guard hoverEnabled else { return }
        if inside {
            // Nothing to reveal yet: hovering must not open an empty, spinning card.
            guard !isExpanded, !suppressHoverUntilExit, content != .none else { return }
            let generation = hoverGeneration
            hoverTask = interactionTimer.schedule(after: 0.3, leeway: 0) { [weak self] in
                guard let self, self.hoverGeneration == generation,
                      self.pointerInside, self.hoverEnabled, !self.suppressHoverUntilExit,
                      self.content != .none else { return }
                self.cancelHover()
                withAnimation(Self.motionAnimation) { self.isExpanded = true }
            }
        } else if isExpanded && autoCollapseTask == nil {
            let generation = hoverGeneration
            hoverTask = interactionTimer.schedule(after: 0.15, leeway: 0) { [weak self] in
                guard let self, self.hoverGeneration == generation,
                      !self.pointerInside, self.autoCollapseTask == nil else { return }
                self.cancelHover()
                self.collapse()
            }
        }
    }

    /// A retired presentation cannot retain pointer ownership of the new one.
    func resetPointerInteraction() {
        let hadHoverInteraction = pointerInside || hoverTask != nil
        cancelHover()
        pointerInside = false
        suppressHoverUntilExit = false
        if hadHoverInteraction && autoCollapseTask == nil { collapse() }
    }

    func toggleExpanded() {
        guard isExpanded else {
            expandAndAutoCollapse()
            return
        }
        cancelAutoCollapse()
        cancelHover()
        suppressHoverUntilExit = pointerInside
        collapse()
    }

    private func collapse() {
        withAnimation(Self.motionAnimation) { isExpanded = false }
    }

    private func cancelHover() {
        hoverGeneration += 1
        hoverTask?.cancel()
        hoverTask = nil
    }

    private func cancelAutoCollapse() {
        autoGeneration += 1
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
    }
}

/// One-shot tasks only; no idle polling. The scheduling boundary is shared
/// with AyahKit so interaction races can be exercised without real sleeps.
@MainActor
private final class NotchInteractionTimer: OneShotTimerScheduling {
    private final class Token: OneShotTimerToken {
        var task: Task<Void, Never>?
        func cancel() { task?.cancel() }
        deinit { task?.cancel() }
    }

    func schedule(after interval: TimeInterval, leeway: TimeInterval,
                  action: @escaping @MainActor () -> Void) -> any OneShotTimerToken {
        let token = Token()
        token.task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            action()
        }
        return token
    }
}
