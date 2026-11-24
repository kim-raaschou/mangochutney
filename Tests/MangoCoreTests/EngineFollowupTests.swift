import XCTest
@testable import Mango
@testable import Port

final class EngineFollowupTests: MangoTestCase {
    func testClampMatchesMangoOverrideConfig() {
        var c = Config()
        c.overcircleCenterRatio = 0.99
        c.hotareaSize = 0
        c.gestureSwipeDistance = 5
        c.gestureSwipeCancelRatio = 1
        c.scratchpadWidthRatio = 3
        c.specialGappoh = -4
        c.gestureSwipeMinSpeedToForce = -1
        c.overrideConfig()
        XCTAssertEqual(c.overcircleCenterRatio, 0.9)
        XCTAssertEqual(c.hotareaSize, 1)
        XCTAssertEqual(c.gestureSwipeDistance, 32)
        XCTAssertEqual(c.gestureSwipeCancelRatio, 0.95)
        XCTAssertEqual(c.scratchpadWidthRatio, 1)
        XCTAssertEqual(c.specialGappoh, 0)
        XCTAssertEqual(c.gestureSwipeMinSpeedToForce, 0)
    }

    /// mango's parse_func_name joins setoption's fields after the key that are not empty, and the
    /// keybinding parser gives the fields a binding does not give as "0", so
    /// `bind=…,setoption,circle_layout,tile,scroller` gives "tile,scroller,0,0" in mango. Ours gives
    /// a binding's missing fields to setoption as "", as IPC does (docs/afvigelser.md §6).
    @MainActor
    func testSetoptionSkipsTheBindingsUngivenFields() {
        var arg = Arg()
        XCTAssertNotNil(BindingParser.parseFuncName("setoption", &arg, "circle_layout", "tile", "scroller", "0", "0"))
        XCTAssertEqual(arg.v, "circle_layout")
        XCTAssertEqual(arg.v2, "tile,scroller,0,0", "parse_func_name is mango's: only empty fields are skipped")
        XCTAssertNotNil(BindingParser.parseFuncName("setoption", &arg, "gappih", "5", "", "", ""))
        XCTAssertEqual(arg.v2, "5")

        let r = EngineRig()
        let parsed = ConfigParser.parse(text: "bind=SUPER,a,setoption,circle_layout,tile,scroller\nbind=SUPER,b,setoption,animations,0\n",
                                        baseDirectory: FileManager.default.temporaryDirectory, fileName: "t.conf")
        XCTAssertEqual(parsed.errors, [])
        r.server.config.animations = true
        r.server.dispatch(parsed.config.keyBindings[0].dispatch)
        XCTAssertEqual(r.server.config.circleLayout, ["tile", "scroller"])
        r.server.dispatch(parsed.config.keyBindings[1].dispatch)
        XCTAssertFalse(r.server.config.animations, "a given 0 is the value")
    }

    /// A field given as "0" is kept, as in mango: `setoption,animation_curve_move,0,0,1,1` sets 0,0,1,1.
    @MainActor
    func testSetoptionKeepsGivenZeros() {
        let r = EngineRig()
        let parsed = ConfigParser.parse(text: "bind=SUPER,a,setoption,animation_curve_move,0,0,1,1\n",
                                        baseDirectory: FileManager.default.temporaryDirectory, fileName: "t.conf")
        XCTAssertEqual(parsed.errors, [])
        r.server.dispatch(parsed.config.keyBindings[0].dispatch)
        XCTAssertEqual(r.server.config.animationCurveMove, BezierCurve(x1: 0, y1: 0, x2: 1, y2: 1))

        r.server.config.animationCurveMove = BezierCurve(x1: 0.5, y1: 0.5, x2: 0.5, y2: 0.5)
        r.server.dispatch(Dispatch(name: "setoption", args: ["animation_curve_move", "0", "0", "1", "1"]), notGiven: "")
        XCTAssertEqual(r.server.config.animationCurveMove, BezierCurve(x1: 0, y1: 0, x2: 1, y2: 1), "IPC's path")
    }
}
