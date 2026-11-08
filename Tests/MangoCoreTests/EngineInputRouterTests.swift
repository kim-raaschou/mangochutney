import XCTest
@testable import Mango
@testable import Port

final class EngineInputRouterTests: MangoTestCase {
    let hyper: Modifiers = [.superKey, .ctrl, .alt]

    func router(binds: [KeyBinding] = [], mouse: [MouseBinding] = [], axis: [AxisBinding] = [],
                overview: CGRect? = nil, jump: Bool = false, jumpKeys: Set<UInt16> = []) -> InputRouter {
        let r = InputRouter()
        r.publish { s in
            s.bindings = binds
            s.mouseBindings = mouse
            s.axisBindings = axis
            s.overviewFrame = overview
            s.jumpActive = jump
            s.jumpKeys = jumpKeys
            s.axisTimeout = 0.1
        }
        return r
    }

    func key(_ code: UInt16, _ mods: Modifiers, down: Bool) -> KeyEvent {
        KeyEvent(keyCode: code, mods: mods, isDown: down, isRepeat: false, isModifierKey: false)
    }

    func testBoundKeyIsSwallowedTogetherWithItsKeyUp() {
        let b = KeyBinding(mods: hyper, keyName: "Left", keyCodes: [123], dispatch: Dispatch(name: "focusdir", args: ["left"]))
        let r = router(binds: [b])
        XCTAssertTrue(r.key(key(123, hyper.union(.fn), down: true), modifierOnlySinceDown: false))
        XCTAssertTrue(r.key(key(123, [], down: false), modifierOnlySinceDown: false))
    }

    func testABoundModifierKeyStillReachesTheApps() {
        let b = KeyBinding(mods: [], keyName: "Super_L", keyCodes: [55], dispatch: Dispatch(name: "toggleoverview"))
        let r = router(binds: [b])
        XCTAssertFalse(r.key(KeyEvent(keyCode: 55, mods: [], isDown: true, isRepeat: false, isModifierKey: true),
                             modifierOnlySinceDown: false))
        XCTAssertFalse(r.key(KeyEvent(keyCode: 55, mods: .superKey, isDown: false, isRepeat: false, isModifierKey: true),
                             modifierOnlySinceDown: true))
    }

    func testCmdDigitsPickTabsOnlyWhileATabBarHasThem() {
        let r = router()
        XCTAssertFalse(r.key(key(19, [.superKey], down: true), modifierOnlySinceDown: false), "no tab bar: ⌘2 is the app's")
        r.publish { $0.tabShortcuts = 3 }
        XCTAssertTrue(r.key(key(19, [.superKey], down: true), modifierOnlySinceDown: false))
        XCTAssertTrue(r.key(key(19, [.superKey], down: false), modifierOnlySinceDown: false))
        XCTAssertFalse(r.key(key(21, [.superKey], down: true), modifierOnlySinceDown: false), "⌘4 with three tabs")
        XCTAssertFalse(r.key(key(19, [.superKey, .shift], down: true), modifierOnlySinceDown: false), "⇧⌘2")
        XCTAssertFalse(r.key(key(8, [.superKey], down: true), modifierOnlySinceDown: false), "⌘C")
    }

    func testUnboundKeysPassThrough() {
        let b = KeyBinding(mods: hyper, keyName: "Left", keyCodes: [123], dispatch: Dispatch(name: "focusdir", args: ["left"]))
        let r = router(binds: [b])
        XCTAssertFalse(r.key(key(123, [.superKey], down: true), modifierOnlySinceDown: false))
        XCTAssertFalse(r.key(key(123, [.superKey], down: false), modifierOnlySinceDown: false))
        XCTAssertFalse(r.key(key(0, [], down: true), modifierOnlySinceDown: false))
    }

    func testKeyModeIsRespected() {
        let w = KeyBinding(mode: "window", mods: [], keyName: "Left", keyCodes: [123], dispatch: Dispatch(name: "resizewin", args: ["-50", "+0"]))
        let r = router(binds: [w])
        XCTAssertFalse(r.key(key(123, [], down: true), modifierOnlySinceDown: false))
        r.publish { $0.keymode = "window" }
        XCTAssertTrue(r.key(key(123, [], down: true), modifierOnlySinceDown: false))
    }

    func testOverviewCapturesEscapeAndJumpLetters() {
        let screen = CGRect(x: 0, y: 0, width: 100, height: 100)
        let r = router(overview: screen, jump: true, jumpKeys: [0])
        XCTAssertTrue(r.key(key(53, [], down: true), modifierOnlySinceDown: false))
        XCTAssertTrue(r.key(key(0, [], down: true), modifierOnlySinceDown: false))
        XCTAssertTrue(r.key(key(0, [], down: false), modifierOnlySinceDown: false))
        XCTAssertFalse(r.key(key(11, [], down: true), modifierOnlySinceDown: false))
        let noJump = router(overview: screen, jump: false)
        XCTAssertFalse(noJump.key(key(0, [], down: true), modifierOnlySinceDown: false))
    }

    func testBindingsComeBeforeJumpLabels() {
        let w = KeyBinding(mode: "apps", mods: [], keyName: "w", keyCodes: [13], dispatch: Dispatch(name: "chutney_focus_app", args: ["com.mitchellh.ghostty"]))
        let r = router(binds: [w], overview: CGRect(x: 0, y: 0, width: 100, height: 100), jump: true, jumpKeys: [13])
        r.publish { $0.keymode = "apps" }
        XCTAssertTrue(r.key(key(13, [], down: true), modifierOnlySinceDown: false))
    }

    func testARepeatWaitsAloneForTheMainThread() {
        let j = KeyBinding(mods: [], keyName: "j", keyCodes: [38], dispatch: Dispatch(name: "focusdir", args: ["down"]))
        let r = router(binds: [j])
        let repeated = KeyEvent(keyCode: 38, mods: [], isDown: true, isRepeat: true, isModifierKey: false)
        for _ in 0..<5 { XCTAssertTrue(r.key(repeated, modifierOnlySinceDown: false), "still mango's key") }
        XCTAssertEqual(r.repeatQueued, [38], "one repeat waits; the others were dropped")
    }

    func testMouseBindingSwallowsOnlyMatchingClicks() {
        let m = MouseBinding(mods: hyper, button: .left, dispatch: Dispatch(name: "moveresize", args: ["curmove"]))
        let r = router(mouse: [m])
        XCTAssertFalse(r.mouseButton(MouseButtonEvent(button: 0, mods: [], isDown: true, location: .zero)))
        XCTAssertTrue(r.mouseButton(MouseButtonEvent(button: 0, mods: hyper, isDown: true, location: .zero)))
        XCTAssertFalse(r.mouseButton(MouseButtonEvent(button: 0, mods: hyper, isDown: false, location: .zero)))
    }

    func testScrollBindingAndDebounce() {
        let a = AxisBinding(mods: hyper, direction: .up, dispatch: Dispatch(name: "viewtoleft_have_client"))
        let r = router(axis: [a])
        XCTAssertFalse(r.scroll(ScrollEvent(direction: .up, mods: [], location: .zero)))
        XCTAssertTrue(r.scroll(ScrollEvent(direction: .up, mods: hyper, location: .zero)))
        XCTAssertTrue(r.scroll(ScrollEvent(direction: .up, mods: hyper, location: .zero)))
        XCTAssertFalse(r.scroll(ScrollEvent(direction: .up, mods: [], location: .zero)))
    }

    func testDecisionsWorkOffTheMainThread() {
        let b = KeyBinding(mods: hyper, keyName: "Left", keyCodes: [123], dispatch: Dispatch(name: "focusdir", args: ["left"]))
        let r = router(binds: [b])
        let done = expectation(description: "tap thread")
        let t = AXThread(name: "test.tap")
        t.startAndWait()
        t.perform {
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertTrue(r.key(KeyEvent(keyCode: 123, mods: self.hyper, isDown: true, isRepeat: false, isModifierKey: false),
                                modifierOnlySinceDown: false))
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        t.stop()
    }

    func testGeometrySuppression() {
        let s = WatcherShared()
        XCTAssertFalse(s.isSuppressed(7))
        s.suppress(7, until: CACurrentMediaTime() + 10)
        XCTAssertTrue(s.isSuppressed(7))
        s.suppress(7, until: CACurrentMediaTime() - 1)
        XCTAssertFalse(s.isSuppressed(7))
    }
}

@MainActor
final class MangoInputStateTests: MangoTestCase {
    let hyper: Modifiers = [.superKey, .ctrl, .alt]
    func key(_ code: UInt16, _ mods: Modifiers, down: Bool) -> KeyEvent {
        KeyEvent(keyCode: code, mods: mods, isDown: down, isRepeat: false, isModifierKey: false)
    }
    func router(_ binds: [KeyBinding] = [], axis: [AxisBinding] = [], timeout: TimeInterval = 0.1) -> InputRouter {
        let r = InputRouter()
        r.publish { s in s.bindings = binds; s.axisBindings = axis; s.axisTimeout = timeout }
        return r
    }

    func testReleaseBindIsForTheLastKeyPressed() {
        let a = KeyBinding(mods: .superKey, keyName: "a", keyCodes: [0], flags: .release, dispatch: Dispatch(name: "focusstack"))
        let r = router([a])
        _ = r.key(key(0, .superKey, down: true), modifierOnlySinceDown: false)
        _ = r.key(key(11, .superKey, down: true), modifierOnlySinceDown: false)
        _ = r.key(key(11, .superKey, down: false), modifierOnlySinceDown: false)
        XCTAssertFalse(r.key(key(0, .superKey, down: false), modifierOnlySinceDown: false), "b was pressed last")
        _ = r.key(key(0, .superKey, down: true), modifierOnlySinceDown: false)
        XCTAssertTrue(r.key(key(0, .superKey, down: false), modifierOnlySinceDown: false))
    }

    func testAClickCancelsTheReleaseBind() {
        let a = KeyBinding(mods: .superKey, keyName: "a", keyCodes: [0], flags: .release, dispatch: Dispatch(name: "focusstack"))
        let r = router([a])
        _ = r.key(key(0, .superKey, down: true), modifierOnlySinceDown: false)
        _ = r.mouseButton(MouseButtonEvent(button: 0, mods: .superKey, isDown: true, location: .zero))
        XCTAssertFalse(r.key(key(0, .superKey, down: false), modifierOnlySinceDown: false))
    }

    func testModifierKeysUseTheModifiersFromBeforeTheKey() {
        let m = HotkeyMatcher()
        let none = KeyBinding(mods: [], keyName: "Super_L", keyCodes: [55], flags: .release, dispatch: Dispatch(name: "x"))
        m.bindings = [none]
        let release = KeyEvent(keyCode: 55, mods: [], isDown: false, isRepeat: false, isModifierKey: true)
        XCTAssertTrue(m.match(release, lastHeldIsThisKey: true).isEmpty)
    }

    func testAContinuousScrollFiresOnce() {
        let rig = EngineRig()
        let a = AxisBinding(mods: hyper, direction: .down, dispatch: Dispatch(name: "viewtoright"))
        let r = router(axis: [a], timeout: 0.06)
        r.server = rig.server
        for _ in 0..<8 {
            XCTAssertTrue(r.scroll(ScrollEvent(direction: .down, mods: hyper, location: .zero)))
            Thread.sleep(forTimeInterval: 0.02)
        }
        rig.settle()
        XCTAssertEqual(rig.monitor.tagset[rig.monitor.seltags], 1 << 1, "one step")
        Thread.sleep(forTimeInterval: 0.1)
        _ = r.scroll(ScrollEvent(direction: .down, mods: hyper, location: .zero))
        rig.settle()
        XCTAssertEqual(rig.monitor.tagset[rig.monitor.seltags], 1 << 2, "after a pause")
    }

    func testAxisbindAlldir() {
        let c = ConfigParser.parse(text: "axisbind=SUPER,alldir,viewtoright", baseDirectory: nil, fileName: "t")
        XCTAssertEqual(c.config.axisBindings.first?.direction, nil)
        XCTAssertEqual(c.config.axisBindings.count, 1)
    }

    func testSetkeymodeEndsTheSearch() {
        let m = HotkeyMatcher()
        let a = KeyBinding(mods: .superKey, keyName: "x", keyCodes: [7], flags: .allowConflict,
                           dispatch: Dispatch(name: "setkeymode", args: ["resize"]))
        let b = KeyBinding(mods: .superKey, keyName: "x", keyCodes: [7], dispatch: Dispatch(name: "spawn", args: ["foo"]))
        m.bindings = [a, b]
        XCTAssertEqual(m.match(key(7, .superKey, down: true), lastHeldIsThisKey: true).map(\.dispatch.name), ["setkeymode"])
    }

    func testAPassthroughKeyStillReachesTheJumpLabels() {
        let p = KeyBinding(mods: [], keyName: "a", keyCodes: [0], flags: .passthrough, dispatch: Dispatch(name: "spawn", args: ["x"]))
        let r = InputRouter()
        r.publish { s in s.bindings = [p]; s.overviewFrame = CGRect(x: 0, y: 0, width: 100, height: 100); s.jumpActive = true; s.jumpKeys = [0] }
        XCTAssertTrue(r.key(key(0, [], down: true), modifierOnlySinceDown: false), "the jump label takes it")
    }

    func testEscapeIsOnlyJumpModes() {
        let plain = InputRouter()
        plain.publish { s in s.overviewFrame = CGRect(x: 0, y: 0, width: 100, height: 100) }
        XCTAssertFalse(plain.key(key(53, [], down: true), modifierOnlySinceDown: false))
        XCTAssertFalse(plain.key(key(36, [], down: true), modifierOnlySinceDown: false))
        let jump = InputRouter()
        jump.publish { s in s.overviewFrame = CGRect(x: 0, y: 0, width: 100, height: 100); s.jumpActive = true }
        XCTAssertTrue(jump.key(key(53, [], down: true), modifierOnlySinceDown: false))
    }
}

