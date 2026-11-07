import Mango
/// Port extension: not in mango. The port's own config keys (listed in MangoCompat.portExtensionOptions),
/// beside the Config fields they set:
/// mango itself reports each as an unknown keyword and skips it. Unset, each leaves mango's
/// behaviour.
enum PortOptions {
    static let setters: [String: ConfigOptions.Setter] = {
        typealias O = ConfigOptions
        var t: [String: ConfigOptions.Setter] = [:]
        t["chutney_floating_color"] = { config, value in
            // Empty or "none": floating windows use mango's colours again.
            if value.isEmpty || value.lowercased() == "none" { config.chutneyFloatingColor = nil; return .applied }
            guard let c = parseColor(value) else { return .invalid("Invalid color format: \(value)") }
            config.chutneyFloatingColor = c
            return .applied
        }
        t["chutney_hyper_modifier"] = { config, value in
            guard let mods = Modifiers.parse(value, hyperModifier: ""), !mods.isEmpty else {
                return .invalid("Invalid chutney_hyper_modifier: \(value)")
            }
            config.chutneyHyperModifier = value
            return .applied
        }
        t["chutney_hyper_key"] = { config, value in
            let v = value.lowercased()
            guard ["", "none"].contains(v) || KeyboardOptions.hyperKey(v) != nil else {
                return .invalid("Invalid chutney_hyper_key: \(value) (caps_lock, left_/right_ control, shift, option or command, f1 … f12)")
            }
            config.chutneyHyperKey = v == "none" ? "" : v
            return .applied
        }
        t["chutney_hyper_tap"] = { config, value in
            let v = value.lowercased()
            guard ["none", "original", "escape"].contains(v) else {
                return .invalid("Invalid chutney_hyper_tap: \(value) (none, original or escape)")
            }
            config.chutneyHyperTap = v
            return .applied
        }
        t["chutney_menu_bar"] = O.bool(\.chutneyMenuBar)
        t["chutney_menu_bar_tag_style"] = { config, value in
            let v = value.lowercased()
            guard ["square", "circle", "text"].contains(v) else {
                return .invalid("Invalid chutney_menu_bar_tag_style: \(value) (square, circle or text)")
            }
            config.chutneyMenuBarTagStyle = v
            return .applied
        }
        t["chutney_menu_config"] = { config, value in
            config.chutneyMenuConfig = value.trimmingCharacters(in: .whitespaces)
            return .applied
        }
        t["chutney_menu_bar_logo"] = { config, value in
            // 1 and 0 as before, the colour logo or none; mono: a template silhouette.
            switch value.lowercased() {
            case "1", "color", "colour": config.chutneyMenuBarLogo = "color"
            case "mono": config.chutneyMenuBarLogo = "mono"
            case "0": config.chutneyMenuBarLogo = "off"
            default: return .invalid("Invalid chutney_menu_bar_logo: \(value) (color, mono or 0)")
            }
            return .applied
        }
        t["chutney_menu_bar_layout"] = O.bool(\.chutneyMenuBarLayout)
        t["chutney_menu_bar_mode"] = O.bool(\.chutneyMenuBarMode)
        t["chutney_style"] = O.bool(\.chutneyStyle)
        t["chutney_tab_bar_app_icons"] = O.bool(\.chutneyTabBarAppIcons)
        t["chutney_tab_bar_shortcuts"] = O.bool(\.chutneyTabBarShortcuts)
        t["chutney_border_unfocused"] = O.bool(\.chutneyBorderUnfocused)
        t["chutney_physical_pixels"] = O.bool(\.chutneyPhysicalPixels)
        t["chutney_overlap_warning"] = O.bool(\.chutneyOverlapWarning)
        t["chutney_hotkeys_max_rows"] = O.int(\.chutneyHotkeysMaxRows, 3...60)
        t["chutney_hotkeys_recent"] = O.int(\.chutneyHotkeysRecent, 0...20)
        t["chutney_hotkeys_width"] = O.double(\.chutneyHotkeysWidth, 360...3000)
        t["chutney_hotkeys_apps"] = O.bool(\.chutneyHotkeysApps)
        t["chutney_layout_palette_width"] = O.double(\.chutneyLayoutPaletteWidth, 300...2000)
        t["chutney_layout_palette_keys"] = { config, value in
            let keys = value.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let arrows: Set<String> = ["left", "down", "up", "right"]
            guard keys.count == 4, keys.allSatisfy({ $0.count == 1 || arrows.contains($0) }) else {
                return .invalid("Invalid chutney_layout_palette_keys: \(value) (four keys: left,down,up,right or h,j,k,l)")
            }
            config.chutneyLayoutPaletteKeys = keys
            return .applied
        }
        t["chutney_ignore_apps"] = { config, value in
            // An empty value clears the list; otherwise ids are appended (several lines accumulate).
            let ids = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if ids.isEmpty { config.chutneyIgnoreApps = []; return .applied }
            for id in ids where !config.chutneyIgnoreApps.contains(id) { config.chutneyIgnoreApps.append(id) }
            return .applied
        }
        return t
    }()
}
