import AppKit
import Mango

/// not in mango: mangonag (mangonag/mangonag.c) inside mango's process, as a panel. mango runs
/// it as a Wayland client on a layer surface, drawn with cairo and pango; here AppKit draws the
/// same bar: its options, colours, four lines, ANSI colours and buttons. With chutney_style the
/// port's look instead (docs/afvigelser.md §3).
@MainActor
public final class Nag {
    struct NagType {
        var background: UInt32, text: UInt32, buttonBackground: UInt32, buttonText: UInt32
        var border: UInt32, borderBottom: UInt32
    }

    nonisolated static let typeError = NagType(background: 0x201B14FF, text: 0xE1D1B6FF, buttonBackground: 0x3A332AFF,
                                   buttonText: 0xE1D1B6FF, border: 0xEF2929FF, borderBottom: 0xEF2929FF)
    nonisolated static let typeWarning = NagType(background: 0xFFA800FF, text: 0x000000FF, buttonBackground: 0xFFC100FF,
                                     buttonText: 0x000000FF, border: 0xAB7100FF, borderBottom: 0xAB7100FF)
    nonisolated static let typeInfo = NagType(background: 0x323232FF, text: 0xFFFFFFFF, buttonBackground: 0x333333FF,
                                  buttonText: 0xFFFFFFFF, border: 0x222222FF, borderBottom: 0x444444FF)

    struct NagButton {
        var text: String
        var action: String?
        var terminal: Bool
        var dismiss: Bool
        var outer = CGRect.zero
    }

    enum Edge { case top, bottom }

    /// mangonag's struct nag, what its options set.
    struct Options {
        var message: String?
        var details: String?
        var type = Nag.typeError
        var edge = Edge.top
        var outputName: String?
        var font = "monospace 13"
        var dismissText: String? = "X"
        var buttons: [NagButton] = []
        var timeoutMs = 0
    }

    static let maxLines = 4

    private var panel: NSPanel?
    private var timeout: DispatchWorkItem?

    public init() {}

    /// mangonag's main: its options read as getopt does, and the bar shown.
    public func spawn(_ argv: [String], input: String, macOS: Bool = false) {
        kill()
        var o = Options()
        var i = 1
        func next() -> String? { i += 1; return i < argv.count ? argv[i] : nil }
        while i < argv.count {
            let a = argv[i]
            switch a {
            case "-m", "--message": o.message = next()
            case "-l", "--detailed-message": o.details = input
            case "-t", "--type":
                switch next() {
                case "warning": o.type = Nag.typeWarning
                case "info": o.type = Nag.typeInfo
                default: o.type = Nag.typeError
                }
            case "-e", "--edge": if next() == "bottom" { o.edge = .bottom }
            case "-y", "--layer": _ = next()
            case "-o", "--output": o.outputName = next()
            case "-f", "--font": if let f = next() { o.font = f }
            case "-s", "--dismiss-button": o.dismissText = next()
            case "-b", "--button", "-B", "--button-no-terminal", "-z", "--button-dismiss",
                 "-Z", "--button-dismiss-no-terminal":
                guard let text = next() else { break }
                var action: String?
                if i + 1 < argv.count, !argv[i + 1].hasPrefix("-") { action = next() }
                let terminal = ["-b", "--button", "-z", "--button-dismiss"].contains(a)
                let dismiss = ["-z", "--button-dismiss", "-Z", "--button-dismiss-no-terminal"].contains(a)
                o.buttons.append(NagButton(text: text, action: action, terminal: terminal, dismiss: dismiss))
            case "-T", "--timeout": o.timeoutMs = Int(next() ?? "") ?? 0
            default: break
            }
            i += 1
        }

        if let details = o.details {
            let a = o.message ?? ""
            o.message = a.isEmpty ? details : a + "\n" + details
        }

        if let d = o.dismissText, !d.isEmpty {
            o.buttons.append(NagButton(text: d, action: nil, terminal: false, dismiss: true))
        }

        var message = o.message ?? ""
        while let last = message.unicodeScalars.last, [" ", "\t", "\n", "\r"].contains(last) {
            message.unicodeScalars.removeLast()
        }
        o.message = Nag.limitLines(message, Nag.maxLines)

        show(o, macOS: macOS)
    }

    /// The bar gone (mango's nag_kill, mangonag leaving its loop).
    public func kill() {
        timeout?.cancel()
        timeout = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    // MARK: - The bar

    private func show(_ o: Options, macOS: Bool) {
        let screen = NSScreen.screens.first { $0.localizedName == o.outputName }
            ?? NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        guard let screen else { return }
        let view = NagView(options: o, macOS: macOS) { [weak self] b in self?.runAction(b) }
        // not in mango: under the menu bar (or above the Dock), where a layer surface's exclusive zone ends
        let vf = screen.visibleFrame
        let width = screen.frame.width
        let height = view.computeHeight()
        let y = o.edge == .top ? vf.maxY - height : vf.minY
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
        if o.timeoutMs > 0 {
            // A timer: mangonag's -T, only when asked for (the config errors' bar has none).
            let w = DispatchWorkItem { [weak self] in self?.kill() }
            timeout = w
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(o.timeoutMs), execute: w)
        }
    }

    /// mangonag's nag_run_action.
    private func runAction(_ button: NagButton) {
        if button.dismiss { kill() }
        guard let action = button.action, !action.isEmpty else { return }
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

    // MARK: - Text

    /// mangonag's nag_limit_lines.
    static func limitLines(_ text: String, _ maxLines: Int) -> String {
        let lines = text.components(separatedBy: "\n")
        if lines.count <= maxLines { return text }
        let keep = maxLines - 1
        return lines.prefix(keep).map { $0 + "\n" }.joined() + "\u{1B}[0m\u{2026} (+\(lines.count - keep) more)"
    }

    /// mangonag's nag_ansi_skip: the length of an escape sequence at `i`, or 0.
    static func ansiSkip(_ s: [Unicode.Scalar], _ i: Int) -> Int {
        guard i + 1 < s.count, s[i] == "\u{1B}", s[i + 1] == "[" else { return 0 }
        var j = i + 2
        while j < s.count, !(s[j].value >= 0x40 && s[j].value <= 0x7E) { j += 1 }
        return j < s.count ? j + 1 - i : 0
    }

    /// mangonag's nag_truncate_lines.
    static func truncateLines(_ text: String, _ maxChars: Int) -> String {
        text.components(separatedBy: "\n").map { line in
            let s = Array(line.unicodeScalars)
            var count = 0, i = 0, cut = s.count
            while i < s.count {
                let skip = ansiSkip(s, i)
                if skip > 0 { i += skip; continue }
                if count == maxChars { cut = i; break }
                count += 1
                i += 1
            }
            var out = String(String.UnicodeScalarView(s[..<cut]))
            if cut < s.count { out += "\u{1B}[0m\u{2026}" }
            return out
        }.joined(separator: "\n")
    }

    static let palette: [UInt32] = [
        0x262626FF, 0xDE5959FF, 0x84D082FF, 0xE9B959FF, 0xE9B959FF, 0xD5A7E0FF,
        0xA5DE86FF, 0xE1D1B6FF, 0xC6C09CFF, 0xF57474FF, 0xB3EC7BFF, 0xF1E69FFF,
        0xA3C1E0FF, 0xCAACC6FF, 0xF1E69FFF, 0xF4F4F3FF,
    ]

    /// mangonag's nag_color.
    static func color(_ index: Int) -> UInt32 {
        if index < 0 { return 0 }
        if index < 16 { return palette[index] }
        if index < 232 {
            let c = index - 16
            func v(_ x: Int) -> UInt32 { x != 0 ? UInt32(55 + x * 40) : 0 }
            return v(c / 36) << 24 | v((c / 6) % 6) << 16 | v(c % 6) << 8 | 0xFF
        }
        let v = UInt32(8 + (index - 232) * 10)
        return v << 24 | v << 16 | v << 8 | 0xFF
    }

    static func ns(_ c: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((c >> 24) & 0xFF) / 255, green: CGFloat((c >> 16) & 0xFF) / 255,
                blue: CGFloat((c >> 8) & 0xFF) / 255, alpha: CGFloat(c & 0xFF) / 255)
    }

    struct Style {
        var fg: UInt32?, bg: UInt32?, bold = false, dim = false, italic = false, underline = false
    }

    /// mangonag's nag_style_params.
    static func apply(_ params: String, to st: inout Style) {
        let values = params.isEmpty ? [] : params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        if values.isEmpty { st = Style(); return }
        var i = 0
        while i < values.count {
            let code = values[i]
            if code == 38 && i + 2 < values.count && values[i + 1] == 5 {
                st.fg = color(values[i + 2]); i += 2
            } else if code == 38 && i + 4 < values.count && values[i + 1] == 2 {
                st.fg = UInt32(values[i + 2]) << 24 | UInt32(values[i + 3]) << 16 | UInt32(values[i + 4]) << 8 | 0xFF; i += 4
            } else if code == 48 && i + 2 < values.count && values[i + 1] == 5 {
                st.bg = color(values[i + 2]); i += 2
            } else if code == 48 && i + 4 < values.count && values[i + 1] == 2 {
                st.bg = UInt32(values[i + 2]) << 24 | UInt32(values[i + 3]) << 16 | UInt32(values[i + 4]) << 8 | 0xFF; i += 4
            } else {
                switch code {
                case 0: st = Style()
                case 1: st.bold = true
                case 2: st.dim = true
                case 3: st.italic = true
                case 4: st.underline = true
                case 22: st.bold = false; st.dim = false
                case 23: st.italic = false
                case 24: st.underline = false
                case 39: st.fg = nil
                case 49: st.bg = nil
                case 30...37: st.fg = color(code - 30)
                case 90...97: st.fg = color(code - 90 + 8)
                case 40...47: st.bg = color(code - 40)
                case 100...107: st.bg = color(code - 100 + 8)
                default: break
                }
            }
            i += 1
        }
    }

    static let tags: [(String, UInt32, UInt32)] = [
        ("[ERROR]", 0x201B14FF, 0xEF2929FF), ("[WARN]", 0x201B14FF, 0xEAD96BFF),
        ("[INFO]", 0x201B14FF, 0x729FCFFF), ("[DEBUG]", 0x201B14FF, 0x8AE234FF),
    ]

    /// mangonag's nag_ansi_attrs: the text without escapes, with their colours.
    static func attributed(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let s = Array(text.unicodeScalars)
        var st = Style()
        var run = String.UnicodeScalarView()
        func attrs(_ st: Style) -> [NSAttributedString.Key: Any] {
            var f = font
            var traits: NSFontDescriptor.SymbolicTraits = []
            if st.bold { traits.insert(.bold) }
            if st.italic { traits.insert(.italic) }
            if !traits.isEmpty { f = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font }
            var fg = st.fg.map(ns) ?? color
            if st.dim { fg = fg.withAlphaComponent(fg.alphaComponent * 0x6000 / 0xFFFF) }
            var a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: fg]
            if let bg = st.bg { a[.backgroundColor] = ns(bg) }
            if st.underline { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            return a
        }
        func flush() {
            if !run.isEmpty { out.append(NSAttributedString(string: String(run), attributes: attrs(st))) }
            run = String.UnicodeScalarView()
        }
        var i = 0
        var lineStart = true
        while i < s.count {
            let skip = ansiSkip(s, i)
            if skip > 0 {
                if s[i + skip - 1] == "m" {
                    flush()
                    apply(String(String.UnicodeScalarView(s[(i + 2)..<(i + skip - 1)])), to: &st)
                }
                i += skip
                continue
            }
            if lineStart {
                lineStart = false
                let rest = String(String.UnicodeScalarView(s[i...]))
                if let tag = tags.first(where: { rest.hasPrefix($0.0) }) {
                    flush()
                    var t = tag.0
                    i += tag.0.unicodeScalars.count
                    if i < s.count, s[i] == ":" { t += ":"; i += 1 }
                    out.append(NSAttributedString(string: t, attributes: attrs(Style(fg: tag.1, bg: tag.2, bold: true))))
                    continue
                }
            }
            if s[i] == "\n" {
                flush()
                out.append(NSAttributedString(string: "\n", attributes: attrs(st)))
                st = Style()
                lineStart = true
                i += 1
                continue
            }
            run.append(s[i])
            i += 1
        }
        flush()
        return out
    }
}

/// mangonag's nag_compute_layout and nag_render.
private final class NagView: NSView {
    let o: Nag.Options
    let macOS: Bool
    var buttons: [Nag.NagButton]
    let onClick: (Nag.NagButton) -> Void
    let font: NSFont
    let padding: CGFloat = 8, borderThickness: CGFloat = 3, buttonBorder: CGFloat = 3
    let buttonPadding: CGFloat = 3, buttonGap: CGFloat = 20

    init(options: Nag.Options, macOS: Bool, onClick: @escaping (Nag.NagButton) -> Void) {
        o = options
        self.macOS = macOS
        buttons = options.buttons
        self.onClick = onClick
        // Port extension: not in mango. chutney_style's font.
        font = macOS ? .monospacedSystemFont(ofSize: 12, weight: .regular) : decorateFont(FontDescription(options.font))
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    var type: Nag.NagType {
        // Port extension: not in mango. chutney_style's colours.
        guard macOS else { return o.type }
        return Nag.NagType(background: 0xAD401FF5, text: 0xFFFFFFFF, buttonBackground: 0xFFFFFF33,
                           buttonText: 0xFFFFFFFF, border: 0xAD401F00, borderBottom: 0xAD401F00)
    }

    func size(_ s: String) -> CGSize { (s as NSString).size(withAttributes: [.font: font]) }

    func computeHeight() -> CGFloat {
        let text = Nag.attributed(o.message ?? "", font: font, color: .white)
        var maxHeight = ceil(text.boundingRect(with: CGSize(width: 100_000, height: 100_000),
                                               options: [.usesLineFragmentOrigin]).height) + padding * 2
        for b in buttons {
            let ideal = ceil(size(b.text).height) + buttonPadding * 2 + buttonBorder * 2 + borderThickness * 2
            if ideal > maxHeight { maxHeight = ideal }
        }
        return max(maxHeight, 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        let t = type
        Nag.ns(t.background).setFill()
        bounds.fill()

        var buttonsTotal: CGFloat = 0
        for b in buttons { buttonsTotal += ceil(size(b.text).width) + buttonPadding * 2 + buttonBorder * 2 }
        if buttons.count > 1 { buttonsTotal += CGFloat(buttons.count - 1) * buttonGap }

        let textAvail = max(32, bounds.width - borderThickness * 2 - padding * 2 - buttonsTotal - 24)
        let charW = max(1, Int(size("0000000000").width) / 10)
        let display = Nag.truncateLines(o.message ?? "", Int(textAvail) / charW)

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
            buttons[i].outer = outer
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
        let p = convert(event.locationInWindow, from: nil)
        if let b = buttons.first(where: { $0.outer.contains(p) }) { onClick(b) }
    }
}
