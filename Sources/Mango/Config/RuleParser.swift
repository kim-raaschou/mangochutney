import Foundation

// not in mango: parse_option's window_rule and tag_rule branches, apart from it; `errors`, where
// mango_error prints
public enum RuleParser {
    /// The rule (nil where mango does not count it) and parse_option's result.
    static func parseWindowRule(_ value: String, once: Bool, errors: inout [String]) -> (ConfigWinRule?, Bool) {
        var rule = ConfigWinRule()
        rule.once = once
        var parseError = false

        for (key, val) in tokens(value) {
            // not in mango: nil for a negative value, mango's unset -1
            func flag(_ apply: (Bool?) -> Void) {
                let n = ValueParse.atoi(val)
                apply(n >= 0 ? n != 0 : nil)
            }
            func number(_ apply: (Double) -> Void) { apply(ValueParse.atof(val)) }
            func integer(_ apply: (Int) -> Void) { apply(ValueParse.atoi(val)) }
            func anim(_ apply: (AnimationType) -> Void) {
                guard !val.isEmpty else { return }
                apply(animationTypeFromString(val))
            }

            switch key {
            case "app_id": rule.appId = val
            case "title": rule.title = val
            case "is_floating": flag { rule.isfloating = $0 }
            case "is_fullscreen": flag { rule.isfullscreen = $0 }
            case "is_fake_fullscreen": flag { rule.isfakefullscreen = $0 }
            case "is_global": flag { rule.isglobal = $0 }
            case "is_overlay": flag { rule.isoverlay = $0 }
            case "is_open_silent": flag { rule.isopensilent = $0 }
            case "is_tag_silent": flag { rule.istagsilent = $0 }
            case "is_named_scratchpad": flag { rule.isnamedscratchpad = $0 }
            case "is_unmanaged_global": flag { rule.isUnmanagedGlobal = $0 }
            case "is_term": flag { rule.isTerm = $0 }
            case "no_swallow": flag { rule.noSwallow = $0 }
            case "tags":
                let m = TagMask.parseTagMask(val)
                rule.tags = m == 0 ? nil : m
            case "monitor": rule.monitor = val.isEmpty ? nil : MonitorSpec(mango: val)
            case "width": number { rule.width = $0 }
            case "height": number { rule.height = $0 }
            case "offset_x": integer { rule.offsetX = $0 }
            case "offset_y": integer { rule.offsetY = $0 }
            case "no_force_center": flag { rule.noForceCenter = $0 }
            case "no_size_hint": flag { rule.noSizeHint = $0 }
            case "no_border": flag { rule.noBorder = $0 }
            case "no_shadow": flag { rule.noShadow = $0 }
            case "no_radius": flag { rule.noRadius = $0 }
            case "no_blur": flag { rule.noBlur = $0 }
            case "no_animation": flag { rule.noAnimation = $0 }
            case "no_fade_in": flag { rule.noFadeIn = $0 }
            case "no_fade_out": flag { rule.noFadeOut = $0 }
            case "focused_opacity": number { rule.focusedOpacity = $0 }
            case "unfocused_opacity": number { rule.unfocusedOpacity = $0 }
            case "allow_csd": flag { rule.allowCsd = $0 }
            case "animation_type_open": anim { rule.animationTypeOpen = $0 }
            case "animation_type_close": anim { rule.animationTypeClose = $0 }
            case "scroller_proportion": number { rule.scrollerProportion = $0 }
            case "scroller_proportion_single": number { rule.scrollerProportionSingle = $0 }
            case "no_focus": flag { rule.noFocus = $0 }
            case "confine_pointer": flag { rule.confinePointer = $0 }
            case "ignore_maximize": flag { rule.ignoreMaximize = $0 }
            case "ignore_minimize": flag { rule.ignoreMinimize = $0 }
            case "force_tiled_state": flag { rule.forceTiledState = $0 }
            case "global_key_binding":
                guard let dash = val.firstIndex(of: "-"), dash != val.startIndex,
                      let keyStart = val[val.index(after: dash)...].firstIndex(where: { !$0.isWhitespace }) else {
                    errors.append("Invalid globalkeybinding: \(mangoHighlight(val))")
                    return (nil, false)
                }
                let modStr = ConfigParser.trimWhitespace(val[..<dash])
                let keyStr = String(val[keyStart...].prefix { !$0.isWhitespace })
                let mods = Modifiers.parse(modStr) { errors.append($0) }
                let keyKnown = !(ConfigParser.port?.keyCodes(keyStr) ?? []).isEmpty   // the boundary: xkb's keymap
                if !keyKnown { errors.append("Unknown key: \(mangoHighlight(keyStr))") }
                if mods == nil || !keyKnown { return (nil, false) }
                rule.globalKeyBinding = val
            default:
                if !(ConfigParser.port?.knowsWindowRuleField(key) ?? false) {   // the port's: not in mango
                    errors.append("Unknown window rule option:\(mangoHighlight(key))")
                    parseError = true
                }
            }
        }
        return (rule, !parseError)
    }

    /// The rule, which mango always counts, and parse_option's result.
    static func parseTagRule(_ value: String, errors: inout [String]) -> (ConfigTagRule, Bool) {
        var rule = ConfigTagRule()
        rule.id = 0
        var parseError = false

        func clampI(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
        func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }

        for (key, val) in tokens(value) {
            switch key {
            case "id": rule.id = val == "*" ? nil : clampI(ValueParse.atoi(val), 0, 31)
            case "layout_name": rule.layoutName = val
            case "monitor_name": rule.monitorName = val
            case "monitor_make": rule.monitorMake = val
            case "monitor_model": rule.monitorModel = val
            case "monitor_serial": rule.monitorSerial = val
            case "no_render_border": rule.noRenderBorder = ValueParse.atoi(val) > 0
            case "open_as_floating": rule.openAsFloating = ValueParse.atoi(val) > 0
            case "no_hide": rule.noHide = ValueParse.atoi(val) > 0
            case "master_count": rule.masterCount = clampI(ValueParse.atoi(val), 1, 99)
            case "master_factor": rule.masterFactor = clampD(ValueParse.atof(val), 0.1, 0.9)
            case "scroller_default_proportion":
                rule.scrollerDefaultProportion = clampD(ValueParse.atof(val), 0, 1)
            case "scroller_default_proportion_single":
                rule.scrollerDefaultProportionSingle = clampD(ValueParse.atof(val), 0, 1)
            case "scroller_ignore_proportion_single":
                rule.scrollerIgnoreProportionSingle = ValueParse.atoi(val) > 0
            default:
                errors.append("Unknown tag rule option:\(mangoHighlight(key))")
                parseError = true
            }
        }
        return (rule, !parseError)
    }

    // not in mango: strtok's tokens split at their first colon, trimmed
    static func tokens(_ value: String) -> [(String, String)] {
        value.split(separator: ",").compactMap { tok in
            guard let colon = tok.firstIndex(of: ":") else { return nil }
            let k = ConfigParser.trimWhitespace(tok[..<colon])
            let v = ConfigParser.trimWhitespace(tok[tok.index(after: colon)...])
            return (k, v)
        }
    }
}
