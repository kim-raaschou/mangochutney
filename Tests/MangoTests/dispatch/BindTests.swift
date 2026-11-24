import XCTest
@testable import Mango
import MangoTestKit

/// mango's src/dispatch/bind.c
@MainActor
final class BindTests: XCTestCase {

    // MARK: client_group_join

    func testAJoinParksOneAndADetachLeavesTheFocusToTheCallers() {
        let mango = TestMango()
        let side = mango.addMonitorOnTheRight()
        let a = mango.map("a")
        a.isfloating = true
        a.floatGeom = CGRect(x: 10, y: 50, width: 300, height: 200)
        let b = mango.map("b")
        b.mon = side
        b.tags = side.tagset[side.seltags]

        mango.server.clientGroupJoin(a, b)

        XCTAssertTrue([a, b].first { !mango.server.clientIsParked($0) }!.mon === side)
        XCTAssertNil([a, b].first { mango.server.clientIsParked($0) }!.mon, "client_park: no monitor")
        let focus = [a, b].first { $0.isGroupFocus }!
        let other = focus === a ? b : a
        mango.server.clientGroupDetach(other)
        XCTAssertTrue(focus.isGroupFocus, "left to the callers")
    }

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

    func testMonocleInTheOverviewGoesByTheCards() throws {
        let mango = TestMango()
        mango.monitor.pertag.ltidxs[getMonCurtag(mango.monitor)] = .monocle
        for title in ["a", "b", "c", "d"] { mango.map(title) }
        mango.run("toggleoverview")
        let cards = mango.monitor.ovCards
        let top = cards.values.map(\.minY).min()!
        let start = try XCTUnwrap(cards.filter { $0.value.minY == top }.max { $0.value.minX < $1.value.minX })
        mango.server.clientFocus(mango.server.clientByIdAll(start.key)!, true)

        mango.run("focusdir", "right")

        XCTAssertEqual(mango.monitor.sel?.id, start.key, "no card to the right of the top row's last")
        mango.run("focusdir", "left")
        let to = try XCTUnwrap(mango.monitor.sel.flatMap { cards[$0.id] })
        XCTAssertLessThan(to.midX, start.value.midX, "a card to the left")
        XCTAssertEqual(to.minY, top, "in the same row")
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

    // MARK: tagmon

    func testTagmonOnItsOwnMonitorViewsItsTags() {
        let mango = TestMango()
        let a = mango.map("a")
        a.tags = 1 << 1

        mango.run("tagmon", ["next", "1"], on: a)

        XCTAssertEqual(mango.viewedTags, 1, "one monitor: next is none, as mango's monitor_from_cycle")
        mango.run("tagmon", ["DP-1", "1"], on: a)
        XCTAssertEqual(mango.viewedTags, 1 << 1)
    }

    // MARK: setmfact

    func testTheMasterShareIsTheFirstClientsAndSetmfactSetsItInView() {
        let mango = TestMango()
        let a = mango.map("a"), b = mango.map("b")
        mango.server.clients.first!.masterMfactPer = 0.7
        mango.server.arrange(mango.monitor, false, false)
        let w = mango.monitor.screen.workArea.width
        XCTAssertGreaterThan(mango.server.clients.first!.geom.width, w * 0.6, "the first client's 0.7, not the tag's 0.55")

        mango.run("setmfact", "1.4")

        XCTAssertEqual(a.masterMfactPer, 0.4, accuracy: 0.001)
        XCTAssertEqual(b.masterMfactPer, 0.4, accuracy: 0.001)
        let c = mango.map("c")
        XCTAssertEqual(c.masterMfactPer, 0.4, accuracy: 0.001, "set_size_per: the share in view")
    }

    // MARK: minimized, restore_minimized

    func testTheMinimizedGoFirstInTheClientListAndComeBackLastInFirstOut() {
        let mango = TestMango()
        let a = mango.map("a"); mango.map("b")
        let c = mango.map("c")

        mango.run("minimized", on: c)
        mango.run("minimized", on: a)

        XCTAssertEqual(mango.clients.first, "a")
        XCTAssertEqual(a.tags, 0)
        XCTAssertEqual(a.oldtags, 1)
        mango.run("restore_minimized")
        XCTAssertFalse(a.isminimized, "the last minimized")
        XCTAssertTrue(c.isminimized)
    }

    // MARK: movewin, resizewin

    func testMovewinAndResizewinAbsolute() {
        let mango = TestMango()
        let a = mango.map("a")

        mango.run("movewin", ["100", "120"], on: a)
        mango.run("resizewin", ["40", "40"], on: a)

        XCTAssertEqual(a.floatGeom.origin, CGPoint(x: 100, y: 120))
        XCTAssertEqual(a.floatGeom.size, CGSize(width: 40, height: 40))
    }

    func testResizewinKeepsTheAnimationSetting() {
        let mango = TestMango("animations=1")
        let a = mango.map("a")
        mango.map("b")

        mango.run("resizewin", ["+50", "0"], on: a)

        XCTAssertTrue(mango.server.config.animations)
    }

    // MARK: spawn_on_empty

    func testSpawnOnEmptyTakesTheCommandThenTheTags() {
        let mango = TestMango()
        mango.map("a")

        mango.run("spawn_on_empty", "foot -e x", "3")

        XCTAssertEqual(mango.wlroots.spawned, ["foot -e x"])
        XCTAssertEqual(mango.viewedTags, 1 << 2)
    }

    // MARK: toggle_named_scratchpad

    func testTheNamedScratchpadLooksOnTheSelectedMonitorOnly() {
        let mango = TestMango()
        let main = mango.monitor
        mango.server.selectedMonitor = mango.addMonitorOnTheRight()
        let a = mango.map("a")
        mango.server.selectedMonitor = main

        mango.run("toggle_named_scratchpad", "a", "none", "foot")

        XCTAssertFalse(a.isnamedscratchpad)
        XCTAssertEqual(mango.wlroots.spawned, ["foot"])
    }

    // MARK: toggle_special_tag

    func testTheSpecialTagIsAViewOfItsOwn() {
        let mango = TestMango()
        let a = mango.map("a")

        mango.run("toggle_special_tag")

        XCTAssertEqual(mango.viewedTags, TAG0_MASK, "the special tag alone")
        XCTAssertTrue(a.platform.sceneNodeEnabled, "the client of the tag before stays")
        let s = mango.map("s")
        XCTAssertEqual(s.tags, TAG0_MASK, "a new client opens on the special tag")
        mango.unmap("s")
        XCTAssertEqual(mango.viewedTags, 1, "the last special client gone: back to tag 1")
        mango.run("toggle_special_tag")
        mango.run("toggle_special_tag")
        XCTAssertEqual(mango.viewedTags, 1, "toggled back to the tags before")
    }

    // MARK: view_insert

    func testViewInsertShiftsTheTags() {
        let mango = TestMango()
        let a = mango.map("a")
        let b = mango.map("b")
        b.tags = 1 << 1
        mango.monitor.pertag.nmasters[2] = 3

        mango.run("view_insert", "next")

        XCTAssertEqual(a.tags, 1)
        XCTAssertEqual(b.tags, 1 << 2, "tag 2 moved to 3")
        XCTAssertEqual(mango.monitor.pertag.nmasters[3], 3, "with its state")
        XCTAssertEqual(mango.viewedTags, 1 << 1)
    }

    // MARK: setoption

    func testSetoptionReappliesAsMango() {
        let mango = TestMango()
        mango.map("a")
        mango.server.config.exec = ["foo"]
        mango.monitor.pertag.nmasters[getMonCurtag(mango.monitor)] = 3

        mango.run("setoption", "gap_outer_horizontal", "24")

        XCTAssertEqual(mango.monitor.gappoh, 24)
        XCTAssertEqual(Int(mango.monitor.pertag.nmasters[getMonCurtag(mango.monitor)]), mango.server.config.defaultNmaster)
        XCTAssertEqual(mango.wlroots.spawned, ["foo"])
    }

    // MARK: toggleoverview

    func testTheOverviewViewsEveryTagAndLeavesOnTheSelectedClientsTag() {
        let mango = TestMango()
        let a = mango.map("a")
        let b = mango.map("b")
        b.tags = 1 << 1
        mango.server.clientFocus(a, true)
        mango.monitor.tagset[mango.monitor.seltags] = 1

        mango.run("toggleoverview")

        XCTAssertEqual(mango.viewedTags, 0x1FF)
        _ = mango.server.dispatch(Dispatch(name: "view", args: ["3"]), rescan: false)
        XCTAssertTrue(mango.anyOverview, "a tag view is refused in overview")
        XCTAssertEqual(mango.viewedTags, 0x1FF)
        mango.run("focusstack", "next")
        XCTAssertEqual(mango.focused, "b", "a card on another tag is reached")
        mango.run("toggleoverview")
        XCTAssertFalse(mango.anyOverview)
        XCTAssertEqual(mango.viewedTags, 1 << 1, "b's first tag")
        XCTAssertEqual(mango.monitor.tagset[mango.monitor.seltags ^ 1], 1, "the tags from before")
        XCTAssertEqual(mango.focused, "b")
    }

    func testTheOverviewClearsAndRestoresTheStates() {
        let mango = TestMango()
        let a = mango.map("a"), b = mango.map("b"), c = mango.map("c")
        a.isfloating = true
        b.isfullscreen = true
        c.ismaximizescreen = true

        mango.run("toggleoverview")

        XCTAssertEqual([a.isfloating, b.isfullscreen, c.ismaximizescreen], [false, false, false])
        var moved = false
        for d in ["left", "right", "up", "down"] {
            mango.server.clientFocus(b, true)
            mango.run("focusdir", d)
            if mango.monitor.sel !== b { moved = true }
        }
        XCTAssertTrue(moved, "the fullscreen client's card is no stop")
        mango.server.clientFocus(b, true)
        mango.run("toggleoverview")
        XCTAssertEqual([a.isfloating, b.isfullscreen, c.ismaximizescreen], [true, true, false],
                       "want_restore_fullscreen: c shares its tag with b, the selection")
    }

    func testNoOverviewWhileGrabbed() {
        let mango = TestMango()
        let a = mango.map("a")
        mango.server.grabClient = a; mango.server.cursorMode = CurMove

        for name in ["toggleoverview", "enteroverview", "togglejump"] { mango.run(name) }

        XCTAssertFalse(mango.anyOverview)
        XCTAssertFalse(mango.monitor.isJumpMode, "a mango bug, docs/afvigelser.md §6: no jump mode left on")
        mango.server.grabClient = nil; mango.server.cursorMode = CurNormal
        mango.run("toggleoverview")
        XCTAssertTrue(mango.anyOverview)
        mango.server.grabClient = a; mango.server.cursorMode = CurMove
        mango.run("leaveoverview")
        XCTAssertTrue(mango.anyOverview, "leave_overview: nothing while grabbed")
    }
}
