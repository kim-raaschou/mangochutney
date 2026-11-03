import CoreGraphics

/// Not in mango: mango's keyboard decisions, taken on the port's event-tap thread (macOS wants the answer at once).
package enum Keyboard {
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
            if b.dispatch.name == "setkeymode" || b.dispatch.name == "chvt" { break }
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

extension Keyboard {
    package static func handleKeyboardKey(_ k: KeyInput, state: inout KeyboardState, bindings: [KeyBinding], mode: String,
                                          overcircleActive: Bool, switcherActive: Bool, tagCombo: Bool,
                                          cursorHideOnKeypress: Bool) -> (actions: [KeyAction], handled: Bool, swallow: Bool) {
        var actions: [KeyAction] = []
        let isModifierKey = k.keyModifier != nil
        if cursorHideOnKeypress && k.isDown { actions.append(.hideCursor) }
        if tagCombo && !k.isDown { actions.append(.endTagCombo) }
        if isModifierKey && !k.isDown {
            if overcircleActive { actions.append(.leaveOvercircle) }
            if switcherActive { actions.append(.switcherCommit) }
        }
        if k.isDown && !k.isRepeat { state.lastHoldKeycode = k.keyCode }
        let matches = keyboardCheckKeybinding(bindings, mode: mode, keyCode: k.keyCode, mods: k.mods, isDown: k.isDown,
                                              keyModifier: k.keyModifier,
                                              lastHoldKeycodeIsThisKey: !k.isDown && state.lastHoldKeycode == k.keyCode)
        var handled = false
        for b in matches {
            if k.isRepeat && (b.flags.contains(.release) || b.flags.contains(.passthrough)) { continue }
            actions.append(.binding(b, held: k.isRepeat))
            if !b.flags.contains(.passthrough) { handled = true }
        }
        if handled && k.isDown { state.boundKeys.insert(k.keyCode) }
        if !k.isDown && state.boundKeys.remove(k.keyCode) != nil { handled = true }
        return (actions, handled, handled)
    }

/// mango handle_keyboard_key
    package static func handleUnboundKey(_ k: KeyInput, state: inout KeyboardState, jumpActive: Bool, isEscape: Bool,
                                         jumpLabel: String?, globalKeys: [(mods: Modifiers, keyCodes: Set<UInt16>, pid: pid_t)])
        -> (action: KeyAction?, swallow: Bool) {
        if jumpActive, k.isDown {
            if isEscape { state.boundKeys.insert(k.keyCode); return (.overviewKey(.escape), true) }
            if let jumpLabel { state.boundKeys.insert(k.keyCode); return (.overviewKey(.jump(jumpLabel)), true) }
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
