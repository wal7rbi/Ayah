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
    private var memorizationSetsWindowController: MemorizationSetsWindowController?
    private var cityPickerWindowController: CityPickerWindowController?
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

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 620)
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(
                settingsStore: settingsStore,
                locationViewModel: locationViewModel,
                launchAtLoginViewModel: launchAtLoginViewModel,
                onManageMemorizationSets: onManageMemorizationSets,
                onSelectCity: onSelectCity,
                locationRepository: locationRepository
            )
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            launchAtLoginViewModel.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// `quranRepository`/`memorizationRepository` are only `nil` when the
    /// closure that calls this was never wired up, so force-unwrapping
    /// here is safe — see `onManageMemorizationSets` above.
    private func showMemorizationSetsWindow() {
        guard let quranRepository, let memorizationRepository else { return }
        popover.performClose(nil)
        if memorizationSetsWindowController == nil {
            memorizationSetsWindowController = MemorizationSetsWindowController(
                quranRepository: quranRepository,
                memorizationRepository: memorizationRepository
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        memorizationSetsWindowController?.show()
    }

    /// `locationRepository` is only `nil` when the closure that calls
    /// this was never wired up, so force-unwrapping here is safe — see
    /// `onSelectCity` above.
    private func showCityPicker() {
        guard let locationRepository else { return }
        popover.performClose(nil)
        let controller = CityPickerWindowController(locationRepository: locationRepository) { [weak self] city in
            self?.settingsStore.settings.selectedCityID = city.id
            self?.cityPickerWindowController?.window?.close()
        }
        cityPickerWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.show()
    }
}
