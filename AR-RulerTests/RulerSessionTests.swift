import XCTest

final class RulerSessionTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let otherScreen = CGRect(x: 1000, y: 0, width: 1000, height: 800)

    /// A horizontal ruler from (100, 100) to (200, 100).
    private func rulerSession() -> RulerSession {
        var session = RulerSession()
        session.click(at: CGPoint(x: 100, y: 100), on: screen)
        session.click(at: CGPoint(x: 200, y: 100), on: screen)
        return session
    }

    // MARK: Aligning

    func testTwoClicksMakeARulerWithZeroAtTheFirst() throws {
        var session = RulerSession()
        XCTAssertEqual(session.click(at: CGPoint(x: 100, y: 100), on: screen), .placedFirst)
        XCTAssertNil(session.line)
        XCTAssertEqual(session.click(at: CGPoint(x: 200, y: 100), on: screen), .placedSecond)
        let line = try XCTUnwrap(session.line)
        XCTAssertEqual(line.position(of: CGPoint(x: 100, y: 100)), 0)
        XCTAssertEqual(line.position(of: CGPoint(x: 200, y: 100)), 100)
        XCTAssertEqual(session.rulerLength, 100)
    }

    func testSecondClickOnTheFirstIsIgnored() {
        var session = RulerSession()
        session.click(at: CGPoint(x: 100, y: 100), on: screen)
        XCTAssertEqual(session.click(at: CGPoint(x: 101, y: 100), on: screen), .ignored)
        XCTAssertFalse(session.hasRuler)
    }

    func testShiftSnapsTheSecondClick() {
        var session = RulerSession()
        session.click(at: CGPoint(x: 100, y: 100), on: screen)
        session.click(at: CGPoint(x: 200, y: 104), on: screen, snapping: true)
        XCTAssertEqual(session.points[1].y, 100)
    }

    // MARK: Click classification

    func testClickWithinToleranceOfTheLinePins() {
        var session = rulerSession()
        XCTAssertEqual(session.click(at: CGPoint(x: 150, y: 108), on: screen), .pinned)
        XCTAssertEqual(session.pins.first?.position, 50)
        XCTAssertEqual(session.points.count, 2)
    }

    func testClickJustOutsideToleranceAddsAnAnglePoint() {
        var session = rulerSession()
        XCTAssertEqual(session.click(at: CGPoint(x: 150, y: 108.5), on: screen), .addedPoint)
        XCTAssertTrue(session.pins.isEmpty)
        XCTAssertEqual(session.points.count, 3)
    }

    func testToleranceAppliesAlongTheExtendedLineToo() {
        var session = rulerSession()
        XCTAssertEqual(session.click(at: CGPoint(x: 900, y: 104), on: screen), .pinned)
        XCTAssertEqual(session.click(at: CGPoint(x: 20, y: 96), on: screen), .pinned)
        XCTAssertEqual(session.pins.first?.position, -80)
    }

    func testAnglePointsStopAtFourThenStartNew() {
        var session = rulerSession()
        XCTAssertEqual(session.click(at: CGPoint(x: 200, y: 300), on: screen), .addedPoint)
        XCTAssertEqual(session.click(at: CGPoint(x: 400, y: 300), on: screen), .addedPoint)
        session.click(at: CGPoint(x: 500, y: 100), on: screen)
        XCTAssertEqual(session.points.count, 4)
        XCTAssertEqual(session.pins.count, 1, "that click was on the line")
        XCTAssertEqual(session.click(at: CGPoint(x: 700, y: 600), on: screen), .startedNew)
        XCTAssertEqual(session.points, [CGPoint(x: 700, y: 600)])
        XCTAssertFalse(session.hasRuler)
        XCTAssertTrue(session.pins.isEmpty)
    }

    func testOnLineClickStillPinsWhenFourPointsExist() {
        var session = rulerSession()
        session.click(at: CGPoint(x: 200, y: 300), on: screen)
        session.click(at: CGPoint(x: 400, y: 300), on: screen)
        XCTAssertEqual(session.click(at: CGPoint(x: 300, y: 100), on: screen), .pinned)
    }

    func testAnglesAtEachInteriorPoint() throws {
        var session = rulerSession()
        session.click(at: CGPoint(x: 200, y: 300), on: screen)
        XCTAssertEqual(session.angles.count, 1)
        XCTAssertEqual(try XCTUnwrap(session.angles.first).degrees, 90, accuracy: 1e-9)
        session.click(at: CGPoint(x: 400, y: 500), on: screen)
        XCTAssertEqual(session.angles.map(\.vertex), [1, 2])
        XCTAssertEqual(session.angles[1].degrees, 135, accuracy: 1e-9)
    }

    // MARK: Pins

    func testPinGapsAreBetweenNeighboursAlongTheRuler() {
        var session = rulerSession()
        session.click(at: CGPoint(x: 300, y: 100), on: screen)
        session.click(at: CGPoint(x: 150, y: 100), on: screen)
        session.click(at: CGPoint(x: 180, y: 100), on: screen)
        XCTAssertEqual(session.pins.map(\.position), [50, 80, 200])
        XCTAssertEqual(session.pins.map(\.gapFromPrevious), [nil, 30, 120])
    }

    func testRepeatingAPinIsNotAnotherPin() {
        var session = rulerSession()
        session.click(at: CGPoint(x: 150, y: 100), on: screen)
        XCTAssertEqual(session.click(at: CGPoint(x: 150.2, y: 103), on: screen), .duplicatePin)
        XCTAssertEqual(session.pins.count, 1)
    }

    func testPinReadingsFollowTheRulerWhenFineTuned() {
        var session = rulerSession()
        session.click(at: CGPoint(x: 150, y: 100), on: screen)
        session.translateRuler(by: CGVector(dx: 10, dy: 0))
        XCTAssertEqual(session.pins.first?.position, 40)
    }

    // MARK: Screens

    func testOtherScreenClicksAreIgnored() {
        var session = rulerSession()
        XCTAssertEqual(session.click(at: CGPoint(x: 1500, y: 300), on: otherScreen), .ignored)
        XCTAssertEqual(session.points.count, 2)
    }

    func testOtherScreenClickAfterFourPointsStartsThere() {
        var session = rulerSession()
        session.click(at: CGPoint(x: 200, y: 300), on: screen)
        session.click(at: CGPoint(x: 400, y: 300), on: screen)
        XCTAssertEqual(session.click(at: CGPoint(x: 1500, y: 300), on: otherScreen), .startedNew)
        XCTAssertEqual(session.bounds, otherScreen)
    }

    func testTopRowOfTheScreenCounts() {
        var session = RulerSession()
        session.click(at: CGPoint(x: 100, y: 100), on: screen)
        XCTAssertEqual(session.click(at: CGPoint(x: 100, y: 800), on: screen), .placedSecond)
    }

    // MARK: Hit testing

    func testHitTestPrefersHandles() {
        let session = rulerSession()
        XCTAssertEqual(session.hitTest(CGPoint(x: 105, y: 103)), .handle(.start))
        XCTAssertEqual(session.hitTest(CGPoint(x: 195, y: 100)), .handle(.end))
        XCTAssertEqual(session.hitTest(CGPoint(x: 150, y: 100)), .body)
        XCTAssertEqual(session.hitTest(CGPoint(x: 150, y: 150)), .offLine)
        XCTAssertNil(RulerSession().hitTest(.zero))
    }

    // MARK: Press and drag

    func testStillPressIsAClickAtThePressPoint() {
        var session = rulerSession()
        session.pressBegan(at: CGPoint(x: 150, y: 100), on: screen)
        session.pressMoved(to: CGPoint(x: 151, y: 101))
        XCTAssertFalse(session.isDragging)
        XCTAssertEqual(session.pressEnded(), .pinned)
        XCTAssertEqual(session.pins.first?.position, 50)
    }

    func testClickingNearAHandleWithoutDraggingStillPins() {
        var session = rulerSession()
        session.pressBegan(at: CGPoint(x: 195, y: 100), on: screen)
        XCTAssertEqual(session.pressEnded(), .pinned)
        XCTAssertEqual(session.points[1], CGPoint(x: 200, y: 100))
    }

    func testDraggingAnEndReAimsAroundTheOtherEnd() {
        var session = rulerSession()
        session.pressBegan(at: CGPoint(x: 197, y: 100), on: screen)
        session.pressMoved(to: CGPoint(x: 197, y: 200))
        XCTAssertEqual(session.points[0], CGPoint(x: 100, y: 100))
        XCTAssertEqual(session.points[1], CGPoint(x: 200, y: 200), "keeps the grab offset")
        XCTAssertNil(session.pressEnded())
        XCTAssertTrue(session.pins.isEmpty)
    }

    func testDraggingTheStartMovesZero() {
        var session = rulerSession()
        session.pressBegan(at: CGPoint(x: 100, y: 100), on: screen)
        session.pressMoved(to: CGPoint(x: 50, y: 100))
        session.pressEnded()
        XCTAssertEqual(session.points[0], CGPoint(x: 50, y: 100))
        XCTAssertEqual(session.points[1], CGPoint(x: 200, y: 100))
    }

    func testDraggingTheMiddleSlidesBothEnds() {
        var session = rulerSession()
        session.pressBegan(at: CGPoint(x: 150, y: 100), on: screen)
        session.pressMoved(to: CGPoint(x: 160, y: 130))
        session.pressMoved(to: CGPoint(x: 170, y: 150))
        session.pressEnded()
        XCTAssertEqual(session.points[0], CGPoint(x: 120, y: 150))
        XCTAssertEqual(session.points[1], CGPoint(x: 220, y: 150))
    }

    func testSlideExtendsFromAlongTheLineFarFromTheEnds() {
        var session = rulerSession()
        session.pressBegan(at: CGPoint(x: 800, y: 100), on: screen)
        session.pressMoved(to: CGPoint(x: 800, y: 110))
        XCTAssertEqual(session.points[0].y, 110)
    }

    func testShiftSnapsADraggedEnd() {
        var session = rulerSession()
        session.pressBegan(at: CGPoint(x: 200, y: 100), on: screen)
        session.pressMoved(to: CGPoint(x: 203, y: 205), snapping: true)
        XCTAssertEqual(session.line?.angleDegrees ?? 0, 45, accuracy: 1e-9)
    }

    func testSnappedDragToVerticalIsExact() {
        var session = rulerSession()
        session.pressBegan(at: CGPoint(x: 200, y: 100), on: screen)
        session.pressMoved(to: CGPoint(x: 104, y: 300), snapping: true)
        XCTAssertEqual(session.points[1].x, 100)
    }

    func testDragCannotCollapseTheRuler() {
        var session = rulerSession()
        session.pressBegan(at: CGPoint(x: 200, y: 100), on: screen)
        session.pressMoved(to: CGPoint(x: 100, y: 100))
        XCTAssertEqual(session.points[1], CGPoint(x: 200, y: 100))
        XCTAssertNotNil(session.line)
    }

    func testDraggedEndStaysOnScreen() {
        var session = rulerSession()
        session.pressBegan(at: CGPoint(x: 200, y: 100), on: screen)
        session.pressMoved(to: CGPoint(x: 1500, y: -40))
        XCTAssertEqual(session.points[1], CGPoint(x: 1000, y: 0))
    }

    func testSnappedEndPulledOffScreenKeepsItsAngle() {
        var session = rulerSession()
        session.pressBegan(at: CGPoint(x: 200, y: 100), on: screen)
        session.pressMoved(to: CGPoint(x: 1500, y: 102), snapping: true)
        XCTAssertEqual(session.points[1], CGPoint(x: 1000, y: 100))
    }

    func testDragOffTheLineIsStillAClickWherePressed() {
        var session = rulerSession()
        session.pressBegan(at: CGPoint(x: 300, y: 400), on: screen)
        session.pressMoved(to: CGPoint(x: 350, y: 450))
        XCTAssertEqual(session.pressEnded(), .addedPoint)
        XCTAssertEqual(session.points[2], CGPoint(x: 300, y: 400))
    }

    func testPressWithNoRulerPlacesPointOnRelease() {
        var session = RulerSession()
        session.pressBegan(at: CGPoint(x: 10, y: 10), on: screen)
        XCTAssertTrue(session.isEmpty)
        XCTAssertEqual(session.pressEnded(), .placedFirst)
        XCTAssertEqual(session.bounds, screen)
    }

    func testPressOnAnotherScreenDoesNotGrabTheRuler() {
        var session = rulerSession()
        session.pressBegan(at: CGPoint(x: 1500, y: 100), on: otherScreen)
        session.pressMoved(to: CGPoint(x: 1600, y: 200))
        XCTAssertEqual(session.pressEnded(), .ignored)
        XCTAssertEqual(session.points[0], CGPoint(x: 100, y: 100))
    }

    // MARK: Nudge and clear

    func testNudgeMovesTheWholeRulerAndStopsAtTheEdge() {
        var session = rulerSession()
        session.translateRuler(by: CGVector(dx: 1, dy: 0))
        XCTAssertEqual(session.points, [CGPoint(x: 101, y: 100), CGPoint(x: 201, y: 100)])
        session.translateRuler(by: CGVector(dx: 0, dy: -500))
        XCTAssertEqual(session.points, [CGPoint(x: 101, y: 0), CGPoint(x: 201, y: 0)])
        XCTAssertEqual(session.rulerLength, 100)
    }

    func testNudgeLeavesAnglePointsWhereTheyWere() {
        var session = rulerSession()
        session.click(at: CGPoint(x: 200, y: 300), on: screen)
        session.translateRuler(by: CGVector(dx: 5, dy: 0))
        XCTAssertEqual(session.points[2], CGPoint(x: 200, y: 300))
    }

    func testClearEmptiesEverything() {
        var session = rulerSession()
        session.click(at: CGPoint(x: 150, y: 100), on: screen)
        session.pressBegan(at: CGPoint(x: 150, y: 100), on: screen)
        session.clear()
        XCTAssertEqual(session, RulerSession())
        XCTAssertNil(session.bounds)
        XCTAssertFalse(session.isPressed)
    }

    func testPlacementPreviewMatchesTheClick() {
        var session = RulerSession()
        session.click(at: CGPoint(x: 100, y: 100), on: screen)
        let preview = session.placement(for: CGPoint(x: 200, y: 103), snapping: true)
        session.click(at: CGPoint(x: 200, y: 103), on: screen, snapping: true)
        XCTAssertEqual(session.points[1], preview)
    }
}
