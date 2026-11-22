import XCTest
@testable import Mango
import MangoTestKit

/// mango's src/dispatch/bind.c
@MainActor
final class BindTests: XCTestCase {

    // MARK: focusstack

    // MARK: focusdir

    func testFocusDirDownCrossesToTheNextTagWithFocusCrossTag() {
        let mango = TestMango("focus_cross_tag=1")
        mango.map("a")
        mango.map("b").tags = 1 << 1
        mango.server.arrange(mango.monitor, false, false)
        mango.server.clientFocus(mango.client("a"), true)

        mango.run("focusdir", "down")

        XCTAssertEqual(mango.viewedTags, 1 << 1)
    }

    // MARK: focusmon

    func testFocusingAnEmptyMonitorClearsThePointersFocus() {
        let mango = TestMango("warp_cursor=0")
        let side = mango.addMonitorOnTheRight()
        let a = mango.map("a")
        mango.wlroots.seatPointerNotifyEnter(a.id)

        mango.run("focusmon", "right")

        XCTAssertTrue(mango.monitor === side)
        // wlr_seat_pointer_notify_clear_focus: the next motion over a focuses it again
        XCTAssertNil(mango.wlroots.pointerFocusedSurface)
    }
}
