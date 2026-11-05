import XCTest

final class RulerGeometryTests: XCTestCase {
    func testProjectionIsPerpendicularAndSigned() throws {
        let line = try XCTUnwrap(RulerLine(from: CGPoint(x: 100, y: 100), through: CGPoint(x: 200, y: 100)))
        XCTAssertEqual(line.position(of: CGPoint(x: 150, y: 400)), 50)
        XCTAssertEqual(line.position(of: CGPoint(x: 40, y: 90)), -60)
        XCTAssertEqual(line.perpendicularDistance(to: CGPoint(x: 150, y: 107)), 7)
    }

    func testProjectionOnADiagonal() throws {
        let line = try XCTUnwrap(RulerLine(from: .zero, through: CGPoint(x: 10, y: 10)))
        XCTAssertEqual(line.position(of: CGPoint(x: 10, y: 0)), 10 / CGFloat(2).squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(line.perpendicularDistance(to: CGPoint(x: 10, y: 0)), 10 / CGFloat(2).squareRoot(), accuracy: 1e-9)
        let foot = line.point(at: line.position(of: CGPoint(x: 10, y: 0)))
        XCTAssertEqual(foot.x, 5, accuracy: 1e-9)
        XCTAssertEqual(foot.y, 5, accuracy: 1e-9)
    }

    func testCoincidentPointsHaveNoLine() {
        XCTAssertNil(RulerLine(from: CGPoint(x: 5, y: 5), through: CGPoint(x: 5, y: 5)))
    }

    func testClipReachesBothScreenEdgesWithNegativeSide() throws {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let line = try XCTUnwrap(RulerLine(from: CGPoint(x: 300, y: 250), through: CGPoint(x: 400, y: 250)))
        XCTAssertEqual(line.clipped(to: screen), -300...700)
    }

    func testClipOnScreenWithNegativeOrigin() throws {
        let screen = CGRect(x: -1000, y: -200, width: 1000, height: 800)
        let line = try XCTUnwrap(RulerLine(from: CGPoint(x: -500, y: 0), through: CGPoint(x: -500, y: 10)))
        XCTAssertEqual(line.clipped(to: screen), -200...600)
    }

    func testClipDiagonalAndMiss() throws {
        let screen = CGRect(x: 0, y: 0, width: 100, height: 100)
        let diagonal = try XCTUnwrap(RulerLine(from: CGPoint(x: 50, y: 50), through: CGPoint(x: 60, y: 60)))
        let range = try XCTUnwrap(diagonal.clipped(to: screen))
        XCTAssertEqual(range.upperBound - range.lowerBound, 100 * CGFloat(2).squareRoot(), accuracy: 1e-9)
        let outside = try XCTUnwrap(RulerLine(from: CGPoint(x: 0, y: 200), through: CGPoint(x: 10, y: 200)))
        XCTAssertNil(outside.clipped(to: screen))
    }

    func testSnapGoesToNearest45AndKeepsLength() {
        let pivot = CGPoint(x: 10, y: 20)
        XCTAssertEqual(RulerSnap.snap(CGPoint(x: 110, y: 24), around: pivot).y, 20)
        XCTAssertEqual(RulerSnap.snap(CGPoint(x: 12, y: 120), around: pivot).x, 10)
        let diagonal = RulerSnap.snap(CGPoint(x: 80, y: 100), around: pivot)
        XCTAssertEqual(diagonal.x - pivot.x, diagonal.y - pivot.y, accuracy: 1e-9)
        let original = CGFloat(hypot(70.0, 80.0))
        XCTAssertEqual(hypot(diagonal.x - pivot.x, diagonal.y - pivot.y), original, accuracy: 1e-9)
    }

    func testSnapHandlesEveryDirection() {
        let expectations: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: -100, y: 3), -100, 0),
            (CGPoint(x: -100, y: -3), -100, 0),
            (CGPoint(x: 3, y: -100), 0, -100),
            (CGPoint(x: 100, y: -3), 100, 0)
        ]
        for (input, x, y) in expectations {
            let snapped = RulerSnap.snap(input, around: .zero)
            XCTAssertEqual(snapped.x, x, accuracy: 0.1)
            XCTAssertEqual(snapped.y, y, accuracy: 0.1)
        }
    }

    private func tilt(_ dx: CGFloat, _ dy: CGFloat, file: StaticString = #filePath, line: UInt = #line) throws -> Double {
        let start = CGPoint(x: 500, y: 500)
        let forward = try XCTUnwrap(RulerLine(from: start, through: CGPoint(x: start.x + dx, y: start.y + dy)))
        let backward = try XCTUnwrap(RulerLine(from: CGPoint(x: start.x + dx, y: start.y + dy), through: start))
        XCTAssertEqual(forward.tiltDegrees, backward.tiltDegrees, accuracy: 1e-9, "click order must not matter", file: file, line: line)
        return forward.tiltDegrees
    }

    func testTiltIsPositiveRisingToTheRightInYUpCoordinates() throws {
        XCTAssertEqual(try tilt(100, 100), 45, accuracy: 1e-9, "AppKit y up: up and to the right")
        XCTAssertEqual(try tilt(100, -100), -45, accuracy: 1e-9, "down and to the right")
    }

    func testTiltOfLevelAndVerticalLines() throws {
        XCTAssertEqual(try tilt(100, 0), 0, accuracy: 1e-9)
        XCTAssertEqual(try tilt(-100, 0), 0, accuracy: 1e-9)
        XCTAssertEqual(try tilt(0, 100), 90, accuracy: 1e-9)
        XCTAssertEqual(try tilt(0, -100), 90, accuracy: 1e-9, "never −90")
    }

    func testTiltStaysInRangeAllTheWayRound() throws {
        for degrees in stride(from: 0.0, to: 360.0, by: 7.0) {
            let radians = degrees * .pi / 180
            let value = try tilt(100 * cos(radians), 100 * sin(radians))
            XCTAssertGreaterThan(value, -90)
            XCTAssertLessThanOrEqual(value, 90)
        }
    }

    func testLabelLanesSeparateOnlyWhatOverlaps() {
        XCTAssertEqual(LabelLanes.assign([0...10, 20...30, 40...50]), [0, 0, 0])
        XCTAssertEqual(LabelLanes.assign([0...10, 5...15, 8...18, 16...20]), [0, 1, 2, 0])
    }
}
