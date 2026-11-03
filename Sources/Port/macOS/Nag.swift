import AppKit
import Mango

/// mango's `mangonag`: a bar listing config errors with Edit / Close buttons. Drawn as
/// mangonag's error bar (mangonag.c: its colours, monospace 13, a 3 px red outline,
/// outlined buttons), or in the port's style with chutney_style.
@MainActor
public final class Nag {
    private var panel: NSPanel?
    private var configURL: URL?

    public init() {}

    public func show(errors: [ConfigError], configURL: URL, macOS: Bool = false) {
        hide()
        self.configURL = configURL
        guard let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main else { return }
        let lines = errors.prefix(6).map { "\($0.file):\($0.line): \($0.message)" }
        let more = errors.count > 6 ? "\n… and \(errors.count - 6) more" : ""
        let text = "mango: config errors\n" + lines.joined(separator: "\n") + more
        let height = CGFloat(28 + 18 * min(errors.count + 1, 8))
        let vf = screen.visibleFrame
        let frame = CGRect(x: vf.minX, y: vf.maxY - height, width: vf.width, height: height)
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary]
        let v = NSView(frame: CGRect(origin: .zero, size: frame.size))
        v.wantsLayer = true
        // mangonag's error colours (type "error").
        func hex(_ s: String) -> NSColor { let c = parseColor(s)!; return NSColor(red: c.r, green: c.g, blue: c.b, alpha: c.a) }
        let text1 = hex("0xE1D1B6FF"), red = hex("0xEF2929FF")
        let mangoFont = decorateFont(FontDescription("monospace 13"))
        if macOS {
            v.layer?.backgroundColor = NSColor(calibratedRed: 0.68, green: 0.25, blue: 0.12, alpha: 0.96).cgColor
        } else {
            v.layer?.backgroundColor = hex("0x201B14FF").cgColor
            v.layer?.borderColor = red.cgColor
            v.layer?.borderWidth = 3
        }
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = macOS ? .monospacedSystemFont(ofSize: 12, weight: .regular) : mangoFont
        label.textColor = macOS ? .white : text1
        label.frame = CGRect(x: macOS ? 12 : 8, y: 6, width: frame.width - 200, height: frame.height - 12)
        v.addSubview(label)
        func button(_ title: String, _ action: Selector, x: CGFloat) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.frame = CGRect(x: x, y: frame.height - 34, width: 80, height: 26)
            if !macOS {
                // mangonag: the button in its background colour inside a 3 px red border.
                b.isBordered = false
                b.wantsLayer = true
                b.layer?.backgroundColor = hex("0x3A332AFF").cgColor
                b.layer?.borderColor = red.cgColor
                b.layer?.borderWidth = 3
                b.attributedTitle = NSAttributedString(string: title, attributes: [.font: mangoFont, .foregroundColor: text1])
            }
            return b
        }
        v.addSubview(button("Edit", #selector(editConfig), x: frame.width - 180))
        v.addSubview(button("Close", #selector(closeNag), x: frame.width - 92))
        p.contentView = v
        p.orderFrontRegardless()
        panel = p
    }

    public func hide() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    @objc private func editConfig() {
        if let u = configURL { NSWorkspace.shared.open(u) }
    }

    @objc private func closeNag() { hide() }
}
