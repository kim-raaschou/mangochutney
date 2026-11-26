import AppKit
import Mango

@MainActor
final class TitleMessageBar {
    private let window: NSWindow
    private let container = GlassBacking(material: .hudWindow)
    private let view = TitleMessageBarView()

    init() {
        window = OverlayWindow.make(level: .popUpMenu, shadow: true)
        window.appearance = NSAppearance(named: .vibrantDark)
        container.addContent(view)
        window.contentView = container
    }

    func show(frame: CGRect, title: String, appid: String, style: DecorateDrawData) {
        view.title = title
        view.appid = appid
        view.style = style
        window.setFrame(OverlayWindow.cocoa(frame), display: false)
        view.frame = container.bounds
        container.materialHidden = style.focusBgColor != nil
        let r = min(CGFloat(style.cornerRadius ?? TitleMessageBarView.macRadius), min(frame.width, frame.height) / 2)
        container.cornerRadius = r
        view.needsDisplay = true
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    func close() {
        window.close()
    }
}

/// mango's MangoBarDecoration of type TitleMessageBar, drawn in its own window.
@MainActor
final class TitleMessageBarDecoration: MangoBarDecoration {
    private let bar = TitleMessageBar()
    private let config: @MainActor () -> Config
    private var data: DecorateDrawData
    private var frame = CGRect.zero
    private(set) var enabled = true
    private(set) var lastText: String?
    private(set) var lastScale = 0.0

    init(_ data: DecorateDrawData, config: @escaping @MainActor () -> Config) {
        self.data = data
        self.config = config
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if enabled { draw() } else { bar.hide() }
    }

    func setPosition(_ x: CGFloat, _ y: CGFloat) {
        frame.origin = CGPoint(x: x, y: y)
        draw()
    }

    func raiseToTop() { draw() }

    func update(_ text: String, _ scale: Double) {
        lastText = text
        lastScale = scale
        draw()
    }

    func setSize(_ width: CGFloat, _ height: CGFloat) {
        frame.size = CGSize(width: width, height: height)
        draw()
    }

    /// The bar is drawn focused, as mango always sets it.
    func setFocus(_ focused: Bool) {}

    /// The second line is drawn centred, as mango always sets it.
    func setCenterSecondaryLine(_ center: Bool) {}

    func applyConfig(_ data: DecorateDrawData) {
        self.data = data
        draw()
    }

    func destroy() { bar.close() }

    private func draw() {
        guard enabled, frame.width > 0, frame.height > 0, let text = lastText else { return }
        let cut = text.lastIndex(of: "\n")
        let title = cut.map { String(text[..<$0]) } ?? text
        let appid = cut.map { String(text[text.index(after: $0)...]) } ?? ""
        let config = config()
        bar.show(frame: frame, title: title, appid: appid,
                 style: MacOSAppearance.bar(data, set: config.titleMessageBardata, config))
    }
}

private final class TitleMessageBarView: NSView {
    static let macRadius = 12
    var title = ""
    var appid = ""
    var style = DecorateDrawData()

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        let border = CGFloat(max(0, style.borderWidth ?? 0))
        func radius(_ r: CGRect) -> CGFloat {
            min(CGFloat(style.cornerRadius ?? Self.macRadius), min(r.width, r.height) / 2)
        }
        if border > 0 {
            nsColor(style.borderColor ?? parseColor("0x3b4261ff")!).setFill()
            NSBezierPath(roundedRect: b, xRadius: radius(b), yRadius: radius(b)).fill()
        }
        let inner = b.insetBy(dx: border, dy: border)
        guard inner.width > 0, inner.height > 0 else { return }
        if let bg = style.focusBgColor {
            nsColor(bg).setFill()
            NSBezierPath(roundedRect: inner, xRadius: radius(inner), yRadius: radius(inner)).fill()
        } else if border > 0 {
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(roundedRect: inner, xRadius: radius(inner), yRadius: radius(inner)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        }

        let padX = CGFloat(style.paddingX ?? 12), padY = CGFloat(style.paddingY ?? 0)
        let avail = inner.insetBy(dx: padX, dy: padY)
        guard avail.width > 0, avail.height > 0 else { return }
        let mangoFont = style.fontDesc.map { decorateFont(FontDescription($0)) }
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: mangoFont ?? .systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: style.focusFgColor.map(nsColor) ?? .labelColor,
        ]
        let appidAttrs: [NSAttributedString.Key: Any] = [
            .font: mangoFont ?? .systemFont(ofSize: 12),
            .foregroundColor: style.focusFgColor.map(nsColor) ?? .labelColor,
        ]
        let lines = [(ellipsized(title, titleAttrs, width: avail.width), titleAttrs),
                     (ellipsized(appid, appidAttrs, width: avail.width), appidAttrs)]
        let sizes = lines.map { ($0.0 as NSString).size(withAttributes: $0.1) }
        let blockW = sizes.map(\.width).max() ?? 0
        let blockH = sizes.map(\.height).reduce(0, +)
        let x0 = avail.minX + max(0, (avail.width - blockW) / 2)
        var y = avail.minY + max(0, (avail.height - blockH) / 2)
        for (i, line) in lines.enumerated() {
            let x = i == 0 ? x0 : x0 + (blockW - sizes[i].width) / 2
            (line.0 as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: line.1)
            y += sizes[i].height
        }
    }

    private func ellipsized(_ s: String, _ attrs: [NSAttributedString.Key: Any], width: CGFloat) -> String {
        func w(_ t: String) -> CGFloat { (t as NSString).size(withAttributes: attrs).width }
        guard w(s) > width else { return s }
        var best = ""
        var prefix = ""
        for ch in s {
            prefix.append(ch)
            if w(prefix + "…") > width { break }
            best = prefix
        }
        return best + "…"
    }
}

func decorateFont(_ d: FontDescription) -> NSFont {
    let size = CGFloat(d.pixelSize)
    let weight: NSFont.Weight = switch d.weight {
    case .thin: .thin
    case .ultraLight: .ultraLight
    case .light: .light
    case .regular: .regular
    case .medium: .medium
    case .semiBold: .semibold
    case .bold: .bold
    case .ultraBold: .heavy
    case .heavy: .black
    }
    let managerWeight: Int = switch d.weight {
    case .thin: 2
    case .ultraLight: 3
    case .light: 4
    case .regular: 5
    case .medium: 6
    case .semiBold: 8
    case .bold: 9
    case .ultraBold: 10
    case .heavy: 11
    }
    func italicized(_ f: NSFont) -> NSFont { d.italic ? NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) : f }
    for family in d.families {
        switch family.lowercased() {
        case "monospace", "mono":
            return italicized(.monospacedSystemFont(ofSize: size, weight: weight))
        case "sans", "sans-serif", "system-ui":
            return italicized(.systemFont(ofSize: size, weight: weight))
        case "serif":
            if let f = NSFontManager.shared.font(withFamily: "Times New Roman", traits: d.italic ? .italicFontMask : [],
                                                 weight: managerWeight, size: size) { return f }
        default:
            if let f = NSFontManager.shared.font(withFamily: family, traits: d.italic ? .italicFontMask : [],
                                                 weight: managerWeight, size: size) { return f }
        }
    }
    return italicized(.systemFont(ofSize: size, weight: weight))
}

private func nsColor(_ c: RGBA) -> NSColor { NSColor(red: c.r, green: c.g, blue: c.b, alpha: c.a) }
