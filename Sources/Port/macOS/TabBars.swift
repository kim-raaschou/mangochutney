import AppKit
import Mango

/// mango's tab strip (tab.c): over the focused window of a tabbed monocle or deck stack,
/// one segment per member, each with its window's title; the focused member's segment
/// in the focus colours. A click on a segment focuses that window.
/// The strip is drawn in the macOS style (like the jump labels): a translucent bar, the
/// focused tab a light pill with the focus colour underneath, system colours for light and
/// dark mode. Each of mango's tab_bar_ / group_bar_decorate_* keys set in the config
/// replaces that part with mango's (`decorate`).

/// mango divides the strip's width evenly; the first `width % count` segments get one
/// point more (tab.c, client_draw_tabbar).
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
public final class TabBarManager {
    /// A segment was clicked.
    public var onSelect: ((CGWindowID) -> Void)?
    /// A click on a segment's close button.
    public var onClose: ((CGWindowID) -> Void)?
    /// A right click on a segment.
    public var onRightClick: ((CGWindowID) -> Void)?
    private var panels: [CGWindowID: (NSPanel, TabStripView, TabStrip)] = [:]
    private var style: TabStripStyle?

    public init() {}

    /// Strips keyed by the focused member they sit above; others are removed.
    public func update(_ strips: [TabStrip], style: TabStripStyle) {
        let restyle = style != self.style
        self.style = style
        var seen: Set<CGWindowID> = []
        // A strip that moved to another member (the focus went along the tabs) takes a panel
        // no strip keeps, instead of a new one: making a panel is the costly part.
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
                    // Moved only (every frame of a slide): the tabs stay as drawn.
                    var moved = old
                    moved.frame.origin = strip.frame.origin
                    apply(strip, to: panel, view: view, style: style, redraw: moved != strip || restyle)
                    panels[strip.above] = (panel, view, strip)
                }
            } else {
                let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.level = .normal
                panel.becomesKeyOnlyIfNeeded = true
                panel.hidesOnDeactivate = false   // NSPanel's default would hide it after mango's menu
                panel.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone, .transient]
                panel.isReleasedWhenClosed = false
                panel.animationBehavior = .none
                let view = TabStripView(frame: .zero)
                view.onClick = { [weak self] id in self?.onSelect?(id) }
                view.onClose = { [weak self] id in self?.onClose?(id) }
                view.onRightClick = { [weak self] id in self?.onRightClick?(id) }
                let bar = NSVisualEffectView(frame: .zero)
                bar.material = .headerView
                bar.blendingMode = .behindWindow
                bar.state = .active
                // The panel's look (chutney_style) under the tabs, beside them in a container,
                // so a plain strip can hide it.
                let container = NSView(frame: .zero)
                container.wantsLayer = true
                container.layer?.masksToBounds = true
                // Rounded on top only: the bottom is under the window.
                container.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                for v in [bar, view] as [NSView] {
                    v.autoresizingMask = [.width, .height]
                    container.addSubview(v)
                }
                panel.contentView = container
                apply(strip, to: panel, view: view, style: style)
                panel.orderFrontRegardless()
                panel.order(.below, relativeTo: Int(strip.above))
                panels[strip.above] = (panel, view, strip)
            }
        }
        for id in panels.keys where !seen.contains(id) {
            panels[id]?.0.orderOut(nil)
            panels[id]?.0.close()
            panels.removeValue(forKey: id)
        }
    }

    /// Back right below their windows (after focus changes, like borders).
    /// Those of `ids` (nil: all).
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
        panel.contentView?.layer?.cornerRadius = strip.plain ? 0 : strip.cornerRadius
        for v in panel.contentView?.subviews ?? [] {
            v.frame = panel.contentView?.bounds ?? .zero
            if v is NSVisualEffectView { v.isHidden = strip.plain }
        }
        view.show(strip, style: style)
    }
}

/// The tabs, drawn with layers over the panel's vibrancy; clicks go to `onClick`.
final class TabStripView: NSView {
    var onClick: ((CGWindowID) -> Void)?
    var onClose: ((CGWindowID) -> Void)?
    var onRightClick: ((CGWindowID) -> Void)?
    /// mango's close buttons (close_button_box), one per segment.
    private var closeLayers: [CALayer] = []
    private var closeFrames: [CGRect] = []
    private var ids: [CGWindowID] = []
    private var frames: [CGRect] = []
    private var shown: (TabStrip, TabStripStyle)?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if let (strip, style) = shown { show(strip, style: style, recolor: true) }   // light / dark mode
    }

    /// One tab's layers, kept while only the strip's geometry changes.
    private struct Tab {
        var layer: CALayer
        var separator: CALayer?
        var icon: CALayer?
        var text: CATextLayer
        var titleWidth: CGFloat
        /// A "⌘1" badge in the focus colour at the trailing edge while ⌘ is held.
        var number: CALayer?
        var numberWidth: CGFloat = 0
    }
    private var tabs: [Tab] = []
    private var lineHeight: CGFloat = 0

    func show(_ strip: TabStrip, style: TabStripStyle, recolor: Bool = false) {
        // The same tabs at another size (every frame of an animation): lay them out again.
        if !recolor, let (old, oldStyle) = shown, oldStyle == style, old.segments == strip.segments,
           old.barHeight == strip.barHeight, old.cornerRadius == strip.cornerRadius, tabs.count == strip.segments.count {
            shown = (strip, style)
            layout(strip)
            return
        }
        shown = (strip, style)
        wantsLayer = true
        guard let root = layer else { return }
        // Drawn anew in one go: no implicit fades between frames of an animation.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        tabs = []
        let height = strip.barHeight
        let inset: CGFloat = 3
        // Concentric with the bar's corners: the first and last tab follow its curve.
        let d = style.decorate
        let tabRadius = d.cornerRadius.map { CGFloat($0) } ?? max(4, strip.cornerRadius - inset)
        ids = strip.segments.map(\.id)
        let mangoFont = d.fontDesc.map { decorateFont(FontDescription($0)) }
        let font = mangoFont ?? NSFont.systemFont(ofSize: min(13, max(10, height * 0.38)))
        let focusedFont = mangoFont ?? NSFont.systemFont(ofSize: font.pointSize, weight: .medium)
        func cg(_ c: RGBA) -> CGColor { CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a) }
        lineHeight = ceil(font.ascender - font.descender)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        var resolved: (pill: CGColor, label: CGColor, secondary: CGColor, separator: CGColor)!
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = (NSColor.labelColor.withAlphaComponent(0.13).cgColor, NSColor.labelColor.cgColor,
                        NSColor.secondaryLabelColor.cgColor, NSColor.separatorColor.cgColor)
        }
        let focusedIndex = strip.segments.firstIndex { $0.focused }
        for (i, seg) in strip.segments.enumerated() {
            let tab = CALayer()
            tab.cornerRadius = tabRadius
            var separator: CALayer?
            let boxed = d.bgColor != nil || (d.borderWidth ?? 0) > 0   // mango's cells: no separators
            if seg.focused {
                // A ring in the focus colour, like the focused window's border.
                tab.backgroundColor = d.focusBgColor.map(cg) ?? resolved.pill
                tab.borderColor = d.borderColor.map(cg) ?? cg(style.accent)
                tab.borderWidth = d.borderWidth.map { CGFloat($0) } ?? style.accentWidth
            } else if boxed {
                tab.backgroundColor = d.bgColor.map(cg)
                tab.borderColor = d.borderColor.map(cg) ?? resolved.separator
                tab.borderWidth = CGFloat(d.borderWidth ?? 0)
            } else if i > 0, focusedIndex != i, focusedIndex != i - 1 {
                // A thin separator between two unfocused tabs.
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
                                               : d.fgColor.map(cg) ?? resolved.secondary
            text.alignmentMode = .center
            text.truncationMode = .end
            text.contentsScale = scale
            // Port extension: not in mango (chutney_tab_bar_app_icons). App icon before the
            // title (OmniWM's app-icon tabs).
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
            // Port extension: not in mango (chutney_tab_bar_shortcuts). The ⌘n badge.
            var number: CALayer?, numberWidth: CGFloat = 0
            if let n = seg.shortcut {
                let label = "⌘\(n)"
                let nf = NSFont.systemFont(ofSize: font.pointSize - 1, weight: .semibold)
                let textWidth = ceil((label as NSString).size(withAttributes: [.font: nf]).width)
                let badgeHeight = ceil(nf.ascender - nf.descender) + 4
                let badge = CALayer()
                badge.backgroundColor = CGColor(red: style.accent.r, green: style.accent.g, blue: style.accent.b, alpha: 1)
                badge.cornerRadius = badgeHeight / 2
                badge.bounds.size = CGSize(width: textWidth + 12, height: badgeHeight)
                let l = CATextLayer()
                l.string = label
                l.font = nf
                l.fontSize = nf.pointSize
                // White on a dark focus colour, black on a light one.
                let a = style.accent
                l.foregroundColor = 0.299 * a.r + 0.587 * a.g + 0.114 * a.b > 0.6 ? .black : .white
                l.alignmentMode = .center
                l.contentsScale = scale
                l.frame = CGRect(x: 0, y: 2, width: textWidth + 12, height: badgeHeight - 4)
                badge.addSublayer(l)
                tab.addSublayer(badge)
                number = badge
                numberWidth = textWidth + 12
            }
            root.addSublayer(tab)
            tabs.append(Tab(layer: tab, separator: separator, icon: iconLayer, text: text,
                            titleWidth: ceil((seg.title as NSString).size(withAttributes: [.font: tf]).width),
                            number: number, numberWidth: numberWidth))
        }
        layout(strip)
    }

    /// Places the tabs for the strip's width: mango's even split, inset and gaps.
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
        frames = TabStripLayout.segmentFrames(width: inner - gap * CGFloat(max(0, count - 1)), count: count)
            .enumerated().map { i, f in
                CGRect(x: inset + f.minX + gap * CGFloat(i), y: inset, width: f.width, height: height - 2 * inset)
            }
        layoutCloseButtons(strip)
        for (t, f) in zip(tabs, frames) {
            t.layer.frame = f
            t.separator?.frame = CGRect(x: -gap / 2 - 0.5, y: f.height * 0.25, width: 1, height: f.height * 0.5)
            // The number keeps its place at the trailing edge (none in a tab too narrow for
            // it); the title stays centred in what is left on both sides.
            let fits = t.number != nil && f.width - 2 * pad >= t.numberWidth + 12
            t.number?.isHidden = !fits
            let edge = fits ? 6 + t.numberWidth + 6 : pad
            if let badge = t.number {
                let h = badge.bounds.height
                badge.frame = CGRect(x: f.width - 6 - t.numberWidth, y: (f.height - h) / 2, width: t.numberWidth, height: h)
            }
            var textRect = CGRect(x: edge, y: max(padY, (f.height - lineHeight) / 2), width: max(0, f.width - 2 * edge),
                                  height: lineHeight)
            if let icon = t.icon {
                // Icon and title centred together, the title giving way first when narrow.
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

    /// close_button_box: `size` (no larger than the bar), `margin` in from the segment's
    /// right edge, centred in the bar; a circle in the button colour with a white cross.
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

    /// The app's icon as an image for a layer, kept per app (bundle id): a pid can be
    /// reused by another app, and the cache stays as small as the set of apps.
    static func icon(for pid: pid_t) -> CGImage? {
        guard pid > 0, let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        let key = app.bundleIdentifier ?? "pid:\(pid)"
        if let i = icons[key] { return i }
        guard let image = app.icon else { return nil }
        var rect = CGRect(x: 0, y: 0, width: 64, height: 64)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        icons[key] = cg
        return cg
    }
}
