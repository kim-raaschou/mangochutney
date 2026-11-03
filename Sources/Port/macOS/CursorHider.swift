import CoreGraphics
import MangoPrivate
import Mango

/// Hides the pointer while mango is in the background (mango's cursor_hide_*), as the
/// macOS apps that hide an idle pointer do: the window server lets a connection with
/// "SetsCursorInBackground" hide it. The hide is counted; one show undoes it.
@MainActor
enum CursorHider {
    private(set) static var hidden = false
    private static var allowed = false

    static func hide() {
        guard !hidden else { return }
        if !allowed {
            let cid = SLSMainConnectionID()
            _ = SLSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
            allowed = true
        }
        CGDisplayHideCursor(CGMainDisplayID())
        hidden = true
    }

    static func show() {
        guard hidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        hidden = false
    }
}
