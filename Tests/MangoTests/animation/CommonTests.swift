import XCTest
@testable import Mango
import MangoTestKit

/// mango's src/animation/common.c
@MainActor
final class CommonTests: XCTestCase {

    // MARK: find_animation_curve_at

    /// The curve is baked in BAKED_POINTS_COUNT points and read at the first point past t.
    func testTheCurveIsReadFromItsBakedPoints() {
        let mango = TestMango()
        let s = mango.server
        let step = 1.0 / Double(BAKED_POINTS_COUNT - 1)
        XCTAssertEqual(s.findAnimationCurveAt(0, .move), s.calculateAnimationCurveAt(step, .move).y,
                       "at 0 the first point past it")
        XCTAssertEqual(s.findAnimationCurveAt(1, .move), 1, "at the end the last point")
        XCTAssertEqual(s.findAnimationCurveAt(0.5, .tag), s.bakedPointsTag.first { $0.x > 0.5 }?.y)
    }

    /// A curve set by a reload is baked again (reset_option).
    func testAReloadBakesTheCurvesAgain() {
        let mango = TestMango()
        let s = mango.server
        let before = s.findAnimationCurveAt(0.5, .open)
        s.config.animationCurveOpen = .linear
        XCTAssertEqual(s.findAnimationCurveAt(0.5, .open), before, "not baked till reset_option")
        s.initBakedPoints()
        let point = s.bakedPointsOpen.first { $0.x > 0.5 }!
        XCTAssertEqual(point.y, point.x, "a linear curve's points lie on y = x")
        XCTAssertEqual(s.findAnimationCurveAt(0.5, .open), point.y)
        XCTAssertNotEqual(s.findAnimationCurveAt(0.5, .open), before)
    }
}
