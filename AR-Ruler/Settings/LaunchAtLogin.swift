import AppKit
import ServiceManagement

/// Launch at Login through SMAppService. Nothing is stored here: the system is the only record of the state.
enum LaunchAtLogin {
    static var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    static var menu: LoginItemMenu { LoginItemMenu(status: status) }

    /// Carries out what the menu item offers, and says so in an alert if it didn't work.
    static func perform(_ action: LoginItemMenu.Action) {
        switch action {
        case .openLoginItemsSettings:
            SMAppService.openSystemSettingsLoginItems()
        case .register:
            do {
                try SMAppService.mainApp.register()
                if status == .requiresApproval { showNeedsApproval() }
            } catch {
                showFailure("AR Ruler couldn't be set to launch at login", error: error)
            }
        case .unregister:
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                showFailure("AR Ruler couldn't be removed from login items", error: error)
            }
        }
    }

    private static func showNeedsApproval() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Allow AR Ruler in System Settings"
        alert.informativeText = "macOS needs you to turn AR Ruler on under Login Items before it can launch at login."
        alert.addButton(withTitle: "Open Login Items")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private static func showFailure(_ message: String, error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        var details = error.localizedDescription
        if !Bundle.main.bundlePath.hasPrefix("/Applications/") {
            details += "\n\nThis copy is running from \(Bundle.main.bundlePath). Login items are most reliable for an app in the Applications folder."
        }
        alert.informativeText = details
        alert.runModal()
    }
}
