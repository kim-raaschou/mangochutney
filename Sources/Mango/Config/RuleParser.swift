import Foundation

public enum RuleParser {
/// Not in mango: parse_option's window_rule and tag_rule branches, apart for its two callers.
    public static func parseWindowRule(_ value: String, once: Bool) -> Result<WindowRule, String> {
        let (rule, errors) = parseWindowRuleLenient(value, once: once)
        if let first = errors.first { return .failure(first) }
        return .success(rule)
    }

    public static func parseTagRule(_ value: String) -> Result<TagRule, String> {
        let (rule, errors) = parseTagRuleLenient(value)
        if let first = errors.first { return .failure(first) }
        return .success(rule)
    }

    static func parseWindowRuleLenient(_ value: String, once: Bool) -> (WindowRule, [String]) {
        let (rule, errors, _) = parseWindowRuleChecked(value, once: once)
        return (rule, errors)
    }

    static func parseWindowRuleChecked(_ value: String, once: Bool) -> (WindowRule, [String], keep: Bool) {
        var keep = true
        var rule = WindowRule()
        rule.once = once
        var errors: [String] = []

        for (key, val) in tokens(value) {
            func flag(_ apply: (Bool) -> Void) {
                if let n = ValueParse.int(val) { apply(n != 0) } else { errors.append("Invalid value for window rule option \(key): \(val)") }
            }
            func number(_ apply: (Double) -> Void) {
                if let d = ValueParse.double(val) { apply(d) } else { errors.append("Invalid value for window rule option \(key): \(val)") }
            }
            func integer(_ apply: (Int) -> Void) {
                if let n = ValueParse.int(val) { apply(n) } else { errors.append("Invalid value for window rule option \(key): \(val)") }
            }
            func anim(_ apply: (AnimationType) -> Void) {
                guard !val.isEmpty else { return }
                apply(animationTypeFromString(val))
            }

            switch key {
            case "app_id": rule.appId = val.isEmpty ? nil : val
            case "title": rule.title = val.isEmpty ? nil : val
            case "is_floating": flag { rule.isFloating = $0 }
            case "is_fullscreen": flag { rule.isFullscreen = $0 }
            case "is_fake_fullscreen": flag { rule.isFakeFullscreen = $0 }
            case "is_global": flag { rule.isGlobal = $0 }
            case "is_overlay": flag { rule.isOverlay = $0 }
            case "is_open_silent": flag { rule.isOpenSilent = $0 }
            case "is_tag_silent": flag { rule.isTagSilent = $0 }
            case "is_named_scratchpad": flag { rule.isNamedScratchpad = $0 }
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
                guard let dash = val.firstIndex(of: "-"), dash != val.startIndex else {
                    errors.append("Invalid globalkeybinding: \(mangoHighlight(val))")
                    keep = false
                    continue
                }
                let modStr = String(val[..<dash]).trimmingCharacters(in: .whitespaces)
                let keyStr = String(val[val.index(after: dash)...]).trimmingCharacters(in: .whitespaces)
                if Modifiers.parse(modStr) == nil {
                    errors.append("Unknown modifier: \(mangoHighlight(modStr))")
                    keep = false
                } else if keyStr.isEmpty || (ConfigParser.port?.keyCodes(keyStr) ?? []).isEmpty {   // the boundary: xkb's keymap
                    errors.append("Unknown key: \(mangoHighlight(keyStr))")
                    keep = false
                } else {
                    rule.globalKeyBinding = val
                }
            default:
                if !(ConfigParser.port?.knowsWindowRuleField(key) ?? false) {   // the port's: not in mango
                    errors.append("Unknown window rule option:\(mangoHighlight(key))")
                }
            }
        }
        return (rule, errors, keep)
    }

    static func parseTagRuleLenient(_ value: String) -> (TagRule, [String]) {
        var rule = TagRule()
        rule.id = 0
        var errors: [String] = []

        func clampI(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
        func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }

        for (key, val) in tokens(value) {
            let bad = "Invalid value for tag rule option \(key): \(val)"
            switch key {
            case "id":
                if val == "*" { rule.id = nil }
                else if let n = ValueParse.int(val) { rule.id = clampI(n, 0, 31) }
                else { errors.append(bad) }
            case "layout_name":
                rule.layoutName = val
            case "monitor_name": rule.monitorName = val
            case "monitor_make": rule.monitorMake = val
            case "monitor_model": rule.monitorModel = val
            case "monitor_serial": rule.monitorSerial = val
            case "no_render_border":
                if let n = ValueParse.int(val) { rule.noRenderBorder = n != 0 } else { errors.append(bad) }
            case "open_as_floating":
                if let n = ValueParse.int(val) { rule.openAsFloating = n != 0 } else { errors.append(bad) }
            case "no_hide":
                if let n = ValueParse.int(val) { rule.noHide = n != 0 } else { errors.append(bad) }
            case "master_count":
                if let n = ValueParse.int(val) { rule.masterCount = clampI(n, 1, 99) } else { errors.append(bad) }
            case "master_factor":
                if let d = ValueParse.double(val) { rule.masterFactor = clampD(d, 0.1, 0.9) } else { errors.append(bad) }
            case "scroller_default_proportion":
                if let d = ValueParse.double(val) { rule.scrollerDefaultProportion = clampD(d, 0, 1) } else { errors.append(bad) }
            case "scroller_default_proportion_single":
                if let d = ValueParse.double(val) { rule.scrollerDefaultProportionSingle = clampD(d, 0, 1) } else { errors.append(bad) }
            case "scroller_ignore_proportion_single":
                if let n = ValueParse.int(val) { rule.scrollerIgnoreProportionSingle = n != 0 } else { errors.append(bad) }
            default:
                errors.append("Unknown tag rule option:\(mangoHighlight(key))")
            }
        }
        return (rule, errors)
    }

    static func tokens(_ value: String) -> [(String, String)] {
        value.split(separator: ",").compactMap { tok in
            guard let colon = tok.firstIndex(of: ":") else { return nil }
            let k = tok[..<colon].trimmingCharacters(in: .whitespaces)
            let v = tok[tok.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return (k, v)
        }
    }
}
