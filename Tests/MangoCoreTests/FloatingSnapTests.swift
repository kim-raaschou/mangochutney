import XCTest
@testable import Mango
@testable import Port

final class FloatingSnapTests: MangoTestCase {
    let monitor = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let work = CGRect(x: 0, y: 37, width: 1728, height: 1080)

    func snap(_ f: CGRect, others: [CGRect] = [], distance: CGFloat = 30) -> CGRect {
        FloatingSnap.snapped(f, others: others, monitor: monitor, workArea: work, distance: distance)
    }

    func testAnEdgeWithinTheDistanceSnaps() {
        let f = CGRect(x: 20, y: 60, width: 400, height: 300)
        let s = snap(f)
        XCTAssertEqual(s.minX, 0, "20 from the left edge")
        XCTAssertEqual(s.minY, 37, "23 below the work area's top (the menu bar)")
    }

    func testAnEdgeFurtherAwayStays() {
        let f = CGRect(x: 200, y: 300, width: 400, height: 300)
        XCTAssertEqual(snap(f), f)
        XCTAssertEqual(snap(CGRect(x: 20, y: 300, width: 400, height: 300), distance: 10).minX, 20)
    }

    func testItSnapsToAnotherFloatingWindowsOppositeEdge() {
        let other = CGRect(x: 100, y: 400, width: 300, height: 200)
        let f = CGRect(x: 412, y: 450, width: 300, height: 200)
        XCTAssertEqual(snap(f, others: [other]).minX, 400, "its left edge on the other's right edge")
        XCTAssertEqual(snap(f, others: [other]).minY, 450, "nothing near vertically")
    }

    func testTheNearerSideWinsAndATieGoesRightOrDown() {
        let wide = CGRect(x: 10, y: 400, width: 1710, height: 200)
        XCTAssertEqual(snap(wide).maxX, 1728)
        let tie = CGRect(x: 10, y: 400, width: 1708, height: 200)
        XCTAssertEqual(snap(tie).minX, 20)
    }
}

@MainActor
final class EngineSnapAndSmallDragTests: MangoTestCase {
    func testAFloatingWindowLetGoNearTheEdgeSnapsWhenEnabled() {
        let r = EngineRig()
        r.server.config.enableFloatingSnap = true
        r.server.config.borderpx = 0
        let c = r.window(1, floating: true, frame: CGRect(x: 15, y: 300, width: 500, height: 400))
        r.server.arrange(r.monitor, .none)
        r.settle()
        r.server.applyWindowSnap(c)
        r.settle()
        XCTAssertEqual(c.floatGeom.minX, 0)
        XCTAssertEqual(r.app.frames[1]?.minX, 0, "written to the window")
    }

    func testSnapIsOffByDefaultAsInMango() {
        let r = EngineRig()
        let c = r.window(1, floating: true, frame: CGRect(x: 15, y: 300, width: 500, height: 400))
        r.server.applyWindowSnap(c)
        XCTAssertEqual(c.floatGeom.minX, 15)
    }

    func testATileMovedWithTheMouseShrinksAroundThePointerAndGoesBackOnDrop() {
        let r = EngineRig()
        let a = r.window(1)
        r.window(2)
        r.server.arrange(r.monitor, .none)
        r.settle()
        let tile = a.geom!
        r.monitor.sel = a.id
        let p = CGPoint(x: tile.midX, y: tile.midY)
        let move = MouseBinding(mods: .superKey, button: .left, dispatch: Dispatch(name: "moveresize", args: ["curmove"]))
        r.server.mousebind(move, at: p)
        XCTAssertEqual(r.app.frames[1], CGRect(x: p.x.rounded() - 150, y: p.y.rounded() - 150, width: 300, height: 300))
        r.server.buttonReleased(at: p)
        r.settle()
        XCTAssertEqual(r.app.frames[1], tile, "back in its tile")
    }
}
