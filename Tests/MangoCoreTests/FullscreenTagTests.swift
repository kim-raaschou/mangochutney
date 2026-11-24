import XCTest
@testable import Mango
@testable import Port

/// Port extension chutney_fullscreen_tag: a window in macOS fullscreen has its own tag, F1–F12 above
/// mango's tags, as it has its own Space.
@MainActor
final class FullscreenTagTests: MangoTestCase {
    let f1: UInt32 = 1 << 9

    func rig(on: Bool = true) -> EngineRig {
        let r = EngineRig()
        r.server.config.chutneyFullscreenTag = on
        for id: CGWindowID in 1...3 { r.window(id) }
        r.arrange()
        r.settle(1)
        return r
    }

    func fake(_ r: EngineRig) -> FakeWindowSystem { r.server.system as! FakeWindowSystem }
    func viewed(_ r: EngineRig) -> UInt32 { r.monitor.tagset[r.monitor.seltags] }
    func before(_ r: EngineRig) -> UInt32 { r.monitor.tagset[r.monitor.seltags ^ 1] }
    func onTag1(_ r: EngineRig) -> [ClientID] { r.server.clients.filter { $0.tags == 1 }.map(\.id) }
    func mask(_ r: EngineRig) -> UInt32 { FullscreenTag.mask(r.server.config) }
    func home(_ r: EngineRig, _ id: ClientID) -> FullscreenTag.Home? { r.server.mac.fullscreenTag.homes[id] }

    func fullscreen(_ r: EngineRig, _ id: ClientID, _ on: Bool) {
        let c = r.server.clientByIdAll(id)!
        r.server.mac.windowGeometryChanged(id: id, frame: c.frame, resized: true, isfullscreen: on)
        r.settle(1)
    }

    func discover(_ r: EngineRig, _ id: CGWindowID, fullscreen: Bool = false, hidden: Bool = false) {
        r.server.mac.windowDiscovered(DiscoveredWindow(
            id: id, pid: getpid(), element: r.app.element(for: id), bundleId: "test", appName: "Test", title: "t\(id)",
            subrole: "AXStandardWindow", isDialog: false, frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            isminimized: false, isfullscreen: fullscreen, isAppHidden: hidden))
    }

    /// At start an app may not yet say its window is in macOS fullscreen: the first scan reads it again,
    /// and the window found as a normal one is then on its F tag.
    func testAWindowFoundInFullscreenOnlyOnTheSecondReadIsOnItsFTag() {
        let r = rig()
        discover(r, 4)
        r.settle()
        XCTAssertEqual(r.server.clientByIdAll(4)?.tags, 1)
        r.server.mac.windowFullscreen(id: 4, fullscreen: true)
        r.settle()
        let c = r.server.clientByIdAll(4)
        XCTAssertEqual(c?.tags, f1, "on F1")
        XCTAssertEqual(c.map { r.server.mac.nativeFullscreen($0) }, true)
    }

    // MARK: in and out

    func testInFullscreenItIsAloneOnF1() {
        let r = rig()
        let c = r.server.clientByIdAll(2)!
        let frames = r.app.frames
        fullscreen(r, 2, true)
        XCTAssertTrue(r.server.clientByIdAll(2) === c, "still mango's")
        XCTAssertEqual(c.tags, f1, "F1, above mango's tags")
        XCTAssertEqual(viewed(r), f1)
        XCTAssertEqual(before(r), 1, "the other view is the desktop's")
        XCTAssertEqual(onTag1(r), [1, 3], "the tag it left closes up")
        XCTAssertEqual(r.app.frames, frames, "nothing written: macOS places it, the desktop's windows stay")
        XCTAssertTrue(r.server.focused === c)
    }

    func testOutOfFullscreenItIsBackInItsPlace() {
        let r = rig()
        let c = r.server.clientByIdAll(2)!
        let tile = c.geom
        fullscreen(r, 2, true)
        fullscreen(r, 2, false)
        XCTAssertEqual(c.tags, 1)
        XCTAssertEqual(viewed(r), 1)
        XCTAssertEqual(before(r) & mask(r), 0, "no F tag to go back to")
        XCTAssertEqual(onTag1(r), [1, 2, 3], "its place")
        XCTAssertTrue(r.server.focused === c)
        r.server.mac.spaceChanged()
        r.settle(1)
        XCTAssertEqual(r.app.frames[2], tile, "on its tile once macOS is done")
        XCTAssertNil(home(r, 2))
    }

    /// As macOS does it: the window fills the screen in fullscreen and comes out where macOS puts it.
    func macOSFullscreen(_ r: EngineRig, _ id: ClientID, _ on: Bool, outAt: CGRect = CGRect(x: 300, y: 200, width: 700, height: 500)) {
        let f = on ? r.monitor.screen.frame : outAt
        r.app.frames[id] = f
        r.server.mac.windowGeometryChanged(id: id, frame: f, resized: true, isfullscreen: on)
        r.settle(1)
    }

    func testOutOfMacOSFullscreenItFallsIntoItsTile() {
        let r = rig()
        let tile = r.server.clientByIdAll(2)!.geom.insetBy(dx: r.server.clientByIdAll(2)!.bw, dy: r.server.clientByIdAll(2)!.bw)
        macOSFullscreen(r, 2, true)
        r.server.mac.spaceChanged()
        r.settle(1)
        macOSFullscreen(r, 2, false)
        r.server.mac.spaceChanged()
        r.settle(1)
        XCTAssertEqual(r.app.frames[2], tile, "back on its tile")
    }

    func testOutOfMacOSFullscreenOnATagNotViewedItIsParked() {
        let r = rig()
        macOSFullscreen(r, 2, true)
        r.server.mac.spaceChanged()
        r.settle(1)
        r.server.clientViewOnMonitor(Arg(ui: 1 << 3), true, r.monitor, true)
        r.settle(1)
        macOSFullscreen(r, 2, false)
        r.server.mac.spaceChanged()
        r.settle(1)
        XCTAssertTrue(Hider.isParked(r.app.frames[2]!, in: r.screen.frame), "hidden on a tag not viewed: \(r.app.frames[2]!)")
    }

    func testParkedBeforeMacOSFullscreenIsParkedAgainAfter() {
        let r = rig()
        r.server.clientViewOnMonitor(Arg(ui: 1 << 3), true, r.monitor, true)
        r.settle(1)
        XCTAssertTrue(r.server.clientByIdAll(2)!.parked, "on a tag not viewed")
        macOSFullscreen(r, 2, true)
        r.server.mac.spaceChanged()
        r.settle(1)
        r.server.clientViewOnMonitor(Arg(ui: 1 << 3), true, r.monitor, true)
        r.settle(1)
        macOSFullscreen(r, 2, false, outAt: CGRect(x: 20, y: 50, width: 1600, height: 1000))
        r.app.frames[2] = CGRect(x: 20, y: 50, width: 1600, height: 1000)   // macOS puts it back when its Space change ends
        r.server.mac.spaceChanged()
        r.settle(1)
        XCTAssertTrue(Hider.isParked(r.app.frames[2]!, in: r.screen.frame), "parked again: \(r.app.frames[2]!)")
    }

    /// macOS may be done with the Space change before the window says it is out of fullscreen, and then
    /// moves it back to where it stood: seen in view, it is parked again.
    func testOutOfMacOSFullscreenAfterItsSpaceChangeIsParkedWhereMacOSPutsIt() {
        let r = rig()
        macOSFullscreen(r, 2, true)
        r.server.mac.spaceChanged()
        r.settle(1)
        r.server.clientViewOnMonitor(Arg(ui: 1 << 3), true, r.monitor, true)
        r.settle(1)
        fake(r).onScreen = { $0 != 2 }   // macOS shows the desktop's Space
        r.server.mac.spaceChanged()
        r.settle(0.1)
        XCTAssertEqual(viewed(r), 1 << 3)
        macOSFullscreen(r, 2, false)
        XCTAssertTrue(Hider.isParked(r.app.frames[2]!, in: r.screen.frame), "parked as it comes out: \(r.app.frames[2]!)")
        let back = CGRect(x: 20, y: 50, width: 1600, height: 1000)
        r.app.frames[2] = back   // macOS puts it back where it stood before fullscreen
        r.server.mac.windowGeometryChanged(id: 2, frame: back, resized: false, isfullscreen: nil)
        r.settle(1)
        XCTAssertTrue(Hider.isParked(r.app.frames[2]!, in: r.screen.frame), "parked again: \(r.app.frames[2]!)")
    }

    /// macOS drops what it is told while it moves a window between Spaces: told to go out as it went in,
    /// the window stays in macOS fullscreen. Once the Space change is done mango's fullscreen is macOS's
    /// again, and the key takes it out.
    func testToldToGoOutWhileMacOSTookItInIsToldAgainByTheKey() {
        let r = rig()
        let c = r.server.clientByIdAll(2)!
        func toggle() { XCTAssertNil(r.server.dispatch(Dispatch(name: "chutney_toggle_fullscreen", args: ["1"]))) }
        r.server.clientFocus(c, true)
        toggle()
        macOSFullscreen(r, 2, true)
        toggle()   // macOS is on its way in: it drops this
        XCTAssertEqual(fake(r).fullscreenWrites.map(\.1), [true, false])
        r.server.mac.spaceChanged()
        r.server.mac.windowFullscreen(id: 2, fullscreen: true)
        r.settle(1)
        XCTAssertEqual(c.tags, f1, "still on its F tag: macOS has it in fullscreen")
        toggle()
        XCTAssertEqual(fake(r).fullscreenWrites.map(\.1), [true, false, false], "the key tells it again")
        macOSFullscreen(r, 2, false)
        XCTAssertEqual(c.tags, 1)
        XCTAssertFalse(c.isfullscreen)
        XCTAssertFalse(r.server.mac.fullscreenPending(c))
    }

    /// Told to go out, and macOS takes it out after its Space change: out, as macOS has it.
    func testToldToGoOutAndTakenOutAfterTheSpaceChange() {
        let r = rig()
        let c = r.server.clientByIdAll(2)!
        r.server.clientFocus(c, true)
        _ = r.server.dispatch(Dispatch(name: "chutney_toggle_fullscreen", args: ["1"]))
        macOSFullscreen(r, 2, true)
        _ = r.server.dispatch(Dispatch(name: "chutney_toggle_fullscreen", args: ["1"]))
        r.server.mac.spaceChanged()
        r.server.mac.windowFullscreen(id: 2, fullscreen: true)   // macOS still on its way out
        r.settle(1)
        XCTAssertFalse(c.isfullscreen, "not judged while macOS may still be on its way out")
        macOSFullscreen(r, 2, false)
        r.server.mac.spaceChanged()
        r.settle(1)
        XCTAssertEqual(c.tags, 1)
        XCTAssertFalse(c.isfullscreen)
        XCTAssertFalse(r.server.mac.fullscreenTag[c].scheduled)
        XCTAssertNil(home(r, 2))
        XCTAssertEqual(fake(r).fullscreenWrites.map(\.1), [true, false], "macOS is not told again")
    }

    func testOutOfFullscreenWhileAnotherTagIsViewedTheViewStays() {
        let r = rig()
        fullscreen(r, 2, true)
        r.server.clientViewOnMonitor(Arg(ui: 1 << 3), true, r.monitor, r.monitor === r.server.selectedMonitor)
        fullscreen(r, 2, false)
        XCTAssertEqual(viewed(r), 1 << 3)
        XCTAssertEqual(r.server.clientByIdAll(2)?.tags, 1)
        XCTAssertEqual(before(r) & mask(r), 0)
    }

    func testWithNoFreeFTagItIsOutOfTheLayout() {
        let r = rig()
        r.server.config.tagNum = 31
        fullscreen(r, 2, true)
        XCTAssertNil(r.server.clientByIdAll(2))
        XCTAssertEqual(r.server.mac.away[2]?.reasons, [.fullscreen])
    }

    func testOffItIsOutOfTheLayout() {
        let r = rig(on: false)
        fullscreen(r, 2, true)
        XCTAssertNil(r.server.clientByIdAll(2))
        XCTAssertEqual(viewed(r), 1)
    }

    func testANotAnsweringAppChangesNothing() {
        let r = rig()
        fullscreen(r, 2, true)
        r.server.mac.windowGeometryChanged(id: 2, frame: .zero, resized: true, isfullscreen: nil)
        XCTAssertEqual(r.server.clientByIdAll(2)?.tags, f1)
        XCTAssertEqual(viewed(r), f1)
    }

    // MARK: Spaces and views

    func testSpacesAndViewsFollowEachOther() {
        let r = rig()
        fullscreen(r, 2, true)
        fake(r).onScreen = { _ in false }
        r.server.mac.spaceChanged()
        XCTAssertEqual(viewed(r), 1, "out of its Space: the desktop's view")
        XCTAssertEqual(fake(r).anchored, 0, "macOS chose the Space: mango's own window is not taken")
        fake(r).onScreen = { $0 == 2 }
        r.server.mac.spaceChanged()
        XCTAssertEqual(viewed(r), f1, "into its Space again")
        XCTAssertEqual(before(r), 1)
    }

    func testFollowingMacOSBackToTheDesktopMovesNoFocus() {
        let r = rig()
        fullscreen(r, 2, true)
        fake(r).focused = []
        fake(r).onScreen = { _ in false }
        r.server.mac.spaceChanged()
        XCTAssertTrue(fake(r).focused.isEmpty, "no native focus that could take macOS to another Space")
    }

    func testMacOSFocusingItBeforeTheSpaceChangeViewsItsFTagNotTag9() {
        let r = rig()
        fullscreen(r, 2, true)
        _ = r.server.dispatch(Dispatch(name: "view", args: ["1"]))
        r.server.mac.windowFocused(id: 2)
        XCTAssertEqual(viewed(r), f1)
        XCTAssertEqual(before(r), 1, "the desktop's view is tag 1, not 9")
    }

    func testTwoInFullscreen() {
        let r = rig()
        fullscreen(r, 2, true)
        fullscreen(r, 3, true)
        XCTAssertEqual(r.server.clientByIdAll(3)?.tags, f1 << 1, "F2")
        XCTAssertEqual(viewed(r), f1 << 1)
        XCTAssertEqual(before(r), 1, "from one F tag to another the desktop's view stays")
        fake(r).onScreen = { $0 == 2 }
        r.server.mac.spaceChanged()
        XCTAssertEqual(viewed(r), f1)
        r.server.mac.spaceChanged()
        XCTAssertEqual(viewed(r), f1, "settled")
    }

    func testSplitViewTheFocusedSideIsViewed() {
        let r = rig()
        fullscreen(r, 2, true)
        fullscreen(r, 3, true)
        fake(r).onScreen = { $0 == 2 || $0 == 3 }
        r.server.mac.windowFocused(id: 2)
        r.server.mac.spaceChanged()
        XCTAssertEqual(viewed(r), f1, "the focused side")
        r.server.mac.windowFocused(id: 3)
        XCTAssertEqual(viewed(r), f1 << 1, "a click on the other side")
        r.server.mac.spaceChanged()
        XCTAssertEqual(viewed(r), f1 << 1, "settled")
    }

    func testAnEmptyTagFromFullscreenTakesMacOSBackToTheDesktop() {
        let r = rig()
        fullscreen(r, 2, true)
        _ = r.server.dispatch(Dispatch(name: "view", args: ["5"]))
        XCTAssertEqual(viewed(r), 1 << 4)
        XCTAssertEqual(fake(r).anchored, 1, "mango's own window on the desktop is focused")
        r.server.mac.windowFocused(id: 2)
        _ = r.server.dispatch(Dispatch(name: "view", args: ["1"]))
        XCTAssertEqual(fake(r).anchored, 1, "a tag with windows focuses one of them")
    }

    // MARK: the F tag is its window's alone

    func testMangosKeysFromTheDesktopDoNotReachIt() {
        let r = rig()
        fullscreen(r, 2, true)
        _ = r.server.dispatch(Dispatch(name: "view", args: ["1"]))
        _ = r.server.dispatch(Dispatch(name: "tag", args: ["10"]), target: r.server.clientByIdAll(1)!)
        XCTAssertEqual(r.server.clientByIdAll(1)?.tags, 1, "no other window goes onto F1")
        _ = r.server.dispatch(Dispatch(name: "view", args: ["1"]))
        _ = r.server.dispatch(Dispatch(name: "viewtoright"))
        XCTAssertEqual(viewed(r), 1 << 1)
    }

    func testTagFromItsFTagMovesItsOwnTag() {
        let r = rig()
        fullscreen(r, 2, true)
        _ = r.server.dispatch(Dispatch(name: "tagsilent", args: ["3"]), target: r.server.clientByIdAll(2)!)
        XCTAssertEqual(r.server.clientByIdAll(2)?.tags, f1, "it stays on F1")
        XCTAssertEqual(home(r, 2)?.tags, 1 << 2, "its own tag is now 3")
        fullscreen(r, 2, false)
        XCTAssertEqual(r.server.clientByIdAll(2)?.tags, 1 << 2)
    }

    func testToggletagFromItsFTagAddsToItsOwnTags() {
        let r = rig()
        fullscreen(r, 2, true)
        _ = r.server.dispatch(Dispatch(name: "toggletag", args: ["3"]), target: r.server.clientByIdAll(2)!)
        XCTAssertEqual(r.server.clientByIdAll(2)?.tags, f1)
        XCTAssertEqual(home(r, 2)?.tags, 1 | 1 << 2)
    }

    func testToggleviewFromAnFTagKeepsItAlone() {
        let r = rig()
        fullscreen(r, 2, true)
        _ = r.server.dispatch(Dispatch(name: "toggleview", args: ["3"]))
        XCTAssertEqual(viewed(r), f1, "no view of an F tag and a desktop tag at once")
    }

    func testAWindowOpenedMeanwhileGoesToTheDesktopsView() {
        let r = rig()
        fullscreen(r, 2, true)
        discover(r, 9)
        XCTAssertEqual(r.server.clientByIdAll(9)?.tags, 1, "F1 is its window's alone")
        XCTAssertEqual(r.server.clientByIdAll(2)?.tags, f1)
    }

    func testAWindowOpenedOnAnotherTagMeanwhileIsParkedBackOnTheDesktop() {
        let r = rig()
        fullscreen(r, 2, true)
        XCTAssertEqual(viewed(r), f1)
        discover(r, 9)
        let c = r.server.clientByIdAll(9)!
        c.tags = 1 << 2   // a rule's tag, not the one the desktop views
        r.server.arrange(r.monitor, false, false)
        r.settle(1)
        FullscreenTag.viewDesktop(r.server, r.monitor)
        r.settle(1)
        XCTAssertTrue(Hider.isParked(r.app.frames[9]!, in: r.screen.frame), "parked once the desktop is viewed: \(r.app.frames[9]!)")
    }

    // MARK: leaving mango

    func testClosedInFullscreenItsTagGoesAndItIsRememberedAtHome() {
        let r = rig()
        fullscreen(r, 2, true)
        r.server.mac.windowDestroyed(id: 2)
        r.settle(0.5)
        XCTAssertEqual(viewed(r), 1, "no empty F tag left viewed")
        XCTAssertEqual(before(r) & mask(r), 0, "nor one to go back to")
        XCTAssertNil(home(r, 2))
        XCTAssertEqual(r.server.mac.memory.departed.entries[2]?.tags, 1, "remembered on its own tag")
    }

    func testClosedWhileTheDesktopIsViewedLeavesNoFTagToGoBackTo() {
        let r = rig()
        fullscreen(r, 2, true)
        _ = r.server.dispatch(Dispatch(name: "view", args: ["1"]))
        r.server.mac.windowDestroyed(id: 2)
        r.settle(0.5)
        XCTAssertEqual(before(r) & mask(r), 0)
        XCTAssertEqual(r.server.mac.memory.currentLayout(r.server).previousTagsets?.values.first.map { $0 & mask(r) }, 0)
    }

    func testOverviewNeverLeavesTheDesktopsViewBehind() {
        let r = rig()
        fullscreen(r, 2, true)
        _ = r.server.dispatch(Dispatch(name: "toggleoverview"))
        r.server.mac.windowDestroyed(id: 2)
        _ = r.server.dispatch(Dispatch(name: "toggleoverview"))
        r.settle(0.5)
        XCTAssertEqual(viewed(r), 1)
        XCTAssertEqual(before(r) & mask(r), 0)
    }

    func testHiddenInFullscreenComesBackOnItsFTag() {
        let r = rig()
        fullscreen(r, 2, true)
        let c = r.server.clientByIdAll(2)!
        let written = r.app.frames[2]
        r.server.mac.appHidden(pid: c.pid, hidden: true)
        fake(r).axFullscreen = { $0 == 2 }
        r.server.mac.appHidden(pid: c.pid, hidden: false)
        r.settle(1)
        XCTAssertTrue(r.server.mac.nativeFullscreen(r.server.clientByIdAll(2)!))
        XCTAssertEqual(r.server.clientByIdAll(2)?.tags, f1)
        XCTAssertEqual(r.app.frames[2], written, "nothing written to it")
    }

    func testOutOfFullscreenWhileItsElementWasDead() {
        let r = rig()
        fullscreen(r, 2, true)
        r.server.mac.windowReacquired(id: 2, element: r.app.element(for: 2),
                                      state: ReacquiredState(frame: nil, minimized: false, fullscreen: false, appHidden: false))
        XCTAssertEqual(r.server.clientByIdAll(2)?.tags, 1)
        XCTAssertFalse(r.server.mac.nativeFullscreen(r.server.clientByIdAll(2)!))
    }

    // MARK: saved and found

    func testSavedOnItsOwnTagAndTheDesktopsView() {
        let r = rig()
        fullscreen(r, 2, true)
        let saved = r.server.mac.memory.currentLayout(r.server)
        XCTAssertEqual(saved.windows.first { $0.id == 2 }?.tags, 1)
        XCTAssertEqual(saved.tagsets.values.first, 1)
    }

    func testFoundInFullscreenAtTheStart() {
        let r = rig()
        fake(r).onScreen = { _ in false }
        discover(r, 9, fullscreen: true)
        XCTAssertEqual(r.server.clientByIdAll(9)?.tags, f1)
        XCTAssertEqual(viewed(r), 1, "not on screen: the view stays")
        XCTAssertNil(r.server.mac.away[9])
    }

    func testFoundHiddenAndInFullscreenComesBackOnItsFTag() {
        let r = rig()
        fake(r).onScreen = { _ in false }
        discover(r, 9, fullscreen: true, hidden: true)
        XCTAssertEqual(r.server.mac.away[9]?.reasons, [.hidden], "away for being hidden only")
        fake(r).axFullscreen = { $0 == 9 }
        r.server.mac.appHidden(pid: getpid(), hidden: false)
        XCTAssertEqual(r.server.clientByIdAll(9)?.tags, f1)
    }

    // MARK: the menu bar and keys

    func testTheMenuBarShowsItsApp() {
        let r = rig()
        fullscreen(r, 2, true)
        let f = MenuBarStatus.monitors(r.server)[0].tags.first { $0.label == "F1" }
        XCTAssertEqual(f?.app, getpid())
        XCTAssertEqual(f?.active, true)
        _ = r.server.dispatch(Dispatch(name: "view", args: ["1"]))
        MenuBarStatus.viewTag(r.server, monitor: r.monitor.screen.name, tag: 10)
        XCTAssertEqual(viewed(r), f1, "a click on it goes to it")
    }

    func testTheDispatcherViewsTheFTag() {
        let r = rig()
        fullscreen(r, 2, true)
        let c = r.server.clientByIdAll(2)!
        _ = r.server.dispatch(Dispatch(name: "view", args: ["1"]))
        XCTAssertNil(r.server.dispatch(Dispatch(name: "chutney_view_fullscreen", args: ["1"])))
        XCTAssertEqual(viewed(r), f1)
        XCTAssertTrue(r.server.focused === c)
        XCTAssertNil(r.server.dispatch(Dispatch(name: "chutney_view_fullscreen", args: ["2"])), "an empty F tag: nothing")
        XCTAssertEqual(viewed(r), f1)
        XCTAssertNotNil(r.server.dispatch(Dispatch(name: "chutney_view_fullscreen", args: ["13"])))
    }

    func testTheToggleDispatcher() {
        let r = rig()
        let c = r.server.clientByIdAll(2)!
        let f3 = f1 << 2, f5 = f1 << 4
        func toggle(_ n: Int) { XCTAssertNil(r.server.dispatch(Dispatch(name: "chutney_toggle_fullscreen", args: ["\(n)"]))) }
        r.server.clientFocus(c, true)
        toggle(3)
        XCTAssertTrue(c.isfullscreen, "into fullscreen")
        fullscreen(r, 2, true)
        XCTAssertEqual(c.tags, f3, "on the F tag asked for, not the first free")
        toggle(5)
        XCTAssertEqual(c.tags, f5, "moved to F5")
        XCTAssertEqual(viewed(r), f5)
        _ = r.server.dispatch(Dispatch(name: "view", args: ["1"]))
        let other = r.server.clientByIdAll(1)!
        r.server.clientFocus(other, true)
        toggle(5)
        XCTAssertEqual(viewed(r), f5, "another window's F tag: viewed")
        XCTAssertTrue(r.server.focused === c)
        XCTAssertFalse(other.isfullscreen)
        toggle(5)
        XCTAssertFalse(c.isfullscreen, "its own F tag: out")
        fullscreen(r, 2, false)
        XCTAssertEqual(c.tags, 1, "back on its tag")
        XCTAssertNil(home(r, 2))
    }

    // MARK: what the second review found

    func testAGlobalWindowInFullscreenDoesNotLoop() {
        let r = rig()
        fullscreen(r, 2, true)
        r.server.clientByIdAll(2)!.isglobal = true
        _ = r.server.dispatch(Dispatch(name: "view", args: ["1"]))
        XCTAssertEqual(viewed(r), 1, "mango keeps it on every view; the F tag's rule leaves it")
    }

    func testAnUnmanagedGlobalWindowBesideAnFTagDoesNotLoop() {
        let r = rig()
        r.server.clientByIdAll(1)!.isunglobal = true
        fullscreen(r, 2, true)
        XCTAssertEqual(viewed(r), f1)
    }

    func testToggletagTwiceFromItsFTagIsUndone() {
        let r = rig()
        fullscreen(r, 2, true)
        let c = r.server.clientByIdAll(2)!
        _ = r.server.dispatch(Dispatch(name: "toggletag", args: ["3"]), target: c)
        _ = r.server.dispatch(Dispatch(name: "toggletag", args: ["3"]), target: c)
        XCTAssertEqual(home(r, 2)?.tags, 1, "as mango's toggletag")
    }

    func testTagFromItsFTagFollowsItThere() {
        let r = rig()
        fullscreen(r, 2, true)
        _ = r.server.dispatch(Dispatch(name: "tag", args: ["3"]), target: r.server.clientByIdAll(2)!)
        XCTAssertEqual(home(r, 2)?.tags, 1 << 2)
        XCTAssertEqual(viewed(r), f1, "mango's tag follows the window: it is on F1 still")
    }

    func testFoundInFullscreenWhileAnotherFTagIsViewedKeepsADesktopTag() {
        let r = rig()
        fullscreen(r, 2, true)
        fake(r).onScreen = { $0 == 2 }
        discover(r, 9, fullscreen: true)
        XCTAssertEqual(home(r, 9)?.tags, 1, "the desktop's view, not F1")
        fullscreen(r, 9, false)
        XCTAssertEqual(r.server.clientByIdAll(9)?.tags, 1)
    }

    func testAMissedEnterOffScreenDoesNotTakeMacOSThere() {
        let r = rig()
        fake(r).onScreen = { _ in false }
        r.server.mac.windowFullscreen(id: 2, fullscreen: true)
        XCTAssertEqual(r.server.clientByIdAll(2)?.tags, f1)
        XCTAssertEqual(viewed(r), 1, "macOS shows the desktop: so does mango")
    }

    func testOffNoTagIsFolded() {
        let r = rig(on: false)
        r.server.clientByIdAll(1)!.tags = f1
        r.server.printstatus(.arrangge)
        XCTAssertEqual(r.server.clientByIdAll(1)?.tags, f1, "without the key the extension changes nothing")
    }

    func testEnteringLeavesOverview() {
        let r = rig()
        _ = r.server.dispatch(Dispatch(name: "toggleoverview"))
        XCTAssertTrue(r.server.anyOverview)
        fullscreen(r, 2, true)
        XCTAssertFalse(r.server.anyOverview)
        XCTAssertEqual(viewed(r), f1)
    }

    func testWhatThePortKnewIsForgottenAndNothingIsWrittenToIt() {
        let r = rig()
        let c = r.server.clientByIdAll(2)!
        r.app.minSize[2] = CGSize(width: 1200, height: 900)   // the app keeps it larger than its tile
        r.server.clients.append(r.server.clients.removeFirst())   // a new tile: written
        r.arrange()
        r.settle(3)
        XCTAssertNotNil(c.refusedSize)
        fullscreen(r, 2, true)
        XCTAssertNil(c.refusedSize)
        let frame = r.app.frames[2]
        r.server.mac.windowGeometryChanged(id: 2, frame: r.monitor.screen.frame, resized: true, isfullscreen: true)
        r.settle(1)
        XCTAssertEqual(r.app.frames[2], frame, "macOS moving it is not the user moving it")
    }

    func testOutOfFullscreenTheDesktopsViewIsTheOneBefore() {
        let r = rig()
        fullscreen(r, 2, true)
        fullscreen(r, 2, false)
        XCTAssertEqual(viewed(r), 1)
        XCTAssertEqual(before(r) & mask(r), 0)
        let saved = r.server.mac.memory.currentLayout(r.server)
        XCTAssertEqual((saved.previousTagsets?.values.first ?? 0) & mask(r), 0)
    }
}
