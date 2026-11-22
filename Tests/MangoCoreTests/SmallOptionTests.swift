import XCTest
@testable import Mango
@testable import Port

@MainActor
final class SmallOptionTests: MangoTestCase {

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
