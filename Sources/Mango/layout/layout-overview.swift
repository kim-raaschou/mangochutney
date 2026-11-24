import Foundation
import CoreGraphics

/// mango OvPlacedRect (layout/overview.h).
struct OvPlacedRect {
    var x: Float = 0, y: Float = 0, w: Float = 0, h: Float = 0
}

/// mango OvPoint (layout/overview.h).
struct OvPoint {
    var x: Float = 0, y: Float = 0
}

/// mango OvLayoutItem (layout/overview.h).
struct OvLayoutItem {
    var c: Client
    var origW: Float
    var origH: Float
    var area: Float
}

func compareLayoutItems(_ a: OvLayoutItem, _ b: OvLayoutItem) -> Int32 {
    let areaA = a.area
    let areaB = b.area
    if areaA < areaB {
        return 1
    }
    if areaA > areaB {
        return -1
    }
    return 0
}

func tryPlace(_ placed: [OvPlacedRect], _ placedCnt: Int, _ w: Float, _ h: Float,
              _ gap: Float, _ availW: Float, _ availH: Float, _ out: inout OvPlacedRect,
              _ cands: inout [OvPoint], _ feas: inout [OvPoint]) -> Bool {
    var candCnt = 0
    cands[candCnt] = OvPoint(x: 0.0, y: 0.0); candCnt += 1

    for i in 0..<placedCnt {
        let p = placed[i]
        cands[candCnt] = OvPoint(x: p.x + p.w + gap, y: p.y); candCnt += 1
        cands[candCnt] = OvPoint(x: p.x, y: p.y + p.h + gap); candCnt += 1
        cands[candCnt] = OvPoint(x: p.x + p.w + gap, y: p.y + p.h + gap); candCnt += 1
    }

    var uniqueCnt = 0
    for i in 0..<candCnt {
        var dup = false
        for j in 0..<uniqueCnt {
            if abs(cands[i].x - cands[j].x) < 0.5 &&
                abs(cands[i].y - cands[j].y) < 0.5 {
                dup = true
                break
            }
        }
        if !dup {
            cands[uniqueCnt] = cands[i]; uniqueCnt += 1
        }
    }
    candCnt = uniqueCnt

    var feasCnt = 0
    for i in 0..<candCnt {
        let cx = cands[i].x
        let cy = cands[i].y

        if cx < 0 || cy < 0 || cx + w > availW || cy + h > availH {
            continue
        }

        var overlap = false
        for j in 0..<placedCnt {
            let p = placed[j]
            if !(cx + w + gap <= p.x || cx >= p.x + p.w + gap ||
                 cy + h + gap <= p.y || cy >= p.y + p.h + gap) {
                overlap = true
                break
            }
        }
        if !overlap {
            feas[feasCnt] = OvPoint(x: cx, y: cy); feasCnt += 1
        }
    }

    if feasCnt == 0 {
        return false
    }

    var best = 0
    for i in 1..<max(1, feasCnt) {
        if feas[i].y < feas[best].y ||
            (abs(feas[i].y - feas[best].y) < 0.5 &&
             feas[i].x < feas[best].x) {
            best = i
        }
    }

    out.x = feas[best].x
    out.y = feas[best].y
    out.w = w
    out.h = h
    return true
}

// Centers each packed row on the widest row's axis without creating overlaps.
private func centerPlacedRows(_ placed: inout [OvPlacedRect], _ n: Int, _ gap: Float) {
    if n <= 1 {
        return
    }

    var rowOf = [Int](repeating: 0, count: n)
    var rowY = [Float](repeating: 0, count: n)
    var rowOrder = [Int](repeating: 0, count: n)

    var rowCnt = 0
    for i in 0..<n {
        var r = -1
        for j in 0..<rowCnt {
            if abs(placed[i].y - rowY[j]) < 0.5 {
                r = j
                break
            }
        }
        if r < 0 {
            r = rowCnt; rowCnt += 1
            rowY[r] = placed[i].y
        }
        rowOf[i] = r
    }

    for i in 0..<rowCnt {
        rowOrder[i] = i
    }
    for i in 1..<max(1, rowCnt) {
        let key = rowOrder[i]
        var j = i - 1
        while j >= 0 && rowY[rowOrder[j]] > rowY[key] {
            rowOrder[j + 1] = rowOrder[j]
            j -= 1
        }
        rowOrder[j + 1] = key
    }

    var gridW: Float = 0.0
    for r in 0..<rowCnt {
        var left: Float = 1e30
        var right: Float = -1e30
        for i in 0..<n {
            if rowOf[i] != r {
                continue
            }
            if placed[i].x < left {
                left = placed[i].x
            }
            let e = placed[i].x + placed[i].w
            if e > right {
                right = e
            }
        }
        let span = right - left
        if span > gridW {
            gridW = span
        }
    }

    for oi in 0..<rowCnt {
        let r = rowOrder[oi]
        var left: Float = 1e30
        var right: Float = -1e30
        for i in 0..<n {
            if rowOf[i] != r {
                continue
            }
            if placed[i].x < left {
                left = placed[i].x
            }
            let e = placed[i].x + placed[i].w
            if e > right {
                right = e
            }
        }
        let span = right - left
        var delta = gridW * 0.5 - (left + span * 0.5)
        var lo: Float = -1e30
        var hi: Float = 1e30

        // Rows sharing a vertical band keep the gap and never swap sides.
        for i in 0..<n {
            if rowOf[i] != r {
                continue
            }
            let a = placed[i]
            for j in 0..<n {
                let b = placed[j]
                if rowOf[j] == r {
                    continue
                }
                if !(a.y + a.h + gap <= b.y || a.y >= b.y + b.h + gap) {
                    if b.x < a.x {
                        let minDelta = b.x + b.w + gap - a.x
                        if minDelta > lo {
                            lo = minDelta
                        }
                    } else {
                        let maxDelta = b.x - gap - a.x - a.w
                        if maxDelta < hi {
                            hi = maxDelta
                        }
                    }
                }
            }
        }

        if -left > lo {
            lo = -left
        }
        if gridW - right < hi {
            hi = gridW - right
        }

        if lo <= hi {
            if delta < lo {
                delta = lo
            }
            if delta > hi {
                delta = hi
            }
            if abs(delta) > 0.5 {
                for i in 0..<n {
                    if rowOf[i] == r {
                        placed[i].x += delta
                    }
                }
            }
        }
    }
}

package extension MangoServer {

    func beginJumpMode(_ m: Monitor) {
        m.isJumpMode = true
        publishInputState()   // not in mango: the event tap's snapshot
    }

    func overviewScale(_ m: Monitor) {
        let targetGappo = Int32(config.overviewgappo)
        let targetGappi = Int32(config.overviewgappi)

        var items: [OvLayoutItem] = []

        // not in mango: the clients counted here, as m->visible_clients is not counted in the overview (arrange)
        for c in clients {
            if c.mon !== m {
                continue
            }
            if VISIBLEON(c, m) && !c.isunglobal {   // not in mango: no X11 popups
                var w = Float(c.overviewBackupGeom.width)
                var h = Float(c.overviewBackupGeom.height)
                if w <= 0 || h <= 0 {
                    w = 100.0
                    h = 100.0
                }
                items.append(OvLayoutItem(c: c, origW: w, origH: h, area: w * h))
            }
        }
        let n = items.count

        if n == 0 {
            return
        }

        items.sort { compareLayoutItems($0, $1) < 0 }

        let maxAvailW = max(1.0, Float(Int32(m.w.width) - 2 * targetGappo))
        let maxAvailH = max(1.0, Float(Int32(m.w.height) - 2 * targetGappo))

        let maxPoints = 1 + 3 * n
        var placed = [OvPlacedRect](repeating: OvPlacedRect(), count: n)
        var cands = [OvPoint](repeating: OvPoint(), count: maxPoints)
        var feas = [OvPoint](repeating: OvPoint(), count: maxPoints)

        var low: Float = 0.0, high: Float = 1.0, bestS: Float = 0.0
        for _ in 0..<50 {
            let mid = (low + high) / 2.0
            var ok = true
            var placedCnt = 0

            for k in 0..<n {
                let w = items[k].origW * mid
                let h = items[k].origH * mid
                var out = OvPlacedRect()
                if !tryPlace(placed, placedCnt, w, h, Float(targetGappi),
                             maxAvailW, maxAvailH, &out, &cands, &feas) {
                    ok = false
                    break
                }
                placed[placedCnt] = out; placedCnt += 1
            }

            if ok {
                bestS = mid
                low = mid
            } else {
                high = mid
            }
        }

        if bestS > 0.0 {
            var placedCnt = 0

            for k in 0..<n {
                let w = items[k].origW * bestS
                let h = items[k].origH * bestS
                var out = OvPlacedRect()
                _ = tryPlace(placed, placedCnt, w, h, Float(targetGappi),
                             maxAvailW, maxAvailH, &out, &cands, &feas)
                placed[placedCnt] = out; placedCnt += 1
            }

            centerPlacedRows(&placed, n, Float(targetGappi))

            var boxW: Float = 0, boxH: Float = 0
            for k in 0..<n {
                let r = placed[k].x + placed[k].w
                let b = placed[k].y + placed[k].h
                if r > boxW {
                    boxW = r
                }
                if b > boxH {
                    boxH = b
                }
            }

            let dx = (maxAvailW - boxW) / 2.0
            let dy = (maxAvailH - boxH) / 2.0
            let baseX = Float(Int32(m.w.minX) + targetGappo) + dx
            let baseY = Float(Int32(m.w.minY) + targetGappo) + dy

            // Collects the target geometry of all clients and calls
            // client_tile_resize once at the end.
            var overviewBoxes = [CGRect](repeating: .zero, count: n)
            for k in 0..<n {
                let w = items[k].origW * bestS
                let h = items[k].origH * bestS
                let ix = Int32(baseX + placed[k].x + 0.5)
                let iy = Int32(baseY + placed[k].y + 0.5)
                let iw = Int32(Float(ix) + w + 0.5) - ix
                let ih = Int32(Float(iy) + h + 0.5) - iy
                overviewBoxes[k] = CGRect(x: Int(ix), y: Int(iy), width: Int(iw), height: Int(ih))
            }

            for k in 0..<n {
                clientTileResize(items[k].c, overviewBoxes[k], false, nil)
            }
        }
    }

    // Overview layout: focused window centered (about half screen width), remaining
    // windows split on both sides.
    func overviewLayoutColumn(_ m: Monitor, _ items: [Client], _ cnt: Int, _ x: Float,
                              _ top: Float, _ colW: Float, _ colH: Float, _ gap: Float) {
        if cnt <= 0 {
            return
        }

        var ws = [Float](repeating: 0, count: cnt)
        var hs = [Float](repeating: 0, count: cnt)

        // Width fills the column width; height is proportional.
        var totalH: Float = 0.0
        for i in 0..<cnt {
            var ow = Float(items[i].overviewBackupGeom.width)
            var oh = Float(items[i].overviewBackupGeom.height)
            if ow <= 0 || oh <= 0 {
                ow = 100.0
                oh = 100.0
            }
            ws[i] = colW
            hs[i] = colW * (oh / ow)
            totalH += hs[i]
        }

        // Scales the whole item down when it is too tall.
        let gapTotal = gap * Float(cnt - 1)
        if totalH + gapTotal > colH {
            var s = (colH - gapTotal) / totalH
            if s < 0.0 {
                s = 0.01
            }
            for i in 0..<cnt {
                ws[i] *= s
                hs[i] *= s
            }
            totalH *= s
        }

        // Vertically centers when there is extra room.
        var y = top
        if totalH + gapTotal < colH {
            y = top + (colH - (totalH + gapTotal)) / 2.0
        }

        for i in 0..<cnt {
            let ix = Int32(x + (colW - ws[i]) / 2.0 + 0.5)
            let iy = Int32(y + 0.5)
            clientTileResize(items[i],
                             CGRect(x: Int(ix), y: Int(iy), width: Int(Int32(ws[i])), height: Int(Int32(hs[i]))), false,
                             nil)
            y += hs[i] + gap
        }
    }

    func overviewScaleTab(_ m: Monitor) {
        let targetGappo = Int32(config.overviewgappo)
        let targetGappi = Int32(config.overviewgappi)

        var items: [Client] = []

        // not in mango: the clients counted here, as m->visible_clients is not counted in the overview (arrange)
        for c in clients {
            if c.mon !== m {
                continue
            }
            if VISIBLEON(c, m) && !c.isunglobal {   // not in mango: no X11 popups
                items.append(c)
            }
        }
        let n = items.count

        if n == 0 {
            return
        }

        // Index of the focused window (or the first one if none).
        let sel = m.sel
        var focusIdx = 0
        for i in 0..<n {
            if items[i].id == sel?.id {
                focusIdx = i
                break
            }
        }

        // Uses the larger gap between columns and the smaller gap at the edges.
        var gapMid = Float(targetGappo)
        var gapEdge = Float(targetGappi)
        if gapMid < gapEdge {
            let tmp = gapMid
            gapMid = gapEdge
            gapEdge = tmp
        }
        gapMid *= 0.5 /* Halves the gap between columns. */

        let availW = max(1.0, Float(m.w.width) - 2 * gapEdge)
        let availH = max(1.0, Float(m.w.height) - 2 * gapEdge)

        // Center column ratio is configurable; both sides split the remaining space
        // evenly.
        let centerW = availW * config.overcircleCenterRatio
        var sideW = (availW - centerW - 2.0 * gapMid) * 0.5
        if sideW < 1.0 {
            sideW = 1.0
        }

        let baseX = Float(m.w.minX) + gapEdge
        let baseY = Float(m.w.minY) + gapEdge

        let leftX = baseX
        let centerX = baseX + sideW + gapMid
        let rightX = centerX + centerW + gapMid

        // The focused window is centered.
        let focus = items[focusIdx]
        do {
            /* Keep the title bar and its gap inside the visible area by treating
             * them as part of the centered focus block. */
            var titleBlockH: Float = 0.0
            if config.titleMessageBarHeight > 0 {
                titleBlockH = Float(config.titleMessageBarHeight) +
                    Float(config.titleMessageBarGap)
            }
            if titleBlockH >= availH {
                titleBlockH = 0.0
            }
            var ow = Float(focus.overviewBackupGeom.width)
            var oh = Float(focus.overviewBackupGeom.height)
            if ow <= 0 || oh <= 0 {
                ow = 100.0
                oh = 100.0
            }
            var w = centerW
            var h = w * (oh / ow)
            let maxH = availH - titleBlockH
            if h > maxH {
                let s = maxH / h
                w *= s
                h *= s
            }
            let ix = Int32(centerX + (centerW - w) / 2.0 + 0.5)
            let iy = Int32(baseY + (availH - (h + titleBlockH)) / 2.0 + 0.5)
            clientTileResize(focus, CGRect(x: Int(ix), y: Int(iy), width: Int(Int32(w)), height: Int(Int32(h))), false,
                             nil)
        }

        // The rest split into the left/right columns; on focus change they
        // circulate (rotate).
        var left: [Client] = []
        var right: [Client] = []
        let rest = n - 1
        let rightCnt = (rest + 1) / 2
        let leftCnt = rest - rightCnt

        for k in 0..<rightCnt {
            let idx = (focusIdx + 1 + k) % n
            right.append(items[idx])
        }
        for k in 0..<leftCnt {
            let idx = (focusIdx - 1 - k + n) % n
            left.append(items[idx])
        }

        overviewLayoutColumn(m, left, left.count, leftX, baseY, sideW, availH,
                             gapEdge)
        overviewLayoutColumn(m, right, right.count, rightX, baseY, sideW, availH,
                             gapEdge)
    }

    func createJumpHints(_ m: Monitor) {
        // Uses the static default sequence when jump_labels is not configured.
        let jumpLabels = Array(config.jumpLabels)
        if jumpLabels.isEmpty {
            return
        }
        let jumpLabelsLen = jumpLabels.count
        var labelIdx = 0

        for c in clients {
            if VISIBLEON(c, m) && !c.isunglobal {   // not in mango: no X11 popups
                if labelIdx >= jumpLabelsLen {
                    break
                }
                let cChar = jumpLabels[labelIdx]
                c.jumpChar = cChar
                findKeycodesForChar(cChar, &c.jumpKeycodes)

                c.jumpLabelNode?.update(String(cChar), m.screen.scale)
                overviewUpdateJumpLabel(c)
                labelIdx += 1
            }
        }
        publishInputState()   // not in mango: the event tap's snapshot
    }

    func finishJumpMode(_ m: Monitor) {
        if !m.isJumpMode {
            return
        }

        for c in clients {
            if c.mon !== m {
                continue
            }

            c.jumpChar = nil
            c.jumpKeycodes = MultiKeycode()

            if let label = c.jumpLabelNode, label.enabled {
                label.setEnabled(false)
            }
        }
        m.isJumpMode = false
        publishInputState()   // not in mango: the event tap's snapshot
    }

    func overview(_ m: Monitor) {
        m.ovCards = [:]   // not in mango: the port's cards are laid out anew
        if m.ovTabLayout && !m.isJumpMode && !m.ovNormalMode {
            overviewScaleTab(m)
        } else {
            overviewScale(m)
        }

        // not in mango: a client the layout gave no card (floating, fullscreen or maximized, mapped in
        // overview) has its card where it stands, as its card tree does
        for c in clients where VISIBLEON(c, m) && !c.isunglobal && m.ovCards[c.id] == nil {
            m.ovCards[c.id] = c.geom
        }

        if m.isJumpMode {
            createJumpHints(m)
        }
        overviewLayoutCards(m)   // not in mango: the port's pictures and title bar, once for the cards
    }
}
