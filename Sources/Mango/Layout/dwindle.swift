import Foundation
import CoreGraphics

/// mango DwindleNode (layout/dwindle.h).
package final class DwindleNode {
    var isSplit = false
    var splitH = false
    var splitLocked = false
    var customLeafSplitH = false
    var ratio: Float = 0
    var dragInitRatio: Float = 0
    var containerX: Int32 = 0
    var containerY: Int32 = 0
    var containerW: Int32 = 0
    var containerH: Int32 = 0
    weak var parent: DwindleNode?
    var first: DwindleNode?
    var second: DwindleNode?
    weak var client: Client?
}

/// mango CLAMP_FLOAT (common/util.h).
@inline(__always) func CLAMP_FLOAT(_ v: Float, _ lo: Float, _ hi: Float) -> Float { v < lo ? lo : v > hi ? hi : v }

package extension MangoServer {
    // Counts nodes in the same direction (N_old).
    func countBlockItems(_ node: DwindleNode?, _ splitH: Bool) -> Int32 {
        guard let node else { return 0 }
        if !node.isSplit || node.splitH != splitH { return 1 }
        return countBlockItems(node.first, splitH) + countBlockItems(node.second, splitH)
    }

    func dwindleFindLeaf(_ node: DwindleNode?, _ c: Client) -> DwindleNode? {
        guard let node else { return nil }
        if !node.isSplit { return node.client === c ? node : nil }
        let r = dwindleFindLeaf(node.first, c)
        return r ?? dwindleFindLeaf(node.second, c)
    }

    func dwindleFirstLeaf(_ node: DwindleNode?) -> DwindleNode? {
        guard var node else { return nil }
        while node.isSplit, let f = node.first { node = f }
        return node
    }

    // not in mango: no dwindle_free_tree; Swift frees a tree no one holds

    func dwindleRemove(_ root: inout DwindleNode?, _ c: Client) {
        guard let leaf = dwindleFindLeaf(root, c) else { return }

        let parent = leaf.parent

        if dwindleLockedHorizontalNode === leaf || (parent != nil && dwindleLockedHorizontalNode === parent) {
            dwindleLockedHorizontalNode = nil
        }
        if dwindleLockedVerticalNode === leaf || (parent != nil && dwindleLockedVerticalNode === parent) {
            dwindleLockedVerticalNode = nil
        }

        guard let parent else {
            root = nil
            return
        }

        // Starts the proportional rollback for the removed space.

        // Finds the contiguous same-direction block path.
        if config.dwindleManualSplit {
            let splitH = parent.splitH
            var path: [DwindleNode] = [parent]
            var curr = parent.parent
            while let cur = curr, cur.splitH == splitH {
                path.append(cur)
                curr = cur.parent
            }
            let pathLen = path.count
            var p = [Float](repeating: 0, count: pathLen)

            // Computes the old absolute ratio of each ancestor.
            p[pathLen - 1] = 1.0
            var i = pathLen - 1
            while i > 0 {
                let S = path[i]
                let child = path[i - 1]
                if S.first === child {
                    p[i - 1] = p[i] * S.ratio
                } else {
                    p[i - 1] = p[i] * (1.0 - S.ratio)
                }
                i -= 1
            }

            // Computes the absolute area ratio (P_del) that the removed leaf
            // occupies in its direction block.
            var pDel = p[0] * (parent.first === leaf ? parent.ratio : (1.0 - parent.ratio))
            if pDel > 0.999 { pDel = 0.999 } // Fallback.

            // Recomputes ancestor ratios: distribute the space freed by P_del
            // seamlessly to the other windows using their original ratios.
            i = pathLen - 1
            while i > 0 {
                let S = path[i]
                let child = path[i - 1]
                let pS = p[i]
                let pFirst = pS * S.ratio

                var denom = pS - pDel
                if denom < 0.0001 { denom = 0.0001 }

                if S.first === child {
                    S.ratio = (pFirst - pDel) / denom
                } else {
                    S.ratio = pFirst / denom
                }

                if S.ratio < 0.001 { S.ratio = 0.001 }
                if S.ratio > 0.999 { S.ratio = 0.999 }
                i -= 1
            }
        }

        // Ratio recomputation finished.

        // Basic binary-tree node removal logic.
        guard let sibling = parent.first === leaf ? parent.second : parent.first else { return }
        let grandparent = parent.parent

        sibling.parent = grandparent

        if !sibling.isSplit || (!config.dwindlePreserveSplit && !config.dwindleSmartSplit) {
            sibling.containerW = 0
            sibling.containerH = 0
        }

        if let grandparent {
            if grandparent.first === parent {
                grandparent.first = sibling
            } else {
                grandparent.second = sibling
            }
        } else {
            root = sibling
        }
    }

    func dwindleAssign(_ node: DwindleNode?, _ ax: Int32, _ ay: Int32, _ aw: Int32, _ ah: Int32,
                       _ gapH: Int32, _ gapV: Int32, _ ctx: LayoutContext?) {
        guard let node else { return }

        if !node.isSplit {
            if let c = node.client {
                if !c.isfullscreen && !c.ismaximizescreen {
                    let box = wlrBox(ax, ay, MANGO_MAX(1, aw), MANGO_MAX(1, ah))
                    if let ctx, let probe = ctx.probe {
                        if c === probe { ctx.out = box }
                    } else {
                        clientTileResize(c, box, false, nil)
                    }
                }
            }
            return
        }

        if !node.splitLocked && node.containerW == 0 && node.containerH == 0 { node.splitH = aw >= ah }
        node.containerX = ax
        node.containerY = ay
        node.containerW = aw
        node.containerH = ah
        if node.splitH {
            let w1 = MANGO_MAX(1, i32(Float(aw) * node.ratio) - gapH / 2)
            dwindleAssign(node.first, ax, ay, w1, ah, gapH, gapV, ctx)
            dwindleAssign(node.second, ax + w1 + gapH, ay, aw - w1 - gapH, ah, gapH, gapV, ctx)
        } else {
            let h1 = MANGO_MAX(1, i32(Float(ah) * node.ratio) - gapV / 2)
            dwindleAssign(node.first, ax, ay, aw, h1, gapH, gapV, ctx)
            dwindleAssign(node.second, ax, ay + h1 + gapV, aw, ah - h1 - gapV, gapH, gapV, ctx)
        }
    }

    func dwindleNewLeaf(_ c: Client) -> DwindleNode {
        let n = DwindleNode()
        n.client = c
        return n
    }

    // Walks up the direction block path and computes the absolute ratio of each
    // ancestor.
    func getBlockPathAndRatios(_ target: DwindleNode, _ splitH: Bool) -> (path: [DwindleNode], p: [Float]) {
        var path: [DwindleNode] = [target]
        var curr = target.parent
        while let cur = curr, cur.splitH == splitH {
            path.append(cur)
            curr = cur.parent
        }
        let pathLen = path.count
        var p = [Float](repeating: 0, count: pathLen)

        p[pathLen - 1] = 1.0 // The direction block root ratio is 100%.
        var i = pathLen - 1
        while i > 0 {
            let S = path[i]
            let child = path[i - 1]
            if S.first === child {
                p[i - 1] = p[i] * S.ratio
            } else {
                p[i - 1] = p[i] * (1.0 - S.ratio)
            }
            i -= 1
        }
        return (path, p)
    }

    func dwindleInsert(_ root: inout DwindleNode?, _ newC: Client, _ focused: Client?, _ ratio: Float,
                       _ asFirst: Bool, _ splitH: Bool, _ lock: Bool) {
        let newLeaf = dwindleNewLeaf(newC)

        guard let r = root else {
            newLeaf.customLeafSplitH = true
            root = newLeaf
            return
        }

        guard let target = (focused.flatMap { dwindleFindLeaf(r, $0) }) ?? dwindleFirstLeaf(r) else { return }

        // ================= Keep other windows proportional when shrinking
        // =================
        if config.dwindleManualSplit {
            let (path, p) = getBlockPathAndRatios(target, splitH)
            let pathLen = path.count

            var nOld: Int32 = 1
            if pathLen > 1 { nOld = countBlockItems(path[pathLen - 1], splitH) }
            let N = Float(nOld + 1)

            var i = pathLen - 1
            while i > 0 {
                let S = path[i]
                let child = path[i - 1]
                let pS = p[i]
                let pFirst = pS * S.ratio

                if S.first === child {
                    let pFirstNew = pFirst * (N - 1.0) / N + 1.0 / N
                    let pSNew = pS * (N - 1.0) / N + 1.0 / N
                    S.ratio = pFirstNew / pSNew
                } else {
                    let pFirstNew = pFirst * (N - 1.0) / N
                    let pSNew = pS * (N - 1.0) / N + 1.0 / N
                    S.ratio = pFirstNew / pSNew
                }
                if S.ratio < 0.001 { S.ratio = 0.001 }
                if S.ratio > 0.999 { S.ratio = 0.999 }
                i -= 1
            }
        }
        // ============================================================

        let split = DwindleNode()
        split.isSplit = true
        split.splitH = splitH
        split.splitLocked = lock
        split.customLeafSplitH = target.customLeafSplitH
        newLeaf.customLeafSplitH = target.customLeafSplitH

        if asFirst {
            split.first = newLeaf
            split.second = target
        } else {
            split.first = target
            split.second = newLeaf
        }

        // Generic logic.
        split.ratio = ratio

        split.parent = target.parent
        target.parent = split
        newLeaf.parent = split

        if let sp = split.parent {
            if sp.first === target {
                sp.first = split
            } else {
                sp.second = split
            }
        } else {
            root = split
        }
    }

    // not in mango: nil is UNDIR, a target of no direction
    func dwindleMoveNextTo(_ c: Client, _ target: Client?, _ ratio: Float, _ dir: Direction) {
        guard let cmon = c.mon, c !== target else { return }

        guard let target else {
            if let to = monitorFromDirection(dir) { _ = clientJumpToMonitor(c, to, dir) }
            return
        }

        let crossed = c.mon !== target.mon
        let cCx = c.geom.minX + (c.geom.width / 2).rounded(.towardZero)
        let cCy = c.geom.minY + (c.geom.height / 2).rounded(.towardZero)
        let tgeom = target.geom

        guard let tmon = target.mon else { return }
        if !clientJumpToMonitor(c, tmon, dir) && c.mon !== target.mon { return }

        guard let m = c.mon else { return }
        let tag = getMonCurtag(m)
        guard let cLeaf = dwindleFindLeaf(m.pertag.dwindleRoot[tag], c),
              let targetLeaf = dwindleFindLeaf(m.pertag.dwindleRoot[tag], target) else { return }

        if !crossed, let split = cLeaf.parent, split === targetLeaf.parent {
            let first = split.first
            split.first = split.second
            split.second = first
            arrange(m, false, false)
            return
        }

        var area = tgeom
        if !crossed, let parent = cLeaf.parent {
            let sibling = parent.first === cLeaf ? parent.second : parent.first
            if parent.containerW > 0 && parent.containerH > 0 && dwindleFindLeaf(sibling, target) != nil {
                area = wlrBox(parent.containerX, parent.containerY, parent.containerW, parent.containerH)
            }
        }

        let splitH = area.width >= area.height
        let asFirst = splitH ? cCx < tgeom.minX + (tgeom.width / 2).rounded(.towardZero)
            : cCy < tgeom.minY + (tgeom.height / 2).rounded(.towardZero)

        dwindleRemove(&m.pertag.dwindleRoot[tag], c)
        dwindleInsert(&m.pertag.dwindleRoot[tag], c, target, ratio, asFirst, splitH, true)
        arrange(m, false, false)
    }

    // not in mango: only the tree's part; exchange_two_client swaps the layout properties, monitors and
    // list itself (Dispatch.swift)
    func dwindleSwapClients(_ c1: Client, _ c2: Client) {
        guard let m1 = c1.mon, let m2 = c2.mon, c1 !== c2 else { return }

        let c1node = dwindleFindLeaf(m1.pertag.dwindleRoot[getMonCurtag(m1)], c1)
        let c2node = dwindleFindLeaf(m2.pertag.dwindleRoot[getMonCurtag(m2)], c2)

        c1node?.client = c2
        c2node?.client = c1
    }

    func dwindleResizeClient(_ m: Monitor, _ c: Client) {
        let tag = getMonCurtag(m)
        guard let leaf = dwindleFindLeaf(m.pertag.dwindleRoot[tag], c) else { return }

        if !startDragWindow {
            startDragWindow = true
            dwindleLockedHorizontalNode = nil
            dwindleLockedVerticalNode = nil
            dragBeginCursor = system.pointer   // not in mango: the port's cursor
            var node = leaf.parent
            while let n = node {
                if n.splitH && dwindleLockedHorizontalNode == nil {
                    dwindleLockedHorizontalNode = n
                    n.dragInitRatio = n.ratio
                }
                if !n.splitH && dwindleLockedVerticalNode == nil {
                    dwindleLockedVerticalNode = n
                    n.dragInitRatio = n.ratio
                }
                if dwindleLockedHorizontalNode != nil && dwindleLockedVerticalNode != nil { break }
                node = n.parent
            }
        }

        if dwindleLockedHorizontalNode == nil && dwindleLockedVerticalNode == nil { return }

        let cursor = system.pointer   // not in mango: the port's cursor
        if let h = dwindleLockedHorizontalNode {
            let cw = Float(MANGO_MAX(1, h.containerW))
            var ox = Float(cursor.x - dragBeginCursor.x)
            if config.dwindleSmartResize {
                /* Move the boundary toward the cursor: invert direction when
                 * the drag started on the right side of the split line. */
                let splitX = Float(h.containerX) + cw * h.dragInitRatio
                if Float(dragBeginCursor.x) >= splitX { ox = -ox }
            }
            h.ratio = h.dragInitRatio + ox / cw
            h.ratio = CLAMP_FLOAT(h.ratio, 0.05, 0.95)
        }

        if let v = dwindleLockedVerticalNode {
            let ch = Float(MANGO_MAX(1, v.containerH))
            var oy = Float(cursor.y - dragBeginCursor.y)
            if config.dwindleSmartResize {
                /* Same logic for the vertical split line. */
                let splitY = Float(v.containerY) + ch * v.dragInitRatio
                if Float(dragBeginCursor.y) >= splitY { oy = -oy }
            }
            v.ratio = v.dragInitRatio + oy / ch
            v.ratio = CLAMP_FLOAT(v.ratio, 0.05, 0.95)
        }

        let n = m.visibleTilingClients
        var gapIh: Int32 = enableGaps ? m.gappih : 0
        var gapIv: Int32 = enableGaps ? m.gappiv : 0
        var gapOh: Int32 = enableGaps ? m.gappoh : 0
        var gapOv: Int32 = enableGaps ? m.gappov : 0
        if config.smartgaps && n == 1 { gapIh = 0; gapIv = 0; gapOh = 0; gapOv = 0 }

        let w = WBox(m.w)
        dwindleAssign(m.pertag.dwindleRoot[tag], w.x + gapOh, w.y + gapOv, w.width - 2 * gapOh,
                      w.height - 2 * gapOv, gapIh, gapIv, nil)
    }

    func dwindleResizeClientStep(_ m: Monitor, _ c: Client, _ dx: Int32, _ dy: Int32) {
        let tag = getMonCurtag(m)
        guard let leaf = dwindleFindLeaf(m.pertag.dwindleRoot[tag], c) else { return }

        var hNode: DwindleNode?
        var vNode: DwindleNode?
        var node = leaf.parent

        while let n = node {
            if n.splitH && hNode == nil { hNode = n }
            if !n.splitH && vNode == nil { vNode = n }
            if hNode != nil && vNode != nil { break }
            node = n.parent
        }

        if hNode == nil && vNode == nil { return }

        if let h = hNode, dx != 0 {
            let cw = Float(MANGO_MAX(1, h.containerW))
            let delta = Float(dx) / cw
            h.ratio = CLAMP_FLOAT(h.ratio + delta, 0.05, 0.95)
        }

        if let v = vNode, dy != 0 {
            let ch = Float(MANGO_MAX(1, v.containerH))
            let delta = Float(dy) / ch
            v.ratio = CLAMP_FLOAT(v.ratio + delta, 0.05, 0.95)
        }

        let nClients = m.visibleTilingClients
        var gapIh: Int32 = enableGaps ? m.gappih : 0
        var gapIv: Int32 = enableGaps ? m.gappiv : 0
        var gapOh: Int32 = enableGaps ? m.gappoh : 0
        var gapOv: Int32 = enableGaps ? m.gappov : 0
        if config.smartgaps && nClients == 1 { gapIh = 0; gapIv = 0; gapOh = 0; gapOv = 0 }

        let w = WBox(m.w)
        dwindleAssign(m.pertag.dwindleRoot[tag], w.x + gapOh, w.y + gapOv, w.width - 2 * gapOh,
                      w.height - 2 * gapOv, gapIh, gapIv, nil)
    }

    func dwindleRemoveClient(_ c: Client) {
        for m in monitors {
            for t in 0..<PERTAG_SLOTS { dwindleRemove(&m.pertag.dwindleRoot[t], c) }
        }
    }

    /* Insert a new client respecting dwindle_vsplit, dwindle_hsplit, and
     * dwindle_smart_split config options. */
    func dwindleInsertWithConfig(_ root: inout DwindleNode?, _ newC: Client, _ focused: Client?, _ ratioIn: Float) {
        guard let focused else { return }
        var ratio = ratioIn

        var asFirst = false
        var splitH = false
        var lock = false

        let fg = focused.geom
        let fcx = Double(fg.minX) + Double(fg.width) * 0.5
        let fcy = Double(fg.minY) + Double(fg.height) * 0.5
        let cursor = system.pointer   // not in mango: the port's cursor

        if config.dwindleSmartSplit {
            let nx = (Double(cursor.x) - fcx) / (Double(fg.width) * 0.5)
            let ny = (Double(cursor.y) - fcy) / (Double(fg.height) * 0.5)

            if abs(ny) > abs(nx) {
                splitH = false // vertical split
                asFirst = ny < 0 // top → new window on top
            } else {
                splitH = true // horizontal split
                asFirst = nx < 0 // left → new window on left
            }
            lock = true // lock split direction
        } else {
            // normal mode, auto split
            let likelyH = fg.width >= fg.height
            splitH = likelyH

            if likelyH {
                if config.dwindleHsplit == 0 {
                    asFirst = Double(cursor.x) < fcx
                } else {
                    asFirst = config.dwindleHsplit == 2
                }
            } else {
                if config.dwindleVsplit == 0 {
                    asFirst = Double(cursor.y) < fcy
                } else {
                    asFirst = config.dwindleVsplit == 2
                }
            }
        }

        var target = dwindleFindLeaf(root, focused)
        if target == nil && root != nil { target = dwindleFirstLeaf(root) }

        // Computes the exact 1/N ratio for the new node if and only if
        // manual_split=1.
        if config.dwindleManualSplit, let target {
            splitH = target.customLeafSplitH
            lock = true
            asFirst = false

            // ================= Compute the 1/N ratio of the new node
            // =================
            let (path, p) = getBlockPathAndRatios(target, splitH)
            let pathLen = path.count

            var nOld: Int32 = 1
            if pathLen > 1 { nOld = countBlockItems(path[pathLen - 1], splitH) }
            let N = Float(nOld + 1)

            let pTargetOld = p[0]
            let pSplitNew = pTargetOld * (N - 1.0) / N + 1.0 / N

            if asFirst {
                ratio = (1.0 / N) / pSplitNew
            } else {
                ratio = (pTargetOld * (N - 1.0) / N) / pSplitNew
            }

            if ratio < 0.001 { ratio = 0.001 }
            if ratio > 0.999 { ratio = 0.999 }
            // =========================================================
        }

        // Calls the generic insert function.
        dwindleInsert(&root, newC, focused, ratio, asFirst, splitH, lock)
    }

    func dwindleCore(_ m: Monitor, _ ctx: LayoutContext?) {
        let n = m.visibleTilingClients
        if n == 0 { return }

        let tag = getMonCurtag(m)
        let ratio = Float(config.dwindleSplitRatio)

        var vis: [Client] = []
        for c in clients where VISIBLEON(c, m) && ISTILED(c) { vis.append(c) }

        // Removes clients that no longer exist from the tree.
        var leaves: [DwindleNode] = []
        var stack: [DwindleNode] = []
        if let r = m.pertag.dwindleRoot[tag] { stack.append(r) }
        while let nd = stack.popLast() {
            if !nd.isSplit {
                leaves.append(nd)
            } else {
                if let s = nd.second { stack.append(s) }
                if let f = nd.first { stack.append(f) }
            }
        }

        for leaf in leaves {
            guard let lc = leaf.client else {
                // not in mango: a leaf whose client is gone (freed in mango) is taken out
                removeDeadLeaf(&m.pertag.dwindleRoot[tag], leaf)
                continue
            }
            if !vis.contains(where: { $0 === lc }) {
                if VISIBLEON(lc, m) && (lc.isfullscreen || lc.ismaximizescreen) { continue }
                dwindleRemove(&m.pertag.dwindleRoot[tag], lc)
            }
        }

        // Gets the focused client, falling back to the first visible tiled client
        // if none.
        var focused = clientFocusTop(m)
        if let f = focused, dwindleFindLeaf(m.pertag.dwindleRoot[tag], f) == nil {
            focused = m.sel.flatMap { clientByIdAll($0) }
        }

        if focused == nil && !vis.isEmpty { focused = vis[0] }

        for c in vis where dwindleFindLeaf(m.pertag.dwindleRoot[tag], c) == nil {
            dwindleInsertWithConfig(&m.pertag.dwindleRoot[tag], c, focused, ratio)
        }

        var gapIh: Int32 = enableGaps ? m.gappih : 0
        var gapIv: Int32 = enableGaps ? m.gappiv : 0
        var gapOh: Int32 = enableGaps ? m.gappoh : 0
        var gapOv: Int32 = enableGaps ? m.gappov : 0
        if config.smartgaps && n == 1 { gapIh = 0; gapIv = 0; gapOh = 0; gapOv = 0 }

        let w = WBox(m.w)
        dwindleAssign(m.pertag.dwindleRoot[tag], w.x + gapOh, w.y + gapOv, w.width - 2 * gapOh,
                      w.height - 2 * gapOv, gapIh, gapIv, ctx)
    }

    /// Not in mango: a leaf whose Client was freed (mango removes it in handle_client_destroy first).
    private func removeDeadLeaf(_ root: inout DwindleNode?, _ leaf: DwindleNode) {
        guard let parent = leaf.parent else { root = nil; return }
        guard let sibling = parent.first === leaf ? parent.second : parent.first else { return }
        sibling.parent = parent.parent
        if let gp = parent.parent {
            if gp.first === parent { gp.first = sibling } else { gp.second = sibling }
        } else {
            root = sibling
        }
    }

    func dwindle(_ m: Monitor) { dwindleCore(m, nil) }
}
