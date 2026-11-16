import CoreGraphics

package extension MangoServer {
    func verticalTileCore(_ m: Monitor, _ ctx: LayoutContext?) {
        var i: Int32, n: Int32 = 0, wd: Int32, r: Int32, mh: Int32, mx: Int32, tx: Int32
        let ie: Int32 = enableGaps ? 1 : 0
        var mfact: Double = 0
        var masterNum: Int32 = 0
        var stackNum: Int32 = 0
        let tag = getMonCurtag(m)
        let w = WBox(m.screen.workArea)

        n = m.visibleFakeTilingClients
        masterNum = Int32(m.pertag.nmasters[tag])
        masterNum = n > masterNum ? masterNum : n
        stackNum = n - masterNum

        if n == 0 { return }

        var curGapih: Int32 = enableGaps ? m.gappih : 0
        var curGapiv: Int32 = enableGaps ? m.gappiv : 0
        var curGapoh: Int32 = enableGaps ? m.gappoh : 0
        var curGapov: Int32 = enableGaps ? m.gappov : 0

        curGapih = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGapih
        curGapiv = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGapiv
        curGapoh = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGapoh
        curGapov = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGapov

        guard let fc = clients.first(where: { VISIBLEON($0, m) && ISFAKETILED($0) }) else { return }

        mfact = fc.masterMfactPer > 0.0 ? Double(fc.masterMfactPer) : Double(m.pertag.mfacts[tag])

        if n > Int32(m.pertag.nmasters[tag]) {
            mh = m.pertag.nmasters[tag] != 0 ? i32(Double(w.height + curGapiv * ie) * mfact) : 0
        } else {
            mh = w.height - 2 * curGapov + curGapiv * ie
        }

        i = 0
        mx = curGapoh
        tx = curGapoh

        var masterSurplusWidth = w.width - 2 * curGapoh - curGapih * ie * (masterNum - 1)
        var masterSurplusRatio: Float = 1.0

        var slaveSurplusWidth = w.width - 2 * curGapoh - curGapih * ie * (stackNum - 1)
        var slaveSurplusRatio: Float = 1.0

        for c in clients {
            if !VISIBLEON(c, m) || !ISFAKETILED(c) { continue }
            if i < Int32(m.pertag.nmasters[tag]) {
                r = MANGO_MIN(n, Int32(m.pertag.nmasters[tag])) - i
                if c.masterInnerPer > 0.0 {
                    wd = i32(Double(masterSurplusWidth) * Double(c.masterInnerPer) / Double(masterSurplusRatio))
                    if r == 1 { wd = w.width - mx - curGapoh }   // not in mango: the last one takes the rest, as in mango's own center_tile (a mango bug, docs/afvigelser.md §6)
                    masterSurplusWidth = masterSurplusWidth - wd
                    masterSurplusRatio = Float(Double(masterSurplusRatio) - Double(c.masterInnerPer))
                    c.masterMfactPer = CGFloat(mfact)
                } else {
                    wd = (w.width - mx - curGapih - curGapih * ie * (r - 1)) / r
                    c.masterInnerPer = CGFloat(wd / (w.width - mx - curGapih - curGapih * ie * (r - 1)))
                    c.masterMfactPer = CGFloat(mfact)
                }
                clientTileResize(c, wlrBox(w.x + mx, w.y + curGapov, wd, mh - curGapiv * ie), false, ctx)
                mx += wd + curGapih * ie // Accumulates using the theoretical width.
            } else {
                r = n - i
                if c.stackInnerPer > 0.0 {
                    wd = i32(Double(slaveSurplusWidth) * Double(c.stackInnerPer) / Double(slaveSurplusRatio))
                    if r == 1 { wd = w.width - tx - curGapoh }   // not in mango: the last one takes the rest, as in mango's own center_tile (a mango bug, docs/afvigelser.md §6)
                    slaveSurplusWidth = slaveSurplusWidth - wd
                    slaveSurplusRatio = Float(Double(slaveSurplusRatio) - Double(c.stackInnerPer))
                    c.masterMfactPer = CGFloat(mfact)
                } else {
                    wd = (w.width - tx - curGapih - curGapih * ie * (r - 1)) / r
                    c.stackInnerPer = CGFloat(wd / (w.width - tx - curGapih - curGapih * ie * (r - 1)))
                    c.masterMfactPer = CGFloat(mfact)
                }

                clientTileResize(c, wlrBox(w.x + tx, w.y + mh + curGapov, wd, w.height - mh - 2 * curGapov), false, ctx)
                tx += wd + curGapih * ie // Accumulates using the theoretical width.
            }
            i += 1
        }
    }

    func verticalDeckCore(_ m: Monitor, _ ctx: LayoutContext?) {
        var mh: Int32, mx: Int32
        var i: Int32, n: Int32 = 0
        let tag = getMonCurtag(m)
        let w = WBox(m.screen.workArea)
        let nmasters = Int32(m.pertag.nmasters[tag])

        var curGappiv: Int32 = enableGaps ? m.gappiv : 0
        var curGappoh: Int32 = enableGaps ? m.gappoh : 0
        var curGappov: Int32 = enableGaps ? m.gappov : 0

        curGappiv = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappiv
        curGappoh = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappoh
        curGappov = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappov

        n = m.visibleFakeTilingClients

        if n == 0 { return }

        guard let fc = clients.first(where: { VISIBLEON($0, m) && ISFAKETILED($0) }) else { return }

        let mfact: Float = fc.masterMfactPer > 0.0 ? Float(fc.masterMfactPer) : m.pertag.mfacts[tag]

        if n > nmasters {
            mh = nmasters != 0 ? Int32((Double(Float(w.height - 2 * curGappov) * mfact)).rounded()) : 0
        } else {
            mh = w.height - 2 * curGappov
        }

        i = 0
        mx = 0
        for c in clients {
            if !VISIBLEON(c, m) || !ISFAKETILED(c) { continue }
            if i < nmasters {
                c.masterMfactPer = CGFloat(mfact)
                let wd = (w.width - 2 * curGappoh - mx) / (MANGO_MIN(n, nmasters) - i)
                clientTileResize(c, wlrBox(w.x + curGappoh + mx, w.y + curGappov, wd, mh), false, ctx)
                mx += wd
            } else {
                c.masterMfactPer = CGFloat(mfact)
                clientTileResize(c, wlrBox(w.x + curGappoh, w.y + mh + curGappov + curGappiv,
                                           w.width - 2 * curGappoh, w.height - mh - 2 * curGappov - curGappiv), false, ctx)
                if ctx == nil { clientUpdateVisibility(c) }
            }
            i += 1
        }
    }

    // not in mango: client_is_x11_popup is false; macOS has no X11 popups
    private func verticalGridCounts(_ c: Client, _ m: Monitor) -> Bool {
        VISIBLEON(c, m) && !c.isunglobal
    }

    func verticalGridCore(_ m: Monitor, _ ctx: LayoutContext?) {
        var i: Int32, n: Int32
        var cw: Int32, ch: Int32
        var rows: Int32, cols: Int32, overrows: Int32
        let w = WBox(m.screen.workArea)
        let targetGappo: Int32 = enableGaps ? Int32(config.gappov) : 0
        let targetGappi: Int32 = enableGaps ? Int32(config.gappiv) : 0
        let singleWidthRatio: Float = 0.9
        let singleHeightRatio: Float = 0.9

        n = m.visibleFakeTilingClients
        if n == 0 { return }

        if n == 1 {
            for c in clients {
                if c.mon !== m { continue }
                if verticalGridCounts(c, m) {
                    ch = i32(Float(w.height - 2 * targetGappo) * singleHeightRatio)
                    cw = i32(Float(w.width - 2 * targetGappo) * singleWidthRatio)
                    clientTileResize(c, wlrBox(w.x + (w.width - cw) / 2, w.y + (w.height - ch) / 2, cw, ch), false, ctx)
                    return
                }
            }
        }

        if n == 2 {
            var rowPers: [Float] = [1.0, 1.0]
            // First extracts the existing row ratios of these two windows.
            i = 0
            for c in clients {
                if c.mon !== m { continue }
                if verticalGridCounts(c, m) {
                    if i < 2 { rowPers[Int(i)] = c.gridRowPer > 0.0 ? Float(c.gridRowPer) : 1.0 }
                    i += 1
                }
            }

            let sumRow = rowPers[0] + rowPers[1]
            let availH = Float(w.height - 2 * targetGappo - targetGappi)
            cw = i32(Double(w.width - 2 * targetGappo) * 0.65) // Keeps the pleasing width of 0.65.

            i = 0
            for c in clients {
                if c.mon !== m { continue }
                if verticalGridCounts(c, m) {
                    c.gridColIdx = 0
                    c.gridRowIdx = Int(i)
                    c.gridColPer = 1.0
                    c.gridRowPer = CGFloat(rowPers[Int(i)])

                    // Computes the current window height dynamically from the
                    // assigned weight.
                    ch = i32(availH * (rowPers[Int(i)] / sumRow))

                    let x = w.x + (w.width - cw) / 2 + targetGappo
                    var y: Int32 = 0
                    if i == 0 {
                        y = w.y + targetGappo
                    } else if i == 1 {
                        // The second window Y coordinate follows right after the
                        // first window.
                        let ch0 = availH * (rowPers[0] / sumRow)
                        y = i32(Float(w.y + targetGappo) + ch0 + Float(targetGappi))
                    }
                    clientTileResize(c, wlrBox(x, y, cw, ch), false, ctx)
                    i += 1
                }
            }
            return
        }
        rows = 0
        while rows <= n / 2 {
            if rows * rows >= n { break }
            rows += 1
        }
        cols = (rows != 0 && (rows - 1) * rows >= n) ? rows - 1 : rows
        overrows = n % rows

        var colPers = [Float](repeating: 1.0, count: Int(cols))
        var rowPers = [Float](repeating: 1.0, count: Int(rows))

        i = 0
        for c in clients {
            if c.mon !== m { continue }
            if verticalGridCounts(c, m) {
                let cIdx = i / rows
                let rIdx = i % rows
                if rIdx == 0 { colPers[Int(cIdx)] = c.gridColPer > 0.0 ? Float(c.gridColPer) : 1.0 }
                if cIdx == 0 { rowPers[Int(rIdx)] = c.gridRowPer > 0.0 ? Float(c.gridRowPer) : 1.0 }
                i += 1
            }
        }

        var sumCol: Float = 0.0, sumRow: Float = 0.0
        for v in colPers { sumCol += v }
        for v in rowPers { sumRow += v }

        let availW = Float(w.width - 2 * targetGappo - (cols - 1) * targetGappi)
        let availH = Float(w.height - 2 * targetGappo - (rows - 1) * targetGappi)

        i = 0
        for c in clients {
            if c.mon !== m { continue }
            if verticalGridCounts(c, m) {
                let cIdx = i / rows
                let rIdx = i % rows

                c.gridColPer = CGFloat(colPers[Int(cIdx)])
                c.gridRowPer = CGFloat(rowPers[Int(rIdx)])
                c.gridColIdx = Int(cIdx)
                c.gridRowIdx = Int(rIdx)

                var flCy = Float(w.y + targetGappo)
                var flCh: Float = 0.0

                if overrows != 0 && i >= n - overrows {
                    var overH: Float = 0.0
                    for j in 0..<Int(overrows) { overH += availH * (rowPers[j] / sumRow) }
                    overH += Float((overrows - 1) * targetGappi)
                    let dy = (Float(w.height) - overH) / 2.0 - Float(targetGappo)

                    flCy += dy
                    for j in 0..<Int(rIdx) { flCy += availH * (rowPers[j] / sumRow) + Float(targetGappi) }
                    flCh = availH * (rowPers[Int(rIdx)] / sumRow)
                } else {
                    for j in 0..<Int(rIdx) { flCy += availH * (rowPers[j] / sumRow) + Float(targetGappi) }
                    flCh = rIdx == rows - 1 ? Float(w.y + w.height - targetGappo) - flCy
                        : availH * (rowPers[Int(rIdx)] / sumRow)
                }

                var flCx = Float(w.x + targetGappo)
                for j in 0..<Int(cIdx) { flCx += availW * (colPers[j] / sumCol) + Float(targetGappi) }
                let flCw = cIdx == cols - 1 ? Float(w.x + w.width - targetGappo) - flCx
                    : availW * (colPers[Int(cIdx)] / sumCol)

                clientTileResize(c, wlrBox(i32(flCx), i32(flCy), i32(flCw), i32(flCh)), false, ctx)
                i += 1
            }
        }
    }

    func verticalFairCore(_ m: Monitor, _ ctx: LayoutContext?) {
        var n: Int32 = 0
        let w = WBox(m.screen.workArea)

        n = m.visibleFakeTilingClients
        if n == 0 { return }

        var curGappiv: Int32 = enableGaps ? m.gappiv : 0
        var curGappih: Int32 = enableGaps ? m.gappih : 0
        var curGappov: Int32 = enableGaps ? m.gappov : 0
        var curGappoh: Int32 = enableGaps ? m.gappoh : 0

        if config.smartgaps && n == 1 {
            curGappiv = 0; curGappih = 0; curGappov = 0; curGappoh = 0
        }

        var rows: Int32 = 0
        while rows <= n {
            if rows * rows >= n { break }
            rows += 1
        }

        let baseCols = n / rows
        let remainder = n % rows
        let firstGroupRows = rows - remainder
        let firstGroupCount = firstGroupRows * baseCols
        let maxCols = baseCols + (remainder > 0 ? 1 : 0)

        var arr: [Client] = []
        var rowPers = [Float](repeating: 0, count: Int(rows))
        var colPers = [Float](repeating: 0, count: Int(maxCols))
        var rowY = [Float](repeating: 0, count: Int(rows))
        var rowH = [Float](repeating: 0, count: Int(rows))
        var colXBase = [Float](repeating: 0, count: Int(baseCols))
        var colWBase = [Float](repeating: 0, count: Int(baseCols))
        var colXMax = [Float](repeating: 0, count: Int(maxCols))
        var colWMax = [Float](repeating: 0, count: Int(maxCols))
        for c in clients where VISIBLEON(c, m) && ISFAKETILED(c) {
            arr.append(c)
            if arr.count >= Int(n) { break }
        }

        func place(_ i: Int32) -> (row: Int32, col: Int32) {
            i < firstGroupCount ? (i / baseCols, i % baseCols)
                : (firstGroupRows + (i - firstGroupCount) / maxCols, (i - firstGroupCount) % maxCols)
        }

        for (k, c) in arr.enumerated() {
            let (rowIdx, colIdx) = place(Int32(k))
            if c.gridRowIdx == Int(rowIdx) && c.gridRowPer > 0.0 { rowPers[Int(rowIdx)] = Float(c.gridRowPer) }
            if c.gridColIdx == Int(colIdx) && c.gridColPer > 0.0 { colPers[Int(colIdx)] = Float(c.gridColPer) }
        }
        for (k, c) in arr.enumerated() {
            let (rowIdx, colIdx) = place(Int32(k))
            if rowPers[Int(rowIdx)] == 0.0 && c.gridRowPer > 0.0 { rowPers[Int(rowIdx)] = Float(c.gridRowPer) }
            if colPers[Int(colIdx)] == 0.0 && c.gridColPer > 0.0 { colPers[Int(colIdx)] = Float(c.gridColPer) }
        }

        var sumRow: Float = 0.0
        for k in 0..<Int(rows) {
            if rowPers[k] == 0.0 { rowPers[k] = 1.0 }
            sumRow += rowPers[k]
        }
        for k in 0..<Int(maxCols) where colPers[k] == 0.0 { colPers[k] = 1.0 }

        let availH = Float(w.height - 2 * curGappov - (rows - 1) * curGappiv)
        var nextY = Float(w.y + curGappov)
        for k in 0..<Int(rows) {
            rowY[k] = nextY
            rowH[k] = k == Int(rows) - 1 ? Float(w.y + w.height - curGappov) - nextY : availH * (rowPers[k] / sumRow)
            nextY += rowH[k] + Float(curGappiv)
        }

        var sumColBase: Float = 0.0
        for k in 0..<Int(baseCols) { sumColBase += colPers[k] }
        let availWBase = Float(w.width - 2 * curGappoh - (baseCols - 1) * curGappih)
        var nextX = Float(w.x + curGappoh)
        for k in 0..<Int(baseCols) {
            colXBase[k] = nextX
            colWBase[k] = k == Int(baseCols) - 1 ? Float(w.x + w.width - curGappoh) - nextX
                : availWBase * (colPers[k] / sumColBase)
            nextX += colWBase[k] + Float(curGappih)
        }

        if remainder > 0 {
            var sumColMax: Float = 0.0
            for k in 0..<Int(maxCols) { sumColMax += colPers[k] }
            let availWMax = Float(w.width - 2 * curGappoh - (maxCols - 1) * curGappih)
            nextX = Float(w.x + curGappoh)
            for k in 0..<Int(maxCols) {
                colXMax[k] = nextX
                colWMax[k] = k == Int(maxCols) - 1 ? Float(w.x + w.width - curGappoh) - nextX
                    : availWMax * (colPers[k] / sumColMax)
                nextX += colWMax[k] + Float(curGappih)
            }
        }

        for (k, c) in arr.enumerated() {
            let i = Int32(k)
            var rowIdx: Int32, colIdx: Int32
            var flCx: Float, flCw: Float

            if i < firstGroupCount {
                rowIdx = i / baseCols
                colIdx = i % baseCols
                flCx = colXBase[Int(colIdx)]
                flCw = colWBase[Int(colIdx)]
            } else {
                let offset = i - firstGroupCount
                rowIdx = firstGroupRows + (offset / maxCols)
                colIdx = offset % maxCols
                flCx = colXMax[Int(colIdx)]
                flCw = colWMax[Int(colIdx)]
            }

            c.gridRowPer = CGFloat(rowPers[Int(rowIdx)])
            c.gridColPer = CGFloat(colPers[Int(colIdx)])
            c.gridRowIdx = Int(rowIdx)
            c.gridColIdx = Int(colIdx)

            let flCy = rowY[Int(rowIdx)]
            let flCh = rowH[Int(rowIdx)]

            clientTileResize(c, wlrBox(i32(flCx), i32(flCy), i32(flCw), i32(flCh)), false, ctx)
        }
    }

    func verticalTile(_ m: Monitor) { verticalTileCore(m, nil) }

    func verticalDeck(_ m: Monitor) { verticalDeckCore(m, nil) }

    func verticalGrid(_ m: Monitor) { verticalGridCore(m, nil) }

    func verticalFair(_ m: Monitor) { verticalFairCore(m, nil) }
}
