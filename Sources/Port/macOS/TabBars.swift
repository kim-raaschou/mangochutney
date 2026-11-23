import AppKit
import Mango

/// Where the port's tab and group bars are drawn: AppKit panels (TabBarManager), or the tests' record.
@MainActor
public protocol BarDrawing: AnyObject {
    var onSelect: ((CGWindowID) -> Void)? { get set }
    var onClose: ((CGWindowID) -> Void)? { get set }
    var onRightClick: ((CGWindowID) -> Void)? { get set }
    /// The bars shown now.
    func update(_ strips: [TabStrip], style: TabStripStyle, keyFocus: CGWindowID?)
    /// The bars put back below their windows, unless `inPlace` says one stands right already.
    func restack(_ ids: Set<CGWindowID>?, inPlace: (CGWindowID, CGWindowID) -> Bool)
}

public enum TabStripLayout {
    public static func segmentFrames(width: CGFloat, count: Int) -> [CGRect] {
        guard count > 0 else { return [] }
        let w = Int(width.rounded(.down))
        let base = w / count, rem = w % count
        var x = 0
        return (0..<count).map { i in
            let sw = base + (i < rem ? 1 : 0)
            defer { x += sw }
            return CGRect(x: CGFloat(x), y: 0, width: CGFloat(sw), height: 0)
        }
    }

}

@MainActor
public final class TabBarManager: BarDrawing {
    public var onSelect: ((CGWindowID) -> Void)?
    public var onClose: ((CGWindowID) -> Void)?
    public var onRightClick: ((CGWindowID) -> Void)?
    private var panels: [CGWindowID: (NSPanel, TabStripView, TabStrip)] = [:]
    /// Panels no strip uses now: ordered out and kept (a new one costs window server round trips and its
    /// glass a first layout).
    private var idle: [(NSPanel, TabStripView)] = []
    private var style: TabStripStyle?
    private var keyFocus: CGWindowID?

    public init() {}

    public func update(_ strips: [TabStrip], style: TabStripStyle, keyFocus: CGWindowID? = nil) {
        let restyle = style != self.style || keyFocus != self.keyFocus
        self.style = style
        self.keyFocus = keyFocus
        var seen: Set<CGWindowID> = []
        let wanted = Set(strips.map(\.above))
        var spare = panels.keys.filter { !wanted.contains($0) }
        for strip in strips where panels[strip.above] == nil {
            guard let from = spare.popLast(), let entry = panels.removeValue(forKey: from) else { break }
            entry.0.order(.below, relativeTo: Int(strip.above))
            panels[strip.above] = entry
        }
        for strip in strips {
            seen.insert(strip.above)
            if let (panel, view, old) = panels[strip.above] {
                if old != strip || restyle {
                    // a pure move: the segments (absolute) moved with the strip
                    var moved = old
                    let dx = strip.frame.minX - old.frame.minX, dy = strip.frame.minY - old.frame.minY
                    moved.frame.origin = strip.frame.origin
                    for i in moved.segments.indices {
                        moved.segments[i].frame.origin.x += dx
                        moved.segments[i].frame.origin.y += dy
                    }
                    apply(strip, to: panel, view: view, style: style, redraw: moved != strip || restyle)
                    panels[strip.above] = (panel, view, strip)
                }
            } else if let (panel, view) = idle.popLast() {
                apply(strip, to: panel, view: view, style: style)
                panel.orderFrontRegardless()
                panel.order(.below, relativeTo: Int(strip.above))
                panels[strip.above] = (panel, view, strip)
            } else {
                let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.level = .normal
                panel.becomesKeyOnlyIfNeeded = true
                panel.hidesOnDeactivate = false
                panel.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone, .transient]
                panel.isReleasedWhenClosed = false
                panel.animationBehavior = .none
                let view = TabStripView(frame: .zero)
                view.onClick = { [weak self] id in self?.onSelect?(id) }
                view.onClose = { [weak self] id in self?.onClose?(id) }
                view.onRightClick = { [weak self] id in self?.onRightClick?(id) }
                let container = GlassBacking(material: .headerView)
                container.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                container.addContent(view)
                panel.contentView = container
                apply(strip, to: panel, view: view, style: style)
                panel.orderFrontRegardless()
                panel.order(.below, relativeTo: Int(strip.above))
                panels[strip.above] = (panel, view, strip)
            }
        }
        for id in panels.keys where !seen.contains(id) {
            guard let (panel, view, _) = panels.removeValue(forKey: id) else { continue }
            panel.orderOut(nil)
            idle.append((panel, view))
        }
    }

    public func restack(_ ids: Set<CGWindowID>? = nil, inPlace: (CGWindowID, CGWindowID) -> Bool = { _, _ in false }) {
        for (id, (panel, _, _)) in panels where ids?.contains(id) ?? true {
            if !inPlace(CGWindowID(truncatingIfNeeded: panel.windowNumber), id) { panel.order(.below, relativeTo: Int(id)) }
        }
    }

    private func apply(_ strip: TabStrip, to panel: NSPanel, view: TabStripView, style: TabStripStyle,
                       redraw: Bool = true) {
        let h = Screens.primaryHeight
        panel.setFrame(CGRect(x: strip.frame.minX, y: h - strip.frame.maxY,
                              width: strip.frame.width, height: strip.frame.height), display: false)
        guard redraw else { return }
        if let glass = panel.contentView as? GlassBacking {
            glass.cornerRadius = strip.plain ? 0 : strip.cornerRadius
            glass.materialHidden = strip.plain
        }
        view.frame = panel.contentView?.bounds ?? .zero
        view.keyFocus = keyFocus
        view.show(strip, style: style)
    }
}

final class TabStripView: NSView {
    var onClick: ((CGWindowID) -> Void)?
    var onClose: ((CGWindowID) -> Void)?
    var onRightClick: ((CGWindowID) -> Void)?
    private var closeLayers: [CALayer] = []
    private var closeFrames: [CGRect] = []
    private var ids: [CGWindowID] = []
    private var frames: [CGRect] = []
    private var shown: (TabStrip, TabStripStyle)?
    var keyFocus: CGWindowID?
    private var shownKeyFocus: CGWindowID?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if let (strip, style) = shown { show(strip, style: style, recolor: true) }
    }

    private struct Tab {
        var layer: CALayer
        var separator: CALayer?
        var icon: CALayer?
        var text: CATextLayer
        var titleWidth: CGFloat
    }
    private var tabs: [Tab] = []
    private var lineHeight: CGFloat = 0

    func show(_ strip: TabStrip, style: TabStripStyle, recolor: Bool = false) {
        if !recolor, let (old, oldStyle) = shown, oldStyle == style, shownKeyFocus == keyFocus, old.segments == strip.segments,
           old.barHeight == strip.barHeight, old.cornerRadius == strip.cornerRadius, tabs.count == strip.segments.count {
            shown = (strip, style)
            layout(strip)
            return
        }
        shown = (strip, style)
        shownKeyFocus = keyFocus
        wantsLayer = true
        guard let root = layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        tabs = []
        let height = strip.barHeight
        let inset: CGFloat = 3
        let d = style.decorate
        let tabRadius = d.cornerRadius.map { CGFloat($0) } ?? max(4, strip.cornerRadius - inset)
        ids = strip.segments.map(\.id)
        let mangoFont = d.fontDesc.map { decorateFont(FontDescription($0)) }
        let font = mangoFont ?? NSFont.systemFont(ofSize: min(13, max(10, height * 0.38)))
        let focusedFont = mangoFont ?? NSFont.systemFont(ofSize: font.pointSize, weight: .medium)
        func cg(_ c: RGBA) -> CGColor { CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a) }
        lineHeight = ceil(font.ascender - font.descender)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        var resolved: (pill: CGColor, label: CGColor, separator: CGColor)!
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = (NSColor.labelColor.withAlphaComponent(0.13).cgColor, NSColor.labelColor.cgColor,
                        NSColor.separatorColor.cgColor)
        }
        let focusedIndex = strip.segments.firstIndex { $0.focused }
        for (i, seg) in strip.segments.enumerated() {
            let tab = CALayer()
            tab.cornerRadius = tabRadius
            var separator: CALayer?
            let boxed = d.bgColor != nil || (d.borderWidth ?? 0) > 0
            if seg.focused {
                tab.backgroundColor = d.focusBgColor.map(cg) ?? resolved.pill
                tab.borderColor = d.borderColor.map(cg) ?? cg(style.accent)
                let ring = seg.id == keyFocus || d.borderColor != nil || d.borderWidth != nil
                tab.borderWidth = ring ? d.borderWidth.map { CGFloat($0) } ?? style.accentWidth : 0
            } else if boxed {
                tab.backgroundColor = d.bgColor.map(cg)
                tab.borderColor = d.borderColor.map(cg) ?? resolved.separator
                tab.borderWidth = CGFloat(d.borderWidth ?? 0)
            } else if i > 0, focusedIndex != i, focusedIndex != i - 1 {
                let sep = CALayer()
                sep.backgroundColor = resolved.separator
                tab.addSublayer(sep)
                separator = sep
            }
            let text = CATextLayer()
            text.string = seg.title
            let tf = seg.focused ? focusedFont : font
            text.font = tf
            text.fontSize = tf.pointSize
            text.foregroundColor = seg.focused ? d.focusFgColor.map(cg) ?? resolved.label
                                               : d.fgColor.map(cg) ?? resolved.label
            text.alignmentMode = .center
            text.truncationMode = .end
            text.contentsScale = scale
            var iconLayer: CALayer?
            if style.appIcons, let icon = Self.icon(for: seg.pid) {
                let l = CALayer()
                l.contents = icon
                l.contentsGravity = .resizeAspect
                tab.addSublayer(l)
                iconLayer = l
                text.alignmentMode = .left
            }
            tab.addSublayer(text)
            root.addSublayer(tab)
            tabs.append(Tab(layer: tab, separator: separator, icon: iconLayer, text: text,
                            titleWidth: ceil((seg.title as NSString).size(withAttributes: [.font: tf]).width)))
        }
        layout(strip)
    }

    private func layout(_ strip: TabStrip) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let height = strip.barHeight
        let d = shown?.1.decorate ?? DecorateStyle()
        let inset: CGFloat = 3, gap: CGFloat = 2, pad = CGFloat(d.paddingX ?? 10)
        let padY = CGFloat(d.paddingY ?? 0)
        let inner = strip.frame.width - 2 * inset
        let count = tabs.count
        if strip.plain, strip.segments.count == count {
            // mango's look: each member's bar where mango puts it
            frames = strip.segments.map {
                CGRect(x: $0.frame.minX - strip.frame.minX, y: $0.frame.minY - strip.frame.minY,
                       width: $0.frame.width, height: $0.frame.height)
            }
        } else {
            frames = TabStripLayout.segmentFrames(width: inner - gap * CGFloat(max(0, count - 1)), count: count)
                .enumerated().map { i, f in
                    CGRect(x: inset + f.minX + gap * CGFloat(i), y: inset, width: f.width, height: height - 2 * inset)
                }
        }
        layoutCloseButtons(strip)
        for (t, f) in zip(tabs, frames) {
            t.layer.frame = f
            t.separator?.frame = CGRect(x: -gap / 2 - 0.5, y: f.height * 0.25, width: 1, height: f.height * 0.5)
            let edge = pad
            var textRect = CGRect(x: edge, y: max(padY, (f.height - lineHeight) / 2), width: max(0, f.width - 2 * edge),
                                  height: lineHeight)
            if let icon = t.icon {
                let side = min(16, max(0, f.height - 8))
                let iconGap: CGFloat = 6
                let titleW = min(textRect.width - side - iconGap, t.titleWidth)
                let total = side + iconGap + max(0, titleW)
                let x0 = max(pad, min((f.width - total) / 2, f.width - edge - total))
                icon.frame = CGRect(x: x0, y: (f.height - side) / 2, width: side, height: side)
                textRect = CGRect(x: x0 + side + iconGap, y: textRect.minY, width: max(0, titleW), height: lineHeight)
            }
            t.text.frame = textRect
        }
    }

    private func layoutCloseButtons(_ strip: TabStrip) {
        for l in closeLayers { l.removeFromSuperlayer() }
        closeLayers = []
        closeFrames = []
        guard let cb = strip.closeButton, let root = layer else { return }
        for f in frames {
            let size = min(cb.size, f.height, f.width)
            let margin = min(cb.margin, f.width - size)
            let r = CGRect(x: f.maxX - size - margin, y: f.minY + (f.height - size) / 2, width: size, height: size)
            let circle = CAShapeLayer()
            circle.frame = r
            circle.path = CGPath(ellipseIn: CGRect(origin: .zero, size: r.size), transform: nil)
            circle.fillColor = CGColor(red: cb.color.r, green: cb.color.g, blue: cb.color.b, alpha: cb.color.a)
            let cross = CAShapeLayer()
            let path = CGMutablePath(), k = size * 0.3
            path.move(to: CGPoint(x: k, y: k)); path.addLine(to: CGPoint(x: size - k, y: size - k))
            path.move(to: CGPoint(x: size - k, y: k)); path.addLine(to: CGPoint(x: k, y: size - k))
            cross.path = path
            cross.strokeColor = .white
            cross.lineWidth = max(1, size / 10)
            cross.lineCap = .round
            circle.addSublayer(cross)
            root.addSublayer(circle)
            closeLayers.append(circle)
            closeFrames.append(r)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = closeFrames.firstIndex(where: { $0.contains(p) }), i < ids.count { onClose?(ids[i]); return }
        if let i = frames.firstIndex(where: { $0.contains(p) }) { onClick?(ids[i]) }
    }

    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = frames.firstIndex(where: { $0.contains(p) }) { onRightClick?(ids[i]) }
    }

    private static var icons: [String: CGImage] = [:]
    /// Each running app's key: asking LaunchServices for it on every draw costs a round trip per tab.
    private static var keys: [pid_t: String] = [:]

    static func forget(pid: pid_t) { keys.removeValue(forKey: pid) }

    static func icon(for pid: pid_t) -> CGImage? {
        guard pid > 0 else { return nil }
        if let key = keys[pid], let i = icons[key] { return i }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        let key = app.bundleIdentifier ?? "pid:\(pid)"
        keys[pid] = key
        if let i = icons[key] { return i }
        guard let image = app.icon else { return nil }
        var rect = CGRect(x: 0, y: 0, width: 64, height: 64)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        icons[key] = cg
        return cg
    }
}
