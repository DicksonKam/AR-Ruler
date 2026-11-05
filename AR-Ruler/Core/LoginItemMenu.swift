import Foundation

/// The system's view of the app as a login item, independent of the framework that reports it.
enum LoginItemStatus: Equatable {
    case notRegistered, enabled, requiresApproval, notFound
}

/// How the Launch at Login menu item looks for a given system state, and what choosing it does.
/// The state is always read from the system, so a change in System Settings shows up here.
struct LoginItemMenu: Equatable {
    enum Check: Equatable { case on, off, pending }
    enum Action: Equatable { case register, unregister, openLoginItemsSettings }

    let title: String
    let check: Check
    let action: Action

    init(status: LoginItemStatus) {
        switch status {
        case .enabled:
            self.init(title: "Launch at Login", check: .on, action: .unregister)
        case .requiresApproval:
            // Registered, but turned off in System Settings, and only the user can turn it back on there.
            self.init(title: "Launch at Login (Allow in Settings\u{2026})", check: .pending, action: .openLoginItemsSettings)
        case .notRegistered, .notFound:
            // For notFound, trying gives the system's own reason, which is more use than a disabled item.
            self.init(title: "Launch at Login", check: .off, action: .register)
        }
    }

    private init(title: String, check: Check, action: Action) {
        self.title = title
        self.check = check
        self.action = action
    }
}
