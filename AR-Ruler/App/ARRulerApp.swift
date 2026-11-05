import SwiftUI

@main
struct ARRulerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // SwiftUI needs a scene, but its own settings window would duplicate Preferences, so nothing opens this one.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Preferences\u{2026}") { appDelegate.showPreferences() }
                    .keyboardShortcut(",")
            }
        }
    }
}
