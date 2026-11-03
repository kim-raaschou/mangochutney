import CoreGraphics

/// A display (mango's wlr_output and its boxes), in AX coordinates (top-left origin, y down).
public struct Screen: Equatable, Sendable {
    public var displayID: CGDirectDisplayID
    public var name: String
    /// Full frame (`m->m` in mango).
    public var frame: CGRect
    /// Visible frame minus menu bar and dock (`m->w`).
    public var workArea: CGRect
    public var scale: Double
    public var isMain: Bool
    /// Refresh rate in mHz (wlr_output->refresh); 0: not known.
    public var refresh: Int32

    public init(displayID: CGDirectDisplayID, name: String, frame: CGRect, workArea: CGRect, scale: Double, isMain: Bool,
                refresh: Int32 = 0) {
        self.displayID = displayID; self.name = name; self.frame = frame
        self.workArea = workArea; self.scale = scale; self.isMain = isMain; self.refresh = refresh
    }
}
