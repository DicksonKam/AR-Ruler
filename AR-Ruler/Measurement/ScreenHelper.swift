import AppKit

enum ScreenHelper {
    static func screenContaining(point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    static func frameForAllScreens() -> NSRect {
        guard let first = NSScreen.screens.first else { return .zero }
        return NSScreen.screens.dropFirst().reduce(first.frame) { NSUnionRect($0, $1.frame) }
    }

    static func isSameScreen(_ a: NSScreen, _ b: NSScreen) -> Bool {
        a.frame.origin.x == b.frame.origin.x && a.frame.origin.y == b.frame.origin.y
    }
}
