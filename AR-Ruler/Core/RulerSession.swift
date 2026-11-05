import CoreGraphics
import Foundation

/// Everything the user has placed on screen, and the rules for what a click or drag does to it.
/// Coordinates are global screen points (AppKit, y up). There is no drawing or AppKit in here.
///
/// Two points make a ruler: a finite body with zero at the first click. A third point placed off the
/// body turns the measurement into plain lines and angles, and the ruler and its pins go away.
struct RulerSession: Equatable {
    enum Handle: Equatable { case start, end }

    /// What the pointer is over. Decides whether a drag re-aims, slides or lengthens.
    enum Hit: Equatable { case handle(Handle), endGrip, body, offRuler }

    enum ClickOutcome: Equatable {
        case placedFirst, placedSecond, pinned, duplicatePin, addedPoint, startedNew, ignored
    }

    struct PinReading: Equatable {
        /// Where the pin sits on the ruler.
        let point: CGPoint
        let position: CGFloat
        /// Distance from the pin before it on the ruler. Nil for the lowest reading.
        let gapFromPrevious: CGFloat?
    }

    private struct Press: Equatable {
        let start: CGPoint
        let frame: CGRect
        let hit: Hit?
        let originalPoints: [CGPoint]
        let originalEnd: CGFloat
        var moved: Bool
    }

    static let maximumPoints = 4
    /// How far outside the body a click still counts as on the ruler.
    static let pinTolerance: CGFloat = 8
    static let handleTolerance: CGFloat = 10
    static let gripTolerance: CGFloat = 10
    /// Movement under this is a shaky click rather than a drag.
    static let dragThreshold: CGFloat = 3
    static let minimumRulerLength: CGFloat = 2
    /// Pins closer together than this would just be the same click twice.
    static let duplicatePinDistance: CGFloat = 0.5
    /// Depth of the ruler's body, measured from the measuring edge.
    static let bodyDepth: CGFloat = 32
    /// Blank body beyond the first and last marks, like the ends of a real ruler.
    static let bodyMargin: CGFloat = 12

    /// points[0] is zero on the ruler and points[1] sets its direction. Further points replace the ruler with an angle measurement.
    private(set) var points: [CGPoint] = []
    /// The clicked screen positions. Readings are projected from them, so pins stay with what they
    /// marked on screen and their readings follow when the ruler is fine-tuned.
    private(set) var pinSources: [CGPoint] = []
    /// The screen this measurement belongs to.
    private(set) var bounds: CGRect?
    /// One whole unit (a cm or an inch) in points, used to fit the ruler's length.
    var pointsPerUnit: CGFloat = 72 / 2.54
    /// The last mark's position once the user has dragged the grip. Nil keeps the ruler fitted to its two points.
    private var customEnd: CGFloat?
    private var press: Press?

    var isEmpty: Bool { points.isEmpty }
    var hasRuler: Bool { points.count == 2 }
    var isAngleMeasurement: Bool { points.count > 2 }
    var isDragging: Bool { press?.moved == true }
    var isPressed: Bool { press != nil }

    var line: RulerLine? {
        hasRuler ? RulerLine(from: points[0], through: points[1]) : nil
    }

    var rulerLength: CGFloat? {
        hasRuler ? MeasurementEngine.distance(from: points[0], to: points[1]) : nil
    }

    // MARK: The ruler's extent

    private var visibleRange: ClosedRange<CGFloat>? {
        guard let line, let bounds else { return nil }
        return line.clipped(to: bounds)
    }

    /// Positions of the first and last marks. Starts at zero and ends on a whole unit at least one unit past the second point.
    var scaleRange: ClosedRange<CGFloat>? {
        guard let length = rulerLength, let visible = visibleRange, pointsPerUnit > 0 else { return nil }
        let fitted = ((length + pointsPerUnit) / pointsPerUnit).rounded(.up) * pointsPerUnit
        var end = max(customEnd ?? fitted, length)
        let lastOnScreen = visible.upperBound - Self.bodyMargin
        if end > lastOnScreen {
            // Stops at the last whole unit that fits on screen with its margin, but never short of the second point.
            end = max((lastOnScreen / pointsPerUnit).rounded(.down) * pointsPerUnit, length)
        }
        return 0...end
    }

    /// The physical extent of the body along the line, cut off at the screen edge.
    var bodyRange: ClosedRange<CGFloat>? {
        guard let scale = scaleRange, let visible = visibleRange else { return nil }
        return max(-Self.bodyMargin, visible.lowerBound)...min(scale.upperBound + Self.bodyMargin, visible.upperBound)
    }

    /// Which side of the measuring edge the body lies on: up or left, unless that wouldn't fit on screen.
    var bodySide: CGVector? {
        guard let line, let body = bodyRange, let bounds else { return nil }
        var side = CGVector(dx: -line.direction.dy, dy: line.direction.dx)
        let pointsUpOrLeft = abs(side.dy) < 0.01 ? side.dx < 0 : side.dy > 0
        if !pointsUpOrLeft { side = CGVector(dx: -side.dx, dy: -side.dy) }
        func fits(_ candidate: CGVector) -> Bool {
            [body.lowerBound, body.upperBound].allSatisfy { position in
                let foot = line.point(at: position)
                let corner = CGPoint(x: foot.x + candidate.dx * Self.bodyDepth, y: foot.y + candidate.dy * Self.bodyDepth)
                return Self.contains(bounds, corner)
            }
        }
        let opposite = CGVector(dx: -side.dx, dy: -side.dy)
        return !fits(side) && fits(opposite) ? opposite : side
    }

    /// The centre of the grab handle on the far end of the body.
    var gripPoint: CGPoint? {
        guard let line, let body = bodyRange, let side = bodySide else { return nil }
        let foot = line.point(at: body.upperBound)
        return CGPoint(x: foot.x + side.dx * Self.bodyDepth / 2, y: foot.y + side.dy * Self.bodyDepth / 2)
    }

    /// Whether a point is on the body or within tolerance of it.
    func isNearBody(_ point: CGPoint) -> Bool {
        guard let line, let body = bodyRange, let side = bodySide else { return false }
        let along = line.position(of: point)
        let across = (point.x - line.origin.x) * side.dx + (point.y - line.origin.y) * side.dy
        return along >= body.lowerBound - Self.pinTolerance
            && along <= body.upperBound + Self.pinTolerance
            && across >= -Self.pinTolerance
            && across <= Self.bodyDepth + Self.pinTolerance
    }

    /// The reading for a pointer near the body, kept on the body.
    func reading(at point: CGPoint) -> CGFloat? {
        guard let line, let body = bodyRange, isNearBody(point) else { return nil }
        return min(max(line.position(of: point), body.lowerBound), body.upperBound)
    }

    /// Pins on the body, in ruler order. Any left past its ends by fine-tuning are hidden until the body reaches them again.
    var pins: [PinReading] {
        guard let line, let body = bodyRange else { return [] }
        let positions = pinSources.map { line.position(of: $0) }.filter { body.contains($0) }.sorted()
        return positions.enumerated().map { index, position in
            PinReading(
                point: line.point(at: position),
                position: position,
                gapFromPrevious: index == 0 ? nil : position - positions[index - 1]
            )
        }
    }

    /// Angle at each interior point of the measurement, keyed by the index of that point.
    var angles: [(vertex: Int, degrees: Double)] {
        guard points.count >= 3 else { return [] }
        return (1..<(points.count - 1)).map { index in
            (index, MeasurementEngine.angleAtVertex(a: points[index - 1], b: points[index], c: points[index + 1]))
        }
    }

    mutating func clear() {
        let unit = pointsPerUnit
        self = RulerSession()
        pointsPerUnit = unit
    }

    func hitTest(_ point: CGPoint) -> Hit? {
        guard hasRuler else { return nil }
        if let grip = gripPoint, MeasurementEngine.distance(from: point, to: grip) <= Self.gripTolerance { return .endGrip }
        if MeasurementEngine.distance(from: point, to: points[0]) <= Self.handleTolerance { return .handle(.start) }
        if MeasurementEngine.distance(from: point, to: points[1]) <= Self.handleTolerance { return .handle(.end) }
        return isNearBody(point) ? .body : .offRuler
    }

    /// Where a click at `point` would land once snapping is taken into account.
    func placement(for point: CGPoint, snapping: Bool) -> CGPoint {
        guard snapping, let last = points.last, points.count < Self.maximumPoints else { return point }
        return RulerSnap.snap(point, around: last)
    }

    // MARK: Clicks

    /// `frame` is the screen the click happened on.
    @discardableResult
    mutating func click(at point: CGPoint, on frame: CGRect, snapping: Bool = false) -> ClickOutcome {
        guard let bounds else {
            self.bounds = frame
            points = [point]
            return .placedFirst
        }
        guard Self.contains(bounds, point) else {
            if points.count == Self.maximumPoints { return startNew(at: point, on: frame) }
            return .ignored
        }
        if points.count == 1 {
            let placed = placement(for: point, snapping: snapping)
            guard MeasurementEngine.distance(from: points[0], to: placed) >= Self.minimumRulerLength else { return .ignored }
            points.append(placed)
            return .placedSecond
        }
        if hasRuler, isNearBody(point) { return pin(at: point) }
        guard points.count < Self.maximumPoints else { return startNew(at: point, on: frame) }
        // A third point switches to an angle measurement. Pins are readings off a scale that's now gone.
        points.append(placement(for: point, snapping: snapping))
        pinSources = []
        customEnd = nil
        return .addedPoint
    }

    private mutating func pin(at point: CGPoint) -> ClickOutcome {
        guard let line, let body = bodyRange else { return .ignored }
        let position = line.position(of: point)
        let onBody = min(max(position, body.lowerBound), body.upperBound)
        let isDuplicate = pinSources.contains { abs(line.position(of: $0) - onBody) < Self.duplicatePinDistance }
        if isDuplicate { return .duplicatePin }
        // A click just off the end is brought back onto the body, so a pin is never born hidden.
        let shift = onBody - position
        pinSources.append(CGPoint(x: point.x + line.direction.dx * shift, y: point.y + line.direction.dy * shift))
        return .pinned
    }

    private mutating func startNew(at point: CGPoint, on frame: CGRect) -> ClickOutcome {
        clear()
        bounds = frame
        points = [point]
        return .startedNew
    }

    // MARK: Press, drag, release

    mutating func pressBegan(at point: CGPoint, on frame: CGRect) {
        let onThisScreen = bounds.map { Self.contains($0, point) } ?? false
        press = Press(
            start: point,
            frame: frame,
            hit: onThisScreen ? hitTest(point) : nil,
            originalPoints: points,
            originalEnd: scaleRange?.upperBound ?? 0,
            moved: false
        )
    }

    mutating func pressMoved(to point: CGPoint, snapping: Bool = false) {
        guard var current = press else { return }
        if !current.moved {
            guard MeasurementEngine.distance(from: current.start, to: point) >= Self.dragThreshold else { return }
            current.moved = true
            press = current
        }
        guard let hit = current.hit else { return }
        let delta = CGVector(dx: point.x - current.start.x, dy: point.y - current.start.y)
        switch hit {
        case .handle(let handle):
            let index = handle == .start ? 0 : 1
            let original = current.originalPoints[index]
            // Keep the offset from where it was grabbed, so the handle doesn't jump to the pointer.
            let target = CGPoint(x: original.x + delta.dx, y: original.y + delta.dy)
            moveHandle(handle, pivot: current.originalPoints[1 - index], to: target, snapping: snapping)
        case .endGrip:
            lengthen(toward: current.originalEnd, by: delta)
        case .body:
            points = current.originalPoints
            translateRuler(by: delta)
        case .offRuler:
            break
        }
    }

    /// Returns what the release did. A drag on the ruler is finished by then; anything else counts as a click where it was pressed.
    @discardableResult
    mutating func pressEnded(snapping: Bool = false) -> ClickOutcome? {
        guard let current = press else { return nil }
        press = nil
        if current.hit == .endGrip { return nil }
        let wasRulerDrag = current.moved && (current.hit == .body || current.hit == .handle(.start) || current.hit == .handle(.end))
        if wasRulerDrag { return nil }
        return click(at: current.start, on: current.frame, snapping: snapping)
    }

    // MARK: Fine-tuning

    /// Moves the ruler without leaving the screen. Used for sliding and arrow key nudges.
    mutating func translateRuler(by delta: CGVector) {
        guard hasRuler, let bounds else { return }
        let a = points[0], b = points[1]
        let dx = min(max(delta.dx, bounds.minX - min(a.x, b.x)), bounds.maxX - max(a.x, b.x))
        let dy = min(max(delta.dy, bounds.minY - min(a.y, b.y)), bounds.maxY - max(a.y, b.y))
        points[0] = CGPoint(x: a.x + dx, y: a.y + dy)
        points[1] = CGPoint(x: b.x + dx, y: b.y + dy)
    }

    /// Changes only where the scale stops, in whole units. The two points, and so the zero and the angle, stay put.
    private mutating func lengthen(toward originalEnd: CGFloat, by delta: CGVector) {
        guard let line, let length = rulerLength, pointsPerUnit > 0 else { return }
        let dragged = originalEnd + delta.dx * line.direction.dx + delta.dy * line.direction.dy
        let whole = (dragged / pointsPerUnit).rounded() * pointsPerUnit
        let shortest = (length / pointsPerUnit).rounded(.up) * pointsPerUnit
        customEnd = max(whole, shortest)
    }

    private mutating func moveHandle(_ handle: Handle, pivot: CGPoint, to target: CGPoint, snapping: Bool) {
        guard let bounds else { return }
        var moved = CGPoint(
            x: min(max(target.x, bounds.minX), bounds.maxX),
            y: min(max(target.y, bounds.minY), bounds.maxY)
        )
        if snapping {
            let snapped = RulerSnap.snap(target, around: pivot)
            guard let line = RulerLine(from: pivot, through: snapped),
                  let visible = line.clipped(to: bounds) else { return }
            // Pulling a snapped end off screen shortens the ruler rather than breaking its angle.
            moved = line.point(at: min(MeasurementEngine.distance(from: pivot, to: snapped), visible.upperBound))
        }
        guard MeasurementEngine.distance(from: pivot, to: moved) >= Self.minimumRulerLength else { return }
        points[handle == .start ? 0 : 1] = moved
    }

    /// Top and right edges count as inside: the pointer on a screen's top row reports exactly maxY.
    private static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX - 0.001 && point.x <= rect.maxX + 0.001 && point.y >= rect.minY - 0.001 && point.y <= rect.maxY + 0.001
    }
}
