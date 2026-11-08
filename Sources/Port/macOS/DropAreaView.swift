import AppKit
import Mango

@MainActor
final class DropAreaView {
    private let window: NSWindow

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.level = .floating
        window.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone, .transient]
        let view = NSView()
        view.wantsLayer = true
        window.contentView = view
    }

    func show(_ area: CGRect, color: RGBA) {
        let frame = CGRect(x: area.minX, y: Screens.primaryHeight - area.maxY, width: area.width, height: area.height)
        window.contentView?.layer?.backgroundColor = NSColor(red: color.r, green: color.g, blue: color.b, alpha: color.a).cgColor
        if window.frame != frame { window.setFrame(frame, display: true) }
        if !window.isVisible { window.orderFrontRegardless() }
    }

    func hide() {
        window.orderOut(nil)
    }
}
