import XCTest
@testable import Mango
@testable import Port

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

    func testCapsLockHeldIsHyper() {
        let r = EngineRig()
        r.server.config.xkbRulesOptions = "caps:hyper"
        r.server.config.chutneyHyperModifier = "super+ctrl+alt"
        r.server.publishInputState()
        let hyper = Modifiers.hyper
        let router = r.server.mac.router
        router.publish { $0.bindings = [KeyBinding(mods: hyper, keyName: "h", keyCodes: [4],
                                                   dispatch: Dispatch(name: "view", args: ["2"]))] }
        router.server = nil
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
        let p = parse("chutney_hyper_key=Right_Command\n")
        XCTAssertEqual(p.errors, [])
        XCTAssertEqual(p.config.chutneyHyperKey, "right_command")
        XCTAssertFalse(parse("chutney_hyper_key=fn\n").errors.isEmpty, "not a Hyper key")
        XCTAssertEqual(Config().chutneyHyperKey, "", "none unless set")
    }

    func testTheHyperKeyHeldIsHyper() {
        let r = EngineRig()
        r.server.config.chutneyHyperKey = "caps_lock"
        r.server.publishInputState()
        let hyper = Modifiers.hyper
        let router = r.server.mac.router
        router.publish { $0.bindings = [KeyBinding(mods: hyper, keyName: "h", keyCodes: [4],
                                                   dispatch: Dispatch(name: "view", args: ["2"]))] }
        router.server = nil
        func key(_ code: UInt16, down: Bool) -> KeyEvent {
            KeyEvent(keyCode: code, mods: [], isDown: down, isRepeat: false, isModifierKey: false)
        }
        XCTAssertTrue(router.key(key(K.hyperKeyCode, down: true), modifierOnlySinceDown: false), "the key itself is swallowed")
        XCTAssertTrue(router.key(key(4, down: true), modifierOnlySinceDown: false), "hyper+h: the binding")
        _ = router.key(key(4, down: false), modifierOnlySinceDown: false)
        XCTAssertTrue(router.key(key(K.hyperKeyCode, down: false), modifierOnlySinceDown: false))
    }

    func testTheUserKeyMappingIsRead() {
        let text = """
        RegistryID  Key                   Value
        100000cf8   UserKeyMapping   (null)
        100000b49   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            },
                {
                HIDKeyboardModifierMappingDst = 30064771113;
                HIDKeyboardModifierMappingSrc = 30064771300;
            }
        )
        100000bb1   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        """
        XCTAssertEqual(KeyboardOptions.parseUserKeyMapping(text), [
            KeyboardOptions.Mapping(src: 30064771129, dst: 30064771181),
            KeyboardOptions.Mapping(src: 30064771300, dst: 30064771113),
        ])
        XCTAssertEqual(KeyboardOptions.parseUserKeyMapping("100000cf8   UserKeyMapping   (null)"), [])
    }

    func testTheUsersMovesStay() {
        let mine = KeyboardOptions.Mapping(src: 1, dst: 2), caps = KeyboardOptions.Mapping(src: 3, dst: 4)
        let hyper = KeyboardOptions.Mapping(src: 3, dst: KeyboardOptions.f18)
        XCTAssertEqual(KeyboardOptions.merged(user: [mine, caps], mango: [hyper]), [mine, hyper])
        XCTAssertEqual(KeyboardOptions.merged(user: [mine], mango: []), [mine])
    }
}
