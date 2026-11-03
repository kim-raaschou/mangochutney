import Foundation
import CoreGraphics

public enum OverviewLayout {
    struct PRect { var x: Float, y: Float, w: Float, h: Float }

    public static func overviewScale(clients: [(id: ClientID, size: CGSize)], workArea: CGRect,
                            gapInner: CGFloat, gapOuter: CGFloat) -> [ClientID: CGRect] {
        guard !clients.isEmpty else { return [:] }
        let gi = Float(gapInner), go = Float(gapOuter)

        struct Item { var id: ClientID; var w: Float; var h: Float; var index: Int
            var area: Float { w * h } }
        var list: [Item] = []
        for (i, c) in clients.enumerated() {
            var w = Float(c.size.width), h = Float(c.size.height)
            if w <= 0 || h <= 0 { w = 100; h = 100 }
            list.append(Item(id: c.id, w: w, h: h, index: i))
        }
        let items = list.sorted { a, b in a.area != b.area ? a.area > b.area : a.index < b.index }

        let availW = max(1, Float(workArea.width) - 2 * go)
        let availH = max(1, Float(workArea.height) - 2 * go)

        func placeAll(_ s: Float) -> [PRect]? {
            var placed: [PRect] = []
            for it in items {
                guard let r = tryPlace(placed, w: it.w * s, h: it.h * s, gap: gi, availW: availW, availH: availH)
                else { return nil }
                placed.append(r)
            }
            return placed
        }

        var low: Float = 0, high: Float = 1, best: Float = 0
        for _ in 0..<50 {
            let mid = (low + high) / 2
            if placeAll(mid) != nil {
                best = mid; low = mid
            } else {
                high = mid
            }
        }

        guard best > 0, var placed = placeAll(best) else { return [:] }
        centerPlacedRows(&placed, gap: gi)

        var boxW: Float = 0, boxH: Float = 0
        for p in placed {
            boxW = max(boxW, p.x + p.w)
            boxH = max(boxH, p.y + p.h)
        }
        let dx = (availW - boxW) / 2
        let dy = (availH - boxH) / 2
        let baseX = Float(workArea.minX) + go + dx
        let baseY = Float(workArea.minY) + go + dy

        var out: [ClientID: CGRect] = [:]
        for (k, it) in items.enumerated() {
            let w = it.w * best, h = it.h * best
            let ix = Int(baseX + placed[k].x + 0.5)
            let iy = Int(baseY + placed[k].y + 0.5)
            let iw = Int(Float(ix) + w + 0.5) - ix
            let ih = Int(Float(iy) + h + 0.5) - iy
            out[it.id] = CGRect(x: ix, y: iy, width: max(1, iw), height: max(1, ih))
        }
        return out
    }

    public static func overviewScaleTab(clients: [(id: ClientID, size: CGSize)], focused: ClientID?,
                              workArea: CGRect, gapInner: CGFloat, gapOuter: CGFloat,
                              centerRatio: CGFloat, titleBlockHeight: CGFloat = 0) -> [ClientID: CGRect] {
        let n = clients.count
        guard n > 0 else { return [:] }
        var out: [ClientID: CGRect] = [:]
        let focusIdx = focused.flatMap { f in clients.firstIndex { $0.id == f } } ?? 0

        func size(_ c: (id: ClientID, size: CGSize)) -> (w: Float, h: Float) {
            let w = Float(c.size.width), h = Float(c.size.height)
            return w <= 0 || h <= 0 ? (100, 100) : (w, h)
        }
        func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> CGRect {
            CGRect(x: x, y: y, width: max(1, w), height: max(1, h))
        }

        var gapMid = Float(gapOuter), gapEdge = Float(gapInner)
        if gapMid < gapEdge { swap(&gapMid, &gapEdge) }
        gapMid *= 0.5
        let availW = max(1, Float(workArea.width) - 2 * gapEdge)
        let availH = max(1, Float(workArea.height) - 2 * gapEdge)
        let centerW = availW * Float(centerRatio)
        let sideW = max(1, (availW - centerW - 2 * gapMid) * 0.5)
        let baseX = Float(workArea.minX) + gapEdge
        let baseY = Float(workArea.minY) + gapEdge
        let leftX = baseX
        let centerX = baseX + sideW + gapMid
        let rightX = centerX + centerW + gapMid

        do {
            var block = titleBlockHeight > 0 ? Float(titleBlockHeight) : 0
            if block >= availH { block = 0 }
            let (ow, oh) = size(clients[focusIdx])
            var w = centerW
            var h = w * (oh / ow)
            let maxH = availH - block
            if h > maxH {
                let s = maxH / h
                w *= s; h *= s
            }
            let ix = Int(centerX + (centerW - w) / 2 + 0.5)
            let iy = Int(baseY + (availH - (h + block)) / 2 + 0.5)
            out[clients[focusIdx].id] = box(ix, iy, Int(w), Int(h))
        }

        let rest = n - 1
        let rightCount = (rest + 1) / 2
        let leftCount = rest - rightCount
        let right = (0..<rightCount).map { clients[(focusIdx + 1 + $0) % n] }
        let left = (0..<leftCount).map { clients[(focusIdx - 1 - $0 + n) % n] }

        func overviewLayoutColumn(_ items: [(id: ClientID, size: CGSize)], x: Float, top: Float, colW: Float, colH: Float, gap: Float) {
            guard !items.isEmpty else { return }
            var ws = [Float](), hs = [Float]()
            var totalH: Float = 0
            for it in items {
                let (ow, oh) = size(it)
                ws.append(colW)
                hs.append(colW * (oh / ow))
                totalH += hs[hs.count - 1]
            }
            let gapTotal = gap * Float(items.count - 1)
            if totalH + gapTotal > colH {
                var s = (colH - gapTotal) / totalH
                if s < 0 { s = 0.01 }
                for i in ws.indices { ws[i] *= s; hs[i] *= s }
                totalH *= s
            }
            var y = top
            if totalH + gapTotal < colH { y = top + (colH - (totalH + gapTotal)) / 2 }
            for (i, it) in items.enumerated() {
                let ix = Int(x + (colW - ws[i]) / 2 + 0.5)
                let iy = Int(y + 0.5)
                out[it.id] = box(ix, iy, Int(ws[i]), Int(hs[i]))
                y += hs[i] + gap
            }
        }
        overviewLayoutColumn(left, x: leftX, top: baseY, colW: sideW, colH: availH, gap: gapEdge)
        overviewLayoutColumn(right, x: rightX, top: baseY, colW: sideW, colH: availH, gap: gapEdge)
        return out
    }

    static func tryPlace(_ placed: [PRect], w: Float, h: Float, gap: Float,
                         availW: Float, availH: Float) -> PRect? {
        var cands: [(Float, Float)] = [(0, 0)]
        for p in placed {
            cands.append((p.x + p.w + gap, p.y))
            cands.append((p.x, p.y + p.h + gap))
            cands.append((p.x + p.w + gap, p.y + p.h + gap))
        }
        var unique: [(Float, Float)] = []
        for c in cands where !unique.contains(where: { abs($0.0 - c.0) < 0.5 && abs($0.1 - c.1) < 0.5 }) {
            unique.append(c)
        }
        var best: (Float, Float)?
        for (cx, cy) in unique {
            if cx < 0 || cy < 0 || cx + w > availW || cy + h > availH { continue }
            let overlap = placed.contains { p in
                !(cx + w + gap <= p.x || cx >= p.x + p.w + gap || cy + h + gap <= p.y || cy >= p.y + p.h + gap)
            }
            if overlap { continue }
            if let b = best {
                if cy < b.1 || (abs(cy - b.1) < 0.5 && cx < b.0) { best = (cx, cy) }
            } else {
                best = (cx, cy)
            }
        }
        guard let b = best else { return nil }
        return PRect(x: b.0, y: b.1, w: w, h: h)
    }

    static func centerPlacedRows(_ placed: inout [PRect], gap: Float) {
        let n = placed.count
        guard n > 1 else { return }
        var rowOf = [Int](repeating: 0, count: n)
        var rowY: [Float] = []
        for i in 0..<n {
            if let r = rowY.firstIndex(where: { abs(placed[i].y - $0) < 0.5 }) {
                rowOf[i] = r
            } else {
                rowOf[i] = rowY.count
                rowY.append(placed[i].y)
            }
        }
        let rowOrder = rowY.indices.sorted { rowY[$0] < rowY[$1] }
        func span(_ r: Int) -> (Float, Float) {
            var left: Float = 1e30, right: Float = -1e30
            for i in 0..<n where rowOf[i] == r {
                left = min(left, placed[i].x)
                right = max(right, placed[i].x + placed[i].w)
            }
            return (left, right)
        }
        var gridW: Float = 0
        for r in rowY.indices {
            let (l, rt) = span(r)
            gridW = max(gridW, rt - l)
        }
        for r in rowOrder {
            let (left, right) = span(r)
            var delta = gridW * 0.5 - (left + (right - left) * 0.5)
            var lo: Float = -1e30, hi: Float = 1e30
            for i in 0..<n where rowOf[i] == r {
                let a = placed[i]
                for j in 0..<n where rowOf[j] != r {
                    let b = placed[j]
                    if !(a.y + a.h + gap <= b.y || a.y >= b.y + b.h + gap) {
                        if b.x < a.x {
                            lo = max(lo, b.x + b.w + gap - a.x)
                        } else {
                            hi = min(hi, b.x - gap - a.x - a.w)
                        }
                    }
                }
            }
            lo = max(lo, -left)
            hi = min(hi, gridW - right)
            if lo <= hi {
                delta = min(max(delta, lo), hi)
                if abs(delta) > 0.5 {
                    for i in 0..<n where rowOf[i] == r { placed[i].x += delta }
                }
            }
        }
    }
}
