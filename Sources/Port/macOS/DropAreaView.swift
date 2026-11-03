import AppKit
import Mango

/// mango's drop area: a rectangle in drop_color over the part of a tile a dragged window
/// will take, above every ordinary window (the one being dragged too: macOS keeps
/// putting that one on top while it drags it). Click-through; shown only during a drag.
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

    /// `area` in AX coordinates.
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
