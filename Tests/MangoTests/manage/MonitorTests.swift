import XCTest
@testable import Mango
import MangoTestKit

/// mango's src/manage/monitor.c
@MainActor
final class MonitorTests: XCTestCase {

    // MARK: get_tags_first_tag

    func testTheFirstTag() {
        let mango = TestMango()

        mango.run("view", "3")

        XCTAssertEqual(mango.server.getTagsFirstTag(0), 1 << 2, "no tags: the current tag")
        XCTAssertEqual(mango.server.getTagsFirstTag(TAG0_MASK | 1 << 4), TAG0_MASK)
        XCTAssertEqual(mango.server.getTagsFirstTag(1 << 4 | 1 << 6), 1 << 4)
    }

    // MARK: get_tags_first_tag_num

    func testTheFirstTagNumWithTheSpecialTag() {
        let mango = TestMango()

        XCTAssertEqual(mango.server.getTagsFirstTagNum(TAG0_MASK | 1 << 3), 0)
        XCTAssertEqual(mango.server.getTagsFirstTagNum(1 << 3 | 1 << 5), 4)
        XCTAssertEqual(mango.server.getTagsFirstTagNum(0), 0)
    }

    // MARK: monitor_from_cycle

    /// mango reads the list head as a monitor on the wrap: a mango bug, docs/afvigelser.md §6.
    func testTheCycleWrapsAround() {
        let mango = TestMango()
        let first = mango.monitor
        let last = mango.addMonitorOnTheRight()

        mango.server.selectedMonitor = last
        XCTAssertTrue(mango.server.monitorFromCycle(MON_NEXT) === first)
        mango.server.selectedMonitor = first
        XCTAssertTrue(mango.server.monitorFromCycle(MON_PREV) === last)
    }

    // MARK: match_monitor_spec

    /// strtok(spec, "&&") splits at every "&", the key is exact and nothing is trimmed; make, model and
    /// serial are compared with the output's, and a missing one does not match.
    func testTheSpecIsMangos() {
        let benq = Screen(displayID: 2, name: "DP-1", frame: .zero, workArea: .zero, scale: 1, isMain: false,
                          make: "BNQ", model: "X", serial: "42")
        let bare = Screen(displayID: 1, name: "Built-in", frame: .zero, workArea: .zero, scale: 1, isMain: true)

        XCTAssertEqual(MonitorSpec(mango: "make:BNQ&&model:X"), MonitorSpec(make: "BNQ", model: "X"))
        XCTAssertEqual(MonitorSpec(mango: "make:BNQ&model:X"), MonitorSpec(make: "BNQ", model: "X"))
        XCTAssertEqual(MonitorSpec(mango: "make:BNQ && model:X"), MonitorSpec(make: "BNQ "), "\" model\" is no key")
        XCTAssertEqual(MonitorSpec(mango: "Name:DP"), MonitorSpec(), "keys are exact")
        XCTAssertEqual(MonitorSpec(mango: " DP-1"), MonitorSpec(name: " DP-1"), "no trim")

        XCTAssertTrue(MonitorSpec(mango: "make:BNQ&&model:X&&serial:42").matchMonitorSpec(benq))
        XCTAssertFalse(MonitorSpec(mango: "make:BNQ").matchMonitorSpec(bare), "no make: no match")
        XCTAssertFalse(MonitorSpec(mango: "make:BNQ && model:X").matchMonitorSpec(benq))
        XCTAssertTrue(MonitorSpec(mango: "Name:nothing").matchMonitorSpec(bare), "no known key: every monitor")
        XCTAssertTrue(MonitorSpec(mango: "").matchMonitorSpec(bare), "an empty spec is an empty regex")
        XCTAssertTrue(MonitorSpec(mango: "name:^DP").matchMonitorSpec(benq))
        XCTAssertFalse(MonitorSpec(mango: "name:^DP").matchMonitorSpec(bare))
    }

    // MARK: handle_output_destroy

    func testRemovingTheOverviewsOutputClosesTheOverview() {
        let mango = TestMango()
        let side = mango.addMonitorOnTheRight()
        mango.server.selectedMonitor = side
        let a = mango.map("a")
        a.tags = 1 << 2
        mango.server.toggleOverview(Arg())
        XCTAssertTrue(side.isoverview)

        mango.wlroots.screens.removeLast()
        mango.server.rebuildMonitors(screens: mango.wlroots.screens)

        XCTAssertFalse(mango.anyOverview)
        XCTAssertTrue(a.mon === mango.monitor)
        XCTAssertEqual(a.tags, 1 << 2)
    }
}
