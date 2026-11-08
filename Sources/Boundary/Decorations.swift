import CoreGraphics

public struct BorderSpec: Equatable {
    public var id: CGWindowID
    public var frame: CGRect
    public var color: RGBA
    public var width: CGFloat
    public var radius: CGFloat
    public var split: (side: SplitSide, color: RGBA)?
    public enum SplitSide: Equatable { case bottom, right }
    public init(id: CGWindowID, frame: CGRect, color: RGBA, width: CGFloat, radius: CGFloat,
                split: (side: SplitSide, color: RGBA)? = nil) {
        self.id = id; self.frame = frame; self.color = color; self.width = width; self.radius = radius
        self.split = split
    }
    public static func == (a: BorderSpec, b: BorderSpec) -> Bool {
        a.id == b.id && a.frame == b.frame && a.color == b.color && a.width == b.width && a.radius == b.radius
            && a.split?.side == b.split?.side && a.split?.color == b.split?.color
    }
}

public struct TabStrip: Equatable {
    public struct Segment: Equatable {
        public var id: CGWindowID
        public var title: String
        public var focused: Bool
        public var pid: pid_t = 0
        public var shortcut: Int? = nil
    }
    public var frame: CGRect
    public var barHeight: CGFloat
    public var cornerRadius: CGFloat
    public var segments: [Segment]
    public var above: CGWindowID
    public var closeButton: CloseButton? = nil
    public var plain = false

    public struct CloseButton: Equatable {
        public var size: CGFloat
        public var margin: CGFloat
        public var color: RGBA
    }
}

public struct TabStripStyle: Equatable {
    public var accent: RGBA
    public var accentWidth: CGFloat = 2
    public var appIcons = false
    public var decorate = DecorateStyle()
}

public struct OverviewCard: Equatable {
    public var id: ClientID
    public var frame: CGRect
    public var label: String?
    public var title: String
    public var pid: pid_t
    public var focused: Bool
}

public struct OverviewLook: Equatable {
    public var focusColor: RGBA
    public var borderColor: RGBA
    public var jumpLook: DecorateStyle
    public var mango: (root: RGBA, borderWidth: CGFloat, cornerRadius: CGFloat)?
    public static func == (a: OverviewLook, b: OverviewLook) -> Bool {
        a.focusColor == b.focusColor && a.borderColor == b.borderColor && a.jumpLook == b.jumpLook
            && a.mango?.root == b.mango?.root && a.mango?.borderWidth == b.mango?.borderWidth
            && a.mango?.cornerRadius == b.mango?.cornerRadius
    }
}

public struct SwitcherTile: Equatable {
    public var id: ClientID
    public var frame: CGRect
    public var size: CGSize
    public var pid: pid_t
    public var highlighted: Bool
}

public struct SwitcherLook: Equatable {
    public var focus: RGBA
    public var border: RGBA
    public var macOS: Bool
}
