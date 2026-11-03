import XCTest
@testable import Mango
@testable import Port

/// mango's window groups: groupjoin, groupfocus, groupleave, the group bar.
@MainActor
final class GroupTests: MangoTestCase {
    /// Three tiles: 900_700 master, 900_701 and 900_702 stacked; 900_701 focused.
    func rig() -> EngineRig {
        let r = EngineRig()
        r.monitor.current.layout = .tile
        for i in 0..<3 { r.window(CGWindowID(900_700 + i)) }
        r.server.arrange(r.monitor, .none)
        r.server.clientFocus(r.server.clientByIdAll(900_701)!, raise: false)
        return r
    }

    func c(_ r: EngineRig, _ id: CGWindowID) -> Client { r.server.clientByIdAll(id)! }
    func tiled(_ r: EngineRig) -> [CGWindowID] { r.server.tiledClients(r.monitor).map(\.id) }
    func run(_ r: EngineRig, _ name: String, _ args: String...) { _ = r.server.dispatch(Dispatch(name: name, args: args)) }

    func testJoiningTakesThePlaceOfTheWindowJoined() {
        let r = rig()
        let slot = c(r, 900_702).geom!
        run(r, "groupjoin", "down")   // 900_701 joins 900_702, below it
        XCTAssertEqual(r.server.groupMembers(c(r, 900_701)).map(\.id), [900_701, 900_702])
        XCTAssertTrue(c(r, 900_701).isGroupFocus)
        XCTAssertTrue(c(r, 900_702).groupParked, "the member out of view is parked")
        XCTAssertEqual(tiled(r), [900_700, 900_701], "one place for the group")
        XCTAssertEqual(r.monitor.sel, 900_701)
        XCTAssertEqual(c(r, 900_701).geom!.minX, slot.minX, accuracy: 1, "in the joined window's column")
    }

    /// mango client_handle_decorate_click: a press on a group bar's member swaps the group's
    /// focus (client_focus_group_member); the close button closes it.
    func testAPressOnTheGroupBar() {
        let r = rig()
        run(r, "groupjoin", "down")
        r.server.pointerProcessButtonPress(button: 0, pressed: true, at: r.server.system.pointer, mods: [], bar: BarButton(client: 900_702, isTab: false, onClose: false))
        XCTAssertEqual(r.monitor.sel, 900_702)
        XCTAssertTrue(c(r, 900_701).groupParked, "the group's focus swapped")
        r.server.pointerProcessButtonPress(button: 0, pressed: true, at: r.server.system.pointer, mods: [], bar: BarButton(client: 900_702, isTab: false, onClose: true))
        XCTAssertEqual((r.server.system as! FakeWindowSystem).closed, [900_702])
    }

    /// mango group_bar_drag_pending: a press on a member, then 5 px of motion: it leaves the
    /// group and is moved (a grab); less is still the press.
    func testDraggingAMemberOutOfTheGroupBar() {
        let r = rig()
        run(r, "groupjoin", "down")
        let fake = r.server.system as! FakeWindowSystem
        fake.fakePointer = CGPoint(x: 500, y: 300)
        r.server.pointerProcessButtonPress(button: 0, pressed: true, at: r.server.system.pointer, mods: [], bar: BarButton(client: 900_702, isTab: false, onClose: false))
        r.server.pointerProcessMotion(CGPoint(x: 502, y: 301), time: 1)
        XCTAssertNotNil(r.server.groupBarDrag, "the bar's motion")
        XCTAssertTrue(c(r, 900_702).isGroupMember, "not yet 5 px")
        XCTAssertNil(r.server.grab)
        r.server.pointerProcessMotion(CGPoint(x: 510, y: 300), time: 2)
        XCTAssertFalse(c(r, 900_702).isGroupMember, "out of the group")
        XCTAssertTrue(r.server.grab?.client === c(r, 900_702), "moved with the pointer")
        XCTAssertNil(r.server.groupBarDrag, "the press is over")
    }

    /// mango pointer_process_button_press: a right click on a tab closes it only with
    /// monocle_right_button_close; otherwise it is focused as a left click.
    func testARightClickOnATab() {
        let r = rig()
        r.server.pointerProcessButtonPress(button: 1, pressed: true, at: r.server.system.pointer, mods: [], bar: BarButton(client: 900_700, isTab: true, onClose: false))
        XCTAssertEqual(r.monitor.sel, 900_700)
        XCTAssertEqual((r.server.system as! FakeWindowSystem).closed, [])
        r.server.config.monocleRightButtonClose = true
        r.server.pointerProcessButtonPress(button: 1, pressed: true, at: r.server.system.pointer, mods: [], bar: BarButton(client: 900_701, isTab: true, onClose: false))
        XCTAssertEqual((r.server.system as! FakeWindowSystem).closed, [900_701])
    }

    func testGroupfocusSwapsTheMemberInView() {
        let r = rig()
        run(r, "groupjoin", "down")
        run(r, "groupfocus", "next")
        XCTAssertEqual(r.monitor.sel, 900_702)
        XCTAssertTrue(c(r, 900_701).groupParked)
        XCTAssertEqual(tiled(r), [900_700, 900_702])
        run(r, "groupfocus", "next")
        XCTAssertEqual(r.monitor.sel, 900_702, "no wrapping, as mango")
        run(r, "groupfocus", "prev")
        XCTAssertEqual(r.monitor.sel, 900_701)
    }

    func testLeavingPutsItRightAfterTheGroup() {
        let r = rig()
        run(r, "groupjoin", "down")
        run(r, "groupleave")
        XCTAssertFalse(c(r, 900_701).isGroupMember)
        XCTAssertFalse(c(r, 900_702).isGroupMember)
        XCTAssertEqual(tiled(r), [900_700, 900_702, 900_701])
        XCTAssertEqual(r.monitor.sel, 900_702, "the one left keeps the focus")
    }

    func testTheNextMemberTakesTheClosedOnesPlace() {
        let r = rig()
        run(r, "groupjoin", "down")
        r.server.mac.windowDestroyed(id: 900_701)
        XCTAssertFalse(c(r, 900_702).groupParked)
        XCTAssertEqual(tiled(r), [900_700, 900_702])
        XCTAssertFalse(c(r, 900_702).isGroupMember)
    }

    /// Not in mango: a member that goes away and comes back (sleep) is in its group again,
    /// in its place, the member in view still in view; the saved layout keeps the group.
    func testAGroupComesBackWithItsMembers() {
        let r = rig()
        run(r, "groupjoin", "down")                       // [900_701, 900_702], 900_701 in view
        XCTAssertEqual(r.server.mac.memory.currentLayout(r.server).groups, [DepartedGroup(members: [900_701, 900_702], focus: 900_701)])
        r.server.mac.windowDestroyed(id: 900_702)
        XCTAssertFalse(c(r, 900_701).isGroupMember)
        XCTAssertEqual(r.server.mac.memory.departed.groups.count, 1, "kept")
        XCTAssertNotNil(r.server.mac.memory.departed.entries[900_702], "departed")
        r.map(900_702)                                     // back, through handle_client_map
        XCTAssertEqual(r.server.groupMembers(c(r, 900_701)).map(\.id), [900_701, 900_702])
        XCTAssertTrue(c(r, 900_701).isGroupFocus)
        XCTAssertTrue(c(r, 900_702).groupParked)
        XCTAssertEqual(tiled(r), [900_700, 900_701], "one place for the group")
        XCTAssertTrue(r.server.mac.memory.departed.groups.isEmpty, "all back: forgotten")
    }

    func testFocusingAParkedMemberBringsItIn() {
        let r = rig()
        run(r, "groupjoin", "down")
        r.server.mac.windowFocused(id: 900_702)   // the Dock or ⌘Tab
        XCTAssertEqual(r.monitor.sel, 900_702)
        XCTAssertFalse(c(r, 900_702).groupParked)
    }

    /// A tiled group member lies group_bar_height lower; togglegroupbar does it for all.
    func testTheGroupBarTakesRoomAbove() {
        let r = rig()
        let master = c(r, 900_700).geom!
        run(r, "togglegroupbar")
        XCTAssertEqual(c(r, 900_700).geom!.minY, master.minY + 33, accuracy: 1)
        XCTAssertEqual(c(r, 900_700).geom!.height, master.height - 33, accuracy: 1)
        run(r, "togglegroupbar")
        XCTAssertEqual(c(r, 900_700).geom!.minY, master.minY, accuracy: 1)
    }

    /// The bar's segments are the members; close buttons with group_bar_close_button_enable.
    func testTheGroupBarNamesTheMembers() {
        let r = rig()
        run(r, "groupjoin", "down")
        var strip = r.server.clientDrawGroupBar(animating: [:]).first
        XCTAssertEqual(strip?.segments.map(\.id), [900_701, 900_702])
        XCTAssertEqual(strip?.segments.first?.focused, true)
        XCTAssertNil(strip?.closeButton)
        r.server.config.groupBarCloseButtonEnable = true
        strip = r.server.clientDrawGroupBar(animating: [:]).first
        XCTAssertEqual(strip?.closeButton?.size, 16)
        XCTAssertEqual(strip?.frame.maxY ?? 0, c(r, 900_701).frame.minY, accuracy: 1,
                       "mango's: right on top of the bordered window")
        XCTAssertEqual(strip?.plain, true)
        r.server.config.chutneyStyle = true
        strip = r.server.clientDrawGroupBar(animating: [:]).first
        XCTAssertEqual(strip?.frame.maxY ?? 0, c(r, 900_701).frame.minY + BorderGeometry.cornerRadius, accuracy: 1,
                       "the port's: reaching under the window's corners")
    }

    func testDroppingOnAGroupBarJoinsTheGroup() {
        let r = rig()
        run(r, "groupjoin", "down")   // 900_701 + 900_702, with a bar
        let shown = c(r, 900_701).frame
        r.server.clientBeginDragFloat(c(r, 900_700), at: CGPoint(x: 1, y: 1))
        r.server.dropDraggedTile(at: CGPoint(x: shown.midX, y: shown.minY - 10))
        XCTAssertEqual(Set(r.server.groupMembers(c(r, 900_700)).map(\.id)), [900_700, 900_701, 900_702])
        XCTAssertEqual(tiled(r), [900_700])
    }
}
