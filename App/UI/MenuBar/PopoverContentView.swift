import Adhan
import AyahKit
import ServiceManagement
import SwiftUI

/// The Settings UI (ARCHITECTURE.md's "Settings UI" build stage): edits
/// the shared `SettingsStore` that `VerseScheduler`/`PrayerCalculator`
/// already read live, so changes here take effect without a relaunch.
/// Text and layout are Arabic/RTL throughout, matching the app's primary
/// audience — there is no separate English variant to maintain. Also the
/// app's only interaction surface on Macs without a notch (see
/// ARCHITECTURE.md §4) — verse content itself still isn't shown there (a
/// separate, deliberate gap tracked outside this stage).
struct PopoverContentView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var locationViewModel: CurrentLocationViewModel
    @ObservedObject var launchAtLoginViewModel: LaunchAtLoginViewModel
    /// `nil` when memorization data failed to load this launch — see
    /// `StatusItemController`.
    var onManageMemorizationSets: (() -> Void)?
    /// `nil` when GeoNames data failed to load this launch — see
    /// `StatusItemController`.
    var onSelectCity: (() -> Void)?
    var locationRepository: LocationRepository?

    /// Human-labeled presets for `displayInterval` — a raw seconds field
    /// isn't a friendly control for this.
    private static let intervalPresets: [(label: String, seconds: TimeInterval)] = [
        ("15 دقيقة", 900), ("30 دقيقة", 1800), ("ساعة واحدة", 3600),
        ("ساعتان", 7200), ("3 ساعات", 10800)
    ]

    private static let calculationMethodLabels: [CalculationMethod: String] = [
        .muslimWorldLeague: "رابطة العالم الإسلامي",
        .egyptian: "الهيئة المصرية العامة للمساحة",
        .karachi: "جامعة العلوم الإسلامية، كراتشي",
        .ummAlQura: "أم القرى (مكة المكرمة)",
        .dubai: "دبي",
        .moonsightingCommittee: "لجنة رؤية الهلال",
        .northAmerica: "أمريكا الشمالية (ISNA)",
        .kuwait: "الكويت",
        .qatar: "قطر",
        .singapore: "سنغافورة",
        .tehran: "طهران",
        .turkey: "تركيا (ديانت)",
        .other: "أخرى",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("آية")
                    .font(.headline)

                Toggle("عرض الآيات في طرف الشاشة", isOn: $settingsStore.settings.isVerseDisplayEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    Picker("الفاصل الزمني", selection: intervalBinding) {
                        ForEach(Self.intervalPresets, id: \.seconds) { preset in
                            Text(preset.label).tag(preset.seconds)
                        }
                    }

                    Stepper(
                        "عدد الآيات لكل عرض: \(settingsStore.settings.versesPerDisplay)",
                        value: $settingsStore.settings.versesPerDisplay,
                        in: 1...5
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Stepper(
                            "نسبة آيات الحفظ: \(settingsStore.settings.memorizationWeightPercent)%",
                            value: $settingsStore.settings.memorizationWeightPercent,
                            in: 0...100,
                            step: 5
                        )
                        Text("احتمال اختيار الآية من مجموعات الحفظ بدلاً من القرآن كاملاً.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .disabled(!settingsStore.settings.isVerseDisplayEnabled)
                .opacity(settingsStore.settings.isVerseDisplayEnabled ? 1 : 0.5)

                if let onManageMemorizationSets {
                    Button("إدارة مجموعات الحفظ", action: onManageMemorizationSets)
                }

                Divider()
                prayerSection

                Divider()
                generalSection

                Divider()
                Button("إغلاق آية") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(16)
        }
        .frame(width: 320, height: 620)
        .environment(\.layoutDirection, .rightToLeft)
        .multilineTextAlignment(.trailing)
    }

    private var prayerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("أوقات الصلاة")
                .font(.headline)

            Picker("طريقة الحساب", selection: $settingsStore.settings.prayerCalculationMethod) {
                ForEach(CalculationMethod.allCases, id: \.self) { method in
                    Text(Self.calculationMethodLabels[method] ?? method.rawValue).tag(method)
                }
            }

            Picker("حساب العصر", selection: $settingsStore.settings.asrMadhab) {
                Text("قياسي").tag(Madhab.shafi)
                Text("حنفي").tag(Madhab.hanafi)
            }

            Picker("مصدر الموقع", selection: $settingsStore.settings.prayerLocationSource) {
                Text("مدينة").tag(PrayerLocationSource.city)
                Text("الموقع الحالي").tag(PrayerLocationSource.currentLocation)
            }
            .pickerStyle(.segmented)

            switch settingsStore.settings.prayerLocationSource {
            case .city:
                cityRow
            case .currentLocation:
                currentLocationRow
            }

            if let times = todaysPrayerTimes {
                VStack(alignment: .leading, spacing: 3) {
                    prayerRow("الفجر", times.fajr, in: activeTimeZoneIdentifier)
                    prayerRow("الشروق", times.sunrise, in: activeTimeZoneIdentifier)
                    prayerRow("الظهر", times.dhuhr, in: activeTimeZoneIdentifier)
                    prayerRow("العصر", times.asr, in: activeTimeZoneIdentifier)
                    prayerRow("المغرب", times.maghrib, in: activeTimeZoneIdentifier)
                    prayerRow("العشاء", times.isha, in: activeTimeZoneIdentifier)
                }
                .font(.caption)
                .padding(.top, 2)
            } else {
                Text(settingsStore.settings.prayerLocationSource == .city
                     ? "اختر مدينة لعرض أوقات الصلاة"
                     : "حدد موقعك الحالي لعرض أوقات الصلاة")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()
            notificationsRow
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("عام")
                .font(.headline)

            Toggle("بدء التشغيل مع تسجيل الدخول", isOn: launchAtLoginBinding)

            if case .requiresApproval = launchAtLoginViewModel.status {
                VStack(alignment: .leading, spacing: 4) {
                    Text("يتطلب هذا موافقتك من إعدادات النظام.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("فتح إعدادات تسجيل الدخول", action: launchAtLoginViewModel.openSystemSettingsLoginItems)
                }
            }

            if let errorMessage = launchAtLoginViewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginViewModel.isEnabled },
            set: { launchAtLoginViewModel.setEnabled($0) }
        )
    }

    /// A notification always fires at each prayer's exact time; this
    /// dropdown picks at most one *additional*, earlier reminder on top
    /// of it (single-select, not checkboxes) — `0` means no extra
    /// reminder.
    private static let reminderMinutesPresets: [(label: String, minutes: Int)] = [
        ("بدون", 0), ("5 دقائق", 5), ("10 دقائق", 10), ("15 دقيقة", 15)
    ]

    private var notificationsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("تنبيه أوقات الصلاة", isOn: $settingsStore.settings.arePrayerNotificationsEnabled)

            if settingsStore.settings.arePrayerNotificationsEnabled {
                Picker("تذكير إضافي قبل الصلاة بـ", selection: $settingsStore.settings.prayerNotificationReminderMinutes) {
                    ForEach(Self.reminderMinutesPresets, id: \.minutes) { preset in
                        Text(preset.label).tag(preset.minutes)
                    }
                }
            }
        }
    }

    private var cityRow: some View {
        HStack {
            Text("المدينة")
            Spacer()
            Text(selectedCity?.displayName ?? "لم يتم الاختيار")
                .foregroundStyle(.secondary)
            if let onSelectCity {
                Button("تغيير", action: onSelectCity)
            }
        }
    }

    private var currentLocationRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if locationViewModel.isFetching {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(settingsStore.settings.currentLocationCoordinates == nil ? "استخدام الموقع الحالي" : "تحديث الموقع الحالي") {
                    Task { await locationViewModel.fetchCurrentLocation() }
                }
                .disabled(locationViewModel.isFetching)
            }

            if let fetchedAt = settingsStore.settings.currentLocationFetchedAt {
                Text("آخر تحديث: \(Self.formattedTimestamp(fetchedAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = locationViewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Text("آية نفسه لا يتصل بالإنترنت أبدًا. لكن تحديد موقعك تقوم به macOS عبر شبكات Wi-Fi القريبة (أجهزة Mac لا تحتوي على GPS)، وقد يتطلب ذلك اتصالاً بالإنترنت من خارج التطبيق تمامًا. يتم الطلب مرة واحدة فقط عند الضغط على الزر، ويُحفظ الموقع على جهازك حتى تحدّثه يدويًا.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func prayerRow(_ label: String, _ date: Date, in timeZoneIdentifier: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(Self.formattedTime(date, timeZoneIdentifier: timeZoneIdentifier))
                .foregroundStyle(.secondary)
        }
    }

    private var selectedCity: City? {
        guard let id = settingsStore.settings.selectedCityID else { return nil }
        return locationRepository?.city(id: id)
    }

    /// A bundled city carries its own IANA timezone; a raw current-location
    /// fix doesn't (no reverse-geocoding — see `CurrentLocationProvider`'s
    /// offline note), so that case falls back to the Mac's own system
    /// timezone, which is already known locally with no lookup needed.
    private var activeTimeZoneIdentifier: String {
        switch settingsStore.settings.prayerLocationSource {
        case .city:
            return selectedCity?.timeZoneIdentifier ?? TimeZone.current.identifier
        case .currentLocation:
            return TimeZone.current.identifier
        }
    }

    /// `AyahKit.Coordinates` is ambiguous with `Adhan.Coordinates` in this
    /// file (both modules are imported) and can't be module-qualified —
    /// see the `AyahKit.swift` marker-enum note in the Architecture
    /// section of CLAUDE.md / `PrayerCalculatorTests.swift`. Resolving
    /// `coordinates` from a `let` here (rather than a separately
    /// `Coordinates`-typed property) lets inference carry the concrete
    /// type through without ever spelling the ambiguous name.
    private var todaysPrayerTimes: Adhan.PrayerTimes? {
        let timeZone = TimeZone(identifier: activeTimeZoneIdentifier) ?? .current
        switch settingsStore.settings.prayerLocationSource {
        case .city:
            guard let coordinates = selectedCity?.coordinates else { return nil }
            return PrayerCalculator.prayerTimes(
                on: Date(),
                coordinates: coordinates,
                calculationMethod: settingsStore.settings.prayerCalculationMethod,
                asrMadhab: settingsStore.settings.asrMadhab,
                timeZone: timeZone
            )
        case .currentLocation:
            guard let coordinates = settingsStore.settings.currentLocationCoordinates else { return nil }
            return PrayerCalculator.prayerTimes(
                on: Date(),
                coordinates: coordinates,
                calculationMethod: settingsStore.settings.prayerCalculationMethod,
                asrMadhab: settingsStore.settings.asrMadhab,
                timeZone: timeZone
            )
        }
    }

    private static func formattedTime(_ date: Date, timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier)
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Snaps `displayInterval` to the nearest preset for display; setting
    /// it writes the exact preset value back.
    private var intervalBinding: Binding<TimeInterval> {
        Binding(
            get: {
                let current = settingsStore.settings.displayInterval
                return Self.intervalPresets.min { abs($0.seconds - current) < abs($1.seconds - current) }?.seconds ?? current
            },
            set: { settingsStore.settings.displayInterval = $0 }
        )
    }
}
