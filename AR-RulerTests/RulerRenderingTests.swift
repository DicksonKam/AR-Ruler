import AppKit
import XCTest

/// Renders real scenes over mock backgrounds. Set ARRULER_SNAPSHOT_DIR to save PNGs for looking at them;
/// passing here only means the drawing ran and put marks on the page.
final class RulerRenderingTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 900, height: 420)

    private enum Background: String, CaseIterable { case light, dark, busy }

    private func drawBackground(_ background: Background, size: CGSize) {
        switch background {
        case .light:
            NSColor(white: 0.97, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            drawMockText(color: NSColor(white: 0.3, alpha: 1), size: size)
        case .dark:
            NSColor(srgbRed: 0.11, green: 0.12, blue: 0.15, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            drawMockText(color: NSColor(white: 0.75, alpha: 1), size: size)
        case .busy:
            let colors: [NSColor] = [.systemTeal, .systemOrange, .white, .systemIndigo, .black, .systemGreen, .systemPink, .systemBlue, .systemYellow]
            let cell: CGFloat = 60
            var index = 0
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    colors[(index * 7 + Int(y / cell)) % colors.count].setFill()
                    NSRect(x: x, y: y, width: cell, height: cell).fill()
                    x += cell
                    index += 1
                }
                y += cell
            }
        }
    }

    private func drawMockText(color: NSColor, size: CGSize) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color]
        var y = size.height - 34
        while y > 10 {
            ("The quick brown fox jumps over the lazy dog while measuring the width of the column beside it, " +
             "and then keeps on going to fill the line right across the page.")
                .draw(at: CGPoint(x: 24, y: y), withAttributes: attributes)
            y -= 26
        }
    }

    private func render(_ scene: RulerScene, background: Background?, scale: CGFloat) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(screen.width * scale),
            pixelsHigh: Int(screen.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = screen.size
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        if let background { drawBackground(background, size: screen.size) }
        RulerRenderer.draw(scene, dirty: screen)
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func save(_ rep: NSBitmapImageRep, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["ARRULER_SNAPSHOT_DIR"] else { return }
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }

    private func scene(_ session: RulerSession, unit: RulerUnit = .cm, pointsPerCm: CGFloat = 36.3, backingScale: CGFloat = 1,
                       pointer: CGPoint? = nil, modifierHeld: Bool = false) -> RulerScene {
        RulerScene(
            session: session,
            scale: RulerScale(unit: unit, pointsPerCm: pointsPerCm),
            screenFrame: screen,
            backingScale: backingScale,
            pointer: pointer,
            modifierHeld: modifierHeld
        )
    }

    private func session(_ a: CGPoint, _ b: CGPoint, pins: [CGPoint] = [], extra: [CGPoint] = [], pointsPerUnit: CGFloat = 36.3) -> RulerSession {
        var session = RulerSession()
        session.pointsPerUnit = pointsPerUnit
        session.click(at: a, on: screen)
        session.click(at: b, on: screen)
        pins.forEach { session.click(at: $0, on: screen) }
        extra.forEach { session.click(at: $0, on: screen) }
        return session
    }

    private func scenes() -> [(String, RulerScene)] {
        let level = session(CGPoint(x: 180, y: 210), CGPoint(x: 460, y: 210),
                            pins: [CGPoint(x: 300, y: 212), CGPoint(x: 372, y: 208), CGPoint(x: 420, y: 220)])
        let close = session(CGPoint(x: 180, y: 210), CGPoint(x: 460, y: 210),
                            pins: [CGPoint(x: 300, y: 210), CGPoint(x: 318, y: 210), CGPoint(x: 332, y: 210), CGPoint(x: 449, y: 210)])
        let tilted = session(CGPoint(x: 160, y: 90), CGPoint(x: 400, y: 230), pins: [CGPoint(x: 300, y: 172)])
        let steep = session(CGPoint(x: 450, y: 60), CGPoint(x: 500, y: 330), pins: [CGPoint(x: 472, y: 180)])
        let plumb = session(CGPoint(x: 450, y: 60), CGPoint(x: 450, y: 332), pins: [CGPoint(x: 450, y: 180)])
        var firstPointOnly = RulerSession()
        firstPointOnly.pointsPerUnit = 36.3
        firstPointOnly.click(at: CGPoint(x: 180, y: 210), on: screen)
        var dragging = level
        dragging.pressBegan(at: CGPoint(x: 460, y: 210), on: screen)
        dragging.pressMoved(to: CGPoint(x: 460, y: 300))
        // Like the screenshot that prompted this design: a plumb ruler, then a third click close to its second point.
        let screenshotCase = session(CGPoint(x: 450, y: 80), CGPoint(x: 450, y: 352), extra: [CGPoint(x: 490, y: 60)])
        return [
            ("level", scene(level, pointer: CGPoint(x: 320, y: 225))),
            ("level-willpin", scene(level, pointer: CGPoint(x: 350, y: 212), modifierHeld: true)),
            ("close-pins", scene(close)),
            ("tilted", scene(tilted, pointer: CGPoint(x: 260, y: 175))),
            ("steep", scene(steep, pointer: CGPoint(x: 470, y: 250))),
            ("plumb", scene(plumb, pointer: CGPoint(x: 440, y: 150))),
            ("top-edge", scene(session(CGPoint(x: 200, y: 412), CGPoint(x: 500, y: 412), pins: [CGPoint(x: 350, y: 412)]))),
            ("near-right-edge", scene(session(CGPoint(x: 640, y: 210), CGPoint(x: 880, y: 210)))),
            ("inches", scene(session(CGPoint(x: 180, y: 210), CGPoint(x: 460, y: 210), pins: [CGPoint(x: 300, y: 210)], pointsPerUnit: 36.3 * 2.54), unit: .inch, pointer: CGPoint(x: 400, y: 225))),
            ("dense", scene(session(CGPoint(x: 180, y: 210), CGPoint(x: 460, y: 210), pointsPerUnit: 12), pointsPerCm: 12)),
            ("placing", scene(firstPointOnly, pointer: CGPoint(x: 520, y: 300), modifierHeld: true)),
            ("dragging", scene(dragging)),
            ("hover-grip", scene(level, pointer: level.gripPoint, modifierHeld: true)),
            ("preview-angle", scene(level, pointer: CGPoint(x: 620, y: 340), modifierHeld: true)),
            ("angle-90", scene(session(CGPoint(x: 200, y: 110), CGPoint(x: 500, y: 110), extra: [CGPoint(x: 500, y: 340)]))),
            ("angle-screenshot", scene(screenshotCase)),
            ("angle-tight", scene(session(CGPoint(x: 150, y: 120), CGPoint(x: 600, y: 120), extra: [CGPoint(x: 200, y: 165)]))),
            ("angle-obtuse", scene(session(CGPoint(x: 120, y: 200), CGPoint(x: 450, y: 200), extra: [CGPoint(x: 800, y: 240)]))),
            ("angle-four", scene(session(CGPoint(x: 120, y: 120), CGPoint(x: 400, y: 120), extra: [CGPoint(x: 560, y: 320), CGPoint(x: 780, y: 200)]))),
            ("four-zigzag", scene(session(CGPoint(x: 150, y: 330), CGPoint(x: 420, y: 90), extra: [CGPoint(x: 560, y: 340), CGPoint(x: 800, y: 110)]))),
            ("four-tight", scene(session(CGPoint(x: 120, y: 200), CGPoint(x: 700, y: 200), extra: [CGPoint(x: 150, y: 165), CGPoint(x: 720, y: 120)]))),
            ("four-short", scene(session(CGPoint(x: 400, y: 200), CGPoint(x: 445, y: 200), extra: [CGPoint(x: 470, y: 160), CGPoint(x: 430, y: 135)]))),
            ("four-very-short", scene(session(CGPoint(x: 430, y: 200), CGPoint(x: 450, y: 205), extra: [CGPoint(x: 445, y: 180), CGPoint(x: 465, y: 175)]))),
            ("four-corner", scene(session(CGPoint(x: 40, y: 395), CGPoint(x: 240, y: 395), extra: [CGPoint(x: 60, y: 300), CGPoint(x: 20, y: 150)]))),
            ("preview-third-line", scene(session(CGPoint(x: 120, y: 120), CGPoint(x: 400, y: 120), extra: [CGPoint(x: 560, y: 320)]), pointer: CGPoint(x: 780, y: 200), modifierHeld: true)),
            ("angle-short-arms", scene(session(CGPoint(x: 420, y: 200), CGPoint(x: 450, y: 200), extra: [CGPoint(x: 430, y: 230)])))
        ]
    }

    func testAllScenesRenderMarksAndSnapshotsWhenAsked() throws {
        for (name, scene) in scenes() {
            let bare = try render(scene, background: nil, scale: 1)
            let hasMarks = (0..<bare.pixelsHigh).contains { y in
                stride(from: 0, to: bare.pixelsWide, by: 3).contains { x in (bare.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 }
            }
            XCTAssertTrue(hasMarks, name)
            for background in Background.allCases {
                let rep = try render(scene, background: background, scale: 1)
                try save(rep, name: "\(name)-\(background.rawValue)")
            }
        }
        var retina = scenes()[0].1
        retina.backingScale = 2
        try save(try render(retina, background: .light, scale: 2), name: "level-light-2x")
    }

    func testLevelRulerIsOnePixelWideAtOneX() throws {
        let scene = scene(session(CGPoint(x: 100, y: 200), CGPoint(x: 300, y: 200)))
        let rep = try render(scene, background: nil, scale: 1)
        // Past the second click, so the white edge. Row 420 - 200 = 220 is the pixel under a pointer at y = 200.
        let core = try XCTUnwrap(rep.colorAt(x: 315, y: 220)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(core.redComponent * core.alphaComponent, 0.8)
    }

    func testBusyScenesReallyHaveFourPoints() {
        for name in ["angle-four", "four-zigzag", "four-tight", "four-short", "four-very-short", "four-corner"] {
            let scene = scenes().first { $0.0 == name }?.1
            XCTAssertEqual(scene?.session.points.count, 4, name)
        }
    }

    func testNothingDrawnOnAnotherScreen() throws {
        var scene = scene(session(CGPoint(x: 100, y: 200), CGPoint(x: 800, y: 200)))
        scene.screenFrame = CGRect(x: 900, y: 0, width: 900, height: 420)
        let rep = try render(scene, background: nil, scale: 1)
        let hasMarks = (0..<rep.pixelsHigh).contains { y in
            stride(from: 0, to: rep.pixelsWide, by: 5).contains { x in (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 }
        }
        XCTAssertFalse(hasMarks)
    }

    func testLiveBoundsCoverTheMarkerAndAreEmptyWithoutAPointer() {
        let base = session(CGPoint(x: 100, y: 200), CGPoint(x: 400, y: 200))
        XCTAssertTrue(RulerRenderer.liveBounds(for: scene(base)).isNull)
        let bounds = RulerRenderer.liveBounds(for: scene(base, pointer: CGPoint(x: 250, y: 215)))
        XCTAssertTrue(bounds.contains(CGPoint(x: 250, y: 200)))
    }

    func testNoLiveReadingOnTheGrip() {
        let base = session(CGPoint(x: 100, y: 200), CGPoint(x: 400, y: 200))
        XCTAssertTrue(RulerRenderer.liveBounds(for: scene(base, pointer: base.gripPoint)).isNull)
    }

    func testNoLiveReadingOffTheRuler() {
        let base = session(CGPoint(x: 100, y: 200), CGPoint(x: 400, y: 200))
        XCTAssertTrue(RulerRenderer.liveBounds(for: scene(base, pointer: CGPoint(x: 250, y: 380))).isNull)
    }
}
