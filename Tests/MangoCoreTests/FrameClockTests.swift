import XCTest
@testable import Mango
@testable import Port

/// The port's output frames: the display link calls mango's handle_output_frame while a frame is scheduled.
@MainActor
final class FrameClockTests: MangoTestCase {
    func testItRunsAtOnceWhenNothingAnimates() {
        let r = EngineRig()
        var ran = false
        r.server.mac.frameClock.whenIdle { ran = true }
        XCTAssertTrue(ran)
    }

    func testItRunsWhenTheLastAnimationEnds() {
        let r = EngineRig()
        r.server.config.animations = true
        r.server.config.animationDurationMove = 60
        let c = r.window(900_010, frame: CGRect(x: 0, y: 40, width: 100, height: 100))
        c.isfloating = true
        r.arrange()
        r.settle(0.3)
        c.floatGeom = CGRect(x: 200, y: 40, width: 100, height: 100)
        r.arrange()
        XCTAssertTrue(c.animation.running)
        var ran = false
        r.server.mac.frameClock.whenIdle { ran = true }
        XCTAssertFalse(ran, "still animating")
        r.settle(0.3)
        XCTAssertTrue(ran)
        XCTAssertEqual(r.app.frames[900_010]?.minX, 200)
    }

    func testAWholeSizeAtAHalfPointOriginKeepsItsSize() {
        for x in [-0.5, 0.5, 1.5, -1.5] as [CGFloat] {
            XCTAssertEqual(CGRect(x: x, y: x, width: 301, height: 200).rounded().size, CGSize(width: 301, height: 200))
        }
    }
}
