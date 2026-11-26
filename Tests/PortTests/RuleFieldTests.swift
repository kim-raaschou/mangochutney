import XCTest
@testable import Mango
@testable import Port

@MainActor
final class RuleFieldTests: MangoTestCase {
    let float = CGRect(x: 100, y: 120, width: 600, height: 400)

    func otherApp(_ r: EngineRig, _ id: CGWindowID, pid: pid_t, bundleId: String) -> Client {
        let w = DiscoveredWindow(id: id, pid: pid, element: r.app.element(for: id), bundleId: bundleId, appName: "OBS",
                                 title: "OBS", subrole: "AXStandardWindow", isDialog: false, frame: float, isminimized: false, isfullscreen: false, isAppHidden: false)
        let c = Client(window: w, monitor: r.monitor, tags: 1)
        c.isPendingOpenAnimation = false
        r.app.frames[id] = float
        c.id = r.server.generateClientId()
        r.server.clients.append(c)
        return c
    }

    func testAGlobalKeyGoesToItsWindowsAppNotTheFocusedOne() {
        let r = EngineRig()
        var rule = ConfigWinRule()
        rule.id = "com.obsproject.Studio"
        rule.globalkeybinding = "ctrl+alt-o"
        r.server.config.windowRules = [rule]
        let obs = otherApp(r, 900_310, pid: 4242, bundleId: "com.obsproject.Studio")
        let editor = r.window(900_311)
        r.server.clientFocus(editor, false)

        var sent: [(UInt16, Bool, pid_t)] = []
        r.server.mac.router.forward = { code, _, down, pid in sent.append((code, down, pid)) }
        let o = KeyNames.keyCodes(forName: "o").first!
        let down = KeyEvent(keyCode: o, mods: [.ctrl, .alt], isDown: true, isRepeat: false, isModifierKey: false)
        let up = KeyEvent(keyCode: o, mods: [], isDown: false, isRepeat: false, isModifierKey: false)
        XCTAssertTrue(r.server.mac.router.key(down, modifierOnlySinceDown: false), "not for the focused app")
        XCTAssertTrue(r.server.mac.router.key(up, modifierOnlySinceDown: false), "its release follows, modifiers up or not")
        XCTAssertEqual(sent.map(\.0), [o, o])
        XCTAssertEqual(sent.map(\.1), [true, false])
        XCTAssertEqual(Set(sent.map(\.2)), [4242])

        sent.removeAll()
        r.server.clientFocus(obs, false)
        XCTAssertFalse(r.server.mac.router.key(down, modifierOnlySinceDown: false), "the window has the focus: the key goes there anyway")
        XCTAssertTrue(sent.isEmpty)

        r.server.clientFocus(editor, false)
        r.server.mac.windowDestroyed(id: 900_310)
        XCTAssertFalse(r.server.mac.router.key(down, modifierOnlySinceDown: false), "no window: an ordinary key")
    }

    func testABindingWinsOverAGlobalKey() {
        let r = EngineRig()
        var rule = ConfigWinRule()
        rule.id = "com.obsproject.Studio"
        rule.globalkeybinding = "ctrl+alt-o"
        r.server.config.windowRules = [rule]
        let o = KeyNames.keyCodes(forName: "o").first!
        r.server.config.keyBindings = [KeyBinding(mods: [.ctrl, .alt], keyName: "o", keyCodes: [o],
                                              dispatch: Dispatch(name: "togglegaps", args: []))]
        _ = otherApp(r, 900_312, pid: 4242, bundleId: "com.obsproject.Studio")
        r.server.clientFocus(r.window(900_313), false)
        r.server.publishInputState()
        var sent = 0
        r.server.mac.router.forward = { _, _, _, _ in sent += 1 }
        XCTAssertTrue(r.server.mac.router.key(KeyEvent(keyCode: o, mods: [.ctrl, .alt], isDown: true, isRepeat: false, isModifierKey: false),
                                      modifierOnlySinceDown: false))
        XCTAssertEqual(sent, 0, "mango: bindings first")
    }
}

@MainActor
final class DragCornerTests: MangoTestCase {
    let start = CGRect(x: 200, y: 200, width: 600, height: 400)
    let resize = MouseBinding(mods: [.superKey], button: .right, dispatch: Dispatch(name: "moveresize", args: ["curresize"]))

    func grab(_ r: EngineRig, at p: CGPoint) -> Client {
        let c = r.window(900_320, floating: true, frame: start)
        c.floatGeom = start
        r.server.mousebind(resize, at: p)
        return c
    }

}
