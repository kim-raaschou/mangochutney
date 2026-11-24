import XCTest
@testable import Mango
@testable import Port

@MainActor
final class UnmanagedGlobalTests: MangoTestCase {
    let a: CGWindowID = 900_001, b: CGWindowID = 900_002, pet: CGWindowID = 900_003

    func testAnUnmanagedGlobalWindowIsNeverLaidOutMovedOrParked() {
        let r = EngineRig()
        r.window(a)
        r.window(b)
        let petFrame = CGRect(x: 1500, y: 900, width: 120, height: 90)
        let u = r.window(pet, frame: petFrame)
        u.isunglobal = true
        r.arrange()
        r.settle()
        XCTAssertEqual(r.server.tiledClients(r.monitor).map(\.windowID), [a, b], "not a tile")
        XCTAssertFalse(r.app.writes.contains { $0.id == pet }, "mango does not move it")
        XCTAssertEqual(r.app.frames[pet], petFrame)

        r.server.clientViewOnMonitor(Arg(ui: 1 << 1), true, r.monitor, r.monitor === r.server.selectedMonitor)
        r.settle()
        XCTAssertTrue(VISIBLEON(u, r.monitor), "on every tag")
        XCTAssertEqual(u.tags, 1 << 1, "and reported on the tag in view, as in mango")
        XCTAssertFalse(u.parked)
        XCTAssertFalse(r.app.writes.contains { $0.id == pet })
    }

    func testAMinimizeIsMangosWhenIgnoreMinimizeIsOff() {
        let r = EngineRig()
        let c = r.window(a)
        c.ignoreMinimize = false
        r.server.mac.windowMinimized(id: a, minimized: true)
        XCTAssertTrue(c.isInScratchpad, "in mango's minimized pool")
        XCTAssertNil(r.server.mac.away[a], "not away in the Dock")
        r.server.mac.windowMinimized(id: a, minimized: false)
        XCTAssertTrue(c.isInScratchpad, "stays in the pool")
    }

    func testAMinimizeGoesToTheDockByDefault() {
        let r = EngineRig()
        let c = r.map(a)
        c.tags = 1 << 2
        r.server.mac.windowMinimized(id: a, minimized: true)
        XCTAssertNil(r.server.clientByWindowID(a), "unmapped, as mango would have it")
        XCTAssertEqual(r.server.mac.away[a]?.reasons, [.minimized])
        XCTAssertFalse(c.isInScratchpad)
        r.server.mac.windowMinimized(id: a, minimized: false)
        XCTAssertTrue(r.server.clientByWindowID(a) === c, "mapped back")
        XCTAssertEqual(c.tags, 1 << 2, "on its tag")
        XCTAssertNil(r.server.mac.away[a])
    }

    func testFullscreenAndHiddenAreAwayUntilBothAreOver() {
        let r = EngineRig()
        let c = r.map(a)
        r.server.mac.windowGeometryChanged(id: a, frame: c.frame, resized: false, isfullscreen: true)
        XCTAssertNil(r.server.clientByWindowID(a))
        r.server.mac.appHidden(pid: c.pid, hidden: true)
        XCTAssertEqual(r.server.mac.away[a]?.reasons, [.fullscreen, .hidden])
        r.server.mac.windowGeometryChanged(id: a, frame: c.frame, resized: false, isfullscreen: false)
        XCTAssertNil(r.server.clientByWindowID(a), "still hidden")
        r.server.mac.appHidden(pid: c.pid, hidden: false)
        XCTAssertTrue(r.server.clientByWindowID(a) === c)
    }

    func testAWindowFoundAwayIsMappedWhenItIsBack() {
        let r = EngineRig()
        r.server.mac.windowDiscovered(DiscoveredWindow(
            id: a, pid: getpid(), element: r.app.element(for: a), bundleId: "test", appName: "Test", title: "t",
            subrole: "AXStandardWindow", isDialog: false, frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            isminimized: true, isfullscreen: false, isAppHidden: false))
        XCTAssertNil(r.server.clientByWindowID(a))
        r.server.mac.windowMinimized(id: a, minimized: false)
        XCTAssertNotNil(r.server.clientByWindowID(a))
    }
}
