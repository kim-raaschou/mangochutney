import XCTest
@testable import Mango
@testable import Port

final class LaunchOrFocusTests: MangoTestCase {
    func testNoWindowsStartsTheApp() {
        XCTAssertEqual(LaunchOrFocusRule.decide(windows: [], current: 7, recent: [7]), .launch)
        XCTAssertEqual(LaunchOrFocusRule.decide(windows: [], current: nil, recent: []), .launch)
    }

    func testOneWindowIsFocused() {
        XCTAssertEqual(LaunchOrFocusRule.decide(windows: [1], current: 9, recent: [9]), .focus(1))
        XCTAssertEqual(LaunchOrFocusRule.decide(windows: [1], current: 1, recent: [1]), .focus(1))
    }

    func testFromAnotherAppTheWindowUsedLast() {
        XCTAssertEqual(LaunchOrFocusRule.decide(windows: [1, 2, 3], current: 9, recent: [9, 3, 1]), .focus(3))
        XCTAssertEqual(LaunchOrFocusRule.decide(windows: [1, 2], current: 9, recent: [9, 2]), .focus(2))
        XCTAssertEqual(LaunchOrFocusRule.decide(windows: [1, 2, 3], current: nil, recent: []), .focus(1))
    }

    func testTwoWindowsToggle() {
        XCTAssertEqual(LaunchOrFocusRule.decide(windows: [1, 2], current: 1, recent: [1, 2]), .focus(2))
        XCTAssertEqual(LaunchOrFocusRule.decide(windows: [1, 2], current: 2, recent: [2]), .focus(1))
    }

    func testThreeOrMoreGoToTheOneUsedBefore() {
        XCTAssertEqual(LaunchOrFocusRule.decide(windows: [1, 2, 3, 4], current: 1, recent: [1, 3, 2]), .focus(3))
        XCTAssertEqual(LaunchOrFocusRule.decide(windows: [1, 2, 3], current: 2, recent: [2]), .focus(3))
        XCTAssertEqual(LaunchOrFocusRule.decide(windows: [1, 2, 3], current: 3, recent: [3, 9]), .focus(1))
    }

    func testLaunchOrFocusIsAKnownPortExtension() {
        XCTAssertTrue(Dispatch.isKnown("chutney_launch_or_focus"))
        XCTAssertFalse(Dispatch.knownNames.contains("chutney_launch_or_focus"))
        guard case .success(let d) = BindingParser.parseFuncName(["chutney_launch_or_focus", "com.mitchellh.ghostty"]) else {
            return XCTFail("chutney_launch_or_focus does not parse")
        }
        XCTAssertEqual(d.args, ["com.mitchellh.ghostty"])
    }
}
