import Adhan
import Combine
import Dispatch
import Foundation

/// Drives the in-notch prayer-alert popup: a reminder `N` minutes before
/// each prayer (`AppSettings.prayerNotificationReminderMinutes`, `0` means
/// no separate reminder) and an at-time alert, for Fajr/Dhuhr/Asr/Maghrib/
/// Isha (sunrise excluded — it isn't a prayer). Replaces the deleted
/// `UNUserNotificationCenter`-based `PrayerNotificationScheduler`: alerts
/// are now shown entirely in-process, in the notch, mirroring the existing
/// verse-display popup rather than an OS notification banner. There is no
/// OS handoff anymore, so — unlike the deleted scheduler, which only
/// self-timed a local-midnight rollover and let `UNCalendarNotificationTrigger`
/// fire everything else — this type must self-time every individual
/// reminder/at-time moment while the app is running: `armNextTimer()`
/// always arms exactly one `DispatchSourceTimer` for the single soonest
/// upcoming event (today + tomorrow, recomputed fresh each time), firing
/// it and immediately rearming for the next.
///
/// `@MainActor` for the same reason `PrayerNotificationScheduler` was:
/// `settingsStore.$settings` fires on the main thread and the self-rearming
/// timer runs on the main queue by construction.
@MainActor
public final class PrayerAlertScheduler {
    private static let salahSearchSubstring = "الصلاة"

    private let quranRepository: QuranRepository?
    private let locationRepository: LocationRepository?
    private let settingsStore: SettingsStore
    private let now: () -> Date
    private let notificationCenter: NotificationCenter

    private var settingsCancellable: AnyCancellable?
    private var systemChangeCancellables: Set<AnyCancellable> = []
    private var timerSource: DispatchSourceTimer?
    private var onAlertDue: ((PrayerAlertDisplay) -> Void)?
    private var scheduleGeneration: UInt = 0
    var rearmGeneration: UInt { scheduleGeneration }

    public init(
        quranRepository: QuranRepository?,
        locationRepository: LocationRepository?,
        settingsStore: SettingsStore,
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.quranRepository = quranRepository
        self.locationRepository = locationRepository
        self.settingsStore = settingsStore
        self.notificationCenter = notificationCenter
        self.now = now
    }

    public func start(onAlertDue: @escaping (PrayerAlertDisplay) -> Void) {
        guard settingsCancellable == nil else { return }
        self.onAlertDue = onAlertDue
        settingsCancellable = settingsStore.$settings
            .removeDuplicates()
            .sink { [weak self] _ in self?.armNextTimer() }
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            notificationCenter.publisher(for: name)
                .sink { [weak self] _ in self?.armNextTimer() }
                .store(in: &systemChangeCancellables)
        }
    }

    public func stop() {
        settingsCancellable = nil
        systemChangeCancellables.removeAll()
        scheduleGeneration &+= 1
        timerSource?.cancel()
        timerSource = nil
        onAlertDue = nil
    }

    /// Re-arms against the current soonest event. Exposed for
    /// `NotchController` to call on `NSWorkspace.didWakeNotification` —
    /// the one edge case a purely event-driven, no-midnight-timer design
    /// doesn't otherwise cover: an already-armed timer's deadline passing
    /// while the Mac was asleep.
    public func rearm() {
        armNextTimer()
    }

    private func armNextTimer() {
        let interval = PerformanceSignposts.begin("PrayerSchedulerRearm")
        defer { PerformanceSignposts.end("PrayerSchedulerRearm", interval) }
        scheduleGeneration &+= 1
        let generation = scheduleGeneration
        timerSource?.cancel()
        timerSource = nil

        guard settingsStore.settings.arePrayerNotificationsEnabled,
              let (coordinates, timeZone) = resolveLocation() else { return }

        let settings = settingsStore.settings
        let referenceNow = now()
        var tomorrowCalendar = Calendar.current
        tomorrowCalendar.timeZone = timeZone
        let tomorrow = tomorrowCalendar.date(byAdding: .day, value: 1, to: referenceNow)
            ?? referenceNow.addingTimeInterval(86400)

        let events = (
            Self.prayerAlertEvents(
                for: referenceNow,
                coordinates: coordinates,
                calculationMethod: settings.prayerCalculationMethod,
                asrMadhab: settings.asrMadhab,
                reminderMinutes: min(180, max(0, settings.prayerNotificationReminderMinutes)),
                timeZone: timeZone,
                now: referenceNow
            ) + Self.prayerAlertEvents(
                for: tomorrow,
                coordinates: coordinates,
                calculationMethod: settings.prayerCalculationMethod,
                asrMadhab: settings.asrMadhab,
                reminderMinutes: min(180, max(0, settings.prayerNotificationReminderMinutes)),
                timeZone: timeZone,
                now: referenceNow
            )
        ).sorted { $0.fireDate < $1.fireDate }

        guard let next = events.first else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + max(1, next.fireDate.timeIntervalSince(referenceNow)), leeway: .seconds(5))
        timer.setEventHandler { [weak self] in
            guard let self, self.scheduleGeneration == generation else { return }
            let ayah = self.quranRepository?.randomAyah(searchableTextContains: Self.salahSearchSubstring)
            self.onAlertDue?(PrayerAlertDisplay(event: next, ayah: ayah))
            self.armNextTimer()
        }
        timer.resume()
        timerSource = timer
    }

    /// Same city/current-location switch `PrayerNotificationScheduler`
    /// used (and, before that, `PopoverContentView`'s live prayer-time
    /// preview) — duplicated here rather than shared, matching that
    /// file's own precedent. Now also resolves a `TimeZone` alongside
    /// `Coordinates`: `PrayerCalculator.prayerTimes(...)` requires the
    /// target location's zone (not the Mac's system zone) to compute the
    /// correct calendar day — see ARCHITECTURE.md §9's "Update". A
    /// selected city carries its own IANA zone; current-location uses the
    /// system IANA zone captured with the one-shot coordinates.
    private func resolveLocation() -> (coordinates: Coordinates, timeZone: TimeZone)? {
        switch settingsStore.settings.prayerLocationSource {
        case .city:
            guard let id = settingsStore.settings.selectedCityID,
                  let city = locationRepository?.city(id: id),
                  let timeZone = TimeZone(identifier: city.timeZoneIdentifier) else { return nil }
            return (city.coordinates, timeZone)
        case .currentLocation:
            guard let coordinates = settingsStore.settings.currentLocationCoordinates else { return nil }
            let identifier = settingsStore.settings.currentLocationTimeZoneIdentifier
                ?? TimeZone.current.identifier
            guard let timeZone = TimeZone(identifier: identifier) else { return nil }
            return (coordinates, timeZone)
        }
    }

    /// Pure and synchronous — the "what to show" half, fully testable
    /// without any timer/settings/repository involved. Always produces an
    /// at-time event (offset `0`) per prayer, plus one more `reminderMinutes`
    /// earlier when `reminderMinutes > 0`; any event whose `fireDate` has
    /// already passed relative to `now` is skipped.
    public nonisolated static func prayerAlertEvents(
        for date: Date,
        coordinates: Coordinates,
        calculationMethod: CalculationMethod,
        asrMadhab: Madhab,
        reminderMinutes: Int,
        timeZone: TimeZone,
        now: Date
    ) -> [PrayerAlertEvent] {
        guard let times = PrayerCalculator.prayerTimes(
            on: date,
            coordinates: coordinates,
            calculationMethod: calculationMethod,
            asrMadhab: asrMadhab,
            timeZone: timeZone
        ) else { return [] }

        let prayers: [(key: String, time: Date)] = [
            ("fajr", times.fajr),
            ("dhuhr", times.dhuhr),
            ("asr", times.asr),
            ("maghrib", times.maghrib),
            ("isha", times.isha),
        ]
        var offsets: Set<Int> = [0]
        if reminderMinutes > 0 {
            offsets.insert(reminderMinutes)
        }

        return prayers.flatMap { prayer in
            offsets.sorted().compactMap { offsetMinutes -> PrayerAlertEvent? in
                let fireDate = prayer.time.addingTimeInterval(-TimeInterval(offsetMinutes) * 60)
                guard fireDate > now else { return nil }
                return PrayerAlertEvent(
                    prayerKey: prayer.key,
                    fireDate: fireDate,
                    offsetMinutes: offsetMinutes
                )
            }
        }
    }
}
