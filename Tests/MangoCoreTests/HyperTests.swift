import XCTest
@testable import Mango
@testable import Port

@MainActor
final class HyperTests: MangoTestCase {
    let h: Modifiers = [.superKey, .ctrl, .alt]

    func testTheHyperSetHeldIsHyper() {
        XCTAssertEqual(KeyboardOptions.hyperMods(h, hyper: h, keyHeld: false), .hyper)
        XCTAssertEqual(KeyboardOptions.hyperMods(h.union(.shift), hyper: h, keyHeld: false), [.hyper, .shift])
        XCTAssertEqual(KeyboardOptions.hyperMods(h.union(.fn), hyper: h, keyHeld: false), [.hyper, .fn])
        XCTAssertEqual(KeyboardOptions.hyperMods([.superKey, .ctrl], hyper: h, keyHeld: false), [.superKey, .ctrl], "part of it is not")
        XCTAssertEqual(KeyboardOptions.hyperMods(.shift, hyper: h, keyHeld: true), [.hyper, .shift], "the Hyper key")
        XCTAssertEqual(KeyboardOptions.hyperMods(h, hyper: [], keyHeld: false), h, "no hyper set")
    }

    func testTheHyperSetIsChutneyHyperModifier() {
        var c = Config()
        c.chutneyHyperModifier = "super+ctrl"
        XCTAssertEqual(KeyboardOptions.hyperSet(c), [.superKey, .ctrl])
        XCTAssertFalse(ConfigParser.parse(text: "chutney_hyper_modifier=hyper+shift\n", baseDirectory: nil, fileName: "t.conf")
            .errors.isEmpty, "HYPER cannot stand for itself")
    }

    func testTheRouterSeesTheHyperSetAsHyper() {
        let router = InputRouter()
        let b = KeyBinding(mods: [.hyper, .shift], keyName: "h", keyCodes: [4], dispatch: Dispatch(name: "tag", args: ["2"]))
        router.publish { s in s.bindings = [b]; s.hyper = self.h }
        let down = KeyEvent(keyCode: 4, mods: h.union(.shift), isDown: true, isRepeat: false, isModifierKey: false)
        XCTAssertTrue(router.key(down, modifierOnlySinceDown: false), "⌃⌥⌘⇧H is HYPER+SHIFT,h")
        let other = KeyEvent(keyCode: 4, mods: [.superKey, .shift], isDown: true, isRepeat: false, isModifierKey: false)
        XCTAssertFalse(router.key(other, modifierOnlySinceDown: false))
    }

    /// Every binding fires on the keys a person presses for it exactly as when the core resolved HYPER
    /// to chutney_hyper_modifier: the bindings matched before and after are the same.
    func assertTheSameAsBefore(_ c: Config, _ name: String) {
        let h = KeyboardOptions.hyperSet(c)
        func before(_ m: Modifiers) -> Modifiers { m.contains(.hyper) ? m.subtracting(.hyper).union(h) : m }
        let old = c.keyBindings.map { b -> KeyBinding in var o = b; o.mods = before(b.mods); return o }
        XCTAssertFalse(c.keyBindings.isEmpty, name)
        for b in c.keyBindings {
            let held = before(b.mods)
            let release = b.flags.contains(.release)
            let modifier = HotkeyMatcher.modifier(forKeyCode: b.keyCodes[0])
            func fired(_ binds: [KeyBinding], _ mods: Modifiers) -> [Dispatch] {
                Keyboard.keyboardCheckKeybinding(binds, mode: b.mode, keyCode: b.keyCodes[0], mods: mods, isDown: !release,
                                                 keyModifier: modifier.isEmpty ? nil : modifier,
                                                 lastHoldKeycodeIsThisKey: true).map(\.dispatch)
            }
            XCTAssertEqual(fired(c.keyBindings, KeyboardOptions.hyperMods(held, hyper: h, keyHeld: false)), fired(old, held),
                           "\(name): \(b.mods.mangoDescription),\(b.keyName)")
        }
        for b in c.mouseBindings {
            let held = before(b.mods)
            XCTAssertEqual(c.mouseBindings.filter { $0.button == b.button && $0.mods == KeyboardOptions.hyperMods(held, hyper: h, keyHeld: false) }.map(\.dispatch),
                           c.mouseBindings.filter { $0.button == b.button && before($0.mods) == held }.map(\.dispatch), "\(name): mouse")
        }
        for b in c.axisBindings {
            let held = before(b.mods)
            XCTAssertEqual(c.axisBindings.filter { $0.direction == b.direction && $0.mods == KeyboardOptions.hyperMods(held, hyper: h, keyHeld: false) }.map(\.dispatch),
                           c.axisBindings.filter { $0.direction == b.direction && before($0.mods) == held }.map(\.dispatch), "\(name): axis")
        }
        XCTAssertEqual(KeyboardOptions.unreachable(c), [], "\(name): no binding the hyper set hides")
    }

    func testTheShippedConfigFiresAsBefore() {
        _ = EngineRig()
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/config.conf")
        assertTheSameAsBefore(ConfigParser.parseConfig(fileAt: url).config, "Resources/config.conf")
    }

    func testYourConfigFiresAsBefore() throws {
        _ = EngineRig()
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/.config/mango/config.conf")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("no ~/.config/mango/config.conf") }
        assertTheSameAsBefore(ConfigParser.parseConfig(fileAt: url).config, "~/.config/mango/config.conf")
    }
}
