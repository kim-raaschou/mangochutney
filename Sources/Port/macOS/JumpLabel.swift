import AppKit
import Mango

/// Big letter badge for togglejump.
@MainActor
enum JumpLabel {
    static func make(_ text: String, centeredIn axRect: CGRect, look decorate: DecorateStyle = DecorateStyle()) -> NSWindow {
        let look = JumpLabelLook(text, decorate: decorate, side: 64,
                                 ring: NSColor(calibratedRed: 0.79, green: 0.72, blue: 0.56, alpha: 1).cgColor)
        let size = look.size
        let h = Screens.primaryHeight
        let frame = CGRect(x: axRect.midX - size.width / 2, y: h - axRect.midY - size.height / 2,
                           width: size.width, height: size.height)
        let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .popUpMenu
        win.ignoresMouseEvents = true
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true
        view.layer?.backgroundColor = look.background
        view.layer?.cornerRadius = look.cornerRadius
        view.layer?.borderColor = look.border
        view.layer?.borderWidth = look.borderWidth
        let label = NSTextField(labelWithString: text)
        label.font = look.font
        label.textColor = NSColor(cgColor: look.text) ?? .white
        label.alignment = .center
        label.frame = look.textFrame
        view.addSubview(label)
        win.contentView = view
        win.orderFrontRegardless()
        return win
    }
}

/// The jump labels of the moving-windows overview, one window each.
@MainActor
final class JumpLabelSet {
    private let windows: [NSWindow]

    /// `labels`: each letter and the card (AX coordinates) it goes on.
    init(_ labels: [(String, CGRect)], look: DecorateStyle) {
        windows = labels.map { JumpLabel.make($0.0, centeredIn: $0.1, look: look) }
    }

    func close() {
        for w in windows { w.orderOut(nil); w.close() }
    }
}
