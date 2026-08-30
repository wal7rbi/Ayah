import Foundation
import XCTest
@testable import AyahKit

final class VerseSchedulerPerformanceTests: XCTestCase {
    func testPerformanceDeterministicMemorizationSelection() throws {
        let fixture = try PerformanceTestSupport.makeMemorizationRepository()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        _ = try fixture.repository.create(
            surahNumber: 2,
            startAyah: 1,
            endAyah: 286,
            repetitionMode: .random
        )

        let suiteName = "com.ayah.performance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = SettingsStore(defaults: defaults)
        settingsStore.settings = AppSettings(versesPerDisplay: 5, memorizationWeightPercent: 100)

        let scheduler = VerseScheduler(
            quranRepository: try PerformanceTestSupport.makeQuranRepository(),
            memorizationRepository: fixture.repository,
            settingsStore: settingsStore,
            randomDouble: { 0 },
            randomInt: { $0.lowerBound }
        )
        XCTAssertEqual(scheduler.selectNextVerses().map(\.ayahNumber), [1, 2, 3, 4, 5])
        var selectedCount = 0

        measure(metrics: [XCTClockMetric()]) {
            var count = 0
            for _ in 0..<1_000 {
                count += scheduler.selectNextVerses().count
            }
            selectedCount = count
        }

        XCTAssertEqual(selectedCount, 5_000)
        XCTAssertNil(scheduler.lastCursorUpdateError)
    }
}
