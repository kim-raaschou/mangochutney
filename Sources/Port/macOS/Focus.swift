import AppKit
import ApplicationServices
import MangoPrivate
import Mango

public enum NativeFocus {
    /// Make a window key without the app raising all of its other windows
    /// (yabai / Hammerspoon technique), then AX-raise it unless `raise` is false
    /// (sloppy focus: focus follows the pointer but must not reorder windows,
    /// or a floating window hovered over a tile would flip above/below it).
    /// `completion` runs on the main thread after the window has been raised
    /// (borders must be re-stacked only then, or the app ends up above them).
    public static func focus(windowID: CGWindowID, pid: pid_t, element: AXUIElement, raise: Bool = true,
                             completion: (@MainActor () -> Void)? = nil) {
        var psn = ProcessSerialNumber()
        if mango_GetProcessForPID(pid, &psn) == noErr {
            _ = _SLPSSetFrontProcessWithOptions(&psn, windowID, 0x200 /* kCPSUserGenerated */)
            postFocusRecord(&psn, windowID: windowID, kind: 0x01)
            postFocusRecord(&psn, windowID: windowID, kind: 0x02)
        } else {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
        // setMain / raise are synchronous IPC to the app (30 to 80 ms in an app that is
        // being activated): off the main thread, and not on the app's write queue, whose
        // animation frames for this very window would wait behind them.
        DispatchQueue.global(qos: .userInteractive).async {
            element.setMain()
            if raise { element.raise() }
            if let completion { DispatchQueue.main.async { MainActor.assumeIsolated { completion() } } }
        }
    }

    /// Not in mango: one of mango's own windows (the hotkeys palette) to the front and key, the
    /// way other apps' windows are focused. NSApp.activate is a request macOS refuses to an
    /// app in the background, and a window of an app that is not active gets no keys.
    public static func focusOwn(windowID: CGWindowID) {
        var psn = ProcessSerialNumber()
        guard mango_GetProcessForPID(getpid(), &psn) == noErr else { NSApp.activate(); return }
        _ = _SLPSSetFrontProcessWithOptions(&psn, windowID, 0x200 /* kCPSUserGenerated */)
        postFocusRecord(&psn, windowID: windowID, kind: 0x01)
        postFocusRecord(&psn, windowID: windowID, kind: 0x02)
    }

    private static func postFocusRecord(_ psn: inout ProcessSerialNumber, windowID: CGWindowID, kind: UInt8) {
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0x04] = 0xF8
        bytes[0x08] = kind
        bytes[0x3a] = 0x10
        var wid = windowID
        withUnsafeBytes(of: &wid) { b in for i in 0..<4 { bytes[0x3c + i] = b[i] } }
        for i in 0x20..<0x30 { bytes[i] = 0xFF }
        _ = SLPSPostEventRecordTo(&psn, bytes)
    }

    public static func warpCursor(to p: CGPoint) {
        CGWarpMouseCursorPosition(p)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
