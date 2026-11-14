import AppKit
import Mango

/// mango's MangoJumpLabel as the port draws it: a small panel above the overview, built the first
/// time it is shown.
@MainActor
final class JumpLabelNode: MangoJumpLabel {
    private let config: @MainActor () -> Config
    private var data: DecorateStyle
    private var text: String?
    private var origin = CGPoint.zero
    private var window: NSWindow?
    private(set) var enabled = false
    private(set) var logicalWidth: CGFloat = 0
    private(set) var logicalHeight: CGFloat = 0

    init(_ data: DecorateStyle, config: @escaping @MainActor () -> Config) {
        self.data = data
        self.config = config
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if enabled { draw() } else { window?.orderOut(nil) }
    }

    func setPosition(_ x: CGFloat, _ y: CGFloat) {
        origin = CGPoint(x: x, y: y)
        if enabled { draw() }
    }

    func raiseToTop() {
        if enabled { window?.orderFrontRegardless() }
    }

    func update(_ text: String, _ scale: Double) {
        self.text = text
        measure()
        if enabled { draw() }
    }

    func applyConfig(_ data: DecorateStyle) {
        self.data = data
        measure()
        if enabled { draw() }
    }

    func destroy() {
        window?.orderOut(nil)
        window?.close()
        window = nil
        enabled = false
    }

    private var look: JumpLabelLook {
        let config = config()
        return JumpLabelLook(text ?? "", decorate: MacOSAppearance.bar(data, set: config.jumplabeldata, config), side: 64,
                             ring: NSColor(calibratedRed: 0.79, green: 0.72, blue: 0.56, alpha: 1).cgColor)
    }

    private func measure() {
        guard let text, !text.isEmpty else { logicalWidth = 0; logicalHeight = 0; return }
        let size = look.size
        logicalWidth = size.width
        logicalHeight = size.height
    }

    private func draw() {
        guard let text else { return }
        let look = look
        let size = look.size
        let frame = CGRect(x: origin.x, y: Screens.primaryHeight - origin.y - size.height,
                           width: size.width, height: size.height)
        let win = window ?? Self.makeWindow()
        window = win
        let view = win.contentView!
        view.layer?.backgroundColor = look.background
        view.layer?.cornerRadius = look.cornerRadius
        view.layer?.borderColor = look.border
        view.layer?.borderWidth = look.borderWidth
        let label = view.subviews.first as! NSTextField
        label.stringValue = text
        label.font = look.font
        label.textColor = NSColor(cgColor: look.text) ?? .white
        label.frame = look.textFrame
        win.setFrame(frame, display: true)
        win.orderFrontRegardless()
    }

    private static func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .popUpMenu
        win.ignoresMouseEvents = true
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        view.autoresizesSubviews = false
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        view.addSubview(label)
        win.contentView = view
        return win
    }
}
