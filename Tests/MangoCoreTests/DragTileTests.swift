import XCTest
@testable import Mango
@testable import Port

@MainActor
final class DragTileTests: MangoTestCase {
    let tile = CGRect(x: 100, y: 100, width: 400, height: 200)

    /// client_set_drop_area on a tile with no border: its direction and the area the port is given.
    func area(_ layout: LayoutKind, _ p: CGPoint, master: Bool = false, tiled: Int32 = 3,
              simple: Bool = true) -> (Int32, CGRect?) {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = layout
        r.server.config.dwindleDropSimpleSplit = simple
        r.server.config.dwindleSplitRatio = 0.5
        let c = r.window(900_499, frame: tile)
        c.bw = 0
        c.geom = tile
        c.ismaster = master
        r.monitor.visibleTilingClients = tiled
        r.server.fake.fakePointer = p
        c.enableDropAreaDraw = true
        r.server.clientSetDropArea(c)
        return (c.dropDirection, r.server.fake.shownDropArea)
    }

    func testTheDirectionsAndAreasAreMangos() {
        XCTAssertEqual(area(.tile, CGPoint(x: 150, y: 150), master: true).0, UNDIR)
        XCTAssertEqual(area(.tile, CGPoint(x: 150, y: 150), master: true, tiled: 1).1, CGRect(x: 100, y: 100, width: 200, height: 200))
        XCTAssertEqual(area(.tile, CGPoint(x: 150, y: 150)).0, UP)
        XCTAssertEqual(area(.tile, CGPoint(x: 150, y: 250)).1, CGRect(x: 100, y: 200, width: 400, height: 100))
        XCTAssertEqual(area(.verticalTile, CGPoint(x: 450, y: 150)).0, RIGHT)
        XCTAssertEqual(area(.grid, CGPoint(x: 110, y: 200)).0, LEFT)
        XCTAssertEqual(area(.grid, CGPoint(x: 300, y: 295)).0, DOWN)
        XCTAssertEqual(area(.dwindle, CGPoint(x: 400, y: 110)).0, RIGHT, "wide: left or right")
        XCTAssertEqual(area(.dwindle, CGPoint(x: 400, y: 110), simple: false).0, UP)
    }

    func testTheDropAreaGoesOffWithTheDropClient() {
        let r = EngineRig()
        let c = r.window(900_499, frame: tile)
        c.enableDropAreaDraw = true
        r.server.clientSetDropArea(c)
        XCTAssertNotNil(r.server.fake.shownDropArea)
        c.enableDropAreaDraw = false
        r.server.clientSetDropArea(c)
        XCTAssertNil(r.server.fake.shownDropArea)
    }

    func rig(_ layout: LayoutKind = .tile) -> EngineRig {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = layout
        for i in 0..<3 { r.window(CGWindowID(900_500 + i)) }
        r.arrange()
        return r
    }

    func testAPickedUpTileShrinksAroundThePointer() {
        let r = rig()
        r.app.writes.removeAll()
        let c = r.server.clientByWindowID(900_501)!
        r.server.fake.fakePointer = CGPoint(x: 500, y: 400)
        r.server.pointerBeginMoveResize(c, CurMove, 500, 400, [])
        r.frame()
        XCTAssertEqual(c.geom, CGRect(x: 350, y: 250, width: 300, height: 300), "pointer_begin_move_resize's 300 by 300")
        let inside = c.geom.insetBy(dx: c.bw, dy: c.bw)
        XCTAssertEqual(r.app.writes.last { $0.id == 900_501 }?.frame, inside)
    }

}
