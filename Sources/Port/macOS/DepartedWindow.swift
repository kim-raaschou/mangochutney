import CoreGraphics
import Mango

package struct DepartedWindow: Equatable {
    package var tags: UInt32
    package var displayID: CGDirectDisplayID?
    package var isfloating: Bool
    package var isglobal: Bool
    package var isoverlay: Bool
    package var isminimized: Bool
    package var isScratchpad: Bool
    package var isnamedscratchpad: Bool
    package var floatFrame: CGRect
    package var scrollerProportion: CGFloat?
    package var orderSnapshot: [CGWindowID]
    package var at: CFTimeInterval
    package var bundleId: String = ""
    package var homeDisplayID: CGDirectDisplayID? = nil
    package var fromSavedLayout = false
    package var iscustomsize = false

    package init(tags: UInt32, displayID: CGDirectDisplayID?, isfloating: Bool, isglobal: Bool, isoverlay: Bool,
                 isminimized: Bool, isScratchpad: Bool, isnamedscratchpad: Bool, floatFrame: CGRect,
                 scrollerProportion: CGFloat?, orderSnapshot: [CGWindowID], at: CFTimeInterval, bundleId: String = "",
                 homeDisplayID: CGDirectDisplayID? = nil, fromSavedLayout: Bool = false, iscustomsize: Bool = false) {
        self.tags = tags; self.displayID = displayID; self.isfloating = isfloating; self.isglobal = isglobal
        self.isoverlay = isoverlay; self.isminimized = isminimized; self.isScratchpad = isScratchpad
        self.isnamedscratchpad = isnamedscratchpad; self.floatFrame = floatFrame
        self.scrollerProportion = scrollerProportion; self.orderSnapshot = orderSnapshot; self.at = at
        self.bundleId = bundleId; self.homeDisplayID = homeDisplayID; self.fromSavedLayout = fromSavedLayout
        self.iscustomsize = iscustomsize
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
