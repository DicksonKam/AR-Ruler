import AppKit
import XCTest

/// Holds the same `OverlayInputState` the app's controller does, with the same click gate.
private final class ScriptedOverlay: VirtualInputTarget {
    var state = OverlayInputState()
    var sent: [OverlayInput] = []
    var physicalEnabled = true
    let screenFrame: CGRect
    let pointsPerCm: CGFloat

    init(screenFrame: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080), pointsPerCm: CGFloat = 36) {
        self.screenFrame = screenFrame
        self.pointsPerCm = pointsPerCm
    }

    var capturesClicks: Bool { state.capturesClicks }
    var configuredModifier: ModifierKey { state.modifierKey }
    var mainDisplayHeight: CGFloat { screenFrame.height }
    var summary: String { "points=\(state.session.points.count)" }

    func screen(at point: CGPoint) -> (frame: CGRect, pointsPerUnit: CGFloat)? {
        guard point.x >= screenFrame.minX, point.x <= screenFrame.maxX,
              point.y >= screenFrame.minY, point.y <= screenFrame.maxY else { return nil }
        return (screenFrame, pointsPerCm)
    }

    func send(_ input: OverlayInput) {
        sent.append(input)
        _ = state.apply(input)
    }

    func setPhysicalInputEnabled(_ enabled: Bool) {
        physicalEnabled = enabled
    }
}

final class VirtualInputTests: XCTestCase {
    private var overlay: ScriptedOverlay!
    private var logged: [String] = []
    private var waits: [TimeInterval] = []
    private var runner: VirtualInputRunner!

    private var session: RulerSession { overlay.state.session }

    override func setUp() {
        overlay = ScriptedOverlay()
        logged = []
        waits = []
        runner = VirtualInputRunner(
            target: overlay,
            log: { [unowned self] in self.logged.append($0) },
            schedule: { [unowned self] seconds, next in
                self.waits.append(seconds)
                next()
            }
        )
    }

    private func run(_ script: String) {
        runner.run(script: script)
    }

    /// A top-left screen point as AppKit sees it, on the 1080 point tall display.
    private func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x, y: 1080 - y)
    }

    // MARK: The click gate

    func testClicksPassThroughWithNoKeysHeld() {
        run("click 100,100")
        XCTAssertTrue(session.isEmpty)
        XCTAssertTrue(logged.contains { $0.contains("passed through") })
    }

    func testOneOfTheTwoKeysAloneDoesNotCapture() {
        run("""
        hold control
        click 100,100
        hold option
        click 200,200
        """)
        XCTAssertTrue(session.isEmpty)
    }

    func testBothKeysCapture() {
        run("""
        hold control option
        click 100,100
        """)
        XCTAssertEqual(session.points, [p(100, 100)])
    }

    func testHoldUsesTheConfiguredKey() {
        overlay.state.modifierKey = .option
        run("""
        hold
        click 100,100
        """)
        XCTAssertEqual(session.points.count, 1)
    }

    func testReleaseStopsCapturing() {
        run("""
        hold
        click 100,100
        release
        click 400,100
        """)
        XCTAssertEqual(session.points.count, 1)
    }

    // MARK: Full flows

    func testHoldPlusTwoClicksLaysARuler() throws {
        run("""
        hold
        click 100,500
        click 400,500
        """)
        XCTAssertTrue(session.hasRuler)
        XCTAssertEqual(session.rulerLength, 300)
        let line = try XCTUnwrap(session.line)
        XCTAssertEqual(line.position(of: p(100, 500)), 0)
        XCTAssertEqual(session.scaleRange?.upperBound, 360, "8.33 + 1 cm rounds up to 10 cm")
    }

    func testPinsAndGapsThenHoverWithKeysUp() {
        run("""
        hold
        click 100,500
        click 400,500
        click 172,500
        click 244,500
        release
        move 280,500
        """)
        XCTAssertEqual(session.pins.map(\.position), [72, 144])
        XCTAssertEqual(session.pins.last?.gapFromPrevious, 72)
        XCTAssertEqual(session.reading(at: overlay.state.pointer ?? .zero), 180)
        XCTAssertFalse(overlay.state.capturesClicks)
    }

    func testThirdClickOffTheRulerSwitchesToAngles() throws {
        run("""
        hold
        click 100,500
        click 400,500
        click 172,500
        click 400,200
        """)
        XCTAssertFalse(session.hasRuler)
        XCTAssertTrue(session.isAngleMeasurement)
        XCTAssertTrue(session.pins.isEmpty)
        XCTAssertEqual(try XCTUnwrap(session.angles.first).degrees, 90, accuracy: 1e-9)
    }

    func testFourPointsThenTheNextClickStartsOver() {
        run("""
        hold
        click 100,500
        click 400,500
        click 400,200
        click 700,200
        click 900,900
        """)
        XCTAssertEqual(session.points, [p(900, 900)])
    }

    func testDraggingAnEndReAims() {
        run("""
        hold
        click 100,500
        click 400,500
        drag 400,500 400,200
        """)
        XCTAssertEqual(session.points, [p(100, 500), p(400, 200)])
        XCTAssertEqual(session.pins.count, 0, "a drag isn't a click")
    }

    func testDraggingTheBodyMovesTheWholeRuler() {
        run("""
        hold
        click 100,500
        click 400,500
        drag 250,500 250,700
        """)
        XCTAssertEqual(session.points, [p(100, 700), p(400, 700)])
    }

    func testDraggingTheGripLengthens() throws {
        run("""
        hold
        click 100,500
        click 400,500
        """)
        let before = try XCTUnwrap(session.scaleRange?.upperBound)
        let grip = try XCTUnwrap(session.gripPoint)
        run("drag \(grip.x),\(1080 - grip.y) \(grip.x + 72),\(1080 - grip.y)")
        XCTAssertEqual(try XCTUnwrap(session.scaleRange?.upperBound), before + 72)
        XCTAssertEqual(session.points, [p(100, 500), p(400, 500)])
    }

    func testShiftSnapsADraggedEndWhileTheKeysAreHeld() {
        run("""
        hold
        click 100,500
        click 400,500
        shift on
        drag 400,500 112,200
        shift off
        """)
        XCTAssertEqual(session.line?.angleDegrees ?? 0, 90, accuracy: 1e-9)
        XCTAssertTrue(overlay.state.modifierHeld, "Shift on top doesn't drop the trigger")
    }

    func testEscClearAndRightClickAllClear() {
        for clearing in ["esc", "clear", "hold\nrightclick 500,500"] {
            run("""
            hold
            click 100,500
            click 400,500
            release
            \(clearing)
            release
            """)
            XCTAssertTrue(session.isEmpty, clearing)
        }
    }

    func testRightClickWithKeysUpPassesThrough() {
        run("""
        hold
        click 100,500
        release
        rightclick 500,500
        """)
        XCTAssertEqual(session.points.count, 1)
    }

    // MARK: The shared entry point

    func testCommandsBecomeTheSameInputsARealSourceDelivers() {
        run("""
        hold
        click 100,500
        """)
        XCTAssertEqual(overlay.sent, [
            .modifiers([.control, .option], pointer: nil),
            .pointerMoved(p(100, 500)),
            .press(p(100, 500), frame: overlay.screenFrame, pointsPerUnit: 36),
            .release(p(100, 500), [.control, .option])
        ])
    }

    func testDragSendsSteps() {
        run("""
        hold
        drag 0,0 80,0
        """)
        let drags = overlay.sent.filter { if case .drag = $0 { return true } else { return false } }
        XCTAssertEqual(drags.count, 8)
    }

    func testPhysicalCommandReachesTheTarget() {
        run("physical off")
        XCTAssertFalse(overlay.physicalEnabled)
        run("physical on")
        XCTAssertTrue(overlay.physicalEnabled)
    }

    // MARK: Script format

    func testBothPointFormsAndCommentsWork() {
        guard case .success(let lines) = VirtualInputScript.parse("""
        # a comment

        move 10 20
        move 10,20   # trailing comment
        drag 1 2, 3 4
        """) else { return XCTFail("should parse") }
        XCTAssertEqual(lines.map(\.command), [
            .move(CGPoint(x: 10, y: 20)),
            .move(CGPoint(x: 10, y: 20)),
            .drag(CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4))
        ])
        XCTAssertEqual(lines[0].number, 3)
    }

    func testABadLineStopsTheWholeScriptAndIsLogged() {
        run("""
        hold
        click 100,100
        flap 1
        click nonsense
        """)
        XCTAssertTrue(session.isEmpty, "nothing runs")
        XCTAssertTrue(logged.contains { $0.contains("line 3") && $0.contains("unknown command") })
        XCTAssertTrue(logged.contains { $0.contains("line 4") && $0.contains("click takes") })
        XCTAssertTrue(logged.contains("nothing was run"))
    }

    func testEveryAppliedCommandIsLogged() {
        run("""
        hold
        move 5,5
        """)
        XCTAssertTrue(logged.contains { $0.hasPrefix("line 1: hold") })
        XCTAssertTrue(logged.contains { $0.hasPrefix("line 2: move 5,5") })
        XCTAssertTrue(logged.last?.hasPrefix("finished") == true)
    }

    func testWaitPausesThenCarriesOn() {
        run("""
        wait 0.5
        hold
        wait 1
        click 10,10
        """)
        XCTAssertEqual(waits, [0.5, 1])
        XCTAssertEqual(session.points.count, 1)
    }

    func testBadWaitIsRejected() {
        run("wait -1")
        XCTAssertTrue(logged.contains("nothing was run"))
    }

    func testClickOffEveryScreenIsNotApplied() {
        run("""
        hold
        click 5000,5000
        """)
        XCTAssertTrue(session.isEmpty)
        XCTAssertTrue(logged.contains { $0.contains("not on any screen") })
    }
}

/// The two demo scripts in `scripts/virtual-input`, run for real and optionally saved as PNGs.
final class VirtualInputDemoTests: XCTestCase {
    private func scriptText(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("scripts/virtual-input/\(name).txt"), encoding: .utf8)
    }

    private func play(_ name: String) throws -> ScriptedOverlay {
        let overlay = ScriptedOverlay()
        let runner = VirtualInputRunner(target: overlay, log: { _ in }, schedule: { _, next in next() })
        runner.run(script: try scriptText(name))
        return overlay
    }

    private func snapshot(_ overlay: ScriptedOverlay, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["ARRULER_SNAPSHOT_DIR"] else { return }
        let frame = overlay.screenFrame
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(frame.width), pixelsHigh: Int(frame.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSColor(srgbRed: 0.11, green: 0.12, blue: 0.15, alpha: 1).setFill()
        frame.fill()
        RulerRenderer.draw(RulerScene(
            session: overlay.state.session,
            scale: RulerScale(unit: .cm, pointsPerCm: overlay.pointsPerCm),
            screenFrame: frame,
            backingScale: 1,
            pointer: overlay.state.pointer,
            modifierHeld: overlay.state.modifierHeld,
            shiftHeld: overlay.state.shiftHeld
        ), dirty: frame)
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }

    func testRulerDemoLaysARulerWithFourPinsAndAHoverReading() throws {
        let overlay = try play("demo-ruler")
        let session = overlay.state.session
        XCTAssertTrue(session.hasRuler)
        XCTAssertEqual(session.pins.count, 4)
        XCTAssertFalse(overlay.state.capturesClicks, "keys released")
        XCTAssertNotNil(session.reading(at: try XCTUnwrap(overlay.state.pointer)), "the pointer rests on the ruler")
        try snapshot(overlay, name: "demo-ruler")
    }

    func testAngleDemoEndsAsTwoLinesAndOneAngle() throws {
        let overlay = try play("demo-angle")
        let session = overlay.state.session
        XCTAssertTrue(session.isAngleMeasurement)
        XCTAssertEqual(session.points.count, 3)
        XCTAssertEqual(session.angles.count, 1)
        XCTAssertFalse(overlay.state.capturesClicks, "keys released")
        try snapshot(overlay, name: "demo-angle")
    }

    func testRunningTheAngleDemoAfterTheRulerDemoStartsClean() throws {
        let overlay = ScriptedOverlay()
        let runner = VirtualInputRunner(target: overlay, log: { _ in }, schedule: { _, next in next() })
        runner.run(script: try scriptText("demo-ruler"))
        runner.run(script: try scriptText("demo-angle"))
        XCTAssertEqual(overlay.state.session.points.count, 3)
        XCTAssertTrue(overlay.state.session.pins.isEmpty)
    }
}
