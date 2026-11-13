import XCTest
@testable import Mango
@testable import Port

/// A window in macOS fullscreen is away from the layout; it comes back to its place.
@MainActor
final class FullscreenAwayTests: MangoTestCase {
    func rig() -> EngineRig {
        let r = EngineRig()
        for id: CGWindowID in 1...3 { r.window(id) }
        r.server.arrange(r.monitor, .none)
        r.settle(1)
        return r
    }

    func fake(_ r: EngineRig) -> FakeWindowSystem { r.server.system as! FakeWindowSystem }
    func ids(_ r: EngineRig) -> [ClientID] { r.server.tiledClients(r.monitor).map(\.id) }

    func geometry(_ r: EngineRig, _ id: ClientID, fullscreen: Bool?, frame: CGRect? = nil) {
        let f = frame ?? r.server.clientByIdAll(id)?.frame ?? r.server.mac.away[id]?.client.frame ?? .zero
        r.server.mac.windowGeometryChanged(id: id, frame: f, resized: true, isFullscreen: fullscreen)
    }

    func testComingBackFromFullscreenTakesItsPlaceAndTheAppsFocus() {
        let r = rig()
        let c = r.server.clientByIdAll(2)!
        let tile = c.geom
        geometry(r, 2, fullscreen: true)
        XCTAssertEqual(ids(r), [1, 3])
        geometry(r, 2, fullscreen: false, frame: r.monitor.screen.frame)
        XCTAssertEqual(ids(r), [1, 2, 3], "its old place")
        XCTAssertEqual(fake(r).focusAsked, [2], "the app says which window has the keys")
        XCTAssertTrue(r.server.focused === c)
        XCTAssertEqual(c.geom, tile)
    }

    func testANotAnsweringAppChangesNothing() {
        let r = rig()
        geometry(r, 2, fullscreen: nil)
        XCTAssertEqual(ids(r), [1, 2, 3])
        geometry(r, 2, fullscreen: true)
        geometry(r, 2, fullscreen: nil)
        XCTAssertEqual(ids(r), [1, 3], "still away")
    }

    func testAMissedEnterIsSeenWhenTheSpaceChanges() {
        let r = rig()
        r.server.mac.windowFullscreen(id: 2, fullscreen: true)
        XCTAssertEqual(ids(r), [1, 3], "no tile left for it")
        XCTAssertEqual(r.server.mac.away[2]?.reasons, [.fullscreen])
    }

    func testAMissedLeaveIsSeenWhenTheSpaceChanges() {
        let r = rig()
        r.server.mac.windowFullscreen(id: 2, fullscreen: true)
        r.server.mac.spaceChanged()
        r.server.mac.windowFullscreen(id: 2, fullscreen: false)
        XCTAssertEqual(ids(r), [1, 2, 3], "back, not lost")
        XCTAssertNil(r.server.mac.away[2])
    }

    func testPlacedAgainWhenMacOSHasFinishedMovingIt() {
        let r = rig()
        let tile = r.server.clientByIdAll(2)!.geom!
        geometry(r, 2, fullscreen: true)
        geometry(r, 2, fullscreen: false, frame: r.monitor.screen.frame)
        r.app.frames[2] = r.monitor.screen.frame   // macOS still moving it out
        r.settle(0.3)
        XCTAssertNotEqual(r.app.frames[2], tile, "not before macOS is done")
        r.server.mac.spaceChanged()
        r.settle(1)
        XCTAssertEqual(r.app.frames[2], tile, "on its tile once the Space change is done")
    }

    func testPlacedAtOnceWhenTheSpaceChangeCameFirst() {
        let r = rig()
        let tile = r.server.clientByIdAll(2)!.geom!
        geometry(r, 2, fullscreen: true)
        r.server.mac.spaceChanged()
        r.app.frames[2] = r.monitor.screen.frame
        geometry(r, 2, fullscreen: false, frame: r.monitor.screen.frame)
        r.settle(1)
        XCTAssertEqual(r.app.frames[2], tile, "placed at once")
    }

    func testWhatThePortKnewOfItsPlaceIsForgotten() {
        let r = rig()
        let c = r.server.clientByIdAll(2)!
        c.refusedSize = CGSize(width: 3000, height: 2000)
        c.retryTarget = CGRect(x: 1, y: 1, width: 1, height: 1)
        c.retryCount = 2
        geometry(r, 2, fullscreen: true)
        XCTAssertNil(c.refusedSize)
        XCTAssertNil(c.retryTarget)
        XCTAssertEqual(c.retryCount, 0)
        c.refusedSize = CGSize(width: 3000, height: 2000)
        geometry(r, 2, fullscreen: false)
        XCTAssertNil(c.refusedSize, "nor what it kept while away")
    }

    func testItsPlaceIsKeptHoweverLongItIsAway() {
        let r = rig()
        geometry(r, 2, fullscreen: true)
        XCTAssertTrue(r.server.mac.memory.departed.away.contains(2))
        r.server.mac.memory.departed.prune(now: CACurrentMediaTime() + 2 * DepartedWindows.keepFor)
        XCTAssertNotNil(r.server.mac.memory.departed.entries[2])
        geometry(r, 2, fullscreen: false)
        XCTAssertEqual(ids(r), [1, 2, 3])
        XCTAssertFalse(r.server.mac.memory.departed.away.contains(2))
    }

    func testAnAppQuitWhileAwayIsForgotten() {
        let r = rig()
        let c = r.server.clientByIdAll(2)!
        geometry(r, 2, fullscreen: true)
        r.server.mac.appTerminated(pid: c.pid)
        XCTAssertNil(r.server.mac.away[2])
        XCTAssertFalse(r.server.mac.memory.departed.away.contains(2))
    }

    func testBackWhenItsElementWasReacquired() {
        let r = rig()
        geometry(r, 2, fullscreen: true)
        r.server.mac.windowReacquired(id: 2, element: r.app.element(for: 2),
                                      state: ReacquiredState(frame: nil, minimized: false, fullscreen: false, appHidden: false))
        XCTAssertEqual(ids(r), [1, 2, 3])
    }
}
