import SwiftUI

@main
struct ARRulerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
                .environmentObject(AppSettings.shared)
        }
    }
}
