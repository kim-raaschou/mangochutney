import XCTest
@testable import Mango
@testable import Port

/// mango's title_message_bar.c: one bar per monitor, under the switcher panel or the overcircle's card.
@MainActor
final class TitleMessageBarTests: MangoTestCase {
    func rig() -> EngineRig {
        let r = EngineRig()
        r.window(900_200)
        r.window(900_201)
        r.server.clientFocus(r.server.clientByIdAll(900_200)!, false)
        r.server.clientFocus(r.server.clientByIdAll(900_201)!, false)
        return r
    }

    func fake(_ r: EngineRig) -> FakeWindowSystem { r.server.system as! FakeWindowSystem }
    func bar(_ r: EngineRig) -> FakeBar? { r.monitor.titleMessageBar as? FakeBar }
    func run(_ r: EngineRig, _ name: String, _ args: String...) {
        _ = r.server.dispatch(Dispatch(name: name, args: args))
    }

    func testUnderTheSwitcherPanelForTheHighlightedClient() throws {
        let r = rig()
        run(r, "switcher", "next")
        let bar = try XCTUnwrap(bar(r))
        let panel = r.server.switcherState!.layout.panel
        XCTAssertTrue(bar.enabled)
        XCTAssertEqual(bar.lastText, "t900200\ntest", "title, then appid")
        XCTAssertEqual(bar.lastScale, 2)
        XCTAssertEqual(bar.frame, CGRect(x: panel.minX, y: panel.maxY + 20, width: panel.width, height: 52))
        XCTAssertEqual(bar.raises, 1)
        run(r, "switcher", "next")
        XCTAssertEqual(bar.lastText, "t900201\ntest", "switcher_cycle updates it")
        XCTAssertEqual(bar.raises, 1, "raised only as it is enabled")
        r.server.switcherClose()
        XCTAssertFalse(bar.enabled, "switcher_close hides it")
        XCTAssertFalse(bar.destroyed)
        XCTAssertEqual(fake(r).bars.count, 1, "one bar per monitor, kept")
    }

    func testAtHeightZeroItIsNeverMade() {
        let r = rig()
        r.server.config.titleMessageBarHeight = 0
        run(r, "switcher", "next")
        XCTAssertNil(r.monitor.titleMessageBar)
    }

    func testTheSameTextAtTheSameScaleIsNotDrawnAgain() throws {
        let r = rig()
        run(r, "switcher", "next")
        let bar = try XCTUnwrap(bar(r))
        let updates = bar.updates
        r.server.titleMessageBarUpdate(r.monitor)
        XCTAssertEqual(bar.updates, updates)
    }

    func testATitleChangeReachesItOnlyForItsClient() throws {
        let r = rig()
        run(r, "switcher", "next")
        let bar = try XCTUnwrap(bar(r))
        let other = r.server.clientByIdAll(900_201)!
        other.title = "elsewhere"
        r.server.handleClientSetTitle(other)
        XCTAssertEqual(bar.lastText, "t900200\ntest")
        let c = r.server.clientByIdAll(900_200)!
        c.title = "renamed"
        r.server.handleClientSetTitle(c)
        XCTAssertEqual(bar.lastText, "renamed\ntest")
        r.server.switcherClose()
        c.title = "hidden"
        r.server.handleClientSetTitle(c)
        XCTAssertEqual(bar.lastText, "renamed\ntest", "not while it is hidden")
    }

    func testUnderTheOvercircleCardAndHiddenOnLeaving() throws {
        let r = rig()
        run(r, "overcircle", "next")
        let bar = try XCTUnwrap(bar(r))
        let sel = try XCTUnwrap(r.monitor.sel)
        let card = try XCTUnwrap(r.server.selectedMonitor.ovCards[sel])
        XCTAssertTrue(bar.enabled)
        XCTAssertEqual(bar.frame, CGRect(x: card.minX, y: card.maxY + 20, width: card.width, height: 52))
        XCTAssertEqual(bar.lastText, "t\(sel)\ntest")
        run(r, "overcircle", "next")
        let next = try XCTUnwrap(r.monitor.sel)
        XCTAssertNotEqual(next, sel)
        XCTAssertEqual(bar.lastText, "t\(next)\ntest", "it follows the focused client")
        r.server.leaveOverview(Arg())
        XCTAssertFalse(bar.enabled)
    }

    func testNotInThePlainOverview() {
        let r = rig()
        run(r, "toggleoverview")
        XCTAssertNil(r.monitor.titleMessageBar)
    }

    func testAReloadAppliesTheConfigToEveryMonitorsBar() throws {
        let r = rig()
        run(r, "switcher", "next")
        let bar = try XCTUnwrap(bar(r))
        r.server.config.titleMessageBardata.cornerRadius = 3
        r.server.resetOption()
        XCTAssertEqual(bar.data.cornerRadius, 3)
        XCTAssertTrue(bar.enabled, "and updates it")
    }

    func testAMonitorThatGoesTakesItsBar() throws {
        let r = rig()
        run(r, "switcher", "next")
        r.server.switcherClose()
        let bar = try XCTUnwrap(bar(r))
        let m = r.monitor
        let other = Screen(displayID: 2, name: "Other", frame: CGRect(x: 2000, y: 0, width: 1000, height: 800),
                           workArea: CGRect(x: 2000, y: 0, width: 1000, height: 800), scale: 1, isMain: true)
        r.server.rebuildMonitors(screens: [other])
        XCTAssertTrue(bar.destroyed, "cleanup_monitor: title_message_bar_finish")
        XCTAssertNil(m.titleMessageBar)
    }
}
