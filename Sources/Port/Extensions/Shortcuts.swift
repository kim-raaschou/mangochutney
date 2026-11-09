import Foundation
import Mango

enum ShortcutFormatter {
    static func mods(_ m: Modifiers) -> String {
        var s = ""
        if m.contains(.ctrl) { s += "⌃" }
        if m.contains(.alt) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.superKey) { s += "⌘" }
        if m.contains(.fn) { s += "fn" }
        return s
    }

    static func key(_ name: String) -> String {
        switch name.lowercased() {
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        case "return", "enter", "kp_enter": return "↩"
        case "tab": return "⇥"
        case "space": return "Space"
        case "escape": return "Esc"
        case "backspace": return "⌫"
        case "delete": return "⌦"
        case "comma": return ","
        case "period": return "."
        case "minus": return "-"
        case "plus": return "+"
        case "equal": return "="
        case "slash": return "/"
        case "backslash": return "\\"
        case "semicolon": return ";"
        case "apostrophe", "quote": return "'"
        case "grave": return "`"
        case "bracketleft": return "["
        case "bracketright": return "]"
        default: return name.count == 1 ? name.uppercased() : name
        }
    }

    static func combo(_ m: Modifiers, _ k: String) -> String {
        let p = mods(m)
        return p.isEmpty ? key(k) : "\(p) \(key(k))"
    }

    static func action(_ d: Dispatch) -> String {
        let a0 = d.arg(0), a1 = d.arg(1)
        switch d.name {
        case "focusdir": return "focus \(a0)"
        case "focus_window_or_workspace": return "focus \(a0) (or next tag)"
        case "move_client": return "move window \(a0)"
        case "exchange_client": return "swap window \(a0)"
        case "focusstack": return a0 == "next" ? "focus next window" : "focus previous window"
        case "focuslast": return "focus last window"
        case "zoom": return "swap with master"
        case "view": return a0 == "-1" ? "previous tags" : "view tag \(a0)"
        case "toggleview": return "toggle tag \(a0) in view"
        case "tag": return "send window to tag \(a0)"
        case "tagsilent": return "send window to tag \(a0) (stay)"
        case "toggletag": return "toggle window on tag \(a0)"
        case "viewtoleft": return "tag to the left"
        case "viewtoright": return "tag to the right"
        case "viewtoleft_have_client", "viewprev_have_client": return "previous occupied tag"
        case "viewtoright_have_client", "viewnext_have_client": return "next occupied tag"
        case "tagtoleft": return "send window one tag left"
        case "tagtoright": return "send window one tag right"
        case "toggle_special_tag": return "show/hide special tag"
        case "tag_special_tag": return "send window to special tag"
        case "focusmon": return "focus \(a0) monitor"
        case "tagmon": return "send window to \(a0) monitor"
        case "switch_layout": return "next layout"
        case "setlayout": return "layout: \(a0)"
        case "togglefloating": return "floating on/off"
        case "toggle_all_floating": return "all windows floating on/off"
        case "togglefullscreen": return "fullscreen on/off"
        case "togglefakefullscreen": return "fake fullscreen on/off"
        case "togglemaximizescreen": return "maximize on/off"
        case "toggleglobal": return "show on all tags on/off"
        case "toggleoverlay": return "always on top on/off"
        case "killclient": return a0 == "force" ? "kill app" : "close window"
        case "minimized": return "minimize to scratchpad"
        case "restore_minimized": return "restore minimized window"
        case "toggle_scratchpad": return "show/hide scratchpad"
        case "toggle_named_scratchpad": return "show/hide scratchpad \(a0)"
        case "toggleoverview", "enteroverview": return "overview of all windows"
        case "leaveoverview": return "leave overview"
        case "togglejump": return "jump to window (letter labels)"
        case "switcher":
            let back = a0.hasSuffix("prev")
            let scope = a0.hasPrefix("all_tag") ? " (all tags)" : a0.hasPrefix("all") ? " (all monitors)" : ""
            return "window switcher\(back ? ", backwards" : "")\(scope)"
        case "chutney_launch_or_focus": return "focus or open \(a0)"
        case "overcircle": return "overview, tab mode"
        case "reload_config": return "reload config"
        case "quit": return "quit mango"
        case "spawn", "spawn_shell": return "run: " + d.args.filter { $0 != "0" }.joined(separator: ",")
        case "setkeymode": return a0 == "default" ? "back to normal mode" : "enter \(a0) mode"
        case "resizewin": return "resize \(a0),\(a1)"
        case "movewin": return "move \(a0),\(a1)"
        case "smartmovewin": return "move floating window \(a0)"
        case "smartresizewin": return "resize floating window \(a0)"
        case "scroller_stack": return "stack into column \(a0)"
        case "switch_proportion_preset": return "cycle column width"
        case "set_proportion": return "column width \(a0)"
        case "incnmaster": return "masters \(a0)"
        case "setmfact": return "master size \(a0)"
        case "incgaps": return "gaps \(a0)"
        case "togglegaps": return "gaps on/off"
        case "centerwin": return "center window"
        case "dwindle_toggle_split_direction": return "flip dwindle split"
        case "moveresize": return a0 == "curresize" ? "resize window" : "move window"
        default:
            let args = d.args.filter { $0 != "0" }
            return args.isEmpty ? d.name : "\(d.name) \(args.joined(separator: ","))"
        }
    }

    static func rows(_ c: Config) -> [ShortcutRow] {
        var rows: [ShortcutRow] = []
        for b in c.keyBindings {
            var keys = combo(b.mods, b.keyName)
            if b.flags.contains(.release) { keys += " (release)" }
            rows.append(ShortcutRow(mode: b.mode, keys: keys, action: action(b.dispatch),
                                    dispatch: b.dispatch.name, args: b.dispatch.args))
        }
        for b in c.mouseBindings {
            let button: String
            switch b.button {
            case .left: button = "left drag"
            case .right: button = "right drag"
            case .middle: button = "middle click"
            default: button = "button \(b.button.cgButtonNumber)"
            }
            let p = mods(b.mods)
            rows.append(ShortcutRow(mode: b.mode, keys: p.isEmpty ? button : "\(p) + \(button)",
                                    action: action(b.dispatch), dispatch: b.dispatch.name, args: b.dispatch.args))
        }
        for b in c.axisBindings {
            let p = mods(b.mods)
            rows.append(ShortcutRow(mode: b.mode, keys: (p.isEmpty ? "" : "\(p) + ") + "scroll \(b.direction?.rawValue ?? "alldir")",
                                    action: action(b.dispatch), dispatch: b.dispatch.name, args: b.dispatch.args))
        }
        for b in c.gestureBindings {
            let p = mods(b.mods)
            rows.append(ShortcutRow(mode: b.mode, keys: (p.isEmpty ? "" : "\(p) + ") + "\(b.fingers)-finger swipe \(b.direction?.rawValue ?? "any direction")",
                                    action: action(b.dispatch), dispatch: b.dispatch.name, args: b.dispatch.args))
        }
        return rows
    }
}

public struct ShortcutRow: Equatable, Sendable {
    public var mode: String
    public var keys: String
    public var action: String
    public var dispatch: String
    public var args: [String]
    public init(mode: String, keys: String, action: String, dispatch: String, args: [String]) {
        self.mode = mode; self.keys = keys; self.action = action; self.dispatch = dispatch; self.args = args
    }
}

extension ShortcutFormatter {
    static func bindsReply(_ rows: [ShortcutRow]) -> JSONValue {
        .object([("binds", .array(rows.map { r in
            .object([("mode", .string(r.mode)), ("keys", .string(r.keys)), ("action", .string(r.action)),
                     ("dispatch", .string(r.dispatch)), ("args", .array(r.args.map { .string($0) }))])
        }))])
    }
}

extension MangoServer {
    public var shortcutRows: [ShortcutRow] { ShortcutFormatter.rows(config) }
}
