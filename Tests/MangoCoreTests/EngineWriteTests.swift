import XCTest
@testable import Mango
@testable import Port

@MainActor
final class EngineWriteTests: MangoTestCase {
    func testTheWindowLeavingWaitsTillTheOneComingBackStandsInView() {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .monocle
        r.window(1); r.window(2)
        r.arrange()
        r.settle()
        let shown = r.server.clientsAll.first { !$0.parked }!, hidden = r.server.clientsAll.first { $0.parked }!
        let tile = shown.frame
        _ = r.server.focusStack(Arg(i: 1))
        r.arrange()
        XCTAssertEqual(r.app.frames[hidden.id], tile, "the window coming back is written")
        XCTAssertFalse(shown.parked, "the one leaving stays till its app has answered")
        XCTAssertEqual(r.app.frames[shown.id], tile)
        r.settle()
        XCTAssertTrue(shown.parked, "and is parked then")
        XCTAssertFalse(r.screen.frame.intersects(r.app.frames[shown.id]!.insetBy(dx: 1, dy: 1)))
        XCTAssertFalse(hidden.parked)
    }

    func testQuittingBringsHiddenWindowsBack() {
        let r = EngineRig()
        r.window(1)
        r.window(2, tags: 1 << 1)
        r.arrange()
        r.settle()
        XCTAssertTrue(r.server.clientByIdAll(2)!.parked)
        r.app.writes.removeAll()
        r.server.cleanup()
        XCTAssertEqual(r.app.writes.map(\.id), [2], "only the hidden window")
        XCTAssertTrue(r.screen.workArea.contains(r.app.frames[2]!), "back on the screen")
    }

    func testQuittingBringsBackAWindowAwayInACorner() {
        let r = EngineRig()
        r.window(1)
        let c = r.window(2, tags: 1 << 1)
        r.arrange()
        r.settle()
        XCTAssertTrue(c.parked)
        r.server.mac.appHidden(pid: c.pid, hidden: true)
        XCTAssertNil(r.server.clientByIdAll(2), "away")
        XCTAssertFalse(r.screen.workArea.contains(r.app.frames[2]!), "still in the corner")
        r.app.writes.removeAll()
        r.server.cleanup()
        XCTAssertTrue(r.app.writes.map(\.id).contains(2))
        XCTAssertTrue(r.screen.workArea.contains(r.app.frames[2]!), "back on the screen")
    }

    func testRestartingLeavesHiddenWindowsHidden() {
        let r = EngineRig()
        r.window(1)
        r.window(2, tags: 1 << 1)
        r.arrange()
        r.settle()
        r.app.writes.removeAll()
        r.server.mac.restarting = true
        r.server.cleanup()
        XCTAssertEqual(r.app.writes.count, 0)
    }

    func testTiledWindowsAreWrittenToTheirLayoutFramesOnce() {
        let r = EngineRig()
        let a = r.window(1), b = r.window(2)
        r.arrange()
        r.settle()
        for c in [a, b] {
            XCTAssertEqual(r.app.frames[c.id], c.geom, "the window is where the layout put it")
            XCTAssertEqual(c.frame, r.app.frames[c.id], "and mango knows it")
            XCTAssertTrue(r.screen.workArea.contains(c.frame))
        }
        XCTAssertFalse(a.frame.intersects(b.frame.insetBy(dx: 1, dy: 1)))
        let writes = r.app.writes.count
        r.arrange()
        r.settle()
        XCTAssertEqual(r.app.writes.count, writes, "nothing to write when everything is in place")
    }

    func testAWindowThatRefusesItsSizeIsTakenAsItIs() {
        let r = EngineRig()
        r.window(1)
        let b = r.window(2)
        r.app.minSize[2] = CGSize(width: 300, height: 1000)
        r.arrange()
        r.settle()
        XCTAssertEqual(b.frame, r.app.frames[2], "the border follows the real window")
        XCTAssertGreaterThanOrEqual(b.frame.height, 1000)
    }

    func testARefusalKeepsMangosTileAndIsAskedOnceMore() {
        let r = EngineRig()
        r.window(1)
        let b = r.window(2)
        r.window(3)
        r.app.minSize[2] = CGSize(width: 0, height: 700)
        r.arrange()
        let tile = b.geom
        r.settle(4)
        XCTAssertEqual(b.geom, tile, "mango's tile, not moved for the window")
        XCTAssertEqual(r.app.frames[2]?.height, 700, "the window keeps its own size")
        XCTAssertEqual(r.app.writes.filter { $0.id == 2 }.count, 2, "one write and one more ask")
        XCTAssertLessThan(tile.height, 700)
    }

    func testARefusedWindowGrowsInwardFromTheScreenEdge() {
        let r = EngineRig()
        r.window(1)
        let b = r.window(2)
        r.app.minSize[2] = CGSize(width: 1100, height: 0)
        r.arrange()
        let tile = b.geom
        r.settle(1)
        let f = r.app.frames[2]!
        XCTAssertEqual(b.geom, tile, "mango's tile stays")
        XCTAssertEqual(f.width, 1100)
        let right = r.server.tiledClients(r.monitor).compactMap(\.geom).map(\.maxX).max()!
        XCTAssertEqual(f.maxX, right, "in from the edge, inside the outer gap as the other tiles")
        XCTAssertEqual(f.minY, tile.minY, "only moved the way it would have crossed")
        r.arrange()
        r.settle(1)
        XCTAssertEqual(r.app.frames[2], f, "the next arrange puts it there at once")
    }

    func testInwardOrigin() {
        let work = CGRect(x: 0, y: 37, width: 1728, height: 1080)
        XCTAssertEqual(MacWindowSystem.inwardOrigin(CGRect(x: 864, y: 600, width: 864, height: 500),
                                                    size: CGSize(width: 1000, height: 600), in: work),
                       CGPoint(x: 728, y: 517))
        XCTAssertEqual(MacWindowSystem.inwardOrigin(CGRect(x: 0, y: 37, width: 864, height: 500),
                                                    size: CGSize(width: 1000, height: 600), in: work),
                       CGPoint(x: 0, y: 37), "it fits: the tile's corner")
        XCTAssertEqual(MacWindowSystem.inwardOrigin(CGRect(x: 100, y: 37, width: 864, height: 500),
                                                    size: CGSize(width: 2000, height: 600), in: work).x,
                       0, "wider than the screen: from its left edge")
    }

    func testAWriteTheBusyAppDidNotTakeIsMadeAgain() {
        let r = EngineRig()
        let a = r.window(1, frame: CGRect(x: 300, y: 300, width: 400, height: 300))
        r.app.busy = true
        r.arrange()
        r.settle()
        XCTAssertEqual(r.app.frames[1], CGRect(x: 300, y: 300, width: 400, height: 300), "busy: not applied")
        r.app.busy = false
        r.settle(1.5)
        XCTAssertEqual(r.app.frames[1], a.geom, "put back where the layout has it")
    }

    func testAWindowOnAHiddenTagIsParked() {
        let r = EngineRig()
        r.window(1)
        let hidden = r.window(2, tags: 1 << 1)
        r.arrange()
        r.settle()
        XCTAssertTrue(hidden.parked)
        XCTAssertTrue(Hider.isParked(r.app.frames[2]!, in: r.screen.frame), "a sliver in a corner")
        XCTAssertEqual(r.app.writes.last { $0.id == 2 }?.setSize, false, "parking moves, it does not resize")
    }

    /// mango's clip_to_hide: a scroller column wholly off its monitor is hidden, not drawn on the next
    /// monitor (its clip box has a negative width, which CGRect's width would hide).
    func testAScrollerColumnWhollyOffItsMonitorIsHidden() {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .scroller
        for i: CGWindowID in 1...4 { r.window(i) }
        r.arrange()
        r.settle()
        let off = r.server.clientsAll.filter { !$0.geom.intersects(r.screen.frame) }
        XCTAssertFalse(off.isEmpty, "columns beyond the monitor")
        for c in off {
            XCTAssertTrue(c.isClipToHide, "\(c.id)")
            XCTAssertTrue(c.parked, "\(c.id)")
        }
        XCTAssertTrue(r.server.clientsAll.filter { $0.geom.intersects(r.screen.frame) }.allSatisfy { !$0.parked })
    }

    /// mango clips a column partly off its monitor at the monitor's edge. macOS cannot clip another app's
    /// window: it is drawn whole where no other monitor is beyond the edge, and parked where one is.
    func testAScrollerColumnAcrossTheEdgeIsParkedOnlyWhereAnotherMonitorIsBeyond() {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .scroller
        for i: CGWindowID in 1...4 { r.window(i) }
        r.arrange()
        r.settle()
        let sf = r.screen.frame
        let partly = r.server.clientsAll.filter { $0.geom.intersects(sf) && !sf.contains($0.geom) }
        XCTAssertFalse(partly.isEmpty, "a column across the monitor's edge")
        for c in partly {
            XCTAssertFalse(c.parked, "\(c.id): no monitor beyond the edge, drawn whole as mango shows it")
            XCTAssertEqual(r.app.frames[c.id]?.size, c.tile.size, "\(c.id): its own size")
        }

        let edge = partly[0]
        let right = edge.geom.maxX > sf.maxX
        let beyond = CGRect(x: right ? sf.maxX : sf.minX - 1920, y: 0, width: 1920, height: 1080)
        r.server.rebuildMonitors(screens: [r.screen, Screen(displayID: 2, name: "External", frame: beyond,
                                                              workArea: beyond, scale: 1, isMain: false)])
        r.server.arrangeAll(false)
        r.settle()
        XCTAssertTrue(edge.parked, "the part beyond the edge would be on the external monitor")
        let plate = (r.server.system as! FakeWindowSystem).plates[edge.id]
        XCTAssertEqual(plate, edge.tile.intersection(sf), "a plate where mango shows the clipped part")
        r.server.rebuildMonitors(screens: [r.screen])
        r.server.arrangeAll(false)
        r.settle()
        XCTAssertNil((r.server.system as! FakeWindowSystem).plates[edge.id], "no other monitor: the window itself again")
        XCTAssertFalse(edge.parked)
        XCTAssertTrue(r.server.clientsAll.filter { sf.contains($0.geom) }.allSatisfy { !$0.parked })
    }

    /// mango's client_draw_border cuts the border at the monitor's edge (compute_edge_offsets) where it
    /// clips the window; the port draws the border within that box.
    func testTheBorderIsCutAtTheMonitorsEdgeWhereMangoClips() {
        let r = EngineRig()
        r.server.renderBorder = true
        r.server.drawsOverlays = true
        r.server.config.borderpx = 4
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .scroller
        for i: CGWindowID in 1...3 { r.window(i) }
        let f = r.window(9, floating: true, frame: CGRect(x: 200, y: 200, width: 300, height: 200))
        r.arrange()
        r.settle()
        let specs = (r.server.system as! FakeWindowSystem).borderSpecs
        XCTAssertFalse(specs.filter { $0.id != f.id }.isEmpty)
        XCTAssertTrue(specs.filter { $0.id != f.id }.allSatisfy { $0.clip == r.screen.frame }, "the scroller's columns")
        XCTAssertNil(specs.first { $0.id == f.id }?.clip, "a floating window is not clipped")
    }

    /// The border is drawn where the window is shown: after the commit has written it, not where it was.
    func testTheBorderFollowsTheWindowTheCommitWrites() {
        let r = EngineRig()
        r.server.renderBorder = true
        r.server.drawsOverlays = true
        r.server.config.borderpx = 4
        let c = r.window(1, frame: CGRect(x: 50, y: 60, width: 300, height: 400))
        r.server.arrange(r.monitor, false, false)
        r.frame()
        let spec = (r.server.system as! FakeWindowSystem).borderSpecs.first { $0.id == c.id }
        XCTAssertEqual(spec?.frame, r.app.frames[1], "around the window where it is now")
        XCTAssertEqual(spec?.frame, c.tile)
    }

    /// wlroots shows the scene at the output commit: an arrange's resizes of one window (set_arrange_visible's,
    /// then the layout's) reach the app as one write, the last.
    func testAnArrangeWritesEachWindowOnceWhenTheFrameIsShown() {
        let r = EngineRig()
        r.window(1)
        r.arrange()
        let n = r.app.writes.count
        r.window(2)
        r.server.arrange(r.monitor, false, false)
        XCTAssertEqual(r.app.writes.count, n, "nothing before the frame is shown")
        r.frame()
        let after = r.app.writes.dropFirst(n)
        XCTAssertEqual(after.filter { $0.id == 1 }.count, 1)
        XCTAssertEqual(after.filter { $0.id == 2 }.count, 1)
        XCTAssertEqual(r.app.frames[2], r.server.clientByIdAll(2)!.tile)
    }

    func testAHiddenWindowThatComesBackIntoViewIsParkedAgainAtMostThreeTimes() {
        let r = EngineRig()
        r.window(1)
        let inView = CGRect(x: 12, y: 45, width: 1704, height: 1060)
        r.app.movesBackTo[2] = inView
        r.window(2, tags: 1 << 1, frame: inView)
        r.arrange()
        r.settle(0.2)
        XCTAssertEqual(r.app.writes.filter { $0.id == 2 }.count, 4, "parked, then three more tries")
        r.app.movesBackTo[2] = nil
        _ = r.server.dispatch(Dispatch(name: "view", args: ["2"]))
        r.settle()
        XCTAssertFalse(r.server.clientByIdAll(2)!.parked)
        _ = r.server.dispatch(Dispatch(name: "view", args: ["1"]))
        r.settle()
        XCTAssertTrue(Hider.isParked(r.app.frames[2]!, in: r.screen.frame), "hidden again: parked again")
    }

    func testAParkedWindowThatMovesItselfIntoViewIsParkedAgain() {
        let r = EngineRig()
        r.window(1)
        let hidden = r.window(2, tags: 1 << 1)
        r.arrange()
        r.settle()
        let inView = CGRect(x: 12, y: 45, width: 800, height: 600)
        r.app.frames[2] = inView
        hidden.ignoreMovesUntil = 0
        r.server.mac.windowGeometryChanged(id: 2, frame: inView, resized: false, isfullscreen: nil)
        r.settle()
        XCTAssertTrue(Hider.isParked(r.app.frames[2]!, in: r.screen.frame))
        XCTAssertTrue(hidden.parked)
    }

    func testAFloatingWindowKeepsItsFrame() {
        let r = EngineRig()
        let f = CGRect(x: 400, y: 300, width: 500, height: 400)
        let c = r.window(1, floating: true, frame: f)
        r.window(2)
        r.arrange()
        r.settle()
        XCTAssertEqual(r.app.frames[1], f)
        XCTAssertEqual(c.frame, f)
    }

    func testAnAppThatMovesItselfRightAfterOurWriteIsRecordedThenPutBack() {
        let r = EngineRig()
        let a = r.window(1)
        r.window(2)
        r.arrange()
        r.settle()
        let target = a.geom
        let writes = r.app.writes.count
        let moved = target.offsetBy(dx: 40, dy: 30)
        r.app.frames[1] = moved
        r.server.mac.windowGeometryChanged(id: 1, frame: moved, resized: false, isfullscreen: nil)
        XCTAssertEqual(a.frame, moved, "recorded at once, so the border follows")
        XCTAssertEqual(r.app.writes.count, writes, "not reacted to inside the write's own window")
        r.settle(1.0)
        XCTAssertEqual(r.app.frames[1], target, "put back where the layout has it")
    }

    func testAnAppThatAppliesSizesLateTeachesNoMinimumSize() {
        let r = EngineRig()
        let a = r.window(1)
        r.arrange()
        r.settle()
        let whole = a.geom
        r.app.appliesAfter = 0.3
        r.window(2)
        r.arrange()
        let tile = a.geom
        XCTAssertLessThan(tile.width, whole.width)
        r.settle(3)
        XCTAssertEqual(a.geom, tile, "the layout kept its tile")
        XCTAssertEqual(r.app.frames[1], tile, "and the window has it")
    }

    func testAnOldFrameLearnedAsAMinimumIsForgotten() {
        let r = EngineRig()
        let a = r.window(1)
        r.app.minSize[1] = CGSize(width: 900, height: 400)
        r.app.appliesAfter = 0.3
        r.arrange()
        r.settle(1.5)
        for id: CGWindowID in [2, 3, 4] { r.window(id) }
        r.arrange()
        r.settle(2)
        XCTAssertNil(a.mac.refusedSize, "it took its tile: no minimum")
        r.server.clients.append(r.server.clients.removeFirst())
        r.arrange()
        r.settle(4)
        let bounds = r.server.mac.layoutBounds(r.monitor)
        XCTAssertEqual(r.app.frames[1]?.size, CGSize(width: 900, height: 400))
        XCTAssertEqual(r.app.frames[1]?.maxX, bounds.maxX, "in from the right edge")
        XCTAssertEqual(r.app.frames[1]?.maxY, bounds.maxY, "in from the bottom edge")
    }

}

@MainActor
final class ScratchpadPlaceTests: MangoTestCase {
    func rig() -> EngineRig {
        let r = EngineRig()
        r.window(1)
        r.window(2)
        r.arrange()
        r.server.clientFocus(r.server.clientByIdAll(2)!, true)
        _ = r.server.dispatch(Dispatch(name: "minimized", args: []))
        return r
    }

    func toggle(_ r: EngineRig) { _ = r.server.dispatch(Dispatch(name: "toggle_scratchpad", args: [])) }

    func testRestoringAMinimizedWindowForgetsItsPlace() {
        let r = rig()
        let c = r.server.clientByIdAll(2)!
        c.iscustomsize = true
        _ = r.server.dispatch(Dispatch(name: "restore_minimized", args: []))
        XCTAssertFalse(c.isInScratchpad)
        XCTAssertFalse(c.iscustomsize, "as mango, for whichever window it restores")
    }

}
