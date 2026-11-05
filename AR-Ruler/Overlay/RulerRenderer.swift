import AppKit

/// Everything needed to draw one screen's overlay. Coordinates are global screen points.
struct RulerScene {
    var session: RulerSession
    var scale: RulerScale
    var screenFrame: CGRect
    var backingScale: CGFloat
    /// Nil hides the live reading.
    var pointer: CGPoint?
    var modifierHeld = false
    var shiftHeld = false
}

private enum Style {
    // Pale ink on a translucent dark body holds up on any background, since the overlay can't see what's
    // behind it. The body lies on one side of the measuring edge, leaving the other side clear.
    static let ink = NSColor.white
    static let halo = NSColor(srgbRed: 0.04, green: 0.05, blue: 0.08, alpha: 1)
    static let bodyFill = NSColor(srgbRed: 0.06, green: 0.07, blue: 0.10, alpha: 0.6)
    static let bodyEdge = NSColor(white: 1, alpha: 0.42)
    static let accent = NSColor(srgbRed: 0.16, green: 0.56, blue: 1.00, alpha: 1)
    /// Brighter, because the live marker has to stand out against the dark body as well as the page.
    static let liveMarker = NSColor(srgbRed: 0.42, green: 0.76, blue: 1.00, alpha: 1)
    static let pin = NSColor(srgbRed: 1.00, green: 0.71, blue: 0.16, alpha: 1)
    static let chipFill = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.12, alpha: 0.92)
    static let chipEdge = NSColor(white: 1, alpha: 0.16)
    static let mutedText = NSColor(white: 1, alpha: 0.68)

    static let lineWidth: CGFloat = 1
    static let haloWidth: CGFloat = 3
    static let haloAlpha: CGFloat = 0.62

    static let minorTick: CGFloat = 5
    static let midTick: CGFloat = 8
    static let majorTick: CGFloat = 12
    static let labelGap: CGFloat = 1
    static let handleRadius: CGFloat = 4.5
    static let vertexRadius: CGFloat = 3

    static let tickFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    static let zeroFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
    static let chipFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    static let chipDetailFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
}

private struct Chip {
    enum Kind { case neutral, live, willPin }
    var lines: [NSAttributedString]
    var kind: Kind = .neutral

    init(_ text: String, detail: String? = nil, kind: Kind = .neutral) {
        self.kind = kind
        let color: NSColor = kind == .willPin ? Style.halo : .white
        lines = [NSAttributedString(string: text, attributes: [.font: Style.chipFont, .foregroundColor: color])]
        if let detail {
            lines.append(NSAttributedString(string: detail, attributes: [.font: Style.chipDetailFont, .foregroundColor: Style.mutedText]))
        }
    }

    var size: CGSize {
        let sizes = lines.map { $0.size() }
        return CGSize(
            width: ceil((sizes.map(\.width).max() ?? 0) + 12),
            height: ceil(sizes.map(\.height).reduce(0, +) + 5)
        )
    }
}

enum RulerRenderer {
    // MARK: Layout shared by drawing and invalidation

    /// The ruler as drawn.
    private struct Layout {
        /// Clicks land on a pixel, so drawing through pixel centres keeps level and plumb rulers one crisp pixel wide.
        let line: RulerLine
        let body: ClosedRange<CGFloat>
        let scale: ClosedRange<CGFloat>
        /// The side the body, ticks and labels lie on. Pins and the length chip use the other side.
        let side: CGVector
        let isAxisAligned: Bool
    }

    private static func pixelCentre(_ point: CGPoint, scale: CGFloat) -> CGPoint {
        // A pointer position names the pixel to its right and below, since y runs upwards.
        CGPoint(x: (floor(point.x * scale) + 0.5) / scale, y: (ceil(point.y * scale) - 0.5) / scale)
    }

    private static func layout(for scene: RulerScene) -> Layout? {
        let session = scene.session
        guard session.hasRuler,
              let body = session.bodyRange,
              let range = session.scaleRange,
              let side = session.bodySide else { return nil }
        let a = pixelCentre(session.points[0], scale: scene.backingScale)
        let b = pixelCentre(session.points[1], scale: scene.backingScale)
        guard let line = RulerLine(from: a, through: b) else { return nil }
        let isAxisAligned = abs(line.direction.dx) < 0.000_001 || abs(line.direction.dy) < 0.000_001
        return Layout(line: line, body: body, scale: range, side: side, isAxisAligned: isAxisAligned)
    }

    /// How far a horizontal box of `size` reaches when measured along a direction.
    private static func extent(of size: CGSize, along direction: CGVector) -> CGFloat {
        abs(direction.dx) * size.width + abs(direction.dy) * size.height
    }

    private static func offset(_ point: CGPoint, _ vector: CGVector, by distance: CGFloat) -> CGPoint {
        CGPoint(x: point.x + vector.dx * distance, y: point.y + vector.dy * distance)
    }

    private static func rect(_ size: CGSize, centredOn centre: CGPoint) -> CGRect {
        CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height)
    }

    private static func kept(_ rect: CGRect, inside frame: CGRect) -> CGRect {
        var result = rect
        result.origin.x = min(max(result.minX, frame.minX + 4), frame.maxX - 4 - result.width)
        result.origin.y = min(max(result.minY, frame.minY + 4), frame.maxY - 4 - result.height)
        return result
    }

    /// Ruler direction as a tilt in (-90, 90], since a ruler has no up or down of its own.
    private static func displayAngle(_ degrees: Double) -> Double {
        var angle = degrees
        if angle > 90 { angle -= 180 }
        if angle <= -90 { angle += 180 }
        return angle
    }

    // MARK: Live reading

    private struct LiveLayout {
        var markerPoint: CGPoint?
        var markerChip: Chip?
        var markerChipRect: CGRect = .null
        var willPin = false
        var rubberBand: (from: CGPoint, to: CGPoint)?
        var rubberChip: Chip?
        var rubberChipRect: CGRect = .null
    }

    private static func liveLayout(for scene: RulerScene) -> LiveLayout? {
        guard let pointer = scene.pointer,
              !scene.session.isEmpty,
              !scene.session.isDragging,
              let bounds = scene.session.bounds,
              bounds == scene.screenFrame else { return nil }
        let session = scene.session
        var live = LiveLayout()

        // Only on the ruler. Off it there's nothing to read.
        if let layout = layout(for: scene), session.hitTest(pointer) != .endGrip, let position = session.reading(at: pointer) {
            live.willPin = scene.modifierHeld
            let foot = layout.line.point(at: position)
            live.markerPoint = foot
            let chip = Chip(ReadingFormat.reading(position, scale: scene.scale), kind: live.willPin ? .willPin : .live)
            live.markerChip = chip
            // Past the body, on the side away from the arrow pointer's body.
            let distance = RulerSession.bodyDepth + 5 + extent(of: chip.size, along: layout.side) / 2
            live.markerChipRect = kept(rect(chip.size, centredOn: offset(foot, layout.side, by: distance)), inside: scene.screenFrame)
        }

        // While the modifier is held, preview the line a click here would add.
        let wouldPlacePoint = session.points.count < RulerSession.maximumPoints
            && (!session.hasRuler || session.hitTest(pointer) == .offRuler)
        if scene.modifierHeld, wouldPlacePoint, let last = session.points.last {
            let target = session.placement(for: pointer, snapping: scene.shiftHeld)
            live.rubberBand = (last, target)
            let length = MeasurementEngine.distance(from: last, to: target)
            if length >= RulerSession.minimumRulerLength {
                // The direction matters while placing the ruler itself.
                let detail = session.points.count == 1
                    ? RulerLine(from: last, through: target).map { ReadingFormat.angle(displayAngle($0.angleDegrees)) }
                    : nil
                let chip = Chip(ReadingFormat.reading(length, scale: scene.scale), detail: detail, kind: .live)
                live.rubberChip = chip
                let middle = CGPoint(x: (last.x + target.x) / 2, y: (last.y + target.y) / 2)
                live.rubberChipRect = kept(rect(chip.size, centredOn: middle), inside: scene.screenFrame)
            }
        }
        return live
    }

    /// The area touched by the live reading, for redrawing it alone as the pointer moves.
    static func liveBounds(for scene: RulerScene) -> CGRect {
        guard let live = liveLayout(for: scene) else { return .null }
        var bounds = CGRect.null
        if let point = live.markerPoint, let side = layout(for: scene)?.side {
            let tip = offset(point, side, by: RulerSession.bodyDepth + 2)
            let back = offset(point, side, by: -6)
            bounds = bounds.union(CGRect(origin: tip, size: .zero)).union(CGRect(origin: back, size: .zero))
        }
        bounds = bounds.union(live.markerChipRect).union(live.rubberChipRect)
        if let band = live.rubberBand {
            bounds = bounds.union(CGRect(origin: band.from, size: .zero)).union(CGRect(origin: band.to, size: .zero))
        }
        return bounds.isNull ? .null : bounds.insetBy(dx: -8, dy: -8)
    }

    // MARK: Drawing

    /// Draws in global screen coordinates into the current graphics context. The caller translates the context.
    static func draw(_ scene: RulerScene, dirty: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              !scene.session.isEmpty,
              scene.session.bounds == scene.screenFrame else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineCap(.butt)

        if let layout = layout(for: scene) {
            drawRuler(layout, scene: scene, dirty: dirty, in: context)
            drawHandles(scene, in: context)
            drawPinsAndLength(layout, scene: scene, in: context)
        } else if scene.session.isAngleMeasurement {
            drawAngleMeasurement(scene, in: context)
        } else {
            drawHandles(scene, in: context)
        }
        if let live = liveLayout(for: scene) {
            drawLive(live, scene: scene, in: context)
        }
    }

    private static func strokeDual(_ path: CGPath, core: NSColor, width: CGFloat, haloWidth: CGFloat, in context: CGContext) {
        context.addPath(path)
        context.setStrokeColor(Style.halo.withAlphaComponent(Style.haloAlpha).cgColor)
        context.setLineWidth(haloWidth)
        context.strokePath()
        context.addPath(path)
        context.setStrokeColor(core.cgColor)
        context.setLineWidth(width)
        context.strokePath()
    }

    private static func snappedPosition(_ position: CGFloat, layout: Layout, scale: CGFloat) -> CGFloat {
        guard layout.isAxisAligned else { return position }
        // Puts a level or plumb tick exactly on a pixel, so spacing varies by at most one pixel instead of blurring.
        let point = layout.line.point(at: position)
        let isHorizontal = abs(layout.line.direction.dy) < 0.000_001
        let coordinate = isHorizontal ? point.x : point.y
        let snapped = (floor(coordinate * scale) + 0.5) / scale
        return position + (snapped - coordinate) * (isHorizontal ? layout.line.direction.dx : layout.line.direction.dy)
    }

    private static func tickLength(_ level: TickLevel) -> CGFloat {
        switch level {
        case .minor: return Style.minorTick
        case .mid: return Style.midTick
        case .major: return Style.majorTick
        }
    }

    private static func drawRuler(_ layout: Layout, scene: RulerScene, dirty: CGRect, in context: CGContext) {
        let line = layout.line
        let side = layout.side
        let depth = RulerSession.bodyDepth

        let lowerEnd = line.point(at: layout.body.lowerBound)
        let upperEnd = line.point(at: layout.body.upperBound)
        let outline = CGMutablePath()
        outline.addLines(between: [lowerEnd, upperEnd, offset(upperEnd, side, by: depth), offset(lowerEnd, side, by: depth)])
        outline.closeSubpath()
        context.addPath(outline)
        context.setFillColor(Style.bodyFill.cgColor)
        context.fillPath()
        context.addPath(outline)
        context.setStrokeColor(Style.bodyEdge.cgColor)
        context.setLineWidth(Style.lineWidth)
        context.strokePath()

        // The measuring edge, with the span between the two clicks picked out.
        let edge = CGMutablePath()
        edge.move(to: lowerEnd)
        edge.addLine(to: upperEnd)
        strokeDual(edge, core: Style.ink.withAlphaComponent(0.95), width: Style.lineWidth, haloWidth: Style.haloWidth, in: context)

        let span = line.position(of: pixelCentre(scene.session.points[1], scale: scene.backingScale))
        let spanPath = CGMutablePath()
        spanPath.move(to: line.origin)
        spanPath.addLine(to: line.point(at: span))
        context.addPath(spanPath)
        context.setStrokeColor(Style.accent.cgColor)
        context.setLineWidth(Style.lineWidth)
        context.strokePath()

        drawGrip(scene, in: context)

        // Only what could touch the dirty rect, so the live reading stays cheap to redraw.
        let margin = Style.majorTick + 40
        guard let needed = line.clipped(to: dirty.insetBy(dx: -margin, dy: -margin)) else { return }
        let lower = max(needed.lowerBound, layout.scale.lowerBound)
        let upper = min(needed.upperBound, layout.scale.upperBound + 0.001)
        guard lower <= upper else { return }
        let ticks = scene.scale.ticks(in: lower...upper)

        // Grouped by level, so the finer divisions recede behind the ones you count by.
        let levels: [(TickLevel, CGFloat)] = [(.minor, 0.62), (.mid, 0.82), (.major, 1)]
        for (level, alpha) in levels {
            let path = CGMutablePath()
            for tick in ticks where tick.level == level {
                let start = line.point(at: snappedPosition(tick.position, layout: layout, scale: scene.backingScale))
                path.move(to: start)
                path.addLine(to: offset(start, side, by: tickLength(level)))
            }
            context.addPath(path)
            context.setStrokeColor(Style.ink.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(Style.lineWidth)
            context.strokePath()
        }

        drawTickLabels(ticks, layout: layout, scene: scene)
    }

    private static func drawTickLabels(_ ticks: [RulerTick], layout: Layout, scene: RulerScene) {
        let widest = NSAttributedString(string: "00", attributes: [.font: Style.tickFont]).size()
        let stride = scene.scale.labelStride(forLabelExtent: extent(of: widest, along: layout.line.direction) + 6)
        for tick in ticks {
            guard let value = tick.value, value % stride == 0 else { continue }
            let font = value == 0 ? Style.zeroFont : Style.tickFont
            let text = ReadingFormat.tickLabel(value)
            let size = NSAttributedString(string: text, attributes: [.font: font]).size()
            let distance = Style.majorTick + Style.labelGap + extent(of: size, along: layout.side) / 2
            let foot = layout.line.point(at: snappedPosition(tick.position, layout: layout, scale: scene.backingScale))
            let box = rect(size, centredOn: offset(foot, layout.side, by: distance))
            guard scene.screenFrame.contains(box) else { continue }
            NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: Style.ink])
                .draw(at: CGPoint(x: round(box.minX), y: round(box.minY)))
        }
    }

    /// A small tab on the far end of the body, with two ridges so it reads as something to grab.
    private static func drawGrip(_ scene: RulerScene, in context: CGContext) {
        guard let centre = scene.session.gripPoint,
              let line = scene.session.line,
              let side = scene.session.bodySide else { return }
        let isHovered = scene.modifierHeld && scene.pointer.flatMap { scene.session.hitTest($0) } == .endGrip
        let along = line.direction
        let halfLength: CGFloat = 4
        let halfWidth: CGFloat = isHovered ? 10 : 8
        let corners = [(1, 1), (1, -1), (-1, -1), (-1, 1)].map { signs -> CGPoint in
            offset(offset(centre, along, by: CGFloat(signs.0) * halfLength), side, by: CGFloat(signs.1) * halfWidth)
        }
        let tab = CGMutablePath()
        tab.addLines(between: corners)
        tab.closeSubpath()
        context.saveGState()
        context.setLineJoin(.round)
        context.addPath(tab)
        context.setStrokeColor(Style.halo.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(3)
        context.strokePath()
        context.restoreGState()
        context.addPath(tab)
        context.setFillColor((isHovered ? Style.accent : Style.ink).cgColor)
        context.fillPath()
        let ridges = CGMutablePath()
        for shift in [-1.5, 1.5] as [CGFloat] {
            let middle = offset(centre, along, by: shift)
            ridges.move(to: offset(middle, side, by: -4))
            ridges.addLine(to: offset(middle, side, by: 4))
        }
        context.addPath(ridges)
        context.setStrokeColor((isHovered ? NSColor.white : Style.halo).cgColor)
        context.setLineWidth(1)
        context.strokePath()
    }

    private static func drawRing(at point: CGPoint, radius: CGFloat, color: NSColor, in context: CGContext) {
        // Hollow, so the exact spot that was clicked stays visible underneath.
        let box = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.setStrokeColor(Style.halo.withAlphaComponent(Style.haloAlpha).cgColor)
        context.setLineWidth(3.5)
        context.strokeEllipse(in: box)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: box)
    }

    private static func drawHandles(_ scene: RulerScene, in context: CGContext) {
        let hovered: RulerSession.Handle? = {
            guard scene.modifierHeld, let pointer = scene.pointer else { return nil }
            if case .handle(let handle)? = scene.session.hitTest(pointer) { return handle }
            return nil
        }()
        for (index, point) in scene.session.points.enumerated() {
            let centre = pixelCentre(point, scale: scene.backingScale)
            let isHovered = (index == 0 && hovered == .start) || (index == 1 && hovered == .end)
            drawRing(at: centre, radius: isHovered ? Style.handleRadius + 2 : Style.handleRadius, color: Style.accent, in: context)
        }
    }

    private static func drawPinsAndLength(_ layout: Layout, scene: RulerScene, in context: CGContext) {
        let line = layout.line
        // Chips go on the side without tick numbers. If the ruler runs so close to the edge that they
        // wouldn't fit there, they go past the far side of the body instead, still clear of the scale.
        var chipSide = CGVector(dx: -layout.side.dx, dy: -layout.side.dy)
        var chipBase: CGFloat = 10
        let fits = [layout.body.lowerBound, layout.body.upperBound].allSatisfy {
            scene.screenFrame.contains(offset(line.point(at: $0), chipSide, by: 44))
        }
        if !fits {
            chipSide = layout.side
            chipBase = RulerSession.bodyDepth + 5
        }

        struct Item { let position: CGFloat; let chip: Chip; let isPin: Bool }
        var items: [Item] = scene.session.pins.map { pin in
            Item(
                position: pin.position,
                chip: Chip(
                    ReadingFormat.reading(pin.position, scale: scene.scale),
                    detail: pin.gapFromPrevious.map { ReadingFormat.gap($0, scale: scene.scale) }
                ),
                isPin: true
            )
        }
        if let length = scene.session.rulerLength, let measuredLine = scene.session.line {
            // The direction only matters while the ruler is being placed or moved.
            let detail = scene.session.isDragging ? ReadingFormat.angle(displayAngle(measuredLine.angleDegrees)) : nil
            items.append(Item(
                position: length,
                chip: Chip(ReadingFormat.reading(length, scale: scene.scale), detail: detail),
                isPin: false
            ))
        }
        items.sort { $0.position < $1.position }

        let spans: [ClosedRange<CGFloat>] = items.map { item in
            let half = extent(of: item.chip.size, along: line.direction) / 2 + 3
            return (item.position - half)...(item.position + half)
        }
        // Spans can start out of order when chips differ in size, so assign lanes in order of their start.
        let order = spans.indices.sorted { spans[$0].lowerBound < spans[$1].lowerBound }
        let assigned = LabelLanes.assign(order.map { spans[$0] })
        var lanes = [Int](repeating: 0, count: items.count)
        for (rank, index) in order.enumerated() { lanes[index] = assigned[rank] }

        // Every lane is as deep as the deepest chip, so one- and two-line chips can't overlap across lanes.
        let laneDepth = (items.map { extent(of: $0.chip.size, along: chipSide) }.max() ?? 0) + 4
        var chips: [(Chip, CGRect)] = []
        for (index, item) in items.enumerated() {
            let foot = line.point(at: item.position)
            let depth = extent(of: item.chip.size, along: chipSide)
            let distance = chipBase + depth / 2 + CGFloat(lanes[index]) * laneDepth
            let box = kept(rect(item.chip.size, centredOn: offset(foot, chipSide, by: distance)), inside: scene.screenFrame)
            let leader = CGMutablePath()
            leader.move(to: foot)
            leader.addLine(to: CGPoint(x: box.midX, y: box.midY))
            strokeDual(leader, core: item.isPin ? Style.pin : Style.accent, width: 1, haloWidth: 2.4, in: context)
            chips.append((item.chip, box))
        }
        for item in items where item.isPin {
            drawPinDot(at: line.point(at: item.position), in: context)
        }
        for (chip, box) in chips { drawChip(chip, in: box, context: context) }
    }

    private static func drawPinDot(at point: CGPoint, in context: CGContext) {
        let radius: CGFloat = 3
        let box = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.setFillColor(Style.pin.cgColor)
        context.fillEllipse(in: box)
        context.setStrokeColor(Style.halo.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: box)
    }

    private static func drawChip(_ chip: Chip, in box: CGRect, context: CGContext) {
        let path = CGPath(roundedRect: box, cornerWidth: 4.5, cornerHeight: 4.5, transform: nil)
        let fill: NSColor
        switch chip.kind {
        case .neutral: fill = Style.chipFill
        case .live: fill = Style.accent
        case .willPin: fill = Style.pin
        }
        context.addPath(path)
        context.setFillColor(fill.cgColor)
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(chip.kind == .neutral ? Style.chipEdge.cgColor : Style.halo.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(0.5)
        context.strokePath()

        let sizes = chip.lines.map { $0.size() }
        var y = box.maxY - 2.5
        for (line, size) in zip(chip.lines, sizes) {
            y -= size.height
            line.draw(at: CGPoint(x: round(box.midX - size.width / 2), y: round(y)))
        }
    }

    // MARK: Angle measurement

    /// Plain lines, a small arc at each angle, and labels placed clear of all of it.
    private static func drawAngleMeasurement(_ scene: RulerScene, in context: CGContext) {
        let points = scene.session.points
        let drawn = points.map { pixelCentre($0, scale: scene.backingScale) }
        guard points.count >= 3 else { return }

        let lengthChips = (0..<(points.count - 1)).map { index in
            Chip(ReadingFormat.reading(MeasurementEngine.distance(from: points[index], to: points[index + 1]), scale: scene.scale))
        }
        let angleChips = scene.session.angles.map { Chip(ReadingFormat.angle($0.degrees)) }
        let labels = AngleLayout(
            points: drawn,
            lengthSizes: lengthChips.map(\.size),
            angleSizes: angleChips.map(\.size),
            bounds: scene.screenFrame
        )

        let linesPath = CGMutablePath()
        linesPath.addLines(between: drawn)
        context.saveGState()
        context.setLineJoin(.round)
        strokeDual(linesPath, core: Style.accent, width: 1.25, haloWidth: 3, in: context)
        context.restoreGState()

        for arc in labels.arcs {
            let path = CGMutablePath()
            path.addArc(
                center: arc.vertex,
                radius: arc.radius,
                startAngle: arc.startAngle,
                endAngle: arc.startAngle + arc.sweep,
                clockwise: arc.sweep < 0
            )
            strokeDual(path, core: Style.ink, width: 1, haloWidth: 2.6, in: context)
        }
        for point in drawn {
            drawRing(at: point, radius: Style.vertexRadius, color: Style.accent, in: context)
        }
        for (chip, box) in zip(lengthChips, labels.lengthBoxes) { drawChip(chip, in: box, context: context) }
        for (chip, box) in zip(angleChips, labels.angleBoxes) { drawChip(chip, in: box, context: context) }
    }

    // MARK: Live

    private static func drawLive(_ live: LiveLayout, scene: RulerScene, in context: CGContext) {
        if let band = live.rubberBand {
            context.saveGState()
            let path = CGMutablePath()
            path.move(to: pixelCentre(band.from, scale: scene.backingScale))
            path.addLine(to: pixelCentre(band.to, scale: scene.backingScale))
            context.setLineDash(phase: 0, lengths: [5, 4])
            strokeDual(path, core: Style.accent, width: 1.25, haloWidth: 3, in: context)
            context.restoreGState()
            drawRing(at: pixelCentre(band.to, scale: scene.backingScale), radius: Style.handleRadius, color: Style.accent, in: context)
            if let chip = live.rubberChip { drawChip(chip, in: live.rubberChipRect, context: context) }
        }
        if let point = live.markerPoint, let side = layout(for: scene)?.side {
            let path = CGMutablePath()
            path.move(to: offset(point, side, by: -5))
            path.addLine(to: offset(point, side, by: RulerSession.bodyDepth))
            strokeDual(path, core: live.willPin ? Style.pin : Style.liveMarker, width: 2, haloWidth: 4, in: context)
            if live.willPin { drawPinDot(at: point, in: context) }
            if let chip = live.markerChip { drawChip(chip, in: live.markerChipRect, context: context) }
        }
    }
}
