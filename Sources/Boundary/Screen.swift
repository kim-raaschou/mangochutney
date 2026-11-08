import CoreGraphics

public struct Screen: Equatable, Sendable {
    public var displayID: CGDirectDisplayID
    public var name: String
    public var frame: CGRect
    public var workArea: CGRect
    public var scale: Double
    public var isMain: Bool
    public var refresh: Int32
    public var make: String?
    public var model: String?
    public var serial: String?
    public var transform: Int32 = 0

    public init(displayID: CGDirectDisplayID, name: String, frame: CGRect, workArea: CGRect, scale: Double, isMain: Bool,
                refresh: Int32 = 0, make: String? = nil, model: String? = nil, serial: String? = nil) {
        self.displayID = displayID; self.name = name; self.frame = frame
        self.workArea = workArea; self.scale = scale; self.isMain = isMain; self.refresh = refresh
        self.make = make; self.model = model; self.serial = serial
    }
}
