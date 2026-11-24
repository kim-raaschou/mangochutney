import XCTest
@testable import Mango
import MangoTestKit

/// mango's src/input/pointer.c
@MainActor
final class PointerTests: XCTestCase {

    // MARK: pointer_check_confine_client

    func testConfinePointerKeepsThePointerInside() {
        let mango = TestMango("window_rule=confine_pointer:1,title:^a$")

        let a = mango.map("a")

        XCTAssertTrue(a.confinePointer)
        let box = a.geom
        XCTAssertEqual(mango.wlroots.warps.last, CGPoint(x: box.midX, y: box.midY), "to the middle of its box")
        let p = mango.wlroots.pointer
        mango.move(by: CGVector(dx: box.maxX + 50 - p.x, dy: box.midY - p.y))
        XCTAssertEqual(mango.wlroots.warps.last, CGPoint(x: box.maxX - a.bw - 6, y: box.midY), "CONFINE_POINTER_MARGIN inside the border")
    }

    // MARK: group_bar_target_at

    /// It goes through node_at_point: a client in the bar's layer or above hides the bar.
    func testAFloatingClientOverAGroupBarHidesIt() {
        let mango = TestMango("window_rule=is_floating:1,title:^f$")
        mango.server.config.alwaysShowGroupBar = true
        let a = mango.map("a")
        mango.map("b")
        mango.frame()
        let af = (a.platform as! FakeSurface).frame
        let bar = CGPoint(x: af.midX, y: af.minY - CGFloat(mango.server.config.groupBarHeight) / 2)
        XCTAssertTrue(mango.server.groupBarTargetAt(bar.x, bar.y, nil) === a)
        let box = CGRect(x: bar.x - 50, y: bar.y - 50, width: 100, height: 100)

        let f = mango.map("f", size: box.size)
        (f.platform as! FakeSurface).frame = box

        XCTAssertNil(mango.server.groupBarTargetAt(bar.x, bar.y, nil), "the floating client lies over the bar")
        XCTAssertTrue(mango.server.groupBarTargetAt(bar.x, bar.y, f) === a, "the dragged client does not hide it")
    }
}
