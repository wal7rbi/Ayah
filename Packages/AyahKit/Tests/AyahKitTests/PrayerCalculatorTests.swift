import Adhan
import Foundation
import XCTest
@testable import AyahKit

final class PrayerCalculatorTests: XCTestCase {
    // `Coordinates` is ambiguous between `Adhan.Coordinates` and
    // `AyahKit.Coordinates` in a file that imports both — constructed
    // inline at each `PrayerCalculator.prayerTimes(coordinates:)` call
    // site instead of as a standalone property, so the parameter's
    // declared type (`AyahKit.Coordinates`) resolves the overload.
    // (Module-qualifying as `AyahKit.Coordinates` doesn't work here
    // either: AyahKit.swift's own `public enum AyahKit` marker type
    // shadows the module name for qualified lookup within the module.)
    private let riyadhLatitude = 24.68773
    private let riyadhLongitude = 46.72185
    private let riyadhTimeZone = TimeZone(identifier: "Asia/Riyadh")!

    private func nonRamadanDate() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func ramadanDate() -> Date {
        var components = DateComponents()
        components.year = 1448
        components.month = 9
        components.day = 15
        return Calendar(identifier: .islamicUmmAlQura).date(from: components)!
    }

    func testPrayerTimesAreOrderedThroughoutTheDay() throws {
        let times = try XCTUnwrap(PrayerCalculator.prayerTimes(
            on: nonRamadanDate(), coordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            calculationMethod: .ummAlQura, asrMadhab: .shafi, timeZone: riyadhTimeZone
        ))
        XCTAssertLessThan(times.fajr, times.sunrise)
        XCTAssertLessThan(times.sunrise, times.dhuhr)
        XCTAssertLessThan(times.dhuhr, times.asr)
        XCTAssertLessThan(times.asr, times.maghrib)
        XCTAssertLessThan(times.maghrib, times.isha)
    }

    func testUmmAlQuraIshaIsNinetyMinutesAfterMaghribOutsideRamadan() throws {
        let times = try XCTUnwrap(PrayerCalculator.prayerTimes(
            on: nonRamadanDate(), coordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            calculationMethod: .ummAlQura, asrMadhab: .shafi, timeZone: riyadhTimeZone
        ))
        let minutes = times.isha.timeIntervalSince(times.maghrib) / 60
        XCTAssertEqual(minutes, 90, accuracy: 1)
    }

    /// ARCHITECTURE.md §10: Adhan Swift has no Hijri calendar awareness,
    /// so `PrayerCalculator` must detect Ramadan itself and extend Umm
    /// al-Qura's Isha interval from 90 to 120 minutes.
    func testUmmAlQuraIshaIsExtendedToOneHundredTwentyMinutesDuringRamadan() throws {
        let times = try XCTUnwrap(PrayerCalculator.prayerTimes(
            on: ramadanDate(), coordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            calculationMethod: .ummAlQura, asrMadhab: .shafi, timeZone: riyadhTimeZone
        ))
        let minutes = times.isha.timeIntervalSince(times.maghrib) / 60
        XCTAssertEqual(minutes, 120, accuracy: 1)
    }

    /// The +30 minute Ramadan extension is specifically Umm al-Qura's own
    /// civil-time convention (§10), not a generic "any fixed 90-minute
    /// Isha interval gets extended during Ramadan" rule. Qatar's method
    /// also uses a fixed 90-minute interval but must stay at 90 even
    /// during Ramadan — this would catch a bug where the Ramadan check
    /// keyed on `ishaInterval > 0` instead of `calculationMethod == .ummAlQura`.
    func testRamadanExtensionIsSpecificToUmmAlQuraNotAnyFixedIntervalMethod() throws {
        let qatarRamadan = try XCTUnwrap(PrayerCalculator.prayerTimes(
            on: ramadanDate(), coordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            calculationMethod: .qatar, asrMadhab: .shafi, timeZone: riyadhTimeZone
        ))
        let minutes = qatarRamadan.isha.timeIntervalSince(qatarRamadan.maghrib) / 60
        XCTAssertEqual(minutes, 90, accuracy: 1)
    }

    /// ARCHITECTURE.md §11: Hanafi's 2x shadow-length rule gives a later
    /// Asr time than the majority position for the same day/location.
    func testHanafiAsrIsLaterThanMajorityAsrForTheSameDayAndLocation() throws {
        let majority = try XCTUnwrap(PrayerCalculator.prayerTimes(
            on: nonRamadanDate(), coordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            calculationMethod: .karachi, asrMadhab: .shafi, timeZone: riyadhTimeZone
        ))
        let hanafi = try XCTUnwrap(PrayerCalculator.prayerTimes(
            on: nonRamadanDate(), coordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            calculationMethod: .karachi, asrMadhab: .hanafi, timeZone: riyadhTimeZone
        ))
        XCTAssertLessThan(majority.asr, hanafi.asr)
    }

    /// Regression test for the bug this `timeZone:` parameter fixes:
    /// `PrayerCalculator` used to determine "which calendar day" to
    /// compute via `Calendar(identifier: .gregorian)`'s implicit
    /// `TimeZone.current` — the Mac's *system* timezone — rather than the
    /// target location's. Builds an instant that's still June 15 at night
    /// in Riyadh but already June 16 in a system timezone 11 hours ahead
    /// (Pacific/Kiritimati, UTC+14), overrides `NSTimeZone.default` to
    /// that far-away zone for the duration of the test, and confirms the
    /// resulting Fajr still falls on June 15 in Riyadh's own calendar —
    /// proving the calculation no longer depends on the system's
    /// timezone at all.
    func testPrayerTimesUseTheSuppliedTimeZoneRegardlessOfSystemTimeZone() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        components.hour = 23
        components.minute = 30
        components.timeZone = riyadhTimeZone
        let lateNightInRiyadh = Calendar(identifier: .gregorian).date(from: components)!

        let originalSystemTimeZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "Pacific/Kiritimati")!
        defer { NSTimeZone.default = originalSystemTimeZone }

        let times = try XCTUnwrap(PrayerCalculator.prayerTimes(
            on: lateNightInRiyadh, coordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            calculationMethod: .ummAlQura, asrMadhab: .shafi, timeZone: riyadhTimeZone
        ))

        var riyadhCalendar = Calendar(identifier: .gregorian)
        riyadhCalendar.timeZone = riyadhTimeZone
        XCTAssertEqual(riyadhCalendar.component(.month, from: times.fajr), 6)
        XCTAssertEqual(riyadhCalendar.component(.day, from: times.fajr), 15)
    }

    func testRejectsInvalidCoordinatesAndUnconfiguredOtherMethod() {
        XCTAssertNil(PrayerCalculator.prayerTimes(
            on: nonRamadanDate(), coordinates: Coordinates(latitude: 91, longitude: riyadhLongitude),
            calculationMethod: .ummAlQura, asrMadhab: .shafi, timeZone: riyadhTimeZone
        ))
        XCTAssertNil(PrayerCalculator.prayerTimes(
            on: nonRamadanDate(), coordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            calculationMethod: .other, asrMadhab: .shafi, timeZone: riyadhTimeZone
        ))
        XCTAssertFalse(PrayerCalculator.supportedCalculationMethods.contains(.other))
    }

    func testEverySupportedCalculationMethodProducesOrderedRiyadhTimes() throws {
        for method in PrayerCalculator.supportedCalculationMethods {
            let times = try XCTUnwrap(PrayerCalculator.prayerTimes(
                on: nonRamadanDate(),
                coordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
                calculationMethod: method,
                asrMadhab: .shafi,
                timeZone: riyadhTimeZone
            ), "Expected usable prayer times for \(method.rawValue)")
            XCTAssertLessThan(times.fajr, times.sunrise)
            XCTAssertLessThan(times.sunrise, times.dhuhr)
            XCTAssertLessThan(times.dhuhr, times.asr)
            XCTAssertLessThan(times.asr, times.maghrib)
            XCTAssertLessThan(times.maghrib, times.isha)
        }
    }

    func testDSTBoundaryUsesTheTargetLocationsCalendarDay() throws {
        let newYork = TimeZone(identifier: "America/New_York")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        for day in [7, 8, 9] {
            let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: 12))!
            let times = try XCTUnwrap(PrayerCalculator.prayerTimes(
                on: date,
                coordinates: Coordinates(latitude: 40.7128, longitude: -74.0060),
                calculationMethod: .northAmerica,
                asrMadhab: .shafi,
                timeZone: newYork
            ))
            XCTAssertEqual(calendar.component(.day, from: times.dhuhr), day)
            XCTAssertLessThan(times.fajr, times.sunrise)
            XCTAssertLessThan(times.sunrise, times.dhuhr)
        }
    }
}
