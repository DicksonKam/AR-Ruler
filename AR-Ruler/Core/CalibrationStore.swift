import CoreGraphics
import Foundation

/// A user-measured scale for one display. It records the screen size it was taken at, so it still
/// holds when the display switches to another scaled resolution or is rotated.
struct CalibrationOverride: Codable, Equatable {
    static let plausiblePointsPerCm: ClosedRange<CGFloat> = 5...500

    let pointsPerCm: CGFloat
    /// The screen's longer side in points when calibrated.
    let longEdgePoints: CGFloat

    func pointsPerCm(forLongEdge currentLongEdge: CGFloat) -> CGFloat {
        guard longEdgePoints > 0 else { return pointsPerCm }
        return pointsPerCm * currentLongEdge / longEdgePoints
    }

    /// Nil if the numbers can't be a real calibration, such as a typo that implies an absurd scale.
    static func measured(rulerLengthPoints: CGFloat, trueLengthCm: CGFloat, longEdgePoints: CGFloat) -> CalibrationOverride? {
        guard rulerLengthPoints > 0, trueLengthCm > 0, longEdgePoints > 0 else { return nil }
        let pointsPerCm = rulerLengthPoints / trueLengthCm
        guard plausiblePointsPerCm.contains(pointsPerCm) else { return nil }
        return CalibrationOverride(pointsPerCm: pointsPerCm, longEdgePoints: longEdgePoints)
    }
}

/// Persists one override per display, keyed by the display's identifier.
struct CalibrationStore {
    private static let key = "ARRuler_DisplayCalibrations"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func all() -> [String: CalibrationOverride] {
        guard let data = defaults.data(forKey: Self.key) else { return [:] }
        return (try? JSONDecoder().decode([String: CalibrationOverride].self, from: data)) ?? [:]
    }

    private func write(_ overrides: [String: CalibrationOverride]) {
        if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: Self.key)
        }
    }

    func override(forDisplay display: String) -> CalibrationOverride? {
        all()[display]
    }

    func save(_ override: CalibrationOverride, forDisplay display: String) {
        var overrides = all()
        overrides[display] = override
        write(overrides)
    }

    func reset(display: String) {
        var overrides = all()
        overrides[display] = nil
        write(overrides)
    }
}
