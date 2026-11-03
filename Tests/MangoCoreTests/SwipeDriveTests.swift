import XCTest
@testable import Mango
@testable import Port

/// mango's swipe drive (swipe_drive_update, _begin, _end): locking, progress, finishing or
/// undoing, through mango's own handler.
@MainActor
final class SwipeDriveTests: MangoTestCase {
    func s(_ dx: Double, _ dy: Double = 0) -> Swipe { .init(dx: dx, dy: dy, fingers: 4) }

    /// A rig whose four-finger swipe `direction` drives `name`; the fake starts its animation.
    func rig(_ name: String = "viewtoright", _ direction: Direction = .right, minSpeed: Double = 50) -> (EngineRig, FakeWindowSystem) {
        let r = EngineRig()
        r.map(1)
        r.server.config.gestureSwipeMinSpeedToForce = minSpeed
        r.server.config.gestureBindings = [GestureBinding(mods: [], direction: direction, fingers: 4,
                                                          dispatch: Dispatch(name: name))]
        let fake = r.server.system as! FakeWindowSystem
        fake.fakeAnimating = true
        return (r, fake)
    }

    func update(_ r: EngineRig, _ sw: Swipe, _ t: UInt32) { r.server.handleCursorSwipeUpdate(sw, time: t) }

    func testItLocksAfterSixteenUnitsOnTheLongerAxis() {
        let (r, _) = rig()
        update(r, s(10, 5), 0)
        XCTAssertEqual(r.server.swipeDrive?.locked, false)
        update(r, s(20, 5), 10)
        XCTAssertEqual(r.server.swipeDrive?.locked, true)
        XCTAssertEqual(r.server.swipeDrive?.horizontal, true)
        XCTAssertNotNil(r.server.swipeDriving, "to the right: the binding drives")
        let (l, _) = rig()
        update(l, s(-20), 0)
        XCTAssertNil(l.server.swipeDriving, "to the left: no binding")
    }

    /// mango starts the way SWIPE_LOCK_DISTANCE before where the swipe locked.
    func testProgressAndUndo() {
        let (r, fake) = rig()
        update(r, s(20), 0)
        update(r, s(20), 10)
        XCTAssertEqual(fake.animationProgress.last ?? -1, 16.0 / 300, accuracy: 0.001)
        for (i, x) in stride(from: 30.0, through: 120, by: 10).enumerated() { update(r, s(x), UInt32(1000 + i * 100)) }
        r.server.handleCursorSwipeEnd(s(120))
        XCTAssertEqual(fake.letGo, 1, "a third of the way, slowly: undone")
        XCTAssertTrue(fake.resumedFrom.isEmpty)
    }

    func testPastHalfWayFinishes() {
        let (r, fake) = rig()
        update(r, s(20), 0)
        for (i, x) in stride(from: 30.0, through: 120, by: 10).enumerated() { update(r, s(x), UInt32(1000 + i * 100)) }
        update(r, s(200), 3000)
        r.server.handleCursorSwipeEnd(s(200))
        XCTAssertEqual(fake.resumedFrom.count, 1, "past half way: finished")
    }

    func testOverviewIsAlwaysFinished() {
        let (r, fake) = rig("toggleoverview", .up)
        update(r, s(0, -20), 0)
        update(r, s(0, -30), 1000)
        r.server.handleCursorSwipeEnd(s(0, -30))
        XCTAssertEqual(fake.resumedFrom.count, 1)
    }

    func testAFlickFinishesShortOfTheRatio() {
        let (r, fake) = rig(minSpeed: 1000)
        update(r, s(20), 0)
        update(r, s(60), 50)
        r.server.handleCursorSwipeEnd(s(60))
        XCTAssertEqual(fake.resumedFrom.count, 1, "within 200 ms: a flick")
    }

    func testAVerticalSwipeLocksVertically() {
        let (r, _) = rig()
        update(r, s(0, -20), 0)
        XCTAssertEqual(r.server.swipeDrive?.horizontal, false)
    }
}
