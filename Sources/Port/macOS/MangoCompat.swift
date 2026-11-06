import Foundation
import Mango

/// Not in mango: the port's compatibility table, given to mango's config reader through
/// ConfigPort (MacConfigPort, below). How each name in mango's configuration maps onto the
/// macOS port.
///
/// Every global option, keyword, rule field and dispatcher of mango (the lists in
/// `Tests/mango-keys`, extracted from mango's source by `script/mango-keys.sh`) is one of:
///
/// - implemented: it has an effect, as in mango or with a difference the README states;
/// - accepted without effect: parsed and validated like in mango, but the engine does not
///   use it, either because macOS cannot do it (`.impossible`) or because the port has not
///   implemented it yet (`.notImplemented`);
/// - ignored: accepted without parsing the value, because it belongs to a part of mango that
///   has no macOS counterpart (blur, libinput, xkb, ...).
///
/// `MangoCoverageTests` requires every mango name to be in one of these classes, so
/// "a stock mango config loads with zero unknown keys" is tested. `mango -p` reports the
/// non-implemented names a config uses, and `mango --list-ignored` prints these tables.
public enum MangoCompat {

    /// Why a mango name does nothing on macOS.
    public enum NoEffect: Equatable, Sendable {
        /// macOS does not let a window manager do this (the reason says why).
        case impossible(String)
        /// Possible on macOS; the port does not implement it yet.
        case notImplemented

        public var text: String {
            switch self {
            case .impossible(let why): return why
            case .notImplemented: return "not implemented in the macOS port yet"
            }
        }
    }

    public struct Group: Sendable {
        public let name: String
        public let reason: String
        public let keys: [String]
        /// Possible on macOS, not implemented yet (else: macOS does not allow it).
        public var notYet = false
    }

    // MARK: - Global options without a setter

    /// mango options that are accepted without reading the value, grouped by reason.
    public static let ignoredOptionGroups: [Group] = [
        Group(name: "Blur", reason: "scenefx effect; macOS draws other apps' windows", keys: [
            "blur", "blur_layer", "blur_optimized", "blur_params_brightness", "blur_params_contrast",
            "blur_params_noise", "blur_params_num_passes", "blur_params_radius", "blur_params_saturation",
        ]),
        Group(name: "Shadows", reason: "macOS draws window shadows", keys: [
            "shadows", "shadows_size", "shadows_blur", "shadows_color", "shadows_position_x",
            "shadows_position_y", "shadow_only_floating", "layer_shadows",
        ]),
        Group(name: "Dimming", reason: "darkening other apps' windows needs a compositor", keys: [
            "dim_enable", "dim_focused_color", "dim_unfocused_color",
        ]),
        Group(name: "Opacity animation", reason: "another app's window opacity can only be changed with SIP off", keys: [
            "animation_curve_opacity_fade_in", "animation_curve_opacity_fade_out",
        ]),
        Group(name: "Layer surfaces", reason: "macOS has no layer shell; bars and launchers are ordinary apps", keys: [
            "layer_animations", "layer_animation_type_open", "layer_animation_type_close",
        ]),
        Group(name: "Display", reason: "colour depth and tearing are display settings of macOS", keys: [
            "hdr_depth", "allow_tearing", "sync_obj_enable",
        ]),
        Group(name: "Keyboard", reason: "layout, repeat and Num Lock are macOS keyboard settings (mango repeats a binding with its own timer; the port leaves key repeat to macOS, and a passthrough binding does not repeat)", keys: [
            "xkb_rules_rules", "xkb_rules_model", "xkb_rules_layout", "xkb_rules_variant",
            "repeat_rate", "repeat_delay", "numlock_on",
        ]),
        Group(name: "Mouse", reason: "pointer settings are macOS settings", keys: [
            "mouse_accel_profile", "mouse_accel_speed", "mouse_click_method", "mouse_left_handed",
            "mouse_middle_button_emulation", "mouse_natural_scrolling", "mouse_scroll_button",
            "mouse_scroll_method", "mouse_send_events_mode",
        ]),
        Group(name: "Trackpad and touch", reason: "trackpad settings are macOS settings", keys: [
            "trackpad_accel_profile", "trackpad_accel_speed", "trackpad_click_method",
            "trackpad_disable_while_typing", "trackpad_left_handed", "trackpad_middle_button_emulation",
            "trackpad_natural_scrolling", "trackpad_scroll_button", "trackpad_scroll_factor",
            "trackpad_scroll_method", "trackpad_send_events_mode", "disable_trackpad",
            "tap_to_click", "tap_and_drag", "drag_lock", "touch_enable", "touch_enable_mouse_emulation",
        ]),
        Group(name: "Other input", reason: "libinput settings and Wayland's middle-click paste", keys: [
            "send_events_mode", "button_map", "axis_scroll_factor", "disable_middle_paste",
        ]),
        Group(name: "Cursor", reason: "macOS draws the cursor (System Settings, Accessibility, Display)", keys: [
            "cursor_size", "cursor_theme",
        ]),
        Group(name: "Idle", reason: "macOS handles sleep and the screen saver", keys: [
            "idle_inhibit_ignore_visible", "idle_inhibit_when_fullscreen",
        ]),
        Group(name: "Wayland protocols", reason: "protocols without a macOS counterpart", keys: [
            "allow_shortcuts_inhibit", "allow_lock_transparent",
        ]),
        Group(name: "Xwayland", reason: "there is no X11 on macOS", keys: [
            "xwayland_persistence", "xwayland_ignore_scale",
        ]),
    ]

    /// Keywords whose whole line is accepted and ignored.
    public static let ignoredKeywords: [String: String] = [
        "switchbind": "lid switch events are not available to apps on macOS",
        "monitor_rule": "display mode, scale, position and HDR are macOS display settings",
        "layer_rule": "macOS has no layer shell",
        "device_rule": "input devices are configured in macOS settings",
    ]

    /// Keywords the config parser handles itself (structure, not settings).
    public static let parserKeywords: Set<String> = [
        "key_mode", "var", "source", "source_optional", "env", "exec", "exec_once",
        "window_rule", "window_rule_once", "tag_rule", "mousebind", "axisbind", "gesturebind",
    ]

    // MARK: - Global options with a setter but no effect

    /// Options that are parsed and validated like in mango, but the engine never reads.
    public static let optionsWithoutEffect: [String: NoEffect] = {
        let closeAnim = NoEffect.impossible("the window is already gone when macOS reports it closed")
        let fade = NoEffect.impossible("another app's window opacity can only be changed with SIP off")
        let corners = NoEffect.impossible("macOS draws window corners; the border follows them")
        var t: [String: NoEffect] = [
            "animation_fade_in": fade, "animation_fade_out": fade,
            "fade_in_begin_opacity": fade, "fade_out_begin_opacity": fade,
            "focused_opacity": fade, "unfocused_opacity": fade,
            "animation_type_close": closeAnim, "animation_duration_close": closeAnim, "animation_curve_close": closeAnim,
            "float_full_to_top": .impossible("macOS has no layers for other apps' windows: the window focused last is on top"),
        ]
        t["animation_duration_focus"] = fade   // mango's focus animation fades the opacity
        t["animation_curve_focus"] = fade
        t["zoom_end_ratio"] = closeAnim         // the end of the zoom close animation
        return t
    }()

    // MARK: - Port extensions

    /// Options of the port that mango does not have: a config that uses them does not
    /// load in mango.
    public static let portExtensionOptions: [String: String] = {
        var t: [String: String] = [
        "chutney_hyper_modifier": "what HYPER means in a bind",
        "chutney_hyper_key": "the key held as HYPER, as Raycast's Hyper Key: caps_lock, a left_ or right_ control, shift, option or command, f1 … f12 (macOS's own key mapping)",
        "chutney_hyper_tap": "Caps Lock or a function key that is Hyper, pressed alone: none, original (the key itself) or escape",
        "chutney_menu_bar": "menu-bar item with the current tags and layout",
        "chutney_menu_bar_tag_style": "the menu bar's tags: square, circle (SF Symbols numbers) or text",
        "chutney_menu_config": "the file the menu's panel saves its settings in; the config reads it with source_optional, last",
        "chutney_menu_bar_logo": "the mango logo in the menu bar: color, mono (the menu bar's colour) or 0",
        "chutney_menu_bar_layout": "the layout's icon in the menu bar",
        "chutney_menu_bar_mode": "the key mode in the menu bar, the default one too (0: only another mode)",
        "chutney_style": "bars, switcher and jump labels in the macOS style where no decorate key is set",
        "chutney_border_unfocused": "draw borders around unfocused windows too",
        "chutney_hotkeys_max_rows": "the most rows the hotkeys palette shows (chutney_toggle_hotkeys_palette); its height follows them",
        "chutney_hotkeys_recent": "the rows used of late on the hotkeys palette's front page (0: none)",
        "chutney_hotkeys_width": "the hotkeys palette's width in points",
        "chutney_hotkeys_apps": "the installed apps (from Spotlight) in the hotkeys palette's search",
        "chutney_layout_palette_width": "the layout palette's width in points; its cells and icons follow",
        "chutney_layout_palette_keys": "the keys that move the layout palette's selection: left,down,up,right (or h,j,k,l); the arrows always work",
        "chutney_physical_pixels": "border_px and the gaps in the screen's pixels, not points (3 is 1.5 points on Retina)",
        "chutney_ignore_apps": "bundle ids that are never managed",
        "chutney_floating_color": "fixed border colour of floating windows, focused or not",
        "chutney_tab_bar_app_icons": "the app's icon before each tab's title",
        "chutney_tab_bar_shortcuts": "⌘1-9 picks a tab while a tab bar is shown",
        ]
        return t
    }()

    /// What the port's dispatchers do (README, --list-ignored).
    static let portDispatcherText: [String: String] = [
        "chutney_focus_app": "one key per app: start it, or go to its window",
        "chutney_restart": "quit, with hidden windows left hidden for the next mango (make install, mmsg service restart)",
        "chutney_set_proportion_all": "set_proportion for every window of the tag in view; without a value, scroller_default_proportion",
        "chutney_toggle_hotkeys_palette": "the hotkeys palette: search the bindings, move with the keys, Return runs one",
        "chutney_toggle_layout_palette": "the layout palette: circle_layout's layouts (or all 14) as icons, move with the keys, Return sets one",
    ]

    /// The port's own dispatchers, mango has none of them (`mango -p` and the README list
    /// them as port extensions).
    public static let portDispatchers: Set<String> = Set(portDispatcherText.keys)

    // MARK: - Window rules

    /// Window-rule fields accepted without reading the value.
    public static let ignoredWindowRuleFields: [String: String] = [
        "shield_when_capture": "screen-capture protocol; macOS decides what captures show",
        "allow_shortcuts_inhibit": "Wayland protocol without a macOS counterpart",
        "idle_inhibit_when_focus": "macOS handles sleep and the screen saver",
        "vrr_only_fullscreen": "variable refresh rate is a macOS display setting",
        "force_render": "the window server decides what is rendered",
        "activation_bypass": "xdg-activation; macOS apps activate themselves",
        "force_fake_maximize": "xdg maximize state; macOS has no such request",
        "force_tearing": "tearing is a display setting",
    ]

    /// Window-rule fields that are parsed and validated, but the engine never reads.
    public static let windowRuleFieldsWithoutEffect: [String: NoEffect] = [
        "no_shadow": .impossible("macOS draws window shadows"),
        "no_blur": .impossible("macOS draws other apps' windows"),
        "no_radius": .impossible("macOS draws window corners"),
        "focused_opacity": .impossible("another app's window opacity can only be changed with SIP off"),
        "unfocused_opacity": .impossible("another app's window opacity can only be changed with SIP off"),
        "no_fade_in": .impossible("another app's window opacity can only be changed with SIP off"),
        "no_fade_out": .impossible("another app's window opacity can only be changed with SIP off"),
        "animation_type_close": .impossible("the window is already gone when macOS reports it closed"),
        "allow_csd": .impossible("macOS apps always draw their own title bars"),
        "is_term": .impossible("macOS does not say which app started another, so nothing can swallow it"),
        "no_swallow": .impossible("macOS does not say which app started another, so nothing can swallow it"),
        "no_size_hint": .impossible("macOS apps keep their own minimum and maximum size"),
        "ignore_maximize": .impossible("macOS apps zoom their own windows; no maximize request reaches mango (the default, 1, is what happens)"),
        "force_tiled_state": .impossible("macOS has no tiled state to tell an app"),
    ]

    // MARK: - Dispatchers

    /// mango dispatchers the port accepts in a bind but that do nothing.
    public static let unsupportedDispatchers: [String: String] = [
        "create_virtual_output": "virtual outputs are a wlroots feature",
        "destroy_all_virtual_output": "virtual outputs are a wlroots feature",
        "disable_monitor": "displays are managed by macOS",
        "enable_monitor": "displays are managed by macOS",
        "toggle_monitor": "displays are managed by macOS",
        "sleep_monitor": "displays are managed by macOS",
        "wakeup_monitor": "displays are managed by macOS",
        "sleep_toggle_monitor": "displays are managed by macOS",
        "togglehdr": "HDR is a macOS display setting",
        "switch_keyboard_layout": "keyboard layouts are switched by macOS's input menu and its own shortcut (not built: chosen)",
        "toggle_trackpad_enable": "macOS has no API to switch the trackpad off",
        "chvt": "macOS has no virtual terminals",
    ]

    /// The dispatchers above that macOS would allow; the others it does not.
    public static let dispatchersNotYet: Set<String> = []

    // MARK: - How much of mango works

    /// mango's window-rule fields and keywords (`Tests/mango-keys`; a test keeps them in step).
    public static let mangoWindowRuleFieldCount = 49
    public static let mangoKeywordCount = 18

    public struct Tally: Equatable, Sendable {
        public var works = 0, notYet = 0, impossible = 0
        public var total: Int { works + notYet + impossible }
    }

    /// mango's global options: every name the port has a setter for or accepts, without
    /// the port's own.
    public static var optionTally: Tally {
        var t = Tally()
        for g in ignoredOptionGroups { if g.notYet { t.notYet += g.keys.count } else { t.impossible += g.keys.count } }
        for n in optionsWithoutEffect.values {
            if case .notImplemented = n { t.notYet += 1 } else { t.impossible += 1 }
        }
        t.works = ConfigOptions.setterKeys.subtracting(portExtensionOptions.keys).subtracting(optionsWithoutEffect.keys).count
        return t
    }

    public static var windowRuleTally: Tally {
        var t = Tally()
        t.impossible = ignoredWindowRuleFields.count
        for n in windowRuleFieldsWithoutEffect.values {
            if case .notImplemented = n { t.notYet += 1 } else { t.impossible += 1 }
        }
        t.works = mangoWindowRuleFieldCount - t.notYet - t.impossible
        return t
    }

    public static var keywordTally: Tally {
        Tally(works: mangoKeywordCount - ignoredKeywords.count, notYet: 0, impossible: ignoredKeywords.count)
    }

    public static var dispatcherTally: Tally {
        var t = Tally()
        t.notYet = dispatchersNotYet.count
        t.impossible = unsupportedDispatchers.count - t.notYet
        t.works = Dispatch.knownNames.count - unsupportedDispatchers.count
        return t
    }

    // MARK: - Lookup

    public enum OptionStatus: Equatable {
        case implemented
        case noEffect(NoEffect)
        case ignored(String)
        case portExtension
        case keyword
        case unknown
    }

    private static let ignoredOptionReasons: [String: String] = {
        var t: [String: String] = [:]
        for g in ignoredOptionGroups { for k in g.keys { t[k] = g.reason } }
        return t
    }()

    /// Not in mango: the port's compatibility table.
    /// The reason a global option or keyword is ignored, or nil when it is not ignored.
    public static func ignoredReason(_ key: String) -> String? {
        ignoredOptionReasons[key] ?? ignoredKeywords[key]
    }

    /// Not in mango: the port's compatibility table.
    public static func status(ofOption key: String) -> OptionStatus {
        if portExtensionOptions[key] != nil { return .portExtension }
        if let n = optionsWithoutEffect[key] { return .noEffect(n) }
        if ConfigOptions.hasSetter(key) { return .implemented }
        if let r = ignoredReason(key) { return .ignored(r) }
        if parserKeywords.contains(key) || BindingParser.isKeyBindKeyword(key) { return .keyword }
        return .unknown
    }

    /// Not in mango: the port's compatibility table.
    /// Possible on macOS, not implemented yet (else, when it has no effect, macOS does not allow it).
    public static func isNotYet(option key: String) -> Bool {
        if case .notImplemented? = optionsWithoutEffect[key] { return true }
        return ignoredOptionGroups.contains { $0.notYet && $0.keys.contains(key) }
    }

    /// Not in mango: the port's compatibility table.
    public static func isNotYet(windowRuleField field: String) -> Bool {
        if case .notImplemented? = windowRuleFieldsWithoutEffect[field] { return true }
        return false
    }

    /// Not in mango: the port's compatibility table.
    /// For `mango -p` and `--list-ignored`: a short note on a window-rule field, or nil when
    /// the field is implemented (or unknown).
    public static func windowRuleNote(_ field: String) -> String? {
        if let r = ignoredWindowRuleFields[field] { return r }
        if let n = windowRuleFieldsWithoutEffect[field] { return n.text }
        return nil
    }

    // MARK: - Markdown (mango --list-ignored, README)

    /// How much of mango works, in one table (`mango --list-glance`, README's status).
    public static func glanceMarkdown() -> String {
        func row(_ cells: String...) -> String { "| " + cells.joined(separator: " | ") + " |" }
        var out: [String] = []
        out.append(row("", "In mango", "Works on macOS", "Not implemented yet", "Cannot work on macOS"))
        out.append(row("---", "---", "---", "---", "---"))
        for (name, t) in [("Options", optionTally), ("Keywords", keywordTally), ("Window-rule fields", windowRuleTally),
                          ("Dispatchers", dispatcherTally)] {
            out.append(row(name, "\(t.total)", "\(t.works)", "\(t.notYet)", "\(t.impossible)"))
        }
        out.append(row("Layouts", "\(LayoutKind.allCases.count)", "\(LayoutKind.allCases.count)", "0", "0"))
        return out.joined(separator: "\n") + "\n"
    }

    /// Every mango name that does nothing on macOS, and the port's own (`mango --list-ignored`).
    public static func markdown() -> String {
        func row(_ cells: String...) -> String { "| " + cells.joined(separator: " | ") + " |" }
        func codes<S: Sequence>(_ keys: S) -> String where S.Element == String {
            keys.sorted().map { "`\($0)`" }.joined(separator: ", ")
        }
        func isNotYet(_ n: NoEffect) -> Bool { if case .notImplemented = n { return true } else { return false } }
        var out: [String] = []

        out.append("### Not implemented yet")
        out.append("")
        var notYet: [String] = []
        for g in ignoredOptionGroups where g.notYet { notYet.append(row(g.name, codes(g.keys), g.reason)) }
        // A kind with nothing left to do gets no row.
        for (what, names, note) in [
            ("Other options", Array(optionsWithoutEffect.filter { isNotYet($0.value) }.keys), "not implemented yet"),
            ("Window-rule fields", Array(windowRuleFieldsWithoutEffect.filter { isNotYet($0.value) }.keys), "not implemented yet"),
            ("Dispatchers", Array(dispatchersNotYet), "not implemented yet"),
        ] where !names.isEmpty { notYet.append(row(what, codes(names), note)) }
        if notYet.isEmpty {
            out.append("Nothing: everything of mango that macOS allows is implemented.")
        } else {
            out.append("macOS would allow these; the port does not have them yet.")
            out.append("")
            out.append(row("What", "Names", "Note"))
            out.append(row("---", "---", "---"))
            out.append(contentsOf: notYet)
        }
        out.append("")

        out.append("### Cannot work on macOS")
        out.append("")
        out.append("macOS draws and manages other apps' windows, the keyboard, the pointer and the displays itself; a window manager cannot change these.")
        out.append("")
        out.append(row("What", "Names", "Why"))
        out.append(row("---", "---", "---"))
        for g in ignoredOptionGroups where !g.notYet { out.append(row(g.name, codes(g.keys), g.reason)) }
        for (k, r) in ignoredKeywords.sorted(by: { $0.key < $1.key }) { out.append(row("Keyword", "`\(k)=`", r)) }
        let impossibleOptions = Dictionary(grouping: optionsWithoutEffect.filter { !isNotYet($0.value) }.keys) { optionsWithoutEffect[$0]!.text }
        for (reason, keys) in impossibleOptions.sorted(by: { $0.key < $1.key }) { out.append(row("Options", codes(keys), reason)) }
        var fieldReasons: [String: [String]] = [:]
        for (f, r) in ignoredWindowRuleFields { fieldReasons[r, default: []].append(f) }
        for (f, n) in windowRuleFieldsWithoutEffect where !isNotYet(n) { fieldReasons[n.text, default: []].append(f) }
        for (reason, fields) in fieldReasons.sorted(by: { $0.key < $1.key }) { out.append(row("Window-rule fields", codes(fields), reason)) }
        let impossibleDispatchers = unsupportedDispatchers.filter { !dispatchersNotYet.contains($0.key) }
        let byDispatchReason = Dictionary(grouping: impossibleDispatchers.keys) { impossibleDispatchers[$0]! }
        for (reason, names) in byDispatchReason.sorted(by: { $0.key < $1.key }) { out.append(row("Dispatchers", codes(names), reason)) }
        out.append("")

        out.append("### Port extensions (not in mango)")
        out.append("")
        out.append("Unset, mango behaves as mango does. In mango itself each is an unknown keyword, reported and skipped.")
        out.append("")
        out.append(row("Name", "Does"))
        out.append(row("---", "---"))
        for (k, d) in portExtensionOptions.sorted(by: { $0.key < $1.key }) { out.append(row("`\(k)`", d)) }
        for k in portDispatchers.sorted() {
            out.append(row("`\(k)` (dispatcher)", portDispatcherText[k] ?? ""))
        }
        return out.joined(separator: "\n") + "\n"
    }
}

/// Not in mango: the port's answers to mango's config reader (ConfigPort): its own keys
/// (PortOptions) and dispatchers, what HYPER is on a Mac, and MangoCompat's notes for
/// `mango -p`. Set as `ConfigParser.port` before a config is read.
package struct MacConfigPort: ConfigPort {
    package init() {}

    /// Sets it as mango's config reader's port; the app and `mango -p` do so first thing.
    package static func install() { ConfigParser.port = MacConfigPort() }

    package func setter(_ key: String) -> ConfigOptions.Setter? { PortOptions.setters[key] }
    package var keys: Set<String> { Set(PortOptions.setters.keys) }
    package func isIgnored(_ key: String) -> Bool { MangoCompat.ignoredReason(key) != nil }

    package func optionNote(_ key: String, applied: Bool) -> (ConfigNote.Kind, String)? {
        guard applied else {
            return (MangoCompat.isNotYet(option: key) ? .notYet : .noEffect,
                    MangoCompat.ignoredReason(key) ?? "no macOS counterpart")
        }
        switch MangoCompat.status(ofOption: key) {
        case .noEffect(.notImplemented): return (.notYet, "")
        case .noEffect(let n): return (.noEffect, n.text)
        case .portExtension: return (.portExtension, "option of the macOS port, not in mango")
        default: return nil
        }
    }

    package func windowRuleNote(_ field: String) -> (ConfigNote.Kind, String)? {
        guard let n = MangoCompat.windowRuleNote(field) else { return nil }
        return MangoCompat.isNotYet(windowRuleField: field) ? (.notYet, "") : (.noEffect, n)
    }

    package func knowsWindowRuleField(_ field: String) -> Bool { MangoCompat.ignoredWindowRuleFields[field] != nil }

    package func dispatcherNote(_ name: String) -> (ConfigNote.Kind, String)? {
        if let why = MangoCompat.unsupportedDispatchers[name] {
            return (MangoCompat.dispatchersNotYet.contains(name) ? .notYet : .unsupportedDispatcher, why)
        }
        if MangoCompat.portDispatchers.contains(name) { return (.portExtension, "dispatcher of the macOS port, not in mango") }
        return nil
    }

    package func knowsDispatcher(_ name: String) -> Bool { MangoCompat.portDispatchers.contains(name) }

    package func hyperModifier(_ config: Config) -> String { config.chutneyHyperModifier }

    /// The macOS names of mango's modifiers, and the fn key.
    package func keyCodes(_ name: String) -> [UInt16] { KeySyms.parseKey(forName: name) }

    package func modifier(_ name: String) -> Modifiers? {
        switch name {
        case "cmd", "command", "logo", "meta": return .superKey
        case "control": return .ctrl
        case "option", "opt": return .alt
        case "fn", "function": return .fn
        default: return nil
        }
    }
}
