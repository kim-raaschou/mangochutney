import Mango

extension MacWindowSystem {
    func withAppIcons(_ style: TabStripStyle, _ on: Bool) -> TabStripStyle {
        var s = style
        s.appIcons = on
        return s
    }
}
