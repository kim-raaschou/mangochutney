import XCTest
@testable import Mango
@testable import Port

@MainActor
final class AnimatorIdleTests: MangoTestCase {
    func testItRunsAtOnceWhenNothingAnimates() {
        let a = Animator()
        var ran = false
        a.whenIdle { ran = true }
        XCTAssertTrue(ran)
    }

    func testItRunsWhenTheLastAnimationEnds() {
        let a = Animator()
        let app = FakeApp()
        a.animate(id: 900_010, element: app.element(for: 900_010), queue: app,
                  from: CGRect(x: 0, y: 0, width: 100, height: 100), to: CGRect(x: 200, y: 0, width: 100, height: 100),
                  durationMs: 60, curve: BezierCurve(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1))
        var ran = false
        a.whenIdle { ran = true }
        XCTAssertFalse(ran, "still animating")
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        XCTAssertTrue(ran)
        XCTAssertEqual(app.frames[900_010]?.minX, 200)
    }
}
