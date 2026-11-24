import XCTest
@testable import Mango
@testable import Port

@MainActor
final class FloatingSnapTests: MangoTestCase {
    /// apply_window_snap on a floating client alone on its monitor (borderpx 0).
    func snap(_ f: CGRect, distance: Int = 30) -> CGRect {
        let r = EngineRig()
        r.server.config.enableFloatingSnap = true
        r.server.config.borderpx = 0
        r.server.config.snapDistance = distance
        let c = r.window(1, floating: true, frame: f)
        c.geom = f
        r.server.applyWindowSnap(c)
        return c.floatGeom
    }

    func testAnEdgeWithinTheDistanceSnaps() {
        let s = snap(CGRect(x: 20, y: 60, width: 400, height: 300))
        XCTAssertEqual(s.minX, 0, "20 from the left edge")
        XCTAssertEqual(s.minY, 37, "23 below the work area's top (the menu bar)")
    }

    func testTheNearerSideWinsAndATieGoesRightOrDown() {
        XCTAssertEqual(snap(CGRect(x: 10, y: 400, width: 1710, height: 200)).maxX, 1728)
        XCTAssertEqual(snap(CGRect(x: 10, y: 400, width: 1708, height: 200)).minX, 20)
    }
}

@MainActor
final class EngineSnapAndSmallDragTests: MangoTestCase {
    func testAFloatingWindowLetGoNearTheEdgeSnapsWhenEnabled() {
        let r = EngineRig()
        r.server.config.enableFloatingSnap = true
        r.server.config.borderpx = 0
        let c = r.window(1, floating: true, frame: CGRect(x: 15, y: 300, width: 500, height: 400))
        r.arrange()
        r.settle()
        r.server.applyWindowSnap(c)
        r.settle()
        XCTAssertEqual(c.floatGeom.minX, 0)
        XCTAssertEqual(r.app.frames[1]?.minX, 0, "written to the window")
    }

    func testATileMovedWithTheMouseShrinksAroundThePointerAndGoesBackOnDrop() {
        let r = EngineRig()
        let a = r.window(1)
        r.window(2)
        r.arrange()
        r.settle()
        let tile = a.geom
        r.monitor.sel = a
        let p = CGPoint(x: tile.midX, y: tile.midY)
        let move = MouseBinding(mods: .superKey, button: .left, dispatch: Dispatch(name: "moveresize", args: ["curmove"]))
        r.server.mousebind(move, at: p)
        r.frame()
        let small = CGRect(x: p.x.rounded() - 150, y: p.y.rounded() - 150, width: 300, height: 300)
        XCTAssertEqual(a.geom, small)
        XCTAssertEqual(r.app.frames[1], small.insetBy(dx: a.bw, dy: a.bw), "written at the frame")
        r.server.buttonReleased(at: p)
        r.settle()
        XCTAssertEqual(r.app.frames[1], tile, "back in its tile")
    }
}
