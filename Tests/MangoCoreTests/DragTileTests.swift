import XCTest
@testable import Mango
@testable import Port

/// mango's drag_tile_to_tile: the drop's direction and area (client_set_drop_area) and
/// where the dropped window goes (pointer_place_drag_tile).
@MainActor
final class DragTileTests: MangoTestCase {
    let tile = CGRect(x: 100, y: 100, width: 400, height: 200)

    func area(_ layout: LayoutKind, _ p: CGPoint, master: Bool = false, tiled: Int = 3,
              simple: Bool = true) -> (DropDirection, CGRect) {
        DropArea.clientSetDropArea(layout: layout, target: tile, at: p, isMaster: master, tiled: tiled,
                         dwindleSimpleSplit: simple, dwindleSplitRatio: 0.5)
    }

    func testTheDirectionsAndAreasAreMangos() {
        // tile: a master with others is replaced as a whole; alone, split left/right.
        XCTAssertEqual(area(.tile, CGPoint(x: 150, y: 150), master: true).0, DropDirection.none)
        XCTAssertEqual(area(.tile, CGPoint(x: 150, y: 150), master: true, tiled: 1).1, CGRect(x: 100, y: 100, width: 200, height: 200))
        // tile stack: upper or lower half.
        XCTAssertEqual(area(.tile, CGPoint(x: 150, y: 150)).0, .up)
        XCTAssertEqual(area(.tile, CGPoint(x: 150, y: 250)).1, CGRect(x: 100, y: 200, width: 400, height: 100))
        // vertical tile stack: left or right half.
        XCTAssertEqual(area(.verticalTile, CGPoint(x: 450, y: 150)).0, .right)
        // others: the nearest edge.
        XCTAssertEqual(area(.grid, CGPoint(x: 110, y: 200)).0, .left)
        XCTAssertEqual(area(.grid, CGPoint(x: 300, y: 295)).0, .down)
        // dwindle: the two parts the split would make; four sides without the simple split.
        XCTAssertEqual(area(.dwindle, CGPoint(x: 400, y: 110)).0, .right, "wide: left or right")
        XCTAssertEqual(area(.dwindle, CGPoint(x: 400, y: 110), simple: false).0, .up)
    }

    /// Three tiles: 900_500 master, 900_501 and 900_502 stacked.
    func rig(_ layout: LayoutKind = .tile) -> EngineRig {
        let r = EngineRig()
        r.monitor.current.layout = layout
        for i in 0..<3 { r.window(CGWindowID(900_500 + i)) }
        r.server.arrange(r.monitor, .none)
        return r
    }

    func frame(_ r: EngineRig, _ id: CGWindowID) -> CGRect { r.server.clientByIdAll(id)!.geom! }

    /// Picks `id` up with a mousebind move and drops it at `p`.
    func drag(_ r: EngineRig, _ id: CGWindowID, to p: CGPoint) {
        let move = MouseBinding(mods: [.superKey], button: .left, dispatch: Dispatch(name: "moveresize", args: ["curmove"]))
        let f = frame(r, id)
        r.server.mousebind(move, at: CGPoint(x: f.midX, y: f.midY))
        XCTAssertTrue(r.server.clientByIdAll(id)!.isFloating, "it floats while it is dragged")
        r.server.pointerProcessMotion(p, time: 0)
        r.server.buttonReleased(at: p)
    }

    func tiledOrder(_ r: EngineRig) -> [CGWindowID] { r.server.tiledClients(r.monitor).map(\.id) }

    func testDroppedAboveAStackTileItGoesBeforeIt() {
        let r = rig()
        let lower = frame(r, 900_502)
        drag(r, 900_501, to: CGPoint(x: lower.midX, y: lower.maxY - 10))   // after the others filled its place
        XCTAssertFalse(r.server.clientByIdAll(900_501)!.isFloating)
        XCTAssertEqual(tiledOrder(r), [900_500, 900_502, 900_501], "below the lower half: after it")
    }

    func testDroppedOnTheMasterItTakesItsPlace() {
        let r = rig()
        let master = frame(r, 900_500)
        drag(r, 900_502, to: CGPoint(x: master.midX, y: master.midY))
        XCTAssertEqual(tiledOrder(r), [900_502, 900_500, 900_501])
        XCTAssertEqual(r.monitor.sel, 900_502)
    }

    func testTheScrollerStacksItAboveOrBelow() {
        let r = rig(.scroller)
        r.server.clientFocus(r.server.clientByIdAll(900_500)!, raise: false)
        r.server.arrange(r.monitor)   // mango's client_focus arranges only when moving from a window (prevsel)
        let f = frame(r, 900_500)
        // 900_502 is off the screen here: picked up as an app's own title-bar drag is.
        r.server.clientBeginDragFloat(r.server.clientByIdAll(900_502)!, at: CGPoint(x: 1, y: 1))
        r.server.dropDraggedTile(at: CGPoint(x: f.midX, y: f.maxY - 5))
        XCTAssertEqual(r.monitor.current.state.scrollerState.column(of: 900_500), [900_500, 900_502], "nearest edge the bottom: below it, in its stack")
    }

    /// drag_tile_small for any drag of a tile, the app's own title-bar drag too.
    func testAPickedUpTileShrinksAroundThePointer() {
        let r = rig()
        r.app.writes.removeAll()   // the rig's own arrange
        r.server.clientBeginDragFloat(r.server.clientByIdAll(900_501)!, at: CGPoint(x: 500, y: 400))
        XCTAssertEqual(r.server.clientByIdAll(900_501)!.frame, CGRect(x: 350, y: 250, width: 300, height: 300))
        XCTAssertEqual(r.app.writes.first { $0.id == 900_501 }?.frame, CGRect(x: 350, y: 250, width: 300, height: 300))
    }

    func testWithoutDragTileToTileItStaysFloating() {
        let r = rig()
        r.server.config.dragTileToTile = false
        drag(r, 900_501, to: CGPoint(x: 300, y: 300))
        XCTAssertTrue(r.server.clientByIdAll(900_501)!.isFloating)
    }

    func testTheFloatingPlaceComesBack() {
        let r = rig()
        let before = CGRect(x: 10, y: 50, width: 300, height: 200)
        r.server.clientByIdAll(900_501)!.floatGeom = before
        drag(r, 900_501, to: CGPoint(x: frame(r, 900_500).midX, y: frame(r, 900_500).midY))
        XCTAssertEqual(r.server.clientByIdAll(900_501)!.floatGeom, before, "mango's drag_tile_float_backup_geom")
    }
}
