import AppKit
import Mango

@MainActor
final class OverviewOverlay {
    struct Card {
        var id: ClientID
        var frame: CGRect
        var label: String?
        var title: String
        var pid: pid_t
        var focused: Bool
    }

    private let window: NSWindow
    private let root: NSView
    private var layers: [ClientID: CALayer] = [:]
    private let workArea: CGRect
    private let focusColor: CGColor
    private let borderColor: CGColor
    private let jumpLook: DecorateStyle
    struct MangoLook {
        var root: RGBA
        var borderWidth: CGFloat
        var cornerRadius: CGFloat
    }
    private let mango: MangoLook?

    private let origin: CGPoint

    init(workArea: CGRect, top: CGFloat? = nil, focusColor: RGBA, borderColor: RGBA, jumpLook: DecorateStyle = DecorateStyle(),
         mango: MangoLook? = nil) {
        self.jumpLook = jumpLook
        self.mango = mango
        self.workArea = workArea
        origin = CGPoint(x: workArea.minX, y: min(top ?? workArea.minY, workArea.minY))
        self.focusColor = NSColor(red: focusColor.r, green: focusColor.g, blue: focusColor.b, alpha: 1).cgColor
        self.borderColor = NSColor(red: borderColor.r, green: borderColor.g, blue: borderColor.b,
                                   alpha: mango == nil ? 0.8 : borderColor.a).cgColor
        let h = Screens.primaryHeight
        let frame = CGRect(x: origin.x, y: h - workArea.maxY, width: workArea.width, height: workArea.maxY - origin.y)
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        root = FlippedView(frame: CGRect(origin: .zero, size: frame.size))
        root.wantsLayer = true
        if let mango {
            root.layer?.backgroundColor = NSColor(red: mango.root.r, green: mango.root.g, blue: mango.root.b, alpha: 1).cgColor
            window.contentView = root
        } else {
            let blur = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.addSubview(root)
            window.contentView = blur
        }
    }

    private func local(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX - origin.x, y: r.minY - origin.y, width: r.width, height: r.height)
    }

    func show(_ cards: [Card]) {
        update(cards)
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            window.animator().alphaValue = 1
        }
    }

    func update(_ cards: [Card]) {
        guard let rootLayer = root.layer else { return }
        let keep = Set(cards.map(\.id))
        for (id, l) in layers where !keep.contains(id) { l.removeFromSuperlayer(); layers.removeValue(forKey: id) }
        CATransaction.begin()
        CATransaction.setDisableActions(layers.isEmpty)
        for c in cards {
            let layer = layers[c.id] ?? makeCard(c, in: rootLayer)
            layer.frame = local(c.frame)
            layer.borderColor = c.focused ? focusColor : borderColor
            layer.borderWidth = mango?.borderWidth ?? (c.focused ? 3 : 1)
            layout(layer, c)
        }
        CATransaction.commit()
    }

    private func makeCard(_ c: Card, in parent: CALayer) -> CALayer {
        let l = CALayer()
        l.cornerRadius = mango?.cornerRadius ?? 10
        l.masksToBounds = true
        l.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 0.95).cgColor
        l.contentsGravity = mango == nil ? .resizeAspect : .resize
        let icon = CALayer()
        icon.name = "icon"
        icon.contents = NSRunningApplication(processIdentifier: c.pid)?.icon
        icon.contentsGravity = .resizeAspect
        l.addSublayer(icon)
        let title = CATextLayer()
        title.name = "title"
        title.string = c.title
        title.fontSize = 13
        title.foregroundColor = NSColor.secondaryLabelColor.cgColor
        title.alignmentMode = .center
        title.truncationMode = .end
        title.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        l.addSublayer(title)
        if let label = c.label {
            let badge = CALayer()
            badge.name = "badge"
            badge.setValue(label, forKey: "label")
            let t = CATextLayer()
            t.string = label
            t.alignmentMode = .center
            t.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            badge.addSublayer(t)
            l.addSublayer(badge)
        }
        parent.addSublayer(l)
        layers[c.id] = l
        return l
    }

    private func layout(_ l: CALayer, _ c: Card) {
        let b = l.bounds
        for s in l.sublayers ?? [] {
            switch s.name {
            case "icon":
                let side = min(64, b.width * 0.4, b.height * 0.4)
                s.frame = CGRect(x: b.midX - side / 2, y: b.midY - side / 2 - 10, width: side, height: side)
            case "title":
                s.frame = CGRect(x: 8, y: b.midY + side(b) / 2, width: b.width - 16, height: 18)
            case "badge":
                layoutBadge(s, on: Self.shownRect(of: l))
            default:
                break
            }
        }
    }

    private func side(_ b: CGRect) -> CGFloat { min(64, b.width * 0.4, b.height * 0.4) }

    static func shownRect(of l: CALayer) -> CGRect {
        let b = l.bounds
        guard let contents = l.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { return b }
        let image = contents as! CGImage
        guard image.width > 0, image.height > 0, b.width > 0, b.height > 0 else { return b }
        let scale = min(b.width / CGFloat(image.width), b.height / CGFloat(image.height))
        let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
        return CGRect(x: b.midX - w / 2, y: b.midY - h / 2, width: w, height: h)
    }

    static func badgeSide(for shown: CGRect) -> CGFloat {
        max(18, min(64, min(shown.width, shown.height) * 0.5))
    }

    private func layoutBadge(_ badge: CALayer, on shown: CGRect) {
        let label = badge.value(forKey: "label") as? String ?? ""
        let look = JumpLabelLook(label, decorate: jumpLook, side: Self.badgeSide(for: shown), ring: focusColor)
        badge.frame = CGRect(x: shown.midX - look.size.width / 2, y: shown.midY - look.size.height / 2,
                             width: look.size.width, height: look.size.height)
        badge.backgroundColor = look.background
        badge.borderColor = look.border
        badge.cornerRadius = look.cornerRadius
        badge.borderWidth = look.borderWidth
        if let t = badge.sublayers?.first as? CATextLayer {
            t.font = look.font
            t.fontSize = look.font.pointSize
            t.foregroundColor = look.text
            t.frame = look.textFrame
        }
    }

    func captureCards(scale: CGFloat) {
        let sizes = layers.mapValues { CGSize(width: $0.frame.width * scale, height: $0.frame.height * scale) }
        WindowSnapshot.capture(Array(layers.keys), pixelSize: sizes) { [weak self] id, image in
            self?.setImage(image, for: id)
        }
    }

    func setImage(_ image: CGImage, for id: ClientID) {
        guard let l = layers[id] else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        l.contents = image
        for s in l.sublayers ?? [] where s.name == "icon" || s.name == "title" { s.isHidden = true }
        for s in l.sublayers ?? [] where s.name == "badge" { layoutBadge(s, on: Self.shownRect(of: l)) }
        CATransaction.commit()
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
