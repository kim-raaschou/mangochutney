import XCTest
@testable import Mango
@testable import Port

@MainActor
final class LayerFocusTests: MangoTestCase {
    func testClientTargetLayerIsMangos() {
        let r = EngineRig()
        let c = r.window(1)
        let s = r.server
        XCTAssertEqual(s.clientTargetLayer(c), .tile)
        c.ismaximizescreen = true
        XCTAssertEqual(s.clientTargetLayer(c), .maximize)
        c.isfloating = true
        XCTAssertEqual(s.clientTargetLayer(c), .float, "floating before maximized")
        c.isfullscreen = true
        XCTAssertEqual(s.clientTargetLayer(c), .fullscreen)
        c.isoverlay = true
        XCTAssertEqual(s.clientTargetLayer(c), .overlay)
        c.isoverlay = false
        c.isfullscreen = false
        c.isfloating = false
        c.tags = TAG0_MASK
        XCTAssertEqual(s.clientTargetLayer(c), .specialMaximize)
        c.ismaximizescreen = false
        XCTAssertEqual(s.clientTargetLayer(c), .specialTile)
    }

    func testFloatFullToTopPutsFloatingAndFullscreenOnTop() {
        let r = EngineRig()
        r.server.config.floatFullToTop = true
        let c = r.window(1)
        let s = r.server
        c.isfloating = true
        XCTAssertEqual(s.clientTargetLayer(c), .top)
        c.isfloating = false
        c.isfullscreen = true
        XCTAssertEqual(s.clientTargetLayer(c), .top)
        c.isfullscreen = false
        c.ismaximizescreen = true
        XCTAssertEqual(s.clientTargetLayer(c), .maximize)
        c.tags = TAG0_MASK
        XCTAssertEqual(s.clientTargetLayer(c), .specialMaximize)
        c.ismaximizescreen = false
        c.isfloating = true
        XCTAssertEqual(s.clientTargetLayer(c), .top)
    }

    func testAWindowUnderAMaximizedOneGetsTheFocusWithoutBeingLifted() {
        let r = EngineRig()
        let a = r.window(1), b = r.window(2)
        r.server.arrange(r.monitor, false, false)
        r.server.clientSetMaximizeScreen(a, true, rearrange: true)
        r.settle(1)
        XCTAssertTrue(a.frame.intersects(b.frame))
        XCTAssertFalse(MacWindowSystem.lifts(b, raise: true, in: r.server), "mango's maximize layer stays over it")
        XCTAssertTrue(MacWindowSystem.lifts(a, raise: true, in: r.server))
    }

    func testTiledWindowsAreLiftedAsBefore() {
        let r = EngineRig()
        let a = r.window(1)
        r.window(2)
        r.server.arrange(r.monitor, false, false)
        r.settle(1)
        XCTAssertTrue(MacWindowSystem.lifts(a, raise: true, in: r.server))
    }

    func testAFloatingWindowStaysOverTheTiledOneItCovers() {
        let r = EngineRig()
        let a = r.window(1), b = r.window(2)
        let f = r.window(3, floating: true)
        r.server.arrange(r.monitor, false, false)
        r.settle(1)
        f.frame = CGRect(x: b.frame.midX, y: b.frame.midY, width: 50, height: 50)
        XCTAssertFalse(MacWindowSystem.lifts(b, raise: true, in: r.server))
        XCTAssertFalse(a.frame.intersects(f.frame))
        XCTAssertTrue(MacWindowSystem.lifts(a, raise: true, in: r.server), "nothing of a higher layer over it")
    }

    func testFocusWithoutRaiseNeverLifts() {
        let r = EngineRig()
        let a = r.window(1)
        r.server.arrange(r.monitor, false, false)
        XCTAssertFalse(MacWindowSystem.lifts(a, raise: false, in: r.server), "client_focus(c, 0)")
    }
}
