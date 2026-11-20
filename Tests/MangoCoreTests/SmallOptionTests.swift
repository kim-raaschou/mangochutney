import XCTest
@testable import Mango
@testable import Port

@MainActor
final class SmallOptionTests: MangoTestCase {
    func testTheHotCorner() {
        let r = EngineRig()
        r.server.config.enableHotarea = true
        let c = r.window(900_600)
        r.server.clientFocus(c, false)
        let f = r.monitor.screen.frame
        let corner = CGPoint(x: f.minX + 2, y: f.maxY - 2), away = CGPoint(x: f.midX, y: f.midY)
        c.isfullscreen = true
        r.server.hotarea(corner)
        XCTAssertFalse(r.server.anyOverview, "under a fullscreen window: quiet")
        c.isfullscreen = false
        r.server.hotarea(corner)
        XCTAssertTrue(r.server.anyOverview, "entering the corner opens it")
        r.server.hotarea(corner)
        XCTAssertTrue(r.server.anyOverview, "staying in it does not toggle it again")
        r.server.hotarea(away)
        r.server.hotarea(corner)
        XCTAssertFalse(r.server.anyOverview, "left and entered again: toggled")
    }

    func testTheSpecialDimTakesThePointer() {
        let r = EngineRig()
        r.window(900_601, frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        r.window(900_602, tags: TAG0_MASK | 1, frame: CGRect(x: 1000, y: 100, width: 400, height: 400))
        let normal = CGPoint(x: 300, y: 300), special = CGPoint(x: 1100, y: 200)
        XCTAssertEqual(r.server.nodeAtPoint(normal)?.id, 900_601)
        r.monitor.tagset[r.monitor.seltags] |= TAG0_MASK
        XCTAssertTrue(isSpecialActive(r.monitor))
        XCTAssertNil(r.server.nodeAtPoint(normal), "under the dim")
        XCTAssertEqual(r.server.nodeAtPoint(special)?.id, 900_602)
    }

    /// node_at_point walks the layers from the top: fullscreen lies over floating, floating over tiled;
    /// within a layer the topmost window.
    func testTheTopmostLayerUnderThePointerWins() {
        let r = EngineRig()
        let fake = r.server.system as! FakeWindowSystem
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        r.window(900_610, floating: true, frame: frame)
        r.window(900_611, floating: true, frame: frame)
        let full = r.window(900_612, frame: frame)
        r.window(900_613, frame: frame)
        let p = CGPoint(x: 300, y: 300)
        fake.surfaceOverride = 1
        XCTAssertEqual(r.server.nodeAtPoint(p)?.id, 900_611, "floating over tiled; the latest focused on top")
        fake.surfaceOverride = 900_610
        XCTAssertEqual(r.server.nodeAtPoint(p)?.id, 900_610, "the window server's top within the layer")
        full.isfullscreen = true
        XCTAssertEqual(r.server.nodeAtPoint(p)?.id, 900_612, "fullscreen over floating")
    }

    func testAKeyHidesThePointerAndMovingShowsIt() {
        let r = EngineRig()
        r.server.handleKeyboardKey([.hideCursor])
        XCTAssertFalse(r.server.cursorHidden, "only with cursor_hide_on_keypress")
        r.server.config.cursorHideOnKeypress = true
        r.server.handleKeyboardKey([.hideCursor])
        XCTAssertTrue(r.server.cursorHidden)
        r.server.pointerCursorActivity()
        XCTAssertFalse(r.server.cursorHidden)
    }
}
