import CoreGraphics

package extension MangoServer {
    /// Not in mango: hands binding state to the event-tap thread.
    func publishInputState() {
        let c = config
        let mode = keyMode
        let sw = switcherIsActive()
        let hidden = cursorHidden
        let combo = tagCombo
        system.publishInput(InputState(
            keymode: mode, bindings: c.keyBindings, mouseBindings: c.mouseBindings, axisBindings: c.axisBindings,
            axisBindApplyTimeout: UInt32(truncatingIfNeeded: c.axisBindApplyTimeout),
            overviewFrame: selectedMonitor.flatMap { $0.isoverview ? $0.m : nil },
            jumpMode: selectedMonitor?.isJumpMode ?? false,
            jumpKeycodes: Set(clients.filter { $0.mon === selectedMonitor }.flatMap {
                [$0.jumpKeycodes.keycode1, $0.jumpKeycodes.keycode2, $0.jumpKeycodes.keycode3].compactMap { $0 }
            }),
            // not in mango: keyboard.c's overcircle test, for the event tap
            overcircleActive: selectedMonitor.map { $0.ovTabLayout && !$0.isJumpMode && $0.isoverview && $0.sel != nil } ?? false,
            switcherActive: sw, tagCombo: combo,
            wantsMouseMoved: c.sloppyfocus || c.enableHotarea || c.cursorHideTimeout > 0 || hidden
                || c.windowRules.contains { $0.confinePointer == true } || c.enableBorderResize,
            cursorHideOnKeypress: c.cursorHideOnKeypress && !hidden,
            hoverResizeCursor: hoverResizeEdge.isEmpty || grabClient != nil ? nil : resizeCursorName(hoverResizeEdge, hoverResizeFloating)))
        publishGlobalKeys()
    }

    // not in mango: xkb_rules_options split for the port, which has no xkb
    static func xkbOptions(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }
}
