import AppKit
import SwiftUI
import QuartzCore

/// Borderless, non-activating panel hosting the notch UI. Never becomes
/// key or main so it never steals focus from whatever the user is doing.
final class NotchPanel: NSPanel, NotchPanelPresenting {
    init(contentRect: NSRect, viewModel: NotchViewModel, mode: NotchPresentationMode) {
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
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        contentView = NotchHoverHostingView(viewModel: viewModel, mode: mode)
    }

    // Allow a floating card to travel fully above the screen before ordering out.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    func place(at frame: CGRect) { setFrame(frame, display: true) }
    func show() { orderFrontRegardless() }
    func hide() {
        (contentView as? NotchHoverHostingView)?.stopPointerMonitoring()
        orderOut(nil)
    }

    func animate(to frame: CGRect, opening: Bool, completion: @escaping @MainActor () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = FloatingPopupMetrics.animationDuration
            // A slight opening overshoot gives the floating card a spring-like arrival.
            context.timingFunction = opening
                ? CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.04)
                : CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(frame, display: true)
        } completionHandler: {
            Task { @MainActor [weak self] in
                (self?.contentView as? NotchHoverHostingView)?.reconcilePointerPosition()
                completion()
            }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Tracking stays active when another app owns focus. The tracking rectangle follows
/// the actual panel size, including every frame of expansion and collapse.
final class NotchHoverHostingView: NSHostingView<NotchContentView> {
    private weak var viewModel: NotchViewModel?
    private var hoverTrackingArea: NSTrackingArea?
    private var localMovementMonitor: Any?
    private var globalMovementMonitor: Any?
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }

    convenience init(viewModel: NotchViewModel, mode: NotchPresentationMode) {
        self.init(rootView: NotchContentView(viewModel: viewModel, mode: mode))
    }

    required init(rootView: NotchContentView) {
        self.viewModel = rootView.viewModel
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // inVisibleRect follows resizing automatically. Replacing the area on
        // each animation frame manufactures exit/entry pairs under a still cursor.
        guard hoverTrackingArea == nil else { return }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { reconcilePointerPosition() }
    override func mouseExited(with event: NSEvent) { reconcilePointerPosition() }

    func reconcilePointerPosition() {
        guard let window, window.isVisible else { return }
        let point = convert(window.convertPoint(fromScreen: pointerLocation()), from: nil)
        // Screen-edge coordinates can equal maxY at the camera housing. Treat
        // the boundary as inside, and reject stale resize-generated exit events.
        let inside = point.x >= bounds.minX && point.x <= bounds.maxX
            && point.y >= bounds.minY && point.y <= bounds.maxY
        if inside { startPointerMonitoring() } else { stopPointerMonitoring() }
        viewModel?.pointerChanged(inside)
    }
    // Tracking-area exits can be consumed by window resizing. Listen to actual
    // movement while hovered, including movement over other apps, without polling.
    private func startPointerMonitoring() {
        guard localMovementMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        localMovementMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor [weak self] in self?.reconcilePointerPosition() }
            return event
        }
        globalMovementMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcilePointerPosition() }
        }
    }

    func stopPointerMonitoring() {
        if let localMovementMonitor { NSEvent.removeMonitor(localMovementMonitor) }
        if let globalMovementMonitor { NSEvent.removeMonitor(globalMovementMonitor) }
        localMovementMonitor = nil
        globalMovementMonitor = nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopPointerMonitoring() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
