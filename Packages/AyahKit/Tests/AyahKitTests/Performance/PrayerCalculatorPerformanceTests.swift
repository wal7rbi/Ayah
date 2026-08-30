import Adhan
import Foundation
import XCTest
@testable import AyahKit

final class PrayerCalculatorPerformanceTests: XCTestCase {
    func testPerformanceRepresentativeAnnualPrayerCalculations() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Riyadh"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12)))
        let dates = try (0..<365).map { dayOffset in
            try XCTUnwrap(calendar.date(byAdding: .day, value: dayOffset, to: firstDay))
        }
        let latitude = 24.68773
        let longitude = 46.72185
        let methods = PrayerCalculator.supportedCalculationMethods

        // Riyadh is the app's primary representative location. Exercising
        // every civil day in 2026 covers seasonal and Ramadan branches;
        // the correctness suite separately covers DST/high-latitude cases.
        for date in dates {
            for method in methods {
                XCTAssertNotNil(PrayerCalculator.prayerTimes(
                    on: date,
                    coordinates: Coordinates(latitude: latitude, longitude: longitude),
                    calculationMethod: method,
                    asrMadhab: .shafi,
                    timeZone: timeZone
                ))
            }
        }

        var resultCount = 0
        measure(metrics: [XCTClockMetric()]) {
            var count = 0
            for date in dates {
                for method in methods {
                    if PrayerCalculator.prayerTimes(
                        on: date,
                        coordinates: Coordinates(latitude: latitude, longitude: longitude),
                        calculationMethod: method,
                        asrMadhab: .shafi,
                        timeZone: timeZone
                    ) != nil {
                        count += 1
                    }
                }
            }
            resultCount = count
        }

        XCTAssertEqual(resultCount, dates.count * methods.count)
    }
}
