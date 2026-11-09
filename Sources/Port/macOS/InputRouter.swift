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
        var axisTimeout: TimeInterval = 0.1
        var overviewFrame: CGRect?
        var jumpActive = false
        var jumpKeys: Set<UInt16> = []
        var overcircleActive = false
        var switcherActive = false
        var tagCombo = false
        var hyper: Modifiers = []
        var hyperKey = false
        var wantsMouseMoved = false
        var menuBarTags: [MenuBarTagHit] = []
        var tabShortcuts = 0
        var cursorHideOnKeypress = false
        var hoverResizeCursor: String?
        var globalKeys: [RoutedGlobalKey] = []
        var launchOrFocusPicker: UInt16??   // Port extension: chutney_launch_or_focus's picture is up (its opening key)
    }

    private let lock = NSLock()
    private var snap = Snapshot()
    weak var server: MangoServer?

    private var keyboard = KeyboardState()
    var setCursor: (String) -> Void = { CursorHider.setCursorFromTap($0) }
    var forward: (_ keyCode: UInt16, _ mods: Modifiers, _ down: Bool, _ pid: pid_t) -> Void = {
        KeyForward.post(keyCode: $0, mods: $1, down: $2, to: $3)
    }
    private var tabNumbersShown = false
    private var axisApplyTime: CFTimeInterval = 0
    private var axisApplyDir = 0
    private var grabbing = false
    private var pressing = false
    private var menuBarPress = false

    private var pendingDrag: (point: CGPoint, time: UInt32)?
    private var pendingMove: (point: CGPoint, speed: CGFloat)?
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
                if ev.isDown && !ev.isRepeat { lock.lock(); keyboard.lastHoldKeycode = ev.keyCode; lock.unlock() }
                return true
            }
        } else {
            hyperHeld = false
        }
        let s = snapshot
        ev.mods = KeyboardOptions.hyperMods(ev.mods, hyper: s.hyper, keyHeld: hyperHeld)
        if ev.isDown && !ev.isModifierKey { lock.lock(); lastKey = ev.keyCode; lock.unlock() }
        if let opening = s.launchOrFocusPicker, !ev.isModifierKey, pickerKey(ev, opening: opening) { return true }
        let numbers = s.tabShortcuts > 0 && ev.mods.subtracting(.fn) == .superKey
            && (ev.isModifierKey || Self.digitKeys[ev.keyCode] != nil)
        if numbers != tabNumbersShown {
            tabNumbersShown = numbers
            onMain { $0.showTabNumbers(numbers) }
        }

        let k = KeyInput(keyCode: ev.keyCode, mods: ev.mods, isDown: ev.isDown, isRepeat: ev.isRepeat,
                         keyModifier: ev.isModifierKey ? HotkeyMatcher.modifier(forKeyCode: ev.keyCode) : nil)
        lock.lock()
        let d = Keyboard.handleKeyboardKey(k, state: &keyboard, bindings: s.bindings, mode: s.keymode,
                                           overcircleActive: s.overcircleActive, switcherActive: s.switcherActive,
                                           tagCombo: s.tagCombo, cursorHideOnKeypress: s.cursorHideOnKeypress)
        lock.unlock()
        let age = ev.ageMs.map { String(format: "%.0f ms", $0) } ?? "?"
        if let a = ev.ageMs, a > 250, ev.isDown {
            wlrLog(.info, "input lag: a key event reached mango \(age) after it was pressed")
        }
        run(d.actions, ev, age: age)
        if d.handled { return d.swallow && !ev.isModifierKey }

        if s.tabShortcuts > 0, ev.isDown, !ev.isModifierKey, ev.mods.subtracting(.fn) == .superKey,
           let n = Self.digitKeys[ev.keyCode], n <= s.tabShortcuts {
            lock.lock(); keyboard.boundKeys.insert(ev.keyCode); lock.unlock()
            if !ev.isRepeat { onMain { $0.tabFocusMember(number: n) } }
            return true
        }
        let label = s.jumpKeys.contains(ev.keyCode) ? KeyNames.name(forKeyCode: ev.keyCode).uppercased() : nil
        lock.lock()
        let u = Keyboard.handleUnboundKey(k, state: &keyboard, jumpActive: s.overviewFrame != nil && s.jumpActive,
                                          isEscape: ev.keyCode == 53, jumpLabel: label,
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
            if waited > 250 || ran > 250 {
                wlrLog(.info, String(format: "key: waited %.0f ms for the main thread, ran %.0f ms", waited, ran))
            }
        }
    }

    static let digitKeys: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

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
        if ev.isDown {
            let decision = Pointer.pointerProcessButtonPress(button: button, at: p, mods: ev.mods, switcherActive: s.switcherActive,
                                                             overviewFrame: s.overviewFrame, mouseBindings: s.mouseBindings,
                                                             mode: s.keymode, hoverResizeEdge: s.hoverResizeCursor != nil)
            let strip = decision == .borderResize
            onMain { $0.pointerProcessButtonPress(button: button, pressed: true, at: p, mods: mods, borderResizeTaken: strip) }
            switch decision {
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
        grabbing = false
        pressing = false
        onMain {
            $0.pointerProcessButtonPress(button: button, pressed: false, at: p, mods: mods)
            $0.mac.userButtonReleased(button: button, at: p)
        }
        return false
    }

    static func eventTime() -> UInt32 {
        max(1, UInt32((CACurrentMediaTime() * 1000).truncatingRemainder(dividingBy: Double(UInt32.max))))
    }

    func dragged(_ p: CGPoint) {
        guard grabbing || pressing else { return }
        lock.lock()
        let schedule = pendingDrag == nil
        pendingDrag = (p, Self.eventTime())
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
                let mangos = server.grab != nil || server.groupBarDrag != nil
                server.handleCursorMotion(latest.point, time: latest.time)
                if !mangos { server.mac.followUserDrag() }
            }
        }
    }

    func mouseMoved(_ p: CGPoint) {
        let speed = lastMovePoint.map { hypot(p.x - $0.x, p.y - $0.y) } ?? 0
        lastMovePoint = p
        let s = snapshot
        if let name = s.hoverResizeCursor { setCursor(name) }
        guard s.wantsMouseMoved else { return }
        lock.lock()
        let schedule = pendingMove == nil
        pendingMove = (p, speed)
        lock.unlock()
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let latest = self.pendingMove
            self.pendingMove = nil
            self.lock.unlock()
            MainActor.assumeIsolated {
                if let latest, let server = self.server { server.handleCursorMotion(latest.point, time: Self.eventTime(), speed: latest.speed) }
            }
        }
    }

    func scroll(_ event: ScrollEvent) -> Bool {
        let s = snapshot
        var ev = event
        ev.mods = KeyboardOptions.hyperMods(ev.mods, hyper: s.hyper, keyHeld: hyperHeld)
        let now = CACurrentMediaTime()
        guard let axis = Pointer.handleCursorAxis(direction: ev.direction, mods: ev.mods, now: now,
                                                  applyTime: axisApplyTime, applyDir: axisApplyDir,
                                                  axisBindings: s.axisBindings, mode: s.keymode,
                                                  timeout: s.axisTimeout) else { return false }
        cancelPendingReleaseBind()
        if axis.fires {
            let d = axis.binding.dispatch
            onMain { _ = $0.dispatch(d) }
        }
        axisApplyTime = now
        axisApplyDir = axis.dir
        return true
    }
}
