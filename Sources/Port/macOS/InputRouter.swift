import AppKit
import Mango

/// Overview keys handled on the main thread.
/// Runs on the event-tap thread. Decides whether an input event is swallowed
/// from a lock-protected snapshot the main thread publishes (bindings, key mode,
/// overview state), and sends the action to the main thread asynchronously.
/// Keyboard and mouse delivery therefore never waits for the window manager,
/// however busy its main thread is.
final class InputRouter: @unchecked Sendable {
    /// A global_key_binding with its key codes.
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
        /// Frame of the monitor showing the overview (nil = no overview).
        var overviewFrame: CGRect?
        var jumpActive = false
        /// Key codes of the jump labels on screen.
        var jumpKeys: Set<UInt16> = []
        /// overcircle is open: releasing a modifier key leaves it.
        var overcircleActive = false
        /// mango's switcher is open: releasing a modifier key focuses the highlighted window.
        var switcherActive = false
        /// mango's tag_combo: a comboview is going on; any key released ends it.
        var tagCombo = false
        /// xkb_rules_options caps:hyper or chutney_hyper_key: what the Hyper key (now F18) held
        /// stands for.
        var capsHyper: Modifiers?
        /// chutney_hyper_tap: the Hyper key pressed alone.
        var hyperTap: HyperTap = .none
        var wantsMouseMoved = false
        /// Tabs in the focused monitor's tab bar that ⌘1-9 picks (0: none, or off).
        var tabShortcuts = 0
        /// cursor_hide_on_keypress, and the pointer is shown.
        var cursorHideOnKeypress = false
        /// mango's hover_resize_edge, with its cursor: a press there begins a border resize.
        var hoverResizeCursor: String?
        /// global_key_binding chords with a window to send them to, in rule order.
        var globalKeys: [RoutedGlobalKey] = []
    }

    private let lock = NSLock()
    private var snap = Snapshot()
    /// Set once on the main thread; only dereferenced on the main thread.
    weak var server: MangoServer?

    /// mango's keyboard state (lock): last_hold_keycode (a click, a matching scroll or a
    /// swipe clears it), the swallowed keys, the keys sent to another app.
    private var keyboard = KeyboardState()
    /// The border resize strip's cursor, set as the pointer moves on it (CursorHider; tests
    /// record it instead).
    var setCursor: (String) -> Void = { CursorHider.setCursorFromTap($0) }
    /// Sends a key to an app (KeyForward; tests record it instead).
    var forward: (_ keyCode: UInt16, _ mods: Modifiers, _ down: Bool, _ pid: pid_t) -> Void = {
        KeyForward.post(keyCode: $0, mods: $1, down: $2, to: $3)
    }
    /// The tabs show their numbers (⌘ alone is held).
    private var tabNumbersShown = false
    /// mango server.axis_apply_time, axis_apply_dir.
    private var axisApplyTime: CFTimeInterval = 0
    private var axisApplyDir = 0
    private var grabbing = false
    /// A plain left press that mango did not take: the user may be dragging a window.
    private var pressing = false

    // Coalesced pointer positions (lock): at most one main-thread hop in flight each.
    private var pendingDrag: (point: CGPoint, time: UInt32)?
    private var pendingMove: (point: CGPoint, speed: CGFloat)?
    /// Keys whose repeat waits for the main thread (a repeat is dropped while one does).
    private(set) var repeatQueued: Set<UInt16> = []
    /// Event-tap thread: the last pointer position, for each motion's speed (mango's
    /// sqrt(dx² + dy²) per motion event).
    private var lastMovePoint: CGPoint?

    /// Main thread: publish the state the tap thread decides from.
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

    // MARK: Keyboard

    /// Caps Lock (F18) is held as mango's hyper (xkb_rules_options caps:hyper).
    private var hyperHeld = false
    /// Port extension: not in mango (chutney_hyper_tap). The Hyper key went down and nothing
    /// else has been pressed or clicked since.
    private var hyperAlone = false
    /// What a quick press of the Hyper key does (chutney_hyper_tap), as Raycast's Quick Press.
    enum HyperTap: Equatable {
        case none
        /// A key pressed and let go for the frontmost app (Escape, or a function key itself).
        case key(UInt16)
        /// Caps Lock itself: its lock turned over.
        case capsLock
    }

    /// Does a quick press (tests record it instead).
    var hyperTapped: (HyperTap) -> Void = { tap in
        switch tap {
        case .none: break
        case .key(let code): KeyForward.postToFront(keyCode: code)
        case .capsLock: KeyboardOptions.toggleCapsLock()
        }
    }

    func key(_ event: KeyEvent, modifierOnlySinceDown: Bool) -> Bool {
        var ev = event
        if let hyper = snapshot.capsHyper {
            // The hyper key itself is mango's: it only holds hyper, and no app sees it.
            if ev.keyCode == KeyboardOptions.hyperKeyCode && !ev.isModifierKey {
                if ev.isDown && !ev.isRepeat { hyperAlone = true }
                if !ev.isDown && hyperAlone && snapshot.hyperTap != .none { hyperTapped(snapshot.hyperTap) }
                if !ev.isDown { hyperAlone = false }
                hyperHeld = ev.isDown
                if ev.isDown && !ev.isRepeat { lock.lock(); keyboard.lastHoldKeycode = ev.keyCode; lock.unlock() }
                return true
            }
            if hyperHeld { ev.mods.formUnion(hyper) }
            if ev.isDown { hyperAlone = false }
        } else {
            hyperHeld = false
        }
        let s = snapshot
        // Port extension: not in mango (chutney_tab_bar_shortcuts). The tabs' numbers show while
        // ⌘ alone is held (and through ⌘1-9), and go at any other key.
        let numbers = s.tabShortcuts > 0 && ev.mods.subtracting(.fn) == .superKey
            && (ev.isModifierKey || Self.digitKeys[ev.keyCode] != nil)
        if numbers != tabNumbersShown {
            tabNumbersShown = numbers
            onMain { $0.showTabNumbers(numbers) }
        }

        // mango handle_keyboard_key, up to the bindings (Keyboard, in the core).
        let k = KeyInput(keyCode: ev.keyCode, mods: ev.mods, isDown: ev.isDown, isRepeat: ev.isRepeat,
                         keyModifier: ev.isModifierKey ? HotkeyMatcher.modifier(forKeyCode: ev.keyCode) : nil)
        lock.lock()
        let d = Keyboard.handleKeyboardKey(k, state: &keyboard, bindings: s.bindings, mode: s.keymode,
                                           overcircleActive: s.overcircleActive, switcherActive: s.switcherActive,
                                           tagCombo: s.tagCombo, cursorHideOnKeypress: s.cursorHideOnKeypress)
        lock.unlock()
        let age = ev.ageMs.map { String(format: "%.0f ms", $0) } ?? "?"
        if let a = ev.ageMs, a > 250, ev.isDown {
            // The key spent this long in macOS and in the taps before ours: input lag, not mango.
            wlrLog(.info, "input lag: a key event reached mango \(age) after it was pressed")
        }
        run(d.actions, ev, age: age)
        // Not in mango: a modifier key's own event always reaches the apps; on macOS one taken
        // from them stays held there (mango takes a bound one, as any key).
        if d.handled { return d.swallow && !ev.isModifierKey }

        // Port extension: not in mango (chutney_tab_bar_shortcuts). Bindings first, then ⌘1-9
        // for the tab bar, held down too.
        if s.tabShortcuts > 0, ev.isDown, !ev.isModifierKey, ev.mods.subtracting(.fn) == .superKey,
           let n = Self.digitKeys[ev.keyCode], n <= s.tabShortcuts {
            lock.lock(); keyboard.boundKeys.insert(ev.keyCode); lock.unlock()
            if !ev.isRepeat { onMain { $0.tabFocusMember(number: n) } }
            return true
        }
        // mango handle_keyboard_key, after the bindings: the jump labels, the global keys.
        let label = s.jumpKeys.contains(ev.keyCode) ? KeyNames.name(forKeyCode: ev.keyCode).uppercased() : nil
        lock.lock()
        let u = Keyboard.handleUnboundKey(k, state: &keyboard, jumpActive: s.overviewFrame != nil && s.jumpActive,
                                          isEscape: ev.keyCode == 53, jumpLabel: label,
                                          globalKeys: s.globalKeys.map { ($0.mods, $0.keyCodes, $0.pid) })
        lock.unlock()
        if let a = u.action { run([a], ev, age: age) }
        return (u.swallow || d.swallow) && !ev.isModifierKey
    }

    /// Carries out what mango's keyboard decided: a key sent to another app here, the rest on
    /// the main thread (MangoServer.handleKeyboardKey).
    private func run(_ actions: [KeyAction], _ ev: KeyEvent, age: String) {
        var main: [KeyAction] = []
        for a in actions {
            if case .forward(let pid, let down) = a { forward(ev.keyCode, ev.mods, down, pid); continue }
            main.append(a)
        }
        guard !main.isEmpty else { return }
        // Not in mango: macOS sends a held key's repeats itself, one after another; mango's own
        // repeat timer never stacks them. A repeat while the last one still waits is dropped.
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

    /// US-position digit keys 1...9.
    static let digitKeys: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    /// mango keyboard_cancel_pending_release_bind (keyboard.c): a held modifier used for
    /// something else no longer fires its release bind.
    func cancelPendingReleaseBind() {
        lock.lock()
        keyboard.lastHoldKeycode = nil
        lock.unlock()
    }

    func mouseButton(_ event: MouseButtonEvent) -> Bool {
        cancelPendingReleaseBind()   // mango pointer_process_button: every button event
        let s = snapshot
        var ev = event
        if hyperHeld, let hyper = s.capsHyper { ev.mods.formUnion(hyper) }
        hyperAlone = false
        let p = ev.location, button = ev.button
        let mods = ev.mods
        if ev.isDown {
            // Whether the press is mango's, decided here as mango's pointer_process_button_press does.
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

    /// The time in ms, as mango's events carry it (never 0: mango's internal calls).
    static func eventTime() -> UInt32 {
        max(1, UInt32((CACurrentMediaTime() * 1000).truncatingRemainder(dividingBy: Double(UInt32.max))))
    }

    func dragged(_ p: CGPoint) {
        guard grabbing || pressing else { return }
        lock.lock()
        let schedule = pendingDrag == nil
        // the motion's time in ms, as mango's events carry it
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
                if !mangos { server.mac.followUserDrag() }   // not in mango: the app's own drag
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

    // MARK: Scroll

    func scroll(_ event: ScrollEvent) -> Bool {
        let s = snapshot
        var ev = event
        if hyperHeld, let hyper = s.capsHyper { ev.mods.formUnion(hyper) }
        // mango handle_cursor_axis decides; the time and direction are kept here.
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
