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
    /// wlr_output->make, ->model, ->serial; nil: not known (NULL in wlroots).
    public var make: String?
    public var model: String?
    public var serial: String?
    /// wlr_output->transform: enum wl_output_transform (0 normal, 1-3 rotated 90/180/270, 4-7 flipped).
    public var transform: Int32 = 0

    public init(displayID: CGDirectDisplayID, name: String, frame: CGRect, workArea: CGRect, scale: Double, isMain: Bool,
                refresh: Int32 = 0, make: String? = nil, model: String? = nil, serial: String? = nil) {
        self.displayID = displayID; self.name = name; self.frame = frame
        self.workArea = workArea; self.scale = scale; self.isMain = isMain; self.refresh = refresh
        self.make = make; self.model = model; self.serial = serial
    }
}
