import XCTest
@testable import AyahKit

final class QuranRepositoryPerformanceTests: XCTestCase {
    func testPerformanceRepositoryInitializationAndIntegrityVerification() throws {
        _ = try PerformanceTestSupport.makeQuranRepository()

        let directory = PerformanceTestSupport.quranResourcesDirectory
        let databasePath = directory.appendingPathComponent("quran.sqlite").path
        let checksumPath = directory.appendingPathComponent("CHECKSUM").path
        var errors: [Error] = []

        measure(
            metrics: [XCTClockMetric()],
            options: PerformanceTestSupport.measureOptions(iterationCount: 5)
        ) {
            do {
                _ = try QuranRepository(databasePath: databasePath, checksumPath: checksumPath)
            } catch {
                errors.append(error)
            }
        }

        XCTAssertTrue(errors.isEmpty, "Every measured initialization must succeed: \(errors)")
    }

    func testPerformanceFixedAyahLookups() throws {
        let repository = try PerformanceTestSupport.makeQuranRepository()
        let ids = [1, 7, 255, 1_234, 3_333, 6_236]
        XCTAssertEqual(ids.compactMap(repository.ayah(id:)).count, ids.count)
        var checksum = 0

        measure(metrics: [XCTClockMetric()]) {
            for index in 0..<1_000 {
                checksum &+= repository.ayah(id: ids[index % ids.count])?.id ?? 0
            }
        }

        XCTAssertGreaterThan(checksum, 0)
    }
}
