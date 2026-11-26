import CoreGraphics
import Mango

/// How the port draws a scene tree mango built (the workspace overview's, under server.layers): the tree,
/// the look and the windows' sizes in; a draw list out, in the scene's coordinates (monitor-local), that
/// ScenePanel lays out as layers. Every decision is here: which rects are cards (their round corners and
/// border), where a window's picture stands and how it is cut, its border ring, the layout icons, and
/// the scene's place inside the monitor (a notch, the outer gaps) with the pointer mapped back.
@MainActor
enum SceneDrawing {
    /// The scene is drawn inside these edges of the monitor, scaled to fit.
    struct Inset: Equatable {
        var top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0
    }

    struct Look {
        /// The monitor's size (the panel's).
        var size: CGSize
        var inset = Inset()
        /// Port extension: chutney_macos_appearance. Round cards with their border as the frame, blur for
        /// the backdrop, the windows' round corners (windowCornerRadius, scaled as the window is).
        var macOS = false
        var windowCornerRadius: CGFloat = 0
    }

    /// A window's box in mango's layout (its size on the card's tag) and its size on the screen now.
    struct WindowSize: Equatable {
        var tile: CGSize
        var now: CGSize
    }

    /// Port extension: chutney_workspace_overview_layout. A card (scene coordinates) and its tag's layout.
    struct Badge: Equatable {
        var card: CGRect
        var kind: LayoutKind
        var tag: UInt32
    }

    /// The scene's place on the monitor: scaled by scale, at offset (monitor-local).
    struct Geometry: Equatable {
        var scale: CGFloat
        var offset: CGPoint

        init(size: CGSize, inset: Inset) {
            let aw = max(1, size.width - inset.left - inset.right), ah = max(1, size.height - inset.top - inset.bottom)
            scale = min(1, aw / max(1, size.width), ah / max(1, size.height))
            offset = CGPoint(x: inset.left + (aw - size.width * scale) / 2, y: inset.top + (ah - size.height * scale) / 2)
        }

        /// A monitor-local point on the screen in the scene's coordinates.
        func scenePoint(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - offset.x) / scale, y: (p.y - offset.y) / scale)
        }

        /// A box in the scene's coordinates where it is on the screen (monitor-local).
        func screenBox(_ r: CGRect) -> CGRect {
            CGRect(x: offset.x + r.minX * scale, y: offset.y + r.minY * scale, width: r.width * scale, height: r.height * scale)
        }
    }

    // MARK: The draw list

    struct DrawList {
        /// The backdrop's colour where the panel shows it itself (not with the macOS look's blur).
        var backdrop: RGBA?
        var nodes: [Node] = []
        var badges: [BadgeFrame] = []
    }

    struct Node {
        var id: ObjectIdentifier
        var frame: CGRect
        var kind: Kind
        enum Kind {
            case rect(Rect)
            case buffer(Buffer)
        }
    }

    struct Rect: Equatable {
        /// nil: not drawn (the backdrop under the macOS look's blur).
        var color: RGBA?
        var radius: CGFloat = 0
        var borderWidth: CGFloat = 0
        var borderColor: RGBA?
        var hidden = false
    }

    struct Buffer {
        var background: RGBA
        var radius: CGFloat
        var items: [Item]
    }

    /// A window in a buffer, in the buffer's box.
    struct Item: Equatable {
        var client: ClientID
        var box: CGRect
        /// Inside the border: where an icon stands while there is no picture.
        var inner: CGRect
        /// Where the picture stands and the part of it shown: at the window's own size, scaled as the card
        /// is, anchored top left and cut where it is larger than its box (a hidden window is not resized
        /// while the overview is up, so on another tag it may have another size than its box there).
        var picture: CGRect
        var pictureContents: CGRect
        /// Whether the picture is drawn at all (a box of 2 pixels or less has none).
        var showsPicture: Bool
        var radius: CGFloat
        var border: CGFloat
        var borderColor: RGBA
        /// The border, a ring around what is shown (the picture, or the icon's box): over it, so it does not
        /// show in macOS's see-through window corners.
        var pictureRing: CGRect
        var iconRing: CGRect
        var ringRadius: CGFloat
    }

    struct BadgeFrame: Equatable {
        var frame: CGRect
        var kind: LayoutKind
        var tag: UInt32
        var hidden: Bool
    }

    static let badgeIconSize = CGSize(width: 18, height: 12)
    /// The icon on its cell (LayoutCell's padding).
    static let badgeSize = CGSize(width: badgeIconSize.width + 8, height: badgeIconSize.height + 6)
    /// The room between a badge and its card's edges.
    static let badgeInset: CGFloat = 8
    static let cardRadius: CGFloat = 10

    /// The tree as the frame left it, drawn with the look; the windows' sizes come from `windows`.
    static func draw(_ tree: WlrSceneTree, at base: CGPoint, look: Look, badges: [Badge],
                     windows: (ClientID) -> WindowSize?) -> DrawList {
        var list = DrawList()
        let cards = look.macOS ? cardStyles(tree, size: look.size) : [:]
        for node in tree.children where node.enabled {
            let id = ObjectIdentifier(node)
            if let rect = node as? WlrSceneRect {
                let frame = CGRect(x: base.x + CGFloat(rect.x), y: base.y + CGFloat(rect.y),
                                   width: CGFloat(rect.width), height: CGFloat(rect.height))
                let backdrop = isBackdrop(CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height), look.size)
                if backdrop && !look.macOS { list.backdrop = rect.color }
                var style = cards[id] ?? Rect()
                style.color = backdrop && look.macOS ? nil : rect.color
                list.nodes.append(Node(id: id, frame: frame, kind: .rect(style)))
            } else if let node = node as? WlrSceneBuffer, let buffer = node.buffer {
                let frame = CGRect(x: base.x + CGFloat(node.x), y: base.y + CGFloat(node.y),
                                   width: CGFloat(node.destWidth), height: CGFloat(node.destHeight))
                let items = self.items(buffer, node, look: look, windows: windows)
                list.nodes.append(Node(id: id, frame: frame,
                                       kind: .buffer(Buffer(background: buffer.background, radius: cards[id]?.radius ?? 0,
                                                            items: items))))
            }
        }
        list.badges = badges.map { b in
            let size = badgeSize, inset = badgeInset
            return BadgeFrame(frame: CGRect(x: base.x + b.card.minX + inset, y: base.y + b.card.maxY - inset - size.height,
                                            width: size.width, height: size.height),
                              kind: b.kind, tag: b.tag,
                              hidden: size.width + 2 * inset > b.card.width || size.height + 2 * inset > b.card.height)
        }
        return list
    }

    /// A rect over the whole monitor: the tree's backdrop.
    static func isBackdrop(_ r: CGRect, _ size: CGSize) -> Bool {
        r.minX <= 0 && r.minY <= 0 && r.width >= size.width && r.height >= size.height
    }

    // MARK: Cards

    /// Port extension: chutney_macos_appearance. A card is a rect with border rects along its edges (rects
    /// a few pixels thin, the length of a side), or with a buffer inside it at most a quarter of its size in
    /// from its edges (a card without borders); the backdrop over the whole monitor is none. A card is round,
    /// with the colour of its border rects as its frame, those rects hidden, and what stands inside it (its
    /// pictures, its dim) round within the frame.
    static func cardStyles(_ tree: WlrSceneTree, size: CGSize) -> [ObjectIdentifier: Rect] {
        func box(_ n: WlrSceneNode) -> CGRect? {
            if let r = n as? WlrSceneRect { return CGRect(x: r.x, y: r.y, width: r.width, height: r.height) }
            if let b = n as? WlrSceneBuffer, b.buffer != nil {
                return CGRect(x: b.x, y: b.y, width: b.destWidth, height: b.destHeight)
            }
            return nil
        }
        let nodes = tree.children.filter(\.enabled).compactMap { n in box(n).map { (n, $0) } }
        let buffers = nodes.filter { $0.0 is WlrSceneBuffer }
        var out: [ObjectIdentifier: Rect] = [:]
        for (node, frame) in nodes where node is WlrSceneRect {
            if isBackdrop(frame, size) { continue }
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
            var style = Rect(radius: min(cardRadius, min(frame.width, frame.height) / 2))
            for (other, r) in nodes where other !== node && frame.contains(r) {
                if isEdge(r), let rect = other as? WlrSceneRect {
                    out[ObjectIdentifier(other)] = Rect(hidden: true)
                    style.borderWidth = max(style.borderWidth, min(r.width, r.height))
                    style.borderColor = rect.color
                } else if out[ObjectIdentifier(other)] == nil {
                    out[ObjectIdentifier(other)] = Rect(radius: max(0, style.radius - inset(r)))
                }
            }
            out[ObjectIdentifier(node)] = style
        }
        return out
    }

    // MARK: Windows

    /// The buffer's windows in the node's box: the source box of the buffer scaled to the box.
    static func items(_ buffer: WlrBuffer, _ node: WlrSceneBuffer, look: Look,
                      windows: (ClientID) -> WindowSize?) -> [Item] {
        var src = node.srcBox
        if src.width <= 0 || src.height <= 0 {
            src = CGRect(x: 0, y: 0, width: buffer.width, height: buffer.height)
        }
        let sx = CGFloat(node.destWidth) / src.width, sy = CGFloat(node.destHeight) / src.height
        return buffer.items.map { item in
            let box = CGRect(x: (item.box.minX - src.minX) * sx, y: (item.box.minY - src.minY) * sy,
                             width: item.box.width * sx, height: item.box.height * sy)
            let bx = item.borderX * sx, by = item.borderY * sy
            let inner = CGRect(x: bx, y: by, width: max(0, box.width - 2 * bx), height: max(0, box.height - 2 * by))
            var picture = inner, contents = CGRect(x: 0, y: 0, width: 1, height: 1)
            let size = windows(item.client)
            if let size, size.tile.width > 0, size.now.width > 0, size.now.height > 0 {
                let k = box.width / size.tile.width
                let shown = CGSize(width: size.now.width * k, height: size.now.height * k)
                picture = CGRect(x: inner.minX, y: inner.minY, width: min(inner.width, shown.width),
                                 height: min(inner.height, shown.height))
                contents = CGRect(x: 0, y: 0, width: picture.width / max(1, shown.width),
                                  height: picture.height / max(1, shown.height))
            }
            var radius: CGFloat = 0
            if look.macOS, let size, size.tile.width > 0 {
                radius = look.windowCornerRadius * box.width / size.tile.width
            }
            let border = max(bx, by)
            return Item(client: item.client, box: box, inner: inner, picture: picture, pictureContents: contents,
                        showsPicture: item.picture, radius: radius, border: border, borderColor: item.borderColor,
                        pictureRing: picture.insetBy(dx: -bx, dy: -by), iconRing: inner.insetBy(dx: -bx, dy: -by),
                        ringRadius: radius > 0 ? radius + border : 0)
        }
    }
}
