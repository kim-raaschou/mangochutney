import AppKit
import ApplicationServices
import MangoPrivate
import Mango

public enum NativeFocus {
    public static func focus(windowID: CGWindowID, pid: pid_t, element: AXUIElement, raise: Bool = true,
                             completion: (@MainActor () -> Void)? = nil) {
        var psn = ProcessSerialNumber()
        if mango_GetProcessForPID(pid, &psn) == noErr {
            _ = _SLPSSetFrontProcessWithOptions(&psn, windowID, 0x200 )
            postFocusRecord(&psn, windowID: windowID, kind: 0x01)
            postFocusRecord(&psn, windowID: windowID, kind: 0x02)
        } else {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
        DispatchQueue.global(qos: .userInteractive).async {
            element.setMain()
            if raise { element.raise() }
            if let completion { DispatchQueue.main.async { MainActor.assumeIsolated { completion() } } }
        }
    }

    public static func focusOwn(windowID: CGWindowID) {
        var psn = ProcessSerialNumber()
        guard mango_GetProcessForPID(getpid(), &psn) == noErr else { NSApp.activate(); return }
        _ = _SLPSSetFrontProcessWithOptions(&psn, windowID, 0x200 )
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
