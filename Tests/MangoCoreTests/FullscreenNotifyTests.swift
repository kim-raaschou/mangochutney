import XCTest
@testable import Mango
@testable import Port

/// Port extension chutney_fullscreen_tag: mango tells the app it is fullscreen (client_notify_fullscreen)
/// by macOS's own fullscreen, and macOS's fullscreen is mango's.
@MainActor
final class FullscreenNotifyTests: MangoTestCase {
    let f1: UInt32 = 1 << 9

    func rig(on: Bool = true) -> EngineRig {
        let r = EngineRig()
        r.server.config.chutneyFullscreenTag = on
        for id: CGWindowID in 1...3 { r.window(id) }
        r.server.arrange(r.monitor, false, false)
        r.settle(1)
        return r
    }

    func fake(_ r: EngineRig) -> FakeWindowSystem { r.server.system as! FakeWindowSystem }
    func writes(_ r: EngineRig) -> [String] { fake(r).fullscreenWrites.map { "\($0.0):\($0.1)" } }
    func tiled(_ r: EngineRig) -> [ClientID] { r.server.tiledClients(r.monitor).map(\.id) }
    func viewed(_ r: EngineRig) -> UInt32 { r.monitor.tagset[r.monitor.seltags] }

    func run(_ r: EngineRig, _ name: String, _ id: ClientID) {
        _ = r.server.dispatch(Dispatch(name: name), target: r.server.clientByIdAll(id))
        r.settle(1)
    }

    /// macOS says the window went in or out of fullscreen.
    func macOS(_ r: EngineRig, _ id: ClientID, _ on: Bool) {
        let c = r.server.clientByIdAll(id)!
        r.server.mac.windowGeometryChanged(id: id, frame: c.frame, resized: true, isfullscreen: on)
        r.settle(1)
    }

    func discover(_ r: EngineRig, _ id: CGWindowID) {
        r.server.mac.windowDiscovered(DiscoveredWindow(
            id: id, pid: getpid(), element: r.app.element(for: id), bundleId: "test", appName: "Test", title: "t\(id)",
            subrole: "AXStandardWindow", isDialog: false, frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            isminimized: false, isfullscreen: false, isAppHidden: false))
        r.settle(1)
    }

    func testWithTheKeyOffTheAppIsNotTold() {
        let r = rig(on: false)
        run(r, "togglefullscreen", 2)
        XCTAssertTrue(r.server.clientByIdAll(2)!.isfullscreen)
        XCTAssertEqual(writes(r), [])
        XCTAssertEqual(r.app.frames[2], r.monitor.screen.frame, "mango's fullscreen, as before")
    }

    func testTogglefullscreenAsksMacOSOnceAndLeavesTheWindowToIt() {
        let r = rig()
        let frame = r.app.frames[2]
        run(r, "togglefullscreen", 2)
        let c = r.server.clientByIdAll(2)!
        XCTAssertTrue(c.isfullscreen)
        XCTAssertEqual(writes(r), ["2:true"])
        XCTAssertEqual(r.app.frames[2], frame, "nothing written while macOS moves it")
        XCTAssertEqual(tiled(r), [1, 3], "the tag closes up at once")
    }

    func testMacOSsAnswerPutsItOnItsFTagWithNoSecondWrite() {
        let r = rig()
        run(r, "togglefullscreen", 2)
        macOS(r, 2, true)
        let c = r.server.clientByIdAll(2)!
        XCTAssertEqual(c.tags, f1)
        XCTAssertEqual(viewed(r), f1)
        XCTAssertTrue(c.isfullscreen)
        XCTAssertEqual(writes(r), ["2:true"])
    }

    func testTogglefullscreenOnItsFTagTakesItBack() {
        let r = rig()
        let tile = r.server.clientByIdAll(2)!.geom
        run(r, "togglefullscreen", 2)
        macOS(r, 2, true)
        run(r, "togglefullscreen", 2)
        XCTAssertEqual(writes(r), ["2:true", "2:false"])
        let c = r.server.clientByIdAll(2)!
        XCTAssertEqual(c.tags, f1, "on its F tag until macOS has it out")
        macOS(r, 2, false)
        XCTAssertEqual(c.tags, 1)
        XCTAssertFalse(c.isfullscreen)
        XCTAssertEqual(tiled(r), [1, 2, 3])
        XCTAssertEqual(c.geom, tile)
    }

    func testMacOSsOwnFullscreenIsMangosAndOneToggleLeavesIt() {
        let r = rig()
        macOS(r, 2, true)
        XCTAssertTrue(r.server.clientByIdAll(2)!.isfullscreen, "as an app's request")
        XCTAssertEqual(writes(r), [], "the app is not told what it did itself")
        run(r, "togglefullscreen", 2)
        XCTAssertEqual(writes(r), ["2:false"])
    }

    func testOutOfMacOSFullscreenItIsOutOfMangos() {
        let r = rig()
        let tile = r.server.clientByIdAll(2)!.geom
        macOS(r, 2, true)
        macOS(r, 2, false)
        let c = r.server.clientByIdAll(2)!
        XCTAssertFalse(c.isfullscreen, "tiled, not covering its tag")
        XCTAssertEqual(tiled(r), [1, 2, 3])
        XCTAssertEqual(c.geom, tile)
        XCTAssertEqual(writes(r), [])
    }

    func testFloatingOrMaximizedIsOutOfMacOSFullscreen() {
        let r = rig()
        macOS(r, 2, true)
        run(r, "togglefloating", 2)
        XCTAssertEqual(writes(r), ["2:false"])
        let s = rig()
        macOS(s, 2, true)
        run(s, "togglemaximizescreen", 2)
        XCTAssertEqual(writes(s), ["2:false"])
    }

    func testAnAppThatCannotStaysInMangosFullscreen() {
        let r = rig()
        fake(r).takesFullscreen = { _ in false }
        run(r, "togglefullscreen", 2)
        let c = r.server.clientByIdAll(2)!
        XCTAssertTrue(c.isfullscreen)
        XCTAssertFalse(c.scheduledFullscreen)
        XCTAssertEqual(r.app.frames[2], r.monitor.screen.frame, "it fills the monitor in mango")
    }

    func testANewWindowDoesNotTakeItOutOfFullscreen() {
        let r = rig()
        macOS(r, 2, true)
        discover(r, 9)
        XCTAssertEqual(writes(r), [])
        XCTAssertTrue(r.server.clientByIdAll(2)!.isfullscreen)
        XCTAssertEqual(r.server.clientByIdAll(9)?.tags, 1)
        XCTAssertEqual(viewed(r), 1, "mango views its tag")
    }

    func testTheSameFullscreenAgainIsNotWritten() {
        let r = rig()
        run(r, "togglefullscreen", 2)
        let c = r.server.clientByIdAll(2)!
        r.server.clientSetFullscreen(c, true, rearrange: true)
        XCTAssertEqual(writes(r), ["2:true"])
    }

    func testOverviewIsNotWritten() {
        let r = rig()
        macOS(r, 2, true)
        run(r, "toggleoverview", 1)
        run(r, "toggleoverview", 1)
        XCTAssertEqual(writes(r), [])
        XCTAssertTrue(r.server.clientByIdAll(2)!.isfullscreen)
    }

    func testFakeFullscreenIsNotWritten() {
        let r = rig()
        run(r, "togglefakefullscreen", 2)
        XCTAssertEqual(writes(r), [])
    }

    func testWithNoFreeFTagItIsMangosFullscreenOnly() {
        let r = rig()
        r.server.clientByIdAll(1)!.tags = 1 | FullscreenTag.mask(r.server.config)
        _ = r.server.dispatch(Dispatch(name: "togglefullscreen"), target: r.server.clientByIdAll(2))
        XCTAssertEqual(writes(r), [])
        XCTAssertTrue(r.server.clientByIdAll(2)!.isfullscreen)
    }

    func testClosedInFullscreenItIsNotRememberedFullscreen() {
        let r = rig()
        macOS(r, 2, true)
        let c = r.server.clientByIdAll(2)!
        r.server.mac.windowDestroyed(id: 2)
        r.settle(0.5)
        XCTAssertFalse(c.isfullscreen)
        XCTAssertFalse(c.scheduledFullscreen)
    }

    // MARK: macOS's answer

    func testToldButNeverInIsNotLeftStuck() {
        let r = rig()
        let tile = r.server.clientByIdAll(2)!.geom
        run(r, "togglefullscreen", 2)
        r.server.mac.windowFullscreen(id: 2, fullscreen: false)   // read after a Space change
        r.settle(1)
        let c = r.server.clientByIdAll(2)!
        XCTAssertFalse(c.isfullscreen, "out of mango's fullscreen as macOS has it")
        XCTAssertFalse(c.leftToMacOS)
        XCTAssertEqual(tiled(r), [1, 2, 3])
        XCTAssertEqual(r.app.frames[2], tile, "placed again")
    }

    func testAnEarlyNotYetIsNotAnAnswer() {
        let r = rig()
        let frame = r.app.frames[2]
        run(r, "togglefullscreen", 2)
        macOS(r, 2, false)   // a resize during macOS's animation, before it reads fullscreen
        XCTAssertTrue(r.server.clientByIdAll(2)!.leftToMacOS)
        XCTAssertEqual(r.app.frames[2], frame)
    }

    func testOutOfMacOSFullscreenDuringOverviewIsOutOfMangos() {
        let r = rig()
        macOS(r, 2, true)
        run(r, "toggleoverview", 1)
        macOS(r, 2, false)
        XCTAssertFalse(r.server.anyOverview)
        XCTAssertFalse(r.server.clientByIdAll(2)!.isfullscreen)
        XCTAssertEqual(tiled(r), [1, 2, 3])
    }

    func testASecondPressMeanwhileWritesNoFrame() {
        let r = rig()
        let frame = r.app.frames[2]
        let tile = r.server.clientByIdAll(2)!.geom
        run(r, "togglefullscreen", 2)
        run(r, "togglefullscreen", 2)
        XCTAssertEqual(writes(r), ["2:true", "2:false"])
        XCTAssertEqual(r.app.frames[2], frame, "macOS still moves it")
        r.server.mac.windowFullscreen(id: 2, fullscreen: false)
        r.settle(1)
        XCTAssertEqual(r.app.frames[2], tile)
    }

    func testASecondPressMacOSDidNotTakeLeavesItInBoth() {
        let r = rig()
        run(r, "togglefullscreen", 2)
        run(r, "togglefullscreen", 2)
        macOS(r, 2, true)
        let c = r.server.clientByIdAll(2)!
        XCTAssertEqual(c.tags, f1)
        XCTAssertTrue(c.isfullscreen, "mango has it as macOS does")
    }

    func testAwayWhileToldIsNotToldAgainWhenBack() {
        let r = rig()
        run(r, "togglefullscreen", 2)
        let c = r.server.clientByIdAll(2)!
        r.server.mac.goAway(c, .minimized)
        r.settle(0.5)
        XCTAssertFalse(c.isfullscreen)
        r.server.mac.comeBack(2, .minimized)
        r.settle(1)
        XCTAssertEqual(writes(r), ["2:true"])
        XCTAssertFalse(r.server.clientByIdAll(2)!.isfullscreen)
    }
}
