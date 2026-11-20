import CoreGraphics

// not in mango: handle_keyboard_key_watch and ipc_notify_device_event, find_device_rule, keyboard_create,
// device_rule_has_keyboard_settings, compile_rule_keymap and the keymaps (xkb), keyboard_repeat (macOS
// repeats a held key itself), is_keyboard_shortcut_inhibitor and the shortcuts inhibitor protocol,
// keyboard_sync_keymap, the standalone and virtual keyboards and the keyboard group,
// keyboard_hard_modifiers (the port's), keyboard_cancel_pending_release_bind (the event tap's
// last_hold_keycode), handle_keyboard_modifiers (the port gives printstatus(IPC_WATCH_KB_LAYOUT) when
// macOS's input source changes), the input method, the idle notifier and the session lock. Bindings match
// on macOS key codes, not keysyms (docs/afvigelser.md §3).

package extension MangoServer {
    // not in mango: keyboard_process_global_keypress's rules, given ahead to the event tap, which sends
    // a press to the window's app
    func publishGlobalKeys() {
        let rules = config.windowRules.filter { $0.globalKeyBinding != nil && ($0.appId != nil || $0.title != nil) }
        guard !rules.isEmpty || publishedGlobalKeys else { return }
        let focusedNow = focused
        let windows = clients
        var keys: [GlobalKey] = []
        for r in rules {
            guard let spec = r.globalKeyBinding, let dash = spec.firstIndex(of: "-"),
                  let mods = BindingParser.parseMod(String(spec[..<dash])), !mods.isEmpty else { continue }
            let name = String(spec[spec.index(after: dash)...]).trimmingCharacters(in: .whitespaces)
            guard let target = windows.first(where: {
                $0 !== focusedNow && r.isWindowRuleMatches(appId: $0.bundleId, appName: $0.appName, title: $0.title)
            }), target.pid != focusedNow?.pid else { continue }   // not in mango: a key goes to an app, not a window
            keys.append(GlobalKey(mods: mods, keyName: name, pid: target.pid))
        }
        publishedGlobalKeys = !keys.isEmpty
        system.publishGlobalKeys(keys)   // not in mango: the port's side
    }
}

/// Not in mango: mango's keyboard decisions, taken on the port's event-tap thread (macOS wants the answer at once).
package enum Keyboard {
    static func keyboardIsBoundKey(_ state: KeyboardState, _ keycode: UInt16) -> Bool {
        state.boundKeys.contains(keycode)
    }

    /* Record a key the compositor consumed, so clients never see it as held. */
    static func keyboardMarkBoundKey(_ state: inout KeyboardState, _ keycode: UInt16) {
        state.boundKeys.insert(keycode)
    }

    /* Drop the key once it is released. */
    static func keyboardUnmarkBoundKey(_ state: inout KeyboardState, _ keycode: UInt16) {
        state.boundKeys.remove(keycode)
    }

    /// mango keyboard_check_keybinding (keyboard.c), the bindings it runs
    // not in mango: the bindings found are run on the main thread; matched on macOS key codes, not keysyms,
    // with a modifier key's own modifier added (release) or taken away (press), as xkb's state is before the key
    package static func keyboardCheckKeybinding(_ bindings: [KeyBinding], mode: String, keyCode: UInt16,
                                                mods: Modifiers, isDown: Bool, keyModifier: Modifiers?,
                                                lastHoldKeycodeIsThisKey: Bool) -> [KeyBinding] {
        var out: [KeyBinding] = []
        for b in bindings {
            guard b.mode == "common" || b.mode == mode else { continue }
            guard b.keyCodes.contains(keyCode) else { continue }
            let wantsRelease = b.flags.contains(.release)
            let evMods = b.mods.contains(.fn) ? mods : mods.subtracting(.fn)
            if let keyModifier {
                if wantsRelease {
                    guard !isDown, lastHoldKeycodeIsThisKey else { continue }
                    guard evMods.union(keyModifier) == b.mods else { continue }
                } else {
                    guard isDown, evMods.subtracting(keyModifier) == b.mods else { continue }
                }
            } else {
                guard evMods == b.mods else { continue }
                if wantsRelease {
                    guard !isDown, lastHoldKeycodeIsThisKey else { continue }
                } else {
                    guard isDown else { continue }
                }
            }
            out.append(b)
            // not in mango: the dispatchers that return non-zero, known before they run (docs/afvigelser.md §3)
            if ["setkeymode", "chvt", "reload_config", "load_config_file"].contains(b.dispatch.name) { break }
            // only match the first keybind
            if !b.flags.contains(.allowConflict) { break }
        }
        return out
    }
}

package struct KeyboardState {
    package var lastHoldKeycode: UInt16?
    package var boundKeys: Set<UInt16> = []
    package var forwardedKeys: [UInt16: pid_t] = [:]
    package init() {}
}

package enum KeyAction: Equatable {
    case leaveOvercircle
    case switcherCommit
    case hideCursor
    case endTagCombo
    case binding(KeyBinding, held: Bool)
    case overviewKey(OverviewKey)
    case forward(pid_t, down: Bool)
}

package struct KeyInput {
    package var keyCode: UInt16
    package var mods: Modifiers
    package var isDown: Bool
    package var isRepeat: Bool
    package var keyModifier: Modifiers?
    package init(keyCode: UInt16, mods: Modifiers, isDown: Bool, isRepeat: Bool, keyModifier: Modifiers?) {
        self.keyCode = keyCode; self.mods = mods; self.isDown = isDown; self.isRepeat = isRepeat
        self.keyModifier = keyModifier
    }
}

package extension MangoServer {
    func keyboardFindJumpClient(_ m: Monitor, _ keycode: UInt16) -> Client? {
        for c in clients {
            if c.mon !== m {
                continue
            }

            if keycode == c.jumpKeycodes.keycode1 ||
                keycode == c.jumpKeycodes.keycode2 ||
                keycode == c.jumpKeycodes.keycode3 {
                return c
            }
        }

        return nil
    }
}

extension Keyboard {
    /// mango handle_keyboard_key (keyboard.c), up to the bindings
    // not in mango: what the event tap decides; the actions run on the main thread (MangoServer.handleKeyboardKey)
    package static func handleKeyboardKey(_ k: KeyInput, state: inout KeyboardState, bindings: [KeyBinding], mode: String,
                                          overcircleActive: Bool, switcherActive: Bool, tagCombo: Bool,
                                          cursorHideOnKeypress: Bool) -> (actions: [KeyAction], handled: Bool, swallow: Bool) {
        var actions: [KeyAction] = []
        let isModeKeycode = !(k.keyModifier ?? []).subtracting(.fn).isEmpty   // not in mango: Caps Lock and Fn are no mode keys, as in xkb

        // In overcircle mode, releasing the mode key exits overview.
        if overcircleActive && !k.isDown && isModeKeycode {
            actions.append(.leaveOvercircle)
        }

        if switcherActive && !k.isDown && isModeKeycode {
            actions.append(.switcherCommit)
        }

        if cursorHideOnKeypress && k.isDown {
            actions.append(.hideCursor)
        }

        if !k.isDown {
            if tagCombo { actions.append(.endTagCombo) }
        } else if !k.isRepeat {
            // Avoids normal bindings affecting a bare mode-key binding.
            state.lastHoldKeycode = k.keyCode
        }

        let matches = keyboardCheckKeybinding(bindings, mode: mode, keyCode: k.keyCode, mods: k.mods, isDown: k.isDown,
                                              keyModifier: k.keyModifier,
                                              lastHoldKeycodeIsThisKey: !k.isDown && state.lastHoldKeycode == k.keyCode)
        var handled = false
        for b in matches {
            // not in mango: macOS repeats every held key; mango's keyboard_repeat repeats only a handled one
            if k.isRepeat && (b.flags.contains(.release) || b.flags.contains(.passthrough)) { continue }
            if !b.flags.contains(.passthrough) {
                handled = true
                /* Mark before running the binding: it may change focus. */
                if k.isDown { keyboardMarkBoundKey(&state, k.keyCode) }
            } else {
                handled = false
            }
            actions.append(.binding(b, held: k.isRepeat))
        }

        // not in mango: macOS repeats a held key the compositor consumed; mango's client never sees it held
        if k.isDown && k.isRepeat && keyboardIsBoundKey(state, k.keyCode) { handled = true }

        /* The press was swallowed, so swallow its release too. */
        if !k.isDown && keyboardIsBoundKey(state, k.keyCode) {
            keyboardUnmarkBoundKey(&state, k.keyCode)
            handled = true
        }
        return (actions, handled, handled)
    }

    /// mango handle_keyboard_key (keyboard.c), after the bindings
    // not in mango: what the event tap decides; Escape is macOS's key code 53, not XKB_KEY_Escape
    package static func handleUnboundKey(_ k: KeyInput, state: inout KeyboardState, jumpMode: Bool, isEscape: Bool,
                                         isJumpKey: Bool, globalKeys: [(mods: Modifiers, keyCodes: Set<UInt16>, pid: pid_t)])
        -> (action: KeyAction?, swallow: Bool) {
        if jumpMode, k.isDown {
            if isEscape { state.boundKeys.insert(k.keyCode); return (.overviewKey(.escape), true) }
            if isJumpKey { state.boundKeys.insert(k.keyCode); return (.overviewKey(.jump(k.keyCode)), true) }
        }
        if !k.isDown, let pid = state.forwardedKeys.removeValue(forKey: k.keyCode) {
            return (.forward(pid, down: false), true)
        }
        if k.isDown, let g = globalKeys.first(where: { $0.mods == k.mods.subtracting(.fn) && $0.keyCodes.contains(k.keyCode) }) {
            state.forwardedKeys[k.keyCode] = g.pid
            return (.forward(g.pid, down: true), true)
        }
        return (nil, false)
    }
}

package extension MangoServer {
    // not in mango: what the port's event-tap thread decided (Keyboard.handleKeyboardKey), on the main thread
    func handleKeyboardKey(_ actions: [KeyAction]) {
        for a in actions {
            switch a {
            case .leaveOvercircle:
                // In overcircle mode, releasing the mode key exits overview.
                if let m = selectedMonitor, m.ovTabLayout, !m.isJumpMode, m.isoverview, m.sel != nil {
                    toggleOverview(Arg())
                }
            case .switcherCommit:
                switcherCommit()
            case .hideCursor:
                if config.cursorHideOnKeypress && !cursorHidden { pointerHideCursor() }
            case .endTagCombo:
                tagCombo = false
            case .binding(let b, let held):
                _ = dispatch(b.dispatch, rescan: !held)
            // not in mango: the event tap decided before the bindings ran; is_jump_mode is asked after them
            case .overviewKey(.escape):
                if selectedMonitor?.isJumpMode == true {
                    toggleJump(Arg())
                }
            case .overviewKey(.jump(let keycode)):
                if let m = selectedMonitor, m.isJumpMode, let target = keyboardFindJumpClient(m, keycode) {
                    clientFocus(target, true)
                    toggleOverview(Arg(tc: target))
                }
            case .forward:
                break
            }
        }
    }

    func resetKeyboardLayout() {
        system.setKeyboardOptions(config.xkbRulesOptions)   // not in mango: xkb_keymap_new_from_names, the port's side
    }
}
