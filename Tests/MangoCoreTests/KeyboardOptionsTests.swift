import XCTest
@testable import Mango
@testable import Port

/// mango's xkb_rules_options on macOS: the options that move keys, and caps:hyper.
@MainActor
final class KeyboardOptionsTests: MangoTestCase {
    typealias K = KeyboardOptions

    func testTheOptionsThatMoveKeys() {
        XCTAssertEqual(K.mappings(["caps:hyper"]), [.init(src: K.capsLock, dst: K.f18)])
        XCTAssertEqual(K.mappings(["caps:escape"]), [.init(src: K.capsLock, dst: K.escape)])
        XCTAssertEqual(K.mappings(["ctrl:swapcaps"]), [.init(src: K.capsLock, dst: K.leftControl),
                                                       .init(src: K.leftControl, dst: K.capsLock)])
        XCTAssertEqual(K.mappings(["caps:super", "caps:escape"]), [.init(src: K.capsLock, dst: K.leftGUI)], "the first wins")
        XCTAssertEqual(K.mappings(["grp:alt_shift_toggle", "compose:ralt"]), [], "not a key move")
        XCTAssertEqual(MangoServer.xkbOptions(" Caps:Hyper , ctrl:swapcaps,,"), ["caps:hyper", "ctrl:swapcaps"])
    }

    /// An option that takes Caps Lock's key leaves no key to turn its lock off: mango turns
    /// it off (a lock left on kept every letter a capital). Swapping keeps a Caps Lock key.
    func testCapsLocksLockIsTurnedOffWhenItsKeyIsTaken() {
        typealias K = KeyboardOptions
        for o in ["caps:hyper", "caps:escape", "ctrl:nocaps", "caps:super", "caps:ctrl_modifier"] {
            XCTAssertTrue(K.takesCapsLock(K.mappings([o])), o)
        }
        for o in ["caps:swapescape", "ctrl:swapcaps", "altwin:swap_alt_win"] {
            XCTAssertFalse(K.takesCapsLock(K.mappings([o])), o)
        }
        XCTAssertFalse(K.takesCapsLock([]))
    }

    func testMangoAppliesTheOptionsWithTheConfig() throws {
        let r = EngineRig()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mango-xkb-\(UUID()).conf")
        try "xkb_rules_options=caps:hyper\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        r.server.configURL = url
        r.server.reloadConfig()
        XCTAssertEqual((r.server.system as! FakeWindowSystem).keyboardOptions, "caps:hyper")
    }

    /// caps:hyper: Caps Lock (F18) held is mango's hyper for the bindings; the key itself is
    /// mango's; let go, the bindings are plain again.
    func testCapsLockHeldIsHyper() {
        let r = EngineRig()
        r.server.config.xkbRulesOptions = "caps:hyper"
        r.server.config.chutneyHyperModifier = "super+ctrl+alt"
        r.server.publishInputState()
        let hyper = Modifiers.parse("hyper", hyperModifier: "super+ctrl+alt")!
        let router = r.server.mac.router
        router.publish { $0.bindings = [KeyBinding(mods: hyper, keyName: "h", keyCodes: [4],
                                                   dispatch: Dispatch(name: "view", args: ["2"]))] }
        router.server = nil   // the bind's dispatch is not under test
        func key(_ code: UInt16, down: Bool) -> KeyEvent {
            KeyEvent(keyCode: code, mods: [], isDown: down, isRepeat: false, isModifierKey: false)
        }
        XCTAssertFalse(router.key(key(4, down: true), modifierOnlySinceDown: false), "h alone: the app's")
        XCTAssertTrue(router.key(key(K.hyperKeyCode, down: true), modifierOnlySinceDown: false), "the hyper key is mango's")
        XCTAssertTrue(router.key(key(4, down: true), modifierOnlySinceDown: false), "hyper+h: the binding")
        _ = router.key(key(4, down: false), modifierOnlySinceDown: false)
        XCTAssertTrue(router.key(key(K.hyperKeyCode, down: false), modifierOnlySinceDown: false))
        XCTAssertFalse(router.key(key(4, down: true), modifierOnlySinceDown: false), "let go: h is the app's again")
    }

    /// chutney_hyper_key (port extension): the chosen key becomes F18, held as Hyper.
    func testTheHyperKeysMapping() {
        XCTAssertEqual(K.hyperKeyMapping("caps_lock"), .init(src: K.capsLock, dst: K.f18))
        XCTAssertEqual(K.hyperKeyMapping("left_control"), .init(src: K.leftControl, dst: K.f18))
        XCTAssertEqual(K.hyperKeyMapping("left_option"), .init(src: K.leftAlt, dst: K.f18))
        XCTAssertEqual(K.hyperKeyMapping("right_command"), .init(src: K.rightGUI, dst: K.f18))
        XCTAssertEqual(K.hyperKeyMapping("right_option"), .init(src: K.rightAlt, dst: K.f18))
        XCTAssertEqual(K.hyperKeyMapping("f1"), .init(src: 0x7_0000_003A, dst: K.f18))
        XCTAssertEqual(K.hyperKeyMapping("f12"), .init(src: 0x7_0000_0045, dst: K.f18))
        XCTAssertNil(K.hyperKeyMapping(""))
        XCTAssertEqual(K.hyperKeys.count, 1 + 8 + 12, "Raycast's: Caps Lock, the eight modifiers, F1 … F12")
        func parse(_ text: String) -> ParsedConfig {
            ConfigParser.parse(text: text, baseDirectory: FileManager.default.temporaryDirectory, fileName: "t.conf")
        }
        XCTAssertTrue(parse("chutney_hyper_tap=original\n").errors.isEmpty)
        let p = parse("chutney_hyper_key=Right_Command\nchutney_hyper_tap=escape\n")
        XCTAssertEqual(p.errors, [])
        XCTAssertEqual(p.config.chutneyHyperKey, "right_command")
        XCTAssertEqual(p.config.chutneyHyperTap, "escape")
        XCTAssertFalse(parse("chutney_hyper_key=fn\n").errors.isEmpty, "not a Hyper key")
        XCTAssertEqual(Config().chutneyHyperKey, "", "none unless set")
    }

    /// Quick Press as Raycast's: only Caps Lock and a function key have one; the key itself is
    /// Caps Lock's lock, or the function key sent.
    func testQuickPress() {
        XCTAssertEqual(MacWindowSystem.hyperTap(key: "caps_lock", tap: "escape"), .key(53))
        XCTAssertEqual(MacWindowSystem.hyperTap(key: "caps_lock", tap: "original"), .capsLock)
        XCTAssertEqual(MacWindowSystem.hyperTap(key: "f5", tap: "original"), .key(96))
        XCTAssertEqual(MacWindowSystem.hyperTap(key: "right_command", tap: "escape"), .none, "a modifier has none")
        XCTAssertEqual(MacWindowSystem.hyperTap(key: "caps_lock", tap: "none"), .none)
    }

    /// chutney_hyper_key's key held is Hyper as caps:hyper's is; with chutney_hyper_tap escape,
    /// pressed and let go alone it is Escape, and not when a key came between.
    func testTheHyperKeyHeldIsHyperAndAloneIsEscape() {
        let r = EngineRig()
        r.server.config.chutneyHyperKey = "caps_lock"
        r.server.config.chutneyHyperTap = "escape"
        r.server.publishInputState()
        let hyper = Modifiers.parse("hyper", hyperModifier: r.server.config.hyperModifier)!
        let router = r.server.mac.router
        router.publish { $0.bindings = [KeyBinding(mods: hyper, keyName: "h", keyCodes: [4],
                                                   dispatch: Dispatch(name: "view", args: ["2"]))] }
        router.server = nil
        var escapes = 0
        router.hyperTapped = { if $0 == .key(53) { escapes += 1 } }
        func key(_ code: UInt16, down: Bool) -> KeyEvent {
            KeyEvent(keyCode: code, mods: [], isDown: down, isRepeat: false, isModifierKey: false)
        }
        XCTAssertTrue(router.key(key(K.hyperKeyCode, down: true), modifierOnlySinceDown: false))
        XCTAssertTrue(router.key(key(K.hyperKeyCode, down: false), modifierOnlySinceDown: false))
        XCTAssertEqual(escapes, 1, "alone: Escape")
        _ = router.key(key(K.hyperKeyCode, down: true), modifierOnlySinceDown: false)
        XCTAssertTrue(router.key(key(4, down: true), modifierOnlySinceDown: false), "hyper+h: the binding")
        _ = router.key(key(4, down: false), modifierOnlySinceDown: false)
        _ = router.key(key(K.hyperKeyCode, down: false), modifierOnlySinceDown: false)
        XCTAssertEqual(escapes, 1, "a key came between: no Escape")
    }
}
