import AppKit
import AyahKit
import CoreText

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var notchController: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPerformanceSignposts.measure("LaunchInitialization") {
            NSApp.setActivationPolicy(.accessory)

            registerBundledFonts()
            let settingsStore = SettingsStore()
            let quranRepository = makeQuranRepository()
            let memorizationRepository = makeMemorizationRepository()
            let locationRepository = makeLocationRepository()
            let verseScheduler = quranRepository.flatMap { qr in
                memorizationRepository.map { mr in
                    VerseScheduler(quranRepository: qr, memorizationRepository: mr, settingsStore: settingsStore)
                }
            }

            let prayerAlertScheduler = PrayerAlertScheduler(
                quranRepository: quranRepository,
                locationRepository: locationRepository,
                settingsStore: settingsStore
            )

            statusItemController = StatusItemController(
                settingsStore: settingsStore,
                quranRepository: quranRepository,
                memorizationRepository: memorizationRepository,
                locationRepository: locationRepository
            )

#if AYAH_PERFORMANCE_AUTOMATION
            startPerformanceAutomationIfRequested()
#endif

            let notchController = NotchController(
                quranRepository: quranRepository,
                verseScheduler: verseScheduler,
                prayerAlertScheduler: prayerAlertScheduler,
                settingsStore: settingsStore
            )
            notchController.attachToNotchIfAvailable()
            self.notchController = notchController
        }
    }

#if AYAH_PERFORMANCE_AUTOMATION
    /// Runs only in the dedicated profiling build produced by
    /// `Scripts/profile_ui_cycles.sh`; normal Debug/Release builds do not
    /// compile this command-line automation path.
    private func startPerformanceAutomationIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let cycles = Self.integerArgument(
            named: "--ayah-performance-popover-cycles",
            in: arguments,
            range: 1...500
        ) else { return }
        let delayMilliseconds = Self.integerArgument(
            named: "--ayah-performance-cycle-delay-ms",
            in: arguments,
            range: 20...2_000
        ) ?? 50
        guard let statusItemController else { return }

        Task { @MainActor in
            Self.writePerformanceMarker("AYAH_PERFORMANCE_WARMUP_STARTED")
            await statusItemController.runAutomatedPopoverCycles(
                count: 5,
                delay: .milliseconds(delayMilliseconds)
            )
            Self.writePerformanceMarker("AYAH_PERFORMANCE_WARMUP_FINISHED")
            try? await Task.sleep(for: .seconds(2))
            Self.writePerformanceMarker("AYAH_PERFORMANCE_BASELINE_READY")
            try? await Task.sleep(for: .seconds(2))
            Self.writePerformanceMarker("AYAH_PERFORMANCE_CYCLES_STARTED")
            await statusItemController.runAutomatedPopoverCycles(
                count: cycles,
                delay: .milliseconds(delayMilliseconds)
            )
            Self.writePerformanceMarker("AYAH_PERFORMANCE_CYCLES_FINISHED")
            try? await Task.sleep(for: .seconds(2))
            Self.writePerformanceMarker("AYAH_PERFORMANCE_COMPLETE")
            NSApp.terminate(nil)
        }
    }

    private static func integerArgument(
        named name: String,
        in arguments: [String],
        range: ClosedRange<Int>
    ) -> Int? {
        guard let index = arguments.firstIndex(of: name),
              arguments.indices.contains(index + 1),
              let value = Int(arguments[index + 1]),
              range.contains(value)
        else { return nil }
        return value
    }

    private static func writePerformanceMarker(_ marker: StaticString) {
        FileHandle.standardError.write(Data("\(marker)\n".utf8))
    }
#endif

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Registers the bundled KFGQPC Uthmanic Hafs font for this process
    /// only (`.process` scope — no persistent system-wide registration,
    /// nothing to clean up, appropriate for a sandboxed app).
    private func registerBundledFonts() {
        guard let fontURL = Bundle.main.url(forResource: "uthmanic_hafs_v20", withExtension: "ttf") else {
            return
        }
        CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
    }

    /// Builds the repository against the bundled, checksummed
    /// `quran.sqlite`. Per ARCHITECTURE.md §8, a missing bundle resource
    /// or a failed integrity check must surface as a visible error
    /// rather than silently showing nothing or unverified text.
    private func makeQuranRepository() -> QuranRepository? {
        guard let dbURL = Bundle.main.url(forResource: "quran", withExtension: "sqlite"),
              let checksumURL = Bundle.main.url(forResource: "CHECKSUM", withExtension: nil)
        else {
            presentErrorAlert(title: "Ayah: Quran data unavailable", message: "Quran data files were not found in the app bundle.")
            return nil
        }
        do {
            return try QuranRepository(databasePath: dbURL.path, checksumPath: checksumURL.path)
        } catch {
            presentErrorAlert(
                title: "Ayah: Quran data unavailable",
                message: "Quran data failed integrity verification and will not be displayed.\n\n\(error)"
            )
            return nil
        }
    }

    /// Builds the local, mutable `ayah_user.sqlite` (memorization sets) —
    /// shared by `VerseScheduler` and the memorization-sets management
    /// window (`StatusItemController`) so both read/write the same
    /// database; `VerseScheduler` re-queries it on every timer fire
    /// rather than caching, so edits made in the management UI take
    /// effect on the next scheduled display with no extra plumbing.
    /// Unlike a Quran data integrity failure (§8), a failure here (e.g. a
    /// full disk) doesn't mean anything is untrusted, just that
    /// memorization sets and the verse timer can't be persisted/run this
    /// launch — surfaced as a non-critical alert rather than blocking
    /// launch.
    private func makeMemorizationRepository() -> MemorizationRepository? {
        do {
            let supportDir = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            let dbURL = supportDir.appendingPathComponent("Ayah/ayah_user.sqlite")
            return try MemorizationRepository(databasePath: dbURL.path)
        } catch {
            presentErrorAlert(
                title: "Ayah: Memorization data unavailable",
                message: "Memorization data could not be loaded and verse display is disabled for this launch.\n\n\(error)",
                style: .warning
            )
            return nil
        }
    }

    /// Builds the repository against the bundled `cities_filtered.sqlite`
    /// (ARCHITECTURE.md §12). Unlike a Quran data integrity failure (§8),
    /// the bundled checksum is required and corrupt or substituted data
    /// fails closed. A failure here just means city selection
    /// (and therefore prayer-time display) is unavailable this launch,
    /// surfaced as a non-critical alert rather than blocking launch.
    private func makeLocationRepository() -> LocationRepository? {
        guard let dbURL = Bundle.main.url(forResource: "cities_filtered", withExtension: "sqlite"),
              let checksumURL = Bundle.main.url(forResource: "GEONAMES_CHECKSUM", withExtension: nil)
        else {
            presentErrorAlert(
                title: "آية: بيانات المدن غير متوفرة",
                message: "لم يتم العثور على بيانات المدن ضمن حزمة التطبيق. لن يمكن اختيار مدينة أو عرض أوقات الصلاة.",
                style: .warning
            )
            return nil
        }
        do {
            return try LocationRepository(databasePath: dbURL.path, checksumPath: checksumURL.path)
        } catch {
            presentErrorAlert(
                title: "آية: بيانات المدن غير متوفرة",
                message: "تعذر تحميل بيانات المدن. لن يمكن اختيار مدينة أو عرض أوقات الصلاة.\n\n\(error)",
                style: .warning
            )
            return nil
        }
    }

    private func presentErrorAlert(title: String, message: String, style: NSAlert.Style = .critical) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
