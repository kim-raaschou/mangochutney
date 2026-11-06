import CoreGraphics

/// What the system's input needs from mango to decide on its own thread whether an event
/// is mango's: the bindings and key mode, and whether the overview, a jump, overcircle, the
/// switcher or a comboview is going on.
package struct InputState {
    package var keymode = "default"
    package var bindings: [KeyBinding] = []
    package var mouseBindings: [MouseBinding] = []
    package var axisBindings: [AxisBinding] = []
    package var axisTimeout: Double = 0.1
    /// The monitor showing the overview (nil: none).
    package var overviewFrame: CGRect?
    /// The jump labels on screen (togglejump), by name.
    package var jumpLabels: [String]?
    package var overcircleActive = false
    package var switcherActive = false
    package var tagCombo = false
    /// The pointer's moves are wanted (sloppy focus, hot area, cursor hiding).
    package var wantsMouseMoved = false
    package var cursorHideOnKeypress = false
    /// mango's hover_resize_edge: the pointer is on a border resize strip, with this cursor.
    package var hoverResizeCursor: String?
    /// xkb_rules_options caps:hyper: the modifiers Caps Lock held stands for (mango's
    /// hyper); nil: Caps Lock is no hyper key.
    package var capsHyper: Modifiers?
}

/// A key the overview takes.
package enum OverviewKey: Equatable {
    case escape
    /// A jump label (togglejump), by its name.
    case jump(String)
}

/// A window rule's global_key_binding whose window is there: its chord, and the app the
/// key goes to.
package struct GlobalKey: Equatable {
    package var mods: Modifiers
    /// mango's key name (the port finds its key codes).
    package var keyName: String
    package var pid: pid_t
}

/// Not in mango: a press on a bar the port draws (mango's node_at_point finds the bar node).
package struct BarButton: Equatable {
    package var client: ClientID
    package var isTab: Bool
    package var onClose: Bool
    package init(client: ClientID, isTab: Bool, onClose: Bool) {
        self.client = client; self.isTab = isTab; self.onClose = onClose
    }
}

/// wlroots enum wlr_edges.
package struct WlrEdges: OptionSet, Hashable, Sendable {
    package let rawValue: UInt32
    package init(rawValue: UInt32) { self.rawValue = rawValue }
    package static let top = WlrEdges(rawValue: 1)
    package static let bottom = WlrEdges(rawValue: 2)
    package static let left = WlrEdges(rawValue: 4)
    package static let right = WlrEdges(rawValue: 8)
}

/// wlroots wlr_xcursor_get_resize_name (xcursor/xcursor.c).
package func wlrXcursorGetResizeName(_ edges: WlrEdges) -> String {
    if edges.contains(.top) {
        if edges.contains(.right) { return "ne-resize" }
        if edges.contains(.left) { return "nw-resize" }
        return "n-resize"
    }
    if edges.contains(.bottom) {
        if edges.contains(.right) { return "se-resize" }
        if edges.contains(.left) { return "sw-resize" }
        return "s-resize"
    }
    if edges.contains(.right) { return "e-resize" }
    if edges.contains(.left) { return "w-resize" }
    return "se-resize"   // fallback
}
