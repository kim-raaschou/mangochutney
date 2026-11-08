import XCTest
@testable import Mango
@testable import Port

final class SwipeTrackerTests: MangoTestCase {
    func swipe(_ fingers: Int = 3, from: CGPoint = CGPoint(x: 80, y: 50), path: [CGPoint]) -> [Swipe] {
        var t = SwipeTracker()
        var out: [Swipe] = []
        func feed(_ n: Int, _ p: CGPoint) { if case .end(let s)? = t.frame(fingers: n, centre: p) { out.append(s) } }
        feed(fingers, from)
        var at = from
        for p in path {
            for i in 1...40 {
                let k = CGFloat(i) / 40
                feed(fingers, CGPoint(x: at.x + (p.x - at.x) * k, y: at.y + (p.y - at.y) * k))
            }
            at = p
        }
        for n in stride(from: fingers - 1, through: 0, by: -1) { feed(n, path.last ?? from) }
        return out
    }

    func testASwipeIsReportedWhenAFingerLifts() {
        var t = SwipeTracker()
        XCTAssertNil(t.frame(fingers: 3, centre: CGPoint(x: 80, y: 50)))
        XCTAssertNil(t.frame(fingers: 3, centre: CGPoint(x: 79, y: 50)), "not begun: under libinput's 2 mm")
        XCTAssertEqual(t.frame(fingers: 3, centre: CGPoint(x: 77, y: 50)), .update(.init(dx: 0, dy: 0, fingers: 3)),
                       "begun: the travel counts from here")
        guard case .update(let u)? = t.frame(fingers: 3, centre: CGPoint(x: 60, y: 50)) else { return XCTFail() }
        XCTAssertEqual(u.dx, -17 * 1000 / 25.4, accuracy: 0.01, "libinput's units: 1/1000 inch")
        guard case .end(let s)? = t.frame(fingers: 2, centre: CGPoint(x: 60, y: 50)) else { return XCTFail() }
        XCTAssertEqual(s.fingers, 3)
        XCTAssertEqual(s.dx, u.dx)
        XCTAssertNil(t.frame(fingers: 0, centre: .zero), "one swipe, not one per finger")
    }

    @MainActor func fires(_ s: Swipe, _ direction: Direction, minThreshold: Int = 1) -> Bool {
        let r = EngineRig()
        r.server.config.swipeMinThreshold = minThreshold
        r.server.config.gestureBindings = [GestureBinding(mods: [], direction: direction, fingers: s.fingers,
                                                          dispatch: Dispatch(name: "togglegaps"))]
        let before = r.server.enableGaps
        r.server.pointerProcessSwipeEnd(s)
        return r.server.enableGaps != before
    }

    @MainActor func testDirectionIsTheLongerAxis() {
        let left = swipe(path: [CGPoint(x: 60, y: 45)]).first!
        XCTAssertTrue(fires(left, .left))
        XCTAssertFalse(fires(left, .up))
        let up = swipe(path: [CGPoint(x: 78, y: 30)]).first!
        XCTAssertTrue(fires(up, .up), "y down: a smaller y is up")
    }

    @MainActor func testSwipeMinThreshold() {
        let s = swipe(path: [CGPoint(x: 87, y: 50)]).first!
        XCTAssertTrue(fires(s, .right, minThreshold: 150))
        XCTAssertFalse(fires(s, .right, minThreshold: 250))
    }

    func testRestingFingersAreNoSwipe() {
        XCTAssertTrue(swipe(path: [CGPoint(x: 81, y: 50)]).isEmpty, "1 mm: libinput begins no gesture")
    }

    func testAFingerCountChangeIsANewGesture() {
        var t = SwipeTracker()
        _ = t.frame(fingers: 3, centre: CGPoint(x: 80, y: 50))
        _ = t.frame(fingers: 3, centre: CGPoint(x: 70, y: 50))
        XCTAssertNil(t.frame(fingers: 4, centre: CGPoint(x: 70, y: 50)), "more fingers: the three-finger swipe is dropped")
        _ = t.frame(fingers: 4, centre: CGPoint(x: 70, y: 40))
        _ = t.frame(fingers: 4, centre: CGPoint(x: 70, y: 30))
        guard case .end(let s)? = t.frame(fingers: 3, centre: CGPoint(x: 70, y: 30)) else { return XCTFail() }
        XCTAssertEqual(s.fingers, 4)
        XCTAssertNil(t.frame(fingers: 0, centre: CGPoint(x: 70, y: 30)), "the three left did not move")
    }
}
