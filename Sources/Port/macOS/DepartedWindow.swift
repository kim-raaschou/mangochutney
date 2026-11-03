import CoreGraphics
import Mango

/// Not in mango: what the port remembers of a window that went away (WindowMemory), given
/// back by the port when it comes back (MacEvents.windowDiscovered).
///
/// What mango knew about a window that went away. macOS can report windows gone and back
/// around sleep (all of them at once, after a wake by a charger): a window that comes back
/// with the same id gets its tag, place and learned minimum size again, instead of being
/// placed as a new window on the current tag and re-learning its size one refusal at a
/// time. Window ids are not reused within a login session.
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
    /// The client order when it left (index 0 = master), to put it back between the same
    /// neighbours. An index alone is wrong: windows leave one by one, so the ones that
    /// leave later have moved up, and two windows end up with the same index.
    package var orderSnapshot: [CGWindowID]
    package var at: CFTimeInterval
    /// Its app: a window id from the saved layout must still belong to it.
    package var bundleId: String = ""
    package var homeDisplayID: CGDirectDisplayID? = nil
    /// From the saved layout: kept until the window is found or the window server no
    /// longer has it, not for `keepFor` (an app may not answer, or the window may be on
    /// another Space, for longer than that).
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

    /// Not in mango: windows that leave and come back.
    /// Where `id` goes back into `order`: right after its nearest predecessor in
    /// `snapshot` that is in `order`, else right before its nearest successor that is,
    /// else at the end.
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
