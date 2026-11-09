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
        c.isMaximizeScreen = true
        XCTAssertEqual(s.clientTargetLayer(c), .maximize)
        c.isFloating = true
        XCTAssertEqual(s.clientTargetLayer(c), .float, "floating before maximized")
        c.isFullscreen = true
        XCTAssertEqual(s.clientTargetLayer(c), .fullscreen)
        c.isOverlay = true
        XCTAssertEqual(s.clientTargetLayer(c), .overlay)
        c.isOverlay = false
        c.isFullscreen = false
        c.isFloating = false
        c.tags = TagMask.special
        XCTAssertEqual(s.clientTargetLayer(c), .specialMaximize)
        c.isMaximizeScreen = false
        XCTAssertEqual(s.clientTargetLayer(c), .specialTile)
    }

    func testFloatFullToTopPutsFloatingAndFullscreenOnTop() {
        let r = EngineRig()
        r.server.config.floatFullToTop = true
        let c = r.window(1)
        let s = r.server
        c.isFloating = true
        XCTAssertEqual(s.clientTargetLayer(c), .top)
        c.isFloating = false
        c.isFullscreen = true
        XCTAssertEqual(s.clientTargetLayer(c), .top)
        c.isFullscreen = false
        c.isMaximizeScreen = true
        XCTAssertEqual(s.clientTargetLayer(c), .maximize)
        c.tags = TagMask.special
        XCTAssertEqual(s.clientTargetLayer(c), .specialMaximize)
        c.isMaximizeScreen = false
        c.isFloating = true
        XCTAssertEqual(s.clientTargetLayer(c), .top)
    }

    func testAWindowUnderAMaximizedOneGetsTheFocusWithoutBeingLifted() {
        let r = EngineRig()
        let a = r.window(1), b = r.window(2)
        r.server.arrange(r.monitor, .none)
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
        r.server.arrange(r.monitor, .none)
        r.settle(1)
        XCTAssertTrue(MacWindowSystem.lifts(a, raise: true, in: r.server))
    }

    func testAFloatingWindowStaysOverTheTiledOneItCovers() {
        let r = EngineRig()
        let a = r.window(1), b = r.window(2)
        let f = r.window(3, floating: true)
        r.server.arrange(r.monitor, .none)
        r.settle(1)
        f.frame = CGRect(x: b.frame.midX, y: b.frame.midY, width: 50, height: 50)
        XCTAssertFalse(MacWindowSystem.lifts(b, raise: true, in: r.server))
        XCTAssertFalse(a.frame.intersects(f.frame))
        XCTAssertTrue(MacWindowSystem.lifts(a, raise: true, in: r.server), "nothing of a higher layer over it")
    }

    func testFocusWithoutRaiseNeverLifts() {
        let r = EngineRig()
        let a = r.window(1)
        r.server.arrange(r.monitor, .none)
        XCTAssertFalse(MacWindowSystem.lifts(a, raise: false, in: r.server), "client_focus(c, 0)")
    }
}
