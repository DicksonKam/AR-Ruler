import AppKit
import CoreGraphics
import Foundation

final class CalibrationManager {
    static let shared = CalibrationManager()

    enum Source {
        case manual, displayReported, fallback

        var description: String {
            switch self {
            case .manual: return "calibrated by you"
            case .displayReported: return "reported by the display"
            case .fallback: return "assumed, display reports no size"
            }
        }
    }

    private let store = CalibrationStore()

    /// Fallback when EDID/physical size unavailable: 72 pts/inch, 2.54 cm/inch
    var defaultPointsPerCm: CGFloat { 72 / 2.54 }

    /// Points per cm for a screen: the user's calibration if there is one, otherwise the display's reported size.
    func pointsPerCm(for screen: NSScreen) -> CGFloat {
        if let key = displayKey(for: screen), let override = store.override(forDisplay: key) {
            return override.pointsPerCm(forLongEdge: longEdge(of: screen))
        }
        return reportedPointsPerCm(for: screen) ?? defaultPointsPerCm
    }

    func source(for screen: NSScreen) -> Source {
        if isCalibrated(screen) { return .manual }
        return reportedPointsPerCm(for: screen) == nil ? .fallback : .displayReported
    }

    func isCalibrated(_ screen: NSScreen) -> Bool {
        guard let key = displayKey(for: screen) else { return false }
        return store.override(forDisplay: key) != nil
    }

    /// Returns false if the numbers imply an impossible scale, in which case nothing is saved.
    func calibrate(_ screen: NSScreen, rulerLengthPoints: CGFloat, trueLengthCm: CGFloat) -> Bool {
        guard let key = displayKey(for: screen),
              let override = CalibrationOverride.measured(
                rulerLengthPoints: rulerLengthPoints,
                trueLengthCm: trueLengthCm,
                longEdgePoints: longEdge(of: screen)
              ) else { return false }
        store.save(override, forDisplay: key)
        return true
    }

    func resetCalibration(_ screen: NSScreen) {
        guard let key = displayKey(for: screen) else { return }
        store.reset(display: key)
    }

    private func longEdge(of screen: NSScreen) -> CGFloat {
        max(screen.frame.width, screen.frame.height)
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// A display's UUID stays the same across reboots and reconnects, unlike its CGDirectDisplayID.
    private func displayKey(for screen: NSScreen) -> String? {
        guard let id = displayID(for: screen),
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Uses CGDisplayScreenSize (mm) + NSScreen frame (points). Nil when the display reports no physical size.
    private func reportedPointsPerCm(for screen: NSScreen) -> CGFloat? {
        guard let id = displayID(for: screen) else { return nil }
        let physicalSize = CGDisplayScreenSize(id)
        guard physicalSize.width > 0, physicalSize.height > 0 else { return nil }
        let frame = screen.frame
        let pointsPerMmW = frame.width / CGFloat(physicalSize.width)
        let pointsPerMmH = frame.height / CGFloat(physicalSize.height)
        return (pointsPerMmW + pointsPerMmH) / 2 * 10
    }
}
