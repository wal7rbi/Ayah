import Combine
import Dispatch
import Foundation

/// Weighted-selects verses for display and drives the notch's display
/// timer, per ARCHITECTURE.md's "Weighted verse selection" and "Verses
/// per display" sections.
///
/// `selectNextVerses()` is synchronous and advances a selected sequential
/// set’s persisted cursor. It is fully testable
/// without a timer. `start(onVersesSelected:)` layers a single
/// self-rearming `DispatchSourceTimer` on top (armed only for the next
/// event, never a repeating timer or a polling loop). Zero leeway rather
/// than ARCHITECTURE.md §18's original ~10% suggestion: display intervals
/// are now user-chosen 15min-3hr presets (see `PopoverContentView`), where
/// firing exactly when picked matters more than the marginal system-wide
/// wakeup-coalescing benefit a single infrequent timer would give up.
///
/// Timer lifecycle and callbacks are main-actor isolated; synchronous
/// selection remains available independently for repository-level use.
public final class VerseScheduler {
    private let quranRepository: QuranRepository
    private let memorizationRepository: MemorizationRepository
    private let settingsStore: SettingsStore
    private let randomDouble: () -> Double
    private let randomInt: (ClosedRange<Int>) -> Int

    private let timerScheduling: (any OneShotTimerScheduling)?
    @MainActor private var timerSource: (any OneShotTimerToken)?
    @MainActor private var onVersesSelected: (@MainActor ([QuranAyah]) -> Void)?
    @MainActor private var intervalCancellable: AnyCancellable?
    @MainActor private var scheduleGeneration: UInt = 0

    /// The error from the most recent sequential-set cursor write inside
    /// `selectFromMemorizationSets`, or `nil` if the last one succeeded
    /// (or none has been attempted). A failed write doesn't affect the
    /// verses returned this cycle, but it does mean that set's walk
    /// position silently didn't advance — it would repeat the same range
    /// next time instead of progressing, with `try?` alone giving no way
    /// to tell the difference from a set that's simply not due yet.
    public private(set) var lastCursorUpdateError: Error?

    public init(
        quranRepository: QuranRepository,
        memorizationRepository: MemorizationRepository,
        settingsStore: SettingsStore,
        randomDouble: @escaping () -> Double = { Double.random(in: 0..<1) },
        randomInt: @escaping (ClosedRange<Int>) -> Int = { Int.random(in: $0) },
        timerScheduling: (any OneShotTimerScheduling)? = nil
    ) {
        self.quranRepository = quranRepository
        self.memorizationRepository = memorizationRepository
        self.settingsStore = settingsStore
        self.randomDouble = randomDouble
        self.randomInt = randomInt
        self.timerScheduling = timerScheduling
    }

    /// Restored content can wait a full interval without selecting unseen verses.
    @MainActor
    public func start(selectImmediately: Bool = true, initialSettings: AppSettings? = nil,
                      onVersesSelected: @escaping @MainActor ([QuranAyah]) -> Void) {
        guard self.onVersesSelected == nil else { return }
        self.onVersesSelected = onVersesSelected
        let settings = initialSettings ?? settingsStore.settings
        if selectImmediately { onVersesSelected(selectNextVerses(settings: settings)) }
        guard self.onVersesSelected != nil else { return }
        intervalCancellable = settingsStore.$settings
            .map(\.displayInterval)
            .dropFirst() // start can be called inside settings' willSet publication.
            .prepend(settings.displayInterval)
            .removeDuplicates()
            .sink { [weak self] interval in self?.armNextTimer(interval: interval) }
    }

    @MainActor
    public func stop() {
        scheduleGeneration &+= 1
        intervalCancellable = nil
        timerSource?.cancel()
        timerSource = nil
        onVersesSelected = nil
    }

    @MainActor
    private func armNextTimer(interval: TimeInterval) {
        PerformanceSignposts.measure("VerseSchedulerRearm") {
            scheduleGeneration &+= 1
            let generation = scheduleGeneration
            timerSource?.cancel()
            timerSource = nil
            guard onVersesSelected != nil else { return }
            timerSource = (timerScheduling ?? DispatchOneShotTimer()).schedule(
                after: max(1, interval), leeway: 0
            ) { [weak self] in
                guard let self, self.scheduleGeneration == generation,
                      let callback = self.onVersesSelected else { return }
                callback(self.selectNextVerses())
                guard self.scheduleGeneration == generation else { return }
                self.armNextTimer(interval: self.settingsStore.settings.displayInterval)
            }
        }
    }

    /// Picks a starting ayah — from an enabled memorization set with
    /// probability `memorizationWeightPercent`, honoring its
    /// `repetitionMode`, otherwise uniformly from the general pool — then
    /// gathers up to `versesPerDisplay - 1` following consecutive ayahs,
    /// clamped so a display never spills past the current surah (general
    /// pool) or the memorization set's own range.
    public func selectNextVerses() -> [QuranAyah] {
        selectNextVerses(settings: settingsStore.settings)
    }

    private func selectNextVerses(settings: AppSettings) -> [QuranAyah] {
        PerformanceSignposts.measure("VerseSelection") {
            let versesPerDisplay = max(1, settings.versesPerDisplay)
            let enabledSets = memorizationRepository.fetchEnabled().filter { $0.ayahCount > 0 }

            if !enabledSets.isEmpty,
               randomDouble() < Double(settings.memorizationWeightPercent) / 100 {
                return selectFromMemorizationSets(enabledSets, versesPerDisplay: versesPerDisplay)
            }
            return selectFromGeneralPool(versesPerDisplay: versesPerDisplay)
        }
    }

    private func selectFromMemorizationSets(
        _ enabledSets: [MemorizationSet],
        versesPerDisplay: Int
    ) -> [QuranAyah] {
        let set = pickWeightedSet(from: enabledSets)

        let startAyah: Int
        switch set.repetitionMode {
        case .sequential:
            startAyah = set.cursorAyah ?? set.startAyah
        case .random:
            startAyah = randomInt(set.startAyah...set.endAyah)
        }

        var ayahs: [QuranAyah] = []
        var ayahNumber = startAyah
        while ayahs.count < versesPerDisplay, ayahNumber <= set.endAyah {
            guard let ayah = quranRepository.ayah(surah: set.surahNumber, ayah: ayahNumber) else { break }
            ayahs.append(ayah)
            ayahNumber += 1
        }

        if set.repetitionMode == .sequential, !ayahs.isEmpty {
            let nextCursor = ayahNumber > set.endAyah ? set.startAyah : ayahNumber
            do {
                try memorizationRepository.updateCursor(id: set.id, cursorAyah: nextCursor)
                lastCursorUpdateError = nil
            } catch {
                lastCursorUpdateError = error
            }
        }

        return ayahs
    }

    /// Weights each enabled set by its ayah count, so drawing from the
    /// "flattened pool of all is_enabled memorization sets" (per
    /// ARCHITECTURE.md) behaves as if every individual ayah across every
    /// set were one shared pool, not as if every set were equally likely
    /// regardless of size.
    private func pickWeightedSet(from sets: [MemorizationSet]) -> MemorizationSet {
        let totalWeight = sets.reduce(0) { $0 + $1.ayahCount }
        var remaining = randomInt(0...(totalWeight - 1))
        for set in sets {
            if remaining < set.ayahCount { return set }
            remaining -= set.ayahCount
        }
        return sets[sets.count - 1]
    }

    private func selectFromGeneralPool(versesPerDisplay: Int) -> [QuranAyah] {
        guard let start = quranRepository.randomAyah() else { return [] }

        var ayahs = [start]
        var ayahNumber = start.ayahNumber + 1
        while ayahs.count < versesPerDisplay,
              let next = quranRepository.ayah(surah: start.surahNumber, ayah: ayahNumber) {
            ayahs.append(next)
            ayahNumber += 1
        }
        return ayahs
    }
}
