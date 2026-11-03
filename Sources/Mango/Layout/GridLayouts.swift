import Foundation
import CoreGraphics

public enum GridLayouts {
    public static func grid(_ input: LayoutInput) -> LayoutResult {
        let area = IRect(input.workArea)
        let gaps = !input.enableGaps ? (outer: 0, inner: 0) : (outer: input.config.gappoh, inner: input.config.gappih)
        let (rects, places) = gridCore(area: area, shares: shares(input, transpose: false), gapOuter: gaps.outer, gapInner: gaps.inner)
        return assign(input, rects, places, transpose: false)
    }

    public static func verticalGrid(_ input: LayoutInput) -> LayoutResult {
        let area = IRect(input.workArea).transposed
        let gaps = !input.enableGaps ? (outer: 0, inner: 0) : (outer: input.config.gappov, inner: input.config.gappiv)
        let (rects, places) = gridCore(area: area, shares: shares(input, transpose: true), gapOuter: gaps.outer, gapInner: gaps.inner)
        return assign(input, rects, places, transpose: true)
    }

    /// Not in mango: grid shares transposed for the vertical variants.
    static func shares(_ input: LayoutInput, transpose: Bool) -> [GridPlace] {
        input.clients.map { c in
            transpose ? GridPlace(colPer: c.gridRowPer, rowPer: c.gridColPer, colIdx: c.gridRowIdx, rowIdx: c.gridColIdx)
                      : GridPlace(colPer: c.gridColPer, rowPer: c.gridRowPer, colIdx: c.gridColIdx, rowIdx: c.gridRowIdx)
        }
    }

    public static func fair(_ input: LayoutInput) -> LayoutResult {
        let (rects, places) = fairCore(area: IRect(input.workArea), shares: shares(input, transpose: false),
                                       gaps: IGaps(input.smartGapped(input.clients.count == 1)))
        return assign(input, rects, places, transpose: false)
    }

    public static func verticalFair(_ input: LayoutInput) -> LayoutResult {
        let (rects, places) = fairCore(area: IRect(input.workArea).transposed, shares: shares(input, transpose: true),
                                       gaps: IGaps(input.smartGapped(input.clients.count == 1)).transposed)
        return assign(input, rects, places, transpose: true)
    }

    /// Not in mango: hands grid rects back to the clients.
    private static func assign(_ input: LayoutInput, _ rects: [IRect], _ places: [GridPlace], transpose: Bool) -> LayoutResult {
        var frames: [ClientID: IRect] = [:]
        var result: [ClientID: GridPlace] = [:]
        for (i, c) in input.clients.enumerated() where i < rects.count {
            frames[c.id] = transpose ? rects[i].transposed : rects[i]
            if i < places.count {
                let p = places[i]
                result[c.id] = transpose ? GridPlace(colPer: p.rowPer, rowPer: p.colPer, colIdx: p.rowIdx, rowIdx: p.colIdx) : p
            }
        }
        var r = LayoutSupport.finish(input, frames)
        r.gridPlaces = result
        return r
    }

    static func gridCore(area m: IRect, shares: [GridPlace], gapOuter: Int, gapInner: Int) -> ([IRect], [GridPlace]) {
        let n = shares.count
        guard n > 0 else { return ([], []) }
        let go = Float(gapOuter), gi = Float(gapInner)
        let mx = Float(m.x), my = Float(m.y), mw = Float(m.w), mh = Float(m.h)
        func per(_ v: CGFloat) -> Float { v > 0 ? Float(v) : 1 }
        if n == 1 {
            let cw = Int(Float(m.w - 2 * gapOuter) * Float(0.9))
            let ch = Int(Float(m.h - 2 * gapOuter) * Float(0.9))
            return ([IRect(m.x + (m.w - cw) / 2, m.y + (m.h - ch) / 2, cw, ch)], [shares[0]])
        }
        if n == 2 {
            let colPers = [per(shares[0].colPer), per(shares[1].colPer)]
            let sum = colPers[0] + colPers[1]
            let availW = mw - 2 * go - gi
            let ch = Int(Double(m.h - 2 * gapOuter) * 0.65)
            let y = m.y + (m.h - ch) / 2 + gapOuter
            let cw0 = availW * (colPers[0] / sum), cw1 = availW * (colPers[1] / sum)
            return ([IRect(Int(mx + go), y, Int(cw0), ch), IRect(Int(mx + go + cw0 + gi), y, Int(cw1), ch)],
                    [GridPlace(colPer: CGFloat(colPers[0]), rowPer: 1, colIdx: 0, rowIdx: 0),
                     GridPlace(colPer: CGFloat(colPers[1]), rowPer: 1, colIdx: 1, rowIdx: 0)])
        }
        var cols = 0
        while cols * cols < n { cols += 1 }
        let rows = (cols - 1) * cols >= n ? cols - 1 : cols
        let overcols = n % cols
        var colPers = [Float](repeating: 1, count: cols), rowPers = [Float](repeating: 1, count: rows)
        for i in 0..<n {
            let c = i % cols, r = i / cols
            if r == 0 { colPers[c] = per(shares[i].colPer) }
            if c == 0 { rowPers[r] = per(shares[i].rowPer) }
        }
        let sumCol = colPers.reduce(0, +), sumRow = rowPers.reduce(0, +)
        let availW = mw - 2 * go - Float(cols - 1) * gi
        let availH = mh - 2 * go - Float(rows - 1) * gi
        var out: [IRect] = [], places: [GridPlace] = []
        for i in 0..<n {
            let cIdx = i % cols, rIdx = i / cols
            places.append(GridPlace(colPer: CGFloat(colPers[cIdx]), rowPer: CGFloat(rowPers[rIdx]), colIdx: cIdx, rowIdx: rIdx))
            var cx = mx + go
            let cw: Float
            if overcols > 0 && i >= n - overcols {
                var overW: Float = 0
                for j in 0..<overcols { overW += availW * (colPers[j] / sumCol) }
                overW += Float(overcols - 1) * gi
                cx += (mw - overW) / 2 - go
                for j in 0..<cIdx { cx += availW * (colPers[j] / sumCol) + gi }
                cw = availW * (colPers[cIdx] / sumCol)
            } else {
                for j in 0..<cIdx { cx += availW * (colPers[j] / sumCol) + gi }
                cw = cIdx == cols - 1 ? mx + mw - go - cx : availW * (colPers[cIdx] / sumCol)
            }
            var cy = my + go
            for j in 0..<rIdx { cy += availH * (rowPers[j] / sumRow) + gi }
            let ch = rIdx == rows - 1 ? my + mh - go - cy : availH * (rowPers[rIdx] / sumRow)
            out.append(IRect(Int(cx), Int(cy), Int(cw), Int(ch)))
        }
        return (out, places)
    }

    static func fairCore(area m: IRect, shares: [GridPlace], gaps g: IGaps) -> ([IRect], [GridPlace]) {
        let n = shares.count
        guard n > 0 else { return ([], []) }
        var cols = 0
        while cols * cols < n { cols += 1 }
        let baseRows = n / cols
        let remainder = n % cols
        let firstGroupCols = cols - remainder
        let firstGroupCount = firstGroupCols * baseRows
        let maxRows = baseRows + (remainder > 0 ? 1 : 0)
        func place(_ i: Int) -> (col: Int, row: Int) {
            i < firstGroupCount ? (i / baseRows, i % baseRows)
                                : (firstGroupCols + (i - firstGroupCount) / maxRows, (i - firstGroupCount) % maxRows)
        }
        var colPers = [Float](repeating: 0, count: cols), rowPers = [Float](repeating: 0, count: maxRows)
        for i in 0..<n {
            let (c, r) = place(i), s = shares[i]
            if s.colIdx == c && s.colPer > 0 { colPers[c] = Float(s.colPer) }
            if s.rowIdx == r && s.rowPer > 0 { rowPers[r] = Float(s.rowPer) }
        }
        for i in 0..<n {
            let (c, r) = place(i), s = shares[i]
            if colPers[c] == 0 && s.colPer > 0 { colPers[c] = Float(s.colPer) }
            if rowPers[r] == 0 && s.rowPer > 0 { rowPers[r] = Float(s.rowPer) }
        }
        for i in colPers.indices where colPers[i] == 0 { colPers[i] = 1 }
        for i in rowPers.indices where rowPers[i] == 0 { rowPers[i] = 1 }

        func spans(start: Int, length: Int, pers: ArraySlice<Float>, outer: Int, inner: Int) -> [(Float, Float)] {
            let count = pers.count
            guard count > 0 else { return [] }
            let sum = pers.reduce(0, +)
            let avail = Float(length) - 2 * Float(outer) - Float(count - 1) * Float(inner)
            var next = Float(start) + Float(outer)
            var res: [(Float, Float)] = []
            for (k, p) in pers.enumerated() {
                let size = k == count - 1 ? Float(start + length) - Float(outer) - next : avail * (p / sum)
                res.append((next, size))
                next += size + Float(inner)
            }
            return res
        }
        let colSpans = spans(start: m.x, length: m.w, pers: colPers[...], outer: g.oh, inner: g.ih)
        let baseSpans = spans(start: m.y, length: m.h, pers: rowPers[0..<baseRows], outer: g.ov, inner: g.iv)
        let maxSpans = remainder > 0 ? spans(start: m.y, length: m.h, pers: rowPers[...], outer: g.ov, inner: g.iv) : []

        var out: [IRect] = [], places: [GridPlace] = []
        for i in 0..<n {
            let (c, r) = place(i)
            let row = i < firstGroupCount ? baseSpans[r] : maxSpans[r]
            let col = colSpans[c]
            places.append(GridPlace(colPer: CGFloat(colPers[c]), rowPer: CGFloat(rowPers[r]), colIdx: c, rowIdx: r))
            out.append(IRect(Int(col.0), Int(row.0), Int(col.1), Int(row.1)))
        }
        return (out, places)
    }
}
