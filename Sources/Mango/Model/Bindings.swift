import Foundation

public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let superKey = Modifiers(rawValue: 1 << 0)
    public static let ctrl = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let alt = Modifiers(rawValue: 1 << 3)
    public static let fn = Modifiers(rawValue: 1 << 4)
    public static let hyper = Modifiers(rawValue: 1 << 5)

    /// mango parse_mod (binding_parse.c)
    // not in mango: `error`, mango_error's message given to the caller
    public static func parse(_ s: String, error: (String) -> Void = { _ in }) -> Modifiers? {
        guard !s.isEmpty else { return nil }
        var result: Modifiers = []
        var matched = false
        for raw in s.lowercased().split(separator: "+") {
            let tok = ConfigParser.trimWhitespace(raw)
            if tok.isEmpty { continue }
            if tok.hasPrefix("code:") {
                if let (code, rest) = ValueParse.strtol(tok.dropFirst(5)), rest.isEmpty || rest.first == " " {
                    switch code {
                    case 133, 134: result.insert(.superKey); matched = true
                    case 37, 105: result.insert(.ctrl); matched = true
                    case 50, 62: result.insert(.shift); matched = true
                    case 64, 108: result.insert(.alt); matched = true
                    default: error("unknown modifier keycode: \(mangoHighlight(tok))")
                    }
                }
                continue
            }
            switch tok {
            case "none": matched = true
            case "super", "super_l", "super_r": result.insert(.superKey); matched = true
            case "ctrl", "ctrl_l", "ctrl_r": result.insert(.ctrl); matched = true
            case "shift", "shift_l", "shift_r": result.insert(.shift); matched = true
            case "alt", "alt_l", "alt_r": result.insert(.alt); matched = true
            case "hyper", "hyper_l", "hyper_r": result.insert(.hyper); matched = true
            default:
                if let m = ConfigParser.port?.modifier(tok) {   // the port's names: not in mango
                    result.formUnion(m)
                    matched = true
                }
            }
        }
        if !matched { error("Unknown modifier: \(mangoHighlight(s))") }
        return matched ? result : nil
    }
}

public struct Dispatch: Equatable, Hashable, Sendable {
    public var name: String
    public var args: [String]
    public init(name: String, args: [String] = []) {
        self.name = name
        self.args = args
    }
    /// Not in mango: an argument, "0" when absent like sscanf defaults.
    public func arg(_ i: Int) -> String { i < args.count ? args[i] : "0" }

/// Not in mango: dispatchers the port does not do are accepted and do nothing (with a log line).
    public static let knownNames: Set<String> = [
        "focusstack", "focusdir", "focus_window_or_workspace", "focuslast", "focusid", "focusmon",
        "tagmon", "exchange_client", "exchange_stack_client", "move_client", "zoom", "incnmaster",
        "setmfact", "setlayout", "switch_layout", "set_proportion", "switch_proportion_preset",
        "scroller_stack", "view", "toggleview", "comboview", "viewtoleft", "viewtoright",
        "viewtoleft_have_client", "viewtoright_have_client", "viewprev_have_client",
        "viewnext_have_client", "view_insert", "viewcrossmon", "tag", "tagsilent", "tagtoleft",
        "tagtoright", "tagcrossmon", "toggletag", "killclient", "smartkillclient", "togglefloating",
        "toggle_all_floating", "togglefullscreen", "togglefakefullscreen", "togglemaximizescreen",
        "toggleglobal", "toggleoverlay", "toggle_render_border", "centerwin", "minimized",
        "restore_minimized", "toggle_scratchpad", "toggle_named_scratchpad", "toggle_special_tag",
        "tag_special_tag", "tag_special_silent", "movewin", "resizewin", "smartmovewin",
        "smartresizewin", "moveresize", "incgaps", "togglegaps", "togglegroupbar", "groupjoin",
        "groupleave", "groupfocus", "toggleoverview", "enteroverview", "leaveoverview", "overcircle",
        "togglejump", "switcher", "spawn", "spawn_shell", "spawn_on_empty", "reload_config",
        "load_config_file", "quit", "setkeymode", "setoption", "switch_keyboard_layout",
        "toggle_trackpad_enable", "create_virtual_output", "destroy_all_virtual_output",
        "disable_monitor", "enable_monitor", "toggle_monitor", "sleep_monitor", "wakeup_monitor",
        "sleep_toggle_monitor", "togglehdr", "dwindle_toggle_split_direction",
        "dwindle_split_horizontal", "dwindle_split_vertical", "dwindle_toggle_current_split", "chvt",
    ]

    /// mango parse_func_name (binding_parse.c), its name lookup; and the port's own
    /// dispatchers (ConfigParser.port, not in mango).
    public static func isKnown(_ name: String) -> Bool {
        knownNames.contains(name) || (ConfigParser.port?.knowsDispatcher(name) ?? false)
    }
}

public struct MultiKeycode: Equatable, Sendable {
    // not in mango: nil for none, as macOS's key code 0 is a key
    public var keycode1: UInt16?
    public var keycode2: UInt16?
    public var keycode3: UInt16?

    public init(keycode1: UInt16? = nil, keycode2: UInt16? = nil, keycode3: UInt16? = nil) {
        self.keycode1 = keycode1
        self.keycode2 = keycode2
        self.keycode3 = keycode3
    }
}

// not in mango: the bind keyword's letters (parse_bind_flags) as one set
public struct KeyBindingFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let keysym = KeyBindingFlags(rawValue: 1 << 0)
    public static let locked = KeyBindingFlags(rawValue: 1 << 1)
    public static let release = KeyBindingFlags(rawValue: 1 << 2)
    public static let passthrough = KeyBindingFlags(rawValue: 1 << 3)
    public static let allowConflict = KeyBindingFlags(rawValue: 1 << 4)
}

public struct KeyBinding: Equatable, Hashable, Sendable {
    public var mode: String
    public var mods: Modifiers
    public var keyName: String
    public var keyCodes: [UInt16]
    public var flags: KeyBindingFlags
    public var dispatch: Dispatch

    public init(mode: String = "default", mods: Modifiers, keyName: String, keyCodes: [UInt16],
                flags: KeyBindingFlags = [], dispatch: Dispatch) {
        self.mode = mode; self.mods = mods; self.keyName = keyName
        self.keyCodes = keyCodes; self.flags = flags; self.dispatch = dispatch
    }
}

public enum MouseButton: Hashable, Sendable {
    case left, right, middle, side, extra, forward, back, task
    case code(Int)

    // not in mango: the button as macOS numbers it (CGEvent's mouse button number)
    public var cgButtonNumber: Int {
        switch self {
        case .left: return 0
        case .right: return 1
        case .middle: return 2
        case .side, .back: return 3
        case .extra, .forward: return 4
        case .task: return 5
        case .code(let n): return n
        }
    }
}

public struct MouseBinding: Equatable, Hashable, Sendable {
    public var mode: String
    public var mods: Modifiers
    public var button: MouseButton
    public var dispatch: Dispatch
    public init(mode: String = "default", mods: Modifiers, button: MouseButton, dispatch: Dispatch) {
        self.mode = mode; self.mods = mods; self.button = button; self.dispatch = dispatch
    }
}

public struct AxisBinding: Equatable, Hashable, Sendable {
    public var mode: String
    public var mods: Modifiers
    public var dir: UInt32
    public var dispatch: Dispatch
    public init(mode: String = "default", mods: Modifiers, dir: UInt32, dispatch: Dispatch) {
        self.mode = mode; self.mods = mods; self.dir = dir; self.dispatch = dispatch
    }
}

public struct GestureBinding: Equatable, Hashable, Sendable {
    public var mode: String
    public var mods: Modifiers
    public var motion: UInt32
    public var fingersCount: UInt32
    public var dispatch: Dispatch
    public init(mode: String = "default", mods: Modifiers, motion: UInt32, fingersCount: UInt32, dispatch: Dispatch) {
        self.mode = mode; self.mods = mods; self.motion = motion; self.fingersCount = fingersCount; self.dispatch = dispatch
    }
}

// not in mango: the button as MouseButton, nil where mango returns UINT32_MAX; `error`,
// mango_error's message given to the caller
public func parseButton(_ str: String, error: (String) -> Void = { _ in }) -> MouseButton? {
    let s = str.lowercased()
    if s.hasPrefix("code:") {
        guard let (n, rest) = ValueParse.strtoul(s.dropFirst(5)), rest.isEmpty, n <= UInt64(UInt32.max) else {
            error("Invalid code format: \(mangoHighlight(str))")
            return nil
        }
        switch n {
        case 272: return .left
        case 273: return .right
        case 274: return .middle
        case 275: return .side
        case 276: return .extra
        case 277: return .forward
        case 278: return .back
        case 279: return .task
        default: return .code(Int(n))
        }
    }
    switch s {
    case "btn_left": return .left
    case "btn_right": return .right
    case "btn_middle": return .middle
    case "btn_side": return .side
    case "btn_extra": return .extra
    case "btn_forward": return .forward
    case "btn_back": return .back
    case "btn_task": return .task
    default:
        error("Unknown button: \(mangoHighlight(str))")
        return nil
    }
}
