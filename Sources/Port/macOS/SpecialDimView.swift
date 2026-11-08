import AppKit
import Mango

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
