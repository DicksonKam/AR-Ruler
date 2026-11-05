import AppKit
import SwiftUI

final class OverlayContentView: NSView {
    var onPointAdded: ((NSPoint) -> Void)?
    var onClear: (() -> Void)?
    var points: [NSPoint] = []
    var displayInInches: Bool = false

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawMeasurements()
    }

    override func mouseDown(with event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)

        if event.type == .rightMouseDown || event.type == .otherMouseDown {
            onClear?()
            return
        }

        onPointAdded?(locationInView)
    }

    override func rightMouseDown(with event: NSEvent) {
        onClear?()
    }

    private func drawMeasurements() {
        guard let context = NSGraphicsContext.current?.cgContext,
              let window = self.window else { return }

        let screen = points.first.flatMap { ScreenHelper.screenContaining(point: $0) }
            ?? NSScreen.main ?? NSScreen.screens.first
        let pointsPerCm = screen.map { CalibrationManager.shared.pointsPerCm(for: $0) } ?? CalibrationManager.shared.defaultPointsPerCm
        let useInches = AppSettings.shared.unit == .inch

        let pointsInView = points.map { window.convertPoint(fromScreen: $0) }

        for point in pointsInView {
            drawPoint(at: point, in: context)
        }

        if pointsInView.count >= 2 {
            drawLine(from: pointsInView[0], to: pointsInView[1], in: context)
            let m1 = MeasurementEngine.twoPointMeasurement(p1: points[0], p2: points[1], pointsPerCm: pointsPerCm)
            let mid1 = midPoint(pointsInView[0], pointsInView[1])
            let value = useInches ? m1.distanceInch : m1.distanceCm
            let unitStr = useInches ? "in" : "cm"
            drawLabel("\(String(format: "%.2f", value)) \(unitStr)", at: mid1, in: context)
        }

        if pointsInView.count >= 3 {
            drawLine(from: pointsInView[1], to: pointsInView[2], in: context)
            let m2 = MeasurementEngine.twoPointMeasurement(p1: points[1], p2: points[2], pointsPerCm: pointsPerCm)
            let mid2 = midPoint(pointsInView[1], pointsInView[2])
            let value2 = useInches ? m2.distanceInch : m2.distanceCm
            let unitStr = useInches ? "in" : "cm"
            drawLabel("\(String(format: "%.2f", value2)) \(unitStr)", at: mid2, in: context)

            if pointsInView.count == 3 {
                let result = MeasurementEngine.threePointMeasurement(
                    a: points[0], b: points[1], c: points[2],
                    pointsPerCm: pointsPerCm
                )
                let angleLabel = "\(String(format: "%.1f", result.angleDeg))°"
                drawLabel(angleLabel, at: pointsInView[1], in: context, offset: 20)
            }
        }

        if pointsInView.count >= 4 {
            drawLine(from: pointsInView[2], to: pointsInView[3], in: context)
            let m3 = MeasurementEngine.twoPointMeasurement(p1: points[2], p2: points[3], pointsPerCm: pointsPerCm)
            let mid3 = midPoint(pointsInView[2], pointsInView[3])
            let value3 = useInches ? m3.distanceInch : m3.distanceCm
            let unitStr = useInches ? "in" : "cm"
            drawLabel("\(String(format: "%.2f", value3)) \(unitStr)", at: mid3, in: context)

            let result4 = MeasurementEngine.fourPointMeasurement(
                a: points[0], b: points[1], c: points[2], d: points[3],
                pointsPerCm: pointsPerCm
            )
            let angleBLabel = "\(String(format: "%.1f", result4.angleB))°"
            let angleCLabel = "\(String(format: "%.1f", result4.angleC))°"
            drawLabel(angleBLabel, at: pointsInView[1], in: context, offset: 20)
            drawLabel(angleCLabel, at: pointsInView[2], in: context, offset: 20)
        }
    }

    private func drawPoint(at point: NSPoint, in context: CGContext) {
        let radius: CGFloat = 6
        let rect = NSRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.8).cgColor)
        context.fillEllipse(in: rect)
    }

    private func drawLine(from p1: NSPoint, to p2: NSPoint, in context: CGContext) {
        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(2)
        context.move(to: p1)
        context.addLine(to: p2)
        context.strokePath()
    }

    private func drawLabel(_ text: String, at point: NSPoint, in context: CGContext, offset: CGFloat = 10) {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        let rect = NSRect(
            x: point.x - size.width / 2 - 4,
            y: point.y + offset - 2,
            width: size.width + 8,
            height: size.height + 4
        )
        NSColor.controlBackgroundColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        attributed.draw(in: NSRect(x: rect.minX + 4, y: rect.minY + 2, width: size.width, height: size.height))
    }

    private func midPoint(_ p1: NSPoint, _ p2: NSPoint) -> NSPoint {
        NSPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
    }
}
