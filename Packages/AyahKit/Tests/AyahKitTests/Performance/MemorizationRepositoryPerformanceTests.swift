import Foundation
import XCTest
@testable import AyahKit

final class MemorizationRepositoryPerformanceTests: XCTestCase {
    func testPerformanceFetchingPersistedSets() throws {
        let fixture = try PerformanceTestSupport.makeMemorizationRepository()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        for index in 0..<1_000 {
            let ayah = (index % 286) + 1
            _ = try fixture.repository.create(
                surahNumber: 2,
                startAyah: ayah,
                endAyah: ayah,
                repetitionMode: index.isMultiple(of: 2) ? .sequential : .random,
                isEnabled: !index.isMultiple(of: 3)
            )
        }
        XCTAssertEqual(fixture.repository.fetchAll().count, 1_000)
        XCTAssertEqual(fixture.repository.fetchEnabled().count, 666)
        XCTAssertNil(fixture.repository.lastFetchError)
        var allCount = 0
        var enabledCount = 0

        measure(metrics: [XCTClockMetric()]) {
            allCount = fixture.repository.fetchAll().count
            enabledCount = fixture.repository.fetchEnabled().count
        }

        XCTAssertEqual(allCount, 1_000)
        XCTAssertEqual(enabledCount, 666)
        XCTAssertNil(fixture.repository.lastFetchError)
    }

    func testPerformanceCursorUpdates() throws {
        // Keep this microbenchmark in memory so filesystem journaling and
        // host-disk contention do not dominate the repository's SQL work.
        let repository = try MemorizationRepository(databasePath: ":memory:")
        let set = try repository.create(surahNumber: 2, startAyah: 1, endAyah: 286)

        var errors: [Error] = []
        measure(metrics: [XCTClockMetric()]) {
            do {
                for index in 0..<1_000 {
                    try repository.updateCursor(id: set.id, cursorAyah: (index % 286) + 1)
                }
            } catch {
                errors.append(error)
            }
        }

        XCTAssertTrue(errors.isEmpty, "Every measured cursor-update batch must succeed: \(errors)")
        XCTAssertEqual(repository.fetchAll().first?.cursorAyah, 142)
    }
}
