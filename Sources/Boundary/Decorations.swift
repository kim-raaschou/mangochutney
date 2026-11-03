import CoreGraphics

// What mango draws with the windows (its borders, bars, overlays), as the port is to draw
// it: mango decides, the port draws (docs/plan-kerne-backend.md, trin 6).

/// A window's border: mango's c->border with its colour and width (get_border_color,
/// c->bw) and the split indicator (client_draw_split_border).
public struct BorderSpec: Equatable {
    public var id: CGWindowID
    /// The window's frame (AX coordinates); the ring is drawn just outside it.
    public var frame: CGRect
    public var color: RGBA
    public var width: CGFloat
    /// The window's corner radius (the ring's inner edge follows it).
    public var radius: CGFloat
    /// mango's split indicator (dwindle_manual_split): the side of the ring where the
    /// next window splits this one, drawn in `split.color`.
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

/// A tab or group bar (mango's tab_bar / group_bar, tab.c): its place and its segments.
public struct TabStrip: Equatable {
    public struct Segment: Equatable {
        public var id: CGWindowID
        public var title: String
        public var focused: Bool
        /// The window's app, for its icon (`chutney_tab_bar_app_icons`).
        public var pid: pid_t = 0
        /// ⌘ is held: the number that picks this tab (`chutney_tab_bar_shortcuts`).
        public var shortcut: Int? = nil
    }
    /// The panel in AX coordinates (top-left origin): the tabs in its top `barHeight`,
    /// the rest reaching under the window so its rounded top corners sit on the bar's
    /// material and the tabs look like part of the window.
    public var frame: CGRect
    public var barHeight: CGFloat
    /// The window's corner radius: the bar's top corners follow it.
    public var cornerRadius: CGFloat
    public var segments: [Segment]
    /// The focused member: the panel is ordered right below it, above the other members.
    public var above: CGWindowID
    /// mango's group bar close button (group_bar_close_button_enable): one per segment.
    public var closeButton: CloseButton? = nil
    /// mango's strip: the segments alone, no panel under them (no chutney_style).
    public var plain = false

    public struct CloseButton: Equatable {
        public var size: CGFloat
        public var margin: CGFloat
        public var color: RGBA
    }
}

/// How mango's bars look: the focus colour and the decorate keys set.
public struct TabStripStyle: Equatable {
    /// mango's focus colour: the ring around the focused tab.
    public var accent: RGBA
    /// The ring's width (the windows' border width, 1-3 pt).
    public var accentWidth: CGFloat = 2
    public var appIcons = false
    /// mango's decorate keys that are set.
    public var decorate = DecorateStyle()
}

/// A window's card in the overview drawn as pictures (the real windows stay).
public struct OverviewCard: Equatable {
    public var id: ClientID
    public var frame: CGRect
    public var label: String?
    public var title: String
    /// The window's app, for its icon until the picture comes.
    public var pid: pid_t
    public var focused: Bool
}

/// How the overview's cards look: the focus and border colours, the jump labels'
/// decorate keys, and mango's own look (no chutney_style): the desktop's root_color behind
/// the cards, each card with its border (border_px, border_radius).
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

/// A tile of mango's switcher panel (switcher.c).
public struct SwitcherTile: Equatable {
    public var id: ClientID
    public var frame: CGRect
    /// The window's own size.
    public var size: CGSize
    public var pid: pid_t
    public var highlighted: Bool
}

/// The switcher's look: mango's focus and border colours, and whether the port's look
/// is on (chutney_style).
public struct SwitcherLook: Equatable {
    public var focus: RGBA
    public var border: RGBA
    public var macOS: Bool
}
