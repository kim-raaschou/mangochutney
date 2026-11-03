import XCTest
@testable import Mango
@testable import Port

/// The menu bar item (port extension, not in mango): one copy on every display, so it shows
/// every monitor in the order the displays stand, the selected one in full.
final class MenuBarStatusTests: MangoTestCase {
    @MainActor
    func testEveryMonitorLeftToRightWithItsOwnTagsAndLayout() throws {
        let rig = EngineRig()
        let benq = Screen(displayID: 2, name: "BenQ", frame: CGRect(x: 1728, y: 0, width: 3360, height: 2240),
                          workArea: CGRect(x: 1728, y: 30, width: 3360, height: 2210), scale: 2, isMain: false)
        // The BenQ comes first in the system's list; the laptop stands to its left.
        rig.server.rebuildMonitors(screens: [benq, rig.screen])
        let laptop = try XCTUnwrap(rig.server.monitors.first { $0.screen.displayID == 1 })
        let ext = try XCTUnwrap(rig.server.monitors.first { $0.screen.displayID == 2 })
        rig.window(1, tags: 1 << 1).mon = laptop
        rig.window(2, tags: 1 << 3).mon = ext
        ext.tagset[ext.seltags] = 1 << 3
        laptop.tagset[laptop.seltags] = 1 << 1
        rig.server.selectedMonitor = ext

        let shown = MenuBarStatus.monitors(rig.server)
        XCTAssertEqual(shown.map(\.tags), [[MenuBarTag(number: 2, active: true)], [MenuBarTag(number: 4, active: true)]])
        XCTAssertEqual(shown.map(\.selected), [false, true])
        XCTAssertEqual(shown.map(\.layout), [laptop.layout, ext.layout])
    }

    @MainActor
    func testOneMonitorIsSelected() {
        let rig = EngineRig()
        XCTAssertEqual(MenuBarStatus.monitors(rig.server).map(\.selected), [true])
    }
}
