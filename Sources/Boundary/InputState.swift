import CoreGraphics

package struct InputState {
    package var keymode = "default"
    package var bindings: [KeyBinding] = []
    package var mouseBindings: [MouseBinding] = []
    package var axisBindings: [AxisBinding] = []
    package var axisTimeout: Double = 0.1
    package var overviewFrame: CGRect?
    package var jumpLabels: [String]?
    package var overcircleActive = false
    package var switcherActive = false
    package var tagCombo = false
    package var wantsMouseMoved = false
    package var cursorHideOnKeypress = false
    package var hoverResizeCursor: String?
    package var capsHyper: Modifiers?
}

package enum OverviewKey: Equatable {
    case escape
    case jump(String)
}

package struct GlobalKey: Equatable {
    package var mods: Modifiers
    package var keyName: String
    package var pid: pid_t
}

package struct BarButton: Equatable {
    package var client: ClientID
    package var isTab: Bool
    package var onClose: Bool
    package init(client: ClientID, isTab: Bool, onClose: Bool) {
        self.client = client; self.isTab = isTab; self.onClose = onClose
    }
}

package struct WlrEdges: OptionSet, Hashable, Sendable {
    package let rawValue: UInt32
    package init(rawValue: UInt32) { self.rawValue = rawValue }
    package static let top = WlrEdges(rawValue: 1)
    package static let bottom = WlrEdges(rawValue: 2)
    package static let left = WlrEdges(rawValue: 4)
    package static let right = WlrEdges(rawValue: 8)
}

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
    return "se-resize"
}
