import XCTest
@testable import Mango
@testable import Port

/// arrange → write → read back → retry, against a fake app: the engine's path to the
/// real windows, which no other test reaches (without a write queue `place` returns early).
@MainActor
final class EngineWriteTests: MangoTestCase {

    /// Quitting brings the windows mango hid back into view, through each app's write
    /// queue; restarting leaves them hidden for the next mango.
    func testQuittingBringsHiddenWindowsBack() {
        let r = EngineRig()
        r.window(1)
        r.window(2, tags: 1 << 1)
        r.server.arrange(r.monitor, .none)
        r.settle()
        XCTAssertTrue(r.server.clientByIdAll(2)!.parked)
        r.app.writes.removeAll()
        r.server.cleanup()
        XCTAssertEqual(r.app.writes.map(\.id), [2], "only the hidden window")
        XCTAssertTrue(r.screen.workArea.contains(r.app.frames[2]!), "back on the screen")
    }

    /// A hidden window whose app is then hidden (⌘H) is away, out of the layout, but still in
    /// mango's corner: quitting brings it back as well.
    func testQuittingBringsBackAWindowAwayInACorner() {
        let r = EngineRig()
        r.window(1)
        let c = r.window(2, tags: 1 << 1)
        r.server.arrange(r.monitor, .none)
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
        r.server.arrange(r.monitor, .none)
        r.settle()
        r.app.writes.removeAll()
        r.server.mac.restarting = true
        r.server.cleanup()
        XCTAssertEqual(r.app.writes.count, 0)
    }

    func testTiledWindowsAreWrittenToTheirLayoutFramesOnce() {
        let r = EngineRig()
        let a = r.window(1), b = r.window(2)
        r.server.arrange(r.monitor, .none)
        r.settle()
        for c in [a, b] {
            XCTAssertEqual(r.app.frames[c.id], c.geom, "the window is where the layout put it")
            XCTAssertEqual(c.frame, r.app.frames[c.id], "and mango knows it")
            XCTAssertTrue(r.screen.workArea.contains(c.frame))
        }
        XCTAssertFalse(a.frame.intersects(b.frame.insetBy(dx: 1, dy: 1)))
        let writes = r.app.writes.count
        r.server.arrange(r.monitor, .none)
        r.settle()
        XCTAssertEqual(r.app.writes.count, writes, "nothing to write when everything is in place")
    }

    func testAWindowThatRefusesItsSizeIsTakenAsItIs() {
        let r = EngineRig()
        r.window(1)
        let b = r.window(2)
        r.app.minSize[2] = CGSize(width: 300, height: 1000)
        r.server.arrange(r.monitor, .none)
        r.settle()
        XCTAssertEqual(b.frame, r.app.frames[2], "the border follows the real window")
        XCTAssertGreaterThanOrEqual(b.frame.height, 1000)
    }

    /// A window that refuses its tile (its minimum size): mango's tile stays, the window
    /// overlaps its neighbour, and it is asked once more, not fought.
    func testARefusalKeepsMangosTileAndIsAskedOnceMore() {
        let r = EngineRig()
        r.window(1)
        let b = r.window(2)
        r.window(3)
        r.app.minSize[2] = CGSize(width: 0, height: 700)
        r.server.arrange(r.monitor, .none)
        let tile = b.geom!
        r.settle(4)
        XCTAssertEqual(b.geom, tile, "mango's tile, not moved for the window")
        XCTAssertEqual(r.app.frames[2]?.height, 700, "the window keeps its own size")
        XCTAssertEqual(r.app.writes.filter { $0.id == 2 }.count, 2, "one write and one more ask")
        XCTAssertLessThan(tile.height, 700)
    }

    /// Not in mango: a window larger than its tile never goes past the monitor's work area;
    /// from an edge it would cross it grows inward, mango's tile unchanged.
    func testARefusedWindowGrowsInwardFromTheScreenEdge() {
        let r = EngineRig()
        r.window(1)
        let b = r.window(2)
        r.app.minSize[2] = CGSize(width: 1100, height: 0)   // wider than the right-hand tile
        r.server.arrange(r.monitor, .none)
        let tile = b.geom!
        r.settle(1)
        let f = r.app.frames[2]!
        XCTAssertEqual(b.geom, tile, "mango's tile stays")
        XCTAssertEqual(f.width, 1100)
        let right = r.server.tiledClients(r.monitor).compactMap(\.geom).map(\.maxX).max()!
        XCTAssertEqual(f.maxX, right, "in from the edge, inside the outer gap as the other tiles")
        XCTAssertEqual(f.minY, tile.minY, "only moved the way it would have crossed")
        r.server.arrange(r.monitor, .none)
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
        r.server.arrange(r.monitor, .none)
        r.settle()
        XCTAssertEqual(r.app.frames[1], CGRect(x: 300, y: 300, width: 400, height: 300), "busy: not applied")
        r.app.busy = false
        // The read-back gets no answer, the window server has the old frame: a retry at
        // once (still busy) and the next one a second later (keepPlaced's rate limit).
        r.settle(1.5)
        XCTAssertEqual(r.app.frames[1], a.geom, "put back where the layout has it")
    }

    func testAWindowOnAHiddenTagIsParked() {
        let r = EngineRig()
        r.window(1)
        let hidden = r.window(2, tags: 1 << 1)
        r.server.arrange(r.monitor, .none)
        r.settle()
        XCTAssertTrue(hidden.parked)
        XCTAssertTrue(Hider.isParked(r.app.frames[2]!, in: r.screen.frame), "a sliver in a corner")
        XCTAssertEqual(r.app.writes.last { $0.id == 2 }?.setSize, false, "parking moves, it does not resize")
    }

    func testAHiddenWindowThatComesBackIntoViewIsParkedAgainAtMostThreeTimes() {
        let r = EngineRig()
        r.window(1)
        let inView = CGRect(x: 12, y: 45, width: 1704, height: 1060)
        r.app.movesBackTo[2] = inView   // Arc playing a video
        r.window(2, tags: 1 << 1, frame: inView)
        r.server.arrange(r.monitor, .none)
        r.settle(0.2)
        XCTAssertEqual(r.app.writes.filter { $0.id == 2 }.count, 4, "parked, then three more tries")
        r.app.movesBackTo[2] = nil
        r.server.clientByIdAll(2)!.parked = false   // the next arrange parks it again with a fresh budget
        r.server.clientByIdAll(2)!.parkRetries = 0
        r.server.arrange(r.monitor, .none)
        r.settle()
        XCTAssertTrue(Hider.isParked(r.app.frames[2]!, in: r.screen.frame))
    }

    func testAParkedWindowThatMovesItselfIntoViewIsParkedAgain() {
        let r = EngineRig()
        r.window(1)
        let hidden = r.window(2, tags: 1 << 1)
        r.server.arrange(r.monitor, .none)
        r.settle()
        let inView = CGRect(x: 12, y: 45, width: 800, height: 600)
        r.app.frames[2] = inView
        hidden.ignoreMovesUntil = 0
        r.server.mac.windowGeometryChanged(id: 2, frame: inView, resized: false, isFullscreen: nil)
        r.settle()
        XCTAssertTrue(Hider.isParked(r.app.frames[2]!, in: r.screen.frame))
        XCTAssertTrue(hidden.parked)
    }

    func testAFloatingWindowKeepsItsFrame() {
        let r = EngineRig()
        let f = CGRect(x: 400, y: 300, width: 500, height: 400)
        let c = r.window(1, floating: true, frame: f)
        r.window(2)
        r.server.arrange(r.monitor, .none)
        r.settle()
        XCTAssertEqual(r.app.frames[1], f)
        XCTAssertEqual(c.frame, f)
    }

    func testAnAppThatMovesItselfRightAfterOurWriteIsRecordedThenPutBack() {
        let r = EngineRig()
        let a = r.window(1)
        r.window(2)
        r.server.arrange(r.monitor, .none)
        r.settle()
        let target = a.geom!
        let writes = r.app.writes.count
        let moved = target.offsetBy(dx: 40, dy: 30)   // Teams repositioning itself
        r.app.frames[1] = moved
        r.server.mac.windowGeometryChanged(id: 1, frame: moved, resized: false, isFullscreen: nil)
        XCTAssertEqual(a.frame, moved, "recorded at once, so the border follows")
        XCTAssertEqual(r.app.writes.count, writes, "not reacted to inside the write's own window")
        r.settle(1.0)   // the read-back just after ignoreMovesUntil
        XCTAssertEqual(r.app.frames[1], target, "put back where the layout has it")
    }

    /// An app that applies a size late (Electron: Claude, VS Code) answers right after
    /// each write with its old frame, the size the layout before gave it. That is not a
    /// minimum size: by the late read-back it has taken the new one.
    func testAnAppThatAppliesSizesLateTeachesNoMinimumSize() {
        let r = EngineRig()
        let a = r.window(1)
        r.server.arrange(r.monitor, .none)
        r.settle()
        let whole = a.geom!
        r.app.appliesAfter = 0.3
        r.window(2)   // a stack beside it: a narrower tile
        r.server.arrange(r.monitor, .none)
        let tile = a.geom!
        XCTAssertLessThan(tile.width, whole.width)
        r.settle(3)
        XCTAssertEqual(a.geom, tile, "the layout kept its tile")
        XCTAssertEqual(r.app.frames[1], tile, "and the window has it")
    }

}

/// mango's show_scratchpad: a scratchpad is sized by the ratios and centred the first time
/// it is shown, then keeps the place it is put in.
@MainActor
final class ScratchpadPlaceTests: MangoTestCase {
    func rig() -> EngineRig {
        let r = EngineRig()
        r.window(1)
        r.window(2)
        r.server.arrange(r.monitor, .none)
        r.server.clientFocus(r.server.clientByIdAll(2)!)
        _ = r.server.dispatch(Dispatch(name: "minimized", args: []))
        return r
    }

    func toggle(_ r: EngineRig) { _ = r.server.dispatch(Dispatch(name: "toggle_scratchpad", args: [])) }

    func testAMovedScratchpadComesBackWhereItWasPut() {
        let r = rig()
        toggle(r)
        let c = r.server.clientByIdAll(2)!
        let w = r.screen.workArea
        XCTAssertEqual(c.geom?.width, (w.width * CGFloat(r.server.config.scratchpadWidthRatio)).rounded(), "first time: the ratio")
        XCTAssertEqual(c.geom!.midX, w.midX, accuracy: 1, "and centred")
        let first = c.geom!
        _ = r.server.dispatch(Dispatch(name: "movewin", args: ["-100", "-50"]), target: c)
        let moved = c.geom!
        XCTAssertNotEqual(moved, first, "the move holds (it was centred again before)")
        toggle(r)   // hidden
        toggle(r)   // shown again
        XCTAssertEqual(c.geom, moved, "where it was put, as in mango")
    }

    /// mango switch_scratchpad_client_state: shown on another display, its place is scaled
    /// to that display's work area and centred there.
    func testOnAnotherDisplayItIsScaledAndCentred() {
        let r = rig()
        let big = Screen(displayID: 2, name: "Big", frame: CGRect(x: 1728, y: 0, width: 2560, height: 1440),
                         workArea: CGRect(x: 1728, y: 25, width: 2560, height: 1415), scale: 2, isMain: false)
        r.server.rebuildMonitors(screens: [r.screen, big])
        r.server.config.scratchpadCrossMonitor = true
        toggle(r)
        let c = r.server.clientByIdAll(2)!
        _ = r.server.dispatch(Dispatch(name: "movewin", args: ["-100", "-50"]), target: c)
        let small = c.floatGeom
        toggle(r)
        r.server.selectedMonitor = r.server.monitors.first { $0.screen.displayID == 2 }!
        toggle(r)
        XCTAssertTrue(c.mon === r.server.selectedMonitor)
        XCTAssertEqual(c.floatGeom.width, (small.width * 2560 / r.screen.workArea.width).rounded(.down), accuracy: 1)
        XCTAssertEqual(c.floatGeom.midX, big.workArea.midX, accuracy: 1, "centred on the new display")
        XCTAssertEqual(c.floatGeom.midY, big.workArea.midY, accuracy: 1)
    }

    func testRestoringAMinimizedWindowForgetsItsPlace() {
        let r = rig()
        let c = r.server.clientByIdAll(2)!
        c.isCustomSize = true
        _ = r.server.dispatch(Dispatch(name: "restore_minimized", args: []))
        XCTAssertFalse(c.isInScratchpad)
        XCTAssertFalse(c.isCustomSize, "as mango, for whichever window it restores")
    }

    func testAScratchpadTakenOutIsSizedAnew() {
        let r = rig()
        toggle(r)
        let c = r.server.clientByIdAll(2)!
        _ = r.server.dispatch(Dispatch(name: "movewin", args: ["-100", "-50"]), target: c)
        _ = r.server.dispatch(Dispatch(name: "restore_minimized", args: []), target: c)
        XCTAssertFalse(c.isCustomSize, "out of the scratchpad")
        r.server.clientFocus(c)
        _ = r.server.dispatch(Dispatch(name: "minimized", args: []))
        toggle(r)
        XCTAssertEqual(c.geom!.midX, r.screen.workArea.midX, accuracy: 1, "centred again")
    }
}
