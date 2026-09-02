import XCTest
@testable import AyahKit

final class LocationRepositoryPerformanceTests: XCTestCase {
    func testPerformanceRepositoryInitializationAndChecksumVerification() throws {
        _ = try PerformanceTestSupport.makeLocationRepository()

        let directory = PerformanceTestSupport.geoNamesResourcesDirectory
        let databasePath = directory.appendingPathComponent("cities_filtered.sqlite").path
        let checksumPath = directory.appendingPathComponent("GEONAMES_CHECKSUM").path
        var errors: [Error] = []

        measure(
            metrics: [XCTClockMetric()],
            options: PerformanceTestSupport.measureOptions(iterationCount: 5)
        ) {
            do {
                _ = try LocationRepository(databasePath: databasePath, checksumPath: checksumPath)
            } catch {
                errors.append(error)
            }
        }

        XCTAssertTrue(errors.isEmpty, "Every measured initialization must succeed: \(errors)")
    }

    func testPerformanceRepresentativeEnglishAndArabicCitySearch() throws {
        let repository = try PerformanceTestSupport.makeLocationRepository()
        let cities = repository.cities()
        // Tracks `Resources/GeoNames/SOURCE.md`'s row count. It exists so a
        // shrunken or substituted fixture can't quietly make this benchmark
        // measure nothing; a re-import that legitimately changes the row
        // count is expected to update it here too.
        XCTAssertEqual(cities.count, 4_659)

        func matchingCities(for query: String) -> [City] {
            cities.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || ($0.nameArabic?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }

        // These are the same English/Arabic fields and comparison API
        // used by CityPickerView. Alternating scripts also prevents this
        // benchmark from representing only one locale-sensitive path.
        let queries = ["Riyadh", "الرياض"]
        let expectedCounts = queries.map { matchingCities(for: $0).count }
        XCTAssertTrue(expectedCounts.allSatisfy { $0 > 0 })

        func runSearchWorkload(iterationCount: Int) -> [Int] {
            var counts: [Int] = []
            counts.reserveCapacity(iterationCount)
            for index in 0..<iterationCount {
                counts.append(matchingCities(for: queries[index % queries.count]).count)
            }
            return counts
        }

        // Warm Foundation's locale-sensitive comparison machinery before
        // XCTest records samples; otherwise Release's first ICU setup can
        // dwarf the actual steady-state city-picker filtering cost.
        let workloadSize = 50
        let warmupCounts = runSearchWorkload(iterationCount: workloadSize)
        for (index, count) in warmupCounts.enumerated() {
            XCTAssertEqual(count, expectedCounts[index % expectedCounts.count])
        }
        var observedCounts: [Int] = []

        measure(metrics: [XCTClockMetric()]) {
            observedCounts = runSearchWorkload(iterationCount: workloadSize)
        }

        XCTAssertEqual(observedCounts.count, workloadSize)
        for (index, count) in observedCounts.enumerated() {
            XCTAssertEqual(count, expectedCounts[index % expectedCounts.count])
        }
    }
}
