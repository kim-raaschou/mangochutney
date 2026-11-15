import XCTest
@testable import Mango
@testable import Port

/// mango's jump mode: toggle_jump (bind.c), create_jump_hints and finish_jump_mode (layout/overview.c),
/// overview_update_jump_label (overview/overview.c) and the jump keys of handle_keyboard_key (keyboard.c).
@MainActor
final class JumpModeTests: MangoTestCase {
    func fake(_ r: EngineRig) -> FakeWindowSystem { r.server.system as! FakeWindowSystem }

    func rig(_ n: Int = 3) -> (EngineRig, [Client]) {
        let r = EngineRig()
        let cs = (1...n).map { r.map(CGWindowID($0)) }
        r.server.arrange(r.monitor, .none)
        return (r, cs)
    }

    func jump(_ r: EngineRig) { _ = r.server.dispatch(Dispatch(name: "togglejump", args: []), target: nil) }

    func testToggleJumpEntersOverviewWithAHintPerClientInClientOrder() {
        let (r, _) = rig()
        jump(r)
        XCTAssertTrue(r.monitor.isJumpMode)
        XCTAssertTrue(r.server.anyOverview)
        let labels = Array(r.server.config.jumpLabels)
        for (i, c) in r.server.clients.enumerated() {
            XCTAssertEqual(c.jumpChar, labels[i])
            XCTAssertEqual(fake(r).jumpLabels[c.id]?.text, String(labels[i]))
            XCTAssertEqual(fake(r).jumpLabels[c.id]?.enabled, true)
        }
    }

    func testTheLabelIsCentredOnTheCard() {
        let (r, cs) = rig(1)
        jump(r)
        let card = r.server.selectedMonitor.ovCards[cs[0].id]!
        let p = fake(r).jumpLabels[cs[0].id]!.position
        XCTAssertEqual(p.x, card.minX + ((card.width - 40) / 2).rounded(.towardZero))
        XCTAssertEqual(p.y, card.minY + ((card.height - 40) / 2).rounded(.towardZero))
    }

    func testTheLabelsAreJumpLabelsAsWritten() {
        let (r, cs) = rig(2)
        r.server.config.jumpLabels = "qw"
        jump(r)
        let chars = Set(cs.compactMap(\.jumpChar))
        XCTAssertEqual(chars, ["q", "w"], "not upper-cased: mango shows the character as written")
    }

    func testClientsBeyondTheLabelsGetNone() {
        let (r, _) = rig(3)
        r.server.config.jumpLabels = "AB"
        jump(r)
        XCTAssertEqual(r.server.clients.map(\.jumpChar), ["A", "B", nil])
    }

    func testAJumpKeyFocusesItsClientAndLeavesOverview() {
        let (r, _) = rig()
        jump(r)
        let target = r.server.clients[1]
        let keycode = target.jumpKeycodes.keycode1!
        r.server.handleKeyboardKey([.overviewKey(.jump(keycode))])
        XCTAssertFalse(r.server.anyOverview)
        XCTAssertTrue(r.server.focused === target)
        XCTAssertFalse(r.monitor.isJumpMode)
        for c in r.server.clients {
            XCTAssertNil(c.jumpChar)
            XCTAssertEqual(c.jumpKeycodes, MultiKeycode())
            XCTAssertEqual(fake(r).jumpLabels[c.id]?.enabled, false)
        }
    }

    func testAKeyOfNoClientDoesNothing() {
        let (r, _) = rig(1)
        jump(r)
        r.server.handleKeyboardKey([.overviewKey(.jump(25))])
        XCTAssertTrue(r.server.anyOverview)
        XCTAssertTrue(r.monitor.isJumpMode)
    }

    func testEscapeIsToggleJump() {
        let (r, _) = rig()
        jump(r)
        r.server.handleKeyboardKey([.overviewKey(.escape)])
        XCTAssertFalse(r.server.anyOverview)
        XCTAssertFalse(r.monitor.isJumpMode)
    }

    func testAPassthroughBindingThatLeavesOverviewEndsJumpModeFirst() {
        let (r, _) = rig()
        jump(r)
        let leave = KeyBinding(mods: [], keyName: "escape", keyCodes: [53], dispatch: Dispatch(name: "leaveoverview", args: []))
        r.server.handleKeyboardKey([.binding(leave, held: false), .overviewKey(.escape)])
        XCTAssertFalse(r.server.anyOverview, "is_jump_mode is asked after the binding has left overview")
        XCTAssertFalse(r.monitor.isJumpMode)
    }

    func testToggleJumpOnAnEmptyMonitorLeavesNoJumpMode() {
        let r = EngineRig()
        jump(r)
        XCTAssertFalse(r.server.anyOverview, "no windows: no overview")
        XCTAssertFalse(r.monitor.isJumpMode, "a mango bug, docs/afvigelser.md §6: mango keeps is_jump_mode set")
        let a = r.map(1)
        r.server.arrange(r.monitor, .none)
        r.server.switcher("next")
        XCTAssertNotNil(r.server.switcherState, "the switcher is not refused afterwards")
        _ = a
    }

    func testToggleJumpAgainLeaves() {
        let (r, _) = rig()
        jump(r)
        jump(r)
        XCTAssertFalse(r.server.anyOverview)
        XCTAssertFalse(r.monitor.isJumpMode)
    }

    func testJumpModeIsNotOvercircleAndRefusesTheSwitcher() {
        let (r, _) = rig()
        jump(r)
        XCTAssertFalse(r.server.isOvercircleMode(r.monitor))
        r.server.leaveOverview()
        r.monitor.isJumpMode = true
        r.server.switcher("next")
        XCTAssertNil(r.server.switcherState, "mango's switcher returns in jump mode")
    }

    func testTheEventTapGetsTheJumpKeys() {
        let (r, cs) = rig(2)
        jump(r)
        func press(_ code: UInt16) -> Bool {
            fake(r).router.key(KeyEvent(keyCode: code, mods: [], isDown: true, isRepeat: false, isModifierKey: false),
                               modifierOnlySinceDown: false)
        }
        XCTAssertFalse(press(25), "not a jump key: it goes to the client")
        XCTAssertTrue(press(cs[1].jumpKeycodes.keycode1!), "a jump key is mango's")
        XCTAssertTrue(press(53), "Escape is mango's in jump mode")
    }

    func testTheLabelComesWithTheMapAndGoesWithTheUnmap() {
        let (r, cs) = rig(1)
        let label = fake(r).jumpLabels[cs[0].id]!
        XCTAssertFalse(label.enabled)
        r.server.handleClientUnmap(cs[0])
        XCTAssertTrue(label.destroyed)
        XCTAssertNil(cs[0].jumpLabelNode)
    }

    func testAReloadAppliesTheLabelConfig() {
        let (r, cs) = rig(1)
        r.server.config.jumplabeldata.paddingX = 7
        r.server.resetOption()
        XCTAssertEqual(fake(r).jumpLabels[cs[0].id]?.data.paddingX, 7)
    }
}
