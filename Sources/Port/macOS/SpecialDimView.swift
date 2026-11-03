import AppKit
import Mango

/// mango's special dim (special_update_dim): a black rectangle at special_dim over the
/// whole monitor while the special tag is shown, under the special tag's windows and over
/// every other window. Like mango's, it takes the pointer: a click on it reaches no
/// window. A non-activating panel, so a click does not bring mango forward.
@MainActor
final class SpecialDimView {
    private let panel: NSPanel

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone, .transient]
    }

    /// Over the monitor `frame` (AX coordinates), just below `below` (the backmost special
    /// window), or in front of the ordinary windows when there is none.
    func show(frame: CGRect, alpha: Double, below: CGWindowID?) {
        let f = CGRect(x: frame.minX, y: Screens.primaryHeight - frame.maxY, width: frame.width, height: frame.height)
        panel.backgroundColor = NSColor(white: 0, alpha: alpha)
        if panel.frame != f { panel.setFrame(f, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
        if let below { panel.order(.below, relativeTo: Int(below)) } else { panel.orderFrontRegardless() }
    }

    func hide() {
        panel.orderOut(nil)
    }
}
