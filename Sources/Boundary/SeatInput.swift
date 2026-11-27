import CoreGraphics

/// Not in mango: the steps wlroots' seat and mango's input handlers take with one input event, the same
/// for the port's event tap (InputRouter) and the tests' virtual devices (TestMango). Each source keeps
/// its own devices and threads: a key's and a wheel's decision may be taken off the main thread, and
/// the caller runs what it decided on it.
package enum SeatInput {
    /// What a key does: mango's actions in order (the bound key's, else the unbound key's) and whether
    /// the key is the compositor's (it does not reach the app).
    package struct Key {
        package var actions: [KeyAction]
        package var swallow: Bool
    }

    /// handle_keyboard_key: the bindings, and when none took the key, its turn as an unbound key.
    package static func key(_ k: KeyInput, state: inout KeyboardState, bindings: [KeyBinding], mode: String,
                            virtualKeyboard: Bool, workspaceOverviewActive: Bool, jumpMode: Bool, isEscape: Bool,
                            isJumpKey: Bool, globalKeys: [(mods: Modifiers, keyCodes: Set<UInt16>, pid: pid_t)]) -> Key {
        let d = Keyboard.handleKeyboardKey(k, state: &state, bindings: bindings, mode: mode,
                                           virtualKeyboard: virtualKeyboard, workspaceOverviewActive: workspaceOverviewActive)
        if d.handled { return Key(actions: d.actions, swallow: d.swallow) }
        let u = Keyboard.handleUnboundKey(k, state: &state, jumpMode: jumpMode, isEscape: isEscape,
                                          isJumpKey: isJumpKey, globalKeys: globalKeys)
        return Key(actions: d.actions + (u.action.map { [$0] } ?? []), swallow: u.swallow || d.swallow)
    }

    /// A relative motion: wlroots moves its cursor, which asks the output it is on for a frame (the
    /// grabs resize once per frame, frame_serial), then handle_cursor_motion.
    @MainActor
    package static func motion(_ server: MangoServer, time: UInt32, dx: Double, dy: Double) {
        cursorMoved(server)
        server.handleCursorMotion(time, dx, dy)
    }

    /// An absolute motion (a virtual pointer): the cursor's frame, then handle_cursor_motion_absolute.
    @MainActor
    package static func motionAbsolute(_ server: MangoServer, time: UInt32, dx: Double, dy: Double) {
        cursorMoved(server)
        server.pointerProcessMotion(time, dx, dy)
    }

    @MainActor
    private static func cursorMoved(_ server: MangoServer) {
        if let m = server.monitorAtPoint(server.system.pointer) { server.system.outputScheduleFrame(m) }
    }

    /// What a wheel's notch does: the workspace overview takes it, or an axis binding (`dispatch` when it
    /// fires); nil when nothing takes it and it goes to the app.
    package enum Axis {
        case workspaceOverview(WlrPointerAxisEvent)
        case binding(fires: Dispatch?)
    }

    /// handle_cursor_axis. `discrete` is the notches (wlroots' value120 / 120).
    package static func axis(vertical: Bool, delta: Double, discrete: Double, timeMsec: UInt32, mods: Modifiers,
                             workspaceOverviewActive: Bool, axisBindings: [AxisBinding], mode: String,
                             axisBindApplyTimeout: UInt32, applyTime: inout UInt32, applyDir: inout Int32) -> Axis? {
        if Pointer.workspaceOverviewTakesAxis(mods: mods, workspaceOverviewActive: workspaceOverviewActive) {
            return .workspaceOverview(WlrPointerAxisEvent(timeMsec: timeMsec, delta: delta, deltaDiscrete: Int32(discrete * 120)))
        }
        guard let a = Pointer.handleCursorAxis(vertical: vertical, delta: delta, timeMsec: timeMsec, mods: mods,
                                               axisBindings: axisBindings, mode: mode,
                                               axisBindApplyTimeout: axisBindApplyTimeout,
                                               axisApplyTime: &applyTime, axisApplyDir: &applyDir) else { return nil }
        return .binding(fires: a.fires ? a.binding.dispatch : nil)
    }
}
