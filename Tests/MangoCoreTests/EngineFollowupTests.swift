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

    /// mango parse_func_name: movewin's and resizewin's fields are parse_num_type and atoi of the rest;
    /// a number that is no number (nan, inf) is 0, as the port's atof reads only finite numbers.
    @MainActor
    func testDispatcherNumbersAreMangosParse() {
        var arg = Arg()
        XCTAssertNotNil(BindingParser.parseFuncName("movewin", &arg, "+30", "40", "0", "0", "0"))
        XCTAssertEqual(arg.ui, NUM_TYPE_PLUS)
        XCTAssertEqual(arg.i, 30)
        XCTAssertEqual(arg.ui2, NUM_TYPE_DEFAULT)
        XCTAssertEqual(arg.i2, 40)
        XCTAssertNotNil(BindingParser.parseFuncName("resizewin", &arg, "-5", "nan", "0", "0", "0"))
        XCTAssertEqual(arg.ui, NUM_TYPE_MINUS)
        XCTAssertEqual(arg.i, 5)
        XCTAssertEqual(arg.i2, 0)
        XCTAssertNotNil(BindingParser.parseFuncName("setmfact", &arg, "nan", "0", "0", "0", "0"))
        XCTAssertEqual(arg.f, 0)
        XCTAssertNotNil(BindingParser.parseFuncName("set_proportion", &arg, "inf", "0", "0", "0", "0"))
        XCTAssertEqual(arg.f, 0)
    }

    /// mango's setoption joins every field after the key that is not empty, so a binding's "0"
    /// (not given) ends up in the value: `setoption,circle_layout,tile,scroller` gives
    /// "tile,scroller,0,0". Ours skips the binding's "0" there, as combine_args_until_empty does.
    @MainActor
    func testSetoptionSkipsTheBindingsUngivenFields() {
        var arg = Arg()
        XCTAssertNotNil(BindingParser.parseFuncName("setoption", &arg, "circle_layout", "tile", "scroller", "0", "0"))
        XCTAssertEqual(arg.v, "circle_layout")
        XCTAssertEqual(arg.v2, "tile,scroller")
        XCTAssertNotNil(BindingParser.parseFuncName("setoption", &arg, "animations", "0", "0", "0", "0"))
        XCTAssertEqual(arg.v2, "0")
        XCTAssertNotNil(BindingParser.parseFuncName("setoption", &arg, "gappih", "5", "", "", ""))
        XCTAssertEqual(arg.v2, "5")
    }
}
