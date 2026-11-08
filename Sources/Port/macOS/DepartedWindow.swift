import CoreGraphics
import Mango

package struct DepartedWindow: Equatable {
    package var tags: UInt32
    package var displayID: CGDirectDisplayID?
    package var isFloating: Bool
    package var isGlobal: Bool
    package var isOverlay: Bool
    package var isMinimized: Bool
    package var isScratchpad: Bool
    package var isNamedScratchpad: Bool
    package var floatFrame: CGRect
    package var scrollerProportion: CGFloat?
    package var orderSnapshot: [CGWindowID]
    package var at: CFTimeInterval
    package var bundleId: String = ""
    package var homeDisplayID: CGDirectDisplayID? = nil
    package var fromSavedLayout = false
    package var isCustomSize = false

    package init(tags: UInt32, displayID: CGDirectDisplayID?, isFloating: Bool, isGlobal: Bool, isOverlay: Bool,
                 isMinimized: Bool, isScratchpad: Bool, isNamedScratchpad: Bool, floatFrame: CGRect,
                 scrollerProportion: CGFloat?, orderSnapshot: [CGWindowID], at: CFTimeInterval, bundleId: String = "",
                 homeDisplayID: CGDirectDisplayID? = nil, fromSavedLayout: Bool = false, isCustomSize: Bool = false) {
        self.tags = tags; self.displayID = displayID; self.isFloating = isFloating; self.isGlobal = isGlobal
        self.isOverlay = isOverlay; self.isMinimized = isMinimized; self.isScratchpad = isScratchpad
        self.isNamedScratchpad = isNamedScratchpad; self.floatFrame = floatFrame
        self.scrollerProportion = scrollerProportion; self.orderSnapshot = orderSnapshot; self.at = at
        self.bundleId = bundleId; self.homeDisplayID = homeDisplayID; self.fromSavedLayout = fromSavedLayout
        self.isCustomSize = isCustomSize
    }

    package static func insertionIndex(of id: CGWindowID, snapshot: [CGWindowID], into order: [CGWindowID]) -> Int {
        guard let at = snapshot.firstIndex(of: id) else { return order.count }
        for p in snapshot[..<at].reversed() {
            if let i = order.firstIndex(of: p) { return i + 1 }
        }
        for s in snapshot[(at + 1)...] {
            if let i = order.firstIndex(of: s) { return i }
        }
        return order.count
    }
}
