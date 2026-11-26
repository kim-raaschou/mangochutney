import AppKit
import SwiftUI
import Mango

/// wlroots' scene output for the trees mango builds its own nodes in (server.layers; the workspace
/// overview): at each frame the port draws every tree under the special overlay layer, one panel per
/// tree on the monitor it stands on. What to draw is SceneDrawing's; the panel lays its draw list out as
/// layers and takes the windows' pictures (ScreenCaptureKit).
@MainActor
final class ScenePanel {
    private let window: NSWindow
    private let root: CALayer
    private let host: CALayer?
    private let origin: CGPoint
    private let look: SceneDrawing.Look
    private let geometry: SceneDrawing.Geometry
    private var layers: [ObjectIdentifier: CALayer] = [:]
    private var badgeLayers: [CALayer] = []
    /// The pictures of the windows, taken once each while the panel is up.
    private var images: [ClientID: CGImage] = [:]
    private var asked: Set<ClientID> = []
    private let capture: ([ClientID], @escaping (ClientID, CGImage) -> Void) -> Void
    private let icon: (ClientID) -> NSImage?
    private let layoutIcon: (LayoutKind) -> CGImage?
    private let windowSizes: (ClientID) -> SceneDrawing.WindowSize?
    private var lastTree: WlrSceneTree?
    private var badges: [SceneDrawing.Badge] = []
    private(set) var list = SceneDrawing.DrawList()

    init(frame: CGRect, look: SceneDrawing.Look,
         capture: @escaping ([ClientID], @escaping (ClientID, CGImage) -> Void) -> Void,
         icon: @escaping (ClientID) -> NSImage?,
         layoutIcon: @escaping (LayoutKind) -> CGImage?,
         windowSizes: @escaping (ClientID) -> SceneDrawing.WindowSize?) {
        origin = frame.origin
        self.look = look
        geometry = SceneDrawing.Geometry(size: look.size, inset: look.inset)
        self.capture = capture
        self.icon = icon
        self.layoutIcon = layoutIcon
        self.windowSizes = windowSizes
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
        root.position = geometry.offset
        root.setAffineTransform(CGAffineTransform(scaleX: geometry.scale, y: geometry.scale))
        view.layer?.addSublayer(root)
        host = view.layer
        if look.macOS {
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
    func covers(_ p: CGPoint) -> Bool { CGRect(origin: origin, size: look.size).contains(p) }

    /// A point on the monitor in the scene's coordinates.
    func scenePoint(_ p: CGPoint) -> CGPoint {
        let q = geometry.scenePoint(CGPoint(x: p.x - origin.x, y: p.y - origin.y))
        return CGPoint(x: origin.x + q.x, y: origin.y + q.y)
    }

    /// The layout icons' boxes on the screen (layout coordinates) and their tags, for a click.
    var badgeHits: [(box: CGRect, tag: UInt32)] {
        list.badges.filter { !$0.hidden }.map { b in (geometry.screenBox(b.frame).offsetBy(dx: origin.x, dy: origin.y), b.tag) }
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }

    /// The tree as the frame left it. The badges stay as they were when it is drawn again for a picture (nil).
    func draw(_ tree: WlrSceneTree, badges: [SceneDrawing.Badge]? = nil) {
        lastTree = tree
        if let badges { self.badges = badges }
        let base = CGPoint(x: CGFloat(tree.x) - origin.x, y: CGFloat(tree.y) - origin.y)
        list = SceneDrawing.draw(tree, at: base, look: look, badges: self.badges, windows: windowSizes)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let backdrop = list.backdrop { host?.backgroundColor = Self.straight(backdrop) }
        var order: [CALayer] = []
        var missing: [ClientID] = []
        for node in list.nodes {
            let l = layers[node.id] ?? CALayer()
            layers[node.id] = l
            l.frame = node.frame
            switch node.kind {
            case .rect(let r):
                l.backgroundColor = r.color.map(Self.straight)
                l.isHidden = r.hidden
                l.cornerRadius = r.radius
                l.borderWidth = r.borderWidth
                l.borderColor = r.borderColor.map(Self.straight)
            case .buffer(let b):
                l.masksToBounds = true
                l.backgroundColor = Self.straight(b.background)
                l.cornerRadius = b.radius
                missing += fill(l, b)
            }
            order.append(l)
        }
        let seen = Set(list.nodes.map(\.id))
        for (key, l) in layers where !seen.contains(key) {
            l.removeFromSuperlayer()
            layers[key] = nil
        }
        root.sublayers = order + layoutBadges()
        CATransaction.commit()
        if !missing.isEmpty {
            asked.formUnion(missing)
            capture(missing) { [weak self] id, image in
                guard let self else { return }
                self.images[id] = image
                if let tree = self.lastTree { self.draw(tree) }
            }
        }
    }

    /// A buffer's windows: each its picture (or its app's icon until the picture comes) and its border
    /// ring; the windows with no picture yet.
    private func fill(_ l: CALayer, _ buffer: SceneDrawing.Buffer) -> [ClientID] {
        var existing: [ClientID: CALayer] = [:]
        for s in l.sublayers ?? [] { if let id = s.value(forKey: "client") as? ClientID { existing[id] = s } }
        var subs: [CALayer] = [], missing: [ClientID] = []
        for item in buffer.items {
            let frame = existing.removeValue(forKey: item.client) ?? CALayer()
            frame.setValue(item.client, forKey: "client")
            frame.frame = item.box
            let picture = frame.sublayers?.first(where: { $0.name == "picture" }) ?? {
                let p = CALayer()
                p.name = "picture"
                p.masksToBounds = true
                frame.addSublayer(p)
                return p
            }()
            let ring = frame.sublayers?.first(where: { $0.name == "ring" }) ?? {
                let r = CALayer()
                r.name = "ring"
                frame.addSublayer(r)
                return r
            }()
            picture.isHidden = !item.showsPicture
            picture.cornerRadius = item.radius
            if let image = images[item.client] {
                picture.frame = item.picture
                picture.contents = image
                picture.contentsGravity = .resize
                picture.contentsRect = item.pictureContents
                picture.backgroundColor = nil
                ring.frame = item.pictureRing
            } else {
                picture.frame = item.inner
                picture.contents = icon(item.client)
                picture.contentsGravity = .center
                picture.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                picture.backgroundColor = Self.straight(buffer.background.a > 0 ? buffer.background
                                                        : RGBA(r: 0.2, g: 0.2, b: 0.2, a: 1))
                ring.frame = item.iconRing
                if !asked.contains(item.client) { missing.append(item.client) }
            }
            ring.cornerRadius = item.ringRadius
            ring.borderWidth = item.border
            ring.borderColor = Self.straight(item.borderColor)
            ring.isHidden = item.border <= 0 || !item.showsPicture
            subs.append(frame)
        }
        l.sublayers = subs
        return missing
    }

    /// Port extension: chutney_workspace_overview_layout. The layout icons, reused as the cards stay; over
    /// everything else in the scene.
    private func layoutBadges() -> [CALayer] {
        while badgeLayers.count < list.badges.count {
            let l = CALayer()
            l.contentsGravity = .resizeAspect
            l.contentsScale = 2
            badgeLayers.append(l)
        }
        badgeLayers.removeLast(badgeLayers.count - list.badges.count)
        for (l, b) in zip(badgeLayers, list.badges) {
            l.frame = b.frame
            l.isHidden = b.hidden
            l.contents = layoutIcon(b.kind)
        }
        return badgeLayers
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
            let panel = scenePanels[key] ?? ScenePanel(frame: m.m, look: sceneLook(m), capture: { [weak self] ids, done in
                self?.captureWindows(ids, done)
            }, icon: { [weak self] id in
                self?.server.clientByWindowID(id).flatMap { NSRunningApplication(processIdentifier: $0.pid)?.icon }
            }, layoutIcon: { [weak self] kind in self?.layoutIconImage(kind) }, windowSizes: { [weak self] id in
                self?.server.clientByWindowID(id).map { SceneDrawing.WindowSize(tile: $0.geom.size, now: $0.frame.size) }
            })
            scenePanels[key] = panel
            panel.draw(tree, badges: layoutBadges(tree, m, workspaceOverview()))
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

    /// The scene's look on a monitor: below a notch (nothing shows under it), and with
    /// chutney_macos_appearance (Port extension) inside the monitor's outer gaps, round and on blur.
    private func sceneLook(_ m: Monitor) -> SceneDrawing.Look {
        let notch = CGFloat(Screens.notchHeight(m.screen.displayID))
        var look = SceneDrawing.Look(size: m.m.size, inset: .init(top: notch))
        guard server.config.chutneyMacOSAppearance else { return look }
        let x = CGFloat(m.gappoh), y = CGFloat(m.gappov)
        look.inset = .init(top: notch + y, left: x, bottom: y, right: x)
        look.macOS = true
        look.windowCornerRadius = windowCornerRadius
        return look
    }

    /// The workspace overview as the port reads it: the one place it reads mango's wsov.
    struct WorkspaceOverview {
        var root: WlrSceneTree?
        var monitor: Monitor?
        /// Still: not opening, closing or moving its cards.
        var still: Bool
        /// The cards' tags and boxes on the monitor (the strip's scroll taken off).
        var cards: [(tag: UInt32, box: CGRect)]
    }

    func workspaceOverview() -> WorkspaceOverview {
        let scrolls = wsov.layout == 1   // mango's WORKSPACE_OVERVIEW_SCROLL
        let horizontal = scrolls && server.config.workspaceOverviewScrollDirection == .horizontal
        let vertical = scrolls && server.config.workspaceOverviewScrollDirection == .vertical
        return WorkspaceOverview(root: wsov.root, monitor: wsov.mon, still: !wsov.closing && wsov.progress >= 1,
                                 cards: wsov.cells.map { cell in
            var box = cell.box.cgRect
            if horizontal { box.origin.x -= wsov.scrollOffset.rounded() }
            if vertical { box.origin.y -= wsov.scrollOffset.rounded() }
            return (cell.tag, box)
        })
    }

    /// Port extension: chutney_workspace_overview_layout. Each card of the workspace overview with its tag's
    /// layout, while the overview stands still.
    private func layoutBadges(_ tree: WlrSceneTree, _ m: Monitor, _ overview: WorkspaceOverview) -> [SceneDrawing.Badge] {
        guard server.config.chutneyWorkspaceOverviewLayout, overview.root === tree, overview.monitor === m, overview.still
        else { return [] }
        return overview.cards.map { SceneDrawing.Badge(card: $0.box, kind: m.pertag.ltidxs[Int($0.tag)], tag: $0.tag) }
            .filter { $0.card.intersects(CGRect(origin: .zero, size: m.m.size)) }
    }

    /// The layout icon (LayoutIcon) on its cell as the menu's layout panel draws the chosen one, once per layout.
    func layoutIconImage(_ kind: LayoutKind) -> CGImage? {
        let theme = server.config.focuscolor
        if layoutIconTheme != theme { layoutIconCache = [:]; layoutIconTheme = theme }
        if let image = layoutIconCache[kind] { return image }
        // as the menu's layout panel draws the chosen layout: white on the theme's colour
        let renderer = ImageRenderer(content: LayoutCell(kind: kind, selected: true, tint: PortAccent.color(server.config),
                                                         iconSize: SceneDrawing.badgeIconSize, nameFont: nil,
                                                         padding: EdgeInsets(top: 3, leading: 4, bottom: 3, trailing: 4), cornerRadius: 4))
        renderer.scale = 2
        let image = renderer.cgImage
        layoutIconCache[kind] = image
        return image
    }

    /// Port extension: chutney_workspace_overview_layout. A click on a card's layout icon: its tag is viewed
    /// (the pointer over the card made it the target) and the layout switcher opens over the overview.
    func layoutBadgeClicked(tag: UInt32) {
        guard let m = workspaceOverview().monitor, m.pertag.curtag == tag || m.tagset[m.seltags] == 1 << (tag - 1) else { return }
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
