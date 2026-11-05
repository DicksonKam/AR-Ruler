import XCTest

final class RulerSessionTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let otherScreen = CGRect(x: 1000, y: 0, width: 1000, height: 800)

    /// A horizontal ruler from (100, 100) to (200, 100), with 100 points to the unit. The scale runs 0...200
    /// (x 100...300), the body x 88...312, and it lies above the line, y 100...132.
    private func rulerSession() -> RulerSession {
        var session = RulerSession()
        session.pointsPerUnit = 100
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

    // MARK: Finite ruler

    func testScaleEndsAWholeUnitAtLeastOnePastTheSecondClick() {
        var session = RulerSession()
        session.pointsPerUnit = 40
        session.click(at: CGPoint(x: 100, y: 100), on: screen)
        session.click(at: CGPoint(x: 400, y: 100), on: screen) // 7.5 units
        XCTAssertEqual(session.scaleRange, 0...360, "7.5 + 1 rounds up to 9 units")
    }

    func testScaleFitWhenTheSecondClickIsOnAWholeUnit() {
        let session = rulerSession()
        XCTAssertEqual(session.scaleRange, 0...200)
    }

    func testBodyHasShortMarginsBeyondTheScale() {
        let session = rulerSession()
        let margin = RulerSession.bodyMargin
        XCTAssertEqual(session.bodyRange, -margin...(200 + margin))
    }

    func testScaleStopsWithRoomForItsMarginAtTheScreenEdge() {
        var session = RulerSession()
        session.pointsPerUnit = 100
        session.click(at: CGPoint(x: 700, y: 100), on: screen)
        session.click(at: CGPoint(x: 850, y: 100), on: screen)
        XCTAssertEqual(session.scaleRange, 0...200, "3 units wouldn't fit before the edge at 300 with the margin")
        XCTAssertEqual(session.bodyRange?.upperBound, 200 + RulerSession.bodyMargin)
    }

    func testScaleNeverStopsShortOfTheSecondClick() {
        var session = RulerSession()
        session.pointsPerUnit = 100
        session.click(at: CGPoint(x: 700, y: 100), on: screen)
        session.click(at: CGPoint(x: 995, y: 100), on: screen)
        XCTAssertEqual(session.scaleRange, 0...295)
        XCTAssertEqual(session.bodyRange?.upperBound, 300, "the body stops at the screen edge")
    }

    func testFollowsAChangeOfUnit() {
        var session = rulerSession()
        session.pointsPerUnit = 30
        XCTAssertEqual(session.scaleRange, 0...150, "100 + 30 rounds up to 5 units")
    }

    func testBodyLiesUpOrLeftUnlessThereIsNoRoom() {
        XCTAssertEqual(rulerSession().bodySide, CGVector(dx: 0, dy: 1))
        var plumb = RulerSession()
        plumb.click(at: CGPoint(x: 500, y: 100), on: screen)
        plumb.click(at: CGPoint(x: 500, y: 300), on: screen)
        XCTAssertEqual(plumb.bodySide, CGVector(dx: -1, dy: 0))
        var atTop = RulerSession()
        atTop.click(at: CGPoint(x: 100, y: 790), on: screen)
        atTop.click(at: CGPoint(x: 300, y: 790), on: screen)
        XCTAssertEqual(atTop.bodySide, CGVector(dx: 0, dy: -1))
        var atLeft = RulerSession()
        atLeft.click(at: CGPoint(x: 10, y: 100), on: screen)
        atLeft.click(at: CGPoint(x: 10, y: 300), on: screen)
        XCTAssertEqual(atLeft.bodySide, CGVector(dx: 1, dy: 0))
    }

    // MARK: Lengthening

    func testDraggingTheGripLengthensInWholeUnitsOnly() throws {
        var session = rulerSession()
        let grip = try XCTUnwrap(session.gripPoint)
        session.pressBegan(at: grip, on: screen)
        session.pressMoved(to: CGPoint(x: grip.x + 130, y: grip.y + 40))
        XCTAssertEqual(session.scaleRange, 0...300, "+130 along the ruler rounds to one more unit")
        XCTAssertNil(session.pressEnded())
        XCTAssertEqual(session.points, [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 100)], "angle and zero don't change")
        XCTAssertEqual(session.line?.angleDegrees, 0)
    }

    func testGripCanShortenOnlyAsFarAsTheSecondClick() throws {
        var session = rulerSession()
        let grip = try XCTUnwrap(session.gripPoint)
        session.pressBegan(at: grip, on: screen)
        session.pressMoved(to: CGPoint(x: grip.x - 500, y: grip.y))
        session.pressEnded()
        XCTAssertEqual(session.scaleRange, 0...100)
    }

    func testGripDragStopsAtTheScreenEdge() throws {
        var session = rulerSession()
        let grip = try XCTUnwrap(session.gripPoint)
        session.pressBegan(at: grip, on: screen)
        session.pressMoved(to: CGPoint(x: grip.x + 5000, y: grip.y))
        session.pressEnded()
        XCTAssertEqual(session.scaleRange, 0...800, "the edge is at 900, less the margin")
    }

    func testClickingTheGripDoesNothing() throws {
        var session = rulerSession()
        let before = session
        let grip = try XCTUnwrap(session.gripPoint)
        session.pressBegan(at: grip, on: screen)
        XCTAssertNil(session.pressEnded())
        XCTAssertEqual(session, before)
    }

    func testGripIsSeparateFromTheSecondPointEvenAtShortestLength() throws {
        var session = rulerSession()
        var grip = try XCTUnwrap(session.gripPoint)
        session.pressBegan(at: grip, on: screen)
        session.pressMoved(to: CGPoint(x: grip.x - 500, y: grip.y))
        session.pressEnded()
        grip = try XCTUnwrap(session.gripPoint)
        XCTAssertEqual(session.hitTest(grip), .endGrip)
        XCTAssertEqual(session.hitTest(session.points[1]), .handle(.end))
    }

    // MARK: Click classification

    func testClickOnOrNearTheBodyPins() {
        var session = rulerSession()
        XCTAssertEqual(session.click(at: CGPoint(x: 150, y: 92), on: screen), .pinned, "just below the edge")
        XCTAssertEqual(session.click(at: CGPoint(x: 180, y: 120), on: screen), .pinned, "on the body")
        XCTAssertEqual(session.click(at: CGPoint(x: 230, y: 140), on: screen), .pinned, "just above the body")
        XCTAssertEqual(session.pins.map(\.position), [50, 80, 130])
        XCTAssertEqual(session.points.count, 2)
    }

    func testClickJustOffTheBodyIsAnAnglePoint() {
        var below = rulerSession()
        XCTAssertEqual(below.click(at: CGPoint(x: 150, y: 91.5), on: screen), .addedPoint)
        var above = rulerSession()
        XCTAssertEqual(above.click(at: CGPoint(x: 150, y: 140.5), on: screen), .addedPoint)
    }

    func testClickPastTheEndOfTheRulerIsAnAnglePointEvenOnItsLine() {
        var session = rulerSession()
        XCTAssertEqual(session.click(at: CGPoint(x: 900, y: 100), on: screen), .addedPoint)
        var behind = rulerSession()
        XCTAssertEqual(behind.click(at: CGPoint(x: 40, y: 100), on: screen), .addedPoint)
    }

    func testToleranceAroundTheEnds() {
        var session = rulerSession()
        XCTAssertEqual(session.click(at: CGPoint(x: 319, y: 100), on: screen), .pinned)
        var past = rulerSession()
        XCTAssertEqual(past.click(at: CGPoint(x: 321, y: 100), on: screen), .addedPoint)
    }

    func testPinJustOffTheEndIsBroughtOntoTheBody() {
        var session = rulerSession()
        session.click(at: CGPoint(x: 319, y: 100), on: screen)
        XCTAssertEqual(session.pins.first?.position, 200 + RulerSession.bodyMargin)
    }

    // MARK: Hover

    func testReadingOnlyOnOrNearTheBody() {
        let session = rulerSession()
        XCTAssertEqual(session.reading(at: CGPoint(x: 150, y: 120)), 50)
        XCTAssertEqual(session.reading(at: CGPoint(x: 150, y: 95)), 50)
        XCTAssertNil(session.reading(at: CGPoint(x: 150, y: 300)))
        XCTAssertNil(session.reading(at: CGPoint(x: 700, y: 100)))
    }

    func testReadingIsHeldOnTheBodyAndShowsItsMarginsTruthfully() {
        let session = rulerSession()
        XCTAssertEqual(session.reading(at: CGPoint(x: 92, y: 100)), -8)
        XCTAssertEqual(session.reading(at: CGPoint(x: 318, y: 100)), 200 + RulerSession.bodyMargin)
    }

    // MARK: Third click

    func testThirdClickSwitchesToAnAngleMeasurement() {
        var session = rulerSession()
        session.click(at: CGPoint(x: 150, y: 100), on: screen)
        XCTAssertEqual(session.click(at: CGPoint(x: 200, y: 300), on: screen), .addedPoint)
        XCTAssertFalse(session.hasRuler)
        XCTAssertTrue(session.isAngleMeasurement)
        XCTAssertNil(session.line)
        XCTAssertNil(session.bodyRange)
        XCTAssertNil(session.gripPoint)
        XCTAssertNil(session.reading(at: CGPoint(x: 150, y: 100)))
        XCTAssertTrue(session.pins.isEmpty)
        XCTAssertTrue(session.pinSources.isEmpty, "pins are gone for good, not hidden")
    }

    func testEveryClickInAnAngleMeasurementIsAPointThenTheNextStartsOver() {
        var session = rulerSession()
        session.click(at: CGPoint(x: 200, y: 300), on: screen)
        XCTAssertEqual(session.click(at: CGPoint(x: 150, y: 100), on: screen), .addedPoint, "where the ruler was no longer pins")
        XCTAssertEqual(session.points.count, 4)
        XCTAssertEqual(session.click(at: CGPoint(x: 700, y: 600), on: screen), .startedNew)
        XCTAssertEqual(session.points, [CGPoint(x: 700, y: 600)])
        XCTAssertFalse(session.isAngleMeasurement)
    }

    func testAngleMeasurementCannotBeMoved() {
        var session = rulerSession()
        session.click(at: CGPoint(x: 200, y: 300), on: screen)
        let before = session.points
        session.translateRuler(by: CGVector(dx: 5, dy: 5))
        XCTAssertEqual(session.points, before)
        XCTAssertNil(session.hitTest(CGPoint(x: 150, y: 100)))
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

    func testPinLeftOffTheEndIsHiddenAndReturnsWhenTheBodyReachesIt() throws {
        var session = rulerSession()
        session.click(at: CGPoint(x: 150, y: 100), on: screen)
        session.translateRuler(by: CGVector(dx: 300, dy: 0))
        XCTAssertTrue(session.pins.isEmpty, "the pin's spot is now behind the ruler")
        session.translateRuler(by: CGVector(dx: -300, dy: 0))
        XCTAssertEqual(session.pins.first?.position, 50)
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
        XCTAssertEqual(session.hitTest(CGPoint(x: 150, y: 150)), .offRuler)
        XCTAssertEqual(session.hitTest(CGPoint(x: 800, y: 100)), .offRuler)
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

    func testBodyPastTheSecondClickSlidesToo() {
        var session = rulerSession()
        session.pressBegan(at: CGPoint(x: 280, y: 120), on: screen)
        session.pressMoved(to: CGPoint(x: 280, y: 130))
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

    // MARK: Moving and clearing

    func testMovingTheWholeRulerStopsAtTheEdge() {
        var session = rulerSession()
        session.translateRuler(by: CGVector(dx: 1, dy: 0))
        XCTAssertEqual(session.points, [CGPoint(x: 101, y: 100), CGPoint(x: 201, y: 100)])
        session.translateRuler(by: CGVector(dx: 0, dy: -500))
        XCTAssertEqual(session.points, [CGPoint(x: 101, y: 0), CGPoint(x: 201, y: 0)])
        XCTAssertEqual(session.rulerLength, 100)
    }

    func testClearEmptiesEverything() {
        var session = rulerSession()
        session.click(at: CGPoint(x: 150, y: 100), on: screen)
        session.pressBegan(at: CGPoint(x: 150, y: 100), on: screen)
        session.clear()
        var expected = RulerSession()
        expected.pointsPerUnit = session.pointsPerUnit
        XCTAssertEqual(session, expected)
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
