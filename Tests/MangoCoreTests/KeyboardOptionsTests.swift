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
}
