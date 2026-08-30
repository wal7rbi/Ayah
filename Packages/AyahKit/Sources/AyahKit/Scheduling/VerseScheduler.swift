import Dispatch
import Foundation

/// Weighted-selects verses for display and drives the notch's display
/// timer, per ARCHITECTURE.md's "Weighted verse selection" and "Verses
/// per display" sections.
///
/// `selectNextVerses()` is a pure, synchronous function — fully testable
/// without a timer. `start(onVersesSelected:)` layers a single
/// self-rearming `DispatchSourceTimer` on top (armed only for the next
/// event, never a repeating timer or a polling loop). Zero leeway rather
/// than ARCHITECTURE.md §18's original ~10% suggestion: display intervals
/// are now user-chosen 15min-3hr presets (see `PopoverContentView`), where
/// firing exactly when picked matters more than the marginal system-wide
/// wakeup-coalescing benefit a single infrequent timer would give up.
///
/// Not `@MainActor`: the timer runs on the main queue by construction,
/// but the type itself does no AppKit work. Callers that need to touch
/// `@MainActor` state from `onVersesSelected` (e.g. `NotchViewModel`) are
/// responsible for hopping back onto their own actor, the same way the
/// Stage 4 placeholder timer did.
public final class VerseScheduler {
    private let quranRepository: QuranRepository
    private let memorizationRepository: MemorizationRepository
    private let settingsStore: SettingsStore
    private let randomDouble: () -> Double
    private let randomInt: (ClosedRange<Int>) -> Int

    private var timerSource: DispatchSourceTimer?
    private var onVersesSelected: (([QuranAyah]) -> Void)?

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
        randomInt: @escaping (ClosedRange<Int>) -> Int = { Int.random(in: $0) }
    ) {
        self.quranRepository = quranRepository
        self.memorizationRepository = memorizationRepository
        self.settingsStore = settingsStore
        self.randomDouble = randomDouble
        self.randomInt = randomInt
    }

    public func start(onVersesSelected: @escaping ([QuranAyah]) -> Void) {
        guard timerSource == nil else { return }
        self.onVersesSelected = onVersesSelected
        fireAndRearm()
    }

    public func stop() {
        timerSource?.cancel()
        timerSource = nil
        onVersesSelected = nil
    }

    private func fireAndRearm() {
        onVersesSelected?(selectNextVerses())
        armNextTimer()
    }

    private func armNextTimer() {
        PerformanceSignposts.measure("VerseSchedulerRearm") {
            let interval = max(1, settingsStore.settings.displayInterval)
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + interval, leeway: .milliseconds(0))
            timer.setEventHandler { [weak self] in self?.fireAndRearm() }
            timer.resume()
            timerSource = timer
        }
    }

    /// Picks a starting ayah — from an enabled memorization set with
    /// probability `memorizationWeightPercent`, honoring its
    /// `repetitionMode`, otherwise uniformly from the general pool — then
    /// gathers up to `versesPerDisplay - 1` following consecutive ayahs,
    /// clamped so a display never spills past the current surah (general
    /// pool) or the memorization set's own range.
    public func selectNextVerses() -> [QuranAyah] {
        PerformanceSignposts.measure("VerseSelection") {
            let versesPerDisplay = max(1, settingsStore.settings.versesPerDisplay)
            let enabledSets = memorizationRepository.fetchEnabled().filter { $0.ayahCount > 0 }

            if !enabledSets.isEmpty,
               randomDouble() < Double(settingsStore.settings.memorizationWeightPercent) / 100 {
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
