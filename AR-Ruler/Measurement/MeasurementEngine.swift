import Foundation
import CoreGraphics

struct MeasurementEngine {
    /// Distance between two points in screen coordinates (points)
    static func distance(from p1: NSPoint, to p2: NSPoint) -> CGFloat {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }

    /// Angle at vertex B (in degrees) for points A, B, C
    /// Returns angle ABC (the angle between BA and BC)
    static func angleAtVertex(a: NSPoint, b: NSPoint, c: NSPoint) -> Double {
        let ba = NSPoint(x: a.x - b.x, y: a.y - b.y)
        let bc = NSPoint(x: c.x - b.x, y: c.y - b.y)

        let dot = ba.x * bc.x + ba.y * bc.y
        let magBA = sqrt(ba.x * ba.x + ba.y * ba.y)
        let magBC = sqrt(bc.x * bc.x + bc.y * bc.y)

        guard magBA > 0 && magBC > 0 else { return 0 }

        let cosAngle = dot / (magBA * magBC)
        let clamped = max(-1, min(1, cosAngle))
        return acos(clamped) * 180 / .pi
    }

    /// Two-point measurement: distance only
    static func twoPointMeasurement(p1: NSPoint, p2: NSPoint, pointsPerCm: CGFloat) -> (distanceCm: Double, distanceInch: Double) {
        let distPoints = distance(from: p1, to: p2)
        let distanceCm = Double(distPoints / pointsPerCm)
        let distanceInch = distanceCm / 2.54
        return (distanceCm, distanceInch)
    }

    /// Three-point measurement: two distances and angle at vertex
    static func threePointMeasurement(
        a: NSPoint, b: NSPoint, c: NSPoint,
        pointsPerCm: CGFloat
    ) -> (distAB: (cm: Double, inch: Double), distBC: (cm: Double, inch: Double), angleDeg: Double) {
        let distAB = twoPointMeasurement(p1: a, p2: b, pointsPerCm: pointsPerCm)
        let distBC = twoPointMeasurement(p1: b, p2: c, pointsPerCm: pointsPerCm)
        let angle = angleAtVertex(a: a, b: b, c: c)
        return (
            (distAB.distanceCm, distAB.distanceInch),
            (distBC.distanceCm, distBC.distanceInch),
            angle
        )
    }

    /// Four-point measurement: three distances (AB, BC, CD) and two angles (at B, at C)
    static func fourPointMeasurement(
        a: NSPoint, b: NSPoint, c: NSPoint, d: NSPoint,
        pointsPerCm: CGFloat
    ) -> (
        distAB: (cm: Double, inch: Double),
        distBC: (cm: Double, inch: Double),
        distCD: (cm: Double, inch: Double),
        angleB: Double,
        angleC: Double
    ) {
        let distAB = twoPointMeasurement(p1: a, p2: b, pointsPerCm: pointsPerCm)
        let distBC = twoPointMeasurement(p1: b, p2: c, pointsPerCm: pointsPerCm)
        let distCD = twoPointMeasurement(p1: c, p2: d, pointsPerCm: pointsPerCm)
        let angleB = angleAtVertex(a: a, b: b, c: c)
        let angleC = angleAtVertex(a: b, b: c, c: d)
        return (
            (distAB.distanceCm, distAB.distanceInch),
            (distBC.distanceCm, distBC.distanceInch),
            (distCD.distanceCm, distCD.distanceInch),
            angleB,
            angleC
        )
    }
}
