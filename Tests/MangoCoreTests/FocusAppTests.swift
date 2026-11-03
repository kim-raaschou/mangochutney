import XCTest
@testable import Mango
@testable import Port

/// chutney_focus_app (port extension) follows AeroControl's one-key-per-app rules
/// (`Visit.open`, `Strip.opened`). Windows are in grid order, `recent` newest first.
final class FocusAppTests: MangoTestCase {
    func testNoWindowsStartsTheApp() {
        XCTAssertEqual(FocusAppRule.decide(windows: [], current: 7, recent: [7]), .launch)
        XCTAssertEqual(FocusAppRule.decide(windows: [], current: nil, recent: []), .launch)
    }

    func testOneWindowIsFocused() {
        XCTAssertEqual(FocusAppRule.decide(windows: [1], current: 9, recent: [9]), .focus(1))
        XCTAssertEqual(FocusAppRule.decide(windows: [1], current: 1, recent: [1]), .focus(1))
    }

    func testFromAnotherAppTheWindowUsedLast() {
        XCTAssertEqual(FocusAppRule.decide(windows: [1, 2, 3], current: 9, recent: [9, 3, 1]), .focus(3))
        XCTAssertEqual(FocusAppRule.decide(windows: [1, 2], current: 9, recent: [9, 2]), .focus(2))
        // never used: the first in grid order
        XCTAssertEqual(FocusAppRule.decide(windows: [1, 2, 3], current: nil, recent: []), .focus(1))
    }

    func testTwoWindowsToggle() {
        XCTAssertEqual(FocusAppRule.decide(windows: [1, 2], current: 1, recent: [1, 2]), .focus(2))
        XCTAssertEqual(FocusAppRule.decide(windows: [1, 2], current: 2, recent: [2]), .focus(1))
    }

    func testThreeOrMoreGoToTheOneUsedBefore() {
        XCTAssertEqual(FocusAppRule.decide(windows: [1, 2, 3, 4], current: 1, recent: [1, 3, 2]), .focus(3))
        // nothing used before: the next in grid order, wrapping
        XCTAssertEqual(FocusAppRule.decide(windows: [1, 2, 3], current: 2, recent: [2]), .focus(3))
        XCTAssertEqual(FocusAppRule.decide(windows: [1, 2, 3], current: 3, recent: [3, 9]), .focus(1))
    }

    func testFocusAppIsAKnownPortExtension() {
        XCTAssertTrue(Dispatch.isKnown("chutney_focus_app"))
        XCTAssertFalse(Dispatch.knownNames.contains("chutney_focus_app"))
        guard case .success(let d) = BindingParser.parseFuncName(["chutney_focus_app", "com.mitchellh.ghostty"]) else {
            return XCTFail("chutney_focus_app does not parse")
        }
        XCTAssertEqual(d.args, ["com.mitchellh.ghostty"])
    }
}
