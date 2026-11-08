import CoreGraphics
import Mango

extension MangoServer {
    static func usesFloatingBorder(_ c: Client) -> Bool {
        (c.isFloating || c.scratchpadShown) && !c.isMaximizeScreen
    }

    func floatingBorderColor(_ c: Client) -> RGBA? {
        guard let fixed = config.chutneyFloatingColor, Self.usesFloatingBorder(c),
              !c.scratchpadShown, !c.isNamedScratchpad, !c.isGlobal, !c.isOverlay else { return nil }
        return c.isUrgent ? config.urgentcolor : fixed
    }
}
