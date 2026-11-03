import XCTest
@testable import Mango
@testable import Port

/// mango's hotarea_disable_on_fullscreen, special_dim's hold on the pointer and
/// cursor_hide_on_keypress.
@MainActor
final class SmallOptionTests: MangoTestCase {
    /// mango toggle_hotarea: quiet under a fullscreen window (hotarea_disable_on_fullscreen);
    /// otherwise entering the corner opens the overview once, until the pointer leaves it.
    func testTheHotCorner() {
        let r = EngineRig()
        r.server.config.enableHotarea = true
        let c = r.window(900_600)
        r.server.clientFocus(c, raise: false)
        let f = r.monitor.screen.frame
        let corner = CGPoint(x: f.minX + 2, y: f.maxY - 2), away = CGPoint(x: f.midX, y: f.midY)
        c.isFullscreen = true
        r.server.toggleHotarea(corner)
        XCTAssertNil(r.server.overviewState, "under a fullscreen window: quiet")
        c.isFullscreen = false
        r.server.toggleHotarea(corner)
        XCTAssertNotNil(r.server.overviewState, "entering the corner opens it")
        r.server.toggleHotarea(corner)
        XCTAssertNotNil(r.server.overviewState, "staying in it does not toggle it again")
        r.server.toggleHotarea(away)
        r.server.toggleHotarea(corner)
        XCTAssertNil(r.server.overviewState, "left and entered again: toggled")
    }

    /// While the special tag is shown its dim lies over the other windows: the pointer
    /// finds only the special tag's windows.
    func testTheSpecialDimTakesThePointer() {
        let r = EngineRig()
        r.window(900_601, frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        r.window(900_602, tags: TagMask.special | 1, frame: CGRect(x: 1000, y: 100, width: 400, height: 400))
        let normal = CGPoint(x: 300, y: 300), special = CGPoint(x: 1100, y: 200)
        XCTAssertEqual(r.server.clientAtPoint(normal)?.id, 900_601)
        r.monitor.tagset[r.monitor.seltags] |= TagMask.special
        XCTAssertTrue(r.server.isSpecialActive(r.monitor))
        XCTAssertNil(r.server.clientAtPoint(normal), "under the dim")
        XCTAssertEqual(r.server.clientAtPoint(special)?.id, 900_602)
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
