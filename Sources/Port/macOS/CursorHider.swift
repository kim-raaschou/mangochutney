import AppKit
import MangoPrivate
import Mango

/// Hides the pointer while mango is in the background (mango's cursor_hide_*), as the
/// macOS apps that hide an idle pointer do: the window server lets a connection with
/// "SetsCursorInBackground" hide it. The hide is counted; one show undoes it. The same lets
/// mango set the cursor over another app's window (its border resize strips).
@MainActor
enum CursorHider {
    private(set) static var hidden = false
    private static var allowed = false

    private static func allow() {
        guard !allowed else { return }
        let cid = SLSMainConnectionID()
        _ = SLSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        allowed = true
    }

    static func hide() {
        guard !hidden else { return }
        allow()
        CGDisplayHideCursor(CGMainDisplayID())
        hidden = true
    }

    /// wlr_cursor_set_xcursor: the cursor by its xcursor name, also over another app's
    /// window ("SetsCursorInBackground"). nil: the arrow, a near equivalent of wlroots giving the
    /// cursor back to the client (an app sets its own again only as the pointer enters its parts).
    static func setCursor(_ name: String?) {
        allow()
        cursor(name).set()
    }

    /// Before the event tap starts: the cursors it sets, made here (main thread) once.
    static func prepareTapCursors() {
        guard tapCursors.isEmpty else { return }
        allow()
        tapCursors = Dictionary(uniqueKeysWithValues: names.map { ($0, cursor($0)) })
    }

    private static let names = ["col-resize", "row-resize", "grab", "n-resize", "s-resize", "e-resize", "w-resize",
                                "ne-resize", "nw-resize", "se-resize", "sw-resize"]
    /// The cursors by name, made on the main thread for the event tap's.
    nonisolated(unsafe) private static var tapCursors: [String: NSCursor] = [:]

    /// The cursor set on the event tap's thread as the pointer moves, before the app under it
    /// has the move: wlroots draws the cursor image where the pointer is at once; set later, on
    /// the main thread, the app's own cursor shows between the two.
    nonisolated static func setCursorFromTap(_ name: String) {
        tapCursors[name]?.perform(#selector(NSCursor.set))
    }

    /// wlr_scene_node_at, its surface: the window under `p` the window server would give a
    /// click; nil for mango's own windows (its borders and bars are scene nodes in mango).
    static func windowAt(_ p: CGPoint) -> ClientID? {
        let cid = SLSMainConnectionID()
        var sp = p, wp = CGPoint.zero
        var wid: UInt32 = 0, wcid: Int32 = 0
        _ = SLSFindWindowAndOwner(cid, 0, 1, 0, &sp, &wp, &wid, &wcid)
        return wid == 0 || wcid == cid ? nil : wid
    }

    static func cursor(_ name: String?) -> NSCursor {
        switch name {
        case "col-resize": return .resizeLeftRight
        case "row-resize": return .resizeUpDown
        case "grab": return .closedHand
        case "n-resize", "s-resize", "e-resize", "w-resize", "ne-resize", "nw-resize", "se-resize", "sw-resize":
            if #available(macOS 15, *) {
                let position: NSCursor.FrameResizePosition = switch name {
                case "n-resize": .top
                case "s-resize": .bottom
                case "e-resize": .right
                case "w-resize": .left
                case "ne-resize": .topRight
                case "nw-resize": .topLeft
                case "se-resize": .bottomRight
                default: .bottomLeft
                }
                return .frameResize(position: position, directions: .all)
            }
            switch name {
            case "n-resize", "s-resize": return .resizeUpDown
            case "e-resize", "w-resize": return .resizeLeftRight
            default: return .crosshair   // macOS 14 has no diagonal resize cursor
            }
        default:
            return .arrow
        }
    }


    static func show() {
        guard hidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        hidden = false
    }
}
