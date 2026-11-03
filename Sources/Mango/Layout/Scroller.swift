import Foundation
import CoreGraphics

public final class ScrollerState {
    private var cols: [[ClientID]] = []
    private var centerRequest: ClientID?

    public init() {}

    // not in mango: find_scroller_node over the port's scroller columns
    public func contains(_ id: ClientID) -> Bool { cols.contains { $0.contains(id) } }

    private func columnIndex(of id: ClientID) -> Int? { cols.firstIndex { $0.contains(id) } }

    /// Not in mango: a helper of the scroller state.
    public func column(of id: ClientID) -> [ClientID] {
        columnIndex(of: id).map { cols[$0] } ?? []
    }

    /// Not in mango: a helper of the scroller state.
    public func columns(for clients: [ClientID]) -> [[ClientID]] {
        let set = Set(clients)
        var out: [[ClientID]] = cols.map { $0.filter { set.contains($0) } }.filter { !$0.isEmpty }
        for id in clients where !contains(id) { out.append([id]) }
        return out
    }

    /// Not in mango: a helper of the scroller state.
    public func position(of id: ClientID, in clients: [ClientID]) -> (column: Int, row: Int)? {
        for (ci, col) in columns(for: clients).enumerated() {
            if let r = col.firstIndex(of: id) { return (ci, r) }
        }
        return nil
    }

    // not in mango: the column client_insert_tiling_order's place gives, in the port's scroller columns
    public func insert(_ id: ClientID, afterFocused focused: ClientID?) {
        guard !contains(id) else { return }
        if let f = focused, let ci = columnIndex(of: f) {
            cols.insert([id], at: ci + 1)
        } else {
            cols.append([id])
        }
    }

    public func scrollerNodeRemove(_ id: ClientID) {
        guard let ci = columnIndex(of: id) else { return }
        cols[ci].removeAll { $0 == id }
        if cols[ci].isEmpty { cols.remove(at: ci) }
        if centerRequest == id { centerRequest = nil }
    }

    public func exitScrollerStack(_ id: ClientID) {
        guard let ci = columnIndex(of: id), cols[ci].count > 1 else { return }
        cols[ci].removeAll { $0 == id }
        cols.insert([id], at: ci + 1)
    }

    /// Not in mango: the port keeps the column order here, where mango's is the client
    /// list's; `id`'s column goes first (zoom put it first in the list).
    public func moveColumnToFront(_ id: ClientID) {
        guard let ci = columnIndex(of: id), ci > 0 else { return }
        cols.insert(cols.remove(at: ci), at: 0)
    }

    public func clearScrollerState() {
        cols = []
        centerRequest = nil
    }

    @discardableResult
    public func scrollerApplyStack(_ id: ClientID, direction: Direction, vertical: Bool, clientOrder: [ClientID]) -> Bool {
        if !vertical && !direction.isHorizontal { return false }
        if vertical && direction.isHorizontal { return false }
        for c in clientOrder where !contains(c) { cols.append([c]) }
        guard let ci = columnIndex(of: id) else { return false }
        let prev = direction == .left || direction == .up

        if cols[ci].count > 1 {
            cols[ci].removeAll { $0 == id }
            cols.insert([id], at: prev ? ci : ci + 1)
            return true
        }
        let visible = Set(clientOrder)
        var ti = ci
        repeat {
            ti += prev ? -1 : 1
        } while ti >= 0 && ti < cols.count && !cols[ti].contains(where: { visible.contains($0) })
        guard ti >= 0 && ti < cols.count else { return false }
        cols[ti].append(id)
        cols.remove(at: ci)
        return true
    }

    public func scrollerDropTile(_ id: ClientID, onto target: ClientID, intoStack: Bool, before: Bool) {
        guard id != target else { return }
        scrollerNodeRemove(id)
        if !contains(target) { cols.append([target]) }
        guard let ci = columnIndex(of: target) else { return }
        if intoStack {
            let ri = cols[ci].firstIndex(of: target)!
            cols[ci].insert(id, at: before ? ri : ri + 1)
        } else {
            cols.insert([id], at: before ? ci : ci + 1)
        }
    }

    public func centerWindow(_ id: ClientID) { centerRequest = id }

    // not in mango: client_replace's part for the port's scroller columns
    public func replace(_ old: ClientID, with new: ClientID) {
        guard old != new else { return }
        scrollerNodeRemove(new)
        cols = cols.map { $0.map { $0 == old ? new : $0 } }
    }

    public func exchangeTwoScrollerClients(_ a: ClientID, _ b: ClientID) {
        guard a != b else { return }
        let ia = columnIndex(of: a), ib = columnIndex(of: b)
        switch (ia, ib) {
        case let (x?, y?) where x == y:
            guard let ra = cols[x].firstIndex(of: a), let rb = cols[x].firstIndex(of: b) else { return }
            cols[x].swapAt(ra, rb)
        case let (x?, y?):
            cols.swapAt(x, y)
        case let (x?, nil):
            cols[x] = cols[x].map { $0 == a ? b : $0 }
        case let (nil, y?):
            cols[y] = cols[y].map { $0 == b ? a : $0 }
        default:
            break
        }
    }

    private func updateScrollerState(_ input: LayoutInput) {
        let ids = input.clients.map(\.id)
        let set = Set(ids)
        cols = cols.map { $0.filter { set.contains($0) } }.filter { !$0.isEmpty }
        let unknown = ids.filter { !contains($0) }
        guard !unknown.isEmpty else { return }
        let index = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        for id in unknown {
            let i = index[id] ?? Int.max
            let at = cols.firstIndex { (index[$0[0]] ?? Int.max) > i } ?? cols.count
            cols.insert([id], at: at)
        }
    }

    public func arrange(_ input: LayoutInput, vertical: Bool) -> LayoutResult {
        guard !input.clients.isEmpty else { return LayoutResult() }
        updateScrollerState(input)
        let byID = Dictionary(input.clients.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let columns = cols.map { $0.compactMap { byID[$0] } }.filter { !$0.isEmpty }

        let work = vertical ? LayoutSupport.transposed(input) : input
        let workByID = Dictionary(work.clients.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let wcols = columns.map { $0.compactMap { workByID[$0.id] } }
        let req = centerRequest
        centerRequest = nil
        let (frames, colRects) = scrollerCore(work, wcols, centerRequest: req)

        let mon = IRect(input.monitorFrame)
        var out: [ClientID: IRect] = [:]
        var hidden = Set<ClientID>()
        for (ci, col) in wcols.enumerated() {
            let cr = vertical ? colRects[ci].transposed : colRects[ci]
            // Not in mango: a column wholly off the monitor is parked (mango's scene clips it).
            let offscreen = cr.x + cr.w <= mon.x || cr.x >= mon.x + mon.w
                || cr.y + cr.h <= mon.y || cr.y >= mon.y + mon.h
            for c in col {
                guard let f = frames[c.id] else { continue }
                out[c.id] = vertical ? f.transposed : f
                if offscreen { hidden.insert(c.id) }
            }
        }
        return LayoutSupport.finish(input, out, hidden: hidden, applyFullscreen: false)
    }

    private func scrollerCore(_ input: LayoutInput, _ heads: [[LayoutClient]],
                      centerRequest: ClientID?) -> ([ClientID: IRect], [IRect]) {
        let nHeads = heads.count
        let m = IRect(input.workArea), mon = IRect(input.monitorFrame), g = IGaps(input.smartGapped(nHeads == 1, iv: false))
        let cfg = input.config, pt = input.pertag
        let structs = cfg.scrollerStructs
        var frames: [ClientID: IRect] = [:]
        var colRects = [IRect](repeating: IRect(0, 0, 1, 1), count: nHeads)
        guard nHeads > 0 else { return (frames, colRects) }

        let maxClientWidth = m.w - 2 * structs - g.ih
        func propOf(_ c: LayoutClient) -> Float {
            Float(c.scrollerProportion ?? pt.scrollerDefaultProportion)
        }
        func prop(_ i: Int) -> Float { propOf(heads[i][0]) }
        func width(of proportion: Float) -> Int { Int(Float(maxClientWidth) * proportion) }
        func rightAnchoredX(_ proportion: Float) -> Int {
            Int(Float(m.x) + (Float(m.w) - proportion * Float(maxClientWidth) - Float(structs)))
        }
        func insideMon(_ r: IRect) -> Bool {
            r.x >= mon.x && r.y >= mon.y && r.x + r.w <= mon.x + mon.w && r.y + r.h <= mon.y + mon.h
        }
        func horizontalCheckScrollerRootInsideMon(_ r: inout IRect) {
            if !insideMon(r) { r.x = m.x + (m.w - r.w) / 2 }
        }
        func scrollerArrangeStackNode(_ col: [LayoutClient], _ geom: IRect) {
            let raw = col.map { Float($0.scrollerStackWeight) }
            let positive = raw.filter { $0 > 0 }
            var weights = raw
            var total: Float = 0
            if positive.isEmpty {
                weights = raw.map { _ in 1 }
                total = Float(raw.count)
            } else {
                total = positive.reduce(0, +)
                let avg = total / Float(positive.count)
                for i in weights.indices where weights[i] <= 0 { weights[i] = avg; total += avg }
            }
            var y = geom.y
            var remain = geom.h - (col.count - 1) * g.iv
            var remainProp: Float = 1
            for (k, c) in col.enumerated() {
                let p = weights[k] / total
                let h = Int(Float(remain) * (p / remainProp))
                frames[c.id] = IRect(geom.x, y, geom.w, h)
                remainProp -= p
                remain -= h
                y += h + g.iv
            }
        }
        func horizontalScrollAdjustFullandmax(_ c: LayoutClient, _ r: inout IRect) {
            if c.isFullscreen {
                r.h = mon.h; r.w = mon.w; r.y = mon.y
            } else if c.isMaximized {
                r.h = m.h - 2 * g.ov; r.w = m.w - 2 * g.oh; r.y = m.y + g.ov
            } else {
                r.h = m.h - 2 * g.ov; r.y = m.y + (m.h - r.h) / 2
            }
        }

        let head0 = heads[0][0]
        if nHeads == 1 && !pt.scrollerIgnoreProportionSingle && !head0.isFullscreen && !head0.isMaximized {
            let single = Float(head0.scrollerProportionSingle ?? pt.scrollerDefaultProportionSingle)
            var r = IRect(0, 0, 0, m.h - 2 * g.ov)
            r.w = Int(Float(m.w - 2 * g.oh) * single)
            r.x = m.x + (m.w - r.w) / 2
            r.y = m.y + (m.h - r.h) / 2
            horizontalCheckScrollerRootInsideMon(&r)
            scrollerArrangeStackNode(heads[0], r)
            colRects[0] = r
            return (frames, colRects)
        }

        var fi = -1
        if let f = input.focusedID { fi = heads.firstIndex { $0.contains { $0.id == f } } ?? -1 }
        if fi < 0, let p = input.prevFocusedID { fi = heads.firstIndex { $0.contains { $0.id == p } } ?? -1 }
        if fi < 0 { fi = nHeads / 2 }

        let root = heads[fi][0]
        var rootGeom = IRect(root.currentFrame)
        if let req = centerRequest, heads[fi].contains(where: { $0.id == req }),
           !root.isFullscreen, !root.isMaximized {
            rootGeom.x = m.x + (m.w - rootGeom.w) / 2
        }

        var needScroller = !(rootGeom.x >= m.x + structs && rootGeom.x + rootGeom.w <= m.x + m.w - structs)
        var needOverspread = cfg.scrollerPreferOverspread && nHeads > 1
            && (fi == 0 || fi == nHeads - 1) && prop(fi) < 1.0
        var overspreadToLeft = false
        if needOverspread {
            overspreadToLeft = fi == 0
            if overspreadToLeft
                && (!insideMon(IRect(heads[1][0].currentFrame)) || prop(1) + prop(0) >= 1.0) {
                needScroller = true
            } else if !overspreadToLeft
                && (!insideMon(IRect(heads[fi - 1][0].currentFrame)) || prop(fi - 1) + prop(fi) >= 1.0) {
                needScroller = true
            } else {
                needOverspread = false
            }
        }

        let prevClause: Bool
        if let p = input.prevFocusedID {
            let prevProp: Float?
            if let known = input.prevFocusedScroll {
                prevProp = known.tiled ? Float(known.proportion) : nil
            } else {
                prevProp = input.clients.first(where: { $0.id == p }).map(propOf)
            }
            if let pp = prevProp {
                prevClause = pp * Float(maxClientWidth) + prop(fi) * Float(maxClientWidth)
                    > Float(m.w - 2 * structs - g.ih)
            } else {
                prevClause = false
            }
        } else {
            prevClause = true
        }
        let needCenter = cfg.scrollerFocusCenter || nHeads == 1
            || (cfg.scrollerPreferCenter && !needOverspread && prevClause)
        if nHeads == 1 && pt.scrollerIgnoreProportionSingle { needScroller = true }
        if input.startDragWindow { needScroller = false }

        var t = IRect(0, 0, width(of: prop(fi)), 0)
        horizontalScrollAdjustFullandmax(root, &t)
        if root.isFullscreen {
            t.x = mon.x
        } else if root.isMaximized {
            t.x = m.x + g.oh
        } else if needScroller {
            if needCenter {
                t.x = m.x + (m.w - t.w) / 2
            } else if needOverspread {
                t.x = overspreadToLeft ? m.x + structs : rightAnchoredX(prop(fi))
            } else {
                t.x = rootGeom.x > m.x + m.w / 2 ? rightAnchoredX(prop(fi)) : m.x + structs
            }
        } else {
            t.x = rootGeom.x
        }
        horizontalCheckScrollerRootInsideMon(&t)
        scrollerArrangeStackNode(heads[fi], t)
        colRects[fi] = t

        if fi > 0 {
            for i in 1...fi {
                let ci = fi - i
                var r = IRect(0, 0, width(of: prop(ci)), 0)
                horizontalScrollAdjustFullandmax(heads[ci][0], &r)
                r.x = colRects[ci + 1].x - g.ih - r.w
                scrollerArrangeStackNode(heads[ci], r)
                colRects[ci] = r
            }
        }
        if fi + 1 < nHeads {
            for ci in (fi + 1)..<nHeads {
                var r = IRect(0, 0, width(of: prop(ci)), 0)
                horizontalScrollAdjustFullandmax(heads[ci][0], &r)
                r.x = colRects[ci - 1].x + g.ih + colRects[ci - 1].w
                scrollerArrangeStackNode(heads[ci], r)
                colRects[ci] = r
            }
        }
        return (frames, colRects)
    }
}
