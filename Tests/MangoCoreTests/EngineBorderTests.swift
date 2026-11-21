import XCTest
@testable import Mango
@testable import Port

final class EngineBorderTests: MangoTestCase {
    func testRingIsOutsideTheWindow() {
        let win = CGRect(x: 100, y: 50, width: 800, height: 600)
        let outer = BorderGeometry.overlayFrame(window: win, width: 4)
        XCTAssertEqual(outer, CGRect(x: 96, y: 46, width: 808, height: 608))
        XCTAssertTrue(outer.contains(win))
    }

    func testInnerEdgeOfStrokeMatchesWindowCorner() {
        XCTAssertEqual(BorderGeometry.outerRadius(corner: 16, width: 4), 20)
        XCTAssertEqual(BorderGeometry.outerRadius(corner: 16, width: 1), 17)
        XCTAssertEqual(BorderGeometry.outerRadius(corner: 0, width: 4), 0)
    }

    func testTheRingFollowsMacOSWindowCorners() {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        XCTAssertEqual(BorderGeometry.cornerRadius, major >= 26 ? 16 : 10)
    }

    func testTheCornerRadiusIsNotASetting() {
        var c = Config()
        guard !parseOption("border_corner_radius", "12", to: &c) else {
            return XCTFail("not a mango key, and the ring follows macOS")
        }
    }
}

@MainActor
final class BorderInsideTheTileTests: MangoTestCase {
    func frames(_ r: EngineRig, borders: Bool) -> [CGWindowID: CGRect] {
        r.server.renderBorder = borders
        r.arrange()
        return Dictionary(uniqueKeysWithValues: r.server.clientsAll.map { ($0.id, $0.tile) })
    }

    func rig(_ n: Int, layout: LayoutKind = .tile) -> EngineRig {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = layout
        r.server.config.borderpx = 4
        for i in 0..<n { r.window(CGWindowID(900_500 + i)) }
        return r
    }

    func testATileHoldsItsWindowAndItsBorder() {
        let r = rig(2)
        let boxes = frames(r, borders: false)
        let windows = frames(r, borders: true)
        for (id, box) in boxes { XCTAssertEqual(windows[id], box.insetBy(dx: 4, dy: 4), "\(id)") }
    }

    func testNoBorderFillsTheTile() {
        let r = rig(2)
        r.server.clientByIdAll(900_500)!.noBorder = true
        let boxes = frames(r, borders: false)
        let windows = frames(r, borders: true)
        XCTAssertEqual(windows[900_500], boxes[900_500])
        XCTAssertEqual(windows[900_501], boxes[900_501]!.insetBy(dx: 4, dy: 4))
    }

    func testOneWindowShownHasNoBorderWithNoBorderWhenSingle() {
        let r = rig(1)
        r.server.config.noBorderWhenSingle = true
        XCTAssertEqual(frames(r, borders: true), frames(r, borders: false))
        r.window(900_510, floating: true)
        let windows = frames(r, borders: true)
        let boxes = frames(r, borders: false)
        XCTAssertEqual(windows[900_500], boxes[900_500])
        r.window(900_511)
        let two = frames(r, borders: true)
        let twoBoxes = frames(r, borders: false)
        XCTAssertEqual(two[900_500], twoBoxes[900_500]!.insetBy(dx: 4, dy: 4))
    }

    func testMonocleNoBorderFillsTheTile() {
        let r = rig(2, layout: .monocle)
        r.server.config.monocleNoBorder = true
        XCTAssertEqual(frames(r, borders: true), frames(r, borders: false))
    }

    func testEveryMonocleWindowHasItsBorder() {
        let r = rig(2, layout: .monocle)
        r.server.renderBorder = true
        r.server.drawsOverlays = true
        let f = r.window(900_520, floating: true)
        r.monitor.sel = f.id
        r.arrange()
        r.server.updateBorders()
        let ids = Set((r.server.system as! FakeWindowSystem).borderSpecs.map(\.id))
        let shown = Set(r.server.clientsAll.filter { !$0.parked }.map(\.id))
        XCTAssertTrue(shown.contains(900_500) && shown.contains(900_520))
        XCTAssertEqual(ids, shown, "client_draw_border has no layout test: the top tiled window keeps its border")
    }

    func testMonocleNoRadius() {
        let r = rig(2, layout: .monocle)
        r.server.config.borderRadius = 6
        let c = r.server.clientsAll[0]
        XCTAssertFalse(r.server.clientNoRadiusActive(c), "off: mango's default")
        r.server.config.monocleNoRadius = true
        XCTAssertTrue(r.server.clientNoRadiusActive(c))
        c.isfloating = true
        XCTAssertFalse(r.server.clientNoRadiusActive(c), "a floating window keeps its corners")
        c.isfloating = false
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .tile
        XCTAssertFalse(r.server.clientNoRadiusActive(c), "only in monocle")
    }

    func testArrangingAgainMovesNothing() {
        for layout in [LayoutKind.scroller, .tile, .dwindle, .deck] {
            let r = rig(3, layout: layout)
            r.monitor.sel = 900_501
            let first = frames(r, borders: true)
            r.arrange()
            r.arrange()
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: r.server.clientsAll.map { ($0.id, $0.tile) }), first, "\(layout)")
        }
    }

}
