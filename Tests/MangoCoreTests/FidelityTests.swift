import XCTest
@testable import Mango
@testable import Port

@MainActor
final class FidelityTests: MangoTestCase {

    func testFocusTopIsTheFocusStack() {
        let r = EngineRig()
        let a = r.window(1), b = r.window(2)
        b.noFocus = true
        XCTAssertTrue(r.server.clientFocusTop(r.monitor) === b, "no_focus is not skipped")
        b.isunglobal = true
        XCTAssertTrue(r.server.clientFocusTop(r.monitor) === a, "isunglobal is")
        r.server.focusStack = []
        XCTAssertNil(r.server.clientFocusTop(r.monitor), "nothing in the focus stack: none")
    }

    var fake: (EngineRig) -> FakeWindowSystem { { $0.server.system as! FakeWindowSystem } }

    func testExchangePutsTheOtherNextInTheFocusStack() {
        let r = EngineRig()
        let a = r.window(1), b = r.window(2), c = r.window(3)
        r.arrange()
        r.server.clientFocus(b, true); r.server.clientFocus(c, true); r.server.clientFocus(a, true)
        r.server.clientExchange(a, b)
        XCTAssertEqual(Array(r.server.focusStack.prefix(2)), [a.id, b.id])
        XCTAssertEqual(r.server.clients.map(\.id).prefix(2), [2, 1])
    }

    func testATagSwitchScrollsTheFocusedWindowIntoView() {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .scroller
        let a = r.map(1), _ = r.map(2), _ = r.map(3), d = r.map(4)
        r.server.clientFocus(d, true)
        r.server.clientSwitchView(Arg(ui: 1 << 1), true)
        r.server.clientFocus(r.map(5), true)
        r.server.focusStack.removeAll { $0 == a.id }
        r.server.focusStack.insert(a.id, at: 0)
        r.server.clientSwitchView(Arg(ui: 1), true)
        XCTAssertTrue(r.server.focused === a)
        let g = a.geom ?? .zero, w = r.monitor.screen.workArea
        XCTAssertTrue(g.minX >= w.minX && g.maxX <= w.maxX, "a in view: \(g) in \(w)")
    }

    func testTabMembersAndChainFocus() {
        let r = EngineRig()
        r.server.config.monocleTabMode = true
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .monocle
        let a = r.window(1), b = r.window(2), c = r.window(3, floating: true)
        r.arrange()
        a.isfullscreen = true
        r.arrange()
        XCTAssertTrue(r.server.tabChain(r.monitor).contains { $0 === a }, "fullscreen: a member")
        r.server.clientFocus(b, true)
        XCTAssertTrue(r.server.tabFocus(r.monitor) === b)
        r.server.clientFocus(c, true)
        XCTAssertTrue(r.server.tabFocus(r.monitor) === b, "the one shown last")
    }

    func testGestureFiresEveryMatch() {
        let r = EngineRig()
        let parsed = ConfigParser.parse(text: """
        gesturebind=none,left,3,setlayout,monocle
        gesturebind=none,alldir,3,togglegaps
        gesturebind=none,left,3,moveresize,curmove
        """, baseDirectory: nil, fileName: "test")
        r.server.config.gestureBindings = parsed.config.gestureBindings
        XCTAssertEqual(r.server.config.gestureBindings.count, 3)
        let gaps = r.server.enableGaps
        XCTAssertTrue(r.server.fireGestureMotion(SWIPE_LEFT, 3))
        XCTAssertEqual(r.monitor.layout, .monocle)
        XCTAssertNotEqual(r.server.enableGaps, gaps, "alldir fired too")
    }

    func testGroupJoinAndDetach() {
        let r = EngineRig()
        let right = Screen(displayID: 2, name: "Right", frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
                           workArea: CGRect(x: 1728, y: 25, width: 1920, height: 1055), scale: 1, isMain: false)
        r.server.rebuildMonitors(screens: [r.screen, right])
        let a = r.window(1, floating: true)
        a.floatGeom = CGRect(x: 10, y: 50, width: 300, height: 200)
        let b = r.window(2)
        let right2 = r.server.monitors.first { $0.screen.displayID == 2 }!
        b.mon = right2
        b.tags = right2.tagset[right2.seltags]
        r.server.clientGroupJoin(a, b)
        XCTAssertTrue([a, b].first { !$0.groupParked }!.mon === right2)
        XCTAssertNil([a, b].first { $0.groupParked }!.mon, "client_park: no monitor")
        let focus = [a, b].first { $0.isGroupFocus }!
        let other = focus === a ? b : a
        r.server.clientGroupDetach(other)
        XCTAssertTrue(focus.isGroupFocus, "left to the callers")
    }

    func testClientReplaceCopiesShares() {
        let r = EngineRig()
        let a = r.window(1), b = r.window(2)
        a.stackInnerPer = 0.7
        a.stackSizeWeight = 0.6
        a.scrollerStackProportion = 0.5
        a.overviewBackupGeom = CGRect(x: 1, y: 2, width: 3, height: 4)
        r.server.clientReplace(b, a, isGroupChangeMember: true)
        XCTAssertEqual(b.stackInnerPer, 0.7)
        XCTAssertEqual(b.stackSizeWeight, 0.6)
        XCTAssertEqual(b.scrollerStackProportion, 0.5)
        XCTAssertEqual(b.overviewBackupGeom, CGRect(x: 1, y: 2, width: 3, height: 4))
    }

    func testViewCurrentToBackGoesToPrevtag() {
        let r = EngineRig()
        r.server.config.viewCurrentToBack = true
        let m = r.monitor
        _ = r.server.dispatch(Dispatch(name: "view", args: ["2"]))
        _ = r.server.dispatch(Dispatch(name: "view", args: ["3"]))
        r.server.clientViewOnMonitor(Arg(ui: 1 << 2), true, m, m === r.server.selectedMonitor)
        XCTAssertEqual(m.tagset[m.seltags ^ 1], 1 << 2)
        _ = r.server.dispatch(Dispatch(name: "view", args: ["3"]))
        XCTAssertEqual(m.tagset[m.seltags], 1 << 1, "prevtag: tag 2")
    }

    func testGetTagsFirstTag() {
        let r = EngineRig()
        _ = r.server.dispatch(Dispatch(name: "view", args: ["3"]))
        XCTAssertEqual(r.server.getTagsFirstTag(0), 1 << 2, "no tags: the current tag")
        XCTAssertEqual(r.server.getTagsFirstTag(TAG0_MASK | 1 << 4), TAG0_MASK)
        XCTAssertEqual(r.server.getTagsFirstTag(1 << 4 | 1 << 6), 1 << 4)
    }

    func testTagRuleFlagsSurviveAReload() {
        let r = EngineRig()
        let with = ConfigParser.parse(text: "tag_rule=id:2,open_as_floating:1", baseDirectory: nil, fileName: "t").config
        r.server.config = with
        r.server.parseTagrule(r.monitor)
        XCTAssertTrue(r.monitor.pertag.openAsFloating[2])
        let without = ConfigParser.parse(text: "", baseDirectory: nil, fileName: "t").config
        r.server.config = without
        r.server.parseTagrule(r.monitor)
        XCTAssertTrue(r.monitor.pertag.openAsFloating[2], "as mango: left as it was")
    }

    func testMasterMfactPer() {
        let r = EngineRig()
        let a = r.map(1), b = r.map(2)
        let first = r.server.clients.first!
        first.masterMfactPer = 0.7
        r.arrange()
        let w = r.monitor.screen.workArea.width
        let master = r.server.clients.first!.geom.width
        XCTAssertGreaterThan(master, w * 0.6, "the first window's 0.7, not the tag's 0.55")
        _ = r.server.dispatch(Dispatch(name: "setmfact", args: ["1.4"]))
        XCTAssertEqual(a.masterMfactPer, 0.4, accuracy: 0.001)
        XCTAssertEqual(b.masterMfactPer, 0.4, accuracy: 0.001)
        let c = r.map(3)
        XCTAssertEqual(c.masterMfactPer, 0.4, accuracy: 0.001, "set_size_per: the share in view")
    }

    func testGridShares() {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .grid
        for id in 1...4 { r.map(CGWindowID(id)) }
        r.arrange()
        let first = r.server.clients[0], second = r.server.clients[1]
        let before = first.geom.width
        r.server.resizeTileClient(first, offsetX: 200, offsetY: 0)
        XCTAssertGreaterThan(first.gridColPer, 1)
        XCTAssertLessThan(second.gridColPer, 1)
        XCTAssertGreaterThan(first.geom.width, before + 100)
        r.arrange()
        XCTAssertGreaterThan(first.geom.width, before + 100, "kept on the windows")
    }

    /// resize_tile_client: keyboard repeats and pointer motion are coalesced to once per output frame.
    func testATiledResizeIsTakenOncePerFrame() throws {
        let r = EngineRig()
        let a = r.map(1)
        r.map(2)
        r.arrange()
        let width = { try XCTUnwrap(a.geom).width }
        let before = try width()
        r.nextFrame()
        r.server.resizeTileClient(a, offsetX: 50, offsetY: 0)
        let once = try width()
        XCTAssertNotEqual(once, before)
        r.server.resizeTileClient(a, offsetX: 50, offsetY: 0)
        XCTAssertEqual(try width(), once, "the same frame: dropped")
        r.nextFrame()
        r.server.resizeTileClient(a, offsetX: 50, offsetY: 0)
        XCTAssertNotEqual(try width(), once, "the next frame: taken")
    }

    func testAGridDragMovesTheEdgeItGrabs() throws {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .grid
        for id in 1...6 { r.map(CGWindowID(id)) }
        r.arrange()
        let tiled = r.server.tiledClients(r.monitor)
        XCTAssertEqual(Set(tiled.map(\.gridColIdx)), [0, 1, 2], "three columns")
        let middle = try XCTUnwrap(tiled.first { $0.gridColIdx == 1 })
        let left = tiled.filter { $0.gridColIdx == 0 }, right = tiled.filter { $0.gridColIdx == 2 }
        let g = try XCTUnwrap(middle.geom)
        let grab = CGPoint(x: g.minX + 5, y: g.midY)
        r.server.resizeTileClient(middle, isdrag: true, offsetX: 0, offsetY: 0, cursor: grab)
        r.nextFrame()
        r.server.resizeTileClient(middle, isdrag: true, offsetX: 0, offsetY: 0, cursor: CGPoint(x: grab.x - 80, y: grab.y))
        XCTAssertGreaterThan(middle.gridColPer, 1, "the middle column grows to the left")
        XCTAssertTrue(left.allSatisfy { $0.gridColPer < 1 }, "the left column gives the room")
        XCTAssertTrue(right.allSatisfy { $0.gridColPer == 1 }, "the right column is not touched")
    }

    func testSpecialTagIsAViewOfItsOwn() {
        let r = EngineRig()
        let m = r.monitor
        let a = r.map(1)
        _ = r.server.dispatch(Dispatch(name: "toggle_special_tag"))
        XCTAssertEqual(m.tagset[m.seltags], TAG0_MASK, "the special tag alone")
        XCTAssertFalse(a.parked, "the window of the tag before stays")
        let s = r.map(2)
        XCTAssertEqual(s.tags, TAG0_MASK, "a new window opens on the special tag")
        r.server.mac.windowDestroyed(id: s.id)
        XCTAssertEqual(m.tagset[m.seltags], 1, "the last special window gone: back to tag 1")
        _ = r.server.dispatch(Dispatch(name: "toggle_special_tag"))
        _ = r.server.dispatch(Dispatch(name: "toggle_special_tag"))
        XCTAssertEqual(m.tagset[m.seltags], 1, "toggled back to the tags before")
    }

    func testFirstTagNumWithTheSpecialTag() {
        XCTAssertEqual(EngineRig().server.getTagsFirstTagNum(TAG0_MASK | 1 << 3), 0)
        XCTAssertEqual(EngineRig().server.getTagsFirstTagNum(1 << 3 | 1 << 5), 4)
        XCTAssertEqual(EngineRig().server.getTagsFirstTagNum(0), 0)
    }

    func testNewFloatingWindowsAreCentred() {
        let r = EngineRig()
        r.server.config.windowRules = ConfigParser.parse(text: "window_rule=is_floating:1,app_id:^test$",
                                                         baseDirectory: nil, fileName: "t").config.windowRules
        let w = r.monitor.screen.workArea
        let a = r.map(1, frame: CGRect(x: 10, y: 40, width: 600, height: 400))
        XCTAssertTrue(a.isfloating)
        XCTAssertEqual(a.floatGeom.midX, w.midX, accuracy: 1)
        XCTAssertEqual(a.floatGeom.midY, w.midY, accuracy: 1)
        let b = r.map(2, frame: CGRect(x: 10, y: 40, width: 600, height: 400))
        let offset = min(w.width / 20, w.height / 20).rounded(.towardZero)
        XCTAssertEqual(b.floatGeom.minX, a.floatGeom.minX + offset, accuracy: 1, "moved off the first")
        XCTAssertEqual(b.geom.origin, b.floatGeom.origin, "set_float_malposition moves geom with float_geom")
        XCTAssertEqual(b.pending.origin, b.floatGeom.origin, "and the window is put there")
    }

    func testANewWindowHasNoDropDirection() {
        let r = EngineRig()
        XCTAssertEqual(r.map(1).dropDirection, UNDIR, "init_client_properties: UNDIR")
    }

    func testClosingAWindowElsewhereFocusesTheSelectedMonitorsTop() {
        let r = EngineRig()
        let side = twoMonitors(r)
        let a = r.map(1)
        let b = r.map(2)
        r.server.clientSetMonitor(b, side, 0, focus: false)
        r.server.setSelectedMonitor(r.monitor)
        r.monitor.sel = nil
        r.server.handleClientUnmap(b)
        XCTAssertEqual(r.monitor.sel, a.id, "client_set_monitor(c, NULL, 0, true) ends in client_focus(client_focus_top(selmon))")
    }

    private func rules(_ r: EngineRig, _ text: String) {
        r.server.config.windowRules = ConfigParser.parse(text: text, baseDirectory: nil, fileName: "t").config.windowRules
    }

    func testAnUnfocusedNewWindowGoesToTheEndOfTheFocusStack() {
        let r = EngineRig()
        rules(r, "window_rule=is_open_silent:1,title:^t2$")
        let a = r.map(1)
        let b = r.map(2)
        XCTAssertEqual(r.server.focusStack.first, a.id)
        XCTAssertEqual(r.server.focusStack.last, b.id)
    }

    func testRuleFractionsAreOfTheWholeMonitor() {
        let r = EngineRig()
        rules(r, "window_rule=is_floating:1,width:0.5,height:0.5,app_id:^test$")
        let c = r.map(1)
        XCTAssertEqual(c.floatGeom.width, (r.screen.frame.width * 0.5).rounded())
        XCTAssertEqual(c.floatGeom.height, (r.screen.frame.height * 0.5).rounded())
    }

    private func d(_ r: EngineRig, _ name: String, _ args: [String] = [], _ c: Client? = nil) {
        _ = r.server.dispatch(Dispatch(name: name, args: args), target: c)
    }

    func testAFloatingWindowAsWideAsTheScreenIsCutTo90Percent() {
        let r = EngineRig()
        rules(r, "window_rule=is_floating:1,app_id:^test$")
        let w = r.monitor.screen.workArea
        let c = r.map(1, frame: CGRect(x: 0, y: 40, width: w.width, height: 500))
        XCTAssertEqual(c.floatGeom.width, (w.width * 0.9).rounded(.towardZero))
        XCTAssertEqual(c.floatGeom.midX, w.midX, accuracy: 1)
    }

    func testMinimizedGoesFirstInTheClientList() {
        let r = EngineRig()
        let a = r.map(1), _ = r.map(2), c = r.map(3)
        d(r, "minimized", [], c)
        d(r, "minimized", [], a)
        XCTAssertEqual(r.server.clients.first?.id, a.id)
        XCTAssertEqual(a.tags, 0)
        XCTAssertEqual(a.oldtags, 1)
        d(r, "restore_minimized")
        XCTAssertFalse(a.isminimized, "the last minimized")
        XCTAssertTrue(c.isminimized)
    }

    private func twoMonitors(_ r: EngineRig) -> Monitor {
        let side = Screen(displayID: 2, name: "Side", frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
                          workArea: CGRect(x: 1728, y: 0, width: 1920, height: 1080), scale: 1, isMain: false)
        r.server.rebuildMonitors(screens: [r.screen, side])
        return r.server.monitors.first { $0.screen.name == "Side" }!
    }

    /// mango's monitor_from_cycle reads the list head as a monitor on the wrap (docs/afvigelser.md §6).
    func testMonitorCycleWrapsAround() {
        let r = EngineRig()
        _ = twoMonitors(r)
        let first = r.server.monitors[0], last = r.server.monitors[1]
        r.server.selectedMonitor = last
        XCTAssertTrue(r.server.monitorFromCycle(MON_NEXT) === first)
        r.server.selectedMonitor = first
        XCTAssertTrue(r.server.monitorFromCycle(MON_PREV) === last)
    }

    func testFocusingAnEmptyMonitorClearsThePointersFocus() {
        let r = EngineRig()
        let side = twoMonitors(r)
        let a = r.map(1)
        r.server.config.warpcursor = false
        r.server.system.seatPointerNotifyEnter(a.id)
        r.server.setSelectedMonitor(r.monitor)
        _ = r.server.focusMonitor(Arg(i: MON_NEXT))
        XCTAssertTrue(r.server.selectedMonitor === side)
        XCTAssertNil(r.server.system.pointerFocusedSurface, "wlr_seat_pointer_notify_clear_focus: the next motion over a focuses it again")
    }

    func testADialogOpensOnItsParentsMonitor() {
        let r = EngineRig()
        let side = twoMonitors(r)
        let a = r.map(1)
        r.server.clientSetMonitor(a, side, 0, focus: false)
        r.server.clientFocus(a, true)
        r.server.setSelectedMonitor(r.monitor)
        let d = r.map(2, dialog: true)
        XCTAssertTrue(d.mon === side, "client_get_parent: the parent's monitor, not the selected one")
        XCTAssertTrue(d.isfloating)
    }

    func testTheOverviewBackupIsTheGeomAtMap() {
        let r = EngineRig()
        let c = r.map(1)
        XCTAssertGreaterThan(c.overviewBackupGeom.width, 0, "handle_client_map: overview_backup_geom = geom")
        XCTAssertFalse(c.overviewBackedUp)
    }

    func testTagmonOnItsOwnMonitorViewsItsTags() {
        let r = EngineRig()
        let a = r.map(1)
        a.tags = 1 << 1
        d(r, "tagmon", ["next", "1"], a)
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 1, "one monitor: next is none, as mango's monitor_from_cycle")
        d(r, "tagmon", [r.screen.name, "1"], a)
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 1 << 1)
    }

    func testArrangeFillsTheSelection() {
        let r = EngineRig()
        let a = r.map(1)
        r.monitor.sel = nil
        r.arrange()
        XCTAssertEqual(r.monitor.sel, a.id)
    }

    private func tileOf4(_ r: EngineRig, _ layout: LayoutKind = .tile) -> [Client] {
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = layout
        for id in 1...4 { r.map(CGWindowID(id)) }
        r.arrange()
        return r.server.tiledClients(r.monitor)
    }

    func testViewInsertShiftsTheTags() {
        let r = EngineRig()
        let a = r.map(1)
        let b = r.map(2)
        b.tags = 1 << 1
        r.monitor.pertag.nmasters[2] = 3
        d(r, "view_insert", ["next"])
        XCTAssertEqual(a.tags, 1)
        XCTAssertEqual(b.tags, 1 << 2, "tag 2 moved to 3")
        XCTAssertEqual(r.monitor.pertag.nmasters[3], 3, "with its state")
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 1 << 1)
    }

    func testAClickOnAWindowInViewFocusesIt() {
        let r = EngineRig()
        r.server.config.focusOnActivate = false
        let a = r.map(1)
        let b = r.map(2)
        r.server.clientFocus(a, true)
        r.server.mac.windowFocused(id: b.id)
        XCTAssertTrue(r.server.focused === b)
        XCTAssertFalse(b.isurgent)
    }

    func testFocusdirInTheOverviewKeepsIt() {
        let r = EngineRig()
        for id in 1...4 { r.map(CGWindowID(id)) }
        r.arrange()
        _ = r.server.dispatch(Dispatch(name: "toggleoverview"))
        _ = r.server.dispatch(Dispatch(name: "focusdir", args: ["right"]))
        let f = try! XCTUnwrap(r.server.focused)
        r.server.config.warpcursor = true
        _ = r.server.dispatch(Dispatch(name: "focusdir", args: ["left"]))
        _ = r.server.dispatch(Dispatch(name: "focusdir", args: ["right"]))
        let fake = r.server.system as! FakeWindowSystem
        XCTAssertEqual(fake.warps.last, r.server.selectedMonitor.ovCards[f.id]?.center, "warp_cursor: to the card")
        r.server.mac.windowFocused(id: f.id)
        XCTAssertTrue(r.server.anyOverview, "the overview stays")
        let other = r.server.clients.first { $0 !== f }!
        r.server.mac.windowFocused(id: other.id)
        XCTAssertFalse(r.server.anyOverview, "another window is the one chosen")
        XCTAssertTrue(r.server.focused === other)
    }

    func testTheOverviewClearsAndRestoresTheStates() {
        let r = EngineRig()
        let a = r.map(1), b = r.map(2), c = r.map(3)
        r.arrange()
        a.isfloating = true
        b.isfullscreen = true
        c.ismaximizescreen = true
        _ = r.server.dispatch(Dispatch(name: "toggleoverview"))
        XCTAssertEqual([a.isfloating, b.isfullscreen, c.ismaximizescreen], [false, false, false])
        var moved = false
        for d in ["left", "right", "up", "down"] {
            r.server.clientFocus(b, true)
            _ = r.server.dispatch(Dispatch(name: "focusdir", args: [d]))
            if r.monitor.sel != b.id { moved = true }
        }
        XCTAssertTrue(moved, "the fullscreen window's card is no stop")
        r.server.clientFocus(b, true)
        _ = r.server.dispatch(Dispatch(name: "toggleoverview"))
        XCTAssertEqual([a.isfloating, b.isfullscreen, c.ismaximizescreen], [true, true, false],
                       "want_restore_fullscreen: c shares its tag with b, the selection")
    }

    func testMonocleInTheOverviewGoesByTheCards() throws {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .monocle
        for id in 1...4 { r.map(CGWindowID(id)) }
        r.arrange()
        _ = r.server.dispatch(Dispatch(name: "toggleoverview"))
        let cards = r.server.selectedMonitor.ovCards
        let top = cards.values.map(\.minY).min()!
        let start = try XCTUnwrap(cards.filter { $0.value.minY == top }.max { $0.value.minX < $1.value.minX })
        r.server.clientFocus(r.server.clientByIdAll(start.key)!, true)
        _ = r.server.dispatch(Dispatch(name: "focusdir", args: ["right"]))
        XCTAssertEqual(r.monitor.sel, start.key, "no card to the right of the top row's last")
        _ = r.server.dispatch(Dispatch(name: "focusdir", args: ["left"]))
        let to = try XCTUnwrap(r.monitor.sel.flatMap { cards[$0] })
        XCTAssertLessThan(to.midX, start.value.midX, "a card to the left")
        XCTAssertEqual(to.minY, top, "in the same row")
    }

    func testMovewinAndResizewinAbsolute() {
        let r = EngineRig()
        let a = r.map(1)
        d(r, "movewin", ["100", "120"], a)
        XCTAssertEqual(a.floatGeom.origin, CGPoint(x: 100, y: 120))
        d(r, "resizewin", ["40", "40"], a)
        XCTAssertEqual(a.floatGeom.size, CGSize(width: 40, height: 40))
    }

    // a mango bug, docs/afvigelser.md §6: mango adds to the normal gaps and writes them as the special ones

    func testSpawnOnEmptyTakesTheCommandThenTheTags() {
        let r = EngineRig()
        r.map(1)
        d(r, "spawn_on_empty", ["foot -e x", "3"])
        XCTAssertEqual((r.server.system as! FakeWindowSystem).spawned, ["foot -e x"])
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 1 << 2)
    }

    func testNamedScratchpadLooksOnTheSelectedMonitorOnly() {
        let r = EngineRig()
        let side = twoMonitors(r)
        r.server.selectedMonitor = side
        let a = r.map(1)
        r.server.selectedMonitor = r.monitor
        d(r, "toggle_named_scratchpad", ["test", "none", "foot"])
        XCTAssertFalse(a.isnamedscratchpad)
        XCTAssertEqual((r.server.system as! FakeWindowSystem).spawned, ["foot"])
    }

    func testRemovingTheOverviewsDisplayClosesTheOverview() {
        let r = EngineRig()
        let side = twoMonitors(r)
        r.server.selectedMonitor = side
        let a = r.map(1)
        a.tags = 1 << 2
        r.server.toggleOverview(Arg())
        XCTAssertTrue(side.isoverview)
        r.server.rebuildMonitors(screens: [r.screen])
        XCTAssertFalse(r.server.anyOverview)
        XCTAssertTrue(a.mon === r.monitor)
        XCTAssertEqual(a.tags, 1 << 2)
    }

    /// group_bar_target_at goes through node_at_point: a window in the bar's layer or above hides it.
    func testAFloatingWindowOverAGroupBarHidesIt() {
        let r = EngineRig()
        r.server.config.alwaysShowGroupBar = true
        let a = r.map(1)
        r.map(2)
        r.arrange()
        let bar = CGPoint(x: a.frame.midX, y: a.frame.minY - CGFloat(r.server.config.groupBarHeight) / 2)
        XCTAssertTrue(r.server.groupBarTargetAt(bar.x, bar.y, nil) === a)
        let f = r.window(3, floating: true, frame: CGRect(x: bar.x - 50, y: bar.y - 50, width: 100, height: 100))
        XCTAssertNil(r.server.groupBarTargetAt(bar.x, bar.y, nil), "the floating window lies over the bar")
        XCTAssertTrue(r.server.groupBarTargetAt(bar.x, bar.y, f) === a, "the dragged window does not hide it")
    }

    func testBarClamps() {
        let c = ConfigParser.parse(text: """
        tab_bar_height=800
        title_message_bar_height=900
        group_bar_button_size=0
        group_bar_button_margin=-5
        """, baseDirectory: nil, fileName: "t").config
        XCTAssertEqual(c.tabBarHeight, 500)
        XCTAssertEqual(c.titleMessageBarHeight, 500)
        XCTAssertEqual(c.groupBarButtonSize, 4)
        XCTAssertEqual(c.groupBarButtonMargin, 0)
    }

    func testNoProportionPresetByDefault() {
        XCTAssertEqual(Config().scrollerProportionPreset, [])
    }

    func testARemovedTagRuleSendsTheTagBackToTile() {
        let r = EngineRig()
        r.server.config.tagRules = ConfigParser.parse(text: "tag_rule=id:2,layout_name:scroller", baseDirectory: nil,
                                                      fileName: "t").config.tagRules
        r.server.parseTagrule(r.monitor)
        XCTAssertEqual(r.monitor.pertag.ltidxs[2], .scroller)
        r.server.config.tagRules = []
        r.server.parseTagrule(r.monitor)
        XCTAssertEqual(r.monitor.pertag.ltidxs[2], .tile)
    }

    func testParseTagMaskAsMango() {
        XCTAssertEqual(ValueParse.parseTagMask("1|0"), TAG0_MASK)
        XCTAssertEqual(ValueParse.parseTagMask("32"), 32)
        XCTAssertEqual(ValueParse.parseTagMask("1|abc"), 1)
        XCTAssertEqual(ValueParse.parseTagMask("00"), 0)
        XCTAssertEqual(ValueParse.parseTagMask("-1"), 0xFFFF_FFFF)
    }

    func testParseModSkipsUnknownTokens() {
        XCTAssertEqual(BindingParser.parseMod("SUPER+FOO"), .superKey)
        XCTAssertNil(BindingParser.parseMod("FOO"))
        XCTAssertNil(BindingParser.parseMod(""))
    }

    func testABadGlobalKeyBindingDropsTheRule() {
        let c = ConfigParser.parse(text: "window_rule=app_id:foo,is_floating:1,global_key_binding:bogus-a",
                                   baseDirectory: nil, fileName: "t")
        XCTAssertTrue(c.config.windowRules.isEmpty)
        XCTAssertEqual(c.errors.count, 1)
    }

    func testDispatcherNamesAreCaseSensitive() {
        let c = ConfigParser.parse(text: "bind=SUPER,j,FocusStack,next", baseDirectory: nil, fileName: "t")
        XCTAssertTrue(c.config.keyBindings.isEmpty)
        XCTAssertTrue(c.errors.first?.message.contains("Unknown dispatch") ?? false)
    }

    func testCurvesTakeFourAndUnknownAnimationTypesSlide() {
        let c = ConfigParser.parse(text: """
        animation_curve_open=0.46,1,0.29,0.99,7
        animation_type_open=bounce
        """, baseDirectory: nil, fileName: "t")
        XCTAssertEqual(c.errors.count, 0)
        XCTAssertEqual(c.config.animationCurveOpen, BezierCurve(x1: 0.46, y1: 1, x2: 0.29, y2: 0.99))
        XCTAssertEqual(c.config.animationTypeOpen, .slide)
    }

    func testSetoptionKeyModeAndEnv() {
        var c = Config()
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
        XCTAssertTrue(ConfigParser.parseOption(&c, "key_mode", "resize", 0, baseDirectory: base))
        XCTAssertTrue(ConfigParser.parseOption(&c, "bind", "NONE,h,focusdir,left", 0, baseDirectory: base))
        XCTAssertEqual(c.keyBindings.last?.mode, "resize")
        guard !parseOption("env", "FOO,", to: &c) else { return XCTFail("expected invalid") }
    }

    func testColoursAreAlwaysRRGGBBAA() {
        let c = parseColor("0xff0000")!
        XCTAssertEqual([c.r, c.g, c.b, c.a], [0, 1, 0, 0])
        XCTAssertNil(parseColor("#ff0000ff"))
        XCTAssertEqual(parseColor("0x112233ff")?.a, 1)
    }

    func testSetoptionReappliesAsMango() {
        let r = EngineRig()
        r.map(1)
        r.server.config.exec = ["foo"]
        r.monitor.pertag.nmasters[getMonCurtag(r.monitor)] = 3
        d(r, "setoption", ["gap_outer_horizontal", "24"])
        XCTAssertEqual(r.monitor.gappoh, 24)
        XCTAssertEqual(Int(r.monitor.pertag.nmasters[getMonCurtag(r.monitor)]), r.server.config.defaultNmaster)
        XCTAssertEqual((r.server.system as! FakeWindowSystem).spawned, ["foo"])
    }

    func testConfinePointerKeepsThePointerInside() {
        let r = EngineRig()
        rules(r, "window_rule=confine_pointer:1,app_id:^test$")
        let fake = r.server.system as! FakeWindowSystem
        let a = r.map(1)
        XCTAssertTrue(a.confinePointer)
        let box = a.geom
        XCTAssertEqual(fake.warps.last, CGPoint(x: box.midX, y: box.midY), "pointer_check_confine_client: to the middle of its box")
        r.server.cursorMotion(to: CGPoint(x: box.maxX + 50, y: box.midY), time: 1)
        XCTAssertEqual(fake.warps.last, CGPoint(x: box.maxX - a.bw - 6, y: box.midY), "CONFINE_POINTER_MARGIN inside the border")
    }

    func testOverviewViewsEveryTagAndLeavesOnTheSelectedWindowsTag() {
        let r = EngineRig()
        let a = r.map(1)
        let b = r.map(2)
        b.tags = 1 << 1
        r.server.clientFocus(a, true)
        r.monitor.tagset[r.monitor.seltags] = 1
        d(r, "toggleoverview")
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 0x1FF)
        d(r, "view", ["3"])
        XCTAssertTrue(r.server.anyOverview, "a tag view is refused in overview")
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 0x1FF)
        d(r, "focusstack", ["next"])
        XCTAssertTrue(r.server.focused === b, "a card on another tag is reached")
        d(r, "toggleoverview")
        XCTAssertFalse(r.server.anyOverview)
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 1 << 1, "b's first tag")
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags ^ 1], 1, "the tags from before")
        XCTAssertTrue(r.server.focused === b)
    }

    func testFocusNoneKeepsAShownSelection() {
        let r = EngineRig()
        let a = r.map(1)
        r.server.clientFocus(nil, false)
        XCTAssertEqual(r.monitor.sel, a.id)
    }

    func testDwindleNewcomersSplitTheFocusedLeaf() {
        let area = CGRect(x: 0, y: 0, width: 2000, height: 1000)
        let r = EngineRig()
        r.server.rebuildMonitors(screens: [Screen(displayID: 1, name: "t", frame: area, workArea: area, scale: 1, isMain: true)])
        r.monitor.gappih = 0; r.monitor.gappiv = 0; r.monitor.gappoh = 0; r.monitor.gappov = 0
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .dwindle
        let c1 = r.window(1, frame: area)
        r.server.clientFocus(c1, false)
        r.arrange()
        r.window(2, frame: area); r.window(3, frame: area)
        r.server.focusStack.removeAll { $0 == 1 }
        r.server.focusStack.insert(1, at: 0)
        r.arrange()
        XCTAssertEqual(r.server.clientByIdAll(2)?.geom.width, 1000)
        XCTAssertEqual(c1.geom.width, 500)
    }

    func testExecRunsThroughTheShell() throws {
        let r = EngineRig()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.conf")
        try "exec=FOO=1 echo a | cat\nexec_once=echo b\n".write(to: url, atomically: true, encoding: .utf8)
        r.server.configURL = url
        r.server.reloadConfig(nil)
        XCTAssertEqual(fake(r).shelled, ["FOO=1 echo a | cat"], "reset_option runs exec, not exec_once")
    }

    func testOverviewNotWhileGrabbed() {
        let r = EngineRig()
        let c = r.map(1)
        r.server.grabClient = c; r.server.cursorMode = CurMove
        for name in ["toggleoverview", "enteroverview", "togglejump"] { d(r, name) }
        XCTAssertFalse(r.server.anyOverview)
        XCTAssertFalse(r.monitor.isJumpMode, "a mango bug, docs/afvigelser.md §6: no jump mode left on")
        r.server.grabClient = nil; r.server.cursorMode = CurNormal
        d(r, "toggleoverview")
        XCTAssertTrue(r.server.anyOverview)
        r.server.grabClient = c; r.server.cursorMode = CurMove
        d(r, "leaveoverview")
        XCTAssertTrue(r.server.anyOverview, "leave_overview: nothing while grabbed")
    }

    func testFocusmonTakesNoNumber() {
        let r = EngineRig()
        let side = twoMonitors(r)
        d(r, "focusmon", ["2"])
        XCTAssertTrue(r.server.selectedMonitor === r.monitor)
        d(r, "focusmon", ["Side"])
        XCTAssertTrue(r.server.selectedMonitor === side)
    }

    /// mango match_monitor_spec: strtok(spec, "&&") splits at every "&", the key is exact and nothing is
    /// trimmed; make, model and serial are compared with the output's, and a missing one does not match.
    func testMonitorSpecIsMangos() {
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

    /// Dispatchers give the monitor's make, model and serial to match_monitor_spec, as mango does.
    func testFocusmonMatchesMake() {
        let r = EngineRig()
        var side = Screen(displayID: 2, name: "Side", frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
                          workArea: CGRect(x: 1728, y: 0, width: 1920, height: 1080), scale: 1, isMain: false)
        side.make = "BNQ"
        r.server.rebuildMonitors(screens: [r.screen, side])
        d(r, "focusmon", ["make:BNQ"])
        XCTAssertEqual(r.server.selectedMonitor.screen.name, "Side")
        d(r, "focusmon", ["name:Built-in"])
        XCTAssertEqual(r.server.selectedMonitor.screen.name, "Built-in")
    }

    func testJumpLabelsPresetAndDropColour() {
        var c = Config()
        XCTAssertEqual(c.dropcolor.a, 0.5)
        _ = parseOption("jump_labels", "", to: &c)
        XCTAssertEqual(c.jumpLabels, "")
        _ = parseOption("scroller_proportion_preset", "0.5x, 0.8", to: &c)
        XCTAssertEqual(c.scrollerProportionPreset, [0.5, 0.8])
        if parseOption("scroller_proportion_preset", "a,0.8", to: &c) { XCTFail("not a number") }
        XCTAssertEqual(c.scrollerProportionPreset, [], "mango frees the old list first")
    }

    func testResizewinKeepsTheAnimationSetting() {
        let r = EngineRig()
        r.server.config.animations = true
        let a = r.map(1)
        r.map(2)
        d(r, "resizewin", ["+50", "0"], a)
        XCTAssertTrue(r.server.config.animations)
    }

    func testMinimizedWhileAwayGoesThroughTheHandler() {
        let r = EngineRig()
        let a = r.map(1), b = r.map(2)
        a.ignoreMinimize = true
        r.server.clientFocus(a, true)
        r.server.mac.windowReacquired(id: a.id, element: r.app.element(for: a.id),
                                      state: ReacquiredState(frame: nil, minimized: true, fullscreen: false, appHidden: false))
        XCTAssertNil(r.server.clientByIdAll(a.id), "away in the Dock: unmapped")
        XCTAssertEqual(r.monitor.sel, b.id, "the next window is focused")
    }

    func testUnmapEndsTheGrab() {
        let r = EngineRig()
        let c = r.map(1)
        r.server.grabClient = c; r.server.cursorMode = CurMove
        r.server.handleClientUnmap(c)
        XCTAssertNil(r.server.grabClient)
        XCTAssertEqual(r.server.cursorMode, CurNormal)
    }

    func testAnEmptyRuleAnimationTypeIsUnset() throws {
        let r = try XCTUnwrap(ConfigParser.parse(text: "window_rule=app_id:x,animation_type_open:", baseDirectory: nil,
                                                 fileName: "t.conf").config.windowRules.first)
        XCTAssertNil(r.animationTypeOpen)
    }

}
