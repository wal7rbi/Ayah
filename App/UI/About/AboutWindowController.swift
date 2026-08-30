import AppKit
import SwiftUI

@MainActor
final class AboutWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
        window.title = "حول آية"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 480, height: 520))
        window.contentMinSize = NSSize(width: 420, height: 420)
        self.init(window: window)
    }

    func show() {
        if let window, !window.isVisible {
            window.center()
        }
        window?.makeKeyAndOrderFront(nil)
    }
}
