import AppKit
import Mango

/// The window the port's panels over the screen stand in (the overview, the switcher, the scene panel,
/// the title-message bar): borderless and see-through, on every Space and over fullscreen apps, out of
/// the window cycle, without the mouse (the event tap gives mango the pointer) and without animation.
@MainActor
enum OverlayWindow {
    /// A window at `frame` (layout coordinates: top left, y down), not yet shown.
    static func make(frame: CGRect = .zero, level: NSWindow.Level, shadow: Bool = false) -> NSWindow {
        let window = NSWindow(contentRect: cocoa(frame), styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = level
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = shadow
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return window
    }

    /// A box in layout coordinates as AppKit has it (bottom left, y up).
    static func cocoa(_ r: CGRect) -> CGRect { Screens.flip(r, primaryHeight: Screens.primaryHeight) }
}

/// A view with mango's coordinates: y down.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
