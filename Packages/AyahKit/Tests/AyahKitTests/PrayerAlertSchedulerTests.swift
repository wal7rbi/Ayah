import Adhan
import Foundation
import XCTest
@testable import AyahKit

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

    @MainActor
    func testClockAndTimeZoneChangesRearmTheScheduler() async throws {
        let center = NotificationCenter()
        let scheduler = PrayerAlertScheduler(
            quranRepository: nil,
            locationRepository: nil,
            settingsStore: SettingsStore(defaults: try isolatedDefaults()),
            notificationCenter: center
        )
        scheduler.start { _ in }
        let initial = scheduler.rearmGeneration

        center.post(name: .NSSystemClockDidChange, object: nil)
        await Task.yield()
        XCTAssertEqual(scheduler.rearmGeneration, initial + 1)
        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await Task.yield()
        XCTAssertEqual(scheduler.rearmGeneration, initial + 2)

        scheduler.stop()
        let stopped = scheduler.rearmGeneration
        center.post(name: .NSSystemClockDidChange, object: nil)
        await Task.yield()
        XCTAssertEqual(scheduler.rearmGeneration, stopped)
    }

    @MainActor
    func testSettingsChangesUsePublishedSnapshotAndCancelledCallbacksDoNotFire() throws {
        let settingsStore = SettingsStore(defaults: try isolatedDefaults())
        settingsStore.settings = AppSettings(
            prayerLocationSource: .currentLocation,
            currentLocationCoordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            currentLocationTimeZoneIdentifier: riyadhTimeZone,
            prayerNotificationReminderMinutes: 0
        )
        let referenceNow = date(year: 2026, month: 6, day: 15)
        let timer = ManualOneShotTimer()
        let scheduler = PrayerAlertScheduler(
            quranRepository: nil, locationRepository: nil, settingsStore: settingsStore,
            now: { referenceNow }, timerScheduling: timer
        )
        var alerts: [PrayerAlertDisplay] = []
        scheduler.start { alerts.append($0) }
        XCTAssertTrue(timer.entries.isEmpty)
        settingsStore.settings.arePrayerNotificationsEnabled = true
        XCTAssertEqual(timer.entries.count, 1)
        let first = try XCTUnwrap(timer.entries.last)
        settingsStore.settings.prayerNotificationReminderMinutes = 15
        let reminder = try XCTUnwrap(timer.entries.last)
        XCTAssertEqual(reminder.interval, first.interval - 900, accuracy: 0.01)
        XCTAssertTrue(first.isCancelled)
        first.fire()
        XCTAssertTrue(alerts.isEmpty)
        settingsStore.settings.arePrayerNotificationsEnabled = false
        XCTAssertTrue(reminder.isCancelled)
        let count = timer.entries.count
        reminder.fire()
        XCTAssertTrue(alerts.isEmpty)
        XCTAssertEqual(timer.entries.count, count)
        settingsStore.settings.arePrayerNotificationsEnabled = true
        let latest = try XCTUnwrap(timer.entries.last)
        scheduler.stop()
        latest.fire()
        scheduler.rearm()
        XCTAssertTrue(alerts.isEmpty)
        XCTAssertEqual(timer.entries.count, count + 1)
    }

    @MainActor
    func testChangingLocationAndCalculationMethodRecomputesDeadlineImmediately() throws {
        let settingsStore = SettingsStore(defaults: try isolatedDefaults())
        settingsStore.settings = AppSettings(
            prayerLocationSource: .currentLocation,
            currentLocationCoordinates: Coordinates(latitude: riyadhLatitude, longitude: riyadhLongitude),
            currentLocationTimeZoneIdentifier: riyadhTimeZone,
            arePrayerNotificationsEnabled: true, prayerNotificationReminderMinutes: 0
        )
        let referenceNow = date(year: 2026, month: 6, day: 15)
        let timer = ManualOneShotTimer()
        let scheduler = PrayerAlertScheduler(
            quranRepository: nil, locationRepository: nil, settingsStore: settingsStore,
            now: { referenceNow }, timerScheduling: timer
        )
        scheduler.start { _ in }
        defer { scheduler.stop() }
        var updated = settingsStore.settings
        updated.currentLocationCoordinates = Coordinates(latitude: 21.4225, longitude: 39.8262)
        updated.prayerCalculationMethod = .northAmerica
        settingsStore.settings = updated
        let expected = try XCTUnwrap(PrayerAlertScheduler.prayerAlertEvents(
            for: referenceNow, coordinates: updated.currentLocationCoordinates!,
            calculationMethod: .northAmerica, asrMadhab: updated.asrMadhab,
            reminderMinutes: 0, timeZone: TimeZone(identifier: riyadhTimeZone)!, now: referenceNow
        ).min { $0.fireDate < $1.fireDate })
        XCTAssertEqual(try XCTUnwrap(timer.entries.last).interval,
                       expected.fireDate.timeIntervalSince(referenceNow), accuracy: 0.01)
        XCTAssertEqual(timer.entries.count, 2)
    }

    private func isolatedDefaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "com.ayah.scheduler-tests.\(UUID().uuidString)"))
    }
}
