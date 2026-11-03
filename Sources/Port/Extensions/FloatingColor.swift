import CoreGraphics
import Mango

/// chutney_floating_color (port extension): a fixed border colour for floating windows.
extension MangoServer {
    /// Floating windows (scratchpads included) take `chutney_floating_color`. A maximized one
    /// counts as tiled, as for mango's border rules.
    static func usesFloatingBorder(_ c: Client) -> Bool {
        (c.isFloating || c.scratchpadShown) && !c.isMaximizeScreen
    }


    /// chutney_floating_color is fixed: focused or not, on any monitor. Urgent still shows, and
    /// scratchpad, global and overlay windows keep their own colours.
    func floatingBorderColor(_ c: Client) -> RGBA? {
        guard let fixed = config.chutneyFloatingColor, Self.usesFloatingBorder(c),
              !c.scratchpadShown, !c.isNamedScratchpad, !c.isGlobal, !c.isOverlay else { return nil }
        return c.isUrgent ? config.urgentcolor : fixed
    }
}
