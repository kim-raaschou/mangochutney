import Foundation
import CoreGraphics

public struct Config: Sendable {
    public init() {}

    public var animations = true
    public var animationTypeOpen: AnimationType = .slide
    public var animationTypeClose: AnimationType = .slide
    public var animationFadeIn = true
    public var animationFadeOut = true
    public var tagAnimationDirection = 1
    public var zoomInitialRatio = 0.4
    public var zoomEndRatio = 0.8
    public var fadeinBeginOpacity = 0.5
    public var fadeoutBeginOpacity = 0.5
    public var animationDurationMove = 500
    public var animationDurationOpen = 400
    public var animationDurationTag = 300
    public var animationDurationClose = 300
    public var animationDurationFocus = 0
    public var animationCurveMove = BezierCurve.mangoDefault
    public var animationCurveOpen = BezierCurve.mangoDefault
    public var animationCurveTag = BezierCurve.mangoDefault
    public var animationCurveClose = BezierCurve.mangoDefault
    public var animationCurveFocus = BezierCurve.mangoDefault

    public var scrollerStructs = 20
    public var scrollerDefaultProportion = 0.9
    public var scrollerDefaultProportionSingle = 1.0
    public var scrollerIgnoreProportionSingle = true
    public var scrollerFocusCenter = false
    public var scrollerPreferCenter = false
    public var scrollerPreferOverspread = true
    public var edgeScrollerPointerFocus = true
    public var edgeScrollerFocusAllowSpeed = 0.0
    public var scrollerProportionPreset: [Double] = []

    public var newIsMaster = true
    public var defaultMfact = 0.55
    public var defaultNmaster = 1
    public var centerMasterOverspread = false
    public var centerWhenSingleStack = true
    public var tagNum = 9
    public var tagGather = false
    public var tagCarousel = false
    public var viewCurrentToBack = false
    public var circleLayout: [String] = []
    public var dwindleVsplit = 1
    public var dwindleHsplit = 1
    public var dwindlePreserveSplit = false
    public var dwindleSmartSplit = false
    public var dwindleSmartResize = false
    public var dwindleManualSplit = false
    public var dwindleDropSimpleSplit = true
    public var dwindleSplitRatio = 0.5
    public var monocleTabMode = true
    public var monocleNoBorder = false
    public var monocleNoGap = false
    public var monocleNoRadius = false
    public var specialTagCrossMonitor = false
    public var deckTabMode = true
    public var tabBarHeight = 33
    public var groupBarHeight = 33
    public var alwaysShowGroupBar = false
    public var groupBarCloseButtonEnable = false
    public var groupBarButtonSize = 16
    public var groupBarButtonMargin = 4
    public var groupBarButtonColor = parseColor("0xad401fff")!
    public var monocleRightButtonClose = false
    public var titleMessageBarHeight = 52
    public var titleMessageBarGap = 20
    public var titleMessageBardata = DecorateStyle()
    public var tabbardata = DecorateStyle()
    public var groupbardata = DecorateStyle()
    public var jumplabeldata = DecorateStyle()

    public var gappih = 5
    public var gappiv = 5
    public var gappoh = 10
    public var gappov = 10
    public var smartgaps = false
    public var borderpx = 4
    public var borderRadius = 0
    public var noBorderWhenSingle = false
    public var noRadiusWhenSingle = false
    public var focusedOpacity = 1.0
    public var unfocusedOpacity = 1.0
    public var rootcolor = parseColor("0x323232ff")!
    public var bordercolor = parseColor("0x444444ff")!
    public var focuscolor = parseColor("0xc66b25ff")!
    public var urgentcolor = parseColor("0xad401fff")!
    public var maximizescreencolor = parseColor("0x89aa61ff")!
    public var scratchpadcolor = parseColor("0x516c93ff")!
    public var globalcolor = parseColor("0xb153a7ff")!
    public var overlaycolor = parseColor("0x14a57cff")!
    public var dropcolor = RGBA(r: 0xd5 / 255.0, g: 0x89 / 255.0, b: 0x9d / 255.0, a: 0.5)
    public var splitcolor = parseColor("0xeb441eff")!
    public var scratchpadWidthRatio = 0.8
    public var scratchpadHeightRatio = 0.9
    public var specialDim = 0.5
    public var specialGappih = 10
    public var specialGappiv = 10
    public var specialGappoh = 20
    public var specialGappov = 20

    public var hotareaSize = 10
    public var hotareaCorner = 2
    public var enableHotarea = false
    public var hotareaDisableOnFullscreen = true
    public var overviewgappi = 5
    public var overviewgappo = 30
    public var overcircleCenterRatio = 0.5
    public var jumpLabels = "HJKLASDFGQWERTYUIOPZXCVBNM"

    public var focusOnActivate = true
    public var sloppyfocus = true
    public var warpcursor = true
    public var focusCrossMonitor = false
    public var focusdirOnlyZoneOverlap = true
    public var focusCrossTag = false
    public var exchangeCrossMonitor = false
    public var scratchpadCrossMonitor = false
    public var singleScratchpad = true
    public var cursorHideTimeout = 0
    public var cursorHideOnKeypress = false
    public var dragCorner = 3
    public var dragWarpCursor = true
    public var enableBorderResize = true
    public var borderResizeSize = 10
    public var enableFloatingSnap = false
    public var snapDistance = 30
    public var floatFullToTop = false
    public var dragTileToTile = true
    public var dragTileSmall = true
    public var axisBindApplyTimeout = 100
    public var autoReloadConfig = true
    public var logLevel: WlrLogImportance = .error
    public var swipeMinThreshold = 1
    public var gestureLive = true
    public var gestureSwipeDistance = 300
    public var gestureSwipeCancelRatio = 0.5
    public var gestureSwipeMinSpeedToForce = 10.0
/// Not in mango: on macOS only the options that move keys are done.
    public var xkbRulesOptions = ""

    /// The boundary, not in mango: the values of the port's own keys, as its setters store
    /// them (ConfigPort); the port reads them as fields of its own (Port/Extensions/PortConfig.swift).
    package var port: [String: String] = [:]

    public var vars: [String: String] = [:]   // not in mango: the ConfigVar list as a table by name
    public var envVars: [(String, String)] = []
    public var exec: [String] = []
    public var execOnce: [String] = []

    public var keyBindings: [KeyBinding] = []
    public var mouseBindings: [MouseBinding] = []
    public var axisBindings: [AxisBinding] = []
    public var switchBindings: [SwitchBinding] = []
    public var gestureBindings: [GestureBinding] = []
    public var windowRules: [ConfigWinRule] = []
    public var tagRules: [ConfigTagRule] = []
    public var keymode = "default"
}

/* Tag animation / folding / global switch state. */
public let VERTICAL = 0
public let HORIZONTAL = 1
let UNFOLD: Int32 = 0, FOLD: Int32 = 1, INVALIDFOLD: Int32 = 2

// not in mango: enum animation_type; ANIM_TYPE_UNSET and ANIM_TYPE_UNKNOWN are .slide, as
// animation/client.c opens them (a window's own type is nil where it is unset)
public enum AnimationType: String, Sendable {
    case slide, zoom, fade, none
}

/* Enums */
let NUM_TYPE_MINUS: UInt32 = 0, NUM_TYPE_PLUS: UInt32 = 1, NUM_TYPE_DEFAULT: UInt32 = 2

let KEY_TYPE_CODE = 0, KEY_TYPE_SYM = 1

/// Not in mango: `name` is matched against the display's localized name.
public struct MonitorSpec: Equatable, Hashable, Sendable {
    public var name: String?
    public var make: String?
    public var model: String?
    public var serial: String?

    public init(name: String? = nil, make: String? = nil, model: String? = nil, serial: String? = nil) {
        self.name = name; self.make = make; self.model = model; self.serial = serial
    }

    // not in mango: match_monitor_spec's parse of the spec (manage/monitor.c), apart
    public init(mango spec: String) {
        // if the spec does not contain a colon, treat it as a match on the monitor
        // name
        if !spec.contains(":") { name = spec; return }
        for token in spec.split(separator: "&") {
            guard let colon = token.firstIndex(of: ":") else { continue }
            let key = token[..<colon]
            let value = String(token[token.index(after: colon)...])

            if key == "name" {
                name = value
            } else if key == "make" {
                make = value
            } else if key == "model" {
                model = value
            } else if key == "serial" {
                serial = value
            }
        }
    }

    /// mango match_monitor_spec (manage/monitor.c)
    public func matchMonitorSpec(_ screen: Screen) -> Bool {
        var match = true

        if let name {
            if !regexMatch(name, screen.name) {
                match = false
            }
        }
        if let make {
            if screen.make == nil || make != screen.make {
                match = false
            }
        }
        if let model {
            if screen.model == nil || model != screen.model {
                match = false
            }
        }
        if let serial {
            if screen.serial == nil || serial != screen.serial {
                match = false
            }
        }

        return match
    }
}

/// Not in mango: `app_id` is matched against the bundle id and the app's name; a nil field is
/// mango's -1 (unset).
public struct ConfigWinRule: Equatable, Sendable {
    public var appId: String?
    public var title: String?
    public var once = false
    public var isOnceApplied = false

    public var isfloating: Bool?
    public var isfullscreen: Bool?
    public var isfakefullscreen: Bool?
    public var isglobal: Bool?
    public var isoverlay: Bool?
    public var isopensilent: Bool?
    public var istagsilent: Bool?
    public var isnamedscratchpad: Bool?
    public var isUnmanagedGlobal: Bool?
    public var isTerm: Bool?
    public var noSwallow: Bool?

    public var tags: UInt32?
    public var monitor: MonitorSpec?
    public var width: Double?
    public var height: Double?
    public var offsetX: Int?
    public var offsetY: Int?
    public var noForceCenter: Bool?
    public var noSizeHint: Bool?

    public var noBorder: Bool?
    public var noShadow: Bool?
    public var noRadius: Bool?
    public var noBlur: Bool?
    public var noAnimation: Bool?
    public var noFadeIn: Bool?
    public var noFadeOut: Bool?
    public var focusedOpacity: Double?
    public var unfocusedOpacity: Double?
    public var allowCsd: Bool?
    public var animationTypeOpen: AnimationType?
    public var animationTypeClose: AnimationType?

    public var scrollerProportion: Double?
    public var scrollerProportionSingle: Double?

    public var noFocus: Bool?
    public var confinePointer: Bool?
    public var ignoreMaximize: Bool?
    public var ignoreMinimize: Bool?
    public var forceTiledState: Bool?
    public var globalKeyBinding: String?

    public init() {}

    public func isWindowRuleMatches(appId id: String, appName: String, title t: String) -> Bool {
        var matched = false
        if let appId {
            let hit = regexMatch(appId, id)
                || regexMatch(appId, appName)   // not in mango: the app's name too (macOS app ids are bundle ids)
            if !hit { return false }
            matched = true
        }
        if let title {
            if !regexMatch(title, t) { return false }
            matched = true
        }
        return matched
    }

}

public struct ConfigTagRule: Equatable, Sendable {
    public var id: Int?
    public var layoutName: String?
    public var monitorName: String?
    public var monitorMake: String?
    public var monitorModel: String?
    public var monitorSerial: String?
    public var noRenderBorder = false
    public var openAsFloating = false
    public var noHide = false
    public var masterCount: Int?
    public var masterFactor: Double?
    public var scrollerDefaultProportion = 0.0
    public var scrollerDefaultProportionSingle = 0.0
    public var scrollerIgnoreProportionSingle: Bool?

    public init() {}
}

public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let superKey = Modifiers(rawValue: 1 << 0)
    public static let ctrl = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let alt = Modifiers(rawValue: 1 << 3)
    public static let fn = Modifiers(rawValue: 1 << 4)
    public static let hyper = Modifiers(rawValue: 1 << 5)
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

    /// mango parse_func_name's names (binding_parse.c)
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

public struct SwitchBinding: Equatable, Hashable, Sendable {
    public var mode: String
    public var fold: Int32
    public var dispatch: Dispatch
    public init(mode: String = "default", fold: Int32, dispatch: Dispatch) {
        self.mode = mode; self.fold = fold; self.dispatch = dispatch
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
