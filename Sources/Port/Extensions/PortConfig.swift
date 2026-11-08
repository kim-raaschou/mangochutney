import Mango

extension Config {
    private func bool(_ key: String, _ unset: Bool) -> Bool { port[key].map { $0 == "1" } ?? unset }
    private mutating func set(_ key: String, _ v: Bool) { port[key] = v ? "1" : "0" }
    private func int(_ key: String, _ unset: Int) -> Int { port[key].flatMap { Int($0) } ?? unset }
    private func double(_ key: String, _ unset: Double) -> Double { port[key].flatMap { Double($0) } ?? unset }
    private func list(_ key: String, _ unset: [String]) -> [String] {
        port[key].map { $0.isEmpty ? [] : $0.split(separator: ",").map(String.init) } ?? unset
    }

    package var chutneyStyle: Bool {
        get { bool("chutney_style", false) } set { set("chutney_style", newValue) }
    }
    package var chutneyTabBarAppIcons: Bool {
        get { bool("chutney_tab_bar_app_icons", false) } set { set("chutney_tab_bar_app_icons", newValue) }
    }
    package var chutneyTabBarShortcuts: Bool {
        get { bool("chutney_tab_bar_shortcuts", false) } set { set("chutney_tab_bar_shortcuts", newValue) }
    }
    package var chutneyFloatingColor: RGBA? {
        get { port["chutney_floating_color"].flatMap { parseColor($0) } }
        set {
            port["chutney_floating_color"] = newValue.map { c in
                let byte = { (v: Double) in Int((v * 255).rounded()) }
                return String(format: "0x%02x%02x%02x%02x", byte(c.r), byte(c.g), byte(c.b), byte(c.a))
            }
        }
    }
    package var chutneyHyperModifier: String {
        get { port["chutney_hyper_modifier"] ?? "super+ctrl+alt" } set { port["chutney_hyper_modifier"] = newValue }
    }
    package var chutneyHyperKey: String {
        get { port["chutney_hyper_key"] ?? "" } set { port["chutney_hyper_key"] = newValue }
    }
    package var chutneyHyperTap: String {
        get { port["chutney_hyper_tap"] ?? "none" } set { port["chutney_hyper_tap"] = newValue }
    }
    package var chutneyMenuBar: Bool {
        get { bool("chutney_menu_bar", false) } set { set("chutney_menu_bar", newValue) }
    }
    package var chutneyMenuBarTagStyle: String {
        get { port["chutney_menu_bar_tag_style"] ?? "square" } set { port["chutney_menu_bar_tag_style"] = newValue }
    }
    package var chutneyMenuConfig: String {
        get { port["chutney_menu_config"] ?? "" } set { port["chutney_menu_config"] = newValue }
    }
    package var chutneyMenuBarLogo: String {
        get { port["chutney_menu_bar_logo"] ?? "color" } set { port["chutney_menu_bar_logo"] = newValue }
    }
    package var chutneyMenuBarLayout: Bool {
        get { bool("chutney_menu_bar_layout", true) } set { set("chutney_menu_bar_layout", newValue) }
    }
    package var chutneyMenuBarMode: Bool {
        get { bool("chutney_menu_bar_mode", true) } set { set("chutney_menu_bar_mode", newValue) }
    }
    package var chutneyBorderUnfocused: Bool {
        get { bool("chutney_border_unfocused", true) } set { set("chutney_border_unfocused", newValue) }
    }
    package var chutneyPhysicalPixels: Bool {
        get { bool("chutney_physical_pixels", false) } set { set("chutney_physical_pixels", newValue) }
    }
    package var chutneyOverlapWarning: Bool {
        get { bool("chutney_overlap_warning", false) } set { set("chutney_overlap_warning", newValue) }
    }
    package var chutneyHotkeysApps: Bool {
        get { bool("chutney_hotkeys_apps", true) } set { set("chutney_hotkeys_apps", newValue) }
    }
    package var chutneyLayoutPaletteKeys: [String] {
        get { list("chutney_layout_palette_keys", ["left", "down", "up", "right"]) }
        set { port["chutney_layout_palette_keys"] = newValue.joined(separator: ",") }
    }
    package var chutneyIgnoreApps: [String] {
        get { list("chutney_ignore_apps", []) } set { port["chutney_ignore_apps"] = newValue.joined(separator: ",") }
    }
}
