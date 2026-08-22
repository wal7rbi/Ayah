import AppKit
import AyahKit
import SwiftUI

/// Owns the "select a city" window — a plain titled/closable/resizable
/// `NSWindow`, same reasoning as `MemorizationSetsWindowController`: a
/// transient popover isn't right for an interactive, searchable list.
@MainActor
final class CityPickerWindowController: NSWindowController {
    convenience init(locationRepository: LocationRepository, onSelect: @escaping (City) -> Void) {
        let view = CityPickerView(locationRepository: locationRepository, onSelect: onSelect)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "اختيار المدينة"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 360, height: 480))
        self.init(window: window)
    }

    func show() {
        if let window, !window.isVisible {
            window.center()
        }
        window?.makeKeyAndOrderFront(nil)
    }
}
