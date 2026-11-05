import XCTest

final class CalibrationStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "ARRulerTests.calibration"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testMeasuredDerivesTheScale() throws {
        let override = try XCTUnwrap(CalibrationOverride.measured(rulerLengthPoints: 400, trueLengthCm: 10, longEdgePoints: 1920))
        XCTAssertEqual(override.pointsPerCm, 40)
    }

    func testMeasuredRejectsNonsense() {
        XCTAssertNil(CalibrationOverride.measured(rulerLengthPoints: 400, trueLengthCm: 0, longEdgePoints: 1920))
        XCTAssertNil(CalibrationOverride.measured(rulerLengthPoints: 400, trueLengthCm: -5, longEdgePoints: 1920))
        XCTAssertNil(CalibrationOverride.measured(rulerLengthPoints: 400, trueLengthCm: 1000, longEdgePoints: 1920), "typo: 0.4 pt/cm")
        XCTAssertNil(CalibrationOverride.measured(rulerLengthPoints: 400, trueLengthCm: 0.1, longEdgePoints: 1920), "typo: 4000 pt/cm")
    }

    func testOverrideFollowsAScaledResolutionChange() {
        let override = CalibrationOverride(pointsPerCm: 40, longEdgePoints: 1920)
        XCTAssertEqual(override.pointsPerCm(forLongEdge: 1920), 40)
        XCTAssertEqual(override.pointsPerCm(forLongEdge: 1280), 40 * 1280 / 1920)
    }

    func testPersistsPerDisplayAcrossInstances() {
        let store = CalibrationStore(defaults: defaults)
        store.save(CalibrationOverride(pointsPerCm: 40, longEdgePoints: 1920), forDisplay: "A")
        store.save(CalibrationOverride(pointsPerCm: 50, longEdgePoints: 2560), forDisplay: "B")
        let reopened = CalibrationStore(defaults: defaults)
        XCTAssertEqual(reopened.override(forDisplay: "A")?.pointsPerCm, 40)
        XCTAssertEqual(reopened.override(forDisplay: "B")?.pointsPerCm, 50)
        XCTAssertNil(reopened.override(forDisplay: "C"))
    }

    func testResetOnlyAffectsThatDisplay() {
        let store = CalibrationStore(defaults: defaults)
        store.save(CalibrationOverride(pointsPerCm: 40, longEdgePoints: 1920), forDisplay: "A")
        store.save(CalibrationOverride(pointsPerCm: 50, longEdgePoints: 2560), forDisplay: "B")
        store.reset(display: "A")
        XCTAssertNil(store.override(forDisplay: "A"))
        XCTAssertNotNil(store.override(forDisplay: "B"))
    }
}
