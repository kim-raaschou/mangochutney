import XCTest
@testable import Mango
@testable import Port

@MainActor
final class FidelityTests: MangoTestCase {
    func testNewWindowGoesLast() {
        let r = EngineRig()
        r.server.config.newIsMaster = false
        let a = r.map(1), _ = r.map(2), _ = r.map(3)
        r.server.clientFocus(a, true)
        r.map(4)
        XCTAssertEqual(r.server.clients.map(\.id), [1, 2, 3, 4])
    }

    func testNewIsMasterGoesFirst() {
        let r = EngineRig()
        r.server.config.newIsMaster = true
        r.map(1); r.map(2)
        XCTAssertEqual(r.server.clients.map(\.id), [2, 1])
    }

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

    func testClientFocusAndFocusStack() {
        let r = EngineRig()
        r.server.config.warpcursor = true
        let a = r.window(1), b = r.window(2), c = r.window(3)
        r.arrange()
        r.server.clientFocus(a, true)
        XCTAssertEqual(fake(r).warps, [], "client_focus does not warp")
        c.noFocus = true
        r.server.clientFocus(c, true)
        XCTAssertEqual(r.monitor.sel, a.id, "no_focus: not focused")
        _ = r.server.dispatch(Dispatch(name: "focusstack", args: ["next"]))
        XCTAssertEqual(r.monitor.sel, b.id, "the next in the client list")
        XCTAssertEqual(fake(r).warps.count, 1, "focus_stack warps")
        _ = r.server.dispatch(Dispatch(name: "focusstack", args: ["next"]))
        XCTAssertEqual(r.monitor.sel, b.id, "the next is no_focus: client_focus leaves the focus")
    }

    func testFocusDirIntoTheStackGoesToItsLastFocused() {
        let r = EngineRig()
        r.server.config.newIsMaster = false
        let a = r.window(1), _ = r.window(2), c = r.window(3)
        r.arrange()
        r.server.clientFocus(c, true)
        r.server.clientFocus(a, true)
        _ = r.server.dispatch(Dispatch(name: "focusdir", args: ["right"]))
        XCTAssertEqual(r.monitor.sel, c.id)
    }

    func testFocusCrossTagDown() {
        let r = EngineRig()
        r.server.config.focusCrossTag = true
        let a = r.window(1, tags: 1), _ = r.window(2, tags: 1 << 1)
        r.arrange()
        r.server.clientFocus(a, true)
        _ = r.server.dispatch(Dispatch(name: "focusdir", args: ["down"]))
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 1 << 1)
    }

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

    func testUnmapFocusesTheStackNeighbour() {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .scroller
        let a = r.map(1), _ = r.map(2), c = r.map(3)
        _ = r.server.dispatch(Dispatch(name: "scroller_stack", args: ["left"]), target: c)
        let col = r.server.scrollerStack(of: c.id)
        guard col.count >= 2, let i = col.firstIndex(of: c.id), i + 1 < col.count || i > 0 else {
            return XCTFail("no stack to test with: \(r.server.scrollerStack(of: a.id)) \(col)")
        }
        let expected = i + 1 < col.count ? col[i + 1] : col[i - 1]
        XCTAssertNotEqual(expected, a.id, "the focused window is outside the stack")
        r.server.clientFocus(a, true)
        r.server.mac.windowDestroyed(id: c.id)
        XCTAssertEqual(r.monitor.sel, expected, "the stack neighbour, though the gone window had no focus")
    }

    func testMonitorFromDirectionGoesRound() {
        let r = EngineRig()
        let right = Screen(displayID: 2, name: "Right", frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
                           workArea: CGRect(x: 1728, y: 25, width: 1920, height: 1055), scale: 1, isMain: false)
        r.server.rebuildMonitors(screens: [r.screen, right])
        let a = r.monitor, b = r.server.monitors.first { $0.screen.displayID == 2 }!
        r.server.setSelectedMonitor(a)
        XCTAssertTrue(r.server.monitorFromDirection(RIGHT) === b)
        XCTAssertTrue(r.server.monitorFromDirection(LEFT) === b, "round the edge")
    }

    func testSetLayoutSparesScrollerFullscreen() {
        let r = EngineRig()
        let a = r.window(1), b = r.window(2, floating: true)
        a.isfullscreen = true; b.isfullscreen = true
        _ = r.server.setLayout(Arg(v: "scroller"))
        XCTAssertTrue(a.isfullscreen)
        XCTAssertFalse(b.isfullscreen)
        _ = r.server.setLayout(Arg(v: "tile"))
        XCTAssertFalse(a.isfullscreen)
    }

    func testSetProportion() {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .scroller
        r.server.config.scrollerIgnoreProportionSingle = false
        let a = r.map(1)
        _ = r.server.dispatch(Dispatch(name: "set_proportion", args: ["0.5"]), target: a)
        XCTAssertEqual(a.scrollerProportion, Float(0.9), "one window: refused")
        let b = r.map(2)
        _ = r.server.dispatch(Dispatch(name: "scroller_stack", args: ["left"]), target: b)
        let head = r.server.scrollerStack(of: b.id).first!
        let other = head == a.id ? b : a
        _ = r.server.dispatch(Dispatch(name: "set_proportion", args: ["0.5"]), target: other)
        XCTAssertEqual(r.server.clientByIdAll(head)?.scrollerProportion, 0.5)
        XCTAssertEqual(other.scrollerProportion, Float(0.9), "only the head")
    }

    func testToggleScratchpadOneAtATime() {
        let r = EngineRig()
        let a = r.window(1), b = r.window(2), _ = r.window(3)
        r.arrange()
        _ = r.server.dispatch(Dispatch(name: "minimized"), target: a)
        _ = r.server.dispatch(Dispatch(name: "minimized"), target: b)
        XCTAssertEqual(r.server.clients.first?.id, 2, "the last minimized first")
        func shown() -> [ClientID] { r.server.clients.filter { SCRATCHPAD_SHOWN($0) }.map(\.id) }
        _ = r.server.dispatch(Dispatch(name: "toggle_scratchpad"))
        XCTAssertEqual(shown(), [1], "one, not the whole pool: the oldest")
        _ = r.server.dispatch(Dispatch(name: "toggle_scratchpad"))
        XCTAssertEqual(shown(), [], "the shown one hides")
        XCTAssertEqual(r.server.clients.first?.id, 1, "and goes first")
        _ = r.server.dispatch(Dispatch(name: "toggle_scratchpad"))
        XCTAssertEqual(shown(), [2], "then the other")
    }

    func testRestoreMinimizedIsLastInFirstOutWithItsFloating() {
        let r = EngineRig()
        let a = r.window(1, floating: true), b = r.window(2)
        r.arrange()
        _ = r.server.dispatch(Dispatch(name: "minimized"), target: a)
        _ = r.server.dispatch(Dispatch(name: "minimized"), target: b)
        _ = r.server.dispatch(Dispatch(name: "restore_minimized"))
        XCTAssertFalse(b.isminimized, "the last minimized first")
        XCTAssertFalse(b.isfloating)
        XCTAssertTrue(a.isminimized)
        _ = r.server.dispatch(Dispatch(name: "restore_minimized"))
        XCTAssertFalse(a.isminimized)
        XCTAssertTrue(a.isfloating, "floating again, as before it was minimized")
    }

    func testSmartMoveStopsAtAFloatingWindow() {
        let r = EngineRig()
        let a = r.window(1, floating: true, frame: CGRect(x: 100, y: 300, width: 200, height: 200))
        _ = r.window(2, floating: true, frame: CGRect(x: 400, y: 300, width: 200, height: 200))
        a.floatGeom = CGRect(x: 100, y: 300, width: 200, height: 200)
        r.server.clientByIdAll(2)!.floatGeom = CGRect(x: 400, y: 300, width: 200, height: 200)
        r.server.smartMoveWindow(Arg(i: RIGHT, tc: a))
        let gap = CGFloat(r.server.config.gappih)
        XCTAssertEqual(a.floatGeom.maxX, 400 - gap, accuracy: 0.5, "stopped before the other, the inner gap apart")
        let t = r.window(3)
        r.server.smartMoveWindow(Arg(i: LEFT, tc: t))
        XCTAssertTrue(t.isfloating)
    }

    func testDwindleKeepsAFullscreenWindowsPlace() {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .dwindle
        let a = r.map(1), _ = r.map(2), _ = r.map(3)
        func order() -> [ClientID] {
            func leaves(_ n: DwindleNode?) -> [ClientID] {
                guard let n else { return [] }
                return n.isSplit ? leaves(n.first) + leaves(n.second) : [n.client?.id].compactMap { $0 }
            }
            return leaves(r.monitor.pertag.dwindleRoot[getMonCurtag(r.monitor)])
        }
        let before = order()
        a.isfullscreen = true
        r.arrange()
        XCTAssertTrue(order().contains(a.id), "its leaf stays")
        a.isfullscreen = false
        r.arrange()
        XCTAssertEqual(order(), before)
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
        XCTAssertTrue(r.server.fireGestureMotion(.left, 3))
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

    func testGrabEndRehomesATiledWindow() {
        let r = EngineRig()
        let right = Screen(displayID: 2, name: "Right", frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
                           workArea: CGRect(x: 1728, y: 25, width: 1920, height: 1055), scale: 1, isMain: false)
        r.server.rebuildMonitors(screens: [r.screen, right])
        let c = r.window(1)
        r.arrange()
        let g = Grab(client: c, mode: .move, startMouse: .zero, startFrame: c.frame)
        r.server.pointerEndGrabClient(g, at: CGPoint(x: 2500, y: 500))
        let b = r.server.monitors.first { $0.screen.displayID == 2 }!
        XCTAssertTrue(c.mon === b)
        XCTAssertTrue(r.server.selectedMonitor === b)
        XCTAssertEqual(b.sel, c.id)
        XCTAssertNotEqual(c.tags & b.tagset[b.seltags], 0)
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

    func testComboview() {
        let r = EngineRig()
        let m = r.monitor
        _ = r.server.dispatch(Dispatch(name: "comboview", args: ["2"]))
        _ = r.server.dispatch(Dispatch(name: "comboview", args: ["3"]))
        XCTAssertEqual(m.tagset[m.seltags], (1 << 1) | (1 << 2))
        r.server.tagCombo = false
        _ = r.server.dispatch(Dispatch(name: "comboview", args: ["1"]))
        XCTAssertEqual(m.tagset[m.seltags], 1)
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

    func testOvercircleFocusesEachStep() {
        let r = EngineRig()
        let a = r.window(1), _ = r.window(2), _ = r.window(3)
        r.arrange()
        r.server.clientFocus(a, true)
        _ = r.server.dispatch(Dispatch(name: "overcircle", args: ["next"]))
        XCTAssertTrue(r.server.anyOverview)
        r.server.overCircle(Arg(i: OVERCIRCLE_NEXT))
        let s1 = r.monitor.sel
        r.server.overCircle(Arg(i: OVERCIRCLE_NEXT))
        XCTAssertNotEqual(r.monitor.sel, s1, "the focus moves at every step")
        XCTAssertNotNil(r.monitor.sel)
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
        r.server.resizeTileClient(middle, isdrag: true, offsetX: 0, offsetY: 0, cursor: CGPoint(x: grab.x - 80, y: grab.y))
        XCTAssertGreaterThan(middle.gridColPer, 1, "the middle column grows to the left")
        XCTAssertTrue(left.allSatisfy { $0.gridColPer < 1 }, "the left column gives the room")
        XCTAssertTrue(right.allSatisfy { $0.gridColPer == 1 }, "the right column is not touched")
    }

    func testScratchpadFieldsAsMango() {
        let r = EngineRig()
        let a = r.window(1), _ = r.window(2)
        r.arrange()
        _ = r.server.dispatch(Dispatch(name: "minimized"), target: a)
        XCTAssertTrue(a.isInScratchpad)
        XCTAssertTrue(a.isminimized)
        XCTAssertFalse(SCRATCHPAD_SHOWN(a))
        _ = r.server.dispatch(Dispatch(name: "toggle_scratchpad"))
        XCTAssertTrue(a.isInScratchpad)
        XCTAssertFalse(a.isminimized, "shown: not minimized")
        XCTAssertTrue(SCRATCHPAD_SHOWN(a))
        let data = r.server.buildClientJson(a).serialized.data(using: .utf8)!
        let info = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(info["is_minimized"] as? Bool, false)
        XCTAssertEqual(info["is_scratchpad"] as? Bool, true, "is_scratchpad is is_in_scratchpad")
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
    }

    private func rules(_ r: EngineRig, _ text: String) {
        r.server.config.windowRules = ConfigParser.parse(text: text, baseDirectory: nil, fileName: "t").config.windowRules
    }

    func testARuleTagOutOfViewIsViewed() {
        let r = EngineRig()
        rules(r, "window_rule=tags:3,title:^t2$")
        r.map(1)
        let c = r.map(2)
        XCTAssertEqual(c.tags, 1 << 2)
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 1 << 2, "its tag is viewed")
        XCTAssertTrue(r.server.focused === c)
    }

    func testTagSilentFocusesOnlyInViewAndOpenSilentNever() {
        let r = EngineRig()
        rules(r, """
        window_rule=is_tag_silent:1,tags:1,title:^t2$
        window_rule=is_tag_silent:1,tags:3,title:^t3$
        window_rule=is_open_silent:1,title:^t4$
        """)
        let a = r.map(1)
        let b = r.map(2)
        XCTAssertTrue(r.server.focused === b, "its tag is in view: focused")
        r.map(3)
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 1, "the view stays")
        XCTAssertTrue(r.server.focused === b)
        r.map(4)
        XCTAssertTrue(r.server.focused === b, "is_open_silent: not focused")
        _ = a
    }

    func testAnUnfocusedNewWindowGoesToTheEndOfTheFocusStack() {
        let r = EngineRig()
        rules(r, "window_rule=is_open_silent:1,title:^t2$")
        let a = r.map(1)
        let b = r.map(2)
        XCTAssertEqual(r.server.focusStack.first, a.id)
        XCTAssertEqual(r.server.focusStack.last, b.id)
    }

    func testOpenAsFloatingIsTheWindowsTags() {
        let r = EngineRig()
        r.monitor.pertag.openAsFloating[3] = true
        rules(r, "window_rule=is_tag_silent:1,tags:3,title:^t2$")
        let a = r.map(1)
        let b = r.map(2)
        XCTAssertFalse(a.isfloating)
        XCTAssertTrue(b.isfloating, "tag 3 opens windows floating")
        r.monitor.pertag.openAsFloating[1] = true
        rules(r, "window_rule=is_tag_silent:1,tags:2,title:^t3$")
        XCTAssertFalse(r.map(3).isfloating, "the tag in view does not decide")
    }

    func testANewTiledWindowEndsFullscreenOnItsTag() {
        let r = EngineRig()
        rules(r, "window_rule=is_floating:1,title:^t2$")
        let a = r.map(1)
        a.isfullscreen = true
        r.map(2)
        XCTAssertTrue(a.isfullscreen, "a floating window leaves it")
        r.map(3)
        XCTAssertFalse(a.isfullscreen)
    }

    func testANamedScratchpadRuleShowsTheWindow() {
        let r = EngineRig()
        r.server.config.singleScratchpad = true
        rules(r, "window_rule=is_named_scratchpad:1,title:^t[12]$")
        let a = r.map(1)
        XCTAssertTrue(a.isInScratchpad && !a.isminimized && a.isfloating, "shown")
        let b = r.map(2)
        XCTAssertTrue(SCRATCHPAD_SHOWN(b))
        XCTAssertTrue(a.isInScratchpad && a.isminimized, "single_scratchpad hides the other")
    }

    func testWindowRuleOnceHitsOneWindow() {
        let r = EngineRig()
        rules(r, "window_rule_once=is_floating:1,app_id:^test$")
        XCTAssertTrue(r.map(1).isfloating)
        XCTAssertFalse(r.map(2).isfloating)
    }

    func testRuleFractionsAreOfTheWholeMonitor() {
        let r = EngineRig()
        rules(r, "window_rule=is_floating:1,width:0.5,height:0.5,app_id:^test$")
        let c = r.map(1)
        XCTAssertEqual(c.floatGeom.width, (r.screen.frame.width * 0.5).rounded())
        XCTAssertEqual(c.floatGeom.height, (r.screen.frame.height * 0.5).rounded())
    }

    func testTheLastMonitorARuleMatchesWins() {
        let r = EngineRig()
        let side = Screen(displayID: 2, name: "Side", frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
                          workArea: CGRect(x: 1728, y: 0, width: 1920, height: 1080), scale: 1, isMain: false)
        r.server.rebuildMonitors(screens: [r.screen, side])
        rules(r, "window_rule=monitor:i,title:^t1$")
        let c = r.map(1)
        XCTAssertTrue(c.mon === r.server.monitors.last)
    }

    private func d(_ r: EngineRig, _ name: String, _ args: [String] = [], _ c: Client? = nil) {
        _ = r.server.dispatch(Dispatch(name: name, args: args), target: c)
    }

    func testTilingAShownScratchpadTakesItOutOfTheScratchpad() {
        let r = EngineRig()
        let a = r.map(1)
        a.isInScratchpad = true
        a.isfloating = true
        d(r, "togglefloating", [], a)
        XCTAssertFalse(a.isfloating)
        XCTAssertFalse(a.isInScratchpad)
        XCTAssertTrue(r.server.tiledClients(r.monitor).contains { $0 === a })
    }

    func testTilingAFloatingWindowEndsFullscreenOnItsTag() {
        let r = EngineRig()
        let a = r.map(1)
        let b = r.map(2)
        d(r, "togglefloating", [], b)
        d(r, "togglemaximizescreen", [], a)
        XCTAssertTrue(a.ismaximizescreen)
        d(r, "togglefloating", [], b)
        XCTAssertFalse(a.ismaximizescreen)
    }

    func testAFloatingWindowAsWideAsTheScreenIsCutTo90Percent() {
        let r = EngineRig()
        rules(r, "window_rule=is_floating:1,app_id:^test$")
        let w = r.monitor.screen.workArea
        let c = r.map(1, frame: CGRect(x: 0, y: 40, width: w.width, height: 500))
        XCTAssertEqual(c.floatGeom.width, (w.width * 0.9).rounded(.towardZero))
        XCTAssertEqual(c.floatGeom.midX, w.midX, accuracy: 1)
    }

    func testFullscreenIsRefusedInOverview() {
        let r = EngineRig()
        let a = r.map(1)
        r.server.toggleOverview(Arg())
        XCTAssertTrue(r.server.anyOverview)
        d(r, "togglefullscreen", [], a)
        d(r, "togglemaximizescreen", [], a)
        XCTAssertFalse(a.isfullscreen)
        XCTAssertFalse(a.ismaximizescreen)
    }

    func testFakeFullscreenLeavesFullscreen() {
        let r = EngineRig()
        let a = r.map(1)
        d(r, "togglefullscreen", [], a)
        XCTAssertTrue(a.isfullscreen)
        d(r, "togglefakefullscreen", [], a)
        XCTAssertTrue(a.isfakefullscreen)
        XCTAssertFalse(a.isfullscreen)
    }

    func testOverlayDoesNotFloat() {
        let r = EngineRig()
        let a = r.map(1)
        d(r, "toggleoverlay", [], a)
        XCTAssertTrue(a.isoverlay)
        XCTAssertFalse(a.isfloating)
        d(r, "togglefloating", [], a)
        d(r, "togglefloating", [], a)
        XCTAssertTrue(a.isoverlay)
    }

    func testGlobalTakesAWindowOutOfTheScratchpad() {
        let r = EngineRig()
        let a = r.map(1)
        a.isInScratchpad = true
        d(r, "toggleglobal", [], a)
        XCTAssertTrue(a.isglobal)
        XCTAssertFalse(a.isInScratchpad)
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

    func testMinimizedIsRefusedInOverview() {
        let r = EngineRig()
        let a = r.map(1)
        r.server.toggleOverview(Arg())
        d(r, "minimized", [], a)
        XCTAssertFalse(a.isminimized)
    }

    func testRestoreMinimizedGoesOntoTheFocusedWindowsTags() {
        let r = EngineRig()
        let a = r.map(1)
        let b = r.map(2)
        d(r, "minimized", [], a)
        b.tags = 0b11
        r.server.clientFocus(b, true)
        d(r, "restore_minimized")
        XCTAssertEqual(a.tags, 0b11)
        XCTAssertFalse(a.isfloating)
    }

    func testFocusIdShowsAMinimizedWindowAndViewsItsFirstTag() {
        let r = EngineRig()
        let a = r.map(1)
        let b = r.map(2)
        d(r, "minimized", [], a)
        r.server.clientActive(a)
        XCTAssertFalse(a.isminimized)
        XCTAssertTrue(SCRATCHPAD_SHOWN(a), "shown in the scratchpad, not taken out")
        XCTAssertTrue(r.server.focused === a)
        b.tags = 1 << 1
        r.monitor.tagset[r.monitor.seltags] = 0b11
        r.server.clientActive(b)
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 1 << 1)
    }

    private func twoMonitors(_ r: EngineRig) -> Monitor {
        let side = Screen(displayID: 2, name: "Side", frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
                          workArea: CGRect(x: 1728, y: 0, width: 1920, height: 1080), scale: 1, isMain: false)
        r.server.rebuildMonitors(screens: [r.screen, side])
        return r.server.monitors.first { $0.screen.name == "Side" }!
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

    func testSpecialTagCrossMonitor() {
        let r = EngineRig()
        let side = twoMonitors(r)
        let a = r.map(1)
        d(r, "tag_special_tag", [], a)
        XCTAssertTrue(isSpecialActive(r.monitor))
        XCTAssertTrue(a.mon === r.monitor)

        r.server.toggleSpecialTagMon(side)
        XCTAssertTrue(a.mon === r.monitor, "off (mango's default): the window stays")
        r.server.toggleSpecialTagMon(side)

        r.server.config.specialTagCrossMonitor = true
        r.monitor.pertag.ltidxs[0] = .grid
        r.server.toggleSpecialTagMon(side)
        XCTAssertTrue(a.mon === side, "on: the special tag's windows come along")
        XCTAssertTrue(isSpecialActive(side))
        XCTAssertFalse(isSpecialActive(r.monitor), "the other monitor goes back to its tags")
        XCTAssertEqual(side.pertag.ltidxs[0], .grid, "with the special tag's layout")
    }

    func testTagmonViewsTheWindowsFirstTagOnTheTarget() {
        let r = EngineRig()
        let side = twoMonitors(r)
        side.tagset[side.seltags] = 0b11
        let a = r.map(1)
        d(r, "tagmon", ["right"], a)
        XCTAssertTrue(a.mon === side)
        XCTAssertEqual(a.tags, 0b11)
        XCTAssertEqual(side.tagset[side.seltags], 1)
        XCTAssertTrue(r.server.selectedMonitor === side)
        XCTAssertTrue(r.server.focused === a)
    }

    func testTagmonOntoTheSpecialTag() {
        let r = EngineRig()
        let side = twoMonitors(r)
        side.tagset[side.seltags] = TAG0_MASK
        let a = r.map(1)
        d(r, "tagmon", ["right"], a)
        XCTAssertEqual(a.tags, TAG0_MASK)
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

    func testTagcrossmonSetsTheTagsAndViewsThem() {
        let r = EngineRig()
        let side = twoMonitors(r)
        let a = r.map(1)
        d(r, "tagcrossmon", ["3", "Side"], a)
        XCTAssertTrue(a.mon === side)
        XCTAssertEqual(a.tags, 1 << 2)
        XCTAssertEqual(side.tagset[side.seltags], 1 << 2)
        XCTAssertTrue(r.server.focused === a)
        r.server.selectedMonitor = r.monitor
        let b = r.map(2)
        d(r, "tagcrossmon", ["2", "Built-in"], b)
        XCTAssertTrue(b.mon === r.monitor)
        XCTAssertEqual(b.tags, 1 << 1)
    }

    func testMoveClientJumpsOnlyWithExchangeCrossMonitor() {
        let r = EngineRig()
        let side = twoMonitors(r)
        r.server.selectedMonitor = r.monitor
        let a = r.map(1)
        d(r, "move_client", ["right"], a)
        XCTAssertTrue(a.mon === r.monitor, "exchange_cross_monitor off")
        r.server.config.exchangeCrossMonitor = true
        d(r, "move_client", ["right"], a)
        XCTAssertTrue(a.mon === side)
        XCTAssertEqual(side.sel, a.id)
        XCTAssertTrue(r.server.selectedMonitor === side)
    }

    func testMoveClientGoesBesideTheWindowOnTheOtherMonitor() {
        let r = EngineRig()
        let side = twoMonitors(r)
        r.server.selectedMonitor = side
        let b = r.map(2)
        let c = r.map(3)
        r.server.selectedMonitor = r.monitor
        let a = r.map(1)
        d(r, "move_client", ["right"], a)
        XCTAssertTrue(a.mon === r.monitor, "exchange_cross_monitor off")
        r.server.config.exchangeCrossMonitor = true
        r.server.selectedMonitor = r.monitor
        d(r, "move_client", ["right"], a)
        XCTAssertTrue(a.mon === side)
        let order = r.server.tiledClients(side).map(\.id)
        XCTAssertEqual(order.count, 3)
        XCTAssertTrue(order.contains(b.id) && order.contains(c.id))
    }

    func testADraggedTileWithoutDragTileToTileJoinsTheMonitorItIsLetGoOn() {
        let r = EngineRig()
        let side = twoMonitors(r)
        r.server.config.dragTileToTile = false
        r.server.selectedMonitor = r.monitor
        let a = r.map(1)
        r.arrange()
        let move = MouseBinding(mods: [.superKey], button: .left, dispatch: Dispatch(name: "moveresize", args: ["curmove"]))
        let f = a.geom ?? a.frame
        r.server.mousebind(move, at: CGPoint(x: f.midX, y: f.midY))
        let p = CGPoint(x: side.screen.frame.midX, y: side.screen.frame.midY)
        r.server.pointerProcessMotion(p, time: 0)
        r.server.buttonReleased(at: p)
        XCTAssertTrue(a.mon === side)
        XCTAssertTrue(a.isfloating)
        XCTAssertTrue(r.server.selectedMonitor === side)
        XCTAssertEqual(side.sel, a.id)
    }

    func testAMaximizedWindowKeepsItsTile() {
        let r = EngineRig()
        let a = r.map(1)
        let b = r.map(2)
        r.arrange()
        let before = a.geom
        d(r, "togglemaximizescreen", [], b)
        XCTAssertTrue(b.ismaximizescreen)
        XCTAssertEqual(a.geom, before)
    }

    func testMaximizedUsesTheConfigOuterGaps() {
        let r = EngineRig()
        let a = r.map(1)
        r.map(2)
        d(r, "togglegaps")
        d(r, "togglemaximizescreen", [], a)
        let w = r.monitor.screen.workArea
        XCTAssertEqual(a.geom.minX, w.minX + CGFloat(r.server.config.gappoh))
    }

    func testArrangeFillsTheSelection() {
        let r = EngineRig()
        let a = r.map(1)
        r.monitor.sel = nil
        r.arrange()
        XCTAssertEqual(r.monitor.sel, a.id)
    }

    func testScrollerSmartGapsCountColumns() {
        let r = EngineRig()
        r.server.config.smartgaps = true
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .scroller
        let a = r.map(1)
        let b = r.map(2)
        d(r, "scroller_stack", ["left"], b)
        r.arrange()
        let w = r.monitor.screen.workArea
        let top = [a, b].compactMap(\.geom).min { $0.minY < $1.minY }!
        let bottom = [a, b].compactMap(\.geom).max { $0.minY < $1.minY }!
        XCTAssertEqual(r.server.scrollerStack(of: a.id).count, 2)
        XCTAssertEqual(top.minY, w.minY, "no outer gap")
        XCTAssertEqual(bottom.minY - top.maxY, CGFloat(r.server.config.gappiv), "the stack gap stays")
    }

    func testGridIgnoresSmartGaps() {
        let r = EngineRig()
        r.server.config.smartgaps = true
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .grid
        let a = r.map(1)
        r.arrange()
        XCTAssertGreaterThan(a.geom.minX, r.monitor.screen.workArea.minX)
    }

    private func tileOf4(_ r: EngineRig, _ layout: LayoutKind = .tile) -> [Client] {
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = layout
        for id in 1...4 { r.map(CGWindowID(id)) }
        r.arrange()
        return r.server.tiledClients(r.monitor)
    }

    func testResizewinChangesAStackWindowsShare() {
        let r = EngineRig()
        let t = tileOf4(r)
        let top = t[1], mid = t[2], low = t[3]
        XCTAssertEqual(top.geom.height, mid.geom.height, accuracy: 2)
        d(r, "resizewin", ["0", "+100"], top)
        XCTAssertGreaterThan(top.geom.height, mid.geom.height + 50)
        XCTAssertEqual(mid.geom.height, low.geom.height, accuracy: 2)
        let h = top.geom.height
        r.arrange()
        XCTAssertEqual(top.geom.height, h, accuracy: 1, "kept in the weights")
    }

    func testResizewinMovesTheSplitMangosWay() {
        let r = EngineRig()
        let t = tileOf4(r)
        d(r, "resizewin", ["+50", "0"], t[2])
        XCTAssertGreaterThan(t[0].masterMfactPer, 0.55)
        let r2 = EngineRig()
        let t2 = tileOf4(r2, .rightTile)
        d(r2, "resizewin", ["+50", "0"], t2[0])
        XCTAssertLessThan(t2[0].masterMfactPer, 0.55)
    }

    func testResizewinChangesAScrollerStackShare() {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .scroller
        let a = r.map(1)
        let b = r.map(2)
        d(r, "scroller_stack", ["left"], b)
        r.arrange()
        let top = [a, b].min { $0.geom.minY < $1.geom.minY }!
        let other = top === a ? b : a
        XCTAssertEqual(top.geom.height, other.geom.height, accuracy: 2)
        d(r, "resizewin", ["0", "+100"], top)
        XCTAssertGreaterThan(top.geom.height, other.geom.height + 50)
    }

    func testResizewinLeavesALoneColumnsProportion() {
        let r = EngineRig()
        r.server.config.scrollerIgnoreProportionSingle = false
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .scroller
        let a = r.map(1)
        r.arrange()
        d(r, "resizewin", ["+100", "0"], a)
        XCTAssertEqual(a.scrollerProportion, Float(0.9), "the tag's default, as set_size_per copied it")
    }

    func testTagEndsFullscreenOnTheTargetTag() {
        let r = EngineRig()
        let a = r.map(1)
        a.tags = 1 << 1
        a.isfullscreen = true
        let b = r.map(2)
        d(r, "tag", ["2"], b)
        XCTAssertFalse(a.isfullscreen)
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 1 << 1)
    }

    func testToggletagAllAndBackAndToggleviewZero() {
        let r = EngineRig()
        let a = r.map(1)
        r.monitor.tagset[r.monitor.seltags] = 0b11
        d(r, "toggletag", [], a)
        XCTAssertEqual(a.tags, TagMask.mask(forTagNum: 9))
        d(r, "toggletag", [], a)
        XCTAssertEqual(a.tags, 1, "the current tag alone")
        d(r, "toggleview", ["0"])
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags] & TAG0_MASK, 0)
    }

    func testTagtorightIsAPlainShift() {
        let r = EngineRig()
        let a = r.map(1)
        d(r, "tagtoright", [], a)
        XCTAssertEqual(a.tags, 1 << 1)
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 1 << 1)
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

    func testTagGatherRenumbersTags() {
        let r = EngineRig()
        r.server.config.tagGather = true
        let a = r.map(1)
        let b = r.map(2)
        b.tags = 1 << 8
        r.arrange()
        XCTAssertEqual(a.tags, 1)
        XCTAssertEqual(b.tags, 1 << 1, "tag 9 became tag 2")
    }

    func testActivationWithoutFocusOnActivateMarksUrgent() {
        let r = EngineRig()
        r.server.config.focusOnActivate = false
        let a = r.map(1)
        let b = r.map(2)
        b.tags = 1 << 1
        r.arrange()
        r.server.clientFocus(a, true)
        r.server.handleClientActivationRequest(b)
        XCTAssertTrue(b.isurgent)
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 1)
        XCTAssertTrue(r.server.focused === a)
    }

    func testActivationWithFocusOnActivateViewsItsTag() {
        let r = EngineRig()
        r.server.config.focusOnActivate = true
        let a = r.map(1)
        let b = r.map(2)
        b.tags = 1 << 1
        r.arrange()
        r.server.clientFocus(a, true)
        r.server.handleClientActivationRequest(b)
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 1 << 1)
        XCTAssertTrue(r.server.focused === b)
        XCTAssertFalse(b.isurgent)
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

    func testAMinimizeRequestIsRefusedWithIgnoreMinimize() {
        let r = EngineRig()
        let a = r.map(1)
        a.ignoreMinimize = true
        r.server.handleClientRequestMinimize(a, true)
        XCTAssertFalse(a.isminimized)
        XCTAssertFalse(a.isInScratchpad)
        a.ignoreMinimize = false
        r.server.handleClientRequestMinimize(a, true)
        XCTAssertTrue(a.isminimized && a.isInScratchpad, "set_minimized")
    }

    func testFocuslastSkipsAMinimizedWindow() {
        let r = EngineRig()
        let a = r.map(1)
        let b = r.map(2)
        let c = r.map(3)
        r.server.clientFocus(a, true)
        r.server.clientFocus(b, true)
        r.server.clientFocus(c, true)
        d(r, "minimized", [], b)
        XCTAssertTrue(r.server.focused === c)
        d(r, "focuslast")
        XCTAssertTrue(r.server.focused === a, "b is minimized")
    }

    func testSmartkillKeepsAWindowWhoseTagsAreNotInView() {
        let r = EngineRig()
        let a = r.map(1)
        a.tags = 0b110
        d(r, "smartkillclient", [], a)
        XCTAssertEqual(a.tags, 0b110)
        XCTAssertFalse((r.server.system as! FakeWindowSystem).closed.contains(a.id))
    }

    func testZoomMovesTheWindowFirst() {
        let r = EngineRig()
        let a = r.map(1), b = r.map(2), c = r.map(3)
        r.server.clients = [a, b, c]
        d(r, "zoom", [], c)
        XCTAssertEqual(r.server.clients.map(\.id), [c.id, a.id, b.id])
        d(r, "zoom", [], c)
        XCTAssertEqual(r.server.clients.map(\.id), [a.id, c.id, b.id])
        XCTAssertTrue(r.server.focused === a)
    }

    func testSmartresizewinFloatsAndStopsAtANeighbour() {
        let r = EngineRig()
        let a = r.map(1)
        d(r, "smartresizewin", ["right"], a)
        XCTAssertTrue(a.isfloating)
        let b = r.map(2)
        b.isfloating = true
        // mango's smart_resize_window reads the floating windows' geom
        a.floatGeom = CGRect(x: 100, y: 200, width: 300, height: 300); a.geom = a.floatGeom
        b.floatGeom = CGRect(x: 450, y: 250, width: 300, height: 300); b.geom = b.floatGeom
        d(r, "smartresizewin", ["right"], a)
        XCTAssertEqual(a.floatGeom.maxX, 450 - CGFloat(r.server.config.gappih))
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
    func testIncgapsOnTheSpecialTagChangesTheSpecialGaps() {
        let r = EngineRig()
        r.map(1)
        let normal = r.monitor.gappoh, special = r.monitor.specialGappoh
        r.monitor.tagset[r.monitor.seltags] = TAG0_MASK
        d(r, "incgaps", ["5"])
        XCTAssertEqual(r.monitor.gappoh, normal)
        XCTAssertEqual(r.monitor.specialGappoh, special + 5)
    }

    func testSpawnOnEmptyTakesTheCommandThenTheTags() {
        let r = EngineRig()
        r.map(1)
        d(r, "spawn_on_empty", ["foot -e x", "3"])
        XCTAssertEqual((r.server.system as! FakeWindowSystem).spawned, ["foot -e x"])
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 1 << 2)
    }

    func testSwitchProportionPresetGoesForwardInTheConfigsOrder() {
        let r = EngineRig()
        r.server.config.scrollerProportionPreset = [0.8, 0.5, 1.0]
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .scroller
        let a = r.map(1)
        r.map(2)
        d(r, "set_proportion", ["0.8"], a)
        d(r, "switch_proportion_preset", [], a)
        XCTAssertEqual(a.scrollerProportion, 0.5)
        d(r, "switch_proportion_preset", ["prev"], a)
        XCTAssertEqual(a.scrollerProportion, 1.0, "prev goes forward too")
        d(r, "switch_proportion_preset", ["next"], a)
        XCTAssertEqual(a.scrollerProportion, 0.8, "and round")
    }

    func testFocusdirAcrossMonitorsTakesTheirFocusHistory() {
        let r = EngineRig()
        let side = twoMonitors(r)
        let a = r.map(1)
        r.server.selectedMonitor = side
        let b1 = r.map(2, frame: CGRect(x: 1800, y: 100, width: 800, height: 600))
        let b2 = r.map(3, frame: CGRect(x: 2800, y: 100, width: 600, height: 600))
        r.server.clientFocus(b2, true)
        r.server.clientFocus(b1, true)
        r.server.clientFocus(b2, true)
        let top = r.server.clientFocusTop(side)
        XCTAssertTrue(top === b2)
        r.server.clientFocus(a, true)
        XCTAssertTrue(r.server.selectedMonitor === r.monitor)
        r.server.config.focusCrossMonitor = false
        d(r, "focusdir", ["right"])
        XCTAssertEqual(r.server.focused?.id, 1, "not over the edge without focus_cross_monitor")
        r.server.config.focusCrossMonitor = true
        d(r, "focusdir", ["right"])
        XCTAssertTrue(r.server.selectedMonitor === side)
        XCTAssertTrue(r.server.focused === b2, "the monitor's last focused window")
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

    func testAMousebindRunsWithoutAWindow() {
        let r = EngineRig()
        let before = r.server.enableGaps
        let b = MouseBinding(mods: [.superKey], button: .middle, dispatch: Dispatch(name: "togglegaps"))
        r.server.mousebind(b, at: CGPoint(x: 5, y: 500))
        XCTAssertNotEqual(r.server.enableGaps, before)
    }

    func testAnOverviewClickOnNothingKeepsTheOverview() {
        let r = EngineRig()
        r.map(1)
        r.server.toggleOverview(Arg())
        r.server.pointerProcessButtonPress(button: 0, pressed: true, at: CGPoint(x: 1, y: 1080), mods: [])
        XCTAssertTrue(r.server.anyOverview)
    }

    func testAPressSelectsTheMonitorAndFocuses() {
        let r = EngineRig()
        let side = twoMonitors(r)
        r.server.selectedMonitor = r.monitor
        let a = r.map(1)
        r.server.selectedMonitor = side
        let b = r.map(2)
        r.server.clientFocus(a, true)
        XCTAssertTrue(r.server.selectedMonitor === r.monitor)
        r.server.pointerProcessButtonPress(button: 0, pressed: true, at: CGPoint(x: side.screen.frame.midX, y: side.screen.frame.midY), mods: [])
        XCTAssertTrue(r.server.selectedMonitor === side)
        XCTAssertTrue(r.server.focused === b)
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

    func testAGroupBarDropWorksWithoutDragTileToTile() {
        let r = EngineRig()
        r.server.config.dragTileToTile = false
        r.server.config.alwaysShowGroupBar = true
        let a = r.map(1)
        let b = r.map(2)
        r.arrange()
        let move = MouseBinding(mods: [.superKey], button: .left, dispatch: Dispatch(name: "moveresize", args: ["curmove"]))
        let f = b.geom ?? b.frame
        r.server.mousebind(move, at: CGPoint(x: f.midX, y: f.midY))
        let bar = CGPoint(x: a.frame.midX, y: a.frame.minY - CGFloat(r.server.config.groupBarHeight) / 2)
        guard r.server.groupBarTargetAt(at: bar, except: b) === a else {
            return XCTFail("no group bar over a: \(a.frame)")
        }
        r.server.buttonReleased(at: bar)
        XCTAssertTrue(b.isGroupMember)
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

    func testResetTagMovesWindowsOffGoneTags() {
        let r = EngineRig()
        let a = r.map(1)
        a.tags = 1 << 7
        r.server.config.tagNum = 5
        r.server.updateGlobalVar()
        r.server.resetTag(9)
        XCTAssertEqual(a.tags, 1 << 4)
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
        XCTAssertEqual(TagMask.parseTagMask("1|0"), TAG0_MASK)
        XCTAssertEqual(TagMask.parseTagMask("32"), 32)
        XCTAssertEqual(TagMask.parseTagMask("1|abc"), 1)
        XCTAssertEqual(TagMask.parseTagMask("00"), 0)
        XCTAssertEqual(TagMask.parseTagMask("-1"), TagMask.all)
    }

    func testParseModSkipsUnknownTokens() {
        XCTAssertEqual(Modifiers.parse("SUPER+FOO"), .superKey)
        XCTAssertNil(Modifiers.parse("FOO"))
        XCTAssertNil(Modifiers.parse(""))
    }

    func testARuleFlagThatIsNoNumberIsZero() {
        var errors: [String] = []
        let r = RuleParser.parseWindowRule("app_id:foo,is_floating:yes", once: false, errors: &errors).0
        XCTAssertEqual(r?.isfloating, false)
    }

    func testSwitchLayoutFollowsCircleLayout() {
        let r = EngineRig()
        r.map(1)
        r.server.config.circleLayout = ["tile", "monocle"]
        d(r, "switch_layout")
        XCTAssertEqual(r.monitor.layout, .monocle)
        r.server.config.circleLayout = ["spiral"]
        d(r, "switch_layout")
        XCTAssertEqual(r.monitor.layout, .monocle)
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
        guard case .invalid = ConfigOptions.parseOption(key: "env", value: "FOO,", to: &c) else { return XCTFail("expected invalid") }
    }

    func testColoursAreAlwaysRRGGBBAA() {
        let c = parseColor("0xff0000")!
        XCTAssertEqual([c.r, c.g, c.b, c.a], [0, 1, 0, 0])
        XCTAssertNil(parseColor("#ff0000ff"))
        XCTAssertEqual(parseColor("0x112233ff")?.a, 1)
    }

    func testBooleanWordsAreZero() {
        let c = ConfigParser.parse(text: "sloppy_focus=true\nsmart_gaps=1", baseDirectory: nil, fileName: "t").config
        XCTAssertFalse(c.sloppyfocus)
        XCTAssertTrue(c.smartgaps)
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
        XCTAssertEqual(fake.warps.last, CGPoint(x: a.frame.midX, y: a.frame.midY))
        r.server.handleCursorMotion(CGPoint(x: a.frame.maxX + 50, y: a.frame.midY), time: 1)
        XCTAssertEqual(fake.warps.last, CGPoint(x: a.frame.maxX - 6, y: a.frame.midY))
    }

    func testOverviewViewsEveryTagAndLeavesOnTheSelectedWindowsTag() {
        let r = EngineRig()
        let a = r.map(1)
        let b = r.map(2)
        b.tags = 1 << 1
        r.server.clientFocus(a, true)
        r.monitor.tagset[r.monitor.seltags] = 1
        d(r, "toggleoverview")
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], TagMask.mask(forTagNum: 9))
        d(r, "view", ["3"])
        XCTAssertTrue(r.server.anyOverview, "a tag view is refused in overview")
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], TagMask.mask(forTagNum: 9))
        d(r, "focusstack", ["next"])
        XCTAssertTrue(r.server.focused === b, "a card on another tag is reached")
        d(r, "toggleoverview")
        XCTAssertFalse(r.server.anyOverview)
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 1 << 1, "b's first tag")
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags ^ 1], 1, "the tags from before")
        XCTAssertTrue(r.server.focused === b)
    }

    func testOvercircleTakesOverAPlainOverview() {
        let r = EngineRig()
        r.map(1)
        r.map(2)
        d(r, "toggleoverview")
        d(r, "overcircle", ["next"])
        XCTAssertEqual(r.server.selectedMonitor.ovTabLayout, true)
    }

    func testTheLastGroupMemberIsNoGroupFocus() {
        let r = EngineRig()
        let a = r.map(1)
        let b = r.map(2)
        r.server.clientGroupJoin(b, a)
        let shown = [a, b].first { !$0.groupParked }!
        let other = shown === a ? b : a
        r.server.handleClientUnmap(shown)
        XCTAssertFalse(other.isGroupMember)
        XCTAssertFalse(other.isGroupFocus)
    }

    func testFocusNoneKeepsAShownSelection() {
        let r = EngineRig()
        let a = r.map(1)
        r.server.clientFocus(nil, false)
        XCTAssertEqual(r.monitor.sel, a.id)
    }

    func testScrollerStackHasNoRemainderForTheLast() {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .scroller
        let a = r.map(1), b = r.map(2), c = r.map(3)
        d(r, "scroller_stack", ["left"], b)
        d(r, "scroller_stack", ["left"], c)
        r.arrange()
        let hs = [a, b, c].map { $0.geom.height }
        XCTAssertEqual(r.server.scrollerStack(of: a.id).count, 3)
        XCTAssertLessThanOrEqual(hs.max()! - hs.min()!, 0.5, "\(hs)")
    }

    func testAWindowTiledAgainGoesBackToItsPlaceInTheScroller() {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .scroller
        let a = r.map(1), b = r.map(2), c = r.map(3)
        r.server.clients = [a, b, c]
        r.arrange()
        d(r, "togglefloating", [], b)
        r.server.clientFocus(c, true)
        d(r, "togglefloating", [], b)
        XCTAssertEqual(r.server.scrollerStacks(r.monitor), [[a.id], [b.id], [c.id]])
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

    func testCenterwinLeavesFullscreenAndMaximized() {
        let r = EngineRig()
        let c = r.window(1, floating: true)
        let before = c.floatGeom
        c.ismaximizescreen = true
        d(r, "centerwin", [], c)
        XCTAssertEqual(c.floatGeom, before)
        XCTAssertFalse(c.iscustomsize)
    }

    func testOverviewNotWhileGrabbed() {
        let r = EngineRig()
        let c = r.map(1)
        r.server.grab = Grab(client: c, mode: .move, startMouse: .zero, startFrame: c.frame)
        for name in ["toggleoverview", "enteroverview", "togglejump"] { d(r, name) }
        XCTAssertFalse(r.server.anyOverview)
        XCTAssertFalse(r.monitor.isJumpMode, "a mango bug, docs/afvigelser.md §6: no jump mode left on")
        r.server.grab = nil
        d(r, "toggleoverview")
        XCTAssertTrue(r.server.anyOverview)
        r.server.grab = Grab(client: c, mode: .move, startMouse: .zero, startFrame: c.frame)
        d(r, "leaveoverview")
        XCTAssertTrue(r.server.anyOverview, "leave_overview: nothing while grabbed")
    }

    func testLayoutDispatchersUseTheSelectedMonitor() {
        let r = EngineRig()
        let side = twoMonitors(r)
        r.server.selectedMonitor = side
        let a = r.map(1)
        r.server.selectedMonitor = r.monitor
        XCTAssertTrue(a.mon === side)
        d(r, "setlayout", ["monocle"], a)
        d(r, "incnmaster", ["1"], a)
        XCTAssertEqual(r.monitor.layout, .monocle)
        XCTAssertEqual(r.monitor.pertag.nmasters[getMonCurtag(r.monitor)], 2)
        XCTAssertNotEqual(side.layout, .monocle)
    }

    func testFocusmonTakesNoNumber() {
        let r = EngineRig()
        let side = twoMonitors(r)
        d(r, "focusmon", ["2"])
        XCTAssertTrue(r.server.selectedMonitor === r.monitor)
        d(r, "focusmon", ["Side"])
        XCTAssertTrue(r.server.selectedMonitor === side)
    }

    func testMonitorNamesMatchByCase() {
        var spec = MonitorSpec()
        spec.name = "Built-in"
        XCTAssertTrue(spec.matchMonitorSpec(name: "Built-in Retina Display"))
        spec.name = "built-in"
        XCTAssertFalse(spec.matchMonitorSpec(name: "Built-in Retina Display"))
    }

    func testJumpLabelsPresetAndDropColour() {
        var c = Config()
        XCTAssertEqual(c.dropcolor.a, 0.5)
        _ = ConfigOptions.parseOption(key: "jump_labels", value: "", to: &c)
        XCTAssertEqual(c.jumpLabels, "")
        _ = ConfigOptions.parseOption(key: "scroller_proportion_preset", value: "0.5x, 0.8", to: &c)
        XCTAssertEqual(c.scrollerProportionPreset, [0.5, 0.8])
        if case .applied = ConfigOptions.parseOption(key: "scroller_proportion_preset", value: "a,0.8", to: &c) { XCTFail("not a number") }
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

    func testAShownScratchpadStaysOnItsTag() {
        let r = EngineRig()
        let a = r.map(1), _ = r.map(2)
        d(r, "minimized", [], a)
        d(r, "toggle_scratchpad")
        XCTAssertTrue(SCRATCHPAD_SHOWN(a))
        XCTAssertTrue(VISIBLEON(a, r.monitor))
        d(r, "view", ["2"])
        XCTAssertTrue(SCRATCHPAD_SHOWN(a), "still shown, on tag 1")
        XCTAssertFalse(VISIBLEON(a, r.monitor), "not on tag 2")
        d(r, "toggle_scratchpad")
        XCTAssertEqual(a.tags, 1 << 1, "moved to the tag in view")
        XCTAssertTrue(VISIBLEON(a, r.monitor))
    }

    func testToggleviewKeepsTheCurrentTagsLayout() {
        let r = EngineRig()
        _ = r.map(1)
        d(r, "view", ["2"])
        d(r, "setlayout", ["scroller"])
        XCTAssertEqual(r.monitor.pertag.curtag, 2)
        d(r, "toggleview", ["1"])
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 0b11)
        XCTAssertEqual(r.monitor.pertag.curtag, 2, "toggle_view leaves curtag")
        XCTAssertEqual(r.monitor.layout, .scroller, "tag 2's layout, not tag 1's")
        d(r, "view", ["1"])
        XCTAssertEqual(r.monitor.pertag.curtag, 1)
        XCTAssertEqual(r.monitor.pertag.prevtag, 2)
    }

    func testUnmapEndsTheGrab() {
        let r = EngineRig()
        let c = r.map(1)
        r.server.grab = Grab(client: c, mode: .move, startMouse: .zero, startFrame: c.frame)
        r.server.handleClientUnmap(c)
        XCTAssertNil(r.server.grab)
    }

    func testFocusstackAndFocusidTakeTheTarget() {
        let r = EngineRig()
        let a = r.map(1), b = r.map(2), c = r.map(3)
        r.server.clientFocus(a, true)
        _ = r.server.dispatch(Dispatch(name: "focusstack", args: ["next"]), target: b)
        XCTAssertEqual(r.monitor.sel, r.server.getNextStackClient(b, reverse: false)?.id, "from b, not from a")
        r.server.clientFocus(c, true)
        _ = r.server.dispatch(Dispatch(name: "focusid"))
        XCTAssertEqual(r.monitor.sel, c.id, "no target: nothing")
    }

    func testCurtagStaysWhenAViewOverlaps() {
        let r = EngineRig()
        _ = r.map(1)
        d(r, "view", ["1"])
        d(r, "toggleview", ["2"])
        d(r, "view", ["2"])
        XCTAssertEqual(r.monitor.pertag.curtag, 2)
        XCTAssertEqual(r.monitor.pertag.prevtag, 1)
    }

    func testLayoutNamesAreCaseSensitive() {
        XCTAssertEqual(LayoutKind(name: "tile"), .tile)
        XCTAssertNil(LayoutKind(name: "Tile"))
    }

    func testAnEmptyRuleAnimationTypeIsUnset() throws {
        var errors: [String] = []
        let r = try XCTUnwrap(RuleParser.parseWindowRule("app_id:x,animation_type_open:", once: false, errors: &errors).0)
        XCTAssertNil(r.animationTypeOpen)
    }

    func testFloatingWindowsKeepMangosLooseBounds() {
        let r = EngineRig()
        let c = r.map(1)
        c.isfloating = true
        let scene = r.server.sceneGeometry
        let half = CGRect(x: scene.maxX - 200, y: 200, width: 600, height: 400)
        XCTAssertEqual(r.server.clientSetBounds(c, half, scene), half, "half outside: left as it is")
        let out = CGRect(x: scene.maxX + 50, y: 200, width: 600, height: 400)
        XCTAssertEqual(r.server.clientSetBounds(c, out, scene).minX, scene.maxX - 600, "wholly outside: back in")
    }
}
