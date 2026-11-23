import XCTest
@testable import Mango
import MangoTestKit

/// mango's src/manage/client.c
@MainActor
final class ClientTests: XCTestCase {

    // MARK: handle_client_map

    func testANewClientIsFocused() {
        let mango = TestMango()
        mango.map("a")

        mango.map("b")

        XCTAssertEqual(mango.focused, "b")
        XCTAssertEqual(mango.focusStack, ["b", "a"])
    }

    // MARK: handle_client_unmap

    func testUnmappingAClientElsewhereFocusesTheTopOfTheSelectedMonitor() {
        let mango = TestMango()
        let main = mango.monitor
        let side = mango.addMonitorOnTheRight()
        mango.map("a")
        let b = mango.map("b")
        mango.server.clientSetMonitor(b, side, 0, focus: false)
        mango.server.setSelectedMonitor(main)
        main.sel = nil

        mango.unmap("b")

        // client_set_monitor(c, NULL, 0, true) ends in client_focus(client_focus_top(selmon))
        XCTAssertEqual(mango.focused, "a")
    }

    // MARK: client_focus_top

    func testTheTopIsTheLastFocusedEvenWithNoFocus() {
        let mango = TestMango()
        mango.map("a")
        mango.map("b").noFocus = true

        XCTAssertEqual(mango.server.clientFocusTop(mango.monitor)?.title, "b")
    }

    func testTheTopSkipsAnUnglobalClient() {
        let mango = TestMango()
        mango.map("a")
        mango.map("b").isunglobal = true

        XCTAssertEqual(mango.server.clientFocusTop(mango.monitor)?.title, "a")
    }

    // MARK: client_focus

    func testFocusingNoneKeepsAShownSelection() {
        let mango = TestMango()
        let a = mango.map("a")

        mango.server.clientFocus(nil, false)

        XCTAssertEqual(mango.monitor.sel, a.id)
    }

    // MARK: client_exchange

    func testAnExchangePutsTheOtherNextInTheFocusStack() {
        let mango = TestMango("new_is_master=0")
        let a = mango.map("a"), b = mango.map("b"), c = mango.map("c")
        mango.server.clientFocus(b, true); mango.server.clientFocus(c, true); mango.server.clientFocus(a, true)

        mango.server.clientExchange(a, b)

        XCTAssertEqual(mango.focusStack.prefix(2), ["a", "b"])
        XCTAssertEqual(mango.clients.prefix(2), ["b", "a"])
    }

    // MARK: client_switch_view

    func testATagSwitchScrollsTheFocusedClientIntoView() {
        let mango = TestMango()
        mango.monitor.pertag.ltidxs[getMonCurtag(mango.monitor)] = .scroller
        let a = mango.map("a"); mango.map("b"); mango.map("c")
        let d = mango.map("d")
        mango.server.clientFocus(d, true)
        mango.server.clientSwitchView(Arg(ui: 1 << 1), true)
        mango.server.clientFocus(mango.map("e"), true)
        mango.server.focusStack.removeAll { $0 == a.id }
        mango.server.focusStack.insert(a.id, at: 0)

        mango.server.clientSwitchView(Arg(ui: 1), true)

        XCTAssertEqual(mango.focused, "a")
        let g = a.geom, w = mango.monitor.screen.workArea
        XCTAssertTrue(g.minX >= w.minX && g.maxX <= w.maxX, "a in view: \(g) in \(w)")
    }

    // MARK: client_replace

    func testAReplaceCopiesTheShares() {
        let mango = TestMango()
        let a = mango.map("a"), b = mango.map("b")
        a.stackInnerPer = 0.7
        a.stackSizeWeight = 0.6
        a.scrollerStackProportion = 0.5
        a.overviewBackupGeom = CGRect(x: 1, y: 2, width: 3, height: 4)

        mango.server.clientReplace(b, a, isGroupChangeMember: true)

        XCTAssertEqual(b.stackInnerPer, 0.7)
        XCTAssertEqual(b.stackSizeWeight, 0.6)
        XCTAssertEqual(b.scrollerStackProportion, 0.5)
        XCTAssertEqual(b.overviewBackupGeom, CGRect(x: 1, y: 2, width: 3, height: 4))
    }

    // MARK: client_view_on_monitor

    func testViewCurrentToBackGoesToTheTagBefore() {
        let mango = TestMango("view_current_to_back=1")
        let m = mango.monitor
        mango.run("view", "2")
        mango.run("view", "3")

        mango.server.clientViewOnMonitor(Arg(ui: 1 << 2), true, m, true)

        XCTAssertEqual(m.tagset[m.seltags ^ 1], 1 << 2)
        mango.run("view", "3")
        XCTAssertEqual(mango.viewedTags, 1 << 1, "prevtag: tag 2")
    }

    // MARK: init_client_properties

    func testANewClientHasNoDropDirection() {
        let mango = TestMango()

        let a = mango.map("a")

        XCTAssertEqual(a.dropDirection, UNDIR)
    }

    // MARK: handle_client_map (more)

    func testAnUnfocusedNewClientGoesToTheEndOfTheFocusStack() {
        let mango = TestMango("window_rule=is_open_silent:1,title:^b$")
        mango.map("a")

        mango.map("b")

        XCTAssertEqual(mango.focusStack, ["a", "b"])
    }

    func testTheOverviewBackupIsTheGeomAtMap() {
        let mango = TestMango()

        let a = mango.map("a")

        // overview_backup_geom = geom
        XCTAssertGreaterThan(a.overviewBackupGeom.width, 0)
        XCTAssertFalse(a.overviewBackedUp)
    }

    func testADialogOpensOnItsParentsMonitor() {
        let mango = TestMango()
        let main = mango.monitor
        let side = mango.addMonitorOnTheRight()
        let a = mango.map("a")
        mango.server.clientSetMonitor(a, side, 0, focus: false)
        mango.server.clientFocus(a, true)
        mango.server.setSelectedMonitor(main)

        let d = mango.map("d", size: CGSize(width: 400, height: 300), dialog: true, parent: "a")

        // client_get_parent: the parent's monitor, not the selected one
        XCTAssertTrue(d.mon === side)
        XCTAssertTrue(d.isfloating)
    }

    // MARK: set_float_malposition

    func testNewFloatingClientsAreCentredAndMovedOffEachOther() {
        let mango = TestMango("window_rule=is_floating:1,title:^[ab]$")
        let w = mango.monitor.screen.workArea
        let a = mango.map("a", size: CGSize(width: 600, height: 400))

        let b = mango.map("b", size: CGSize(width: 600, height: 400))

        XCTAssertTrue(a.isfloating)
        XCTAssertEqual(a.floatGeom.midX, w.midX, accuracy: 1)
        XCTAssertEqual(a.floatGeom.midY, w.midY, accuracy: 1)
        let offset = min(w.width / 20, w.height / 20).rounded(.towardZero)
        XCTAssertEqual(b.floatGeom.minX, a.floatGeom.minX + offset, accuracy: 1, "moved off the first")
        XCTAssertEqual(b.geom.origin, b.floatGeom.origin, "geom moves with float_geom")
        XCTAssertEqual(b.pending.origin, b.floatGeom.origin, "and the client is put there")
    }

    // MARK: client_set_rules

    func testRuleFractionsAreOfTheWholeMonitor() {
        let mango = TestMango("window_rule=is_floating:1,width:0.5,height:0.5,title:^a$")

        let a = mango.map("a")

        XCTAssertEqual(a.floatGeom.width, (mango.monitor.screen.frame.width * 0.5).rounded())
        XCTAssertEqual(a.floatGeom.height, (mango.monitor.screen.frame.height * 0.5).rounded())
    }

    // MARK: client_set_floating

    func testAFloatingClientAsWideAsTheMonitorIsCutTo90Percent() {
        let mango = TestMango("window_rule=is_floating:1,title:^a$")
        let w = mango.monitor.screen.workArea

        let a = mango.map("a", size: CGSize(width: w.width, height: 500))

        XCTAssertEqual(a.floatGeom.width, (w.width * 0.9).rounded(.towardZero))
        XCTAssertEqual(a.floatGeom.midX, w.midX, accuracy: 1)
    }

    // MARK: handle_client_unmap (more)

    func testAnUnmapEndsTheGrab() {
        let mango = TestMango()
        let a = mango.map("a")
        mango.server.grabClient = a; mango.server.cursorMode = CurMove

        mango.unmap("a")

        XCTAssertNil(mango.server.grabClient)
        XCTAssertEqual(mango.server.cursorMode, CurNormal)
    }
}
