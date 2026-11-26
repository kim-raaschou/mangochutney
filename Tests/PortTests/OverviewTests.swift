import XCTest
@testable import Mango
@testable import Port

/// mango's set_overview, toggle_overview, enter_overview, leave_overview and over_circle (dispatch/bind.c).
@MainActor
final class OverviewTests: MangoTestCase {
    private func d(_ r: EngineRig, _ name: String, _ args: [String] = []) {
        _ = r.server.dispatch(Dispatch(name: name, args: args))
    }

    private func twoMonitors(_ r: EngineRig) -> Monitor {
        let side = Screen(displayID: 2, name: "Side", frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
                          workArea: CGRect(x: 1728, y: 0, width: 1920, height: 1080), scale: 1, isMain: false)
        r.server.rebuildMonitors(screens: [r.screen, side])
        return r.server.monitors.first { $0.screen.name == "Side" }!
    }

    // overview_client_on_current_tags: a global client is on the current tags, the special tag is not

    // fix_mon_tagset_from_overview runs on entering too
    func testEnteringKeepsThePreviousTagForTheWayBack() {
        let r = EngineRig()
        r.window(1)
        r.window(2, tags: 1 << 1)
        r.server.clientViewOnMonitor(Arg(ui: 1 << 1), true, r.monitor, r.monitor === r.server.selectedMonitor)
        r.server.clientViewOnMonitor(Arg(ui: 1), true, r.monitor, r.monitor === r.server.selectedMonitor)
        d(r, "toggleoverview")
        let m = r.monitor
        XCTAssertEqual(m.tagset[m.seltags], r.server.tagmask)
        XCTAssertEqual(m.tagset[m.seltags ^ 1], 1 << 1, "ovbk_prev_tagset")
        XCTAssertEqual(m.pertag.prevtag, 2)
    }

    // arg->tc: mmsg's client,<id>

    // a mango bug, docs/afvigelser.md §6: mango gives it overview_backup's zero state
    func testAClientMappedInTheOverviewKeepsItsState() {
        let r = EngineRig()
        r.window(1)
        r.arrange()
        d(r, "toggleoverview")
        let dialog = r.window(2, floating: true, frame: CGRect(x: 300, y: 300, width: 400, height: 300))
        r.arrange()
        d(r, "toggleoverview")
        XCTAssertTrue(dialog.isfloating)
        XCTAssertEqual(dialog.floatGeom.size, CGSize(width: 400, height: 300))
    }

    // overview_scale reads the clients at each arrange

    func testOvercircleInTheHotAreasOverviewLeaves() {
        let r = EngineRig()
        r.server.config.enableHotarea = true
        r.map(1)
        r.map(2)
        let f = r.monitor.screen.frame
        r.server.hotarea(CGPoint(x: f.minX + 2, y: f.maxY - 2))
        XCTAssertTrue(r.monitor.isoverview)
        XCTAssertTrue(r.monitor.ovNormalMode, "the hot area's overview is the grid")
        XCTAssertFalse(r.server.isOvercircleMode(r.monitor))
        d(r, "overcircle", ["next"])
        XCTAssertFalse(r.monitor.isoverview)
        XCTAssertFalse(r.monitor.ovTabLayout)
        XCTAssertFalse(r.monitor.ovNormalMode)
    }

    // a mango bug, docs/afvigelser.md §6: mango leaves ov_normal_mode set when there is nothing to show
    func testTheHotAreaOnAnEmptyMonitorLeavesNoNormalMode() {
        let r = EngineRig()
        r.server.config.enableHotarea = true
        let f = r.monitor.screen.frame
        r.server.hotarea(CGPoint(x: f.minX + 2, y: f.maxY - 2))
        XCTAssertFalse(r.monitor.isoverview)
        XCTAssertFalse(r.monitor.ovNormalMode)
    }

    func testReleasingTheModeKeyLeavesOvercircleOnTheSelection() throws {
        let r = EngineRig()
        r.window(1)
        r.window(2, tags: 1 << 3)
        r.arrange()
        d(r, "overcircle", ["next"])
        let sel = try XCTUnwrap(r.server.focused)
        r.server.handleKeyboardKey([.leaveOvercircle])
        XCTAssertFalse(r.monitor.isoverview)
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], r.server.getTagsFirstTag(sel.tags))
    }

    // a mango bug, docs/afvigelser.md §6: mango toggles the selected monitor's overview
    func testRemovingAMonitorInOverviewLeavesTheSelectedOneAlone() {
        let r = EngineRig()
        let side = twoMonitors(r)
        r.server.selectedMonitor = side
        r.map(1)
        d(r, "toggleoverview")
        r.server.selectedMonitor = r.monitor
        r.map(2)
        r.server.rebuildMonitors(screens: [r.screen])
        XCTAssertFalse(r.server.anyOverview)
    }

    func testThePicturesAreTheCards() throws {
        let r = EngineRig()
        let fake = try XCTUnwrap(r.server.system as? FakeWindowSystem)
        fake.fakeCanCapture = true
        let a = r.map(1), b = r.map(2)
        let before = a.frame
        d(r, "toggleoverview")
        XCTAssertTrue(r.monitor.ovThumbnails)
        XCTAssertEqual(Set(fake.overviewCards?.map(\.id) ?? []), [a.windowID, b.windowID])
        XCTAssertEqual(a.frame, before, "the window stays under its picture")
        r.server.clientFocus(b, true)
        XCTAssertEqual(fake.overviewCards?.first { $0.focused }?.id, b.windowID)
        d(r, "toggleoverview")
        XCTAssertNil(fake.overviewCards)
        XCTAssertFalse(r.monitor.ovThumbnails)
    }
}
