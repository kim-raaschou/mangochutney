import Mango

/// Port extension: not in mango. The port's own options, read and set as fields of mango's
/// Config and kept in its `port` values (PortOptions sets them from the config). Unset, each
/// is its default and mango behaves as mango does.
extension Config {
    private func bool(_ key: String, _ unset: Bool) -> Bool { port[key].map { $0 == "1" } ?? unset }
    private mutating func set(_ key: String, _ v: Bool) { port[key] = v ? "1" : "0" }
    private func int(_ key: String, _ unset: Int) -> Int { port[key].flatMap { Int($0) } ?? unset }
    private func double(_ key: String, _ unset: Double) -> Double { port[key].flatMap { Double($0) } ?? unset }
    private func list(_ key: String, _ unset: [String]) -> [String] {
        port[key].map { $0.isEmpty ? [] : $0.split(separator: ",").map(String.init) } ?? unset
    }

    /// The bars, the switcher's panel and the jump labels in the macOS style where no
    /// decorate key is set (chutney_style; off unless set, as every extension).
    package var chutneyStyle: Bool {
        get { bool("chutney_style", false) } set { set("chutney_style", newValue) }
    }
    /// The app's icon before each tab's title (OmniWM's app-icon tabs).
    package var chutneyTabBarAppIcons: Bool {
        get { bool("chutney_tab_bar_app_icons", false) } set { set("chutney_tab_bar_app_icons", newValue) }
    }
    /// ⌘1-9 picks a tab while a tab bar is shown, with the numbers on the tabs while ⌘ is
    /// held (as browsers' tabs).
    package var chutneyTabBarShortcuts: Bool {
        get { bool("chutney_tab_bar_shortcuts", false) } set { set("chutney_tab_bar_shortcuts", newValue) }
    }
    /// Fixed border colour of floating windows, focused or not; nil = mango's colours.
    package var chutneyFloatingColor: RGBA? {
        get { port["chutney_floating_color"].flatMap { parseColor($0) } }
        set {
            port["chutney_floating_color"] = newValue.map { c in
                let byte = { (v: Double) in Int((v * 255).rounded()) }
                return String(format: "0x%02x%02x%02x%02x", byte(c.r), byte(c.g), byte(c.b), byte(c.a))
            }
        }
    }
    /// Modifier combination that `HYPER` expands to (default: ⌃⌥⌘, super+ctrl+alt).
    package var chutneyHyperModifier: String {
        get { port["chutney_hyper_modifier"] ?? "super+ctrl+alt" } set { port["chutney_hyper_modifier"] = newValue }
    }
    /// The key held as Hyper (chutney_hyper_key), as Raycast's Hyper Key: caps_lock, a left or
    /// right modifier (right_command, …) or f1 … f12; empty: none (Hyper is
    /// chutney_hyper_modifier held).
    package var chutneyHyperKey: String {
        get { port["chutney_hyper_key"] ?? "" } set { port["chutney_hyper_key"] = newValue }
    }
    /// Caps Lock or a function key that is Hyper, pressed alone (chutney_hyper_tap): none, the
    /// key itself (original), or escape.
    package var chutneyHyperTap: String {
        get { port["chutney_hyper_tap"] ?? "none" } set { port["chutney_hyper_tap"] = newValue }
    }
    /// Show a menu-bar status item with the current tag/layout (chutney_menu_bar).
    package var chutneyMenuBar: Bool {
        get { bool("chutney_menu_bar", false) } set { set("chutney_menu_bar", newValue) }
    }
    /// The tags in the menu bar: SF Symbols numbers in a square or a circle, or text.
    package var chutneyMenuBarTagStyle: String {
        get { port["chutney_menu_bar_tag_style"] ?? "square" } set { port["chutney_menu_bar_tag_style"] = newValue }
    }
    /// The file the menu's panel saves its settings in, read after the config (relative to
    /// the config's directory); empty: nothing is saved.
    package var chutneyMenuConfig: String {
        get { port["chutney_menu_config"] ?? "" } set { port["chutney_menu_config"] = newValue }
    }
    /// The mango logo in front of the tags: "color" (mango's colours), "mono" (a template
    /// silhouette in the menu bar's colour) or "off".
    package var chutneyMenuBarLogo: String {
        get { port["chutney_menu_bar_logo"] ?? "color" } set { port["chutney_menu_bar_logo"] = newValue }
    }
    /// The layout's icon after the tags.
    package var chutneyMenuBarLayout: Bool {
        get { bool("chutney_menu_bar_layout", true) } set { set("chutney_menu_bar_layout", newValue) }
    }
    /// The key mode after the layout, the default one too (so the item keeps its width).
    package var chutneyMenuBarMode: Bool {
        get { bool("chutney_menu_bar_mode", true) } set { set("chutney_menu_bar_mode", newValue) }
    }
    /// Draw border overlays for unfocused windows too (mango draws all; 0 is the port's).
    package var chutneyBorderUnfocused: Bool {
        get { bool("chutney_border_unfocused", true) } set { set("chutney_border_unfocused", newValue) }
    }
    /// border_px and the gaps in the screen's own pixels rather than points (on Retina,
    /// border_px=3 is 1.5 points).
    package var chutneyPhysicalPixels: Bool {
        get { bool("chutney_physical_pixels", false) } set { set("chutney_physical_pixels", newValue) }
    }
    /// A tiled window its app keeps larger than its tile (it goes over its neighbour): the menu
    /// bar draws its tag in orange, and the menu says by how much and offers to move it to an
    /// empty tag or float it.
    package var chutneyOverlapWarning: Bool {
        get { bool("chutney_overlap_warning", false) } set { set("chutney_overlap_warning", newValue) }
    }
    /// The hotkeys palette (chutney_toggle_hotkeys_palette): the most rows it shows (its height
    /// follows them; a longer group gets two columns, a search its best matches), the rows used
    /// of late on its front page (0: none), its width in points, and the installed apps in its
    /// search.
    package var chutneyHotkeysMaxRows: Int {
        get { int("chutney_hotkeys_max_rows", 14) } set { port["chutney_hotkeys_max_rows"] = String(newValue) }
    }
    package var chutneyHotkeysRecent: Int {
        get { int("chutney_hotkeys_recent", 4) } set { port["chutney_hotkeys_recent"] = String(newValue) }
    }
    package var chutneyHotkeysWidth: Double {
        get { double("chutney_hotkeys_width", 680) } set { port["chutney_hotkeys_width"] = String(newValue) }
    }
    package var chutneyHotkeysApps: Bool {
        get { bool("chutney_hotkeys_apps", true) } set { set("chutney_hotkeys_apps", newValue) }
    }
    /// The layout palette (chutney_toggle_layout_palette): the keys that move its selection,
    /// left, down, up, right (arrow names or single characters; the arrows always work).
    package var chutneyLayoutPaletteKeys: [String] {
        get { list("chutney_layout_palette_keys", ["left", "down", "up", "right"]) }
        set { port["chutney_layout_palette_keys"] = newValue.joined(separator: ",") }
    }
    /// The layout palette's width in points; its cells and icons follow.
    package var chutneyLayoutPaletteWidth: Double {
        get { double("chutney_layout_palette_width", 560) } set { port["chutney_layout_palette_width"] = String(newValue) }
    }
    /// Windows of apps whose bundle id matches are never managed.
    package var chutneyIgnoreApps: [String] {
        get { list("chutney_ignore_apps", []) } set { port["chutney_ignore_apps"] = newValue.joined(separator: ",") }
    }
}
