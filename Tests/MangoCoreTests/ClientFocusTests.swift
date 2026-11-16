import XCTest
@testable import Mango
@testable import Port

/// mango's client_focus (client.c): the seat, the early return, lift and the end's notify.
@MainActor
final class ClientFocusTests: MangoTestCase {
    func rig() -> (EngineRig, Client, Client) {
        let r = EngineRig()
        let a = r.window(1), b = r.window(2)
        r.arrange()
        r.server.clientFocus(a, true)
        r.settle()
        fake(r).focused = []
        fake(r).raised = []
        return (r, a, b)
    }

    func fake(_ r: EngineRig) -> FakeWindowSystem { r.server.system as! FakeWindowSystem }

    func testTheSeatIsTheClientMangoLastNotified() {
        let (r, a, b) = rig()
        XCTAssertTrue(r.server.system.keyboardFocusedSurface === a)
        r.server.clientFocus(b, true)
        XCTAssertTrue(r.server.system.keyboardFocusedSurface === b)
        r.settle()
        XCTAssertEqual(fake(r).focused.map(\.id), [b.id])
    }

    func testAlreadyFocusedItReturnsEarly() {
        let (r, a, b) = rig()
        r.monitor.prevsel = b.id
        r.server.clientFocus(a, true)
        XCTAssertEqual(r.monitor.prevsel, b.id, "the state is left as it is")
        r.settle()
        XCTAssertTrue(fake(r).focused.isEmpty, "no notify")
        XCTAssertEqual(fake(r).raised, [a.id], "lift comes before the early return")
    }

    func testFocusedAgainPrevselIsSel() {
        let (r, a, _) = rig()
        r.server.system.keyboardNotifyClearFocus()
        r.server.clientFocus(a, true)
        XCTAssertEqual(r.monitor.prevsel, a.id)
        XCTAssertEqual(r.monitor.sel, a.id)
    }

    func testLiftAndFocusAreOneNativeCall() {
        let (r, _, b) = rig()
        r.server.clientFocus(b, true)
        r.settle()
        XCTAssertEqual(fake(r).focused.first?.id, b.id)
        XCTAssertEqual(fake(r).focused.first?.raise, true)
        XCTAssertTrue(fake(r).raised.isEmpty, "the raise goes with the focus")
    }

    func testWithoutLiftTheKeyboardStillMoves() {
        let (r, _, b) = rig()
        r.server.clientFocus(b, false)
        r.settle()
        XCTAssertEqual(fake(r).focused.first?.id, b.id, "client_notify_enter, as sloppy focus gives it")
        XCTAssertEqual(fake(r).focused.first?.raise, false)
    }

    func testAClickInMacOSUpdatesSelAndSendsNoFocusBack() {
        let (r, _, b) = rig()
        r.server.mac.windowFocused(id: b.id)
        XCTAssertEqual(r.monitor.sel, b.id)
        XCTAssertTrue(r.server.system.keyboardFocusedSurface === b)
        r.settle()
        XCTAssertTrue(fake(r).focused.isEmpty, "macOS has it already")
    }

    func testAnotherAppTakingTheKeyboardClearsTheSeat() {
        let (r, a, _) = rig()
        r.server.mac.appActivated(pid: a.pid + 1)
        XCTAssertNil(r.server.system.keyboardFocusedSurface)
        r.server.clientFocus(a, true)
        r.settle()
        XCTAssertEqual(fake(r).focused.map(\.id), [a.id], "given back")
    }

    func testAGoneClientIsNotTheSeat() {
        let (r, a, _) = rig()
        r.server.handleClientUnmap(a)
        r.server.handleClientDestroy(a)
        XCTAssertFalse(r.server.system.keyboardFocusedSurface === a)
    }

    func testWhileHeldNoFocusGoesToMacOSUntilReleased() {
        let (r, _, b) = rig()
        r.server.holdNativeFocus = true
        r.server.clientFocus(b, true)
        r.settle()
        XCTAssertTrue(fake(r).focused.isEmpty)
        r.server.holdNativeFocus = false
        r.settle()
        XCTAssertEqual(fake(r).focused.map(\.id), [b.id])
    }

    func testFocusingNothingClearsTheSeat() {
        let (r, _, _) = rig()
        r.server.clientFocus(nil, false)
        XCTAssertNil(r.server.system.keyboardFocusedSurface)
    }

    func testAParkedGroupMemberIsNotRaised() {
        let (r, a, b) = rig()
        r.server.clientGroupJoin(b, a)
        r.arrange()
        XCTAssertTrue(b.isGroupMember)
        r.settle()
        fake(r).raised = []
        r.server.system.keyboardNotifyClearFocus()
        r.server.clientFocus(b, true)
        r.settle()
        XCTAssertFalse(fake(r).raised.contains(where: { id in r.server.clientByIdAll(id)?.groupParked == true }),
                       "a parked group member is not raised")
    }

    func testTheGroupMemberSwitchedToIsLifted() {
        let (r, a, b) = rig()
        r.server.clientGroupJoin(b, a)
        r.arrange()
        r.settle()
        let shown = a.isGroupFocus ? a : b, other = shown === a ? b : a
        XCTAssertTrue(other.parked)
        fake(r).focused = []
        r.server.groupFocus(Arg(i: shown.groupNext === other ? NEXT : PREV))
        r.settle()
        XCTAssertEqual(r.server.focused?.id, other.id)
        XCTAssertEqual(fake(r).focused.last?.id, other.id)
        XCTAssertEqual(fake(r).focused.last?.raise, true,
                       "parked when it is focused, placed by the arrange after: macOS gets it lifted")
    }
}
