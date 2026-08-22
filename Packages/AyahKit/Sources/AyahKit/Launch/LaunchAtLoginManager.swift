import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` (ARCHITECTURE.md §14) — the app registers
/// itself directly as its own login item, no separate helper-app target
/// needed, and works the same whether or not the app is sandboxed. Kept
/// behind a protocol (mirroring `LocationProviding`) so a view model can be
/// tested against a fake without touching the real system login-item list.
@MainActor
public protocol LaunchAtLoginControlling: AnyObject {
    var status: SMAppService.Status { get }
    func setEnabled(_ enabled: Bool) throws
    func openSystemSettingsLoginItems()
}

@MainActor
public final class LaunchAtLoginManager: LaunchAtLoginControlling {
    public init() {}

    public var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
