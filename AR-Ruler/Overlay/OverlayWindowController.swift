import AppKit
import SwiftUI

final class OverlayWindowController {
    private var overlayWindow: NSWindow?
    private var overlayView: OverlayContentView?
    private var localModifierMonitor: Any?
    private var globalModifierMonitor: Any?
    private var escapeMonitor: Any?

    func showOverlay() {
        guard overlayWindow == nil else {
            overlayWindow?.orderFrontRegardless()
            return
        }

        let allScreensFrame = ScreenHelper.frameForAllScreens()
        guard !allScreensFrame.isEmpty else { return }

        let overlayView = OverlayContentView()
        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.clear.cgColor
        self.overlayView = overlayView

        let window = NSWindow(
            contentRect: allScreensFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.contentView = overlayView

        overlayView.onPointAdded = { [weak self] pointInView in
            guard let self = self, let window = self.overlayWindow else { return }
            let screenPoint = window.convertPoint(toScreen: pointInView)
            self.addPoint(screenPoint)
        }
        overlayView.onClear = { [weak self] in
            self?.clearPoints()
        }

        window.orderFrontRegardless()

        self.overlayWindow = window
        self.overlayView = overlayView

        setupModifierMonitor()
        setupEscapeMonitor()
    }

    func hideOverlay() {
        removeMonitors()
        overlayWindow?.orderOut(nil)
    }

    private func addPoint(_ point: NSPoint) {
        guard var points = overlayView?.points else { return }

        if points.count == 4 {
            points = [point]
        } else if points.count >= 1 {
            guard let firstScreen = ScreenHelper.screenContaining(point: points[0]),
                  let newScreen = ScreenHelper.screenContaining(point: point),
                  ScreenHelper.isSameScreen(firstScreen, newScreen) else { return }
            points.append(point)
        } else {
            points.append(point)
        }
        overlayView?.points = points
        overlayView?.needsDisplay = true
    }

    private func clearPoints() {
        overlayView?.points = []
        overlayView?.needsDisplay = true
    }

    private func setupModifierMonitor() {
        let settings = AppSettings.shared
        let updateCaptureMode: (NSEvent) -> Void = { [weak self] event in
            let relevantFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let modifierHeld = relevantFlags.contains(settings.modifierFlags)
            DispatchQueue.main.async {
                self?.overlayWindow?.ignoresMouseEvents = !modifierHeld
            }
        }

        localModifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            updateCaptureMode(event)
            return event
        }
        globalModifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: updateCaptureMode)
    }

    private func setupEscapeMonitor() {
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                DispatchQueue.main.async {
                    self?.clearPoints()
                }
            }
        }
    }

    private func removeMonitors() {
        if let mon = localModifierMonitor {
            NSEvent.removeMonitor(mon)
        }
        if let mon = globalModifierMonitor {
            NSEvent.removeMonitor(mon)
        }
        if let mon = escapeMonitor {
            NSEvent.removeMonitor(mon)
        }
    }
}
