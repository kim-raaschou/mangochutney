import XCTest
@testable import Mango
@testable import Port

/// mango's behaviour where the port gives it what wlroots gives mango: a click, an activation, a window
/// away in the Dock. mango's behaviour on its own is tested in MangoTests.
@MainActor
final class FidelityTests: MangoTestCase {

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

    func testMinimizedWhileAwayGoesThroughTheHandler() {
        let r = EngineRig()
        let a = r.map(1), b = r.map(2)
        a.ignoreMinimize = true
        r.server.clientFocus(a, true)
        r.server.mac.windowReacquired(id: a.id, element: r.app.element(for: a.id),
                                      state: ReacquiredState(frame: nil, minimized: true, fullscreen: false, appHidden: false))
        XCTAssertNil(r.server.clientByIdAll(a.id), "away in the Dock: unmapped")
        XCTAssertEqual(r.monitor.sel?.id, b.id, "the next window is focused")
    }
}
