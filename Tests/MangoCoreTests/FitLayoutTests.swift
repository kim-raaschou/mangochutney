import XCTest
@testable import Mango
@testable import Port

@MainActor
final class FitLayoutTests: MangoTestCase {
    func rig(level: Int, min: [CGWindowID: CGSize], layout: LayoutKind = .tile, windows: CGWindowID = 3) -> EngineRig {
        let r = EngineRig()
        r.server.config.chutneyOverlapWarning = true
        r.server.config.chutneyFitLayout = level
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = layout
        for id: CGWindowID in 1...windows { r.window(id) }
        for c in r.server.tiledClients(r.monitor) { r.server.setSizePer(r.monitor, c) }   // as mango maps a window
        for (id, size) in min { r.app.minSize[id] = size }
        r.arrange()
        r.settle(1.5)
        return r
    }

    func fake(_ r: EngineRig) -> FakeWindowSystem { r.server.system as! FakeWindowSystem }

    func over(_ r: EngineRig) -> [ClientID] {
        r.server.tiledClients(r.monitor).filter { $0.refusedSize != nil }.map(\.id)
    }

    func fitted(_ r: EngineRig, file: StaticString = #filePath, line: UInt = #line) {
        MenuBarStatus.fit(r.server)
        r.settle(1.5)
        XCTAssertEqual(over(r), [], "fits", file: file, line: line)
        let frames = r.server.tiledClients(r.monitor).compactMap { r.app.frames[$0.id] }
        for (i, a) in frames.enumerated() {
            for b in frames[(i + 1)...] { XCTAssertFalse(a.intersects(b), "\(a) \(b)", file: file, line: line) }
        }
    }

    func testOffChangesNothing() {
        let r = rig(level: 0, min: [1: CGSize(width: 1100, height: 0)])
        XCTAssertEqual(over(r), [1])
        XCTAssertNil(MenuBarStatus.fitTitle(r.server))
        XCTAssertNil(fake(r).nagArgv)
    }

    func testTheMenuOffersWhatTheWindowLacks() {
        let r = rig(level: 1, min: [1: CGSize(width: 1100, height: 0)])
        let lack = Int((1100 - r.server.clientByIdAll(1)!.geom.width).rounded(.up))
        XCTAssertEqual(MenuBarStatus.fitTitle(r.server), "Fit layout: Test \(lack) pt wider")
        fitted(r)
        XCTAssertGreaterThanOrEqual(r.server.clientByIdAll(1)!.geom.width, 1100 - 0.5)
        XCTAssertLessThan(r.server.clientByIdAll(1)!.geom.width, 1100 + 12, "no more than it needs")
    }

    func testAStackWindowGrowsToTheLeft() {
        let r = rig(level: 1, min: [2: CGSize(width: 1000, height: 0)])
        XCTAssertEqual(over(r), [2])
        XCTAssertNil(r.server.dispatch(Dispatch(name: "chutney_fit_layout")))
        r.settle(1.5)
        XCTAssertEqual(over(r), [])
        XCTAssertLessThan(r.server.clientByIdAll(1)!.geom.width, 948, "the master gives the room")
    }

    func testAHeightInTheStack() {
        let r = rig(level: 1, min: [2: CGSize(width: 0, height: 900)])
        XCTAssertEqual(over(r), [2])
        XCTAssertTrue(MenuBarStatus.fitTitle(r.server)?.hasSuffix("pt taller") == true)
        fitted(r)
    }

    func testTheLowestInTheStackGrowsUp() {
        let r = rig(level: 1, min: [3: CGSize(width: 0, height: 900)])
        fitted(r)
    }

    func testAWidthAndAHeight() {
        let r = rig(level: 1, min: [1: CGSize(width: 1100, height: 0), 2: CGSize(width: 0, height: 600)])
        XCTAssertEqual(Set(over(r)), [1, 2])
        fitted(r)
    }

    func testNoRoomNoFit() {
        let r = rig(level: 1, min: [1: CGSize(width: 1000, height: 0), 2: CGSize(width: 1000, height: 0)])
        XCTAssertEqual(Set(over(r)), [1, 2])
        XCTAssertNil(FitLayout.plan(r.server, r.monitor), "1000 + 1000 is more than the screen")
        XCTAssertNil(MenuBarStatus.fitTitle(r.server))
        let tiles = r.server.tiledClients(r.monitor).map(\.geom)
        _ = r.server.dispatch(Dispatch(name: "chutney_fit_layout"))
        XCTAssertEqual(r.server.tiledClients(r.monitor).map(\.geom), tiles)
    }

    func testNoRoomInTheHeight() {
        let r = rig(level: 1, min: [2: CGSize(width: 0, height: 600), 3: CGSize(width: 0, height: 600)])
        XCTAssertNil(FitLayout.plan(r.server, r.monitor), "600 + 600 is more than the stack")
    }

    func testFair() {
        let r = rig(level: 1, min: [2: CGSize(width: 1000, height: 0)], layout: .fair, windows: 4)
        XCTAssertEqual(over(r), [2])
        fitted(r)
    }

    func testGrid() {
        let r = rig(level: 1, min: [1: CGSize(width: 0, height: 700)], layout: .grid, windows: 4)
        XCTAssertEqual(over(r), [1])
        fitted(r)
    }

    /// 1 | 4 over 3, beside 2: 4 is the second of its split, not at the layout's edge. mango's resizewin
    /// moves that split, so its far border out shrinks it; the near one grows it.
    func testDwindleTheWindowInTheMiddle() {
        let r = rig(level: 1, min: [4: CGSize(width: 573, height: 0)], layout: .dwindle, windows: 4)
        let g = { (id: ClientID) in r.server.clientByIdAll(id)!.geom }
        XCTAssertTrue(g(1).maxX < g(4).minX && g(4).maxX < g(2).minX, "4 between 1 and 2")
        XCTAssertEqual(over(r), [4])
        XCTAssertNotNil(FitLayout.plan(r.server, r.monitor))
        fitted(r)
        XCTAssertGreaterThanOrEqual(g(4).width, 573 - 0.5)
        XCTAssertNil(r.server.clientByIdAll(4)!.refusedSize)
    }

    func testTheScroller() {
        let r = EngineRig()
        r.server.config.chutneyFitLayout = 1
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .scroller
        for id: CGWindowID in 1...3 { r.window(id) }
        for c in r.server.tiledClients(r.monitor) { r.server.setSizePer(r.monitor, c) }
        r.app.minSize[2] = CGSize(width: 1600, height: 0)
        r.server.clientFocus(r.server.clientByIdAll(2)!, true)
        r.arrange()
        r.settle(1.5)
        XCTAssertEqual(over(r), [2])
        XCTAssertNotNil(FitLayout.plan(r.server, r.monitor))
        MenuBarStatus.fit(r.server)
        r.settle(1.5)
        XCTAssertEqual(over(r), [])
    }

    func testInMonocleTheScreenIsAllThereIs() {
        let r = EngineRig()
        r.server.config.chutneyFitLayout = 1
        r.server.config.monocleTabMode = false
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .monocle
        for id: CGWindowID in 1...3 { r.window(id) }
        r.app.minSize[3] = CGSize(width: 2000, height: 0)
        r.monitor.sel = r.server.clientByIdAll(3)
        r.arrange()
        r.settle(1.5)
        XCTAssertEqual(over(r), [3])
        XCTAssertNil(FitLayout.plan(r.server, r.monitor))
    }

    func testANotificationOffersTheFitOnce() {
        let r = rig(level: 2, min: [1: CGSize(width: 1100, height: 0)])
        let note = try! XCTUnwrap(fake(r).fitNotification)
        XCTAssertEqual(note.title, "Test larger than its tile")
        XCTAssertTrue(note.body.hasPrefix("Fit layout: Test "), note.body)
        XCTAssertNil(fake(r).nagArgv, "no bar")
        XCTAssertEqual(over(r), [1], "not by itself")
        fake(r).fitNotification = nil
        FitLayout.notify(r.server, FitLayout.plan(r.server, r.monitor))
        XCTAssertNil(fake(r).fitNotification, "the same fit is not offered again")
    }

    func testANotificationSaysWhereThereIsNoRoom() {
        let r = rig(level: 2, min: [1: CGSize(width: 1000, height: 0), 2: CGSize(width: 1000, height: 0)])
        let note = try! XCTUnwrap(fake(r).fitNotification)
        XCTAssertEqual(note.title, "Test larger than its tile")
        XCTAssertTrue(note.body.hasPrefix("No room in this layout: Test needs 1000 pt width, Test needs 1000 pt width."), note.body)
        XCTAssertFalse(note.fit, "no Fit button")
        _ = r.server.dispatch(Dispatch(name: "tagsilent", args: ["2"]), target: r.server.clientByIdAll(2)!)
        r.settle(1.5)
        XCTAssertEqual(fake(r).fitNotification?.fit, true, "with one of them gone there is room: the fit is offered")
    }

    /// A stack of four, two of them taller than their tiles: mango's resizewin gives a stack window its
    /// height from all the others in the stack, the other one too, so neither fit is kept.
    func testAFitThatTakesFromAnotherWindowOverIsPutBack() {
        let r = rig(level: 2, min: [2: CGSize(width: 0, height: 400), 3: CGSize(width: 0, height: 380)], windows: 5)
        XCTAssertEqual(Set(over(r)), [2, 3])
        XCTAssertNotNil(FitLayout.plan(r.server, r.monitor), "the column has room for 400 + 380")
        let tiles = r.server.tiledClients(r.monitor).map(\.geom)
        FitLayout.fit(r.server)
        let back = r.server.tiledClients(r.monitor).map(\.geom)
        XCTAssertEqual(back.count, tiles.count)
        for (b, t) in zip(back, tiles) {   // within a pixel: mango's tile rounds each share down
            XCTAssertEqual(b.minX, t.minX, accuracy: 1, "put back"); XCTAssertEqual(b.minY, t.minY, accuracy: 1, "put back")
            XCTAssertEqual(b.width, t.width, accuracy: 1, "put back"); XCTAssertEqual(b.height, t.height, accuracy: 1, "put back")
        }
        r.settle(1.5)
        XCTAssertNil(FitLayout.plan(r.server, r.monitor), "not offered again")
        XCTAssertEqual(fake(r).fitNotification?.fit, false, "the notification says there is no room")
    }

    /// A window that was larger than its tile and fits now still needs that size: no fit is offered that
    /// would take it from it.
    func testTheLeastSizeAWindowWasKeptAtIsRemembered() {
        let r = rig(level: 1, min: [4: CGSize(width: 0, height: 400)], windows: 5)
        XCTAssertEqual(over(r), [4])
        fitted(r)
        XCTAssertEqual(r.server.mac.fitState.minimum[4]?.height, 400)
        r.app.minSize[2] = CGSize(width: 0, height: 700)
        _ = r.server.dispatch(Dispatch(name: "setmfact", args: ["+0.05"]))
        r.settle(1.5)
        XCTAssertEqual(over(r), [2])
        XCTAssertNil(FitLayout.plan(r.server, r.monitor), "700 + the 400 window 4 needs is more than the stack")
        r.server.mac.fitState.minimum = [:]
        XCTAssertNotNil(FitLayout.plan(r.server, r.monitor), "without it the stack looks like it has room")
    }

    func testAClosedWindowIsForgotten() {
        let r = rig(level: 1, min: [4: CGSize(width: 0, height: 400)], windows: 5)
        _ = FitLayout.plan(r.server, r.monitor)
        XCTAssertNotNil(r.server.mac.fitState.minimum[4])
        r.server.mac.windowDestroyed(id: 4)
        _ = FitLayout.plan(r.server, r.monitor)
        XCTAssertNil(r.server.mac.fitState.minimum[4])
    }

    func testNotWhileTheWindowsMove() {
        let r = rig(level: 2, min: [2: CGSize(width: 1000, height: 0)])
        r.server.config.animations = true
        XCTAssertNotNil(fake(r).fitNotification)
        fake(r).fitNotification = nil
        _ = r.server.dispatch(Dispatch(name: "setmfact", args: ["+0.05"]))
        XCTAssertTrue(r.server.mac.animationsRunning, "the layout moves")
        FitLayout.statusChanged(r.server)
        XCTAssertNil(fake(r).fitNotification, "nothing while they move")
        r.settle(1.5)
        XCTAssertFalse(r.server.mac.animationsRunning)
        XCTAssertNotNil(fake(r).fitNotification, "told when they stand still")
    }

    func testNoRoomAtLevelOneSaysNothing() {
        let r = rig(level: 1, min: [1: CGSize(width: 1000, height: 0), 2: CGSize(width: 1000, height: 0)])
        XCTAssertNil(fake(r).fitNotification)
    }

    func testANotificationForAWindowAlreadyOverWhenTheLevelIsSet() {
        let r = rig(level: 0, min: [1: CGSize(width: 1100, height: 0)])
        XCTAssertEqual(over(r), [1])
        XCTAssertNil(r.server.dispatch(Dispatch(name: "setoption", args: ["chutney_fit_layout", "2"])))
        r.settle(0.5)
        XCTAssertNotNil(fake(r).fitNotification, "no window has to refuse its size again")
    }

    func testTheNotificationsFitFitsAndIsTakenAway() {
        let r = rig(level: 2, min: [1: CGSize(width: 1100, height: 0)])
        XCTAssertNotNil(fake(r).fitNotification)
        FitLayout.fit(r.server)
        r.settle(1.5)
        XCTAssertEqual(over(r), [])
        XCTAssertNil(fake(r).fitNotification, "nothing left to fit")
    }

    func testByItselfItFits() {
        let r = rig(level: 3, min: [1: CGSize(width: 1100, height: 0)])
        r.settle(1.5)
        XCTAssertEqual(over(r), [])
    }

    func testByItselfNothingWhereThereIsNoRoom() {
        let r = rig(level: 3, min: [1: CGSize(width: 1000, height: 0), 2: CGSize(width: 1000, height: 0)])
        r.settle(3)
        XCTAssertEqual(Set(over(r)), [1, 2], "left as mango leaves it; the tag stays orange")
    }

    func testByItselfTwoWindowsInOneRow() {
        let r = rig(level: 3, min: [1: CGSize(width: 1000, height: 0), 2: CGSize(width: 700, height: 0)])
        r.settle(4)
        let tiles = r.server.tiledClients(r.monitor).map(\.geom)
        r.settle(2)
        XCTAssertEqual(r.server.tiledClients(r.monitor).map(\.geom), tiles, "settled")
        XCTAssertEqual(over(r), [], "1000 + 700 fits the screen")
    }

    func testTheMenuBarIsToldWhenAWindowGoesOver() {
        let r = EngineRig()
        var told = 0
        r.server.onStateChange = { told += 1 }
        for id: CGWindowID in 1...2 { r.window(id) }
        r.app.minSize[1] = CGSize(width: 1100, height: 0)
        r.arrange()
        told = 0
        r.settle(1.5)
        XCTAssertGreaterThan(told, 0)
    }

    func testInMonocleOnlyTheWindowShownCounts() {
        let r = EngineRig()
        r.server.config.monocleTabMode = false
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .monocle
        for id: CGWindowID in 1...3 { r.window(id) }
        r.app.minSize[3] = CGSize(width: 2000, height: 0)
        r.monitor.sel = r.server.clientByIdAll(1)
        r.arrange()
        r.settle(1.5)
        XCTAssertNotNil(r.server.clientByIdAll(3)!.refusedSize, "larger than the screen")
        XCTAssertEqual(FitLayout.shown(r.server, r.monitor).map(\.id), [1], "under the one shown")
        r.monitor.sel = r.server.clientByIdAll(3)
        XCTAssertEqual(FitLayout.shown(r.server, r.monitor).map(\.id), [3], "shown now")
    }

    func testAWindowOverItsNeighbourMarksItsTagOrange() {
        let r = rig(level: 0, min: [1: CGSize(width: 1100, height: 0)])
        XCTAssertEqual(MenuBarStatus.monitors(r.server)[0].tags.first?.overlap, true)
        r.server.config.chutneyOverlapWarning = false
        XCTAssertEqual(MenuBarStatus.monitors(r.server)[0].tags.first?.overlap, false, "without the key nothing is marked")
    }

    func testAWindowMovedAwayNoLongerMarksTheTag() {
        let r = rig(level: 0, min: [1: CGSize(width: 1100, height: 0)])
        _ = r.server.dispatch(Dispatch(name: "tagsilent", args: ["2"]), target: r.server.clientByIdAll(1)!)
        XCTAssertEqual(MenuBarStatus.monitors(r.server)[0].tags.map(\.overlap), [false, false])
    }
}
