import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService. Only meaningful when running from a real
/// .app bundle (the bare `swift build` binary has no bundle to register).
enum LoginItem {
    static var isSupported: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// True when the user has to approve the item in System Settings.
    static var requiresApproval: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard isSupported else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
