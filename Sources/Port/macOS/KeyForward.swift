import CoreGraphics
import Mango

/// Sends a key to one app, whether or not it is in front (CGEvent.postToPid): mango's
/// global_key_binding gives the key to a window that does not have the focus. The app
/// takes it as it takes any key, in its key window.
enum KeyForward {
    static func post(keyCode: UInt16, mods: Modifiers, down: Bool, to pid: pid_t) {
        guard let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: keyCode,
                              keyDown: down) else { return }
        var flags: CGEventFlags = []
        if mods.contains(.superKey) { flags.insert(.maskCommand) }
        if mods.contains(.ctrl) { flags.insert(.maskControl) }
        if mods.contains(.shift) { flags.insert(.maskShift) }
        if mods.contains(.alt) { flags.insert(.maskAlternate) }
        if mods.contains(.fn) { flags.insert(.maskSecondaryFn) }
        e.flags = flags
        e.postToPid(pid)
    }
}
