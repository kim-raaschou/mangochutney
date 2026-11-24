import Foundation

// not in mango: is_title_message_bar_decorate_key: the plain options are a table (ConfigOptions.setters)

extension ParserState {
    /// mango parse_option (option_defs.c)
    // not in mango: the plain options are a table (ConfigOptions.setters, docs/afvigelser.md §5), and each
    // rule and binding branch a function of its own (parseTagRule, parseKeyBinding, …), below
    mutating func parseOption(_ key: String, _ value: String, _ lineNumber: Int) -> Bool {
        if key == "key_mode" {
            config.keymode = String(decoding: value.utf8.prefix(27), as: UTF8.self)
        } else if let setter = ConfigOptions.setters[key] ?? ConfigParser.port?.setter(key) {   // the port's keys: not in mango
            if case .invalid(let message, let earlier) = setter(&config, value) {
                for m in earlier { configError(m) }
                configError(message)
                return false
            }
            if let (kind, n) = ConfigParser.port?.optionNote(key, applied: true) { note(kind, key, n) }   // not in mango: the port's side
        } else if key == "monitor_rule" {
            return parseMonitorRule(value)
        } else if key == "tag_rule" {
            return parseTagRule(value)
        } else if key == "layer_rule" {
            return parseLayerRule(value)
        } else if key == "window_rule" || key == "window_rule_once" {
            return parseWindowRule(key, value)
        } else if key == "device_rule" {
            return parseDeviceRule(value)
        } else if key.hasPrefix("env") {
            guard let comma = value.firstIndex(of: ","), comma != value.startIndex,
                  value.index(after: comma) != value.endIndex else {
                configError("Invalid bind format: \(mangoHighlight(value))")
                return false
            }
            let envType = ValueParse.trimWhitespace(value[..<comma])
            var envValue = ValueParse.trimWhitespace(value[value.index(after: comma)...])

            let needle = "~/"

            if envValue.contains(needle) {
                guard let home = ConfigOptions.homeDirectory() else {
                    configError("HOME environment variable not set.")
                    return false
                }
                envValue = envValue.replacingOccurrences(of: needle, with: home + "/")
            }

            config.envVars.append((envType, envValue))

        } else if key == "var" {
            guard let comma = value.firstIndex(of: ",") else {
                configError("Invalid variable format (expected \u{1B}[1mname,value\u{1B}[0m): \(mangoHighlight(value))")
                return false
            }
            let name = ValueParse.trimWhitespace(value[..<comma])
            let varValue = ValueParse.trimWhitespace(value[value.index(after: comma)...])

            if !Self.isValidVarName(name) {
                configError("Invalid variable name (allowed: [A-Za-z_][A-Za-z0-9_]*): \(mangoHighlight(name))")
                return false
            }
            setConfigVar(name, varValue)

        } else if key == "exec" {
            config.exec.append(value)

        } else if key.hasPrefix("exec_once") {
            config.execOnce.append(value)

        } else if BindingParser.isKeyBindKeyword(key) {
            return parseKeyBinding(key, value, lineNumber)
        } else if key.hasPrefix("mousebind") {
            return parseMouseBinding(value, lineNumber)
        } else if key.hasPrefix("axisbind") {
            return parseAxisBinding(value, lineNumber)
        } else if key.hasPrefix("switchbind") {
            return parseSwitchBinding(key, value, lineNumber)
        } else if key.hasPrefix("gesturebind") {
            return parseGestureBinding(value, lineNumber)
        } else if key.hasPrefix("source_optional") {
            parseConfigFile(value, false)
        } else if key.hasPrefix("source") {
            parseConfigFile(value, true)
        } else if ConfigParser.port?.isIgnored(key) ?? false {
            // not in mango: mango's plain options that do nothing on macOS (blur, shadows, libinput, ...), the port's list
            if let (kind, n) = ConfigParser.port?.optionNote(key, applied: false) { note(kind, key, n) }
        } else {
            configError("Unknown keyword: \(mangoHighlight(key))")
            return false
        }

        return true
    }

    // not in mango: the tokens strtok(value, ",") gives, each split at its first colon and trimmed;
    // nil for a token without one
    static func ruleTokens(_ value: String) -> [(String, String)?] {
        value.split(separator: ",").map { tok in
            guard let colon = tok.firstIndex(of: ":") else { return nil }
            return (ValueParse.trimWhitespace(tok[..<colon]), ValueParse.trimWhitespace(tok[tok.index(after: colon)...]))
        }
    }

    // not in mango: parse_option's monitor_rule branch, apart; the rule is checked and not kept, as
    // monitor_rule has no macOS part (MangoCompat)
    private mutating func parseMonitorRule(_ value: String) -> Bool {
        defer { if let (kind, n) = ConfigParser.port?.optionNote("monitor_rule", applied: false) { note(kind, "monitor_rule", n) } }   // not in mango: the port's side
        var name: String?, make: String?, model: String?, serial: String?
        var x = Int32.max, y = Int32.max
        var width = -1, height = -1
        var refresh: Float = 0.0
        var custom = 0

        var parseError = false
        for token in Self.ruleTokens(value) {
            guard let (key, val) = token else { continue }
            if key == "name" {
                name = val
            } else if key == "make" {
                make = val
            } else if key == "model" {
                model = val
            } else if key == "serial" {
                serial = val
            } else if key == "rr" || key == "scale" || key == "vrr" || key == "hdr" || key == "hdr_min_lum"
                        || key == "hdr_max_lum" || key == "hdr_max_avg_lum" || key == "hdr_force" || key == "icc"
                        || key == "disable" || key == "primary" {
                // not in mango: the values nothing on macOS reads
            } else if key == "x" {
                x = Int32(truncatingIfNeeded: ValueParse.atoi(val))
            } else if key == "y" {
                y = Int32(truncatingIfNeeded: ValueParse.atoi(val))
            } else if key == "width" {
                width = min(max(ValueParse.atoi(val), 1), Int(Int32.max))
            } else if key == "height" {
                height = min(max(ValueParse.atoi(val), 1), Int(Int32.max))
            } else if key == "refresh" {
                refresh = min(max(Float(ValueParse.atof(val, keepingInf: true)), 0.001), 1000.0)
            } else if key == "custom" {
                custom = min(max(ValueParse.atoi(val), 0), 1)
            } else {
                configError("Unknown monitor rule option:\(mangoHighlight(key))")
                parseError = true
            }
        }

        if name == nil && make == nil && model == nil && serial == nil {
            configError("Monitor rule must have at least one of the following options: name, make, model, serial")
            return false
        }

        let hasWidth = width > 0
        let hasHeight = height > 0
        let hasRefresh = refresh > 0.0
        if hasWidth != hasHeight || hasWidth != hasRefresh {
            configError("Monitor rule must set width, height and refresh together")
            return false
        }

        if custom != 0 && !hasWidth {
            configError("Monitor rule with custom must set width, height and refresh")
            return false
        }

        if (x == Int32.max) != (y == Int32.max) {
            configError("Monitor rule must set x and y together")
            return false
        }

        return !parseError
    }

    // not in mango: parse_option's tag_rule branch, apart
    private mutating func parseTagRule(_ value: String) -> Bool {
        var rule = ConfigTagRule()

        // Sets default values.
        rule.id = 0

        var parseError = false
        for token in Self.ruleTokens(value) {
            guard let (key, val) = token else { continue }

            if key == "id" {
                if val == "*" {
                    rule.id = nil
                } else {
                    rule.id = min(max(ValueParse.atoi(val), 0), Int(tag_num_MAX))
                }
            } else if key == "layout_name" {
                rule.layoutName = val
            } else if key == "monitor_name" {
                rule.monitorName = val
            } else if key == "monitor_make" {
                rule.monitorMake = val
            } else if key == "monitor_model" {
                rule.monitorModel = val
            } else if key == "monitor_serial" {
                rule.monitorSerial = val
            } else if key == "no_render_border" {
                rule.noRenderBorder = ValueParse.atoi(val) > 0
            } else if key == "open_as_floating" {
                rule.openAsFloating = ValueParse.atoi(val) > 0
            } else if key == "no_hide" {
                rule.noHide = ValueParse.atoi(val) > 0
            } else if key == "master_count" {
                rule.nmaster = min(max(ValueParse.atoi(val), 1), 99)
            } else if key == "master_factor" {
                rule.mfact = min(max(ValueParse.atof(val, keepingInf: true), 0.1), 0.9)
            } else if key == "scroller_default_proportion" {
                rule.scrollerDefaultProportion = min(max(ValueParse.atof(val, keepingInf: true), 0.0), 1.0)
            } else if key == "scroller_default_proportion_single" {
                rule.scrollerDefaultProportionSingle = min(max(ValueParse.atof(val, keepingInf: true), 0.0), 1.0)
            } else if key == "scroller_ignore_proportion_single" {
                rule.scrollerIgnoreProportionSingle = ValueParse.atoi(val) > 0
            } else {
                configError("Unknown tag rule option:\(mangoHighlight(key))")
                parseError = true
            }
        }

        config.tagRules.append(rule)
        return !parseError
    }

    // not in mango: parse_option's layer_rule branch, apart; the rule is checked and not kept, as
    // macOS has no layer shell (MangoCompat)
    private mutating func parseLayerRule(_ value: String) -> Bool {
        defer { if let (kind, n) = ConfigParser.port?.optionNote("layer_rule", applied: false) { note(kind, "layer_rule", n) } }   // not in mango: the port's side
        var parseError = false
        for token in Self.ruleTokens(value) {
            guard let (key, _) = token else { continue }

            if key == "layer_name" || key == "animation_type_open" || key == "animation_type_close"
                || key == "shield_when_capture" || key == "no_blur" || key == "no_animation" || key == "no_shadow" {
                // not in mango: the values nothing on macOS reads
            } else {
                configError("Unknown layer rule option:\(mangoHighlight(key))")
                parseError = true
            }
        }

        return !parseError
    }

    // not in mango: parse_option's window_rule branch, apart
    private mutating func parseWindowRule(_ key: String, _ value: String) -> Bool {
        var rule = ConfigWinRule()

        if key == "window_rule_once" {
            rule.isOnce = true
            rule.isOnceApplied = false
        } else {
            rule.isOnce = false
            rule.isOnceApplied = false
        }

        // not in mango: nil for a negative value, mango's unset -1
        func flag(_ val: String) -> Bool? {
            let n = ValueParse.atoi(val)
            return n >= 0 ? n != 0 : nil
        }

        var parseError = false
        for token in Self.ruleTokens(value) {
            guard let (key, val) = token else { continue }

            if key == "is_floating" {
                rule.isfloating = flag(val)
            } else if key == "title" {
                rule.title = val
            } else if key == "app_id" {
                rule.id = val
            } else if key == "animation_type_open" {
                rule.animationTypeOpen = ValueParse.animationTypeFromString(val)
            } else if key == "animation_type_close" {
                rule.animationTypeClose = ValueParse.animationTypeFromString(val)
            } else if key == "tags" {
                let m = ValueParse.parseTagMask(val)
                rule.tags = m == 0 ? nil : m
            } else if key == "monitor" {
                rule.monitor = val
            } else if key == "offset_x" {
                rule.offsetx = ValueParse.atoi(val)
            } else if key == "offset_y" {
                rule.offsety = ValueParse.atoi(val)
            } else if key == "no_focus" {
                rule.noFocus = flag(val)
            } else if key == "no_fade_in" {
                rule.noFadeIn = flag(val)
            } else if key == "no_fade_out" {
                rule.noFadeOut = flag(val)
            } else if key == "no_force_center" {
                rule.noForceCenter = flag(val)
            } else if key == "width" {
                rule.width = Float(ValueParse.atof(val))
            } else if key == "height" {
                rule.height = Float(ValueParse.atof(val))
            } else if key == "no_border" {
                rule.noBorder = flag(val)
            } else if key == "no_shadow" {
                rule.noShadow = flag(val)
            } else if key == "no_radius" {
                rule.noRadius = flag(val)
            } else if key == "no_animation" {
                rule.noAnimation = flag(val)
            } else if key == "is_open_silent" {
                rule.isopensilent = flag(val)
            } else if key == "is_tag_silent" {
                rule.istagsilent = flag(val)
            } else if key == "is_named_scratchpad" {
                rule.isnamedscratchpad = flag(val)
            } else if key == "is_unmanaged_global" {
                rule.isunglobal = flag(val)
            } else if key == "is_global" {
                rule.isglobal = flag(val)
            } else if key == "scroller_proportion_single" {
                rule.scrollerProportionSingle = Float(ValueParse.atof(val))
            } else if key == "unfocused_opacity" {
                rule.unfocusedOpacity = Float(ValueParse.atof(val))
            } else if key == "focused_opacity" {
                rule.focusedOpacity = Float(ValueParse.atof(val))
            } else if key == "is_overlay" {
                rule.isoverlay = flag(val)
            } else if key == "ignore_maximize" {
                rule.ignoreMaximize = flag(val)
            } else if key == "ignore_minimize" {
                rule.ignoreMinimize = flag(val)
            } else if key == "no_size_hint" {
                rule.noSizeHint = flag(val)
            } else if key == "is_term" {
                rule.isterm = flag(val)
            } else if key == "allow_csd" {
                rule.allowCsd = flag(val)
            } else if key == "force_tiled_state" {
                rule.forceTiledState = flag(val)
            } else if key == "no_swallow" {
                rule.noSwallow = flag(val)
            } else if key == "confine_pointer" {
                rule.confinePointer = flag(val)
            } else if key == "no_blur" {
                rule.noBlur = flag(val)
            } else if key == "scroller_proportion" {
                rule.scrollerProportion = Float(ValueParse.atof(val))
            } else if key == "is_fullscreen" {
                rule.isfullscreen = flag(val)
            } else if key == "is_fake_fullscreen" {
                rule.isfakefullscreen = flag(val)
            } else if key == "global_key_binding" {
                // sscanf(val, "%255[^-]-%255s")
                guard let dash = val.firstIndex(of: "-"), dash != val.startIndex,
                      let keyStart = val[val.index(after: dash)...].firstIndex(where: { !$0.isWhitespace }) else {
                    configError("Invalid globalkeybinding: \(mangoHighlight(val))")
                    return false
                }
                let modStr = ValueParse.trimWhitespace(val[..<dash])
                let keysymStr = String(val[keyStart...].prefix { !$0.isWhitespace })
                let mod = BindingParser.parseMod(modStr) { configError($0) }
                let keysymcode = BindingParser.parseKey(keysymStr, false) { configError($0) }
                if mod == nil {
                    return false
                }
                if keysymcode == nil {
                    return false
                }
                rule.globalkeybinding = val
            } else if ConfigParser.port?.knowsWindowRuleField(key) ?? false {
                // not in mango: the fields that do nothing on macOS, the port's list
            } else {
                configError("Unknown window rule option:\(mangoHighlight(key))")
                parseError = true
            }
        }
        config.windowRules.append(rule)
        for token in Self.ruleTokens(value) {
            guard let (field, _) = token else { continue }
            if let (kind, n) = ConfigParser.port?.windowRuleNote(field) { note(kind, "window_rule \(field)", n) }   // not in mango: the port's side
        }
        return !parseError
    }

    // not in mango: parse_option's device_rule branch, apart; the rule is checked and not kept, as
    // input devices are macOS's (MangoCompat)
    private mutating func parseDeviceRule(_ value: String) -> Bool {
        defer { if let (kind, n) = ConfigParser.port?.optionNote("device_rule", applied: false) { note(kind, "device_rule", n) } }   // not in mango: the port's side
        let known: Set<String> = [
            "name", "repeat_rate", "repeat_delay", "kb_rules", "kb_model", "kb_layout", "kb_variant", "kb_options",
            "natural_scrolling", "accel_profile", "accel_speed", "left_handed", "middle_button_emulation",
            "scroll_method", "scroll_button", "click_method", "send_events_mode", "tap_to_click", "tap_and_drag",
            "drag_lock", "button_map", "disable_while_typing", "monitor", "map_focus_monitor",
        ]

        var parseError = false
        for (token, raw) in zip(Self.ruleTokens(value), value.split(separator: ",")) {
            if let (key, val) = token {
                if key == "type" {
                    /* "touchpad" was the historical name of this device
                     * type; keep it as a deprecated alias so existing
                     * rules are not silently dropped. */
                    var resolved = val
                    if val == "touchpad" {
                        configError("device rule type \u{1B}[1;36mtouchpad\u{1B}[0m is deprecated, use "
                                        + "\u{1B}[1;36mtrackpad\u{1B}[0m instead", verbosity: .info)
                        resolved = "trackpad"
                    }
                    if !["keyboard", "pointer", "trackpad", "touch", "switch", "tablet", "pad"].contains(resolved) {
                        configError("Invalid device rule type: \(mangoHighlight(val)) (expected one of "
                                        + "keyboard, pointer, trackpad, touch, switch, tablet, pad)")
                        parseError = true
                    }
                } else if known.contains(key) {
                    // not in mango: the values nothing on macOS reads
                } else {
                    configError("Unknown device rule option: \(mangoHighlight(key))")
                    parseError = true
                }
            } else {
                configError("Invalid device rule format: \(mangoHighlight(String(raw)))")
                parseError = true
            }
        }
        return !parseError
    }
}

extension BindingParser {
    // not in mango: parse_option's regex_match("^bind[s|l|r|p|c]*$", key)
    public static func isKeyBindKeyword(_ keyword: String) -> Bool {
        guard keyword.hasPrefix("bind") else { return false }
        return keyword.dropFirst(4).allSatisfy { "s|lrpc".contains($0) }
    }

    // not in mango: sscanf's fields for "%255[^,],…,%255[^,],%255[^\n]" with `count` conversions: the
    // fields before the first empty one, the last the rest of the line; no 255-byte width (C's fixed buffers)
    static func sscanfFields(_ value: String, _ count: Int) -> [String] {
        var fields: [String] = []
        var rest = Substring(value)
        while fields.count < count - 1 {
            guard let comma = rest.firstIndex(of: ",") else { break }
            let field = rest[..<comma]
            if field.isEmpty { return fields }
            fields.append(String(field))
            rest = rest[rest.index(after: comma)...]
        }
        if !rest.isEmpty { fields.append(String(rest)) }
        return fields
    }
}

extension ParserState {
    // not in mango: parse_option's bind branch, apart; the binding keeps its fields, parse_func_name runs
    // when it runs (docs/afvigelser.md §5)
    private mutating func parseKeyBinding(_ key: String, _ value: String, _ lineNumber: Int) -> Bool {
        let fields = BindingParser.sscanfFields(value, 8)
        if fields.count < 3 {
            configError("Invalid bind format: \(mangoHighlight(value))")
            return false
        }
        let f = fields.map { ValueParse.trimWhitespace($0) }
        let (modStr, keysymStr, funcName) = (f[0], f[1], f[2])

        let mode = config.keymode

        let flags = BindingParser.parseBindFlags(key) { configError($0) }
        let keysymcode = BindingParser.parseKey(keysymStr, flags.contains(.keysym)) { configError($0) }
        let mod = BindingParser.parseMod(modStr) { configError($0) }
        let known = Dispatch.isKnown(funcName)   // parse_func_name's name
        guard known, let mod, let keysymcode else {
            if !known {
                configError("Unknown dispatch in bind: \(mangoHighlight(funcName))")
            }
            return false
        }
        // not in mango: an XF86 name with no macOS key code is dropped, and other names with none are an error;
        // mango keeps both by keysym (docs/afvigelser.md §3)
        if keysymcode.isEmpty {
            return true
        }
        let dispatch = Dispatch(name: funcName, args: Array(f[3...]))
        config.keyBindings.append(KeyBinding(mode: mode, mods: mod, keyName: keysymStr, keyCodes: keysymcode,
                                             flags: flags, dispatch: dispatch))
        keyLocs.append(BindingLocation(file: currentFile, line: lineNumber))
        noteDispatch(dispatch)
        return true
    }

    // not in mango: parse_option's mousebind branch, apart
    private mutating func parseMouseBinding(_ value: String, _ lineNumber: Int) -> Bool {
        let mode = BindingParser.setBindingKeymode(config)

        let fields = BindingParser.sscanfFields(value, 8)
        if fields.count < 3 {
            configError("Invalid mousebind format: \(mangoHighlight(value))")
            return false
        }
        let f = fields.map { ValueParse.trimWhitespace($0) }
        let (modStr, buttonStr, funcName) = (f[0], f[1], f[2])

        let mod = BindingParser.parseMod(modStr) { configError($0) }
        let button = BindingParser.parseButton(buttonStr) { configError($0) }

        let known = Dispatch.isKnown(funcName)   // parse_func_name's name
        guard known, let mod, let button else {
            if !known {
                configError("Unknown dispatch in mousebind: \(mangoHighlight(funcName))")
            }
            return false
        }
        let dispatch = Dispatch(name: funcName, args: Array(f[3...]))
        config.mouseBindings.append(MouseBinding(mode: mode, mods: mod, button: button, dispatch: dispatch))
        mouseLocs.append(BindingLocation(file: currentFile, line: lineNumber))
        noteDispatch(dispatch)
        return true
    }

    // not in mango: parse_option's axisbind branch, apart
    private mutating func parseAxisBinding(_ value: String, _ lineNumber: Int) -> Bool {
        let mode = BindingParser.setBindingKeymode(config)

        let fields = BindingParser.sscanfFields(value, 8)
        if fields.count < 3 {
            configError("Invalid axisbind format: \(mangoHighlight(value))")
            return false
        }
        let f = fields.map { ValueParse.trimWhitespace($0) }
        let (modStr, dirStr, funcName) = (f[0], f[1], f[2])

        let mod = BindingParser.parseMod(modStr) { configError($0) }
        let dir = UInt32(bitPattern: ValueParse.parseDirection(dirStr))
        let known = Dispatch.isKnown(funcName)   // parse_func_name's name

        guard known, let mod else {
            if !known {
                configError("Unknown dispatch in axisbind: \(mangoHighlight(funcName))")
            }
            return false
        }
        let dispatch = Dispatch(name: funcName, args: Array(f[3...]))
        config.axisBindings.append(AxisBinding(mode: mode, mods: mod, dir: dir, dispatch: dispatch))
        axisLocs.append(BindingLocation(file: currentFile, line: lineNumber))
        noteDispatch(dispatch)
        return true
    }

    // not in mango: parse_option's switchbind branch, apart
    private mutating func parseSwitchBinding(_ key: String, _ value: String, _ lineNumber: Int) -> Bool {
        let mode = BindingParser.setBindingKeymode(config)

        let fields = BindingParser.sscanfFields(value, 7)
        if fields.count < 3 {
            configError("Invalid switchbind format: \(mangoHighlight(value))")
            return false
        }
        let f = fields.map { ValueParse.trimWhitespace($0) }
        let (foldStr, funcName) = (f[0], f[1])

        let fold = ValueParse.parseFoldState(foldStr)
        guard Dispatch.isKnown(funcName) else {   // parse_func_name's name
            configError("Unknown dispatch in switchbind: \(mangoHighlight(funcName))")
            return false
        }
        config.switchBindings.append(SwitchBinding(mode: mode, fold: fold, dispatch: Dispatch(name: funcName, args: Array(f[2...]))))
        switchLocs.append(BindingLocation(file: currentFile, line: lineNumber))
        note(.noEffect, key, ConfigParser.port?.optionNote(key, applied: false)?.1 ?? "")   // not in mango: the port's side
        return true
    }

    // not in mango: parse_option's gesturebind branch, apart
    private mutating func parseGestureBinding(_ value: String, _ lineNumber: Int) -> Bool {
        let mode = BindingParser.setBindingKeymode(config)

        let fields = BindingParser.sscanfFields(value, 9)
        if fields.count < 4 {
            configError("Invalid gesturebind format: \(mangoHighlight(value))")
            return false
        }
        let f = fields.map { ValueParse.trimWhitespace($0) }
        let (modStr, motionStr, fingersCountStr, funcName) = (f[0], f[1], f[2], f[3])

        let mod = BindingParser.parseMod(modStr) { configError($0) }
        let motion = UInt32(bitPattern: ValueParse.parseDirection(motionStr))
        let fingersCount = UInt32(truncatingIfNeeded: ValueParse.atoi(fingersCountStr))
        let known = Dispatch.isKnown(funcName)   // parse_func_name's name

        guard known, let mod else {
            if !known {
                configError("Unknown dispatch in axisbind: \(mangoHighlight(funcName))")
            }
            return false
        }
        let dispatch = Dispatch(name: funcName, args: Array(f[4...]))
        config.gestureBindings.append(GestureBinding(mode: mode, mods: mod, motion: motion, fingersCount: fingersCount,
                                                     dispatch: dispatch))
        gestureLocs.append(BindingLocation(file: currentFile, line: lineNumber))
        noteDispatch(dispatch)
        return true
    }

    mutating func applyOptionExpanded(_ key: String, _ value: String, _ lineNumber: Int) -> Bool {
        let expanded = expandConfigVariables(value)
        let ok = parseOption(key, expanded, lineNumber)
        return ok
    }
}

// not in mango: set_value_default's values are Config's own (parse.swift)

extension Config {
    // not in mango: the 0..1 clamps are where the value is stored (ConfigOptions.bool), as a Bool here
    public mutating func overrideConfig() {
        func c<T: Comparable>(_ v: inout T, _ lo: T, _ hi: T) { v = min(max(v, lo), hi) }
        c(&zoomInitialRatio, 0.1, 1); c(&zoomEndRatio, 0.1, 1)
        c(&fadeinBeginOpacity, 0, 1); c(&fadeoutBeginOpacity, 0, 1)
        c(&animationDurationMove, 0, 50000); c(&animationDurationOpen, 0, 50000)
        c(&animationDurationTag, 0, 50000); c(&animationDurationClose, 0, 50000)
        c(&animationDurationFocus, 0, 50000)
        c(&scrollerStructs, 0, 1000)
        c(&scrollerDefaultProportion, 0.1, 1); c(&scrollerDefaultProportionSingle, 0.1, 1)
        c(&edgeScrollerFocusAllowSpeed, 0, 1000)
        c(&defaultMfact, 0.1, 0.9); c(&defaultNmaster, 1, 1000)
        c(&tagNum, 1, 31)
        c(&dwindleVsplit, 0, 2); c(&dwindleHsplit, 0, 2)
        c(&dwindleSplitRatio, 0.05, 0.95)
        c(&gappih, 0, 1000); c(&gappiv, 0, 1000)
        c(&gappoh, 0, 1000); c(&gappov, 0, 1000)
        c(&borderpx, 0, 200); c(&borderRadius, 0, 100)
        c(&focusedOpacity, 0, 1); c(&unfocusedOpacity, 0, 1)
        c(&hotareaCorner, 0, 3)
        c(&overcircleCenterRatio, 0.1, 0.9)
        c(&hotareaSize, 1, 1000)
        c(&overviewgappi, 0, 1000); c(&overviewgappo, 0, 1000)
        c(&dragCorner, 0, 4)
        c(&borderResizeSize, 0, 50)
        c(&snapDistance, 0, 99999)
        c(&cursorHideTimeout, 0, 36000)
        c(&axisBindApplyTimeout, 0, 1000)
        c(&swipeMinThreshold, 1, 1000)
        c(&gestureSwipeDistance, 32, 4096)
        c(&gestureSwipeCancelRatio, 0.05, 0.95)
        gestureSwipeMinSpeedToForce = max(0, gestureSwipeMinSpeedToForce)
        c(&scratchpadWidthRatio, 0.1, 1); c(&scratchpadHeightRatio, 0.1, 1)
        c(&specialDim, 0, 1)
        c(&tabBarHeight, 0, 500); c(&groupBarHeight, 0, 500)
        c(&titleMessageBarHeight, 0, 500); c(&titleMessageBarGap, 0, 500)
        c(&groupBarButtonSize, 4, 64); c(&groupBarButtonMargin, 0, 50)
        c(&specialGappih, 0, 1000); c(&specialGappiv, 0, 1000)
        c(&specialGappoh, 0, 1000); c(&specialGappov, 0, 1000)
    }
}

extension MangoServer {
    func updateGlobalVar() {
        tagmask = (UInt32(1) << UInt32(config.tagNum)) - 1
    }
}

// not in mango: parse_option's result from a table setter
public enum OptionResult: Equatable {
    case applied
    /// parse_option's false after mango_error's messages: `earlier` ones, then this one.
    case invalid(String, earlier: [String] = [])
}

// not in mango: parse_option's strcmp chain for the plain options, as a table
public enum ConfigOptions {
    // not in mango: the keys parse_option knows, for the tests
    public static var knownKeys: [String] { setters.keys.sorted() }

    /// Not in mango: asks whether apply stores a key.
    public static func hasSetter(_ key: String) -> Bool { setters[key] != nil || ConfigParser.port?.setter(key) != nil }
    public static var setterKeys: Set<String> { Set(setters.keys).union(ConfigParser.port?.keys ?? []) }   // not in mango: the port's side

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
        t["zoom_initial_ratio"] = float(\.zoomInitialRatio)
        t["zoom_end_ratio"] = float(\.zoomEndRatio)
        t["fade_in_begin_opacity"] = float(\.fadeinBeginOpacity)
        t["fade_out_begin_opacity"] = float(\.fadeoutBeginOpacity)
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
        t["scroller_default_proportion"] = float(\.scrollerDefaultProportion)
        t["scroller_default_proportion_single"] = float(\.scrollerDefaultProportionSingle)
        t["scroller_ignore_proportion_single"] = bool(\.scrollerIgnoreProportionSingle)
        t["scroller_focus_center"] = bool(\.scrollerFocusCenter)
        t["scroller_prefer_center"] = bool(\.scrollerPreferCenter)
        t["scroller_prefer_overspread"] = bool(\.scrollerPreferOverspread)
        t["edge_scroller_pointer_focus"] = bool(\.edgeScrollerPointerFocus)
        t["edge_scroller_focus_allow_speed"] = double(\.edgeScrollerFocusAllowSpeed)
        t["scroller_proportion_preset"] = { config, value in
            let floatCount = value.filter { $0 == "," }.count + 1
            config.scrollerProportionPreset = []
            var out: [Float] = []
            for token in value.split(separator: ",").map(String.init) where out.count < floatCount {
                guard let d = ValueParse.scanDouble(token, keepingInf: true) else {
                    return .invalid("Invalid float value in scroller_proportion_preset: \(mangoHighlight(token))")
                }
                out.append(min(max(Float(d), 0.1), 1.0))
            }
            if out.count != floatCount {
                return .invalid("Invalid scroller_proportion_preset format: \(mangoHighlight(value))")
            }
            config.scrollerProportionPreset = out
            return .applied
        }

        t["new_is_master"] = bool(\.newIsMaster)
        t["default_master_factor"] = float(\.defaultMfact)
        t["default_master_count"] = int(\.defaultNmaster)
        t["center_master_overspread"] = bool(\.centerMasterOverspread)
        t["center_when_single_stack"] = bool(\.centerWhenSingleStack)
        t["tag_num"] = int(\.tagNum)
        t["tag_gather"] = bool(\.tagGather)
        t["tag_carousel"] = unclampedBool(\.tagCarousel)
        t["view_current_to_back"] = bool(\.viewCurrentToBack)
        t["circle_layout"] = { config, value in
            let stringCount = value.filter { $0 == "," }.count + 1
            config.circleLayout = []
            let tokens = value.split(separator: ",")
            if tokens.count != stringCount {
                return .invalid("Invalid circle_layout format: \(mangoHighlight(value))")
            }
            config.circleLayout = tokens.map { tok in
                ValueParse.sanitizeString(tok)
            }
            return .applied
        }
        t["dwindle_vertical_split"] = int(\.dwindleVsplit)
        t["dwindle_horizontal_split"] = int(\.dwindleHsplit)
        t["dwindle_preserve_split"] = bool(\.dwindlePreserveSplit)
        t["dwindle_smart_split"] = bool(\.dwindleSmartSplit)
        t["dwindle_smart_resize"] = bool(\.dwindleSmartResize)
        t["dwindle_manual_split"] = bool(\.dwindleManualSplit)
        t["dwindle_drop_simple_split"] = bool(\.dwindleDropSimpleSplit)
        t["dwindle_split_ratio"] = float(\.dwindleSplitRatio)
        t["monocle_tab_mode"] = unclampedBool(\.monocleTabMode)
        t["monocle_no_border"] = bool(\.monocleNoBorder)
        t["monocle_no_gap"] = bool(\.monocleNoGap)
        t["monocle_no_radius"] = bool(\.monocleNoRadius)
        t["special_tag_cross_monitor"] = bool(\.specialTagCrossMonitor)
        t["deck_tab_mode"] = unclampedBool(\.deckTabMode)
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
        t["focused_opacity"] = float(\.focusedOpacity)
        t["unfocused_opacity"] = float(\.unfocusedOpacity)
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
        t["scratchpad_width_ratio"] = float(\.scratchpadWidthRatio, 0.1...1)
        t["scratchpad_height_ratio"] = float(\.scratchpadHeightRatio, 0.1...1)
        t["special_dim"] = float(\.specialDim, 0...1)
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
        t["overcircle_center_ratio"] = float(\.overcircleCenterRatio, 0.1...0.9)
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
        t["gesture_swipe_min_speed_to_force"] = double(\.gestureSwipeMinSpeedToForce)

        return t
    }()

/// Not in mango: parse_option's strcmp chain is a table here; these make its entries.
    // not in mango: override_config's CLAMP_INT(x, 0, 1) as the value is stored (a Bool here)
    package static func bool(_ kp: WritableKeyPath<Config, Bool>) -> Setter {
        { config, value in
            config[keyPath: kp] = ValueParse.atoi(value) > 0
            return .applied
        }
    }

    // not in mango: the int read as true or false, for the keys override_config does not clamp
    package static func unclampedBool(_ kp: WritableKeyPath<Config, Bool>) -> Setter {
        { config, value in
            config[keyPath: kp] = ValueParse.atoi(value) != 0
            return .applied
        }
    }

    package static func int(_ kp: WritableKeyPath<Config, Int>, _ range: ClosedRange<Int>? = nil) -> Setter {
        { config, value in
            let n = ValueParse.atoi(value)
            config[keyPath: kp] = range.map { min(max(n, $0.lowerBound), $0.upperBound) } ?? n
            return .applied
        }
    }

    package static func double(_ kp: WritableKeyPath<Config, Double>, _ range: ClosedRange<Double>? = nil) -> Setter {
        { config, value in
            let d = ValueParse.atof(value, keepingInf: true)   // not in mango: inf kept, each one is clamped
            config[keyPath: kp] = range.map { min(max(d, $0.lowerBound), $0.upperBound) } ?? d
            return .applied
        }
    }

    package static func float(_ kp: WritableKeyPath<Config, Float>, _ range: ClosedRange<Double>? = nil) -> Setter {
        { config, value in
            let d = ValueParse.atof(value, keepingInf: true)   // not in mango: inf kept, each one is clamped
            config[keyPath: kp] = Float(range.map { min(max(d, $0.lowerBound), $0.upperBound) } ?? d)
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
            let n = ValueParse.atoi(value)
            config[keyPath: kp] = min(max(n, range.lowerBound), range.upperBound)
            return .applied
        }
    }

    static func curve(_ kp: WritableKeyPath<Config, BezierCurve>, _ name: String) -> Setter {
        { config, value in
            var v: [Double] = []
            let (num, error) = ValueParse.parseDoubleArray(value, &v, 4)
            config[keyPath: kp] = BezierCurve(x1: v[0], y1: v[1], x2: v[2], y2: v[3])
            if num != 4 {
                return .invalid("Failed to parse \(name): \(mangoHighlight(value))", earlier: error.map { [$0] } ?? [])
            }
            return .applied
        }
    }

    private static func animation(_ kp: WritableKeyPath<Config, AnimationType>) -> Setter {
        { config, value in
            config[keyPath: kp] = ValueParse.animationTypeFromString(value) ?? .slide
            return .applied
        }
    }

    // not in mango: getenv("HOME")
    static func homeDirectory() -> String? {
        ProcessInfo.processInfo.environment["HOME"]
    }
}
