import AppKit
import AyahKit
import SwiftUI

/// Owns the "manage memorization sets" window — a plain titled/closable/
/// resizable `NSWindow`, not another `NSPopover`: a transient popover
/// auto-dismisses on outside click, which is wrong for a multi-field
/// add/edit form. `AppDelegate.applicationShouldTerminateAfterLastWindowClosed`
/// already returns `false`, so closing this window doesn't quit the
/// accessory app.
@MainActor
final class MemorizationSetsWindowController: NSWindowController {
    private let model: MemorizationSetsModel

    init(quranRepository: QuranRepository, memorizationRepository: MemorizationRepository) {
        model = MemorizationSetsModel(repository: memorizationRepository)
        let view = MemorizationSetsView(quranRepository: quranRepository, memorizationRepository: memorizationRepository, model: model)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "مجموعات الحفظ"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 420, height: 480))
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        model.reload()
        if let window, !window.isVisible {
            window.center()
        }
        window?.makeKeyAndOrderFront(nil)
    }
}
