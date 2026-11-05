import XCTest
@testable import Mango
@testable import Port

/// mango's is_unmanaged_global and ignore_minimize window rules.
@MainActor
final class UnmanagedGlobalTests: MangoTestCase {
    // Window ids no process has as a pid: FakeApp makes elements from them, and the
    // minimize test writes to the element.
    let a: CGWindowID = 900_001, b: CGWindowID = 900_002, pet: CGWindowID = 900_003

    func testAnUnmanagedGlobalWindowIsNeverLaidOutMovedOrParked() {
        let r = EngineRig()
        r.window(a)
        r.window(b)
        let petFrame = CGRect(x: 1500, y: 900, width: 120, height: 90)
        let u = r.window(pet, frame: petFrame)
        u.isUnglobal = true
        r.server.arrange(r.monitor, .none)
        r.settle()
        XCTAssertEqual(r.server.tiledClients(r.monitor).map(\.id), [a, b], "not a tile")
        XCTAssertFalse(r.app.writes.contains { $0.id == pet }, "mango does not move it")
        XCTAssertEqual(r.app.frames[pet], petFrame)

        r.server.clientViewOnMonitor(1 << 1, on: r.monitor)   // another tag
        r.settle()
        XCTAssertTrue(u.isVisible(on: r.monitor), "on every tag")
        XCTAssertEqual(u.tags, 1 << 1, "and reported on the tag in view, as in mango")
        XCTAssertFalse(u.parked)
        XCTAssertFalse(r.app.writes.contains { $0.id == pet })
    }

    func testFocusNavigationAndTheOverviewSkipIt() {
        let r = EngineRig()
        let w = r.window(a)
        let u = r.window(pet)
        u.isUnglobal = true
        XCTAssertTrue(r.server.clientFocusTop(r.monitor) === w)
    }

    func testAMinimizeIsMangosWhenIgnoreMinimizeIsOff() {
        let r = EngineRig()
        let c = r.window(a)
        c.ignoreMinimize = false
        r.server.mac.windowMinimized(id: a, minimized: true)        // ⌘M / the yellow button
        XCTAssertTrue(c.isInScratchpad, "in mango's minimized pool")
        XCTAssertNil(r.server.mac.away[a], "not away in the Dock")
        r.server.mac.windowMinimized(id: a, minimized: false)       // our own de-minimize
        XCTAssertTrue(c.isInScratchpad, "stays in the pool")
    }

    /// mango's default ignore_minimize refuses the minimize, which macOS has done: the
    /// window is away (unmapped), and maps back to its tag when the Dock gives it back.
    func testAMinimizeGoesToTheDockByDefault() {
        let r = EngineRig()
        let c = r.map(a)
        c.tags = 1 << 2
        r.server.mac.windowMinimized(id: a, minimized: true)
        XCTAssertNil(r.server.clientByIdAll(a), "unmapped, as mango would have it")
        XCTAssertEqual(r.server.mac.away[a]?.reasons, [.minimized])
        XCTAssertFalse(c.isInScratchpad)
        r.server.mac.windowMinimized(id: a, minimized: false)
        XCTAssertTrue(r.server.clientByIdAll(a) === c, "mapped back")
        XCTAssertEqual(c.tags, 1 << 2, "on its tag")
        XCTAssertNil(r.server.mac.away[a])
    }

    /// Not in mango: native fullscreen and a hidden app (⌘H) unmap the window too; it is
    /// back when both are over.
    func testFullscreenAndHiddenAreAwayUntilBothAreOver() {
        let r = EngineRig()
        let c = r.map(a)
        r.server.mac.windowGeometryChanged(id: a, frame: c.frame, resized: false, isFullscreen: true)
        XCTAssertNil(r.server.clientByIdAll(a))
        r.server.mac.appHidden(pid: c.pid, hidden: true)
        XCTAssertEqual(r.server.mac.away[a]?.reasons, [.fullscreen, .hidden])
        r.server.mac.windowGeometryChanged(id: a, frame: c.frame, resized: false, isFullscreen: false)
        XCTAssertNil(r.server.clientByIdAll(a), "still hidden")
        r.server.mac.appHidden(pid: c.pid, hidden: false)
        XCTAssertTrue(r.server.clientByIdAll(a) === c)
    }

    /// A window found minimized, in fullscreen or hidden is not mapped until it is back.
    func testAWindowFoundAwayIsMappedWhenItIsBack() {
        let r = EngineRig()
        r.server.mac.windowDiscovered(DiscoveredWindow(
            id: a, pid: getpid(), element: r.app.element(for: a), bundleId: "test", appName: "Test", title: "t",
            subrole: "AXStandardWindow", isDialog: false, frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            isMinimized: true, isFullscreen: false, isAppHidden: false))
        XCTAssertNil(r.server.clientByIdAll(a))
        r.server.mac.windowMinimized(id: a, minimized: false)
        XCTAssertNotNil(r.server.clientByIdAll(a))
    }
}
