import AppKit

enum ScreenHelper {
    static func screenContaining(point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}
