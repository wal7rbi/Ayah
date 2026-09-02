import Adhan
import AyahKit
import ServiceManagement
import SwiftUI

/// The Settings UI (ARCHITECTURE.md's "Settings UI" build stage): edits
/// the shared `SettingsStore` that `VerseScheduler`/`PrayerCalculator`
/// already read live, so changes here take effect without a relaunch.
/// Text and layout are Arabic/RTL throughout, matching the app's primary
/// audience — there is no separate English variant to maintain. The
/// leading last-shown card is also the persistent replay surface on every
/// Mac, including machines using the non-notch fallback panel.
struct PopoverContentView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var lastShownStore: LastShownStore
    @ObservedObject var locationViewModel: CurrentLocationViewModel
    @ObservedObject var launchAtLoginViewModel: LaunchAtLoginViewModel
    /// `nil` when memorization data failed to load this launch — see
    /// `StatusItemController`.
    var onManageMemorizationSets: (() -> Void)?
    /// `nil` when GeoNames data failed to load this launch — see
    /// `StatusItemController`.
    var onSelectCity: (() -> Void)?
    var onReplayLastShown: () -> Void
    var onShowAbout: () -> Void
    var locationRepository: LocationRepository?
    var quranRepository: QuranRepository?

    private static let arabicFontName = "kfgqpchafsuthmanicscript-Reg"

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
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let lastShownContent {
                        lastShownSection(content: lastShownContent)
                        Divider()
                    }

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
                }
                .padding(16)
            }

            Divider()

            HStack {
                Button("حول التطبيق", action: onShowAbout)
                Spacer()
                Button("إغلاق آية") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(12)
        }
        .frame(width: PopoverMetrics.contentSize.width, height: PopoverMetrics.contentSize.height)
        .environment(\.layoutDirection, .rightToLeft)
        .multilineTextAlignment(.trailing)
    }

    private var lastShownContent: NotchDisplayContent? {
        NotchDisplayContent.resolve(
            lastShownStore.record,
            quranRepository: quranRepository
        )
    }

    @ViewBuilder
    private func lastShownSection(content: NotchDisplayContent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("آخر ما ظهر")
                    .font(.headline)
                Spacer()
                if let shownAt = lastShownStore.record?.shownAt {
                    Text(Self.relativeTimestamp(shownAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            switch content {
            case .none:
                EmptyView()
            case .verses(let ayahs, let surah):
                Text(ayahs.map(\.uthmanicText).joined(separator: " "))
                    .font(.custom(Self.arabicFontName, size: 18))
                    .lineLimit(5)
                    .minimumScaleFactor(0.6)
                Text(Self.reference(for: ayahs, surah: surah))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .prayerAlert(let event, let ayah, let surah):
                Text("صلاة \(event.prayerNameArabic)")
                    .font(.subheadline.weight(.semibold))
                Text(Self.prayerAlertMessage(for: event))
                    .font(.caption)
                if let ayah {
                    Text(ayah.uthmanicText)
                        .font(.custom(Self.arabicFontName, size: 17))
                        .lineLimit(4)
                        .minimumScaleFactor(0.6)
                    Text(Self.reference(for: [ayah], surah: surah))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("إعادة العرض", action: onReplayLastShown)
        }
    }

    private static func relativeTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func prayerAlertMessage(for event: PrayerAlertEvent) -> String {
        event.isReminder
            ? "توضأ واستعد.. باقي \(event.offsetMinutes) دقائق على الأذان"
            : "حان الآن وقت صلاة \(event.prayerNameArabic)"
    }

    private static func reference(for ayahs: [QuranAyah], surah: Surah?) -> String {
        guard let first = ayahs.first, let last = ayahs.last else { return "" }
        let range = first.ayahNumber == last.ayahNumber
            ? "\(first.ayahNumber)"
            : "\(first.ayahNumber)-\(last.ayahNumber)"
        return "\(surah?.nameArabic ?? String(first.surahNumber)) — \(range)"
    }

    private var prayerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("أوقات الصلاة")
                .font(.headline)

            Picker("طريقة الحساب", selection: $settingsStore.settings.prayerCalculationMethod) {
                ForEach(PrayerCalculator.supportedCalculationMethods, id: \.self) { method in
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

            if let location = resolvedLocation, let times = todaysPrayerTimes(at: location) {
                VStack(alignment: .leading, spacing: 3) {
                    prayerRow("الفجر", times.fajr, in: location.timeZone)
                    prayerRow("الشروق", times.sunrise, in: location.timeZone)
                    prayerRow("الظهر", times.dhuhr, in: location.timeZone)
                    prayerRow("العصر", times.asr, in: location.timeZone)
                    prayerRow("المغرب", times.maghrib, in: location.timeZone)
                    prayerRow("العشاء", times.isha, in: location.timeZone)
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

    private func prayerRow(_ label: String, _ date: Date, in timeZone: TimeZone) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(Self.formattedTime(date, timeZone: timeZone))
                .foregroundStyle(.secondary)
        }
    }

    private var selectedCity: City? {
        guard let id = settingsStore.settings.selectedCityID else { return nil }
        return locationRepository?.city(id: id)
    }

    /// The one shared answer to "which location are prayer times for?",
    /// so what this popover shows and when `PrayerAlertScheduler` fires
    /// can never disagree — see `PrayerLocationResolver`.
    ///
    /// Nil means the location can't be resolved (no city picked, no
    /// cached fix, or a selected city whose stored IANA identifier no
    /// longer parses). The prayer-times block then renders its
    /// "pick a location" prompt rather than times silently computed in
    /// the Mac's own zone, which would be indistinguishable from correct
    /// output.
    private var resolvedLocation: ResolvedPrayerLocation? {
        PrayerLocationResolver.resolve(
            settings: settingsStore.settings,
            locationRepository: locationRepository
        )
    }

    private func todaysPrayerTimes(at location: ResolvedPrayerLocation) -> Adhan.PrayerTimes? {
        PrayerCalculator.prayerTimes(
            on: Date(),
            coordinates: location.coordinates,
            calculationMethod: settingsStore.settings.prayerCalculationMethod,
            asrMadhab: settingsStore.settings.asrMadhab,
            timeZone: location.timeZone
        )
    }

    private static func formattedTime(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.timeZone = timeZone
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
