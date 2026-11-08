import AppKit
import Mango

/// not in mango: mangonag's Wayland side (NagDisplay). mangonag's code
/// (Sources/Mango/mangonag) runs in mango's process; here AppKit places the bar and draws it
/// where mango's mangonag draws a layer surface with cairo and pango, gives mangonag's handlers
/// the pointer, and runs its loop. With chutney_style the port's look instead
/// (docs/afvigelser.md §3).
@MainActor
public final class Nag: NagDisplay {
    /// Port extension: not in mango. chutney_style's look (set before each bar).
    var macOS = false

    private var panel: NSPanel?
    private var timeout: DispatchWorkItem?

    public init() {}

    /// mango's nag_spawn (error_nag.c): the fork and exec of mangonag, here its main in mango's
    /// process.
    public func spawn(_ argv: [String], input: String, macOS: Bool = false) {
        kill()
        self.macOS = macOS
        mangonagMain(argv, stdin: input, display: self)
    }

    /// mango's nag_kill (error_nag.c): SIGTERM, and mangonag's loop ends in nag_destroy.
    public func kill() {
        guard Mango.nag.display === self else { return }
        nagSignal(SIGTERM)
        loop()
    }

    /// mangonag's loop in main, one turn: `while (nag.running)`, then nag_destroy.
    private func loop() {
        if !Mango.nag.running { nagDestroy() }
    }

    // MARK: - NagDisplay

    public func nagSetupSurface() {
        let n = Mango.nag
        let screen = NSScreen.screens.first { $0.localizedName == n.outputName }
            ?? NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        guard let screen else { return }
        let view = NagView(macOS: macOS) { [weak self] p in
            // wl_pointer's motion and button, then the loop's check
            nagPointerMotion(Double(p.x), Double(p.y))
            nagPointerButton(btnLeft, pressed: true)
            self?.loop()
        }
        // not in mango: under the menu bar (or above the Dock), where a layer surface's exclusive zone ends
        let vf = screen.visibleFrame
        let width = screen.frame.width
        let height = view.computeHeight()
        let y = n.edge == .top ? vf.maxY - height : vf.minY
        let frame = CGRect(x: screen.frame.minX, y: y, width: width, height: height)
        view.frame = CGRect(origin: .zero, size: frame.size)
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary]
        p.contentView = view
        p.orderFrontRegardless()
        panel = p
        if n.timeoutMs > 0 {
            // A timer: mangonag's -T (its poll timeout), only when asked for (the config errors' bar has none).
            let w = DispatchWorkItem { nagDestroy() }
            timeout = w
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(n.timeoutMs)), execute: w)
        }
    }

    public func nagDestroySurface() {
        timeout?.cancel()
        timeout = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    public func nagFork(_ button: NagButton) {
        guard let action = button.action else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        if !button.terminal {
            p.arguments = ["-c", action]
        } else {
            // not in mango: a script Terminal can open (.command), and Terminal when no terminal of
            // mango's list is there (mango runs it in sh; vi without a terminal cannot work)
            var template = Array("/tmp/mangonag-XXXXXX.command".utf8CString)
            let fd = template.withUnsafeMutableBufferPointer { mkstemps($0.baseAddress!, 8) }
            guard fd >= 0 else {
                p.arguments = ["-c", action]
                try? p.run()
                return
            }
            let script = String(cString: template)
            let body = "#!/bin/sh\nrm -f \(script)\n\(action)\n"
            _ = body.withCString { write(fd, $0, strlen($0)) }
            fchmod(fd, S_IRUSR | S_IWUSR | S_IXUSR)
            close(fd)
            p.arguments = ["-c",
                "term=\"$TERMINAL\"; if [ -z \"$term\" ]; then for t in foot alacritty kitty wezterm st xterm; do "
                + "command -v \"$t\" >/dev/null 2>&1 && term=\"$t\" && break; done; fi; "
                + "if [ -n \"$term\" ]; then exec \"$term\" -e \(script); else exec open -a Terminal \(script); fi"]
        }
        try? p.run()
    }

    // MARK: - Cairo and pango

    /// mangonag's rgba_to_cairo.
    static func ns(_ c: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((c >> 24) & 0xFF) / 255, green: CGFloat((c >> 16) & 0xFF) / 255,
                blue: CGFloat((c >> 8) & 0xFF) / 255, alpha: CGFloat(c & 0xFF) / 255)
    }

    /// mangonag's nag_layout_markup: nag_ansi_attrs' clean text with its attributes as pango's.
    static func attributed(_ text: String?, font: NSFont, color: NSColor) -> NSAttributedString {
        var clean = ""
        let attrs = nagAnsiAttrs(text, &clean)
        let out = NSMutableAttributedString(string: clean, attributes: [.font: font, .foregroundColor: color])
        let u = clean.utf8
        for a in attrs {
            let range = NSRange(u.index(u.startIndex, offsetBy: a.start)..<u.index(u.startIndex, offsetBy: a.end), in: clean)
            var traits: NSFontDescriptor.SymbolicTraits = []
            if a.bold { traits.insert(.bold) }
            if a.italic { traits.insert(.italic) }
            if !traits.isEmpty {
                let f = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
                out.addAttribute(.font, value: f, range: range)
            }
            var fg = a.foreground.map { ns($0 | 0xFF) } ?? color
            if let alpha = a.foregroundAlpha { fg = fg.withAlphaComponent(fg.alphaComponent * CGFloat(alpha) / 0xFFFF) }
            out.addAttribute(.foregroundColor, value: fg, range: range)
            if let bg = a.background { out.addAttribute(.backgroundColor, value: ns(bg | 0xFF), range: range) }
            if a.underline { out.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
        }
        return out
    }
}

/// mangonag's nag_compute_layout and nag_render, from `nag`.
private final class NagView: NSView {
    let macOS: Bool
    let onClick: (CGPoint) -> Void
    let font: NSFont
    let padding: CGFloat = 8, borderThickness: CGFloat = 3, buttonBorder: CGFloat = 3
    let buttonPadding: CGFloat = 3, buttonGap: CGFloat = 20

    init(macOS: Bool, onClick: @escaping (CGPoint) -> Void) {
        self.macOS = macOS
        self.onClick = onClick
        // Port extension: not in mango. chutney_style's font.
        font = macOS ? .monospacedSystemFont(ofSize: 12, weight: .regular)
            : decorateFont(FontDescription(Mango.nag.font ?? "monospace 13"))
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    var type: NagType {
        // Port extension: not in mango. chutney_style's colours.
        guard macOS else { return Mango.nag.type }
        return NagType(background: 0xAD401FF5, text: 0xFFFFFFFF, buttonBackground: 0xFFFFFF33,
                       buttonText: 0xFFFFFFFF, border: 0xAD401F00, borderBottom: 0xAD401F00)
    }

    func size(_ s: String) -> CGSize { (s as NSString).size(withAttributes: [.font: font]) }

    func computeHeight() -> CGFloat {
        let text = Nag.attributed(Mango.nag.message, font: font, color: .white)
        var maxHeight = ceil(text.boundingRect(with: CGSize(width: 100_000, height: 100_000),
                                               options: [.usesLineFragmentOrigin]).height) + padding * 2
        for b in Mango.nag.buttons {
            let ideal = ceil(size(b.text).height) + buttonPadding * 2 + buttonBorder * 2 + borderThickness * 2
            if ideal > maxHeight { maxHeight = ideal }
        }
        return max(maxHeight, 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        let t = type
        Nag.ns(t.background).setFill()
        bounds.fill()

        let buttons = Mango.nag.buttons
        var buttonsTotal: CGFloat = 0
        for b in buttons { buttonsTotal += ceil(size(b.text).width) + buttonPadding * 2 + buttonBorder * 2 }
        if buttons.count > 1 { buttonsTotal += CGFloat(buttons.count - 1) * buttonGap }

        let textAvail = max(32, bounds.width - borderThickness * 2 - padding * 2 - buttonsTotal - 24)
        let charW = max(1, Int(size("0000000000").width) / 10)
        let display = nagTruncateLines(Mango.nag.message, Int(textAvail) / charW)

        let text = Nag.attributed(display, font: font, color: Nag.ns(t.text))
        let textH = ceil(text.boundingRect(with: CGSize(width: 100_000, height: 100_000), options: [.usesLineFragmentOrigin]).height)
        text.draw(at: CGPoint(x: padding, y: floor((bounds.height - textH) / 2)))

        var x = bounds.width - borderThickness - 8
        for i in buttons.indices {
            let ts = size(buttons[i].text)
            let w = ceil(ts.width) + buttonPadding * 2, h = ceil(ts.height) + buttonPadding * 2
            let inner = CGRect(x: x - buttonBorder - ceil(ts.width) - buttonPadding * 2 + 1,
                               y: floor((bounds.height - h) / 2), width: w, height: h)
            let outer = inner.insetBy(dx: -buttonBorder, dy: -buttonBorder)
            if i < Mango.nag.buttons.count {
                Mango.nag.buttons[i].x = Int(inner.minX)
                Mango.nag.buttons[i].y = Int(inner.minY)
                Mango.nag.buttons[i].width = Int(inner.width)
                Mango.nag.buttons[i].height = Int(inner.height)
                Mango.nag.buttons[i].outerX = Int(outer.minX)
                Mango.nag.buttons[i].outerY = Int(outer.minY)
                Mango.nag.buttons[i].outerWidth = Int(outer.width)
                Mango.nag.buttons[i].outerHeight = Int(outer.height)
            }
            if macOS {
                // Port extension: not in mango. chutney_style's rounded buttons.
                Nag.ns(t.buttonBackground).setFill()
                NSBezierPath(roundedRect: outer, xRadius: 5, yRadius: 5).fill()
            } else {
                Nag.ns(t.border).setFill()
                outer.fill()
                Nag.ns(t.buttonBackground).setFill()
                inner.fill()
            }
            (buttons[i].text as NSString).draw(at: CGPoint(x: inner.minX + buttonPadding, y: inner.minY + buttonPadding),
                                               withAttributes: [.font: font, .foregroundColor: Nag.ns(t.buttonText)])
            x = outer.minX - buttonGap
        }

        guard !macOS else { return }
        Nag.ns(t.borderBottom).setFill()
        CGRect(x: 0, y: bounds.height - borderThickness, width: bounds.width, height: borderThickness).fill()
        Nag.ns(t.border).setStroke()
        let outline = NSBezierPath(rect: bounds.insetBy(dx: borderThickness / 2, dy: borderThickness / 2))
        outline.lineWidth = borderThickness
        outline.stroke()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick(convert(event.locationInWindow, from: nil))
    }
}
