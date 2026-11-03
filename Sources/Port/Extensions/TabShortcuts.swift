import Mango
/// chutney_tab_bar_shortcuts (port extension): ⌘1-9 picks a tab while a tab bar is shown, with
/// the numbers on the tabs while ⌘ alone is held, as browsers' tabs. The event tap takes
/// the keys before the bindings only when no binding wants them (InputRouter).
extension MangoServer {
    /// The tabs on the focused monitor that ⌘1-9 picks (`chutney_tab_bar_shortcuts`): its tab bar
    /// as long as it is shown, up to nine.
    var tabBarShortcutTabs: Int {
        guard config.chutneyTabBarShortcuts, let m = selectedMonitor else { return 0 }
        if let s = m.sel.flatMap({ clientByIdAll($0) }), s.isVisible(on: m), s.isFullscreen || s.isMaximizeScreen { return 0 }
        return min(9, tabMembers(m).count)
    }

    /// ⌘ alone is held or let go: the numbers on the focused monitor's tabs.
    func showTabNumbers(_ on: Bool) {
        guard on != mac.tabNumbersShown else { return }
        mac.tabNumbersShown = on
        tabRefreshBars()
    }

    /// ⌘`n`: the focused monitor's tab `n`.
    func tabFocusMember(number n: Int) {
        // The event tap decided from what was published; the tab bar may have gone since.
        guard n >= 1, n <= tabBarShortcutTabs else { return }
        tabFocusMember(tabMembers(selectedMonitor)[n - 1].id)
    }
}

extension MacWindowSystem {
    /// mango's tab bars were refreshed: the event tap learns how many tabs ⌘1-9 picks now.
    func tabBarsChanged() {
        let n = server.tabBarShortcutTabs
        guard n != publishedTabShortcuts else { return }
        publishedTabShortcuts = n
        router.publish { $0.tabShortcuts = n }
    }

    /// While ⌘ alone is held, the focused monitor's tabs show the numbers ⌘1-9 picks them by.
    func withTabNumbers(_ strips: [TabStrip]) -> [TabStrip] {
        let count = server.tabBarShortcutTabs
        guard tabNumbersShown, count > 0 else { return strips }
        return strips.map { strip in
            guard server.clientByIdAll(strip.above)?.mon === server.selectedMonitor else { return strip }
            var s = strip
            for i in s.segments.indices where i < count { s.segments[i].shortcut = i + 1 }
            return s
        }
    }

    /// chutney_tab_bar_app_icons: the apps' icons on the tabs.
    func withAppIcons(_ style: TabStripStyle) -> TabStripStyle {
        var s = style
        s.appIcons = server.config.chutneyTabBarAppIcons
        return s
    }
}
