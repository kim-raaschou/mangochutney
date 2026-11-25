import CoreGraphics

package struct InputState {
    package var keymode = "default"
    package var bindings: [KeyBinding] = []
    package var mouseBindings: [MouseBinding] = []
    package var axisBindings: [AxisBinding] = []
    package var axisBindApplyTimeout: UInt32 = 100
    package var overviewFrame: CGRect?
    /// mango's is_jump_mode on the selected monitor, and the jump_keycodes of its clients.
    package var jumpMode = false
    package var jumpKeycodes: Set<UInt16> = []
    package var switcherActive = false
    /// workspace_overview_is_active.
    package var workspaceOverviewActive = false
    package var wantsMouseMoved = false
    package var hoverResizeCursor: String?
}

package enum OverviewKey: Equatable {
    case escape
    case jump(UInt16)
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

// xkbcommon's keysyms the workspace overview reads (xkbcommon-keysyms.h); the port gives a key's keysym.
package let XKB_KEY_Escape: UInt32 = 0xff1b
package let XKB_KEY_Return: UInt32 = 0xff0d
package let XKB_KEY_KP_Enter: UInt32 = 0xff8d
package let XKB_KEY_Left: UInt32 = 0xff51
package let XKB_KEY_Up: UInt32 = 0xff52
package let XKB_KEY_Right: UInt32 = 0xff53
package let XKB_KEY_Down: UInt32 = 0xff54
package let XKB_KEY_h: UInt32 = 0x0068
package let XKB_KEY_j: UInt32 = 0x006a
package let XKB_KEY_k: UInt32 = 0x006b
package let XKB_KEY_l: UInt32 = 0x006c

/// wlroots' struct wlr_pointer_axis_event, what the workspace overview reads of it.
package struct WlrPointerAxisEvent {
    package var timeMsec: UInt32
    package var delta: Double
    package var deltaDiscrete: Int32
    package init(timeMsec: UInt32, delta: Double, deltaDiscrete: Int32) {
        self.timeMsec = timeMsec; self.delta = delta; self.deltaDiscrete = deltaDiscrete
    }
}
