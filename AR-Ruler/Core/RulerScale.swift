import CoreGraphics
import Foundation

enum RulerUnit: String, CaseIterable {
    case cm
    case inch

    var symbol: String { self == .cm ? "cm" : "in" }
    var cmPerUnit: CGFloat { self == .cm ? 1 : 2.54 }
    /// Smallest divisions in one whole unit: millimetres, or eighths of an inch.
    var minorPerMajor: Int { self == .cm ? 10 : 8 }
    /// Smallest divisions in one middle division: 5 mm, or 1/2 inch.
    var minorPerMid: Int { self == .cm ? 5 : 4 }
}

enum TickLevel: Int, Comparable {
    case minor, mid, major
    static func < (a: TickLevel, b: TickLevel) -> Bool { a.rawValue < b.rawValue }
}

struct RulerTick: Equatable {
    let position: CGFloat
    let level: TickLevel
    /// The whole-unit reading, for major ticks only.
    let value: Int?
}

/// Converts between screen points and a physical unit, and lays out tick marks.
struct RulerScale: Equatable {
    /// Levels closer together than this many points are hidden rather than turning into a smear.
    static let minimumTickSpacing: CGFloat = 3

    let unit: RulerUnit
    let pointsPerCm: CGFloat

    var pointsPerUnit: CGFloat { pointsPerCm * unit.cmPerUnit }
    var pointsPerMinor: CGFloat { pointsPerUnit / CGFloat(unit.minorPerMajor) }
    var pointsPerMid: CGFloat { pointsPerMinor * CGFloat(unit.minorPerMid) }

    func value(ofPoints points: CGFloat) -> Double {
        Double(points / pointsPerUnit)
    }

    var finestVisibleLevel: TickLevel {
        if pointsPerMinor >= Self.minimumTickSpacing { return .minor }
        if pointsPerMid >= Self.minimumTickSpacing { return .mid }
        return .major
    }

    /// Ticks within `range` (positions in points). Counted in integers so that errors don't accumulate.
    func ticks(in range: ClosedRange<CGFloat>) -> [RulerTick] {
        guard pointsPerCm > 0 else { return [] }
        let stride: Int
        switch finestVisibleLevel {
        case .minor: stride = 1
        case .mid: stride = unit.minorPerMid
        case .major: stride = unit.minorPerMajor
        }
        let spacing = pointsPerMinor * CGFloat(stride)
        let first = Int((range.lowerBound / spacing).rounded(.up))
        let last = Int((range.upperBound / spacing).rounded(.down))
        guard first <= last else { return [] }
        return (first...last).map { step in
            let index = step * stride
            let position = CGFloat(index) * pointsPerMinor
            if index % unit.minorPerMajor == 0 {
                return RulerTick(position: position, level: .major, value: index / unit.minorPerMajor)
            }
            return RulerTick(position: position, level: index % unit.minorPerMid == 0 ? .mid : .minor, value: nil)
        }
    }

    /// Every how many whole units to label, given how much room one label takes along the line.
    func labelStride(forLabelExtent extent: CGFloat) -> Int {
        for stride in [1, 2, 5, 10, 20, 50, 100] where CGFloat(stride) * pointsPerUnit >= extent {
            return stride
        }
        return 200
    }
}

enum ReadingFormat {
    private static let minus = "\u{2212}"

    private static func signed(_ value: Double, decimals: Int) -> String {
        let text = String(format: "%.\(decimals)f", abs(value))
        let roundsToZero = !text.contains { $0 != "0" && $0 != "." }
        return value < 0 && !roundsToZero ? minus + text : text
    }

    static func reading(_ points: CGFloat, scale: RulerScale) -> String {
        "\(signed(scale.value(ofPoints: points), decimals: 2)) \(scale.unit.symbol)"
    }

    static func gap(_ points: CGFloat, scale: RulerScale) -> String {
        "\u{0394} \(signed(scale.value(ofPoints: points), decimals: 2))"
    }

    static func tickLabel(_ value: Int) -> String {
        value < 0 ? minus + String(-value) : String(value)
    }

    /// A line's tilt. Vertical is always 90.0°: a value that would print as −90.0° after rounding is vertical too.
    static func tilt(_ degrees: Double) -> String {
        let rounded = (degrees * 10).rounded() / 10
        return abs(rounded) == 90 ? "90.0\u{00B0}" : angle(rounded)
    }

    static func angle(_ degrees: Double) -> String {
        "\(signed(degrees, decimals: 1))\u{00B0}"
    }
}
