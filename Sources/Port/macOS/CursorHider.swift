import AppKit
import MangoPrivate
import Mango

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

    static func setCursor(_ name: String?) {
        allow()
        cursor(name).set()
    }

    static func prepareTapCursors() {
        guard tapCursors.isEmpty else { return }
        allow()
        tapCursors = Dictionary(uniqueKeysWithValues: names.map { ($0, cursor($0)) })
    }

    private static let names = ["col-resize", "row-resize", "grab", "n-resize", "s-resize", "e-resize", "w-resize",
                                "ne-resize", "nw-resize", "se-resize", "sw-resize"]
    nonisolated(unsafe) private static var tapCursors: [String: NSCursor] = [:]

    nonisolated static func setCursorFromTap(_ name: String) {
        tapCursors[name]?.perform(#selector(NSCursor.set))
    }

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
            default: return .crosshair
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
