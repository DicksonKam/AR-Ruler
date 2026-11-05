import AppKit

/// A borderless panel that never activates AR Ruler, so the user's current app keeps its focus when clicked through.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class OverlayWindowController {
    private struct Overlay {
        let panel: OverlayPanel
        let view: OverlayContentView
        let screen: NSScreen
    }

    private var overlays: [Overlay] = []
    private var isShown = false
    private var session = RulerSession()
    private var pointer: CGPoint?
    private var modifierHeld = false
    private var shiftHeld = false
    private var registeredObservers: [NSObjectProtocol] = []
    private var modifierMonitors: [Any] = []
    private var escapeMonitors: [Any] = []
    private var pointerMonitor: Any?
    private let hotKeys = ArrowHotKeys()

    private var settings: AppSettings { .shared }
    private var unit: RulerUnit { settings.unit == .inch ? .inch : .cm }

    init() {
        hotKeys.onNudge = { [weak self] delta in
            guard let self else { return }
            self.session.translateRuler(by: delta)
            self.redrawAll()
        }
    }

    // MARK: Lifecycle

    func showOverlay() {
        guard !isShown else {
            overlays.forEach { $0.panel.orderFrontRegardless() }
            return
        }
        isShown = true
        rebuildPanels()
        setupModifierMonitors()
        setupEscapeMonitors()
        registeredObservers = [
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.rebuildPanels()
            },
            // Preferences can change the unit and the modifier at any time.
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.sessionChanged()
            }
        ]
    }

    func hideOverlay() {
        isShown = false
        removeMonitors()
        registeredObservers.forEach(NotificationCenter.default.removeObserver)
        registeredObservers = []
        hotKeys.unregister()
        overlays.forEach { $0.panel.orderOut(nil) }
        overlays = []
    }

    /// One panel per screen, because a single window spanning displays can't cross them when
    /// "Displays have separate Spaces" is on.
    private func rebuildPanels() {
        overlays.forEach { overlay in
            overlay.panel.orderOut(nil)
            overlay.panel.close()
        }
        overlays = NSScreen.screens.map(makeOverlay)

        // A measurement is only meaningful on the screen it was made on, at the same geometry.
        if let bounds = session.bounds, !overlays.contains(where: { $0.screen.frame == bounds }) {
            session.clear()
        }
        sessionChanged()
    }

    private func makeOverlay(for screen: NSScreen) -> Overlay {
        let frame = screen.frame
        let view = OverlayContentView(screenFrame: frame)
        let panel = OverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // The app hides itself to give focus back after a dialog, and the ruler has to stay up through that.
        panel.canHide = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = !modifierHeld
        panel.acceptsMouseMovedEvents = true
        panel.contentView = view
        panel.setFrame(frame, display: false)

        view.sceneProvider = { [weak self, weak screen] in
            guard let self, let screen else { return nil }
            return self.scene(for: screen)
        }
        view.onPress = { [weak self, weak view] location, event in
            guard let self, let overlay = self.overlays.first(where: { $0.view === view }) else { return }
            self.pressed(at: location, event: event, on: overlay)
        }
        view.onDrag = { [weak self] location, event in self?.dragged(to: location, event: event) }
        view.onRelease = { [weak self] location, event in self?.released(at: location, event: event) }
        view.onMove = { [weak self] location, event in self?.pointerMoved(to: location, flags: event.modifierFlags) }
        view.onClear = { [weak self] in self?.clear() }

        panel.orderFrontRegardless()
        return Overlay(panel: panel, view: view, screen: screen)
    }

    private func scene(for screen: NSScreen) -> RulerScene {
        RulerScene(
            session: session,
            scale: RulerScale(unit: unit, pointsPerCm: CalibrationManager.shared.pointsPerCm(for: screen)),
            screenFrame: screen.frame,
            backingScale: screen.backingScaleFactor,
            pointer: pointer,
            modifierHeld: modifierHeld,
            shiftHeld: shiftHeld
        )
    }

    // MARK: Public state for the menu

    /// The screen a calibration or reset applies to: where the ruler is, otherwise where the pointer is.
    var targetScreen: NSScreen? {
        if let bounds = session.bounds, let screen = NSScreen.screens.first(where: { $0.frame == bounds }) {
            return screen
        }
        return ScreenHelper.screenContaining(point: NSEvent.mouseLocation) ?? NSScreen.main
    }

    var rulerLengthPoints: CGFloat? { session.rulerLength }
    var hasMeasurement: Bool { !session.isEmpty }

    func clear() {
        session.clear()
        sessionChanged()
    }

    func redrawAll() {
        syncRulerScale()
        overlays.forEach { $0.view.needsDisplay = true }
    }

    /// The ruler's fitted length is in whole units, so it follows a change of unit or calibration.
    private func syncRulerScale() {
        guard let overlay = overlays.first(where: { $0.screen.frame == session.bounds }) else { return }
        session.pointsPerUnit = RulerScale(unit: unit, pointsPerCm: CalibrationManager.shared.pointsPerCm(for: overlay.screen)).pointsPerUnit
    }

    // MARK: Mouse

    private func snapping(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection(.deviceIndependentFlagsMask).contains(.shift)
    }

    private func pressed(at location: CGPoint, event: NSEvent, on overlay: Overlay) {
        session.pointsPerUnit = RulerScale(unit: unit, pointsPerCm: CalibrationManager.shared.pointsPerCm(for: overlay.screen)).pointsPerUnit
        session.pressBegan(at: location, on: overlay.screen.frame)
        pointer = location
    }

    private func dragged(to location: CGPoint, event: NSEvent) {
        pointer = location
        shiftHeld = snapping(event.modifierFlags)
        session.pressMoved(to: location, snapping: shiftHeld)
        redrawAll()
    }

    private func released(at location: CGPoint, event: NSEvent) {
        pointer = location
        session.pressEnded(snapping: snapping(event.modifierFlags))
        // The modifier may have been let go during the press; capture was held open until now.
        applyCaptureState()
        sessionChanged()
    }

    private func pointerMoved(to location: CGPoint, flags: NSEvent.ModifierFlags) {
        guard !session.isEmpty, let overlay = overlays.first(where: { $0.screen.frame == session.bounds }) else {
            pointer = location
            return
        }
        let before = RulerRenderer.liveBounds(for: scene(for: overlay.screen))
        let hoverBefore = pointer.flatMap { session.hitTest($0) }
        pointer = location
        let after = RulerRenderer.liveBounds(for: scene(for: overlay.screen))
        let hoverAfter = session.hitTest(location)
        if hoverBefore != hoverAfter, modifierHeld {
            overlay.view.needsDisplay = true
        } else {
            overlay.view.invalidate(globalRect: before.union(after))
        }
    }

    // MARK: Modifier and keys

    private func setupModifierMonitors() {
        let handle: (NSEvent) -> Void = { [weak self] event in
            self?.modifiersChanged(event.modifierFlags)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
            handle(event)
            return event
        }) {
            modifierMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handle) {
            modifierMonitors.append(global)
        }
    }

    private func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        let relevant = flags.intersection(.deviceIndependentFlagsMask)
        let held = relevant.contains(settings.modifierFlags)
        let shift = relevant.contains(.shift)
        let changed = held != modifierHeld || shift != shiftHeld
        modifierHeld = held
        shiftHeld = shift
        applyCaptureState()
        guard changed else { return }
        pointer = NSEvent.mouseLocation
        if session.isDragging {
            session.pressMoved(to: NSEvent.mouseLocation, snapping: shift)
        }
        redrawAll()
    }

    /// Clicks only reach the overlay while the modifier is held. A press in progress keeps it, so its release isn't lost.
    private func applyCaptureState() {
        let capture = modifierHeld || session.isPressed
        overlays.forEach { $0.panel.ignoresMouseEvents = !capture }
    }

    private func setupEscapeMonitors() {
        let isEscape: (NSEvent) -> Bool = { $0.keyCode == 53 }
        // Global covers other apps being frontmost; local covers AR Ruler's own windows.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if isEscape(event) { self?.clear() }
        }) {
            escapeMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            // In a dialog, Esc belongs to the dialog. Calibrating needs the ruler to still be there afterwards.
            if isEscape(event), NSApp.modalWindow == nil { self?.clear() }
            return event
        }) {
            escapeMonitors.append(local)
        }
    }

    /// Everything that exists only while something is on screen starts and stops here.
    private func sessionChanged() {
        if session.isEmpty {
            if let monitor = pointerMonitor {
                NSEvent.removeMonitor(monitor)
                pointerMonitor = nil
            }
        } else if pointerMonitor == nil {
            pointerMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            ) { [weak self] event in
                self?.pointerMoved(to: NSEvent.mouseLocation, flags: event.modifierFlags)
            }
        }

        if session.hasRuler {
            hotKeys.register(modifier: settings.modifierKey)
        } else {
            hotKeys.unregister()
        }
        applyCaptureState()
        redrawAll()
    }

    private func removeMonitors() {
        (modifierMonitors + escapeMonitors).forEach(NSEvent.removeMonitor)
        modifierMonitors = []
        escapeMonitors = []
        if let monitor = pointerMonitor {
            NSEvent.removeMonitor(monitor)
            pointerMonitor = nil
        }
    }
}
