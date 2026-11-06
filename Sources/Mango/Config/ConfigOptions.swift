import Foundation

public enum OptionResult: Equatable {
    case applied
/// Not in mango: mango's options that do nothing on macOS (blur, shadows, libinput, ...).
    case ignored
    case unknown
    case invalid(String)
}

public enum ConfigOptions {
    public static func parseOption(key rawKey: String, value rawValue: String, to config: inout Config) -> OptionResult {
        let key = rawKey.trimmingCharacters(in: .whitespaces)
        let value = rawValue.trimmingCharacters(in: .whitespaces)

        if let setter = setters[key] ?? ConfigParser.port?.setter(key) { return setter(&config, value) }   // the port's keys: not in mango

        switch key {
        case "env":
            guard let comma = value.firstIndex(of: ",") else {
                return .invalid("Invalid bind format: \(mangoHighlight(value))")
            }
            let name = value[..<comma].trimmingCharacters(in: .whitespaces)
            var v = value[value.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value[value.index(after: comma)...].isEmpty else {
                return .invalid("Invalid bind format: \(mangoHighlight(value))")
            }
            if v.contains("~/") {
                v = v.replacingOccurrences(of: "~/", with: homeDirectory() + "/")
            }
            config.envVars.append((name, v))
            return .applied
        case "exec":
            config.exec.append(value)
            return .applied
        case "exec_once":
            config.execOnce.append(value)
            return .applied
        case "window_rule", "window_rule_once":
            switch RuleParser.parseWindowRule(value, once: key == "window_rule_once") {
            case .success(let rule): config.windowRules.append(rule); return .applied
            case .failure(let msg): return .invalid(msg)
            }
        case "tag_rule":
            switch RuleParser.parseTagRule(value) {
            case .success(let rule): config.tagRules.append(rule); return .applied
            case .failure(let msg): return .invalid(msg)
            }
        case "mousebind":
            switch BindingParser.parseMouseBinding(value: value, mode: config.keymode, hyperModifier: config.hyperModifier) {
            case .success(let b): config.mouseBindings.append(b); return .applied
            case .failure(let msg): return .invalid(msg)
            }
        case "axisbind":
            switch BindingParser.parseAxisBinding(value: value, mode: config.keymode, hyperModifier: config.hyperModifier) {
            case .success(let b): config.axisBindings.append(b); return .applied
            case .failure(let msg): return .invalid(msg)
            }
        case "gesturebind":
            switch BindingParser.parseGestureBinding(value: value, mode: config.keymode, hyperModifier: config.hyperModifier) {
            case .success(let b): config.gestureBindings.append(b); return .applied
            case .failure(let msg): return .invalid(msg)
            }
        case "key_mode":
            config.keymode = value.isEmpty ? "default" : value
            return .applied
        case "switchbind", "layer_rule", "monitor_rule", "device_rule":
            return .ignored
        default:
            break
        }

        if BindingParser.isKeyBindKeyword(key) {
            switch BindingParser.parseKeyBinding(keyword: key, value: value, mode: config.keymode,
                                                 hyperModifier: config.hyperModifier) {
            case .success(let b):
                if !b.keyCodes.isEmpty { config.keyBindings.append(b) }
                return .applied
            case .failure(let msg): return .invalid(msg)
            }
        }

        if isIgnored(key) { return .ignored }
        return .unknown
    }

    public static var knownKeys: [String] { setters.keys.sorted() }

    public static func isIgnored(_ key: String) -> Bool {
        ConfigParser.port?.isIgnored(key) ?? false   // the port's: not in mango
    }

    /// Not in mango: asks whether apply stores a key.
    public static func hasSetter(_ key: String) -> Bool { setters[key] != nil || ConfigParser.port?.setter(key) != nil }
    public static var setterKeys: Set<String> { Set(setters.keys).union(ConfigParser.port?.keys ?? []) }

    package typealias Setter = (inout Config, String) -> OptionResult

    static var setters: [String: Setter] { mangoSetters }

    package static let mangoSetters: [String: Setter] = {
        var t: [String: Setter] = [:]

        t["xkb_rules_options"] = { config, value in config.xkbRulesOptions = value; return .applied }

        t["animations"] = bool(\.animations)
        t["animation_type_open"] = animation(\.animationTypeOpen)
        t["animation_type_close"] = animation(\.animationTypeClose)
        t["animation_fade_in"] = bool(\.animationFadeIn)
        t["animation_fade_out"] = bool(\.animationFadeOut)
        t["tag_animation_direction"] = int(\.tagAnimationDirection, 0...1)
        t["zoom_initial_ratio"] = double(\.zoomInitialRatio)
        t["zoom_end_ratio"] = double(\.zoomEndRatio)
        t["fade_in_begin_opacity"] = double(\.fadeinBeginOpacity)
        t["fade_out_begin_opacity"] = double(\.fadeoutBeginOpacity)
        t["animation_duration_move"] = int(\.animationDurationMove)
        t["animation_duration_open"] = int(\.animationDurationOpen)
        t["animation_duration_tag"] = int(\.animationDurationTag)
        t["animation_duration_close"] = int(\.animationDurationClose)
        t["animation_duration_focus"] = int(\.animationDurationFocus)
        t["animation_curve_move"] = curve(\.animationCurveMove, "animation_curve_move")
        t["animation_curve_open"] = curve(\.animationCurveOpen, "animation_curve_open")
        t["animation_curve_tag"] = curve(\.animationCurveTag, "animation_curve_tag")
        t["animation_curve_close"] = curve(\.animationCurveClose, "animation_curve_close")
        t["animation_curve_focus"] = curve(\.animationCurveFocus, "animation_curve_focus")

        t["scroller_structs"] = int(\.scrollerStructs)
        t["scroller_default_proportion"] = double(\.scrollerDefaultProportion)
        t["scroller_default_proportion_single"] = double(\.scrollerDefaultProportionSingle)
        t["scroller_ignore_proportion_single"] = bool(\.scrollerIgnoreProportionSingle)
        t["scroller_focus_center"] = bool(\.scrollerFocusCenter)
        t["scroller_prefer_center"] = bool(\.scrollerPreferCenter)
        t["scroller_prefer_overspread"] = bool(\.scrollerPreferOverspread)
        t["edge_scroller_pointer_focus"] = bool(\.edgeScrollerPointerFocus)
        t["edge_scroller_focus_allow_speed"] = double(\.edgeScrollerFocusAllowSpeed)
        t["scroller_proportion_preset"] = { config, value in
            let floatCount = value.filter { $0 == "," }.count + 1
            var out: [Double] = []
            for token in value.split(separator: ",").map(String.init) where out.count < floatCount {
                guard let d = ValueParse.scanDouble(token) else {
                    return .invalid("Invalid float value in scroller_proportion_preset: \(mangoHighlight(token))")
                }
                out.append(min(max(d, 0.1), 1.0))
            }
            if out.count != floatCount {
                return .invalid("Invalid scroller_proportion_preset format: \(mangoHighlight(value))")
            }
            config.scrollerProportionPreset = out
            return .applied
        }

        t["new_is_master"] = bool(\.newIsMaster)
        t["default_master_factor"] = double(\.defaultMfact)
        t["default_master_count"] = int(\.defaultNmaster)
        t["center_master_overspread"] = bool(\.centerMasterOverspread)
        t["center_when_single_stack"] = bool(\.centerWhenSingleStack)
        t["tag_num"] = int(\.tagNum)
        t["tag_gather"] = bool(\.tagGather)
        t["tag_carousel"] = bool(\.tagCarousel)
        t["view_current_to_back"] = bool(\.viewCurrentToBack)
        t["circle_layout"] = { config, value in
            config.circleLayout = value.split(separator: ",").map { tok in
                String(tok).trimmingCharacters(in: CharacterSet(charactersIn: " ").inverted.intersection(.controlCharacters))
            }.filter { !$0.isEmpty }
            return .applied
        }
        t["dwindle_vertical_split"] = int(\.dwindleVsplit)
        t["dwindle_horizontal_split"] = int(\.dwindleHsplit)
        t["dwindle_preserve_split"] = bool(\.dwindlePreserveSplit)
        t["dwindle_smart_split"] = bool(\.dwindleSmartSplit)
        t["dwindle_smart_resize"] = bool(\.dwindleSmartResize)
        t["dwindle_manual_split"] = bool(\.dwindleManualSplit)
        t["dwindle_drop_simple_split"] = bool(\.dwindleDropSimpleSplit)
        t["dwindle_split_ratio"] = double(\.dwindleSplitRatio)
        t["monocle_tab_mode"] = bool(\.monocleTabMode)
        t["monocle_no_border"] = bool(\.monocleNoBorder)
        t["monocle_no_gap"] = bool(\.monocleNoGap)
        t["monocle_no_radius"] = bool(\.monocleNoRadius)
        t["special_tag_cross_monitor"] = bool(\.specialTagCrossMonitor)
        t["deck_tab_mode"] = bool(\.deckTabMode)
        t["tab_bar_height"] = int(\.tabBarHeight, 0...500)
        t["group_bar_height"] = int(\.groupBarHeight, 0...500)
        t["always_show_group_bar"] = bool(\.alwaysShowGroupBar)
        t["group_bar_close_button_enable"] = bool(\.groupBarCloseButtonEnable)
        t["group_bar_button_size"] = int(\.groupBarButtonSize, 4...64)
        t["group_bar_button_margin"] = int(\.groupBarButtonMargin, 0...50)
        t["group_bar_button_color"] = color(\.groupBarButtonColor, "group_bar_button_color")
        t["monocle_right_button_close"] = bool(\.monocleRightButtonClose)
        t["title_message_bar_height"] = int(\.titleMessageBarHeight, 0...500)
        t["title_message_bar_gap"] = int(\.titleMessageBarGap, 0...500)
        decorate(&t, "title_message_bar", \.titleMessageBardata)
        decorate(&t, "tab_bar", \.tabbardata)
        decorate(&t, "group_bar", \.groupbardata)
        decorate(&t, "jump_label", \.jumplabeldata)

        t["gap_inner_horizontal"] = int(\.gappih)
        t["gap_inner_vertical"] = int(\.gappiv)
        t["gap_outer_horizontal"] = int(\.gappoh)
        t["gap_outer_vertical"] = int(\.gappov)
        t["smart_gaps"] = bool(\.smartgaps)
        t["border_px"] = int(\.borderpx)
        t["border_radius"] = int(\.borderRadius)
        t["no_border_when_single"] = bool(\.noBorderWhenSingle)
        t["no_radius_when_single"] = bool(\.noRadiusWhenSingle)
        t["focused_opacity"] = double(\.focusedOpacity)
        t["unfocused_opacity"] = double(\.unfocusedOpacity)
        t["root_color"] = color(\.rootcolor, "rootcolor")
        t["border_color"] = color(\.bordercolor, "bordercolor")
        t["focus_color"] = color(\.focuscolor, "focuscolor")
        t["urgent_color"] = color(\.urgentcolor, "urgentcolor")
        t["maximized_screen_color"] = color(\.maximizescreencolor, "maximizescreencolor")
        t["scratchpad_color"] = color(\.scratchpadcolor, "scratchpadcolor")
        t["global_color"] = color(\.globalcolor, "globalcolor")
        t["overlay_color"] = color(\.overlaycolor, "overlaycolor")
        t["drop_color"] = color(\.dropcolor, "dropcolor")
        t["split_color"] = color(\.splitcolor, "splitcolor")
        t["scratchpad_width_ratio"] = double(\.scratchpadWidthRatio, 0.1...1)
        t["scratchpad_height_ratio"] = double(\.scratchpadHeightRatio, 0.1...1)
        t["special_dim"] = double(\.specialDim, 0...1)
        t["special_gap_inner_horizontal"] = int(\.specialGappih, 0...1000)
        t["special_gap_inner_vertical"] = int(\.specialGappiv, 0...1000)
        t["special_gap_outer_horizontal"] = int(\.specialGappoh, 0...1000)
        t["special_gap_outer_vertical"] = int(\.specialGappov, 0...1000)

        t["hotarea_size"] = int(\.hotareaSize, 1...1000)
        t["hotarea_corner"] = int(\.hotareaCorner)
        t["enable_hotarea"] = bool(\.enableHotarea)
        t["hotarea_disable_on_fullscreen"] = bool(\.hotareaDisableOnFullscreen)
        t["overview_gap_inner"] = int(\.overviewgappi, 0...1000)
        t["overview_gap_outer"] = int(\.overviewgappo, 0...1000)
        t["overcircle_center_ratio"] = double(\.overcircleCenterRatio, 0.1...0.9)
        t["jump_labels"] = { config, value in
            config.jumpLabels = value
            return .applied
        }

        t["focus_on_activate"] = bool(\.focusOnActivate)
        t["sloppy_focus"] = bool(\.sloppyfocus)
        t["warp_cursor"] = bool(\.warpcursor)
        t["focus_cross_monitor"] = bool(\.focusCrossMonitor)
        t["focus_direction_only_zone_overlap"] = bool(\.focusdirOnlyZoneOverlap)
        t["focus_cross_tag"] = bool(\.focusCrossTag)
        t["exchange_cross_monitor"] = bool(\.exchangeCrossMonitor)
        t["scratchpad_cross_monitor"] = bool(\.scratchpadCrossMonitor)
        t["single_scratchpad"] = bool(\.singleScratchpad)
        t["cursor_hide_timeout"] = int(\.cursorHideTimeout, 0...36000)
        t["cursor_hide_on_keypress"] = bool(\.cursorHideOnKeypress)
        t["drag_corner"] = int(\.dragCorner, 0...4)
        t["drag_warp_cursor"] = bool(\.dragWarpCursor)
        t["enable_border_resize"] = bool(\.enableBorderResize)
        t["border_resize_size"] = int(\.borderResizeSize, 0...50)
        t["enable_floating_snap"] = bool(\.enableFloatingSnap)
        t["snap_distance"] = int(\.snapDistance, 0...99999)
        t["float_full_to_top"] = bool(\.floatFullToTop)
        t["drag_tile_to_tile"] = bool(\.dragTileToTile)
        t["drag_tile_small"] = bool(\.dragTileSmall)
        t["axis_bind_apply_timeout"] = int(\.axisBindApplyTimeout, 0...1000)
        t["auto_reload_config"] = bool(\.autoReloadConfig)
        t["swipe_min_threshold"] = int(\.swipeMinThreshold, 1...1000)
        t["gesture_live"] = bool(\.gestureLive)
        t["gesture_swipe_distance"] = int(\.gestureSwipeDistance, 32...4096)
        t["gesture_swipe_cancel_ratio"] = double(\.gestureSwipeCancelRatio, 0.05...0.95)
        t["gesture_swipe_min_speed_to_force"] = double(\.gestureSwipeMinSpeedToForce, 0...Double.greatestFiniteMagnitude)

        return t
    }()

/// Not in mango: parse_option's strcmp chain is a table here; these make its entries.
    package static func bool(_ kp: WritableKeyPath<Config, Bool>) -> Setter {
        { config, value in
            guard let b = ValueParse.bool(value) else { return .invalid("Invalid boolean value: \(value)") }
            config[keyPath: kp] = b
            return .applied
        }
    }

    package static func int(_ kp: WritableKeyPath<Config, Int>, _ range: ClosedRange<Int>? = nil) -> Setter {
        { config, value in
            guard let n = ValueParse.int(value) else { return .invalid("Invalid integer value: \(value)") }
            config[keyPath: kp] = range.map { min(max(n, $0.lowerBound), $0.upperBound) } ?? n
            return .applied
        }
    }

    package static func double(_ kp: WritableKeyPath<Config, Double>, _ range: ClosedRange<Double>? = nil) -> Setter {
        { config, value in
            guard let d = ValueParse.double(value) else { return .invalid("Invalid number: \(value)") }
            config[keyPath: kp] = range.map { min(max(d, $0.lowerBound), $0.upperBound) } ?? d
            return .applied
        }
    }

    static func color(_ kp: WritableKeyPath<Config, RGBA>, _ name: String) -> Setter {
        { config, value in
            guard let c = parseColor(value) else { return .invalid("Invalid \(name) format: \(mangoHighlight(value))") }
            config[keyPath: kp] = c
            return .applied
        }
    }

    static func decorate(_ t: inout [String: Setter], _ prefix: String, _ kp: WritableKeyPath<Config, DecorateStyle>) {
        let k = prefix + "_decorate_"
        t[k + "font_desc"] = { config, value in
            config[keyPath: kp].fontDesc = value
            return .applied
        }
        t[k + "fg_color"] = optionalColor(kp.appending(path: \.fgColor), k + "fg_color")
        t[k + "bg_color"] = optionalColor(kp.appending(path: \.bgColor), k + "bg_color")
        t[k + "focus_fg_color"] = optionalColor(kp.appending(path: \.focusFgColor), k + "focus_fg_color")
        t[k + "focus_bg_color"] = optionalColor(kp.appending(path: \.focusBgColor), k + "focus_bg_color")
        t[k + "border_color"] = optionalColor(kp.appending(path: \.borderColor), k + "border_color")
        t[k + "border_width"] = optionalInt(kp.appending(path: \.borderWidth), 0...100)
        t[k + "corner_radius"] = optionalInt(kp.appending(path: \.cornerRadius), 0...100)
        t[k + "padding_x"] = optionalInt(kp.appending(path: \.paddingX), 0...100)
        t[k + "padding_y"] = optionalInt(kp.appending(path: \.paddingY), 0...100)
    }

    static func optionalColor(_ kp: WritableKeyPath<Config, RGBA?>, _ name: String) -> Setter {
        { config, value in
            guard let c = parseColor(value) else { return .invalid("Invalid \(name) format: \(mangoHighlight(value))") }
            config[keyPath: kp] = c
            return .applied
        }
    }

    static func optionalInt(_ kp: WritableKeyPath<Config, Int?>, _ range: ClosedRange<Int>) -> Setter {
        { config, value in
            guard let n = ValueParse.int(value) else { return .invalid("Invalid integer value: \(value)") }
            config[keyPath: kp] = min(max(n, range.lowerBound), range.upperBound)
            return .applied
        }
    }

    static func curve(_ kp: WritableKeyPath<Config, BezierCurve>, _ name: String) -> Setter {
        { config, value in
            guard let v = parseDoubleArray(value, 4), v.count == 4 else {
                return .invalid("Failed to parse \(name): \(mangoHighlight(value))")
            }
            config[keyPath: kp] = BezierCurve(x1: v[0], y1: v[1], x2: v[2], y2: v[3])
            return .applied
        }
    }

    private static func animation(_ kp: WritableKeyPath<Config, AnimationType>) -> Setter {
        { config, value in
            config[keyPath: kp] = animationTypeFromString(value)
            return .applied
        }
    }

    /// Not in mango: HOME lookup with a macOS fallback.
    static func homeDirectory() -> String {
        if let h = ProcessInfo.processInfo.environment["HOME"], !h.isEmpty { return h }
        return NSHomeDirectory()
    }
}

package enum ValueParse {
    static func int(_ s: String) -> Int? { atoi(s) }

    static func atoi(_ s: String) -> Int {
        var it = s.unicodeScalars.drop { " \t\n\r\u{0B}\u{0C}".unicodeScalars.contains($0) }
        var negative = false
        if let f = it.first, f == "+" || f == "-" { negative = f == "-"; it = it.dropFirst() }
        var n = 0
        for u in it {
            guard let d = Int(String(u)), ("0"..."9").contains(Character(u)) else { break }
            let (m, o1) = n.multipliedReportingOverflow(by: 10)
            let (r, o2) = m.addingReportingOverflow(d)
            if o1 || o2 { n = Int(Int32.max); break }
            n = r
        }
        return negative ? -n : n
    }

    static func double(_ s: String) -> Double? { atof(s) }

    static func atof(_ s: String) -> Double {
        let t = String(s.unicodeScalars.drop { " \t\n\r\u{0B}\u{0C}".unicodeScalars.contains($0) })
        guard let r = t.range(of: #"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?"#, options: .regularExpression),
              let d = Double(t[r]), d.isFinite else { return 0 }
        return d
    }

    static func scanDouble(_ s: String) -> Double? {
        let t = String(s.unicodeScalars.drop { " \t\n\r\u{0B}\u{0C}".unicodeScalars.contains($0) })
        guard t.range(of: #"^[+-]?(\d+\.?\d*|\.\d+)"#, options: .regularExpression) != nil else { return nil }
        return atof(t)
    }

    static func bool(_ s: String) -> Bool? { atoi(s) != 0 }
}
