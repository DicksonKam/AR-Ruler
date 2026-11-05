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
}
