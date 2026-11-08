import AppKit
import Mango

@MainActor
final class SwitcherPanel {
    struct Tile {
        var id: ClientID
        var frame: CGRect
        var size: CGSize
        var pid: pid_t
        var highlighted: Bool
    }

    struct Style {
        var focus: CGColor
        var border: CGColor
        var macOS: Bool
        init(focus: RGBA, border: RGBA, macOS: Bool = true) {
            self.macOS = macOS
            self.focus = CGColor(red: focus.r, green: focus.g, blue: focus.b, alpha: macOS ? 1 : focus.a)
            self.border = CGColor(red: border.r, green: border.g, blue: border.b, alpha: macOS ? 0.8 : border.a)
        }
    }

    static let mangoPanelColor = CGColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 0.92)

    private let window: NSWindow
    private let origin: CGPoint
    private let style: Style
    private var layers: [ClientID: CALayer] = [:]

    init(panel: CGRect, tiles: [Tile], style: Style, scale: CGFloat) {
        origin = panel.origin
        self.style = style
        window = NSWindow(contentRect: cocoaRect(panel), styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .popUpMenu
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = style.macOS
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let root = FlippedView(frame: CGRect(origin: .zero, size: panel.size))
        root.wantsLayer = true
        if style.macOS {
            let glass = GlassBacking(material: .hudWindow, cornerRadius: 18)
            glass.frame = CGRect(origin: .zero, size: panel.size)
            glass.addContent(root)
            window.contentView = glass
        } else {
            root.layer?.backgroundColor = Self.mangoPanelColor
            window.contentView = root
        }

        let pad = CGFloat(SwitcherLayout.pad)
        let pictures = style.macOS ? Self.pictureFrames(tiles)
                                   : Dictionary(uniqueKeysWithValues: tiles.map { ($0.id, $0.frame.insetBy(dx: pad, dy: pad)) })
        for t in tiles { root.layer?.addSublayer(makeTile(t, picture: pictures[t.id] ?? t.frame)) }
        highlight(tiles)
        window.orderFrontRegardless()

        guard WindowSnapshot.hasPermission else { return }
        let sizes = pictures.mapValues { CGSize(width: $0.width * scale, height: $0.height * scale) }
        WindowSnapshot.capture(tiles.map(\.id), pixelSize: sizes) { [weak self] id, image in
            self?.setImage(image, for: id)
        }
    }

    static func pictureFrames(_ tiles: [Tile]) -> [ClientID: CGRect] {
        let pad = CGFloat(SwitcherLayout.pad)
        let largest = tiles.map { $0.size.width * $0.size.height }.max() ?? 0
        var out: [ClientID: CGRect] = [:]
        for t in tiles {
            let box = t.frame.insetBy(dx: pad, dy: pad)
            let fit = WindowSnapshot.fitted(t.size, in: box.size)
            let k = smallScale(area: t.size.width * t.size.height, largest: largest)
            let size = CGSize(width: (fit.width * k).rounded(), height: (fit.height * k).rounded())
            out[t.id] = CGRect(x: (box.midX - size.width / 2).rounded(), y: (box.midY - size.height / 2).rounded(),
                               width: size.width, height: size.height)
        }
        return out
    }

    static func smallScale(area: CGFloat, largest: CGFloat) -> CGFloat {
        guard area > 0, largest > 0 else { return 1 }
        return max(0.6, min(1, pow(area / largest, 0.25)))
    }

    private func local(_ r: CGRect) -> CGRect { r.offsetBy(dx: -origin.x, dy: -origin.y) }

    private func makeTile(_ t: Tile, picture frame: CGRect) -> CALayer {
        let l = CALayer()
        l.frame = local(t.frame)
        l.cornerRadius = style.macOS ? 10 : 0
        l.masksToBounds = true
        l.backgroundColor = style.macOS ? NSColor(calibratedWhite: 0.16, alpha: 0.95).cgColor : nil
        let picture = CALayer()
        picture.name = "picture"
        picture.frame = frame.offsetBy(dx: -t.frame.minX, dy: -t.frame.minY)
        picture.contentsGravity = style.macOS ? .resizeAspect : .resize
        picture.backgroundColor = style.macOS ? nil : Self.mangoPanelColor
        picture.cornerRadius = style.macOS ? 6 : 0
        picture.masksToBounds = true
        l.addSublayer(picture)
        let icon = CALayer()
        icon.name = "icon"
        icon.contents = NSRunningApplication(processIdentifier: t.pid)?.icon
        icon.contentsGravity = .resizeAspect
        let side = min(64, l.bounds.width * 0.4, l.bounds.height * 0.4)
        icon.frame = CGRect(x: l.bounds.midX - side / 2, y: l.bounds.midY - side / 2, width: side, height: side)
        l.addSublayer(icon)
        layers[t.id] = l
        return l
    }

    func highlight(_ tiles: [Tile]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for t in tiles {
            guard let l = layers[t.id] else { continue }
            if style.macOS {
                l.borderColor = t.highlighted ? style.focus : style.border
                l.borderWidth = t.highlighted ? 3 : 1
            } else {
                l.backgroundColor = t.highlighted ? style.focus : style.border
            }
        }
        CATransaction.commit()
    }

    private func setImage(_ image: CGImage, for id: ClientID) {
        guard let l = layers[id] else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        for s in l.sublayers ?? [] {
            if s.name == "picture" { s.contents = image }
            if s.name == "icon" { s.isHidden = true }
        }
        CATransaction.commit()
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }
}

@MainActor
final class TitleMessageBar {
    private let window: NSWindow
    private let container = GlassBacking(material: .hudWindow)
    private let view = TitleMessageBarView()

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .popUpMenu
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.appearance = NSAppearance(named: .vibrantDark)
        container.addContent(view)
        window.contentView = container
    }

    func show(frame: CGRect, title: String, appid: String, style: DecorateStyle) {
        view.title = title
        view.appid = appid
        view.style = style
        window.setFrame(cocoaRect(frame), display: false)
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
}

private final class TitleMessageBarView: NSView {
    static let macRadius = 12
    var title = ""
    var appid = ""
    var style = DecorateStyle()

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

private func cocoaRect(_ r: CGRect) -> CGRect {
    CGRect(x: r.minX, y: Screens.primaryHeight - r.maxY, width: r.width, height: r.height)
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
