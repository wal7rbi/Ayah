import AppKit
import AyahKit

/// Owns the notch panel's lifecycle and geometry. On Macs without a
/// notch, `attachToNotchIfAvailable()` simply does nothing — all
/// interaction happens through `StatusItemController` instead, which is
/// always present regardless of notch availability (see ARCHITECTURE.md
/// §4, "Fallback for Macs without a notch"). Verse display on the
/// non-notch popover fallback is not yet implemented — a known,
/// deliberate gap, not an oversight.
@MainActor
final class NotchController {
    private var panel: NotchPanel?
    private let viewModel: NotchViewModel
    private let prayerAlertScheduler: PrayerAlertScheduler?

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
        guard let screen = Self.notchedScreen() else { return }

        let panel = NotchPanel(contentRect: .zero, viewModel: viewModel)
        self.panel = panel
        reposition(panel: panel, on: screen)
        panel.orderFrontRegardless()
        viewModel.startDisplayTimer()
        viewModel.startPrayerAlerts()

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
