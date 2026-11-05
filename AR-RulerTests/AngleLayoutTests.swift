import XCTest

final class AngleLayoutTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    /// A length with its tilt, as wide as they get: "12.34 cm · −89.9°".
    private let lengthSize = CGSize(width: 112, height: 18)
    private let angleSize = CGSize(width: 52, height: 20)

    private func layout(_ points: [CGPoint]) -> AngleLayout {
        AngleLayout(
            points: points,
            lengthSizes: Array(repeating: lengthSize, count: points.count - 1),
            angleSizes: Array(repeating: angleSize, count: points.count - 2),
            bounds: screen
        )
    }

    private func assertClean(_ points: [CGPoint], context: String, file: StaticString = #filePath, line: UInt = #line) {
        let result = layout(points)
        let boxes = result.angleBoxes + result.lengthBoxes
        XCTAssertEqual(boxes.count, (points.count - 2) + (points.count - 1), context, file: file, line: line)
        for (index, box) in boxes.enumerated() {
            XCTAssertTrue(screen.contains(box), "off screen: \(context)", file: file, line: line)
            for other in boxes[(index + 1)...] {
                XCTAssertFalse(box.intersects(other), "labels overlap: \(context)", file: file, line: line)
            }
            for segment in 0..<(points.count - 1) {
                XCTAssertFalse(AngleLayout.segment(points[segment], points[segment + 1], intersects: box), "label on a line: \(context)", file: file, line: line)
            }
        }
    }

    func testNoCollisionsAtAnyAngle() {
        let vertex = CGPoint(x: 900, y: 500)
        for baseDegrees in stride(from: 0.0, to: 360.0, by: 30.0) {
            for openingDegrees in stride(from: 2.0, through: 178.0, by: 4.0) {
                for turn in [1.0, -1.0] {
                    let base = baseDegrees * .pi / 180
                    let other = base + turn * openingDegrees * .pi / 180
                    let a = CGPoint(x: vertex.x + 300 * cos(base), y: vertex.y + 300 * sin(base))
                    let c = CGPoint(x: vertex.x + 220 * cos(other), y: vertex.y + 220 * sin(other))
                    assertClean([a, vertex, c], context: "base \(baseDegrees) opening \(openingDegrees) turn \(turn)")
                }
            }
        }
    }

    func testAngleSitsInsideTheWedgeWhenItFits() {
        let result = layout([CGPoint(x: 600, y: 500), CGPoint(x: 900, y: 500), CGPoint(x: 900, y: 800)])
        let box = result.angleBoxes[0]
        XCTAssertLessThan(box.maxX, 900)
        XCTAssertGreaterThan(box.minY, 500)
    }

    func testVeryTightAngleGoesOutsideTheVertexRatherThanOnTheLines() {
        let vertex = CGPoint(x: 900, y: 500)
        let result = layout([CGPoint(x: 500, y: 500), vertex, CGPoint(x: 500, y: 515)])
        XCTAssertGreaterThan(result.angleBoxes[0].minX, vertex.x)
    }

    func testLengthsSitOutsideTheWedge() {
        let result = layout([CGPoint(x: 600, y: 500), CGPoint(x: 900, y: 500), CGPoint(x: 900, y: 800)])
        XCTAssertLessThan(result.lengthBoxes[0].maxY, 500, "below the first arm, away from the angle above it")
        XCTAssertGreaterThan(result.lengthBoxes[1].minX, 900, "right of the second arm, away from the angle to its left")
    }

    func testFourPointsStayClean() {
        assertClean([CGPoint(x: 300, y: 300), CGPoint(x: 800, y: 300), CGPoint(x: 1000, y: 700), CGPoint(x: 1400, y: 500)], context: "zigzag")
        assertClean([CGPoint(x: 300, y: 300), CGPoint(x: 800, y: 300), CGPoint(x: 400, y: 340), CGPoint(x: 800, y: 380)], context: "tight zigzag")
    }

    func testVertexNearAScreenEdgeStaysOnScreen() {
        assertClean([CGPoint(x: 300, y: 8), CGPoint(x: 8, y: 8), CGPoint(x: 8, y: 300)], context: "bottom-left corner")
        assertClean([CGPoint(x: 1600, y: 1072), CGPoint(x: 1912, y: 1072), CGPoint(x: 1912, y: 800)], context: "top-right corner")
    }

    func testArcStaysSmallAndFollowsTheShorterAngleWay() throws {
        let result = layout([CGPoint(x: 600, y: 500), CGPoint(x: 900, y: 500), CGPoint(x: 900, y: 800)])
        let arc = try XCTUnwrap(result.arcs.first)
        XCTAssertLessThanOrEqual(arc.radius, 18)
        XCTAssertEqual(abs(arc.sweep), .pi / 2, accuracy: 1e-9)
    }

    func testSegmentIntersection() {
        let box = CGRect(x: 10, y: 10, width: 10, height: 10)
        XCTAssertTrue(AngleLayout.segment(CGPoint(x: 0, y: 15), CGPoint(x: 30, y: 15), intersects: box))
        XCTAssertTrue(AngleLayout.segment(CGPoint(x: 15, y: 15), CGPoint(x: 16, y: 16), intersects: box))
        XCTAssertFalse(AngleLayout.segment(CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0), intersects: box))
        XCTAssertFalse(AngleLayout.segment(CGPoint(x: 0, y: 15), CGPoint(x: 5, y: 15), intersects: box))
    }
}
