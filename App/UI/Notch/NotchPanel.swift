import AppKit
import SwiftUI

/// Borderless, non-activating panel hosting the notch UI. Never becomes
/// key or main so it never steals focus from whatever the user is doing.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect, viewModel: NotchViewModel, isPhysicalNotch: Bool) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        contentView = NSHostingView(
            rootView: NotchContentView(viewModel: viewModel, isPhysicalNotch: isPhysicalNotch)
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
