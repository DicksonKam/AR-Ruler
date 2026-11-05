import AppKit
import CoreGraphics
import Foundation

final class CalibrationManager {
    static let shared = CalibrationManager()

    /// Fallback when EDID/physical size unavailable: 72 pts/inch, 2.54 cm/inch
    var defaultPointsPerCm: CGFloat { 72 / 2.54 }

    /// Points per cm for a screen using physical dimensions from EDID when available.
    /// Uses CGDisplayScreenSize (mm) + NSScreen frame (points) for accurate conversion.
    func pointsPerCm(for screen: NSScreen) -> CGFloat {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return defaultPointsPerCm
        }
        let physicalSize = CGDisplayScreenSize(displayID.uint32Value)
        guard physicalSize.width > 0, physicalSize.height > 0 else {
            return defaultPointsPerCm
        }
        let frame = screen.frame
        let pointsWide = frame.width
        let pointsHigh = frame.height
        let mmWide = CGFloat(physicalSize.width)
        let mmHigh = CGFloat(physicalSize.height)
        let pointsPerMmW = pointsWide / mmWide
        let pointsPerMmH = pointsHigh / mmHigh
        let pointsPerMm = (pointsPerMmW + pointsPerMmH) / 2
        return pointsPerMm * 10
    }
}
