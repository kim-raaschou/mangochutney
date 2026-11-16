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
    func testOnlyCurrentTakesAGlobalClientAndNotTheSpecialTag() {
        let r = EngineRig()
        let a = r.window(1), g = r.window(2, tags: 1 << 1), off = r.window(3, tags: 1 << 2)
        let s = r.window(4, tags: TAG0_MASK)
        g.isglobal = true
        r.server.arrange(r.monitor, false, false)
        d(r, "toggleoverview", ["1"])
        XCTAssertTrue(r.monitor.isoverview)
        XCTAssertNotNil(a.overviewBackupGeom)
        XCTAssertNotNil(g.overviewBackupGeom, "isglobal")
        XCTAssertNil(off.overviewBackupGeom, "not on the current tags")
        XCTAssertNil(s.overviewBackupGeom, "TAG0_MASK")
    }

    // fix_mon_tagset_from_overview runs on entering too
    func testEnteringKeepsThePreviousTagForTheWayBack() {
        let r = EngineRig()
        r.window(1)
        r.window(2, tags: 1 << 1)
        r.server.clientViewOnMonitor(1 << 1, on: r.monitor)
        r.server.clientViewOnMonitor(1, on: r.monitor)
        d(r, "toggleoverview")
        let m = r.monitor
        XCTAssertEqual(m.tagset[m.seltags], TagMask.mask(forTagNum: r.server.config.tagNum))
        XCTAssertEqual(m.tagset[m.seltags ^ 1], 1 << 1, "ovbk_prev_tagset")
        XCTAssertEqual(m.pertag.prevtag, 2)
    }

    func testLeavingGoesToTheChosenClientsTag() {
        let r = EngineRig()
        r.window(1)
        let b = r.window(2, tags: 1 << 2)
        r.server.arrange(r.monitor, false, false)
        d(r, "toggleoverview")
        r.server.toggleOverview(tc: b)
        XCTAssertFalse(r.monitor.isoverview)
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 1 << 2)
        XCTAssertTrue(r.server.focused === b)
    }

    // arg->tc: mmsg's client,<id>
    func testTheDispatchersTakeTheTargetClient() {
        let r = EngineRig()
        r.window(1)
        let b = r.window(2, tags: 1 << 2)
        r.server.arrange(r.monitor, false, false)
        d(r, "toggleoverview")
        _ = r.server.dispatch(Dispatch(name: "leaveoverview"), target: b)
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 1 << 2)
        XCTAssertTrue(r.server.focused === b)
    }

    // a mango bug, docs/afvigelser.md §6: mango gives it overview_backup's zero state
    func testAClientMappedInTheOverviewKeepsItsState() {
        let r = EngineRig()
        r.window(1)
        r.server.arrange(r.monitor, false, false)
        d(r, "toggleoverview")
        let dialog = r.window(2, floating: true, frame: CGRect(x: 300, y: 300, width: 400, height: 300))
        r.server.arrange(r.monitor, false, false)
        d(r, "toggleoverview")
        XCTAssertTrue(dialog.isfloating)
        XCTAssertEqual(dialog.floatGeom.size, CGSize(width: 400, height: 300))
    }

    // overview_scale reads the clients at each arrange
    func testTheCardsFollowTheClients() {
        let r = EngineRig()
        let a = r.map(1), b = r.map(2), c = r.map(3)
        d(r, "toggleoverview")
        XCTAssertEqual(Set(r.monitor.ovCards.keys), [a.id, b.id, c.id])
        r.server.mac.windowDestroyed(id: c.id)
        XCTAssertEqual(Set(r.monitor.ovCards.keys), [a.id, b.id], "no hole for a closed window")
        let n = r.map(4)
        XCTAssertNotNil(r.monitor.ovCards[n.id], "a new window gets a card")
    }

    func testOvercircleGoesByTheStack() throws {
        let r = EngineRig()
        r.map(1)
        r.map(2)
        r.map(3)
        d(r, "overcircle", ["next"])
        XCTAssertTrue(r.server.isOvercircleMode(r.monitor))
        let sel = try XCTUnwrap(r.server.focused)
        let next = try XCTUnwrap(r.server.getNextStackClient(sel, reverse: false))
        d(r, "overcircle", ["next"])
        XCTAssertTrue(r.server.focused === next)
        XCTAssertTrue(r.monitor.isoverview)
    }

    func testOvercircleWithOneClientSetsTheTabLayoutAndStays() {
        let r = EngineRig()
        let a = r.map(1)
        d(r, "toggleoverview")
        XCTAssertFalse(r.monitor.ovTabLayout)
        d(r, "overcircle", ["next"])
        XCTAssertTrue(r.monitor.ovTabLayout, "set before get_next_stack_client finds none")
        XCTAssertTrue(r.monitor.isoverview)
        XCTAssertTrue(r.server.focused === a)
    }

    func testOvercircleInTheHotAreasOverviewLeaves() {
        let r = EngineRig()
        r.server.config.enableHotarea = true
        r.map(1)
        r.map(2)
        let f = r.monitor.screen.frame
        r.server.toggleHotarea(CGPoint(x: f.minX + 2, y: f.maxY - 2))
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
        r.server.toggleHotarea(CGPoint(x: f.minX + 2, y: f.maxY - 2))
        XCTAssertFalse(r.monitor.isoverview)
        XCTAssertFalse(r.monitor.ovNormalMode)
    }

    func testReleasingTheModeKeyLeavesOvercircleOnTheSelection() throws {
        let r = EngineRig()
        r.window(1)
        r.window(2, tags: 1 << 3)
        r.server.arrange(r.monitor, false, false)
        d(r, "overcircle", ["next"])
        let sel = try XCTUnwrap(r.server.focused)
        r.server.handleKeyboardKey([.leaveOvercircle])
        XCTAssertFalse(r.monitor.isoverview)
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], r.server.getTagsFirstTag(sel.tags))
    }

    func testEachMonitorHasItsOwnOverview() {
        let r = EngineRig()
        let side = twoMonitors(r)
        r.server.selectedMonitor = side
        r.map(1)
        d(r, "toggleoverview")
        r.server.selectedMonitor = r.monitor
        r.map(2)
        d(r, "toggleoverview")
        XCTAssertTrue(side.isoverview)
        XCTAssertTrue(r.monitor.isoverview, "toggle_overview acts on the selected monitor")
        d(r, "toggleoverview")
        XCTAssertFalse(r.monitor.isoverview)
        XCTAssertTrue(side.isoverview)
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
        XCTAssertEqual(Set(fake.overviewCards?.map(\.id) ?? []), [a.id, b.id])
        XCTAssertEqual(a.frame, before, "the window stays under its picture")
        r.server.clientFocus(b, true)
        XCTAssertEqual(fake.overviewCards?.first { $0.focused }?.id, b.id)
        d(r, "toggleoverview")
        XCTAssertNil(fake.overviewCards)
        XCTAssertFalse(r.monitor.ovThumbnails)
    }
}
