import CoreGraphics

// wlroots' scene graph as far as mango builds its own nodes (the workspace overview): trees, rects and
// buffers in layout coordinates. The core builds and moves them as mango does; the port draws the tree
// under server.layers when a frame is shown (wlr_scene_output_commit).

/// wlroots' struct wlr_box.
package struct WlrBox: Equatable {
    package var x: Int
    package var y: Int
    package var width: Int
    package var height: Int
    package init(x: Int = 0, y: Int = 0, width: Int = 0, height: Int = 0) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    package init(_ x: Int, _ y: Int, _ width: Int, _ height: Int) {
        self.init(x: x, y: y, width: width, height: height)
    }
    /// A layout box of whole pixels, as mango's are.
    package init(_ r: CGRect) {
        self.init(x: Int(r.minX), y: Int(r.minY), width: Int(r.width), height: Int(r.height))
    }
    package var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// wlr_box_empty
package func wlrBoxEmpty(_ box: WlrBox?) -> Bool {
    guard let box else { return true }
    return box.width <= 0 || box.height <= 0
}

/// wlr_box_intersection
package func wlrBoxIntersection(_ dest: inout WlrBox, _ a: WlrBox, _ b: WlrBox) -> Bool {
    let aEmpty = wlrBoxEmpty(a), bEmpty = wlrBoxEmpty(b)
    if aEmpty || bEmpty {
        dest = WlrBox()
        return false
    }
    let x1 = max(a.x, b.x), y1 = max(a.y, b.y)
    let x2 = min(a.x + a.width, b.x + b.width), y2 = min(a.y + a.height, b.y + b.height)
    dest = WlrBox(x1, y1, x2 - x1, y2 - y1)
    return !wlrBoxEmpty(dest)
}

/// wlr_box_contains_point
package func wlrBoxContainsPoint(_ box: WlrBox, _ x: Double, _ y: Double) -> Bool {
    if wlrBoxEmpty(box) { return false }
    return x >= Double(box.x) && x < Double(box.x + box.width) && y >= Double(box.y) && y < Double(box.y + box.height)
}

/// wlr_box_equal
package func wlrBoxEqual(_ a: WlrBox, _ b: WlrBox) -> Bool {
    if wlrBoxEmpty(a) { return wlrBoxEmpty(b) }
    if wlrBoxEmpty(b) { return false }
    return a == b
}

/// struct wlr_scene_node
@MainActor
package class WlrSceneNode {
    package fileprivate(set) weak var parent: WlrSceneTree?
    package fileprivate(set) var enabled = true
    package fileprivate(set) var x = 0
    package fileprivate(set) var y = 0
    fileprivate init() {}
}

/// struct wlr_scene_tree
@MainActor
package final class WlrSceneTree: WlrSceneNode {
    package fileprivate(set) var children: [WlrSceneNode] = []
    package override init() { super.init() }
}

/// struct wlr_scene_rect
@MainActor
package final class WlrSceneRect: WlrSceneNode {
    package fileprivate(set) var width = 0
    package fileprivate(set) var height = 0
    package fileprivate(set) var color = RGBA(r: 0, g: 0, b: 0, a: 0)
}

/// What a wlr_buffer the workspace overview renders holds: the windows drawn into it, at their places in
/// its pixels, over a background. The port draws the windows' pictures (no GL render pass).
package struct WlrBuffer: Equatable {
    package struct Item: Equatable {
        package var client: ClientID
        /// The window's box with its border, and the border's width and colour (0: none).
        package var box: CGRect
        package var borderX: Double
        package var borderY: Double
        package var borderColor: RGBA
        /// Whether the window's picture is drawn inside the border (a box of 2 pixels or less has none).
        package var picture: Bool
        package init(client: ClientID, box: CGRect, borderX: Double = 0, borderY: Double = 0,
                     borderColor: RGBA = RGBA(r: 0, g: 0, b: 0, a: 0), picture: Bool = true) {
            self.client = client; self.box = box; self.borderX = borderX; self.borderY = borderY
            self.borderColor = borderColor; self.picture = picture
        }
    }
    package var width: Int
    package var height: Int
    package var background: RGBA
    package var items: [Item]
    package init(width: Int, height: Int, background: RGBA, items: [Item]) {
        self.width = width; self.height = height; self.background = background; self.items = items
    }
}

/// struct wlr_scene_buffer
@MainActor
package final class WlrSceneBuffer: WlrSceneNode {
    package fileprivate(set) var buffer: WlrBuffer?
    package fileprivate(set) var destWidth = 0
    package fileprivate(set) var destHeight = 0
    /// src_box (wlr_fbox); empty is the whole buffer.
    package fileprivate(set) var srcBox = CGRect.zero
}

/// wlr_scene_tree_create
@MainActor @discardableResult
package func wlrSceneTreeCreate(_ parent: WlrSceneTree?) -> WlrSceneTree {
    let tree = WlrSceneTree()
    if let parent { attach(tree, parent) }
    return tree
}

/// wlr_scene_rect_create
@MainActor
package func wlrSceneRectCreate(_ parent: WlrSceneTree, _ width: Int, _ height: Int, _ color: RGBA) -> WlrSceneRect {
    let rect = WlrSceneRect()
    rect.width = width
    rect.height = height
    rect.color = color
    attach(rect, parent)
    return rect
}

/// wlr_scene_buffer_create
@MainActor
package func wlrSceneBufferCreate(_ parent: WlrSceneTree, _ buffer: WlrBuffer?) -> WlrSceneBuffer {
    let node = WlrSceneBuffer()
    node.buffer = buffer
    attach(node, parent)
    return node
}

@MainActor
private func attach(_ node: WlrSceneNode, _ parent: WlrSceneTree) {
    node.parent = parent
    parent.children.append(node)
}

/// wlr_scene_node_destroy
@MainActor
package func wlrSceneNodeDestroy(_ node: WlrSceneNode) {
    node.parent?.children.removeAll { $0 === node }
    node.parent = nil
    if let tree = node as? WlrSceneTree {
        for child in tree.children { child.parent = nil }
        tree.children = []
    }
}

/// wlr_scene_node_set_enabled
@MainActor
package func wlrSceneNodeSetEnabled(_ node: WlrSceneNode, _ enabled: Bool) { node.enabled = enabled }

/// wlr_scene_node_set_position
@MainActor
package func wlrSceneNodeSetPosition(_ node: WlrSceneNode, _ x: Int, _ y: Int) {
    node.x = x
    node.y = y
}

/// wlr_scene_node_raise_to_top
@MainActor
package func wlrSceneNodeRaiseToTop(_ node: WlrSceneNode) {
    guard let parent = node.parent else { return }
    parent.children.removeAll { $0 === node }
    parent.children.append(node)
}

/// wlr_scene_rect_set_size
@MainActor
package func wlrSceneRectSetSize(_ rect: WlrSceneRect, _ width: Int, _ height: Int) {
    rect.width = width
    rect.height = height
}

/// wlr_scene_rect_set_color
@MainActor
package func wlrSceneRectSetColor(_ rect: WlrSceneRect, _ color: RGBA) { rect.color = color }

/// wlr_scene_buffer_set_buffer
@MainActor
package func wlrSceneBufferSetBuffer(_ node: WlrSceneBuffer, _ buffer: WlrBuffer?) { node.buffer = buffer }

/// wlr_scene_buffer_set_dest_size
@MainActor
package func wlrSceneBufferSetDestSize(_ node: WlrSceneBuffer, _ width: Int, _ height: Int) {
    node.destWidth = width
    node.destHeight = height
}

/// wlr_scene_buffer_set_source_box
@MainActor
package func wlrSceneBufferSetSourceBox(_ node: WlrSceneBuffer, _ box: CGRect?) { node.srcBox = box ?? .zero }

/// mango's MangoDimNode (draw/dim-node.h): a box of one colour; its buffer is a scene rect here.
@MainActor
package final class MangoDimNode {
    package let sceneBuffer: WlrSceneRect
    fileprivate init(_ rect: WlrSceneRect) { sceneBuffer = rect }
}

/// mango_dim_node_create
@MainActor
package func mangoDimNodeCreate(_ parent: WlrSceneTree, _ color: RGBA) -> MangoDimNode {
    MangoDimNode(wlrSceneRectCreate(parent, 0, 0, color))
}

/// mango_dim_node_destroy
@MainActor
package func mangoDimNodeDestroy(_ node: MangoDimNode?) {
    if let node { wlrSceneNodeDestroy(node.sceneBuffer) }
}

/// mango_dim_node_set_color
@MainActor
package func mangoDimNodeSetColor(_ node: MangoDimNode?, _ color: RGBA) {
    if let node { wlrSceneRectSetColor(node.sceneBuffer, color) }
}

/// mango_dim_node_set_box
@MainActor
package func mangoDimNodeSetBox(_ node: MangoDimNode?, _ x: Int, _ y: Int, _ width: Int, _ height: Int) {
    guard let node else { return }
    wlrSceneNodeSetPosition(node.sceneBuffer, x, y)
    wlrSceneRectSetSize(node.sceneBuffer, width, height)
}

/// mango_dim_node_set_enabled
@MainActor
package func mangoDimNodeSetEnabled(_ node: MangoDimNode?, _ enabled: Bool) {
    if let node { wlrSceneNodeSetEnabled(node.sceneBuffer, enabled) }
}
