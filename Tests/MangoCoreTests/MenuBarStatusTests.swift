import XCTest
@testable import Mango
@testable import Port

/// The menu bar item (port extension, not in mango): one copy on every display, so it shows
/// every monitor in the order the displays stand, the selected one in full.
final class MenuBarStatusTests: MangoTestCase {
    @MainActor
    func testEveryMonitorLeftToRightWithItsOwnTagsAndLayout() throws {
        let rig = EngineRig()
        let benq = Screen(displayID: 2, name: "BenQ", frame: CGRect(x: 1728, y: 0, width: 3360, height: 2240),
                          workArea: CGRect(x: 1728, y: 30, width: 3360, height: 2210), scale: 2, isMain: false)
        // The BenQ comes first in the system's list; the laptop stands to its left.
        rig.server.rebuildMonitors(screens: [benq, rig.screen])
        let laptop = try XCTUnwrap(rig.server.monitors.first { $0.screen.displayID == 1 })
        let ext = try XCTUnwrap(rig.server.monitors.first { $0.screen.displayID == 2 })
        rig.window(1, tags: 1 << 1).mon = laptop
        rig.window(2, tags: 1 << 3).mon = ext
        ext.tagset[ext.seltags] = 1 << 3
        laptop.tagset[laptop.seltags] = 1 << 1
        rig.server.selectedMonitor = ext

        let shown = MenuBarStatus.monitors(rig.server)
        XCTAssertEqual(shown.map(\.tags), [[MenuBarTag(number: 2, active: true)], [MenuBarTag(number: 4, active: true)]])
        XCTAssertEqual(shown.map(\.selected), [false, true])
        XCTAssertEqual(shown.map(\.layout), [laptop.layout, ext.layout])
    }

    /// A click on a tag goes to its monitor and views it, as a bar's tag button
    /// (focusmon, view); mango focuses the tag's top window.
    @MainActor
    func testAClickOnATagViewsItOnItsMonitor() throws {
        let rig = EngineRig()
        let benq = Screen(displayID: 2, name: "BenQ", frame: CGRect(x: 1728, y: 0, width: 3360, height: 2240),
                          workArea: CGRect(x: 1728, y: 30, width: 3360, height: 2210), scale: 2, isMain: false)
        rig.server.rebuildMonitors(screens: [benq, rig.screen])
        let laptop = try XCTUnwrap(rig.server.monitors.first { $0.screen.displayID == 1 })
        let ext = try XCTUnwrap(rig.server.monitors.first { $0.screen.displayID == 2 })
        rig.window(1, tags: 1).mon = laptop
        rig.window(2, tags: 1 << 4).mon = ext
        rig.server.selectedMonitor = laptop
        MenuBarStatus.viewTag(rig.server, monitor: "BenQ", tag: 5)
        XCTAssertTrue(rig.server.selectedMonitor === ext)
        XCTAssertEqual(ext.tagset[ext.seltags], 1 << 4)
        XCTAssertEqual(ext.sel, 2, "the tag's window has the focus")
        MenuBarStatus.viewTag(rig.server, monitor: "BenQ", tag: 0)
        XCTAssertEqual(ext.tagset[ext.seltags], 1 << 4, "the special tag: nothing")
    }

    /// A plain press on a tag in the menu bar is taken by mango's event tap with its
    /// release, and views the tag; elsewhere, or with a modifier, it goes on.
    @MainActor
    func testAPressOnAMenuBarTagIsTakenAndViewsIt() {
        let rig = EngineRig()
        rig.window(1, tags: 1)
        rig.window(2, tags: 1 << 4)
        let name = rig.monitor.screen.name
        let frame = CGRect(x: 1400, y: 0, width: 20, height: 33)
        MenuBarStatus.publishTags(rig.server, [MenuBarTagHit(frame: frame, monitor: name, tag: 5),
                                               MenuBarTagHit(frame: frame.offsetBy(dx: 40, dy: 0), monitor: name, tag: 0)])
        let router = rig.server.mac.router
        router.server = rig.server
        defer { router.server = nil }
        let on = CGPoint(x: 1410, y: 15)
        XCTAssertFalse(router.mouseButton(MouseButtonEvent(button: 0, mods: [.superKey], isDown: true, location: on)))
        XCTAssertFalse(router.mouseButton(MouseButtonEvent(button: 0, mods: [.superKey], isDown: false, location: on)))
        XCTAssertFalse(router.mouseButton(MouseButtonEvent(button: 0, mods: [], isDown: true, location: on.applying(.init(translationX: 40, y: 0)))),
                       "the special tag is not published")
        _ = router.mouseButton(MouseButtonEvent(button: 0, mods: [], isDown: false, location: .zero))
        XCTAssertTrue(router.mouseButton(MouseButtonEvent(button: 0, mods: [], isDown: true, location: on)))
        XCTAssertTrue(router.mouseButton(MouseButtonEvent(button: 0, mods: [], isDown: false, location: on)), "its release too")
        rig.settle()
        XCTAssertEqual(rig.monitor.tagset[rig.monitor.seltags], 1 << 4)
        XCTAssertEqual(rig.monitor.sel, 2)
        XCTAssertFalse(router.mouseButton(MouseButtonEvent(button: 0, mods: [], isDown: true, location: CGPoint(x: 900, y: 500))))
        _ = router.mouseButton(MouseButtonEvent(button: 0, mods: [], isDown: false, location: CGPoint(x: 900, y: 500)))
    }

    @MainActor
    func testOneMonitorIsSelected() {
        let rig = EngineRig()
        XCTAssertEqual(MenuBarStatus.monitors(rig.server).map(\.selected), [true])
    }
}
