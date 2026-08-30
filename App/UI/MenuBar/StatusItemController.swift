import AppKit
import AyahKit
import SwiftUI

/// Standard menu-bar-utility pattern (NSStatusItem + NSPopover), present
/// on every Mac regardless of notch availability. This is the universal
/// Settings entry point and, on Macs without a notch, the app's only
/// interaction surface (see ARCHITECTURE.md §4).
@MainActor
final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let settingsStore: SettingsStore
    private let quranRepository: QuranRepository?
    private let memorizationRepository: MemorizationRepository?
    private let locationRepository: LocationRepository?
    private let memorizationSetsWindowSlot = LazySingleton<MemorizationSetsWindowController>()
    private let cityPickerWindowSlot = LazySingleton<CityPickerWindowController>()
    private let aboutWindowSlot = LazySingleton<AboutWindowController>()
    private let locationViewModel: CurrentLocationViewModel
    private let launchAtLoginViewModel = LaunchAtLoginViewModel()

    init(
        settingsStore: SettingsStore,
        quranRepository: QuranRepository?,
        memorizationRepository: MemorizationRepository?,
        locationRepository: LocationRepository? = nil
    ) {
        self.settingsStore = settingsStore
        self.quranRepository = quranRepository
        self.memorizationRepository = memorizationRepository
        self.locationRepository = locationRepository
        self.locationViewModel = CurrentLocationViewModel(settingsStore: settingsStore)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "book.closed", accessibilityDescription: "Ayah")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let onManageMemorizationSets: (() -> Void)? = (quranRepository != nil && memorizationRepository != nil)
            ? { [weak self] in self?.showMemorizationSetsWindow() }
            : nil
        let onSelectCity: (() -> Void)? = locationRepository != nil
            ? { [weak self] in self?.showCityPicker() }
            : nil
        let onShowAbout: () -> Void = { [weak self] in self?.showAboutWindow() }

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 620)
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(
                settingsStore: settingsStore,
                locationViewModel: locationViewModel,
                launchAtLoginViewModel: launchAtLoginViewModel,
                onManageMemorizationSets: onManageMemorizationSets,
                onSelectCity: onSelectCity,
                onShowAbout: onShowAbout,
                locationRepository: locationRepository
            )
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            AppPerformanceSignposts.measure("PopoverPresentation") {
                launchAtLoginViewModel.refresh()
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

#if AYAH_PERFORMANCE_AUTOMATION
    /// Exercises the same action as a real status-item click. This method is
    /// compiled only into the dedicated local profiling build.
    func runAutomatedPopoverCycles(count: Int, delay: Duration) async {
        for _ in 0..<count {
            togglePopover()
            try? await Task.sleep(for: delay)
            togglePopover()
            try? await Task.sleep(for: delay)
        }
        if popover.isShown {
            popover.performClose(nil)
        }
    }
#endif

    /// `quranRepository`/`memorizationRepository` are only `nil` when the
    /// closure that calls this was never wired up, so force-unwrapping
    /// here is safe — see `onManageMemorizationSets` above.
    private func showMemorizationSetsWindow() {
        guard let quranRepository, let memorizationRepository else { return }
        popover.performClose(nil)
        let controller = memorizationSetsWindowSlot.getOrCreate {
            MemorizationSetsWindowController(
                quranRepository: quranRepository,
                memorizationRepository: memorizationRepository
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        AppPerformanceSignposts.measure("AuxiliaryWindowPresentation") {
            controller.show()
        }
    }

    /// `locationRepository` is only `nil` when the closure that calls
    /// this was never wired up, so force-unwrapping here is safe — see
    /// `onSelectCity` above. Reuses the same `CityPickerWindowController`
    /// across repeated calls via `cityPickerWindowSlot` (mirroring
    /// `showMemorizationSetsWindow` above) rather than creating a new one
    /// each time — a second call used to orphan the first window and make
    /// `onSelect` close the wrong one, since it always closed whichever
    /// controller was *currently* stored.
    private func showCityPicker() {
        guard let locationRepository else { return }
        popover.performClose(nil)
        let controller = cityPickerWindowSlot.getOrCreate {
            CityPickerWindowController(locationRepository: locationRepository) { [weak self] city in
                self?.settingsStore.settings.selectedCityID = city.id
                self?.cityPickerWindowSlot.current?.window?.close()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        AppPerformanceSignposts.measure("AuxiliaryWindowPresentation") {
            controller.show()
        }
    }

    private func showAboutWindow() {
        popover.performClose(nil)
        let controller = aboutWindowSlot.getOrCreate {
            AboutWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        AppPerformanceSignposts.measure("AuxiliaryWindowPresentation") {
            controller.show()
        }
    }
}
