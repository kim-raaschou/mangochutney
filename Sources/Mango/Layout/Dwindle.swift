import Foundation
import CoreGraphics

public final class DwindleTree {
    final class Node {
        var isSplit = false
        var splitH = false
        var splitLocked = false
        var customLeafSplitH = false
        var ratio: Float = 0.5
        var dragInitRatio: Float = 0.5
        var container: IRect?
        weak var parent: Node?
        var first: Node?
        var second: Node?
        var client: ClientID?
        var lastFrame: IRect?

        init(client: ClientID? = nil) { self.client = client }

        var sibling: Node? {
            guard let p = parent else { return nil }
            return p.first === self ? p.second : p.first
        }
    }

    private var root: Node?
    private weak var lockedHorizontalNode: Node?
    private weak var lockedVerticalNode: Node?
    private var knownFrames: [ClientID: CGRect] = [:]

    public init() {}

    // not in mango: whether dwindle_find_leaf finds it
    public func contains(_ id: ClientID) -> Bool { dwindleFindLeaf(id) != nil }

    public func dwindleFocusBlockRoot(_ sc: ClientID, _ fc: ClientID) -> Set<ClientID>? {
        guard let s = dwindleFindLeaf(sc), let f = dwindleFindLeaf(fc), s !== f, let fp = f.parent else { return nil }
        func depth(_ n: Node) -> Int { var d = 0; var x = n; while let p = x.parent { d += 1; x = p }; return d }
        var a: Node? = s, b: Node? = f
        var da = depth(s), db = depth(f)
        while da > db { a = a?.parent; da -= 1 }
        while db > da { b = b?.parent; db -= 1 }
        while let x = a, let y = b, x !== y { a = x.parent; b = y.parent }
        guard let lca = a, lca === fp, let branch = lca.first === f ? lca.second : lca.first, branch.isSplit else { return nil }
        return Set(leaves(branch).compactMap(\.client))
    }

    public var clientOrder: [ClientID] { leaves(root).compactMap(\.client) }

    private func dwindleFindLeaf(_ id: ClientID, in node: Node? = nil) -> Node? {
        guard let node = node ?? root else { return nil }
        if !node.isSplit { return node.client == id ? node : nil }
        if let f = node.first, let r = dwindleFindLeaf(id, in: f) { return r }
        if let s = node.second, let r = dwindleFindLeaf(id, in: s) { return r }
        return nil
    }

    /// Not in mango: a helper of the dwindle tree.
    private func leaves(_ node: Node?) -> [Node] {
        guard let node else { return [] }
        if !node.isSplit { return [node] }
        return leaves(node.first) + leaves(node.second)
    }

    private func dwindleFirstLeaf(_ node: Node?) -> Node? {
        var n = node
        while let c = n, c.isSplit { n = c.first }
        return n
    }

    public func dwindleCore(_ input: LayoutInput) -> LayoutResult {
        let ids = input.clients.map(\.id)
        guard !ids.isEmpty else { return LayoutResult() }
        let idSet = Set(ids)
        for c in input.clients { knownFrames[c.id] = c.currentFrame }
        knownFrames = knownFrames.filter { idSet.contains($0.key) }

        for leaf in leaves(root) {
            if let c = leaf.client, !idSet.contains(c), !input.fullscreenInView.contains(c) {
                dwindleRemove(c, config: input.config)
            }
        }

        let anchor = input.focusedID ?? ids.first
        for id in ids where !contains(id) {
            dwindleInsertWithConfig(id, nextTo: anchor, config: input.config, cursor: input.cursor)
        }

        let m = IRect(input.workArea), g = IGaps(input.smartGapped(ids.count == 1))
        var frames: [ClientID: IRect] = [:]
        if let root {
            dwindleAssign(root, IRect(m.x + g.oh, m.y + g.ov, m.w - 2 * g.oh, m.h - 2 * g.ov),
                   gapH: g.ih, gapV: g.iv, into: &frames)
        }
        return LayoutSupport.finish(input, frames)
    }

    private func dwindleAssign(_ node: Node, _ a: IRect, gapH: Int, gapV: Int, into frames: inout [ClientID: IRect]) {
        if !node.isSplit {
            let box = IRect(a.x, a.y, max(1, a.w), max(1, a.h))
            node.lastFrame = box
            if let c = node.client { frames[c] = box }
            return
        }
        if !node.splitLocked && node.container == nil {
            node.splitH = a.w >= a.h
        }
        node.container = a
        let ratio = node.ratio
        if node.splitH {
            let w1 = max(1, Int(Float(a.w) * ratio) - gapH / 2)
            if let f = node.first { dwindleAssign(f, IRect(a.x, a.y, w1, a.h), gapH: gapH, gapV: gapV, into: &frames) }
            if let s = node.second {
                dwindleAssign(s, IRect(a.x + w1 + gapH, a.y, a.w - w1 - gapH, a.h), gapH: gapH, gapV: gapV, into: &frames)
            }
        } else {
            let h1 = max(1, Int(Float(a.h) * ratio) - gapV / 2)
            if let f = node.first { dwindleAssign(f, IRect(a.x, a.y, a.w, h1), gapH: gapH, gapV: gapV, into: &frames) }
            if let s = node.second {
                dwindleAssign(s, IRect(a.x, a.y + h1 + gapV, a.w, a.h - h1 - gapV), gapH: gapH, gapV: gapV, into: &frames)
            }
        }
    }

    private func countBlockItems(_ node: Node?, splitH: Bool) -> Int {
        guard let node else { return 0 }
        if !node.isSplit || node.splitH != splitH { return 1 }
        return countBlockItems(node.first, splitH: splitH) + countBlockItems(node.second, splitH: splitH)
    }

    private func getBlockPathAndRatios(_ target: Node, splitH: Bool) -> (path: [Node], p: [Float]) {
        var path = [target]
        var cur = target.parent
        while let c = cur, c.splitH == splitH {
            path.append(c)
            cur = c.parent
        }
        var p = [Float](repeating: 0, count: path.count)
        p[path.count - 1] = 1
        var i = path.count - 1
        while i > 0 {
            let s = path[i], child = path[i - 1]
            p[i - 1] = s.first === child ? p[i] * s.ratio : p[i] * (1 - s.ratio)
            i -= 1
        }
        return (path, p)
    }

    public func dwindleInsertWithConfig(_ id: ClientID, nextTo focused: ClientID?, config: Config, cursor: CGPoint) {
        guard !contains(id) else { return }
        guard let root else {
            let leaf = Node(client: id)
            leaf.customLeafSplitH = true
            self.root = leaf
            return
        }
        let target = focused.flatMap { dwindleFindLeaf($0) } ?? dwindleFirstLeaf(root)!
        let fg: CGRect = focused.flatMap { knownFrames[$0] } ?? target.lastFrame?.cg
            ?? target.client.flatMap { knownFrames[$0] } ?? .zero
        let fcx = Double(fg.minX) + Double(fg.width) * 0.5
        let fcy = Double(fg.minY) + Double(fg.height) * 0.5

        var asFirst = false
        var splitH = false
        var lock = false
        var ratio = Float(config.dwindleSplitRatio)

        if config.dwindleSmartSplit {
            let nx = fg.width > 0 ? (Double(cursor.x) - fcx) / (Double(fg.width) * 0.5) : 0
            let ny = fg.height > 0 ? (Double(cursor.y) - fcy) / (Double(fg.height) * 0.5) : 0
            if abs(ny) > abs(nx) {
                splitH = false; asFirst = ny < 0
            } else {
                splitH = true; asFirst = nx < 0
            }
            lock = true
        } else {
            let likelyH = fg.width >= fg.height
            splitH = likelyH
            if likelyH {
                asFirst = config.dwindleHsplit == 0 ? Double(cursor.x) < fcx : config.dwindleHsplit == 2
            } else {
                asFirst = config.dwindleVsplit == 0 ? Double(cursor.y) < fcy : config.dwindleVsplit == 2
            }
        }

        if config.dwindleManualSplit {
            splitH = target.customLeafSplitH
            lock = true
            asFirst = false
            let (path, p) = getBlockPathAndRatios(target, splitH: splitH)
            let nOld = path.count > 1 ? countBlockItems(path[path.count - 1], splitH: splitH) : 1
            let N = Float(nOld + 1)
            let pTargetOld = p[0]
            let pSplitNew = pTargetOld * (N - 1) / N + 1 / N
            ratio = min(0.999, max(0.001, (pTargetOld * (N - 1) / N) / pSplitNew))
        }

        dwindleInsert(id, target: target, ratio: ratio, asFirst: asFirst, splitH: splitH, lock: lock, config: config)
    }

    // not in mango: pointer_place_drag_tile's part for the dwindle tree
    public func drop(_ id: ClientID, nextTo target: ClientID, asFirst: Bool, splitH: Bool, lock: Bool, config: Config) {
        guard id != target else { return }
        dwindleRemove(id, config: config)
        guard let t = dwindleFindLeaf(target) else { return }
        dwindleInsert(id, target: t, ratio: Float(config.dwindleSplitRatio), asFirst: asFirst, splitH: splitH,
                  lock: lock, config: config)
    }

    private func dwindleInsert(_ id: ClientID, target: Node, ratio: Float, asFirst: Bool,
                           splitH: Bool, lock: Bool, config: Config) {
        let newLeaf = Node(client: id)
        if config.dwindleManualSplit {
            let (path, p) = getBlockPathAndRatios(target, splitH: splitH)
            let nOld = path.count > 1 ? countBlockItems(path[path.count - 1], splitH: splitH) : 1
            let N = Float(nOld + 1)
            var i = path.count - 1
            while i > 0 {
                let s = path[i], child = path[i - 1]
                let pS = p[i], pFirst = pS * s.ratio
                let pSNew = pS * (N - 1) / N + 1 / N
                let pFirstNew = s.first === child ? pFirst * (N - 1) / N + 1 / N : pFirst * (N - 1) / N
                s.ratio = min(0.999, max(0.001, pFirstNew / pSNew))
                i -= 1
            }
        }
        let split = Node()
        split.isSplit = true
        split.splitH = splitH
        split.splitLocked = lock
        split.customLeafSplitH = target.customLeafSplitH
        newLeaf.customLeafSplitH = target.customLeafSplitH
        if asFirst {
            split.first = newLeaf; split.second = target
        } else {
            split.first = target; split.second = newLeaf
        }
        split.ratio = ratio
        let oldParent = target.parent
        split.parent = oldParent
        target.parent = split
        newLeaf.parent = split
        if let gp = oldParent {
            if gp.first === target { gp.first = split } else { gp.second = split }
        } else {
            root = split
        }
    }

    public func dwindleRemove(_ id: ClientID, config: Config) {
        guard let leaf = dwindleFindLeaf(id) else { return }
        guard let parent = leaf.parent else {
            root = nil
            return
        }
        if config.dwindleManualSplit {
            let splitH = parent.splitH
            var path = [parent]
            var cur = parent.parent
            while let c = cur, c.splitH == splitH { path.append(c); cur = c.parent }
            var p = [Float](repeating: 0, count: path.count)
            p[path.count - 1] = 1
            var i = path.count - 1
            while i > 0 {
                let s = path[i], child = path[i - 1]
                p[i - 1] = s.first === child ? p[i] * s.ratio : p[i] * (1 - s.ratio)
                i -= 1
            }
            let pDel = min(0.999, p[0] * (parent.first === leaf ? parent.ratio : 1 - parent.ratio))
            i = path.count - 1
            while i > 0 {
                let s = path[i], child = path[i - 1]
                let pS = p[i], pFirst = pS * s.ratio
                let denom = max(0.0001, pS - pDel)
                s.ratio = min(0.999, max(0.001, s.first === child ? (pFirst - pDel) / denom : pFirst / denom))
                i -= 1
            }
        }
        guard let sibling = leaf.sibling else { return }
        let grandparent = parent.parent
        sibling.parent = grandparent
        if !sibling.isSplit || (!config.dwindlePreserveSplit && !config.dwindleSmartSplit) {
            sibling.container = nil
        }
        if let gp = grandparent {
            if gp.first === parent { gp.first = sibling } else { gp.second = sibling }
        } else {
            root = sibling
        }
        leaf.parent = nil
        knownFrames[id] = nil
    }

    public func dwindleFreeTree() {
        root = nil
        knownFrames = [:]
    }

    // not in mango: client_replace's part for the dwindle tree
    public func replace(_ old: ClientID, with new: ClientID, config: Config) {
        guard old != new else { return }
        dwindleRemove(new, config: config)
        dwindleFindLeaf(old)?.client = new
    }

    public func dwindleSwapClients(_ a: ClientID, _ b: ClientID) {
        guard a != b else { return }
        let la = dwindleFindLeaf(a), lb = dwindleFindLeaf(b)
        la?.client = b
        lb?.client = a
    }

    public func dwindleMoveNextTo(_ id: ClientID, nextTo target: ClientID, direction: Direction, crossed: Bool = false,
                                  origin: CGRect? = nil, config: Config) {
        guard id != target, let cLeaf = dwindleFindLeaf(id), let tLeaf = dwindleFindLeaf(target) else { return }
        if !crossed, let p = cLeaf.parent, p === tLeaf.parent {
            let f = p.first
            p.first = p.second
            p.second = f
            return
        }
        let cg = origin ?? cLeaf.lastFrame?.cg ?? knownFrames[id] ?? .zero
        let tg = tLeaf.lastFrame?.cg ?? knownFrames[target] ?? .zero
        let cCx = Int(cg.minX) + Int(cg.width) / 2, cCy = Int(cg.minY) + Int(cg.height) / 2
        var area = IRect(tg)
        if !crossed, let parent = cLeaf.parent, let sib = cLeaf.sibling, let cont = parent.container,
           cont.w > 0, cont.h > 0, dwindleFindLeaf(target, in: sib) != nil {
            area = cont
        }
        let splitH = area.w >= area.h
        let tx = Int(tg.minX) + Int(tg.width) / 2, ty = Int(tg.minY) + Int(tg.height) / 2
        let asFirst = splitH ? cCx < tx : cCy < ty
        dwindleRemove(id, config: config)
        guard let newTarget = dwindleFindLeaf(target) else { return }
        dwindleInsert(id, target: newTarget, ratio: Float(config.dwindleSplitRatio), asFirst: asFirst,
                  splitH: splitH, lock: true, config: config)
    }

    public func dwindleResizeClientStep(_ id: ClientID, dx: CGFloat, dy: CGFloat, config: Config) {
        guard let leaf = dwindleFindLeaf(id) else { return }
        var hNode: Node?, vNode: Node?
        var node = leaf.parent
        while let n = node {
            if n.splitH && hNode == nil { hNode = n }
            if !n.splitH && vNode == nil { vNode = n }
            if hNode != nil && vNode != nil { break }
            node = n.parent
        }
        if let h = hNode, dx != 0 {
            let cw = Float(max(1, h.container?.w ?? 1))
            h.ratio = min(max(h.ratio + Float(dx) / cw, 0.05), 0.95)
        }
        if let v = vNode, dy != 0 {
            let ch = Float(max(1, v.container?.h ?? 1))
            v.ratio = min(max(v.ratio + Float(dy) / ch, 0.05), 0.95)
        }
    }

    public func dwindleResizeClient(_ id: ClientID, startDragWindow: inout Bool, dragBeginCursor: inout CGPoint,
                                    cursor: CGPoint, smartResize: Bool) -> Bool {
        guard let leaf = dwindleFindLeaf(id) else { return false }
        if !startDragWindow {
            startDragWindow = true
            lockedHorizontalNode = nil
            lockedVerticalNode = nil
            dragBeginCursor = cursor
            var node = leaf.parent
            while let n = node {
                if n.splitH && lockedHorizontalNode == nil {
                    lockedHorizontalNode = n
                    n.dragInitRatio = n.ratio
                }
                if !n.splitH && lockedVerticalNode == nil {
                    lockedVerticalNode = n
                    n.dragInitRatio = n.ratio
                }
                if lockedHorizontalNode != nil && lockedVerticalNode != nil { break }
                node = n.parent
            }
        }
        if lockedHorizontalNode == nil && lockedVerticalNode == nil { return false }
        let begin = dragBeginCursor
        if let h = lockedHorizontalNode {
            let c = h.container ?? IRect(0, 0, 0, 0)
            let cw = Float(max(1, c.w))
            var ox = Float(cursor.x - begin.x)
            if smartResize && Float(begin.x) >= Float(c.x) + cw * h.dragInitRatio { ox = -ox }
            h.ratio = min(max(h.dragInitRatio + ox / cw, 0.05), 0.95)
        }
        if let v = lockedVerticalNode {
            let c = v.container ?? IRect(0, 0, 0, 0)
            let ch = Float(max(1, c.h))
            var oy = Float(cursor.y - begin.y)
            if smartResize && Float(begin.y) >= Float(c.y) + ch * v.dragInitRatio { oy = -oy }
            v.ratio = min(max(v.dragInitRatio + oy / ch, 0.05), 0.95)
        }
        return true
    }

    // not in mango: dwindle_set_split_direction's leaf, on the tree (`nil`: toggled)
    public func dwindleSetSplitDirection(_ id: ClientID, horizontal: Bool?) {
        guard let leaf = dwindleFindLeaf(id) else { return }
        leaf.customLeafSplitH = horizontal ?? !leaf.customLeafSplitH
    }

    public func dwindleToggleCurrentSplit(for id: ClientID) {
        guard let parent = dwindleFindLeaf(id)?.parent else { return }
        parent.splitH.toggle()
        parent.splitLocked = true
    }

    /// Not in mango: reads a leaf's preferred split direction.
    public func leafSplitHorizontal(for id: ClientID) -> Bool? { dwindleFindLeaf(id)?.customLeafSplitH }
}
