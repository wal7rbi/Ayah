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
    private var timerSource: (any OneShotTimerToken)?
    private let timerScheduling: any OneShotTimerScheduling
    private var currentSettings: AppSettings
    private var onAlertDue: ((PrayerAlertDisplay) -> Void)?
    private var scheduleGeneration: UInt = 0
    var rearmGeneration: UInt { scheduleGeneration }

    public init(
        quranRepository: QuranRepository?,
        locationRepository: LocationRepository?,
        settingsStore: SettingsStore,
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init,
        timerScheduling: (any OneShotTimerScheduling)? = nil
    ) {
        self.quranRepository = quranRepository
        self.locationRepository = locationRepository
        self.settingsStore = settingsStore
        self.notificationCenter = notificationCenter
        self.now = now
        self.timerScheduling = timerScheduling ?? DispatchOneShotTimer()
        self.currentSettings = settingsStore.settings
    }

    public func start(onAlertDue: @escaping (PrayerAlertDisplay) -> Void) {
        guard settingsCancellable == nil else { return }
        self.onAlertDue = onAlertDue
        settingsCancellable = settingsStore.$settings
            .removeDuplicates()
            .sink { [weak self] settings in
                self?.currentSettings = settings
                self?.armNextTimer()
            }
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            notificationCenter.publisher(for: name)
                .sink { [weak self] _ in
                    Task { @MainActor in self?.rearm() }
                }
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
        currentSettings = settingsStore.settings
        armNextTimer()
    }

    private func armNextTimer() {
        let interval = PerformanceSignposts.begin("PrayerSchedulerRearm")
        defer { PerformanceSignposts.end("PrayerSchedulerRearm", interval) }
        scheduleGeneration &+= 1
        let generation = scheduleGeneration
        timerSource?.cancel()
        timerSource = nil

        guard onAlertDue != nil, currentSettings.arePrayerNotificationsEnabled,
              let location = PrayerLocationResolver.resolve(
                  settings: currentSettings,
                  locationRepository: locationRepository
              ) else { return }
        let coordinates = location.coordinates
        let timeZone = location.timeZone

        let settings = currentSettings
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

        timerSource = timerScheduling.schedule(
            after: max(1, next.fireDate.timeIntervalSince(referenceNow)), leeway: 5
        ) { [weak self] in
            guard let self, self.scheduleGeneration == generation else { return }
            let ayah = self.quranRepository?.randomAyah(searchableTextContains: Self.salahSearchSubstring)
            self.onAlertDue?(PrayerAlertDisplay(event: next, ayah: ayah))
            guard self.scheduleGeneration == generation else { return }
            self.armNextTimer()
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
