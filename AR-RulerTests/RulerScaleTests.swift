import XCTest

final class RulerScaleTests: XCTestCase {
    func testCentimetreTickLevels() {
        let scale = RulerScale(unit: .cm, pointsPerCm: 40)
        let ticks = scale.ticks(in: 0...40)
        XCTAssertEqual(ticks.count, 11)
        XCTAssertEqual(ticks[0], RulerTick(position: 0, level: .major, value: 0))
        XCTAssertEqual(ticks[1].level, .minor)
        XCTAssertEqual(ticks[5].level, .mid)
        XCTAssertEqual(ticks[10], RulerTick(position: 40, level: .major, value: 1))
    }

    func testInchTickLevels() {
        let scale = RulerScale(unit: .inch, pointsPerCm: 72 / 2.54)
        let ticks = scale.ticks(in: 0...72.0001)
        XCTAssertEqual(ticks.count, 9)
        XCTAssertEqual(ticks[1].level, .minor)
        XCTAssertEqual(ticks[1].position, 9, accuracy: 1e-9)
        XCTAssertEqual(ticks[4].level, .mid)
        XCTAssertEqual(ticks[8].value, 1)
    }

    func testNegativeReadingsBehindZero() {
        let ticks = RulerScale(unit: .cm, pointsPerCm: 40).ticks(in: -44...0)
        XCTAssertEqual(ticks.first?.position ?? 0, -44, accuracy: 1e-9)
        XCTAssertEqual(ticks.first(where: { $0.value != nil })?.value, -1)
        XCTAssertEqual(ticks.first?.level, .minor)
        XCTAssertEqual(ticks[1].position, -40, accuracy: 1e-9)
        XCTAssertEqual(ticks[6].level, .mid, "−0.5 cm")
    }

    func testDenseLevelsHide() {
        XCTAssertEqual(RulerScale(unit: .cm, pointsPerCm: 40).finestVisibleLevel, .minor)
        XCTAssertEqual(RulerScale(unit: .cm, pointsPerCm: 20).finestVisibleLevel, .mid)
        XCTAssertEqual(RulerScale(unit: .cm, pointsPerCm: 5).finestVisibleLevel, .major)
        let ticks = RulerScale(unit: .cm, pointsPerCm: 20).ticks(in: 0...20)
        XCTAssertEqual(ticks.map(\.level), [.major, .mid, .major])
        XCTAssertEqual(RulerScale(unit: .cm, pointsPerCm: 5).ticks(in: 0...10).map(\.value), [0, 1, 2])
    }

    func testNoDriftFarFromZero() {
        let scale = RulerScale(unit: .cm, pointsPerCm: 37.795)
        let ticks = scale.ticks(in: (37.795 * 100 - 0.01)...(37.795 * 100 + 0.01))
        XCTAssertEqual(ticks.count, 1)
        XCTAssertEqual(ticks[0].value, 100)
    }

    func testLabelStrideGrowsWhenCrowded() {
        let scale = RulerScale(unit: .cm, pointsPerCm: 10)
        XCTAssertEqual(scale.labelStride(forLabelExtent: 9), 1)
        XCTAssertEqual(scale.labelStride(forLabelExtent: 15), 2)
        XCTAssertEqual(scale.labelStride(forLabelExtent: 41), 5)
    }

    func testFormatting() {
        let scale = RulerScale(unit: .cm, pointsPerCm: 10)
        XCTAssertEqual(ReadingFormat.reading(123.4, scale: scale), "12.34 cm")
        XCTAssertEqual(ReadingFormat.reading(-5, scale: scale), "\u{2212}0.50 cm")
        XCTAssertEqual(ReadingFormat.reading(-0.001, scale: scale), "0.00 cm", "no negative zero")
        XCTAssertEqual(ReadingFormat.gap(20, scale: scale), "\u{0394} 2.00")
        XCTAssertEqual(ReadingFormat.tickLabel(-3), "\u{2212}3")
        XCTAssertEqual(ReadingFormat.angle(89.96), "90.0\u{00B0}")
        let inches = RulerScale(unit: .inch, pointsPerCm: 10)
        XCTAssertEqual(ReadingFormat.reading(25.4, scale: inches), "1.00 in")
    }
}
