import XCTest
@testable import Mango
@testable import Port

/// mango's swipe drive (trackpad.c): the fingers drive the transition the binding starts.
@MainActor
final class SwipeDriveTests: MangoTestCase {
    func rig(_ name: String = "viewtoright", _ direction: Direction? = .right, args: [String] = [],
             minSpeed: Double = 50, windows: Bool = true) -> EngineRig {
        let r = EngineRig()
        if windows {
            r.map(1)
            r.map(2).tags = 2
            r.server.arrange(r.monitor, false, false)
            r.settle(0.2)
        }
        r.server.config.gestureSwipeMinSpeedToForce = minSpeed
        r.server.config.gestureBindings = [GestureBinding(mods: [], direction: direction, fingers: 4,
                                                          dispatch: Dispatch(name: name, args: args))]
        return r
    }

    func begin(_ r: EngineRig) { r.server.handleCursorSwipeBegin(4) }
    func move(_ r: EngineRig, _ dx: Double, _ dy: Double = 0, _ t: UInt32) {
        r.server.handleCursorSwipeUpdate(Swipe(dx: dx, dy: dy, fingers: 4), time: t)
    }
    func end(_ r: EngineRig) { r.server.handleCursorSwipeEnd() }
    func viewed(_ r: EngineRig) -> UInt32 { r.monitor.tagset[r.monitor.seltags] }

    /// Slowly to `total` along x, 10 units a step, 100 ms apart.
    func slowly(_ r: EngineRig, to total: Double) {
        var x = 20.0
        move(r, 20, 0, 0)
        var t: UInt32 = 1000
        while x < total { move(r, 10, 0, t); x += 10; t += 100 }
    }

    func testItLocksAfterSixteenUnitsOnTheLongerAxis() {
        let r = rig()
        begin(r)
        move(r, 10, 5, 0)
        XCTAssertFalse(r.server.swipeLocked)
        move(r, 10, 0, 10)
        XCTAssertTrue(r.server.swipeLocked)
        XCTAssertTrue(r.server.swipeHorizontal)
        XCTAssertTrue(r.server.swipeDrive.active, "to the right: the binding drives")
        XCTAssertTrue(r.server.gestureDriveActive)
        let l = rig()
        begin(l)
        move(l, -20, 0, 0)
        XCTAssertFalse(l.server.swipeDrive.consumed, "to the left: no binding")
        let v = rig()
        begin(v)
        move(v, 0, -20, 0)
        XCTAssertFalse(v.server.swipeHorizontal)
    }

    func testTheTransitionFollowsTheFingersInAStraightLine() {
        let r = rig()
        begin(r)
        move(r, 20, 0, 0)
        let start = r.app.frames[2]!
        move(r, 134, 0, 10)   // axis 154: half of the 300 from the base at 4
        let half = r.app.frames[2]!
        move(r, 150, 0, 20)
        let to = r.app.frames[2]!
        XCTAssertNotEqual(start, to)
        let mid = CGRect(x: (start.minX + to.minX) / 2, y: (start.minY + to.minY) / 2,
                         width: (start.width + to.width) / 2, height: (start.height + to.height) / 2)
        XCTAssertEqual(half, mid.rounded(), "client_animation_set_progress is linear")
    }

    func testHeldStillWhileTheFingersRest() {
        let r = rig()
        begin(r)
        move(r, 20, 0, 0)
        move(r, 100, 0, 10)
        let f = r.app.frames[2]
        r.settle(0.5)
        XCTAssertEqual(r.app.frames[2], f, "a gesture-driven client is not drawn on")
    }

    func testShortOfHalfWaySlowlyItIsUndone() {
        let r = rig()
        begin(r)
        slowly(r, to: 120)
        end(r)
        XCTAssertEqual(viewed(r), 1, "the opposite view")
        XCTAssertFalse(r.server.gestureDriveActive)
    }

    func testPastHalfWayItFinishesAtOnceWithAnimationsOff() {
        let r = rig()
        let c = r.server.clientByIdAll(2)!
        begin(r)
        slowly(r, to: 200)
        end(r)
        XCTAssertEqual(viewed(r), 2)
        XCTAssertEqual(r.app.frames[2], c.geom, "no animations: at its end at once")
    }

    func testWithAnimationsOnTheRestRunsFromWhereItIs() {
        let r = rig()
        r.server.config.animations = true
        let c = r.server.clientByIdAll(2)!
        begin(r)
        slowly(r, to: 200)
        let at = r.app.frames[2]
        end(r)
        XCTAssertEqual(r.app.frames[2], at, "on from where the fingers left it")
        r.settle(0.6)
        XCTAssertEqual(r.app.frames[2], c.geom)
    }

    func testAFlickFinishesShortOfTheRatio() {
        let r = rig(minSpeed: 1000)
        begin(r)
        move(r, 20, 0, 0)
        move(r, 40, 0, 50)
        end(r)
        XCTAssertEqual(viewed(r), 2, "within 200 ms: a flick")
    }

    func testOverviewIsAlwaysFinished() {
        let r = rig("toggleoverview", .up)
        begin(r)
        move(r, 0, -20, 0)
        move(r, 0, -10, 1000)
        end(r)
        XCTAssertTrue(r.server.anyOverview)
    }

    func testFiredWithNoTransitionItIsNotFiredAgainAtTheEnd() {
        let r = rig(windows: false)
        begin(r)
        move(r, 20, 0, 0)
        move(r, 200, 0, 10)
        XCTAssertFalse(r.server.gestureDriveActive, "unfrozen at once")
        end(r)
        XCTAssertEqual(viewed(r), 2, "once, not again on release")
    }

    func testADragMovesTheWindowWithTheFingers() {
        let r = rig("moveresize", nil, args: ["curmove"])
        let c = r.server.clientByIdAll(1)!
        _ = r.server.dispatch(Dispatch(name: "togglefloating"), target: c)
        r.server.clientFocus(c, true)
        r.settle(0.2)
        let fake = r.server.system as! FakeWindowSystem
        fake.fakePointer = c.frame.center
        let before = c.frame
        begin(r)
        move(r, 20, 0, 0)
        XCTAssertTrue(r.server.trackpadGestureDragActive())
        move(r, 30, 0, 10)
        let dx = 30 * r.monitor.screen.workArea.width / 300
        XCTAssertEqual(c.frame.minX - before.minX, dx, accuracy: 1)
        end(r)
        XCTAssertNil(r.server.grab)
        XCTAssertFalse(r.server.trackpadGestureDragActive())
    }

    func testADragWithNoDistanceDoesNotMove() {
        let r = rig("moveresize", nil, args: ["curmove"])
        r.server.config.gestureSwipeDistance = 0
        let c = r.server.clientByIdAll(1)!
        _ = r.server.dispatch(Dispatch(name: "togglefloating"), target: c)
        r.settle(0.2)
        let before = c.frame
        begin(r)
        move(r, 20, 0, 0)
        move(r, 30, 0, 10)
        XCTAssertEqual(c.frame, before)
        end(r)
    }

    func testAPanInTheScrollerFocusesTheWindowItBrings() {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .scroller
        r.map(1); r.map(2); r.map(3)
        r.server.clientFocus(r.server.clientByIdAll(2), true)
        r.server.arrange(r.monitor, false, false)
        r.settle(0.2)
        r.server.config.gestureBindings = [GestureBinding(mods: [], direction: nil, fingers: 4,
                                                          dispatch: Dispatch(name: "focusdir", args: ["right"]))]
        let sel = r.monitor.sel
        begin(r)
        move(r, -20, 0, 0)
        XCTAssertTrue(r.server.swipeDrive.pan)
        XCTAssertTrue(r.server.gestureDriveActive, "mango freezes for a pan too")
        move(r, -150, 0, 1000)
        end(r)
        XCTAssertNotEqual(r.monitor.sel, sel, "the window panned to the middle")
        XCTAssertFalse(r.server.gestureDriveActive)
    }
}
