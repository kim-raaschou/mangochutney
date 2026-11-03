import XCTest
@testable import Mango
@testable import Port

/// `HotkeyMatcher`: mango key-mode and flag semantics on top of CGEvent key codes.
final class EngineHotkeyTests: MangoTestCase {
    // US key codes: j = 38, Return = 36, Left arrow = 123, Super_L = 55.
    func bind(_ mods: Modifiers, _ code: UInt16, mode: String = "default", flags: KeyBindingFlags = [],
              _ name: String = "x") -> KeyBinding {
        KeyBinding(mode: mode, mods: mods, keyName: "k\(code)", keyCodes: [code], flags: flags,
                   dispatch: Dispatch(name: name))
    }

    func key(_ code: UInt16, _ mods: Modifiers, down: Bool = true, repeating: Bool = false, modifierKey: Bool = false) -> KeyEvent {
        KeyEvent(keyCode: code, mods: mods, isDown: down, isRepeat: repeating, isModifierKey: modifierKey)
    }

    func testExactModifierMatch() {
        let m = HotkeyMatcher()
        m.bindings = [bind(.superKey, 38, "focusstack")]
        XCTAssertEqual(m.match(key(38, .superKey), lastHeldIsThisKey: true).map(\.dispatch.name), ["focusstack"])
        XCTAssertTrue(m.match(key(38, [.superKey, .shift]), lastHeldIsThisKey: true).isEmpty, "extra modifier must not match")
        XCTAssertTrue(m.match(key(38, []), lastHeldIsThisKey: true).isEmpty)
        XCTAssertTrue(m.match(key(38, .superKey, down: false), lastHeldIsThisKey: true).isEmpty, "keyUp must not fire a press bind")
    }

    func testFnFlagOnArrowKeysIsIgnoredUnlessBound() {
        let m = HotkeyMatcher()
        m.bindings = [bind(.superKey, 123, "focusdir")]
        // Apple keyboards set the fn flag for arrow keys.
        XCTAssertEqual(m.match(key(123, [.superKey, .fn]), lastHeldIsThisKey: true).count, 1)
        m.bindings = [bind([.superKey, .fn], 123, "focusdir")]
        XCTAssertEqual(m.match(key(123, [.superKey, .fn]), lastHeldIsThisKey: true).count, 1)
        XCTAssertTrue(m.match(key(123, .superKey), lastHeldIsThisKey: true).isEmpty, "fn bound explicitly must be present")
    }

    func testReleaseBindFiresOnlyOnReleaseOfLastHeldKey() {
        let m = HotkeyMatcher()
        m.bindings = [bind(.superKey, 38, flags: .release, "toggleoverview")]
        XCTAssertTrue(m.match(key(38, .superKey, down: true), lastHeldIsThisKey: true).isEmpty)
        XCTAssertEqual(m.match(key(38, .superKey, down: false), lastHeldIsThisKey: true).count, 1)
        XCTAssertTrue(m.match(key(38, .superKey, down: false), lastHeldIsThisKey: false).isEmpty)
    }

    func testModifierOnlyBinds() {
        let m = HotkeyMatcher()
        // bind=none,Super_L (press) and bindr=SUPER,Super_L (release)
        m.bindings = [bind([], 55, "a"), bind(.superKey, 55, flags: .release, "b")]
        // Press of Super_L: flags already contain command.
        XCTAssertEqual(m.match(key(55, .superKey, modifierKey: true), lastHeldIsThisKey: true).map(\.dispatch.name), ["a"])
        // Press with another modifier held is a different chord.
        XCTAssertTrue(m.match(key(55, [.superKey, .shift], modifierKey: true), lastHeldIsThisKey: true).isEmpty)
        // Release after a bare tap.
        XCTAssertEqual(m.match(key(55, [], down: false, modifierKey: true), lastHeldIsThisKey: true).map(\.dispatch.name), ["b"])
        // Release after another key was used with it: no tap.
        XCTAssertTrue(m.match(key(55, [], down: false, modifierKey: true), lastHeldIsThisKey: false).isEmpty)
    }

    func testFirstMatchWinsUnlessAllowConflict() {
        let m = HotkeyMatcher()
        m.bindings = [bind(.superKey, 38, "first"), bind(.superKey, 38, "second")]
        XCTAssertEqual(m.match(key(38, .superKey), lastHeldIsThisKey: true).map(\.dispatch.name), ["first"])
        m.bindings = [bind(.superKey, 38, flags: .allowConflict, "first"), bind(.superKey, 38, "second")]
        XCTAssertEqual(m.match(key(38, .superKey), lastHeldIsThisKey: true).map(\.dispatch.name), ["first", "second"])
    }

    func testKeyModes() {
        let m = HotkeyMatcher()
        m.bindings = [bind(.superKey, 38, mode: "default", "d"), bind(.superKey, 38, mode: "resize", "r"),
                      bind(.superKey, 36, mode: "common", "c")]
        XCTAssertEqual(m.match(key(38, .superKey), lastHeldIsThisKey: true).map(\.dispatch.name), ["d"])
        XCTAssertEqual(m.match(key(36, .superKey), lastHeldIsThisKey: true).map(\.dispatch.name), ["c"])
        m.mode = "resize"
        XCTAssertEqual(m.match(key(38, .superKey), lastHeldIsThisKey: true).map(\.dispatch.name), ["r"])
        XCTAssertEqual(m.match(key(36, .superKey), lastHeldIsThisKey: true).map(\.dispatch.name), ["c"], "common binds apply in every mode")
    }

    func testCGFlagsMapping() {
        var flags: CGEventFlags = [.maskCommand, .maskAlternate, .maskNumericPad, .maskAlphaShift]
        XCTAssertEqual(Modifiers(cgFlags: flags), [.superKey, .alt], "numpad / caps lock flags are not modifiers")
        flags = [.maskControl, .maskShift, .maskSecondaryFn]
        XCTAssertEqual(Modifiers(cgFlags: flags), [.ctrl, .shift, .fn])
    }
}
