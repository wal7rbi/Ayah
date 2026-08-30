import AppKit
import AyahKit
import Combine

/// Owns the notch panel's lifecycle and geometry. On a Mac with a
/// physical notch, the panel sits directly over the notch cutout and stays
/// visible as a small collapsed pill at all times. On a Mac without one,
/// `attachToNotchIfAvailable()` reuses the same panel/view stack as a
/// floating bar pinned below the menu bar instead — hidden while idle and
/// shown only while a verse batch or prayer alert is actually active,
/// since there's no physical camera housing for a permanent pill to blend
/// into (see ARCHITECTURE.md §4, "Fallback for Macs without a notch").
/// Either way, `StatusItemController` remains the app's one Settings
/// surface. Switching between the two modes while the app is already
/// running (e.g. a notched MacBook entering clamshell mode with only an
/// external display attached) is out of scope — the mode is picked once,
/// here, at attach time.
@MainActor
final class NotchController {
    private var panel: NotchPanel?
    private let viewModel: NotchViewModel
    private let prayerAlertScheduler: PrayerAlertScheduler?
    private var isFallbackMode = false
    private var fallbackVisibilityCancellable: AnyCancellable?

    private static let expandedSize = CGSize(width: 480, height: 220)

    init(
        quranRepository: QuranRepository?,
        verseScheduler: VerseScheduler?,
        prayerAlertScheduler: PrayerAlertScheduler?,
        settingsStore: SettingsStore
    ) {
        self.prayerAlertScheduler = prayerAlertScheduler
        self.viewModel = NotchViewModel(
            quranRepository: quranRepository,
            verseScheduler: verseScheduler,
            prayerAlertScheduler: prayerAlertScheduler,
            settingsStore: settingsStore
        )
    }

    func attachToNotchIfAvailable() {
        AppPerformanceSignposts.measure("NotchPresentation") {
            if let screen = Self.notchedScreen() {
                attachPhysicalNotch(on: screen)
            } else {
                attachFallbackBar()
            }
        }
    }

    private func attachPhysicalNotch(on screen: NSScreen) {
        let panel = NotchPanel(contentRect: .zero, viewModel: viewModel, isPhysicalNotch: true)
        self.panel = panel
        reposition(panel: panel, on: screen)
        panel.orderFrontRegardless()
        viewModel.startDisplayTimer()
        viewModel.startPrayerAlerts()
        registerObservers()
    }

    /// Floating bar for Macs with no physical notch: the same panel/view
    /// stack, pinned below the menu bar on the primary screen instead of
    /// over a notch cutout, and only ordered on-screen while
    /// `viewModel.isExpanded` — a verse batch or prayer alert is actually
    /// showing — rather than left visible as an always-there pill.
    private func attachFallbackBar() {
        guard let screen = NSScreen.screens.first else { return }
        isFallbackMode = true

        let panel = NotchPanel(contentRect: .zero, viewModel: viewModel, isPhysicalNotch: false)
        self.panel = panel
        repositionFallback(panel: panel, on: screen)
        viewModel.startDisplayTimer()
        viewModel.startPrayerAlerts()

        fallbackVisibilityCancellable = viewModel.$isExpanded
            .sink { [weak panel] isExpanded in
                guard let panel else { return }
                if isExpanded {
                    panel.orderFrontRegardless()
                } else {
                    panel.orderOut(nil)
                }
            }

        registerObservers()
    }

    private func registerObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // A prayer-alert timer's already-armed deadline can pass while the
        // Mac is asleep — re-arm against the (now different) soonest
        // upcoming event on wake, since there's no separate midnight
        // timer to otherwise catch this the way the deleted
        // UNUserNotificationCenter-based scheduler's OS-owned triggers did.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged() {
        guard let panel else { return }
        if isFallbackMode {
            guard let screen = NSScreen.screens.first else { return }
            repositionFallback(panel: panel, on: screen)
            return
        }
        guard let screen = Self.notchedScreen() else {
            panel.orderOut(nil)
            return
        }
        reposition(panel: panel, on: screen)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    @objc private func systemDidWake() {
        prayerAlertScheduler?.rearm()
    }

    private func reposition(panel: NotchPanel, on screen: NSScreen) {
        guard let notchFrame = Self.notchFrame(on: screen) else { return }

        viewModel.collapsedSize = CGSize(width: notchFrame.width, height: notchFrame.height)

        let size = Self.expandedSize
        let origin = NSPoint(
            x: notchFrame.midX - size.width / 2,
            y: screen.frame.maxY - size.height
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Positions the fallback panel centered below the menu bar on the
    /// given screen. `visibleFrame` (not `frame`) excludes the menu bar
    /// strip, so the bar sits flush underneath it instead of overlapping
    /// menu-bar items — there's no notch cutout here to anchor to instead.
    private func repositionFallback(panel: NotchPanel, on screen: NSScreen) {
        let size = Self.expandedSize
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.visibleFrame.maxY - size.height
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// The built-in display reporting a non-zero top safe-area inset,
    /// i.e. the one with a physical notch.
    static func notchedScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    /// The exact notch cutout rect (in screen coordinates): the gap
    /// between the auxiliary areas that flank the camera housing.
    static func notchFrame(on screen: NSScreen) -> CGRect? {
        guard screen.safeAreaInsets.top > 0,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            return nil
        }
        let height = screen.safeAreaInsets.top
        return CGRect(
            x: leftArea.maxX,
            y: screen.frame.maxY - height,
            width: rightArea.minX - leftArea.maxX,
            height: height
        )
    }
}
