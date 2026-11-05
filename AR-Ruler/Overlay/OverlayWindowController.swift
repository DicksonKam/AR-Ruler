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
    private var state = OverlayInputState()
    #if DEBUG
    private var physicalInputEnabled = true
    #endif
    private var registeredObservers: [NSObjectProtocol] = []
    private var modifierMonitors: [Any] = []
    private var escapeMonitors: [Any] = []
    private var pointerMonitor: Any?

    private var settings: AppSettings { .shared }
    private var unit: RulerUnit { settings.unit == .inch ? .inch : .cm }

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
        if let bounds = state.session.bounds, !overlays.contains(where: { $0.screen.frame == bounds }) {
            state.session.clear()
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
        panel.ignoresMouseEvents = !state.capturesClicks
        panel.acceptsMouseMovedEvents = true
        panel.contentView = view
        panel.setFrame(frame, display: false)

        view.sceneProvider = { [weak self, weak screen] in
            guard let self, let screen else { return nil }
            return self.scene(for: screen)
        }
        view.onPress = { [weak self, weak view] location, _ in
            guard let self, let overlay = self.overlays.first(where: { $0.view === view }) else { return }
            self.receivePhysical(self.pressInput(at: location, on: overlay.screen))
        }
        view.onDrag = { [weak self] location, event in self?.receivePhysical(.drag(location, event.modifierFlags)) }
        view.onRelease = { [weak self] location, event in self?.receivePhysical(.release(location, event.modifierFlags)) }
        view.onMove = { [weak self] location, _ in self?.receivePhysical(.pointerMoved(location)) }
        view.onClear = { [weak self] in self?.receivePhysical(.clear) }

        panel.orderFrontRegardless()
        return Overlay(panel: panel, view: view, screen: screen)
    }

    private func scene(for screen: NSScreen) -> RulerScene {
        RulerScene(
            session: state.session,
            scale: RulerScale(unit: unit, pointsPerCm: CalibrationManager.shared.pointsPerCm(for: screen)),
            screenFrame: screen.frame,
            backingScale: screen.backingScaleFactor,
            pointer: state.pointer,
            modifierHeld: state.modifierHeld,
            shiftHeld: state.shiftHeld
        )
    }

    // MARK: Public state for the menu

    /// The screen a calibration or reset applies to: where the ruler is, otherwise where the pointer is.
    var targetScreen: NSScreen? {
        if let bounds = state.session.bounds, let screen = NSScreen.screens.first(where: { $0.frame == bounds }) {
            return screen
        }
        return ScreenHelper.screenContaining(point: NSEvent.mouseLocation) ?? NSScreen.main
    }

    var rulerLengthPoints: CGFloat? { state.session.rulerLength }
    var hasMeasurement: Bool { !state.session.isEmpty }

    func clear() {
        receive(.clear)
    }

    func redrawAll() {
        syncRulerScale()
        overlays.forEach { $0.view.needsDisplay = true }
    }

    private func pointsPerUnit(on screen: NSScreen) -> CGFloat {
        RulerScale(unit: unit, pointsPerCm: CalibrationManager.shared.pointsPerCm(for: screen)).pointsPerUnit
    }

    /// The ruler's fitted length is in whole units, so it follows a change of unit or calibration.
    private func syncRulerScale() {
        guard let overlay = overlays.first(where: { $0.screen.frame == state.session.bounds }) else { return }
        state.session.pointsPerUnit = pointsPerUnit(on: overlay.screen)
    }

    private func pressInput(at location: CGPoint, on screen: NSScreen) -> OverlayInput {
        .press(location, frame: screen.frame, pointsPerUnit: pointsPerUnit(on: screen))
    }

    // MARK: Input

    /// Real keys and mouse come in here.
    private func receivePhysical(_ input: OverlayInput) {
        #if DEBUG
        guard physicalInputEnabled else { return }
        #endif
        receive(input)
    }

    /// The one entry point. All input, whatever its source, changes the state and redraws from here.
    private func receive(_ input: OverlayInput) {
        state.modifierKey = settings.modifierKey
        let session = state.session
        let overlay = overlays.first { $0.screen.frame == session.bounds }
        // Worked out against the old state, to clear where the live reading was.
        let liveBefore = overlay.map { RulerRenderer.liveBounds(for: scene(for: $0.screen)) }
        let hoverBefore = state.pointer.flatMap { session.hitTest($0) }

        let effect = state.apply(input)

        applyCaptureState()
        switch effect {
        case .nothing:
            break
        case .pointerOnly:
            guard let overlay, let liveBefore, !session.isEmpty else { return }
            let hoverAfter = state.pointer.flatMap { state.session.hitTest($0) }
            if hoverBefore != hoverAfter, state.modifierHeld {
                overlay.view.needsDisplay = true
            } else {
                overlay.view.invalidate(globalRect: liveBefore.union(RulerRenderer.liveBounds(for: scene(for: overlay.screen))))
            }
        case .everything:
            redrawAll()
        case .sessionChanged:
            sessionChanged()
        }
    }

    // MARK: Modifier and keys

    private func setupModifierMonitors() {
        let handle: (NSEvent) -> Void = { [weak self] event in
            self?.receivePhysical(.modifiers(event.modifierFlags, pointer: NSEvent.mouseLocation))
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

    private func applyCaptureState() {
        overlays.forEach { $0.panel.ignoresMouseEvents = !state.capturesClicks }
    }

    private func setupEscapeMonitors() {
        let isEscape: (NSEvent) -> Bool = { $0.keyCode == 53 }
        // Global covers other apps being frontmost; local covers AR Ruler's own windows.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if isEscape(event) { self?.receivePhysical(.clear) }
        }) {
            escapeMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            // In a dialog, Esc belongs to the dialog. Calibrating needs the ruler to still be there afterwards.
            if isEscape(event), NSApp.modalWindow == nil { self?.receivePhysical(.clear) }
            return event
        }) {
            escapeMonitors.append(local)
        }
    }

    /// Everything that exists only while something is on screen starts and stops here.
    private func sessionChanged() {
        if state.session.isEmpty {
            if let monitor = pointerMonitor {
                NSEvent.removeMonitor(monitor)
                pointerMonitor = nil
            }
        } else if pointerMonitor == nil {
            pointerMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            ) { [weak self] _ in
                self?.receivePhysical(.pointerMoved(NSEvent.mouseLocation))
            }
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

#if DEBUG
extension OverlayWindowController: VirtualInputTarget {
    /// Reads the panels themselves, so a scripted click meets the same gate as a real one.
    var capturesClicks: Bool { overlays.contains { !$0.panel.ignoresMouseEvents } }
    var configuredModifier: ModifierKey { settings.modifierKey }
    var mainDisplayHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    var summary: String {
        let session = state.session
        return "points=\(session.points.count) pins=\(session.pins.count) ruler=\(session.hasRuler) angles=\(session.angles.count) held=\(state.modifierHeld) capturing=\(capturesClicks)"
    }

    func screen(at point: CGPoint) -> (frame: CGRect, pointsPerUnit: CGFloat)? {
        // Closed on every side, because the pointer on a screen's top row reports exactly maxY.
        let match = overlays.first {
            let frame = $0.screen.frame
            return point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
        }
        return match.map { ($0.screen.frame, pointsPerUnit(on: $0.screen)) }
    }

    func send(_ input: OverlayInput) {
        receive(input)
    }

    func setPhysicalInputEnabled(_ enabled: Bool) {
        physicalInputEnabled = enabled
    }
}
#endif
