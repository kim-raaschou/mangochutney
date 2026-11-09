import Mango

extension Config {
    private func bool(_ key: String, _ unset: Bool) -> Bool { port[key].map { $0 == "1" } ?? unset }
    private mutating func set(_ key: String, _ v: Bool) { port[key] = v ? "1" : "0" }
    private func int(_ key: String, _ unset: Int) -> Int { port[key].flatMap { Int($0) } ?? unset }
    private func double(_ key: String, _ unset: Double) -> Double { port[key].flatMap { Double($0) } ?? unset }
    private func list(_ key: String, _ unset: [String]) -> [String] {
        port[key].map { $0.isEmpty ? [] : $0.split(separator: ",").map(String.init) } ?? unset
    }

    package var chutneyMacOSAppearance: Bool {
        get { bool("chutney_macos_appearance", false) } set { set("chutney_macos_appearance", newValue) }
    }
    package var chutneyTabBarDecorateIcon: Bool {
        get { bool("chutney_tab_bar_decorate_icon", false) } set { set("chutney_tab_bar_decorate_icon", newValue) }
    }
    package var chutneyGroupBarDecorateIcon: Bool {
        get { bool("chutney_group_bar_decorate_icon", false) } set { set("chutney_group_bar_decorate_icon", newValue) }
    }
    package var chutneyTabBarShortcuts: Bool {
        get { bool("chutney_tab_bar_shortcuts", false) } set { set("chutney_tab_bar_shortcuts", newValue) }
    }
    package var chutneyHyperModifier: String {
        get { port["chutney_hyper_modifier"] ?? "super+ctrl+alt" } set { port["chutney_hyper_modifier"] = newValue }
    }
    package var chutneyHyperKey: String {
        get { port["chutney_hyper_key"] ?? "" } set { port["chutney_hyper_key"] = newValue }
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
    package var chutneyOverlapWarning: Bool {
        get { bool("chutney_overlap_warning", false) } set { set("chutney_overlap_warning", newValue) }
    }
    package var chutneyKeybindingsSpotlightLaunch: Bool {
        get { bool("chutney_keybindings_spotlight_launch", true) } set { set("chutney_keybindings_spotlight_launch", newValue) }
    }
    package var chutneyLayoutSwitcherKeys: [String] {
        get { list("chutney_layout_switcher_keys", ["left", "down", "up", "right"]) }
        set { port["chutney_layout_switcher_keys"] = newValue.joined(separator: ",") }
    }
}
