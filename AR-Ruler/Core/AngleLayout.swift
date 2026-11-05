import CoreGraphics
import Foundation

/// Places the labels of an angle measurement so that they stay clear of the lines, the arcs and each other,
/// including at tight angles. Each angle goes inside its wedge if it fits there, otherwise just outside the vertex.
/// Each length goes beside its line, on the side away from the angle.
struct AngleLayout: Equatable {
    struct Arc: Equatable {
        let vertex: CGPoint
        let radius: CGFloat
        let startAngle: CGFloat
        let sweep: CGFloat
    }

    private(set) var arcs: [Arc] = []
    /// One per interior point, in order.
    private(set) var angleBoxes: [CGRect] = []
    /// One per line, in order.
    private(set) var lengthBoxes: [CGRect] = []

    private static let labelClearance: CGFloat = 3
    private static let pointClearance: CGFloat = 7
    /// Past this far from the vertex a label no longer reads as belonging to it.
    private static let farthestAngleLabel: CGFloat = 90

    init(points: [CGPoint], lengthSizes: [CGSize], angleSizes: [CGSize], bounds: CGRect) {
        guard points.count >= 3,
              lengthSizes.count == points.count - 1,
              angleSizes.count == points.count - 2 else { return }
        let segments = (0..<(points.count - 1)).map { (points[$0], points[$0 + 1]) }

        for index in 1..<(points.count - 1) {
            let vertex = points[index]
            let toA = Self.unit(from: vertex, to: points[index - 1])
            let toC = Self.unit(from: vertex, to: points[index + 1])
            let shortest = min(
                MeasurementEngine.distance(from: vertex, to: points[index - 1]),
                MeasurementEngine.distance(from: vertex, to: points[index + 1])
            )
            let start = atan2(toA.dy, toA.dx)
            var sweep = atan2(toC.dy, toC.dx) - start
            while sweep > .pi { sweep -= 2 * .pi }
            while sweep < -.pi { sweep += 2 * .pi }
            arcs.append(Arc(vertex: vertex, radius: max(8, min(26, shortest * 0.35)), startAngle: start, sweep: sweep))
        }

        func isClear(_ box: CGRect, taken: [CGRect]) -> Bool {
            guard bounds.insetBy(dx: 4, dy: 4).contains(box) else { return false }
            let padded = box.insetBy(dx: -Self.labelClearance, dy: -Self.labelClearance)
            if segments.contains(where: { Self.segment($0.0, $0.1, intersects: padded) }) { return false }
            if taken.contains(where: { $0.intersects(padded) }) { return false }
            if points.contains(where: { Self.distance(from: $0, to: box) < Self.pointClearance }) { return false }
            return !arcs.contains { Self.distance(from: $0.vertex, to: box) < $0.radius + 2 }
        }

        func box(_ size: CGSize, centredOn centre: CGPoint) -> CGRect {
            CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height)
        }

        func kept(_ rect: CGRect) -> CGRect {
            var result = rect
            result.origin.x = min(max(result.minX, bounds.minX + 4), bounds.maxX - 4 - result.width)
            result.origin.y = min(max(result.minY, bounds.minY + 4), bounds.maxY - 4 - result.height)
            return result
        }

        var taken: [CGRect] = []
        // Angles first, since they have fewer good places to go.
        for (arcIndex, arc) in arcs.enumerated() {
            let size = angleSizes[arcIndex]
            let toA = Self.unit(from: arc.vertex, to: points[arcIndex])
            let toC = Self.unit(from: arc.vertex, to: points[arcIndex + 2])
            var inward = CGVector(dx: toA.dx + toC.dx, dy: toA.dy + toC.dy)
            let length = hypot(inward.dx, inward.dy)
            inward = length > 0.01
                ? CGVector(dx: inward.dx / length, dy: inward.dy / length)
                : CGVector(dx: -toA.dy, dy: toA.dx)
            let outward = CGVector(dx: -inward.dx, dy: -inward.dy)
            var placed: CGRect?
            for direction in [inward, outward] where placed == nil {
                var distance = arc.radius + 4
                while distance <= Self.farthestAngleLabel {
                    let centre = CGPoint(x: arc.vertex.x + direction.dx * distance, y: arc.vertex.y + direction.dy * distance)
                    let candidate = box(size, centredOn: centre)
                    if isClear(candidate, taken: taken) {
                        placed = candidate
                        break
                    }
                    distance += 3
                }
            }
            let fallback = box(size, centredOn: CGPoint(
                x: arc.vertex.x + outward.dx * (arc.radius + 16),
                y: arc.vertex.y + outward.dy * (arc.radius + 16)
            ))
            let result = placed ?? kept(fallback)
            angleBoxes.append(result)
            taken.append(result)
        }

        for (index, segment) in segments.enumerated() {
            let size = lengthSizes[index]
            let direction = Self.unit(from: segment.0, to: segment.1)
            var away = CGVector(dx: -direction.dy, dy: direction.dx)
            // The first line's angle is at its end, every other line's is at its start.
            let otherArm: CGVector = index == 0
                ? Self.unit(from: points[1], to: points[2])
                : Self.unit(from: points[index], to: points[index - 1])
            if away.dx * otherArm.dx + away.dy * otherArm.dy > 0 { away = CGVector(dx: -away.dx, dy: -away.dy) }
            let reach = abs(away.dx) * size.width + abs(away.dy) * size.height

            var placed: CGRect?
            search: for side in [away, CGVector(dx: -away.dx, dy: -away.dy)] {
                for offset in stride(from: reach / 2 + 5, through: reach / 2 + 53, by: 8) {
                    for along in [0.5, 0.38, 0.62, 0.26, 0.74] as [CGFloat] {
                        let centre = CGPoint(
                            x: segment.0.x + (segment.1.x - segment.0.x) * along + side.dx * offset,
                            y: segment.0.y + (segment.1.y - segment.0.y) * along + side.dy * offset
                        )
                        let candidate = box(size, centredOn: centre)
                        if isClear(candidate, taken: taken) {
                            placed = candidate
                            break search
                        }
                    }
                }
            }
            let middle = CGPoint(
                x: (segment.0.x + segment.1.x) / 2 + away.dx * (reach / 2 + 5),
                y: (segment.0.y + segment.1.y) / 2 + away.dy * (reach / 2 + 5)
            )
            let result = placed ?? kept(box(size, centredOn: middle))
            lengthBoxes.append(result)
            taken.append(result)
        }
    }

    private static func unit(from a: CGPoint, to b: CGPoint) -> CGVector {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(hypot(dx, dy), 0.000_001)
        return CGVector(dx: dx / length, dy: dy / length)
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    /// Whether the segment from a to b passes through the rect.
    static func segment(_ a: CGPoint, _ b: CGPoint, intersects rect: CGRect) -> Bool {
        var lower: CGFloat = 0
        var upper: CGFloat = 1
        let axes: [(origin: CGFloat, delta: CGFloat, min: CGFloat, max: CGFloat)] = [
            (a.x, b.x - a.x, rect.minX, rect.maxX),
            (a.y, b.y - a.y, rect.minY, rect.maxY)
        ]
        for axis in axes {
            if abs(axis.delta) < 0.000_001 {
                if axis.origin < axis.min || axis.origin > axis.max { return false }
                continue
            }
            let first = (axis.min - axis.origin) / axis.delta
            let second = (axis.max - axis.origin) / axis.delta
            lower = max(lower, min(first, second))
            upper = min(upper, max(first, second))
            if lower > upper { return false }
        }
        return true
    }
}
