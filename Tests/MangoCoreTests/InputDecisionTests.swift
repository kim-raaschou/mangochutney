import XCTest
@testable import Port
@testable import Mango

/// mango's input decisions in the core (Keyboard, Pointer), without the port's event tap.
final class InputDecisionTests: MangoTestCase {
    func bind(_ mods: Modifiers, _ code: UInt16, mode: String = "default", flags: KeyBindingFlags = [],
              _ name: String = "x") -> KeyBinding {
        KeyBinding(mode: mode, mods: mods, keyName: "k\(code)", keyCodes: [code], flags: flags, dispatch: Dispatch(name: name))
    }

    /// keyboard_check_keybinding: the first match ends the search, setkeymode too even with `c`.
    func testKeyboardCheckKeybinding() {
        let bs = [bind(.superKey, 38, flags: .allowConflict, "setkeymode"), bind(.superKey, 38, "second")]
        let out = Keyboard.keyboardCheckKeybinding(bs, mode: "default", keyCode: 38, mods: .superKey, isDown: true,
                                                   keyModifier: nil, lastHoldKeycodeIsThisKey: true)
        XCTAssertEqual(out.map(\.dispatch.name), ["setkeymode"])
        // A modifier key's press is matched with the modifiers from before it.
        let mod = Keyboard.keyboardCheckKeybinding([bind([], 55, "tap")], mode: "default", keyCode: 55, mods: .superKey,
                                                   isDown: true, keyModifier: .superKey, lastHoldKeycodeIsThisKey: true)
        XCTAssertEqual(mod.map(\.dispatch.name), ["tap"])
    }

    /// pointer_process_button_press: the switcher, then the overview, then a mouse binding.
    func testButtonPressOrder() {
        let mb = MouseBinding(mode: "default", mods: .superKey, button: .left, dispatch: Dispatch(name: "moveresize"))
        let p = CGPoint(x: 10, y: 10), ov = CGRect(x: 0, y: 0, width: 100, height: 100)
        func press(_ button: Int, switcher: Bool = false, overview: CGRect? = nil, mods: Modifiers = .superKey) -> Pointer.ButtonPress {
            Pointer.pointerProcessButtonPress(button: button, at: p, mods: mods, switcherActive: switcher,
                                              overviewFrame: overview, mouseBindings: [mb], mode: "default")
        }
        XCTAssertEqual(press(0, switcher: true, overview: ov), .switcher)
        XCTAssertEqual(press(0, overview: ov), .overview)
        XCTAssertEqual(press(2, overview: ov), .none, "a middle press is not the overview's")
        XCTAssertEqual(press(0), .mouseBinding(mb))
        XCTAssertEqual(press(0, mods: []), .none)
    }

    /// handle_cursor_axis: fires after the timeout or when the wheel turns; renews otherwise.
    func testHandleCursorAxis() {
        let ab = AxisBinding(mode: "default", mods: .superKey, direction: .down, dispatch: Dispatch(name: "viewtoright"))
        func axis(_ d: Direction, now: Double, at: Double, dir: Int) -> (AxisBinding, Bool, Int)? {
            Pointer.handleCursorAxis(direction: d, mods: .superKey, now: now, applyTime: at, applyDir: dir,
                                     axisBindings: [ab], mode: "default", timeout: 0.1).map { ($0.binding, $0.fires, $0.dir) }
        }
        XCTAssertEqual(axis(.down, now: 1, at: 0, dir: 0)?.1, true, "older than the timeout")
        XCTAssertEqual(axis(.down, now: 1.05, at: 1, dir: 1)?.1, false, "within it, the same way")
        XCTAssertNil(axis(.up, now: 1, at: 0, dir: 0), "no binding for up")
    }

    func key(_ code: UInt16, _ mods: Modifiers = .superKey, down: Bool = true, modifier: Modifiers? = nil) -> KeyInput {
        KeyInput(keyCode: code, mods: mods, isDown: down, isRepeat: false, keyModifier: modifier)
    }

    /// handle_keyboard_key: a bound press is swallowed and so is its release
    /// (keyboard_is_bound_key); a modifier released commits the switcher; a release ends a
    /// comboview.
    func testHandleKeyboardKey() {
        var st = KeyboardState()
        let b = bind(.superKey, 38, "focusstack")
        func run(_ k: KeyInput, switcher: Bool = false, combo: Bool = false) -> ([KeyAction], Bool, Bool) {
            let d = Keyboard.handleKeyboardKey(k, state: &st, bindings: [b], mode: "default", overcircleActive: false,
                                               switcherActive: switcher, tagCombo: combo, cursorHideOnKeypress: false)
            return (d.actions, d.handled, d.swallow)
        }
        let press = run(key(38))
        XCTAssertEqual(press.0, [.binding(b, held: false)])
        XCTAssertTrue(press.1 && press.2)
        let release = run(key(38, down: false))
        XCTAssertEqual(release.0, [], "no binding on the release")
        XCTAssertTrue(release.1 && release.2, "but handled and swallowed: its press was (mango handled = 1)")
        XCTAssertEqual(run(key(55, [], down: false, modifier: .superKey), switcher: true, combo: true).0,
                       [.endTagCombo, .switcherCommit])
    }

    /// After the bindings: jump mode takes Escape and a label's key; a global_key_binding
    /// goes to its app, press and release.
    func testHandleUnboundKey() {
        var st = KeyboardState()
        XCTAssertEqual(Keyboard.handleUnboundKey(key(53, []), state: &st, jumpActive: true, isEscape: true,
                                                 jumpLabel: nil, globalKeys: []).action, .overviewKey(.escape))
        XCTAssertEqual(Keyboard.handleUnboundKey(key(0, []), state: &st, jumpActive: true, isEscape: false,
                                                 jumpLabel: "A", globalKeys: []).action, .overviewKey(.jump("A")))
        let g = [(mods: Modifiers.ctrl, keyCodes: Set<UInt16>([1]), pid: pid_t(42))]
        XCTAssertEqual(Keyboard.handleUnboundKey(key(1, .ctrl), state: &st, jumpActive: false, isEscape: false,
                                                 jumpLabel: nil, globalKeys: g).action, .forward(42, down: true))
        XCTAssertEqual(Keyboard.handleUnboundKey(key(1, [], down: false), state: &st, jumpActive: false, isEscape: false,
                                                 jumpLabel: nil, globalKeys: g).action, .forward(42, down: false))
        XCTAssertNil(Keyboard.handleUnboundKey(key(2, []), state: &st, jumpActive: false, isEscape: false,
                                               jumpLabel: nil, globalKeys: g).action)
    }
}
