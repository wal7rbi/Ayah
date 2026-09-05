import AyahKit
import Foundation
import XCTest
@testable import Ayah

/// The first automated coverage of anything in `App/`. `NotchViewModel` is
/// the piece that most deserves it: despite living next to the AppKit
/// panel code it is really a state machine, and its three interacting
/// pieces of state (`shouldDeferInitialVerseSelection`, the cancellable
/// auto-collapse task, and the `isVerseDisplayEnabled` sink) all fail
/// silently — a wrong answer shows up as a card that vanished, or one that
/// never appeared, with nothing logged.
///
/// Runs under `xcodebuild test`, not `swift test`: the suite is hosted in
/// the Ayah app so `@testable import Ayah` can reach the App target, and
/// so `Bundle.main` is the real app bundle and the tests that need actual
/// ayahs can read the same checksum-verified `quran.sqlite` the app ships.
@MainActor
final class NotchViewModelTests: XCTestCase {
    /// `QuranRepository.init` reads and checksums all 6,236 ayahs, which
    /// is worth doing once for the whole suite rather than per test.
    private static var sharedQuranRepository: QuranRepository?

    // `tearDown()` is nonisolated in XCTestCase, and this class is
    // @MainActor, so these three cannot be plain isolated properties: Swift
    // 6.1 rejects touching them from the override. (Swift 6.2 infers the
    // override's isolation and accepts it, which is exactly why this built
    // locally and failed in CI.) They are safe without isolation because
    // XCTest runs setUp, the test, and tearDown serially for each instance,
    // so nothing here is ever reachable concurrently.
    nonisolated(unsafe) private var temporaryDirectories: [URL] = []
    nonisolated(unsafe) private var defaultsSuiteNames: [String] = []
    nonisolated(unsafe) private var startedSchedulers: [VerseScheduler] = []

    override func tearDown() async throws {
        await MainActor.run {
            for scheduler in startedSchedulers { scheduler.stop() }
        }
        startedSchedulers.removeAll()
        for name in defaultsSuiteNames {
            UserDefaults().removePersistentDomain(forName: name)
        }
        defaultsSuiteNames.removeAll()
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    // MARK: - Launch restoration

    func testLaunchRestorationPopulatesContentWithoutExpanding() throws {
        let quranRepository = try quranRepository()
        let defaults = try isolatedDefaults()
        let store = LastShownStore(defaults: defaults)
        store.save(.verses(LastShownVerseRecord(ayahIDs: [1, 2], shownAt: Date(timeIntervalSince1970: 1_000))))

        let viewModel = try makeViewModel(
            quranRepository: quranRepository,
            settingsStore: SettingsStore(defaults: try isolatedDefaults()),
            lastShownStore: store
        )

        XCTAssertEqual(ayahIDs(of: viewModel.content), [1, 2])
        XCTAssertFalse(viewModel.isExpanded, "Restoring at launch must not pop the notch open on its own.")
    }

    // MARK: - Deferred launch selection

    func testRestoredRecordWaitsUntilFirstDeadline() async throws {
        let quranRepository = try quranRepository()
        let settingsStore = SettingsStore(defaults: try isolatedDefaults())
        settingsStore.settings = AppSettings(displayInterval: 1, versesPerDisplay: 2, memorizationWeightPercent: 100)
        let memorization = try MemorizationRepository(databasePath: ":memory:")
        let set = try memorization.create(surahNumber: 1, startAyah: 1, endAyah: 7)
        try memorization.updateCursor(id: set.id, cursorAyah: 3)
        let scheduler = VerseScheduler(quranRepository: quranRepository, memorizationRepository: memorization,
                                       settingsStore: settingsStore, randomDouble: { 0 })
        startedSchedulers.append(scheduler)
        let lastShownStore = LastShownStore(defaults: try isolatedDefaults())
        let restoredShownAt = Date(timeIntervalSince1970: 1_000)
        lastShownStore.save(.verses(LastShownVerseRecord(ayahIDs: [1, 2], shownAt: restoredShownAt)))

        let viewModel = try makeViewModel(
            quranRepository: quranRepository,
            verseScheduler: scheduler,
            settingsStore: settingsStore,
            lastShownStore: lastShownStore
        )
        viewModel.startDisplayTimer()

        // A restored card starts the scheduler without selecting a new batch.
        XCTAssertEqual(
            ayahIDs(of: viewModel.content), [1, 2],
            "The launch emission must not overwrite the restored card."
        )
        XCTAssertFalse(viewModel.isExpanded)
        XCTAssertEqual(memorization.fetchAll().first?.cursorAyah, 3, "Restoration must not consume unseen verses")
        XCTAssertEqual(lastShownStore.record?.shownAt, restoredShownAt, "Deferring selection must not update the saved record.")

        // The next armed deadline (displayInterval, above) is a real
        // scheduled display and must go through.
        let displayed = await waitUntil { lastShownStore.record?.shownAt != restoredShownAt }
        XCTAssertTrue(displayed, "The first scheduled deadline should display new content.")
        XCTAssertTrue(viewModel.isExpanded)
        XCTAssertEqual(ayahIDs(of: viewModel.content), [3, 4])
        XCTAssertEqual(memorization.fetchAll().first?.cursorAyah, 5)
    }

    func testFirstScheduledEmissionIsDisplayedWhenNothingWasRestored() async throws {
        let quranRepository = try quranRepository()
        let settingsStore = SettingsStore(defaults: try isolatedDefaults())
        let lastShownStore = LastShownStore(defaults: try isolatedDefaults())

        let viewModel = try makeViewModel(
            quranRepository: quranRepository,
            verseScheduler: try verseScheduler(quranRepository: quranRepository, settingsStore: settingsStore),
            settingsStore: settingsStore,
            lastShownStore: lastShownStore
        )
        XCTAssertEqual(viewModel.content, .none)
        viewModel.startDisplayTimer()

        let displayed = await waitUntil { viewModel.isExpanded }
        XCTAssertTrue(displayed, "With nothing restored there is nothing to protect, so the first emission shows.")
        XCTAssertFalse(ayahIDs(of: viewModel.content).isEmpty)
    }

    func testShowingVersesRecordsOnlyAyahIdentifiers() async throws {
        let quranRepository = try quranRepository()
        let settingsStore = SettingsStore(defaults: try isolatedDefaults())
        let lastShownStore = LastShownStore(defaults: try isolatedDefaults())

        let viewModel = try makeViewModel(
            quranRepository: quranRepository,
            verseScheduler: try verseScheduler(quranRepository: quranRepository, settingsStore: settingsStore),
            settingsStore: settingsStore,
            lastShownStore: lastShownStore
        )
        viewModel.startDisplayTimer()
        await waitUntil { lastShownStore.record != nil }

        guard case .verses(let record) = try XCTUnwrap(lastShownStore.record) else {
            return XCTFail("Expected a verses record, got \(String(describing: lastShownStore.record)).")
        }
        XCTAssertEqual(record.ayahIDs, ayahIDs(of: viewModel.content))
    }

    // MARK: - Auto-collapse

    func testNotchCollapsesAfterTheAutoCollapseDelay() async throws {
        let viewModel = try makeViewModel(
            lastShownStore: try prayerAlertStore(),
            autoCollapseDelay: .milliseconds(60)
        )
        viewModel.replayLastShown()
        XCTAssertTrue(viewModel.isExpanded)

        let collapsed = await waitUntil { !viewModel.isExpanded }
        XCTAssertTrue(collapsed, "The auto-collapse task should have collapsed the notch.")
    }

    func testTappingToExpandArmsTheAutoCollapse() async throws {
        let viewModel = try makeViewModel(
            lastShownStore: try prayerAlertStore(),
            autoCollapseDelay: .milliseconds(60)
        )
        XCTAssertFalse(viewModel.isExpanded)

        // The notch's own tap handler. On a physical notch it is the only
        // "show it again" affordance, and it used to expand the card with no
        // dismissal timer at all, leaving it on screen indefinitely.
        viewModel.toggleExpanded()
        XCTAssertTrue(viewModel.isExpanded)

        let collapsed = await waitUntil { !viewModel.isExpanded }
        XCTAssertTrue(collapsed, "A tap that expands must arm the auto-collapse, not leave the card open forever.")
    }

    func testReexpandingArmsAFreshDelayRatherThanInheritingTheStaleOne() async throws {
        let autoCollapseDelay = Duration.milliseconds(600)
        let viewModel = try makeViewModel(
            lastShownStore: try prayerAlertStore(),
            autoCollapseDelay: autoCollapseDelay
        )
        viewModel.replayLastShown()

        // Two thirds of the way to the deadline the display armed, so what is
        // left of it is plainly shorter than a whole fresh delay.
        try await Task.sleep(for: autoCollapseDelay * 2 / 3)
        viewModel.toggleExpanded()
        XCTAssertFalse(viewModel.isExpanded)
        viewModel.toggleExpanded()
        XCTAssertTrue(viewModel.isExpanded)

        // Past where the display's original deadline would have landed: the
        // reader who just tapped the card open must still be looking at it.
        try await Task.sleep(for: autoCollapseDelay * 2 / 3)
        XCTAssertTrue(viewModel.isExpanded, "Re-expanding must arm a fresh delay, not inherit the pending one.")

        let collapsed = await waitUntil { !viewModel.isExpanded }
        XCTAssertTrue(collapsed, "…and that fresh delay must still collapse the notch on its own.")
    }

    // MARK: - The isVerseDisplayEnabled sink

    func testDisablingVerseDisplayClearsVersesAndCollapses() async throws {
        let quranRepository = try quranRepository()
        let settingsStore = SettingsStore(defaults: try isolatedDefaults())
        let viewModel = try makeViewModel(
            quranRepository: quranRepository,
            verseScheduler: try verseScheduler(quranRepository: quranRepository, settingsStore: settingsStore),
            settingsStore: settingsStore,
            lastShownStore: LastShownStore(defaults: try isolatedDefaults())
        )
        viewModel.startDisplayTimer()
        await waitUntil { viewModel.isExpanded }

        settingsStore.settings.isVerseDisplayEnabled = false

        XCTAssertEqual(viewModel.content, .none)
        XCTAssertFalse(viewModel.isExpanded)
        XCTAssertFalse(viewModel.isDisplayEnabled)
    }

    func testDisablingVerseDisplayLeavesAPrayerAlertUntouched() async throws {
        let settingsStore = SettingsStore(defaults: try isolatedDefaults())
        let viewModel = try makeViewModel(
            settingsStore: settingsStore,
            lastShownStore: try prayerAlertStore()
        )
        viewModel.startDisplayTimer()
        viewModel.replayLastShown()
        let alertContent = viewModel.content

        settingsStore.settings.isVerseDisplayEnabled = false

        XCTAssertEqual(viewModel.content, alertContent, "The verse toggle must not clear a prayer alert.")
        XCTAssertTrue(viewModel.isExpanded, "…nor collapse the notch while one is being read.")
        XCTAssertFalse(viewModel.isDisplayEnabled)
    }

    // MARK: - Replay

    func testReplayResolvesContentWithoutMutatingTheStoredTimestamp() throws {
        let shownAt = Date(timeIntervalSince1970: 1_000)
        let store = try prayerAlertStore(shownAt: shownAt)
        let viewModel = try makeViewModel(lastShownStore: store)
        XCTAssertFalse(viewModel.isExpanded)

        viewModel.replayLastShown()

        guard case .prayerAlert(let event, _, _) = viewModel.content else {
            return XCTFail("Replay should have re-resolved the stored prayer alert.")
        }
        XCTAssertEqual(event.prayerKey, "asr")
        XCTAssertTrue(viewModel.isExpanded)
        XCTAssertEqual(store.record?.shownAt, shownAt, "Replay is not a new display and must not restamp the record.")
    }

    // MARK: - Fixtures

    private func makeViewModel(
        quranRepository: QuranRepository? = nil,
        verseScheduler: VerseScheduler? = nil,
        settingsStore: SettingsStore? = nil,
        lastShownStore: LastShownStore,
        autoCollapseDelay: Duration = .seconds(12)
    ) throws -> NotchViewModel {
        NotchViewModel(
            quranRepository: quranRepository,
            verseScheduler: verseScheduler,
            prayerAlertScheduler: nil,
            // Never `UserDefaults.standard`: these tests run inside the
            // real app process, and the real app's preferences are not
            // theirs to write to.
            settingsStore: try settingsStore ?? SettingsStore(defaults: isolatedDefaults()),
            lastShownStore: lastShownStore,
            autoCollapseDelay: autoCollapseDelay
        )
    }

    /// A store already holding a prayer-alert record that carries no ayah,
    /// which `NotchDisplayContent.resolve` can restore with no Quran
    /// repository at all — the cheap fixture for every test about
    /// expansion and the display toggle rather than about verse content.
    private func prayerAlertStore(shownAt: Date = Date(timeIntervalSince1970: 1_000)) throws -> LastShownStore {
        let store = LastShownStore(defaults: try isolatedDefaults())
        store.save(.prayerAlert(LastShownPrayerAlertRecord(
            prayerKey: "asr",
            fireDate: Date(timeIntervalSince1970: 2_000),
            reminderOffsetMinutes: 5,
            ayahID: nil,
            shownAt: shownAt
        )))
        return store
    }

    private func quranRepository() throws -> QuranRepository {
        if let existing = Self.sharedQuranRepository { return existing }
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(forResource: "quran", withExtension: "sqlite"),
            "The test host is the Ayah app, so the bundled Quran database should be reachable."
        )
        let checksumURL = try XCTUnwrap(Bundle.main.url(forResource: "CHECKSUM", withExtension: nil))
        let repository = try QuranRepository(
            databasePath: databaseURL.path,
            checksumPath: checksumURL.path
        )
        Self.sharedQuranRepository = repository
        return repository
    }

    /// A real `VerseScheduler` over a scratch memorization database, so
    /// the emission tests exercise the actual callback wiring rather than
    /// a hand-called method. With no enabled sets it always draws from the
    /// general pool, which is all these tests need.
    private func verseScheduler(
        quranRepository: QuranRepository,
        settingsStore: SettingsStore
    ) throws -> VerseScheduler {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ayah-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)

        let scheduler = VerseScheduler(
            quranRepository: quranRepository,
            memorizationRepository: try MemorizationRepository(
                databasePath: directory.appendingPathComponent("ayah_user.sqlite").path
            ),
            settingsStore: settingsStore
        )
        startedSchedulers.append(scheduler)
        return scheduler
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suiteName = "com.ayah.tests.\(UUID().uuidString)"
        defaultsSuiteNames.append(suiteName)
        return try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    // MARK: - Waiting

    /// Poll only asynchronous timer and auto-collapse outcomes.
    @discardableResult
    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func drainMainActor() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    /// Fails rather than skips on the wrong content case: a skip here
    /// would quietly turn a real regression into a green run.
    private func ayahIDs(
        of content: NotchDisplayContent,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [Int] {
        guard case .verses(let ayahs, _) = content else {
            XCTFail("Expected verse content, got \(content).", file: file, line: line)
            return []
        }
        return ayahs.map(\.id)
    }
}
