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
        r.server.toggleHotarea(corner)
        XCTAssertFalse(r.server.anyOverview, "under a fullscreen window: quiet")
        c.isfullscreen = false
        r.server.toggleHotarea(corner)
        XCTAssertTrue(r.server.anyOverview, "entering the corner opens it")
        r.server.toggleHotarea(corner)
        XCTAssertTrue(r.server.anyOverview, "staying in it does not toggle it again")
        r.server.toggleHotarea(away)
        r.server.toggleHotarea(corner)
        XCTAssertFalse(r.server.anyOverview, "left and entered again: toggled")
    }

    func testTheSpecialDimTakesThePointer() {
        let r = EngineRig()
        r.window(900_601, frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        r.window(900_602, tags: TAG0_MASK | 1, frame: CGRect(x: 1000, y: 100, width: 400, height: 400))
        let normal = CGPoint(x: 300, y: 300), special = CGPoint(x: 1100, y: 200)
        XCTAssertEqual(r.server.clientAtPoint(normal)?.id, 900_601)
        r.monitor.tagset[r.monitor.seltags] |= TAG0_MASK
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
