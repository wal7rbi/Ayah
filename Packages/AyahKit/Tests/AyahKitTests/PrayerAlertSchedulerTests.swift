import Adhan
import Foundation
import XCTest
@testable import AyahKit

/// Only `PrayerAlertScheduler.prayerAlertEvents(...)` is tested here — the
/// pure "what to show" half. The actual `DispatchSourceTimer`
/// arm/fire/rearm cycle in `armNextTimer()` isn't unit-testable, the same
/// way `VerseScheduler`'s timer firing isn't.
final class PrayerAlertSchedulerTests: XCTestCase {
    // See PrayerCalculatorTests.swift for why `Coordinates` is constructed
    // inline rather than as a standalone typed property in a file that
    // also imports `Adhan`.
    private let riyadhLatitude = 24.68773
    private let riyadhLongitude = 46.72185
    private let riyadhTimeZone = "Asia/Riyadh"

    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: riyadhTimeZone)
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    func testReturnsAllFivePrayersExcludingSunriseWhenNoneHavePassed() {
        let events = PrayerAlertScheduler.prayerAlertEvents(
            for: date(year: 2026, month: 6, day: 15),
            coordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            calculationMethod: .ummAlQura,
            asrMadhab: .shafi,
            reminderMinutes: 0,
            timeZone: TimeZone(identifier: riyadhTimeZone)!,
            now: date(year: 2026, month: 6, day: 15)
        )

        let keys = Set(events.map(\.prayerKey))
        XCTAssertEqual(keys, ["fajr", "dhuhr", "asr", "maghrib", "isha"])
    }

    func testAlreadyPassedPrayersAreExcluded() throws {
        let today = date(year: 2026, month: 6, day: 15)
        let times = try XCTUnwrap(PrayerCalculator.prayerTimes(
            on: today,
            coordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            calculationMethod: .ummAlQura,
            asrMadhab: .shafi,
            timeZone: TimeZone(identifier: riyadhTimeZone)!
        ))
        // Just after Dhuhr: Fajr and Dhuhr should be filtered out, leaving
        // Asr/Maghrib/Isha.
        let justAfterDhuhr = times.dhuhr.addingTimeInterval(60)

        let events = PrayerAlertScheduler.prayerAlertEvents(
            for: today,
            coordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            calculationMethod: .ummAlQura,
            asrMadhab: .shafi,
            reminderMinutes: 0,
            timeZone: TimeZone(identifier: riyadhTimeZone)!,
            now: justAfterDhuhr
        )

        let keys = Set(events.map(\.prayerKey))
        XCTAssertEqual(keys, ["asr", "maghrib", "isha"])
    }

    func testReminderMinutesZeroProducesOnlyTheAtTimeEvent() throws {
        let today = date(year: 2026, month: 6, day: 15)

        let events = PrayerAlertScheduler.prayerAlertEvents(
            for: today,
            coordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            calculationMethod: .ummAlQura,
            asrMadhab: .shafi,
            reminderMinutes: 0,
            timeZone: TimeZone(identifier: riyadhTimeZone)!,
            now: today
        )

        // One event per prayer (5 total), all at-time.
        XCTAssertEqual(events.count, 5)
        XCTAssertTrue(events.allSatisfy { $0.offsetMinutes == 0 && !$0.isReminder })
    }

    /// The actual feature request this exists for: the at-time event
    /// always fires, and a non-zero `reminderMinutes` adds exactly one
    /// more, earlier, event on top of it — not instead of it.
    func testNonZeroReminderMinutesAddsAnEarlierEventAlongsideTheAtTimeOne() throws {
        let today = date(year: 2026, month: 6, day: 15)
        let times = try XCTUnwrap(PrayerCalculator.prayerTimes(
            on: today,
            coordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            calculationMethod: .ummAlQura,
            asrMadhab: .shafi,
            timeZone: TimeZone(identifier: riyadhTimeZone)!
        ))

        let events = PrayerAlertScheduler.prayerAlertEvents(
            for: today,
            coordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            calculationMethod: .ummAlQura,
            asrMadhab: .shafi,
            reminderMinutes: 5,
            timeZone: TimeZone(identifier: riyadhTimeZone)!,
            now: today
        )

        let maghribEvents = events.filter { $0.prayerKey == "maghrib" }
        XCTAssertEqual(maghribEvents.count, 2)

        let onTime = try XCTUnwrap(maghribEvents.first { $0.offsetMinutes == 0 })
        let fiveBefore = try XCTUnwrap(maghribEvents.first { $0.offsetMinutes == 5 })
        XCTAssertEqual(onTime.fireDate, times.maghrib)
        XCTAssertFalse(onTime.isReminder)
        XCTAssertEqual(fiveBefore.fireDate, times.maghrib.addingTimeInterval(-5 * 60))
        XCTAssertTrue(fiveBefore.isReminder)
        // All five prayers × two events each, none of which have passed yet.
        XCTAssertEqual(events.count, 10)
    }

    func testEventsForTomorrowFireApproximatelyOneDayAfterToday() {
        let day1 = PrayerAlertScheduler.prayerAlertEvents(
            for: date(year: 2026, month: 6, day: 15),
            coordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            calculationMethod: .ummAlQura,
            asrMadhab: .shafi,
            reminderMinutes: 0,
            timeZone: TimeZone(identifier: riyadhTimeZone)!,
            now: date(year: 2026, month: 6, day: 15)
        )
        let day2 = PrayerAlertScheduler.prayerAlertEvents(
            for: date(year: 2026, month: 6, day: 16),
            coordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            calculationMethod: .ummAlQura,
            asrMadhab: .shafi,
            reminderMinutes: 0,
            timeZone: TimeZone(identifier: riyadhTimeZone)!,
            now: date(year: 2026, month: 6, day: 15)
        )

        let day1ByKey = Dictionary(uniqueKeysWithValues: day1.map { ($0.prayerKey, $0) })
        let day2ByKey = Dictionary(uniqueKeysWithValues: day2.map { ($0.prayerKey, $0) })

        for key in day1ByKey.keys {
            let delta = day2ByKey[key]!.fireDate.timeIntervalSince(day1ByKey[key]!.fireDate)
            XCTAssertEqual(delta, 86400, accuracy: 120)
        }
    }
}
