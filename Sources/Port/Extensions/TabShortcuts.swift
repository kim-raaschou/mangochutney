import Mango
extension MangoServer {
    var tabBarShortcutTabs: Int {
        guard config.chutneyTabBarShortcuts, let m = selectedMonitor else { return 0 }
        if let s = m.sel.flatMap({ clientByIdAll($0) }), s.isVisible(on: m), s.isFullscreen || s.isMaximizeScreen { return 0 }
        return min(9, tabMembers(m).count)
    }

    func showTabNumbers(_ on: Bool) {
        guard on != mac.tabNumbersShown else { return }
        mac.tabNumbersShown = on
        tabRefreshBars()
    }

    func tabFocusMember(number n: Int) {
        guard n >= 1, n <= tabBarShortcutTabs else { return }
        tabFocusMember(tabMembers(selectedMonitor)[n - 1].id)
    }
}

extension MacWindowSystem {
    func tabBarsChanged() {
        let n = server.tabBarShortcutTabs
        guard n != publishedTabShortcuts else { return }
        publishedTabShortcuts = n
        router.publish { $0.tabShortcuts = n }
    }

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

    func withAppIcons(_ style: TabStripStyle) -> TabStripStyle {
        var s = style
        s.appIcons = server.config.chutneyTabBarAppIcons
        return s
    }
}
