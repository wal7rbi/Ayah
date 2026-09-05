import AppKit
import SwiftUI
import QuartzCore

/// Borderless, non-activating panel hosting the notch UI. Never becomes
/// key or main so it never steals focus from whatever the user is doing.
final class NotchPanel: NSPanel, NotchPanelPresenting {
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

    // Allow a floating card to travel fully above the screen before ordering out.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    func place(at frame: CGRect) { setFrame(frame, display: true) }
    func show() { orderFrontRegardless() }
    func hide() { orderOut(nil) }

    func animate(to frame: CGRect, opening: Bool, completion: @escaping @MainActor () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = FloatingPopupMetrics.animationDuration
            // A slight opening overshoot gives the floating card a spring-like arrival.
            context.timingFunction = opening
                ? CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.04)
                : CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(frame, display: true)
        } completionHandler: {
            Task { @MainActor in completion() }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
