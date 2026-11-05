import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var overlayController: OverlayWindowController?
    private var preferencesWindow: NSWindow?
    private let clearItem = NSMenuItem(title: "Clear Measurement", action: #selector(clearMeasurement), keyEquivalent: "")
    private let scaleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let calibrateItem = NSMenuItem(title: "Calibrate This Display\u{2026}", action: #selector(calibrateDisplay), keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "Allow Esc to Clear in Other Apps\u{2026}", action: #selector(requestAccessibility), keyEquivalent: "")
    private let resetCalibrationItem = NSMenuItem(title: "Reset Calibration", action: #selector(resetCalibration), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        overlayController = OverlayWindowController()
        overlayController?.showOverlay()
        setupMenuBar()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlayController?.hideOverlay()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "ruler", accessibilityDescription: "AR Ruler")
            button.toolTip = "AR Ruler - Hold \(AppSettings.shared.modifierKey.rawValue) and click two points to lay a ruler"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "AR Ruler", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(clearItem)
        menu.addItem(accessibilityItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(scaleItem)
        menu.addItem(calibrateItem)
        menu.addItem(resetCalibrationItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit AR Ruler", action: #selector(quitApp), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }

        menu.autoenablesItems = false
        menu.delegate = self
        statusItem?.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        let screen = overlayController?.targetScreen
        clearItem.isEnabled = overlayController?.hasMeasurement ?? false
        scaleItem.isEnabled = false
        // macOS only passes other apps' key presses to apps with Accessibility access. Everything else works without it.
        accessibilityItem.isHidden = AXIsProcessTrusted()
        calibrateItem.isEnabled = screen != nil
        resetCalibrationItem.isEnabled = screen.map { CalibrationManager.shared.isCalibrated($0) } ?? false
        if let screen {
            let manager = CalibrationManager.shared
            scaleItem.title = String(format: "%@: %.1f pt/cm, %@", screen.localizedName, manager.pointsPerCm(for: screen), manager.source(for: screen).description)
        }
    }

    @objc private func clearMeasurement() {
        overlayController?.clear()
    }

    @objc private func requestAccessibility() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    @objc private func calibrateDisplay() {
        guard let overlayController, let screen = overlayController.targetScreen else { return }
        if CalibrationDialog.run(for: screen, rulerLengthPoints: overlayController.rulerLengthPoints) {
            overlayController.redrawAll()
        }
    }

    @objc private func resetCalibration() {
        guard let overlayController, let screen = overlayController.targetScreen else { return }
        CalibrationManager.shared.resetCalibration(screen)
        overlayController.redrawAll()
    }

    @objc private func showPreferences() {
        if preferencesWindow == nil {
            let contentView = PreferencesView()
                .environmentObject(AppSettings.shared)
            preferencesWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            preferencesWindow?.title = "AR Ruler Preferences"
            preferencesWindow?.contentView = NSHostingView(rootView: contentView)
            preferencesWindow?.center()
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
