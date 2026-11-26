import AppKit
import Mango

final class InputRouter: @unchecked Sendable {
    struct RoutedGlobalKey: Equatable {
        var mods: Modifiers
        var keyCodes: Set<UInt16>
        var pid: pid_t
    }

    struct Snapshot {
        var keymode = "default"
        var bindings: [KeyBinding] = []
        var mouseBindings: [MouseBinding] = []
        var axisBindings: [AxisBinding] = []
        var axisBindApplyTimeout: UInt32 = 100
        var overviewFrame: CGRect?
        var jumpMode = false
        var jumpKeys: Set<UInt16> = []
        var switcherActive = false
        var workspaceOverviewActive = false
        var hyper: Modifiers = []
        var hyperKey = false
        var wantsMouseMoved = false
        var menuBarTags: [MenuBarTagHit] = []
        var tabBarFrames: [CGRect] = []
        var groupBarFrames: [CGRect] = []
        var hoverResizeCursor: String?
        var globalKeys: [RoutedGlobalKey] = []
        var launchOrFocusPicker: UInt16??   // Port extension: chutney_launch_or_focus's picture is up (its opening key)
        /// Port extension: chutney_workspace_overview_layout. The cards' layout icons, and the layout
        /// switcher's frame while it is up over the workspace overview (it takes its own keys and clicks).
        var layoutBadges: [(box: CGRect, tag: UInt32)] = []
        var layoutSwitcherFrame: CGRect?
    }

    private let lock = NSLock()
    private var snap = Snapshot()
    weak var server: MangoServer?

    private var keyboard = KeyboardState()
    var setCursor: (String) -> Void = { CursorHider.setCursorFromTap($0) }
    var forward: (_ keyCode: UInt16, _ mods: Modifiers, _ down: Bool, _ pid: pid_t) -> Void = {
        KeyForward.post(keyCode: $0, mods: $1, down: $2, to: $3)
    }
    /// The time a scroll event is given; the tests set their own.
    var scrollTime: () -> UInt32 = { InputRouter.eventTime() }
    private var axisApplyTime: UInt32 = 0
    private var axisApplyDir: Int32 = 0
    private var grabbing = false
    private var pressing = false
    private var menuBarPress = false
    private var pickerPress = false   // Port extension: a click taken by chutney_launch_or_focus's picture
    private var badgePress = false   // Port extension: a click on a workspace overview card's layout icon
    private var switcherPress = false   // Port extension: a click on the layout switcher over the overview

    private var pendingDrag: (dx: Double, dy: Double, time: UInt32)?
    private var pendingMove: (dx: Double, dy: Double, time: UInt32)?
    private(set) var repeatQueued: Set<UInt16> = []
    private var lastMovePoint: CGPoint?

    func publish(_ update: (inout Snapshot) -> Void) {
        lock.lock()
        update(&snap)
        lock.unlock()
    }

    private var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return snap
    }

    private func onMain(_ body: @escaping @MainActor (MangoServer) -> Void) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                if let server = self?.server { body(server) }
            }
        }
    }

    private var hyperHeld = false
    var hyperKeyHeld: Bool { hyperHeld }
    private var lastKey: UInt16?
    var lastKeyDown: UInt16? { lock.lock(); defer { lock.unlock() }; return lastKey }
    private var pickerKeys: Set<UInt16> = []

    func key(_ event: KeyEvent, modifierOnlySinceDown: Bool) -> Bool {
        var ev = event
        if snapshot.hyperKey {
            if ev.keyCode == KeyboardOptions.hyperKeyCode && !ev.isModifierKey {
                hyperHeld = ev.isDown
                // Hyper is a mode key: its press and release take handle_keyboard_key's steps, without bindings
                let hs = snapshot
                let k = KeyInput(keyCode: ev.keyCode, mods: ev.mods, isDown: ev.isDown, isRepeat: ev.isRepeat,
                                 keyModifier: hs.hyper)
                lock.lock()
                let d = Keyboard.handleKeyboardKey(k, state: &keyboard, bindings: [], mode: hs.keymode,
                                                   virtualKeyboard: false)
                lock.unlock()
                run(d.actions, ev, age: "")
                return true
            }
        } else {
            hyperHeld = false
        }
        let s = snapshot
        ev.mods = KeyboardOptions.hyperMods(ev.mods, hyper: s.hyper, keyHeld: hyperHeld)
        if ev.isDown && !ev.isModifierKey { lock.lock(); lastKey = ev.keyCode; lock.unlock() }
        if let opening = s.launchOrFocusPicker, !ev.isModifierKey, pickerKey(ev, opening: opening) { return true }
        let k = KeyInput(keyCode: ev.keyCode, mods: ev.mods, isDown: ev.isDown, isRepeat: ev.isRepeat,
                         keyModifier: ev.isModifierKey ? HotkeyMatcher.modifier(forKeyCode: ev.keyCode) : nil,
                         keysym: s.workspaceOverviewActive ? KeySyms.keysym(forKeyCode: ev.keyCode) : 0)
        // Port extension: the layout switcher over the workspace overview takes the keys itself
        if s.layoutSwitcherFrame != nil && s.workspaceOverviewActive { return false }
        lock.lock()
        let d = Keyboard.handleKeyboardKey(k, state: &keyboard, bindings: s.bindings, mode: s.keymode,
                                           virtualKeyboard: false, workspaceOverviewActive: s.workspaceOverviewActive)
        lock.unlock()
        let age = ev.ageMs.map { String(format: "%.0f ms", $0) } ?? "?"
        if let a = ev.ageMs, a > 250, ev.isDown {
            wlrLog(.info, "input lag: a key event reached mango \(age) after it was pressed")
        }
        run(d.actions, ev, age: age)
        if d.handled { return d.swallow && !ev.isModifierKey }

        lock.lock()
        let u = Keyboard.handleUnboundKey(k, state: &keyboard, jumpMode: s.jumpMode,
                                          isEscape: ev.keyCode == 53, isJumpKey: s.jumpKeys.contains(ev.keyCode),
                                          globalKeys: s.globalKeys.map { ($0.mods, $0.keyCodes, $0.pid) })
        lock.unlock()
        if let a = u.action { run([a], ev, age: age) }
        return (u.swallow || d.swallow) && !ev.isModifierKey
    }

    /// Port extension: a key while chutney_launch_or_focus's picture is up. The picker's own keys
    /// are taken (press and release); any other closes it and goes on as usual (nil).
    private func pickerKey(_ ev: KeyEvent, opening: UInt16?) -> Bool {
        if !ev.isDown { return pickerKeys.remove(ev.keyCode) != nil }
        let code = ev.keyCode, mods = ev.mods
        let taken = LaunchOrFocusPicker.keys.contains(code) || (code == opening && mods.subtracting(.fn).isEmpty)
        if taken { pickerKeys.insert(code) }
        onMain { LaunchOrFocusPicker.shared.key($0, keyCode: code, mods: mods, opening: opening) }
        return taken
    }

    private func run(_ actions: [KeyAction], _ ev: KeyEvent, age: String) {
        var main: [KeyAction] = []
        for a in actions {
            if case .forward(let pid, let down) = a { forward(ev.keyCode, ev.mods, down, pid); continue }
            main.append(a)
        }
        guard !main.isEmpty else { return }
        if wlrLogGetVerbosity() == .debug {
            for case .binding(let b, let held) in main {
                wlrLog(.debug, "key: \(b.dispatch.name) \(b.dispatch.args.joined(separator: ","))\(held ? " (held)" : "")")
            }
        }
        let repeatKey = ev.isRepeat ? ev.keyCode : nil
        if let k = repeatKey {
            lock.lock()
            let waiting = !repeatQueued.insert(k).inserted
            lock.unlock()
            if waiting { return }
        }
        let queued = CACurrentMediaTime()
        onMain { [weak self] server in
            if let k = repeatKey, let self { self.lock.lock(); self.repeatQueued.remove(k); self.lock.unlock() }
            let started = CACurrentMediaTime()
            server.handleKeyboardKey(main)
            let waited = (started - queued) * 1000, ran = (CACurrentMediaTime() - started) * 1000
            if waited > 50 || ran > 50 {
                wlrLog(.info, String(format: "key: waited %.0f ms for the main thread, ran %.0f ms", waited, ran))
            }
        }
    }


    func cancelPendingReleaseBind() {
        lock.lock()
        keyboard.lastHoldKeycode = nil
        lock.unlock()
    }

    func mouseButton(_ event: MouseButtonEvent) -> Bool {
        cancelPendingReleaseBind()
        let s = snapshot
        var ev = event
        ev.mods = KeyboardOptions.hyperMods(ev.mods, hyper: s.hyper, keyHeld: hyperHeld)
        let p = ev.location, button = ev.button
        let mods = ev.mods
        if ev.isDown, button == 0, mods.isEmpty, let hit = s.menuBarTags.first(where: { $0.frame.contains(p) }) {
            menuBarPress = true
            onMain { MenuBarStatus.viewTag($0, monitor: hit.monitor, tag: hit.tag) }
            return true
        }
        if !ev.isDown, menuBarPress {
            menuBarPress = false
            return true
        }
        // Port extension: chutney_launch_or_focus's picture takes a click as mango's switcher does.
        if ev.isDown, s.launchOrFocusPicker != nil, button == 0 || button == 1 {
            pickerPress = true
            onMain { LaunchOrFocusPicker.shared.click($0, at: p, button: button) }
            return true
        }
        if !ev.isDown, pickerPress {
            pickerPress = false
            return true
        }
        // Port extension: chutney_workspace_overview_layout. The layout switcher over the overview takes its
        // own clicks; a click on a card's layout icon opens it.
        if s.workspaceOverviewActive {
            if ev.isDown, let f = s.layoutSwitcherFrame, f.contains(p) { switcherPress = true; return false }
            if !ev.isDown, switcherPress { switcherPress = false; return false }
            if ev.isDown, button == 0, let hit = s.layoutBadges.first(where: { $0.box.contains(p) }) {
                badgePress = true
                onMain { $0.mac.layoutBadgeClicked(tag: hit.tag) }
                return true
            }
            if !ev.isDown, badgePress { badgePress = false; return true }
        }
        // node_at_point gives a press on a bar to the bar: its panel takes it (barPress), not the window under it
        if ev.isDown, (s.tabBarFrames + s.groupBarFrames).contains(where: { $0.contains(p) }) {
            return false
        }
        if ev.isDown {
            let decision = Pointer.pointerProcessButtonPress(button: button, at: p, mods: ev.mods, switcherActive: s.switcherActive,
                                                             overviewFrame: s.overviewFrame, mouseBindings: s.mouseBindings,
                                                             mode: s.keymode, hoverResizeEdge: s.hoverResizeCursor != nil,
                                                             workspaceOverviewActive: s.workspaceOverviewActive)
            let strip = decision == .borderResize
            onMain { $0.pointerProcessButtonPress(button: button, pressed: true, at: p, mods: mods, borderResizeTaken: strip) }
            switch decision {
            case .workspaceOverview:
                grabbing = true
                return true
            case .switcher, .overview:
                return true
            case .mouseBinding, .borderResize:
                grabbing = true
                return true
            case .none:
                if button == 0 {
                    pressing = true
                    onMain { $0.mac.plainMouseDown(at: p) }
                }
                return false
            }
        }
        let wsovRelease = s.workspaceOverviewActive
        grabbing = false
        pressing = false
        onMain {
            $0.pointerProcessButtonPress(button: button, pressed: false, at: p, mods: mods)
            $0.mac.userButtonReleased(button: button, at: p)
        }
        return wsovRelease
    }

    static func eventTime() -> UInt32 {
        max(1, UInt32((CACurrentMediaTime() * 1000).truncatingRemainder(dividingBy: Double(UInt32.max))))
    }

    /// The motion's delta, as wlroots' motion event gives it: from the event before (macOS has moved the pointer).
    private func motionDelta(_ p: CGPoint) -> (dx: Double, dy: Double) {
        defer { lastMovePoint = p }
        guard let last = lastMovePoint else { return (0, 0) }
        return (Double(p.x - last.x), Double(p.y - last.y))
    }

    func dragged(_ p: CGPoint) {
        let d = motionDelta(p)
        guard grabbing || pressing else { return }
        lock.lock()
        let schedule = pendingDrag == nil
        pendingDrag = (d.dx, d.dy, Self.eventTime())
        lock.unlock()
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let latest = self.pendingDrag
            self.pendingDrag = nil
            self.lock.unlock()
            MainActor.assumeIsolated {
                guard let latest, let server = self.server else { return }
                let mangos = server.cursorMode == CurMove || server.cursorMode == CurResize || server.groupBarDragPending
                server.handleCursorMotion(latest.time, latest.dx, latest.dy)
                if !mangos { server.mac.followUserDrag() }
            }
        }
    }

    func mouseMoved(_ p: CGPoint) {
        let d = motionDelta(p)
        let s = snapshot
        if let name = s.hoverResizeCursor { setCursor(name) }
        guard s.wantsMouseMoved else { return }
        lock.lock()
        let schedule = pendingMove == nil
        pendingMove = (d.dx, d.dy, Self.eventTime())
        lock.unlock()
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let latest = self.pendingMove
            self.pendingMove = nil
            self.lock.unlock()
            MainActor.assumeIsolated {
                if let latest, let server = self.server { server.handleCursorMotion(latest.time, latest.dx, latest.dy) }
            }
        }
    }

    func scroll(_ event: ScrollEvent) -> Bool {
        let s = snapshot
        // handle_cursor_axis's pointer_cursor_activity: the hidden cursor comes back and its timer restarts
        if s.wantsMouseMoved { onMain { $0.pointerCursorActivity() } }
        var ev = event
        ev.mods = KeyboardOptions.hyperMods(ev.mods, hyper: s.hyper, keyHeld: hyperHeld)
        if Pointer.workspaceOverviewTakesAxis(mods: ev.mods, workspaceOverviewActive: s.workspaceOverviewActive) {
            let axis = WlrPointerAxisEvent(timeMsec: scrollTime(), delta: ev.delta, deltaDiscrete: Int32(ev.discrete * 120))
            onMain { _ = $0.workspaceOverviewHandleAxis(axis) }
            return true
        }
        guard let axis = Pointer.handleCursorAxis(vertical: ev.vertical, delta: ev.delta, timeMsec: scrollTime(),
                                                  mods: ev.mods, axisBindings: s.axisBindings, mode: s.keymode,
                                                  axisBindApplyTimeout: s.axisBindApplyTimeout,
                                                  axisApplyTime: &axisApplyTime, axisApplyDir: &axisApplyDir)
        else { return false }
        cancelPendingReleaseBind()
        if axis.fires {
            let d = axis.binding.dispatch
            onMain { _ = $0.dispatch(d) }
        }
        return true
    }
}
