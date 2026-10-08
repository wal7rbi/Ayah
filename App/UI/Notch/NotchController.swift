import AppKit
import AyahKit
import Combine

enum NotchPresentationMode {
    case physicalNotch, floatingTab, floatingCard
}

/// A value snapshot permits display transitions to be tested without creating NSScreens.
struct NotchScreen {
    let frame: CGRect
    let visibleFrame: CGRect
    let notchFrame: CGRect?
}

@MainActor
protocol NotchPanelPresenting: AnyObject {
    var isVisible: Bool { get }
    func place(at frame: CGRect)
    func show()
    func hide()
    func animate(to frame: CGRect, opening: Bool, completion: @escaping @MainActor () -> Void)
}

/// Owns one presentation while retaining content and schedulers across display changes.
/// Physical notches retain their collapsed pill; other screens get a black floating card.
@MainActor
final class NotchController {
    private var panel: (any NotchPanelPresenting)?
    private let viewModel: NotchViewModel
    private let prayerAlertScheduler: PrayerAlertScheduler?
    private let screens: () -> [NotchScreen]
    private let makePanel: (NotchViewModel, NotchPresentationMode) -> any NotchPanelPresenting
    private let reduceMotion: () -> Bool
    private var mode: NotchPresentationMode?
    private var collapsedFrame = CGRect.zero
    private var tabCancellable: AnyCancellable?
    private var targetFrame = CGRect.zero
    private var hiddenFrame = CGRect.zero
    private var visibilityCancellable: AnyCancellable?
    private var presentationGeneration: UInt = 0
    private var hasStarted = false

    convenience init(
        quranRepository: QuranRepository?,
        verseScheduler: VerseScheduler?,
        prayerAlertScheduler: PrayerAlertScheduler?,
        settingsStore: SettingsStore,
        lastShownStore: LastShownStore
    ) {
        self.init(
            viewModel: NotchViewModel(
                quranRepository: quranRepository,
                verseScheduler: verseScheduler,
                prayerAlertScheduler: prayerAlertScheduler,
                settingsStore: settingsStore,
                lastShownStore: lastShownStore
            ),
            prayerAlertScheduler: prayerAlertScheduler
        )
    }

    init(
        viewModel: NotchViewModel,
        prayerAlertScheduler: PrayerAlertScheduler? = nil,
        screens: @escaping () -> [NotchScreen] = {
            NSScreen.screens.map {
                NotchScreen(frame: $0.frame, visibleFrame: $0.visibleFrame, notchFrame: NotchController.notchFrame(on: $0))
            }
        },
        makePanel: @escaping (NotchViewModel, NotchPresentationMode) -> any NotchPanelPresenting = {
            NotchPanel(contentRect: .zero, viewModel: $0, mode: $1)
        },
        reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    ) {
        self.viewModel = viewModel
        self.prayerAlertScheduler = prayerAlertScheduler
        self.screens = screens
        self.makePanel = makePanel
        self.reduceMotion = reduceMotion
    }

    func replayLastShown() { viewModel.replayLastShown() }

    func attachToNotchIfAvailable() {
        guard !hasStarted else {
            refreshPresentation()
            return
        }
        hasStarted = true
        refreshPresentation()
        visibilityCancellable = viewModel.$isExpanded.removeDuplicates().sink { [weak self] expanded in
            self?.setVisible(expanded, animated: true)
        }
        tabCancellable = viewModel.$showFloatingTab.removeDuplicates().dropFirst().sink { [weak self] enabled in
            self?.refreshPresentation(showFloatingTab: enabled)
        }
        viewModel.startDisplayTimer()
        viewModel.startPrayerAlerts()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    /// Replacing only the panel keeps a display transition from selecting verses,
    /// advancing memorization, or creating a second scheduler subscription.
    func refreshPresentation(showFloatingTab: Bool? = nil) {
        AppPerformanceSignposts.measure("NotchPresentation") {
            viewModel.resetPointerInteraction()
            presentationGeneration &+= 1
            let available = screens()
            guard let screen = available.first(where: { $0.notchFrame != nil }) ?? available.first else {
                panel?.hide()
                panel = nil
                mode = nil
                return
            }
            let nextMode: NotchPresentationMode = screen.notchFrame != nil ? .physicalNotch
                : (showFloatingTab ?? viewModel.showFloatingTab) ? .floatingTab : .floatingCard
            let replacing = panel == nil || nextMode != mode
            if replacing {
                panel?.hide()
                panel = makePanel(viewModel, nextMode)
                mode = nextMode
            }
            let size = NotchMetrics.expandedSize
            if let notch = screen.notchFrame {
                viewModel.collapsedSize = notch.size
                targetFrame = CGRect(x: notch.midX - size.width / 2,
                                     y: screen.frame.maxY - size.height, width: size.width, height: size.height)
                collapsedFrame = notch
                setVisible(viewModel.isExpanded, animated: false)
            } else {
                viewModel.collapsedSize = nextMode == .floatingTab ? FloatingPopupMetrics.tabSize : size
                targetFrame = CGRect(x: screen.frame.midX - size.width / 2,
                                     y: screen.visibleFrame.maxY - FloatingPopupMetrics.topGap - size.height,
                                     width: size.width, height: size.height)
                hiddenFrame = CGRect(x: targetFrame.minX, y: screen.frame.maxY,
                                     width: size.width, height: size.height)
                let tabSize = FloatingPopupMetrics.tabSize
                collapsedFrame = CGRect(x: targetFrame.midX - tabSize.width / 2,
                                        y: targetFrame.maxY - tabSize.height,
                                        width: tabSize.width, height: tabSize.height)
                if replacing { panel?.place(at: nextMode == .floatingTab ? collapsedFrame : hiddenFrame) }
                setVisible(viewModel.isExpanded, animated: replacing)
            }
        }
    }

    private func setVisible(_ visible: Bool, animated: Bool) {
        guard let mode, let panel else { return }
        presentationGeneration &+= 1
        let generation = presentationGeneration
        if mode != .floatingCard {
            let frame = visible ? targetFrame : collapsedFrame
            if animated && !reduceMotion() && panel.isVisible {
                panel.animate(to: frame, opening: visible, completion: {})
            } else {
                panel.place(at: frame)
            }
            panel.show()
            return
        }
        if visible {
            if !panel.isVisible {
                panel.place(at: reduceMotion() ? targetFrame : hiddenFrame)
                panel.show()
            }
            if animated && !reduceMotion() {
                panel.animate(to: targetFrame, opening: true, completion: {})
            } else {
                panel.place(at: targetFrame)
            }
        } else if panel.isVisible && animated && !reduceMotion() {
            panel.animate(to: hiddenFrame, opening: false) { [weak self, weak panel] in
                guard let self, self.presentationGeneration == generation else { return }
                panel?.hide()
            }
        } else {
            panel.hide()
            panel.place(at: hiddenFrame)
        }
    }

    @objc private func screenParametersChanged() { refreshPresentation() }
    @objc private func systemDidWake() {
        refreshPresentation()
        prayerAlertScheduler?.rearm()
    }

    static func notchFrame(on screen: NSScreen) -> CGRect? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else { return nil }
        return CGRect(x: left.maxX, y: screen.frame.maxY - screen.safeAreaInsets.top,
                      width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
    }
}
