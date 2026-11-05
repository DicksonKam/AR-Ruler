import AppKit

/// One screen's transparent overlay. It draws the scene and reports mouse activity in global screen points.
final class OverlayContentView: NSView {
    var sceneProvider: (() -> RulerScene?)?
    var onPress: ((CGPoint, NSEvent) -> Void)?
    var onDrag: ((CGPoint, NSEvent) -> Void)?
    var onRelease: ((CGPoint, NSEvent) -> Void)?
    var onMove: ((CGPoint, NSEvent) -> Void)?
    var onClear: (() -> Void)?

    let screenFrame: CGRect

    init(screenFrame: CGRect) {
        self.screenFrame = screenFrame
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    /// The first click counts, with no click needed to bring the overlay forward first.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // Global monitors go quiet while the pointer is over this window, so moves are tracked here then.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let scene = sceneProvider?() else { return }
        context.saveGState()
        context.translateBy(x: -screenFrame.minX, y: -screenFrame.minY)
        RulerRenderer.draw(scene, dirty: dirtyRect.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY))
        context.restoreGState()
    }

    /// Marks a region given in global screen points for redraw.
    func invalidate(globalRect rect: CGRect) {
        guard !rect.isNull else { return }
        setNeedsDisplay(rect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY).integral)
    }

    private func globalLocation(of event: NSEvent) -> CGPoint {
        CGPoint(x: event.locationInWindow.x + screenFrame.minX, y: event.locationInWindow.y + screenFrame.minY)
    }

    override func mouseDown(with event: NSEvent) { onPress?(globalLocation(of: event), event) }
    override func mouseDragged(with event: NSEvent) { onDrag?(globalLocation(of: event), event) }
    override func mouseUp(with event: NSEvent) { onRelease?(globalLocation(of: event), event) }
    override func mouseMoved(with event: NSEvent) { onMove?(globalLocation(of: event), event) }
    override func rightMouseDown(with event: NSEvent) { onClear?() }
    override func otherMouseDown(with event: NSEvent) { onClear?() }
}
