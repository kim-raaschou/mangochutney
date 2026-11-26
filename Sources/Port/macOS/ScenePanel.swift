import AppKit
import SwiftUI
import Mango

/// wlroots' scene output for the trees mango builds its own nodes in (server.layers; the workspace
/// overview): at each frame the port draws every tree under the special overlay layer, one panel per
/// tree on the monitor it stands on. Rects are layers of their colour; a buffer is its windows'
/// pictures (ScreenCaptureKit), scaled and clipped as the buffer's source box and size say.
@MainActor
final class ScenePanel {
    private let window: NSWindow
    private let root: CALayer
    private let origin: CGPoint
    private var layers: [ObjectIdentifier: CALayer] = [:]
    /// The pictures of the windows, taken once each while the panel is up.
    private var images: [ClientID: CGImage] = [:]
    private var asked: Set<ClientID> = []
    private let capture: ([ClientID], @escaping (ClientID, CGImage) -> Void) -> Void
    private let icon: (ClientID) -> NSImage?
    private var lastTree: WlrSceneTree?
    private let size: CGSize
    /// Port extension: chutney_macos_appearance. Blur behind the panel where a rect covers the whole tree
    /// (its backdrop), and the windows' round corners, scaled with them (their width on screen).
    struct MacOSLook {
        var cornerRadius: CGFloat
        var windowWidth: (ClientID) -> CGFloat?
    }
    private let macOS: MacOSLook?
    /// The layout switcher's icon of a layout (LayoutIcon), in the given tint.
    private let layoutIcon: (LayoutKind) -> CGImage?
    /// A window's box in mango's layout (its size on the card's tag) and its size on the screen now.
    private let windowSizes: (ClientID) -> (tile: CGSize, now: CGSize)?
    /// The scene is drawn inside these edges of the monitor, scaled to fit: below a notch, and with
    /// chutney_macos_appearance inside the monitor's outer gaps. The pointer is given mango in the
    /// scene's coordinates (scenePoint).
    struct Inset {
        var top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0
    }
    private let scale: CGFloat
    private let offset: CGPoint
    private let host: CALayer?

    init(frame: CGRect, capture: @escaping ([ClientID], @escaping (ClientID, CGImage) -> Void) -> Void,
         icon: @escaping (ClientID) -> NSImage?, macOS: MacOSLook? = nil, inset: Inset = Inset(),
         layoutIcon: @escaping (LayoutKind) -> CGImage? = { _ in nil },
         windowSizes: @escaping (ClientID) -> (tile: CGSize, now: CGSize)? = { _ in nil }) {
        self.layoutIcon = layoutIcon
        self.windowSizes = windowSizes
        origin = frame.origin
        size = frame.size
        let aw = max(1, frame.width - inset.left - inset.right), ah = max(1, frame.height - inset.top - inset.bottom)
        scale = min(1, aw / frame.width, ah / frame.height)
        offset = CGPoint(x: inset.left + (aw - frame.width * scale) / 2, y: inset.top + (ah - frame.height * scale) / 2)
        self.capture = capture
        self.icon = icon
        self.macOS = macOS
        let cocoa = CGRect(x: frame.minX, y: Screens.primaryHeight - frame.maxY, width: frame.width, height: frame.height)
        window = NSWindow(contentRect: cocoa, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        // above the menu bar and the Dock: mango's overlay layer covers the whole output
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        window.ignoresMouseEvents = true   // the event tap gives mango the pointer
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = SceneFlippedView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        root = CALayer()
        root.anchorPoint = .zero
        root.bounds = view.bounds
        root.position = offset
        root.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        view.layer?.addSublayer(root)
        host = view.layer
        if macOS != nil {
            let blur = NSVisualEffectView(frame: view.frame)
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.addSubview(view)
            window.contentView = blur
        } else {
            window.contentView = view
        }
        window.orderFrontRegardless()
    }

    /// Whether the point (layout coordinates) is on the panel's monitor.
    func covers(_ p: CGPoint) -> Bool { CGRect(origin: origin, size: size).contains(p) }

    /// A point on the monitor in the scene's coordinates, where it is drawn scaled inside the inset.
    func scenePoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + (p.x - origin.x - offset.x) / scale, y: origin.y + (p.y - origin.y - offset.y) / scale)
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }

    /// Port extension: chutney_workspace_overview_layout. A tag's layout's icon on its card: the card's box on the
    /// monitor (the scene's coordinates, monitor-local) and the layout.
    struct LayoutBadge {
        var card: CGRect
        var kind: LayoutKind
        var tag: UInt32
    }
    private var badges: [LayoutBadge] = []
    private var badgeLayers: [CALayer] = []

    /// The tree as the frame left it.
    /// The badges stay as they were when it is drawn again for a picture (nil).
    func draw(_ tree: WlrSceneTree, badges: [LayoutBadge]? = nil) {
        lastTree = tree
        if let badges { self.badges = badges }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var seen: Set<ObjectIdentifier> = []
        var order: [CALayer] = []
        let base = CGPoint(x: CGFloat(tree.x) - origin.x, y: CGFloat(tree.y) - origin.y)
        cards = macOS != nil ? Self.cards(tree, size: size) : [:]
        for node in tree.children where node.enabled {
            guard let l = layer(for: node, at: base) else { continue }
            seen.insert(ObjectIdentifier(node))
            order.append(l)
        }
        for (key, l) in layers where !seen.contains(key) {
            l.removeFromSuperlayer()
            layers[key] = nil
        }
        root.sublayers = order + badgeLayers(base)
        CATransaction.commit()
    }

    private func layer(for node: WlrSceneNode, at base: CGPoint) -> CALayer? {
        let key = ObjectIdentifier(node)
        if let rect = node as? WlrSceneRect {
            let l = layers[key] ?? CALayer()
            layers[key] = l
            l.frame = CGRect(x: base.x + CGFloat(rect.x), y: base.y + CGFloat(rect.y),
                             width: CGFloat(rect.width), height: CGFloat(rect.height))
            let backdrop = rect.x == 0 && rect.y == 0
                && CGFloat(rect.width) >= size.width && CGFloat(rect.height) >= size.height
            if backdrop && macOS == nil { host?.backgroundColor = Self.straight(rect.color) }
            l.backgroundColor = backdrop && macOS != nil ? nil : Self.straight(rect.color)
            let card = cards[key]
            l.isHidden = card?.hidden ?? false
            l.cornerRadius = card?.radius ?? 0
            l.borderWidth = card?.borderWidth ?? 0
            l.borderColor = card?.borderColor.map(Self.straight)
            return l
        }
        if let node = node as? WlrSceneBuffer, let buffer = node.buffer {
            let l = layers[key] ?? CALayer()
            layers[key] = l
            l.masksToBounds = true
            l.frame = CGRect(x: base.x + CGFloat(node.x), y: base.y + CGFloat(node.y),
                             width: CGFloat(node.destWidth), height: CGFloat(node.destHeight))
            l.backgroundColor = Self.straight(buffer.background)
            l.cornerRadius = cards[key]?.radius ?? 0
            fill(l, buffer, node)
            return l
        }
        return nil
    }

    /// The badges, reused as the cards stay; above everything else in the scene: over the picture at its
    /// card's bottom left corner, all alike.
    private func badgeLayers(_ base: CGPoint) -> [CALayer] {
        while badgeLayers.count < badges.count { badgeLayers.append(Self.makeBadge()) }
        badgeLayers.removeLast(badgeLayers.count - badges.count)
        let size = Self.badgeSize, inset = Self.badgeInset
        for (l, b) in zip(badgeLayers, badges) {
            l.frame = CGRect(x: base.x + b.card.minX + inset, y: base.y + b.card.maxY - inset - size.height,
                             width: size.width, height: size.height)
            l.isHidden = size.width + 2 * inset > b.card.width || size.height + 2 * inset > b.card.height
            l.sublayers?.first(where: { $0.name == "icon" })?.frame = CGRect(origin: .zero, size: size)
            l.sublayers?.first(where: { $0.name == "icon" })?.contents = layoutIcon(b.kind)
        }
        return badgeLayers
    }

    /// The badges' boxes on the screen (layout coordinates) and their tags, for a click.
    var badgeHits: [(box: CGRect, tag: UInt32)] {
        zip(badgeLayers, badges).filter { !$0.0.isHidden }.map { l, b in
            (CGRect(x: origin.x + offset.x + l.frame.minX * scale, y: origin.y + offset.y + l.frame.minY * scale,
                    width: l.frame.width * scale, height: l.frame.height * scale), b.tag)
        }
    }

    static let badgeIconSize = CGSize(width: 18, height: 12)
    /// The icon on its cell (LayoutCell's padding).
    static let badgeSize = CGSize(width: badgeIconSize.width + 8, height: badgeIconSize.height + 6)
    /// The room between a badge and its card's edges.
    static let badgeInset: CGFloat = 8

    private static func makeBadge() -> CALayer {
        let l = CALayer()
        let icon = CALayer()
        icon.name = "icon"
        icon.contentsGravity = .resizeAspect
        icon.contentsScale = 2
        l.addSublayer(icon)
        return l
    }

    /// Port extension: chutney_macos_appearance. How a node of a card is drawn: the card's frame round,
    /// with the colour of its border rects as its edge, those rects hidden, and what stands inside it
    /// (its pictures, its dim) round within the edge.
    struct CardStyle {
        var radius: CGFloat = 0
        var borderWidth: CGFloat = 0
        var borderColor: RGBA?
        var hidden = false
    }
    private var cards: [ObjectIdentifier: CardStyle] = [:]

    /// A card is a rect with border rects along its edges (rects a few pixels thin, the length of a side),
    /// or with a buffer inside it at most a quarter of its size in from its edges (a card without
    /// borders); the backdrop over the whole monitor is none.
    private static func cards(_ tree: WlrSceneTree, size: CGSize) -> [ObjectIdentifier: CardStyle] {
        func box(_ n: WlrSceneNode) -> CGRect? {
            if let r = n as? WlrSceneRect { return CGRect(x: r.x, y: r.y, width: r.width, height: r.height) }
            if let b = n as? WlrSceneBuffer, b.buffer != nil {
                return CGRect(x: b.x, y: b.y, width: b.destWidth, height: b.destHeight)
            }
            return nil
        }
        let nodes = tree.children.filter(\.enabled).compactMap { n in box(n).map { (n, $0) } }
        let buffers = nodes.filter { $0.0 is WlrSceneBuffer }
        let radius: CGFloat = 10
        var out: [ObjectIdentifier: CardStyle] = [:]
        for (node, frame) in nodes where node is WlrSceneRect {
            // the tree's backdrop (a rect over the whole monitor) is no card
            if frame.minX <= 0 && frame.minY <= 0 && frame.width >= size.width && frame.height >= size.height { continue }
            let slack = min(frame.width, frame.height) / 4
            func inset(_ r: CGRect) -> CGFloat {
                min(r.minX - frame.minX, r.minY - frame.minY, frame.maxX - r.maxX, frame.maxY - r.maxY)
            }
            func isEdge(_ r: CGRect) -> Bool {
                // a border is a few pixels thin, not a neighbour card cut at the monitor's edge
                inset(r) == 0 && min(r.width, r.height) <= max(6, min(frame.width, frame.height) / 40)
                    && max(r.width, r.height) >= min(frame.width, frame.height) - 1
            }
            let edges = nodes.filter { $0.0 !== node && $0.0 is WlrSceneRect && frame.contains($0.1) && isEdge($0.1) }
            guard edges.count >= 2
                || buffers.contains(where: { frame.contains($0.1) && inset($0.1) <= slack && $0.1.width > frame.width / 2 })
            else { continue }
            var style = CardStyle(radius: min(radius, min(frame.width, frame.height) / 2))
            for (other, r) in nodes where other !== node && frame.contains(r) {
                let thin = min(r.width, r.height)
                if isEdge(r), let rect = other as? WlrSceneRect {
                    out[ObjectIdentifier(other)] = CardStyle(hidden: true)
                    style.borderWidth = max(style.borderWidth, thin)
                    style.borderColor = rect.color
                } else if out[ObjectIdentifier(other)] == nil {
                    out[ObjectIdentifier(other)] = CardStyle(radius: max(0, style.radius - inset(r)))
                }
            }
            out[ObjectIdentifier(node)] = style
        }
        return out
    }

    /// The buffer's windows in the node's box: the source box of the buffer scaled to the box.
    private func fill(_ l: CALayer, _ buffer: WlrBuffer, _ node: WlrSceneBuffer) {
        var src = node.srcBox
        if src.width <= 0 || src.height <= 0 {
            src = CGRect(x: 0, y: 0, width: buffer.width, height: buffer.height)
        }
        let sx = CGFloat(node.destWidth) / src.width, sy = CGFloat(node.destHeight) / src.height
        var subs: [CALayer] = []
        var existing: [ClientID: CALayer] = [:]
        for s in l.sublayers ?? [] { if let id = s.value(forKey: "client") as? ClientID { existing[id] = s } }
        var missing: [ClientID] = []
        for item in buffer.items {
            let box = CGRect(x: (item.box.minX - src.minX) * sx, y: (item.box.minY - src.minY) * sy,
                             width: item.box.width * sx, height: item.box.height * sy)
            let frame = existing.removeValue(forKey: item.client) ?? CALayer()
            frame.setValue(item.client, forKey: "client")
            frame.frame = box
            frame.backgroundColor = nil
            frame.cornerRadius = 0
            let picture = frame.sublayers?.first(where: { $0.name != "ring" }) ?? {
                let p = CALayer()
                p.contentsGravity = .resize
                p.masksToBounds = true
                frame.addSublayer(p)
                return p
            }()
            let bx = item.borderX * sx, by = item.borderY * sy
            let inner = CGRect(x: bx, y: by, width: max(0, box.width - 2 * bx), height: max(0, box.height - 2 * by))
            picture.isHidden = !item.picture
            if let image = images[item.client] {
                picture.contents = image
                picture.contentsGravity = .resize
                // the picture at the window's own size, scaled as the card is, anchored top left and cut where
                // it is larger than its box: a hidden window is not resized while the overview is up, so on
                // another tag it may have another size than its box there (never stretched or zoomed)
                if let sizes = windowSizes(item.client), sizes.tile.width > 0, sizes.now.width > 0, sizes.now.height > 0 {
                    let k = box.width / sizes.tile.width
                    let shown = CGSize(width: sizes.now.width * k, height: sizes.now.height * k)
                    picture.frame = CGRect(x: inner.minX, y: inner.minY, width: min(inner.width, shown.width),
                                           height: min(inner.height, shown.height))
                    picture.contentsRect = CGRect(x: 0, y: 0, width: picture.frame.width / max(1, shown.width),
                                                  height: picture.frame.height / max(1, shown.height))
                } else {
                    picture.frame = inner
                    picture.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                }
                picture.backgroundColor = nil
            } else {
                picture.frame = inner
                picture.contents = icon(item.client)
                picture.contentsGravity = .center
                picture.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                picture.backgroundColor = Self.straight(buffer.background.a > 0 ? buffer.background
                                                        : RGBA(r: 0.2, g: 0.2, b: 0.2, a: 1))
                if !asked.contains(item.client) { missing.append(item.client) }
            }
            // the window's border, a ring around the picture as it is shown (it may be smaller than its box);
            // over it, so it does not show in macOS's see-through window corners
            var radius: CGFloat = 0
            if let macOS, let width = macOS.windowWidth(item.client), width > 0 {
                radius = macOS.cornerRadius * box.width / width
            }
            picture.cornerRadius = radius
            let ring = frame.sublayers?.first(where: { $0.name == "ring" }) ?? {
                let l = CALayer()
                l.name = "ring"
                frame.addSublayer(l)
                return l
            }()
            let b = max(bx, by)
            ring.frame = picture.frame.insetBy(dx: -bx, dy: -by)
            ring.cornerRadius = radius > 0 ? radius + b : 0
            ring.borderWidth = b
            ring.borderColor = Self.straight(item.borderColor)
            ring.isHidden = b <= 0 || !item.picture
            subs.append(frame)
        }
        l.sublayers = subs
        if !missing.isEmpty {
            asked.formUnion(missing)
            capture(missing) { [weak self] id, image in
                guard let self else { return }
                self.images[id] = image
                if let tree = self.lastTree { self.draw(tree) }
            }
        }
    }

    /// wlroots' colours are premultiplied; a layer's are not.
    static func straight(_ c: RGBA) -> CGColor {
        guard c.a > 0 else { return CGColor(red: 0, green: 0, blue: 0, alpha: 0) }
        return CGColor(red: min(1, c.r / c.a), green: min(1, c.g / c.a), blue: min(1, c.b / c.a), alpha: c.a)
    }
}

private final class SceneFlippedView: NSView {
    override var isFlipped: Bool { true }
}

extension MacWindowSystem {
    /// wlr_scene_output_commit for the trees under the special overlay layer: each drawn on its monitor's
    /// panel, a panel closed with its tree.
    func drawScene() {
        let layer = server.layers[Lyr.specialOverlay.rawValue]
        var seen: Set<ObjectIdentifier> = []
        for case let tree as WlrSceneTree in layer.children where tree.enabled {
            let at = CGPoint(x: tree.x, y: tree.y)
            guard let m = server.monitors.first(where: { $0.m.contains(at) }) else { continue }
            let key = ObjectIdentifier(tree)
            seen.insert(key)
            let panel = scenePanels[key] ?? ScenePanel(frame: m.m, capture: { [weak self] ids, done in
                self?.captureWindows(ids, done)
            }, icon: { [weak self] id in
                self?.server.clientByWindowID(id).flatMap { NSRunningApplication(processIdentifier: $0.pid)?.icon }
            }, macOS: server.config.chutneyMacOSAppearance   // Port extension: chutney_macos_appearance
                ? ScenePanel.MacOSLook(cornerRadius: windowCornerRadius, windowWidth: { [weak self] id in
                    self?.server.clientByWindowID(id)?.geom.width })
                : nil, inset: sceneInset(m), layoutIcon: { [weak self] kind in self?.layoutIconImage(kind) },
                windowSizes: { [weak self] id in
                    self?.server.clientByWindowID(id).map { (tile: $0.geom.size, now: $0.frame.size) } })
            scenePanels[key] = panel
            panel.draw(tree, badges: layoutBadges(tree, m))
        }
        let hits = scenePanels.values.flatMap(\.badgeHits)
        router.publish { $0.layoutBadges = hits }   // Port extension: chutney_workspace_overview_layout
        var closed = false
        for (key, panel) in scenePanels where !seen.contains(key) {
            panel.close()
            scenePanels[key] = nil
            closed = true
        }
        if closed { releaseHeldFocus() }
    }

    /// Below a notch (nothing shows under it), and with chutney_macos_appearance inside the monitor's outer
    /// gaps (Port extension).
    private func sceneInset(_ m: Monitor) -> ScenePanel.Inset {
        let notch = CGFloat(Screens.notchHeight(m.screen.displayID))
        guard server.config.chutneyMacOSAppearance else { return .init(top: notch) }
        let x = CGFloat(m.gappoh), y = CGFloat(m.gappov)
        return .init(top: notch + y, left: x, bottom: y, right: x)
    }

    /// Port extension: chutney_workspace_overview_layout. Each card of the workspace overview with its tag's
    /// layout, while the overview stands still (not opening, closing or moving its cards).
    private func layoutBadges(_ tree: WlrSceneTree, _ m: Monitor) -> [ScenePanel.LayoutBadge] {
        guard server.config.chutneyWorkspaceOverviewLayout, wsov.root === tree, wsov.mon === m, !wsov.closing,
              wsov.progress >= 1 else { return [] }
        let scrolls = wsov.layout == 1   // mango's WORKSPACE_OVERVIEW_SCROLL
        let horizontal = scrolls && server.config.workspaceOverviewScrollDirection == .horizontal
        let vertical = scrolls && server.config.workspaceOverviewScrollDirection == .vertical
        return wsov.cells.map { cell in
            var card = cell.box.cgRect
            if horizontal { card.origin.x -= wsov.scrollOffset.rounded() }
            if vertical { card.origin.y -= wsov.scrollOffset.rounded() }
            return ScenePanel.LayoutBadge(card: card, kind: m.pertag.ltidxs[Int(cell.tag)], tag: cell.tag)
        }.filter { $0.card.intersects(CGRect(origin: .zero, size: m.m.size)) }
    }

    /// The layout icon (LayoutIcon) on its cell as the menu's layout panel draws the chosen one, once per layout.
    func layoutIconImage(_ kind: LayoutKind) -> CGImage? {
        let theme = server.config.focuscolor
        if layoutIconTheme != theme { layoutIconCache = [:]; layoutIconTheme = theme }
        if let image = layoutIconCache[kind] { return image }
        // as the menu's layout panel draws the chosen layout: white on the theme's colour
        let renderer = ImageRenderer(content: LayoutCell(kind: kind, selected: true, tint: PortAccent.color(server.config),
                                                         iconSize: ScenePanel.badgeIconSize, nameFont: nil,
                                                         padding: EdgeInsets(top: 3, leading: 4, bottom: 3, trailing: 4), cornerRadius: 4))
        renderer.scale = 2
        let image = renderer.cgImage
        layoutIconCache[kind] = image
        return image
    }

    /// Port extension: chutney_workspace_overview_layout. A click on a card's layout icon: its tag is viewed
    /// (the pointer over the card made it the target) and the layout switcher opens over the overview.
    func layoutBadgeClicked(tag: UInt32) {
        guard let m = wsov.mon, m.pertag.curtag == tag || m.tagset[m.seltags] == 1 << (tag - 1) else { return }
        LayoutPalette.shared.show(server)
    }

    /// The pointer as mango is given it: on a scene panel, in the scene's coordinates.
    func scenePointer(_ p: CGPoint) -> CGPoint {
        for panel in scenePanels.values where panel.covers(p) { return panel.scenePoint(p) }
        return p
    }

    /// The windows' pictures at their own size (ScreenCaptureKit).
    private func captureWindows(_ ids: [ClientID], _ done: @escaping (ClientID, CGImage) -> Void) {
        guard canCapture else { return }
        var sizes: [ClientID: CGSize] = [:]
        var fullscreen: Set<ClientID> = []
        for id in ids {
            guard let c = server.clientByWindowID(id) else { continue }
            let scale = CGFloat(c.mon?.screen.scale ?? 2)
            sizes[id] = CGSize(width: c.frame.width * scale, height: c.frame.height * scale)
            if nativeFullscreen(c) { fullscreen.insert(id) }
        }
        WindowSnapshot.capture(ids, pixelSize: sizes, onlyOnScreen: fullscreen) { id, image in done(id, image) }
    }
}
