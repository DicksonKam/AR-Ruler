import AppKit

/// Everything that can happen to the overlay. Every kind of input, whatever its source, comes through here.
enum OverlayInput: Equatable {
    /// The modifier keys changed. `pointer` is where the mouse is now, if the source knows.
    case modifiers(NSEvent.ModifierFlags, pointer: CGPoint?)
    case pointerMoved(CGPoint)
    /// A mouse press that reached the overlay, on the screen with this frame and scale.
    case press(CGPoint, frame: CGRect, pointsPerUnit: CGFloat)
    case drag(CGPoint, NSEvent.ModifierFlags)
    case release(CGPoint, NSEvent.ModifierFlags)
    /// Esc, right-click and the menu's Clear Measurement.
    case clear
}

/// The overlay's state and the rules for how input changes it. There are no windows in here, and the
/// app's controller adds only delivering input to it and redrawing.
struct OverlayInputState {
    /// What the controller needs to redraw afterwards.
    enum Effect: Equatable {
        case nothing, pointerOnly, everything, sessionChanged
    }

    var session = RulerSession()
    var pointer: CGPoint?
    var modifierHeld = false
    var shiftHeld = false
    var modifierKey = ModifierKey.defaultKey

    /// Clicks only reach the overlay while the modifier is held. A press in progress keeps it, so its release isn't lost.
    var capturesClicks: Bool { modifierHeld || session.isPressed }

    private func snapping(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection(.deviceIndependentFlagsMask).contains(.shift)
    }

    mutating func apply(_ input: OverlayInput) -> Effect {
        switch input {
        case .modifiers(let flags, let newPointer):
            let relevant = flags.intersection(.deviceIndependentFlagsMask)
            let held = modifierKey.isHeld(in: relevant)
            let shift = relevant.contains(.shift)
            let changed = held != modifierHeld || shift != shiftHeld
            modifierHeld = held
            shiftHeld = shift
            guard changed else { return .nothing }
            pointer = newPointer ?? pointer
            if session.isDragging, let pointer {
                session.pressMoved(to: pointer, snapping: shift)
            }
            return .everything

        case .pointerMoved(let location):
            pointer = location
            return .pointerOnly

        case .press(let location, let frame, let pointsPerUnit):
            session.pointsPerUnit = pointsPerUnit
            session.pressBegan(at: location, on: frame)
            pointer = location
            return .nothing

        case .drag(let location, let flags):
            pointer = location
            shiftHeld = snapping(flags)
            session.pressMoved(to: location, snapping: shiftHeld)
            return .everything

        case .release(let location, let flags):
            pointer = location
            session.pressEnded(snapping: snapping(flags))
            return .sessionChanged

        case .clear:
            session.clear()
            return .sessionChanged
        }
    }
}
