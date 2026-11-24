import XCTest
@testable import Mango
import MangoTestKit

/// mango's src/manage/monitor.c
@MainActor
final class MonitorTests: XCTestCase {

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
