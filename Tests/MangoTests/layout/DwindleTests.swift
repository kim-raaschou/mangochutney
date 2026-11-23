import XCTest
@testable import Mango
import MangoTestKit

/// mango's src/layout/dwindle.c
@MainActor
final class DwindleTests: XCTestCase {

    // MARK: dwindle

    func testNewcomersSplitTheFocusedLeaf() {
        let area = CGRect(x: 0, y: 0, width: 2000, height: 1000)
        let mango = TestMango("""
            gap_inner_horizontal=0
            gap_inner_vertical=0
            gap_outer_horizontal=0
            gap_outer_vertical=0
            window_rule=is_open_silent:1,title:^[bc]$
            """, screen: Screen(displayID: 1, name: "DP-1", frame: area, workArea: area, scale: 1, isMain: true))
        mango.monitor.pertag.ltidxs[getMonCurtag(mango.monitor)] = .dwindle
        let a = mango.map("a", size: area.size)

        mango.map("b", size: area.size)
        mango.map("c", size: area.size)

        XCTAssertEqual(mango.geom("b").width, 1000)
        XCTAssertEqual(a.geom.width, 500)
    }
}
