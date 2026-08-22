import AyahKit
import Foundation
import ServiceManagement

/// Bridges the Settings popover's "launch at login" toggle to
/// `LaunchAtLoginManager` (AyahKit). Deliberately no `AppSettings` field
/// backs this: `SMAppService.mainApp.status` is itself the persistent
/// source of truth (macOS's own Login Items list, which the user can also
/// change from System Settings directly), so mirroring it into
/// `UserDefaults` would just create a second copy that could drift — the
/// same two-sources-of-truth failure mode the single-shared-`SettingsStore`
/// rule elsewhere in this app already exists to avoid. `status` is
/// re-read from the system on demand (`refresh()`) rather than cached,
/// since it can change out from under the app (e.g. the user approves or
/// removes the login item in System Settings while the popover is closed).
@MainActor
final class LaunchAtLoginViewModel: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published var errorMessage: String?

    private let manager: LaunchAtLoginControlling

    init(manager: LaunchAtLoginControlling = LaunchAtLoginManager()) {
        self.manager = manager
        self.status = manager.status
    }

    func refresh() {
        status = manager.status
    }

    /// `.requiresApproval` still counts as "on" from the toggle's point of
    /// view — `register()` succeeded on Ayah's side, macOS is just holding
    /// it pending the user's approval in System Settings. Showing the
    /// toggle as off here would misrepresent what actually happened.
    var isEnabled: Bool {
        switch status {
        case .enabled, .requiresApproval:
            return true
        default:
            return false
        }
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            try manager.setEnabled(enabled)
        } catch {
            errorMessage = "تعذر تحديث إعداد بدء التشغيل التلقائي."
        }
        status = manager.status
    }

    func openSystemSettingsLoginItems() {
        manager.openSystemSettingsLoginItems()
    }
}
