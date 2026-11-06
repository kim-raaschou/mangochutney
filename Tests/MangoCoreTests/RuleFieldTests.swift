import XCTest
@testable import Mango
@testable import Port

/// mango's no_force_center and global_key_binding window-rule fields, and the centring
/// they change.
@MainActor
final class RuleFieldTests: MangoTestCase {
    let float = CGRect(x: 100, y: 120, width: 600, height: 400)

    func testCenterwinCentresUnlessNoForceCenter() {
        let r = EngineRig()
        let c = r.window(900_300, floating: true, frame: float)
        c.floatGeom = float
        _ = r.server.dispatch(Dispatch(name: "centerwin", args: []), target: c)
        XCTAssertEqual(c.floatGeom.midX, r.screen.workArea.midX, accuracy: 1)
        XCTAssertEqual(c.floatGeom.midY, r.screen.workArea.midY, accuracy: 1)

        c.noForceCenter = true
        c.floatGeom = float
        _ = r.server.dispatch(Dispatch(name: "centerwin", args: []), target: c)
        XCTAssertEqual(c.floatGeom, float, "mango's client_center_geometry keeps it where it is")
    }

    func testTheRuleSetsIt() {
        let r = EngineRig()
        var rule = WindowRule()
        rule.appId = "test"
        rule.noForceCenter = true
        r.server.config.windowRules = [rule]
        let c = r.window(900_301)
        _ = r.server.clientSetRules(c)
        XCTAssertTrue(c.noForceCenter)
    }

    /// mango tag_monitor: the floating size scaled by the two work areas, centred on the
    /// new monitor.
    func testTagmonScalesAndCentresAFloatingWindow() {
        let r = EngineRig()
        let big = Screen(displayID: 2, name: "Big", frame: CGRect(x: 1728, y: 0, width: 2560, height: 1440),
                         workArea: CGRect(x: 1728, y: 25, width: 2560, height: 1415), scale: 2, isMain: false)
        r.server.rebuildMonitors(screens: [r.screen, big])
        let c = r.window(900_302, floating: true, frame: float)
        c.floatGeom = float
        r.server.clientFocus(c, raise: false)
        let target = r.server.monitors.first { $0.screen.displayID == 2 }!
        r.server.tagMonitor(c, to: target, newtags: 0)
        XCTAssertEqual(c.floatGeom.width, (600 * 2560 / r.screen.workArea.width).rounded(.down))
        XCTAssertEqual(c.floatGeom.height, (400 * 1415 / r.screen.workArea.height).rounded(.down))
        XCTAssertEqual(c.floatGeom.midX, big.workArea.midX, accuracy: 1)
        XCTAssertEqual(c.floatGeom.midY, big.workArea.midY, accuracy: 1)
    }

    // MARK: global_key_binding

    /// A window of another app (its own pid), as an OBS window would be.
    func otherApp(_ r: EngineRig, _ id: CGWindowID, pid: pid_t, bundleId: String) -> Client {
        let w = DiscoveredWindow(id: id, pid: pid, element: r.app.element(for: id), bundleId: bundleId, appName: "OBS",
                                 title: "OBS", subrole: "AXStandardWindow", isDialog: false, frame: float, isMinimized: false, isFullscreen: false, isAppHidden: false)
        let c = Client(window: w, monitor: r.monitor, tags: 1)
        c.isPendingOpenAnimation = false
        r.app.frames[id] = float
        r.server.clients.append(c)
        return c
    }

    func testAGlobalKeyGoesToItsWindowsAppNotTheFocusedOne() {
        let r = EngineRig()
        var rule = WindowRule()
        rule.appId = "com.obsproject.Studio"
        rule.globalKeyBinding = "ctrl+alt-o"
        r.server.config.windowRules = [rule]
        let obs = otherApp(r, 900_310, pid: 4242, bundleId: "com.obsproject.Studio")
        let editor = r.window(900_311)
        r.server.clientFocus(editor, raise: false)

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
        r.server.clientFocus(obs, raise: false)
        XCTAssertFalse(r.server.mac.router.key(down, modifierOnlySinceDown: false), "the window has the focus: the key goes there anyway")
        XCTAssertTrue(sent.isEmpty)

        r.server.clientFocus(editor, raise: false)
        r.server.mac.windowDestroyed(id: 900_310)
        XCTAssertFalse(r.server.mac.router.key(down, modifierOnlySinceDown: false), "no window: an ordinary key")
    }

    func testABindingWinsOverAGlobalKey() {
        let r = EngineRig()
        var rule = WindowRule()
        rule.appId = "com.obsproject.Studio"
        rule.globalKeyBinding = "ctrl+alt-o"
        r.server.config.windowRules = [rule]
        let o = KeyNames.keyCodes(forName: "o").first!
        r.server.config.keyBindings = [KeyBinding(mods: [.ctrl, .alt], keyName: "o", keyCodes: [o],
                                              dispatch: Dispatch(name: "togglegaps", args: []))]
        _ = otherApp(r, 900_312, pid: 4242, bundleId: "com.obsproject.Studio")
        r.server.clientFocus(r.window(900_313), raise: false)
        r.server.publishInputState()
        var sent = 0
        r.server.mac.router.forward = { _, _, _, _ in sent += 1 }
        XCTAssertTrue(r.server.mac.router.key(KeyEvent(keyCode: o, mods: [.ctrl, .alt], isDown: true, isRepeat: false, isModifierKey: false),
                                      modifierOnlySinceDown: false))
        XCTAssertEqual(sent, 0, "mango: bindings first")
    }
}

/// mango's drag_corner and drag_warp_cursor: a mousebind resize of a floating window.
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

    func testTheDefaultPullsTheBottomRightCornerFromTheCorner() {
        let r = EngineRig()
        let c = grab(r, at: CGPoint(x: 300, y: 300))
        XCTAssertEqual(r.server.grab?.startMouse, CGPoint(x: 800, y: 600), "drag_warp_cursor: the pointer goes to the corner")
        r.server.pointerProcessMotion(CGPoint(x: 850, y: 640), time: 0)
        XCTAssertEqual(c.floatGeom, CGRect(x: 200, y: 200, width: 650, height: 440))
    }

    func testCornerZeroPullsTheTopLeft() {
        let r = EngineRig()
        r.server.config.dragCorner = 0
        r.server.config.dragWarpCursor = false
        let c = grab(r, at: CGPoint(x: 700, y: 500))
        r.server.pointerProcessMotion(CGPoint(x: 650, y: 470), time: 0)
        XCTAssertEqual(c.floatGeom, CGRect(x: 150, y: 170, width: 650, height: 430), "the bottom right stays")
    }

    func testCornerFourTakesTheNearest() {
        let r = EngineRig()
        r.server.config.dragCorner = 4
        _ = grab(r, at: CGPoint(x: 750, y: 250))   // near the top right
        XCTAssertEqual(r.server.grab?.resizeEdge, [.right, .top])
        XCTAssertEqual(r.server.grab?.startMouse, CGPoint(x: 800, y: 200))
    }

    /// mango's geom holds the border: drag_warp_cursor puts the pointer on its outer corner.
    func testTheWarpGoesToTheBordersOuterCorner() {
        let r = EngineRig()
        r.server.renderBorder = true
        let c = grab(r, at: CGPoint(x: 300, y: 300))
        let bw = r.server.borderWidth(c, on: r.monitor)
        XCTAssertGreaterThan(bw, 0)
        XCTAssertEqual(r.server.grab?.startMouse, CGPoint(x: 800 + bw, y: 600 + bw))
        r.server.pointerProcessMotion(CGPoint(x: 850 + bw, y: 640 + bw), time: 0)
        XCTAssertEqual(c.floatGeom, CGRect(x: 200, y: 200, width: 650, height: 440))
    }
}
