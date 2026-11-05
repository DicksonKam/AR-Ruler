import CoreGraphics
import Foundation

/// An infinite straight line with a zero point and a direction. Positions along it are in screen points.
struct RulerLine: Equatable {
    let origin: CGPoint
    /// Unit vector pointing from zero towards positive readings.
    let direction: CGVector

    /// Returns nil when the two points coincide, because the direction would be undefined.
    init?(from start: CGPoint, through end: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.000_001 else { return nil }
        origin = start
        direction = CGVector(dx: dx / length, dy: dy / length)
    }

    /// Signed reading at the foot of the perpendicular dropped from `point`.
    func position(of point: CGPoint) -> CGFloat {
        (point.x - origin.x) * direction.dx + (point.y - origin.y) * direction.dy
    }

    func point(at position: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + direction.dx * position, y: origin.y + direction.dy * position)
    }

    func perpendicularDistance(to point: CGPoint) -> CGFloat {
        abs((point.x - origin.x) * direction.dy - (point.y - origin.y) * direction.dx)
    }

    /// Angle of the direction above the horizontal, in degrees, in (-180, 180].
    var angleDegrees: Double {
        Double(atan2(direction.dy, direction.dx)) * 180 / .pi
    }

    /// Tilt from horizontal in (-90, 90], the same whichever end was clicked first. Positive rises to the
    /// right on screen. AppKit's y runs upwards, so that's the plain sign of the slope.
    var tiltDegrees: Double {
        var tilt = angleDegrees
        if tilt > 90 { tilt -= 180 }
        if tilt <= -90 { tilt += 180 }
        return tilt
    }

    /// The stretch of the line inside `rect`, as positions along the line. Nil if it misses the rect.
    func clipped(to rect: CGRect) -> ClosedRange<CGFloat>? {
        var lower = -CGFloat.greatestFiniteMagnitude
        var upper = CGFloat.greatestFiniteMagnitude
        let axes: [(origin: CGFloat, delta: CGFloat, min: CGFloat, max: CGFloat)] = [
            (origin.x, direction.dx, rect.minX, rect.maxX),
            (origin.y, direction.dy, rect.minY, rect.maxY)
        ]
        for axis in axes {
            if abs(axis.delta) < 0.000_001 {
                if axis.origin < axis.min || axis.origin > axis.max { return nil }
                continue
            }
            let a = (axis.min - axis.origin) / axis.delta
            let b = (axis.max - axis.origin) / axis.delta
            lower = max(lower, min(a, b))
            upper = min(upper, max(a, b))
        }
        return lower <= upper ? lower...upper : nil
    }
}

enum RulerSnap {
    private static let diagonal = CGFloat(0.5).squareRoot()
    /// Exact values, so that snapped horizontals and verticals carry no floating point noise.
    private static let directions: [CGVector] = [
        CGVector(dx: 1, dy: 0),
        CGVector(dx: diagonal, dy: diagonal),
        CGVector(dx: 0, dy: 1),
        CGVector(dx: -diagonal, dy: diagonal),
        CGVector(dx: -1, dy: 0),
        CGVector(dx: -diagonal, dy: -diagonal),
        CGVector(dx: 0, dy: -1),
        CGVector(dx: diagonal, dy: -diagonal)
    ]

    /// Rotates `point` around `pivot` to the nearest multiple of 45°, keeping its distance.
    static func snap(_ point: CGPoint, around pivot: CGPoint) -> CGPoint {
        let dx = point.x - pivot.x
        let dy = point.y - pivot.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return point }
        var octant = Int((atan2(dy, dx) / (.pi / 4)).rounded()) % 8
        if octant < 0 { octant += 8 }
        let direction = directions[octant]
        return CGPoint(x: pivot.x + direction.dx * length, y: pivot.y + direction.dy * length)
    }
}

/// Assigns labels that sit along a line to lanes so that none overlap. Input must be sorted by `lowerBound`.
enum LabelLanes {
    static func assign(_ spans: [ClosedRange<CGFloat>]) -> [Int] {
        var laneEnds: [CGFloat] = []
        return spans.map { span in
            if let lane = laneEnds.firstIndex(where: { $0 < span.lowerBound }) {
                laneEnds[lane] = span.upperBound
                return lane
            }
            laneEnds.append(span.upperBound)
            return laneEnds.count - 1
        }
    }
}
