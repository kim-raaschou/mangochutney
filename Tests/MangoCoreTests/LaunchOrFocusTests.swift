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
        guard case .success(let d) = BindingParser.parseBindDispatch(["chutney_launch_or_focus", "com.mitchellh.ghostty"]) else {
            return XCTFail("chutney_launch_or_focus does not parse")
        }
        XCTAssertEqual(d.args, ["com.mitchellh.ghostty"])
    }

    func testThePictureShowsWhereTheKeysChoiceIsNotGiven() {
        XCTAssertFalse(LaunchOrFocusPicker.shows(windows: [], current: 9))
        XCTAssertFalse(LaunchOrFocusPicker.shows(windows: [1], current: 9))
        XCTAssertFalse(LaunchOrFocusPicker.shows(windows: [1, 2], current: 1), "two, in the app: the other one")
        XCTAssertTrue(LaunchOrFocusPicker.shows(windows: [1, 2], current: 9), "two, from another app")
        XCTAssertTrue(LaunchOrFocusPicker.shows(windows: [1, 2], current: nil))
        XCTAssertTrue(LaunchOrFocusPicker.shows(windows: [1, 2, 3], current: 1))
    }
}

@MainActor
final class LaunchOrFocusPickerTests: MangoTestCase {
    func testTheKeyAgainMovesAndReturnGoes() {
        let r = EngineRig()
        let a = r.window(1), b = r.window(2), c = r.window(3)
        r.arrange()
        r.server.clientActive(b)
        r.server.clientActive(a)
        let picker = LaunchOrFocusPicker.shared
        defer { picker.close(r.server) }
        r.server.launchOrFocus("test", command: "")
        XCTAssertTrue(picker.isOpen)
        XCTAssertEqual(picker.highlighted, b.id, "the key's own choice: the one used before")
        XCTAssertEqual(r.server.focused?.id, a.id, "nothing moves yet")
        r.server.launchOrFocus("test", command: "")
        XCTAssertEqual(picker.highlighted, c.id, "the key again: the next")
        picker.key(r.server, keyCode: 36, mods: [], opening: nil)
        XCTAssertFalse(picker.isOpen)
        XCTAssertEqual(r.server.focused?.id, c.id)
    }

    func testEscAndOtherKeysClose() {
        let r = EngineRig()
        let a = r.window(1)
        r.window(2); r.window(3)
        r.arrange()
        r.server.clientActive(a)
        let picker = LaunchOrFocusPicker.shared
        defer { picker.close(r.server) }
        r.server.launchOrFocus("test", command: "")
        picker.key(r.server, keyCode: 53, mods: [], opening: nil)
        XCTAssertFalse(picker.isOpen)
        XCTAssertEqual(r.server.focused?.id, a.id)
        r.server.launchOrFocus("test", command: "")
        picker.key(r.server, keyCode: 4, mods: [], opening: 0)
        XCTAssertFalse(picker.isOpen, "another key: closed, and it goes on to the app")
    }

    func testAClickGoesAsInMangosSwitcher() {
        let r = EngineRig()
        let a = r.window(1), b = r.window(2), c = r.window(3)
        r.arrange()
        r.server.clientActive(a)
        let picker = LaunchOrFocusPicker.shared
        defer { picker.close(r.server) }
        let fake = r.server.system as! FakeWindowSystem

        r.server.launchOrFocus("test", command: "")
        let tile = picker.tileFrames[c.id]!
        picker.click(r.server, at: CGPoint(x: tile.midX, y: tile.midY), button: 0)
        XCTAssertFalse(picker.isOpen)
        XCTAssertEqual(r.server.focused?.id, c.id, "the left button: the window clicked")

        r.server.launchOrFocus("test", command: "")
        picker.click(r.server, at: CGPoint(x: 1, y: 1), button: 0)
        XCTAssertFalse(picker.isOpen, "outside the windows: closed")
        XCTAssertEqual(r.server.focused?.id, c.id)

        r.server.launchOrFocus("test", command: "")
        let other = picker.tileFrames[b.id]!
        picker.click(r.server, at: CGPoint(x: other.midX, y: other.midY), button: 1)
        XCTAssertFalse(picker.isOpen)
        XCTAssertEqual(fake.closed, [b.id], "the right button: closes the window clicked")
        XCTAssertEqual(r.server.focused?.id, c.id)
    }

    func testTwoWindowsInTheAppStillToggle() {
        let r = EngineRig()
        let a = r.window(1), b = r.window(2)
        r.arrange()
        r.server.clientActive(a)
        r.server.launchOrFocus("test", command: "")
        XCTAssertFalse(LaunchOrFocusPicker.shared.isOpen)
        XCTAssertEqual(r.server.focused?.id, b.id)
    }
}
