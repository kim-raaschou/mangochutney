import CoreGraphics

/// mango MANGO_MIN (common/util.h).
@inline(__always) func MANGO_MIN<T: Comparable>(_ a: T, _ b: T) -> T { a < b ? a : b }
/// mango MANGO_MAX (common/util.h).
@inline(__always) func MANGO_MAX<T: Comparable>(_ a: T, _ b: T) -> T { a > b ? a : b }

/// not in mango: wlr_box's int32_t fields of the monitor's work area (m->w)
struct WBox {
    let x: Int32, y: Int32, width: Int32, height: Int32
    init(_ r: CGRect) {
        x = Int32(r.minX.rounded()); y = Int32(r.minY.rounded())
        width = Int32(r.width.rounded()); height = Int32(r.height.rounded())
    }
}

/// not in mango: a wlr_box from int32_t fields
@inline(__always) func wlrBox(_ x: Int32, _ y: Int32, _ width: Int32, _ height: Int32) -> CGRect {
    CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
}

/// not in mango: C's conversion of a floating value to int32_t (toward zero)
@inline(__always) func i32(_ v: Double) -> Int32 { Int32(v.rounded(.towardZero)) }
@inline(__always) func i32(_ v: Float) -> Int32 { Int32(v.rounded(.towardZero)) }

package extension MangoServer {
    /// not in mango: wl_list_for_each over server.clients with VISIBLEON and ISFAKETILED's first
    private func firstFakeTiled(_ m: Monitor) -> Client? {
        clients.first { VISIBLEON($0, m) && ISFAKETILED($0) }
    }

    func tile(_ m: Monitor) {
        var i: Int32, n: Int32 = 0, h: Int32, r: Int32, mw: Int32, my: Int32, ty: Int32
        let ie: Int32 = enableGaps ? 1 : 0
        var mfact: Double = 0
        var masterNum: Int32 = 0
        var stackNum: Int32 = 0
        let tag = getMonCurtag(m)
        let w = WBox(m.w)

        n = m.visibleFakeTilingClients
        masterNum = Int32(m.pertag.nmasters[tag])
        masterNum = n > masterNum ? masterNum : n
        stackNum = n - masterNum

        if n == 0 { return }

        var curGappiv: Int32 = enableGaps ? m.gappiv : 0
        var curGappih: Int32 = enableGaps ? m.gappih : 0
        var curGappov: Int32 = enableGaps ? m.gappov : 0
        var curGappoh: Int32 = enableGaps ? m.gappoh : 0

        curGappiv = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappiv
        curGappih = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappih
        curGappov = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappov
        curGappoh = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappoh

        guard let fc = firstFakeTiled(m) else { return }

        mfact = fc.masterMfactPer > 0.0 ? Double(fc.masterMfactPer) : Double(m.pertag.mfacts[tag])

        if n > Int32(m.pertag.nmasters[tag]) {
            mw = m.pertag.nmasters[tag] != 0 ? i32(Double(w.width + curGappih * ie) * mfact) : 0
        } else {
            mw = w.width - 2 * curGappoh + curGappih * ie
        }

        i = 0
        my = curGappov
        ty = curGappov

        var masterSurplusHeight = w.height - 2 * curGappov - curGappiv * ie * (masterNum - 1)
        var masterSurplusRatio: Float = 1.0

        var slaveSurplusHeight = w.height - 2 * curGappov - curGappiv * ie * (stackNum - 1)
        var slaveSurplusRatio: Float = 1.0

        for c in clients {
            if !VISIBLEON(c, m) || !ISFAKETILED(c) { continue }
            if i < Int32(m.pertag.nmasters[tag]) {
                r = MANGO_MIN(n, Int32(m.pertag.nmasters[tag])) - i
                if c.masterInnerPer > 0.0 {
                    h = i32(Double(masterSurplusHeight) * Double(c.masterInnerPer) / Double(masterSurplusRatio))
                    masterSurplusHeight = masterSurplusHeight - h
                    masterSurplusRatio = Float(Double(masterSurplusRatio) - Double(c.masterInnerPer))
                    c.masterMfactPer = CGFloat(mfact)
                } else {
                    h = (w.height - my - curGappov - curGappiv * ie * (r - 1)) / r
                    c.masterInnerPer = CGFloat(h / (w.height - my - curGappov - curGappiv * ie * (r - 1)))
                    c.masterMfactPer = CGFloat(mfact)
                }
                clientTileResize(c, wlrBox(w.x + curGappoh, w.y + my, mw - curGappih * ie, h), false)
                my += h + curGappiv * ie // Accumulates using the theoretical height.
            } else {
                r = n - i
                if c.stackInnerPer > 0.0 {
                    h = i32(Double(slaveSurplusHeight) * Double(c.stackInnerPer) / Double(slaveSurplusRatio))
                    slaveSurplusHeight = slaveSurplusHeight - h
                    slaveSurplusRatio = Float(Double(slaveSurplusRatio) - Double(c.stackInnerPer))
                    c.masterMfactPer = CGFloat(mfact)
                } else {
                    h = (w.height - ty - curGappov - curGappiv * ie * (r - 1)) / r
                    c.stackInnerPer = CGFloat(h / (w.height - ty - curGappov - curGappiv * ie * (r - 1)))
                    c.masterMfactPer = CGFloat(mfact)
                }

                clientTileResize(c, wlrBox(w.x + mw + curGappoh, w.y + ty, w.width - mw - 2 * curGappoh, h), false)
                ty += h + curGappiv * ie // Accumulates using the theoretical height.
            }
            i += 1
        }
    }

    func rightTile(_ m: Monitor) {
        var i: Int32, n: Int32 = 0, h: Int32, r: Int32, mw: Int32, my: Int32, ty: Int32
        let ie: Int32 = enableGaps ? 1 : 0
        var mfact: Double = 0
        var masterNum: Int32 = 0
        var stackNum: Int32 = 0
        let tag = getMonCurtag(m)
        let w = WBox(m.w)

        n = m.visibleFakeTilingClients
        masterNum = Int32(m.pertag.nmasters[tag])
        masterNum = n > masterNum ? masterNum : n
        stackNum = n - masterNum

        if n == 0 { return }

        var curGappiv: Int32 = enableGaps ? m.gappiv : 0
        var curGappih: Int32 = enableGaps ? m.gappih : 0
        var curGappov: Int32 = enableGaps ? m.gappov : 0
        var curGappoh: Int32 = enableGaps ? m.gappoh : 0

        curGappiv = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappiv
        curGappih = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappih
        curGappov = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappov
        curGappoh = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappoh

        guard let fc = firstFakeTiled(m) else { return }

        mfact = fc.masterMfactPer > 0.0 ? Double(fc.masterMfactPer) : Double(m.pertag.mfacts[tag])

        if n > Int32(m.pertag.nmasters[tag]) {
            mw = m.pertag.nmasters[tag] != 0 ? i32(Double(w.width + curGappih * ie) * mfact) : 0
        } else {
            mw = w.width - 2 * curGappoh + curGappih * ie
        }

        i = 0
        my = curGappov
        ty = curGappov

        var masterSurplusHeight = w.height - 2 * curGappov - curGappiv * ie * (masterNum - 1)
        var masterSurplusRatio: Float = 1.0

        var slaveSurplusHeight = w.height - 2 * curGappov - curGappiv * ie * (stackNum - 1)
        var slaveSurplusRatio: Float = 1.0

        for c in clients {
            if !VISIBLEON(c, m) || !ISFAKETILED(c) { continue }
            if i < Int32(m.pertag.nmasters[tag]) {
                r = MANGO_MIN(n, Int32(m.pertag.nmasters[tag])) - i
                if c.masterInnerPer > 0.0 {
                    h = i32(Double(masterSurplusHeight) * Double(c.masterInnerPer) / Double(masterSurplusRatio))
                    masterSurplusHeight = masterSurplusHeight - h
                    masterSurplusRatio = Float(Double(masterSurplusRatio) - Double(c.masterInnerPer))
                    c.masterMfactPer = CGFloat(mfact)
                } else {
                    h = (w.height - my - curGappov - curGappiv * ie * (r - 1)) / r
                    c.masterInnerPer = CGFloat(h / (w.height - my - curGappov - curGappiv * ie * (r - 1)))
                    c.masterMfactPer = CGFloat(mfact)
                }
                clientTileResize(c, wlrBox(w.x + w.width - mw - curGappoh + curGappih * ie, w.y + my,
                                           mw - curGappih * ie, h), false)
                my += h + curGappiv * ie // Accumulates using the theoretical height.
            } else {
                r = n - i
                if c.stackInnerPer > 0.0 {
                    h = i32(Double(slaveSurplusHeight) * Double(c.stackInnerPer) / Double(slaveSurplusRatio))
                    slaveSurplusHeight = slaveSurplusHeight - h
                    slaveSurplusRatio = Float(Double(slaveSurplusRatio) - Double(c.stackInnerPer))
                    c.masterMfactPer = CGFloat(mfact)
                } else {
                    h = (w.height - ty - curGappov - curGappiv * ie * (r - 1)) / r
                    c.stackInnerPer = CGFloat(h / (w.height - ty - curGappov - curGappiv * ie * (r - 1)))
                    c.masterMfactPer = CGFloat(mfact)
                }

                clientTileResize(c, wlrBox(w.x + curGappoh, w.y + ty, w.width - mw - 2 * curGappoh, h), false)
                ty += h + curGappiv * ie // Accumulates using the theoretical height.
            }
            i += 1
        }
    }

    func centerTile(_ m: Monitor) {
        var i: Int32, n: Int32 = 0, h: Int32, r: Int32, mw: Int32, mx: Int32, my: Int32, oty: Int32, ety: Int32, tw: Int32
        let ie: Int32 = enableGaps ? 1 : 0
        var mfact: Double = 0
        var masterNum: Int32 = 0
        var stackNum: Int32 = 0
        let tag = getMonCurtag(m)
        let w = WBox(m.w)

        n = m.visibleFakeTilingClients
        masterNum = Int32(m.pertag.nmasters[tag])
        masterNum = n > masterNum ? masterNum : n
        stackNum = n - masterNum

        if n == 0 { return }

        // Gets the first visible tiled client for the master area width percentage.
        guard let fc = firstFakeTiled(m) else { return }

        // Gap parameter handling.
        var curGappiv: Int32 = enableGaps ? m.gappiv : 0 // Inner vertical gap.
        var curGappih: Int32 = enableGaps ? m.gappih : 0 // Inner horizontal gap.
        var curGappov: Int32 = enableGaps ? m.gappov : 0 // Outer vertical gap.
        var curGappoh: Int32 = enableGaps ? m.gappoh : 0 // Outer horizontal gap.

        // Smart gap handling.
        curGappiv = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappiv
        curGappih = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappih
        curGappov = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappov
        curGappoh = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappoh

        let nmasters = Int32(m.pertag.nmasters[tag])
        mfact = fc.masterMfactPer > 0.0 ? Double(fc.masterMfactPer) : Double(m.pertag.mfacts[tag])

        // Initializes the area.
        mw = w.width
        mx = curGappoh
        my = curGappov
        tw = mw

        // Decides whether the master area should fill the width.
        let shouldOverspread = config.centerMasterOverspread && (n <= nmasters)

        var leftNum: Int32 = 0
        var rightNum: Int32 = 0
        for j in 0..<max(0, stackNum) {
            if (j % 2 == 1) != (n % 2 == 0) {
                rightNum += 1
            } else {
                leftNum += 1
            }
        }

        var masterSurplusHeight = w.height - 2 * curGappov - curGappiv * ie * (masterNum > 0 ? masterNum - 1 : 0)
        var masterSurplusRatio: Float = 1.0
        let initMasterSurplus = masterSurplusHeight

        var slaveLeftSurplusHeight = w.height - 2 * curGappov - curGappiv * ie * (leftNum > 0 ? leftNum - 1 : 0)
        var slaveLeftSurplusRatio: Float = 1.0
        let initSlaveLeftSurplus = slaveLeftSurplusHeight

        var slaveRightSurplusHeight = w.height - 2 * curGappov - curGappiv * ie * (rightNum > 0 ? rightNum - 1 : 0)
        var slaveRightSurplusRatio: Float = 1.0
        let initSlaveRightSurplus = slaveRightSurplusHeight

        let initSingleStackSurplus = w.height - 2 * curGappov - curGappiv * ie * (stackNum > 0 ? stackNum - 1 : 0)

        if n > nmasters || !shouldOverspread {
            // Computes the master area width (centered mode).
            mw = nmasters != 0 ? i32(Double(w.width - 2 * curGappoh - curGappih * ie) * mfact) : 0

            if n - nmasters > 1 {
                // Multiple stack windows: master centered, one stack area on each
                // side.
                tw = (w.width - mw) / 2 - curGappoh - curGappih * ie
                mx = curGappoh + tw + curGappih * ie
            } else if n - nmasters == 1 {
                // Single stack window handling.
                if config.centerWhenSingleStack {
                    // Stack on the right, master centered, left empty.
                    tw = (w.width - mw) / 2 - curGappoh - curGappih * ie
                    mx = curGappoh + tw + curGappih * ie
                } else {
                    // Stack on the right, master on the left.
                    tw = w.width - mw - 2 * curGappoh - curGappih * ie
                    mx = curGappoh
                }
            } else {
                // Only master-area windows: centered display.
                tw = (w.width - mw) / 2 - curGappoh - curGappih * ie
                mx = curGappoh + tw + curGappih * ie
            }
        } else {
            // Master fill mode (only master-area windows).
            mw = w.width - 2 * curGappoh
            mx = curGappoh
            tw = 0
        }

        oty = curGappov
        ety = curGappov

        i = 0
        for c in clients {
            if !VISIBLEON(c, m) || !ISFAKETILED(c) { continue }

            if i < nmasters {
                // Master-area windows.
                r = MANGO_MIN(n, nmasters) - i
                if c.masterInnerPer > 0.0 {
                    h = i32(Double(masterSurplusHeight) * Double(c.masterInnerPer) / Double(masterSurplusRatio))
                    if r == 1 { h = w.height - my - curGappov }
                    masterSurplusHeight = masterSurplusHeight - h
                    masterSurplusRatio = Float(Double(masterSurplusRatio) - Double(c.masterInnerPer))
                    c.masterMfactPer = CGFloat(mfact)
                } else {
                    h = (w.height - my - curGappov - curGappiv * ie * (r - 1)) / r
                    if r == 1 { h = w.height - my - curGappov }
                    c.masterInnerPer = initMasterSurplus > 0 ? CGFloat(Float(h) / Float(initMasterSurplus)) : 0
                    c.masterMfactPer = CGFloat(mfact)
                }

                clientTileResize(c, wlrBox(w.x + mx, w.y + my, mw, h), false)
                my += h + curGappiv * ie // Accumulates using the theoretical height.
            } else {
                // Stack-area windows.
                let stackIndex = i - nmasters

                if n - nmasters == 1 {
                    // Single stack window.
                    r = n - i
                    if c.stackInnerPer > 0.0 {
                        h = i32(Double(initSingleStackSurplus) * Double(c.stackInnerPer))
                        if r == 1 { h = w.height - ety - curGappov }
                        c.masterMfactPer = CGFloat(mfact)
                    } else {
                        h = (w.height - ety - curGappov - curGappiv * ie * (r - 1)) / r
                        if r == 1 { h = w.height - ety - curGappov }
                        c.stackInnerPer = initSingleStackSurplus > 0 ? CGFloat(Float(h) / Float(initSingleStackSurplus)) : 0
                        c.masterMfactPer = CGFloat(mfact)
                    }

                    let stackX: Int32
                    if config.centerWhenSingleStack {
                        stackX = w.x + mx + mw + curGappih * ie
                    } else {
                        stackX = w.x + mx + mw + curGappih * ie
                    }

                    clientTileResize(c, wlrBox(stackX, w.y + ety, tw, h), false)
                    ety += h + curGappiv * ie
                } else {
                    // Multiple stack windows: alternated on the left and right
                    // sides.
                    r = (n - i + 1) / 2

                    if (stackIndex % 2 == 1) != (n % 2 == 0) {
                        // Right stack windows.
                        if c.stackInnerPer > 0.0 {
                            h = i32(Double(slaveRightSurplusHeight) * Double(c.stackInnerPer) / Double(slaveRightSurplusRatio))
                            if r == 1 { h = w.height - ety - curGappov }
                            slaveRightSurplusHeight = slaveRightSurplusHeight - h
                            slaveRightSurplusRatio = Float(Double(slaveRightSurplusRatio) - Double(c.stackInnerPer))
                            c.masterMfactPer = CGFloat(mfact)
                        } else {
                            h = (w.height - ety - curGappov - curGappiv * ie * (r - 1)) / r
                            if r == 1 { h = w.height - ety - curGappov }
                            c.stackInnerPer = initSlaveRightSurplus > 0 ? CGFloat(Float(h) / Float(initSlaveRightSurplus)) : 0
                            c.masterMfactPer = CGFloat(mfact)
                        }

                        let stackX = w.x + mx + mw + curGappih * ie

                        clientTileResize(c, wlrBox(stackX, w.y + ety, tw, h), false)
                        ety += h + curGappiv * ie
                    } else {
                        // Left stack windows.
                        if c.stackInnerPer > 0.0 {
                            h = i32(Double(slaveLeftSurplusHeight) * Double(c.stackInnerPer) / Double(slaveLeftSurplusRatio))
                            if r == 1 { h = w.height - oty - curGappov }
                            slaveLeftSurplusHeight = slaveLeftSurplusHeight - h
                            slaveLeftSurplusRatio = Float(Double(slaveLeftSurplusRatio) - Double(c.stackInnerPer))
                            c.masterMfactPer = CGFloat(mfact)
                        } else {
                            h = (w.height - oty - curGappov - curGappiv * ie * (r - 1)) / r
                            if r == 1 { h = w.height - oty - curGappov }
                            c.stackInnerPer = initSlaveLeftSurplus > 0 ? CGFloat(Float(h) / Float(initSlaveLeftSurplus)) : 0
                            c.masterMfactPer = CGFloat(mfact)
                        }

                        let stackX = w.x + curGappoh
                        clientTileResize(c, wlrBox(stackX, w.y + oty, tw, h), false)
                        oty += h + curGappiv * ie
                    }
                }
            }
            i += 1
        }
    }

    func deck(_ m: Monitor) {
        var mw: Int32, my: Int32
        var i: Int32, n: Int32 = 0
        let tag = getMonCurtag(m)
        let w = WBox(m.w)
        let nmasters = Int32(m.pertag.nmasters[tag])

        var curGappih: Int32 = enableGaps ? m.gappih : 0
        var curGappoh: Int32 = enableGaps ? m.gappoh : 0
        var curGappov: Int32 = enableGaps ? m.gappov : 0

        curGappih = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappih
        curGappoh = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappoh
        curGappov = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappov

        n = m.visibleFakeTilingClients

        if n == 0 { return }

        guard let fc = firstFakeTiled(m) else { return }

        let mfact: Float = fc.masterMfactPer > 0.0 ? Float(fc.masterMfactPer) : m.pertag.mfacts[tag]

        if n > nmasters {
            mw = nmasters != 0 ? Int32((Double(Float(w.width - 2 * curGappoh) * mfact)).rounded()) : 0
        } else {
            mw = w.width - 2 * curGappoh
        }

        i = 0
        my = 0
        for c in clients {
            if !VISIBLEON(c, m) || !ISFAKETILED(c) { continue }
            if i < nmasters {
                c.masterMfactPer = CGFloat(mfact)
                let h = (w.height - 2 * curGappov - my) / (MANGO_MIN(n, nmasters) - i)
                clientTileResize(c, wlrBox(w.x + curGappoh, w.y + curGappov + my, mw, h), false)
                my += h
            } else {
                c.masterMfactPer = CGFloat(mfact)
                clientTileResize(c, wlrBox(w.x + mw + curGappoh + curGappih, w.y + curGappov,
                                           w.width - mw - 2 * curGappoh - curGappih, w.height - 2 * curGappov), false)
                clientUpdateVisibility(c)
            }
            i += 1
        }
    }

    func monocle(_ m: Monitor) {
        let w = WBox(m.w)

        var curGappov: Int32 = enableGaps ? m.gappov : 0
        var curGappoh: Int32 = enableGaps ? m.gappoh : 0

        if config.monocleNoGap {
            curGappoh = 0
            curGappov = 0
        }

        curGappoh = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappoh
        curGappov = config.smartgaps && m.visibleFakeTilingClients == 1 ? 0 : curGappov

        for c in clients {
            if !VISIBLEON(c, m) || !ISFAKETILED(c) { continue }
            let geom = wlrBox(w.x + curGappoh, w.y + curGappov, w.width - 2 * curGappoh, w.height - 2 * curGappov)
            clientTileResize(c, geom, false)
            clientUpdateVisibility(c)
        }
    }

    // not in mango: client_is_x11_popup is false; macOS has no X11 popups
    private func gridCounts(_ c: Client, _ m: Monitor) -> Bool {
        VISIBLEON(c, m) && !c.isunglobal && (m.isoverview || ISFAKETILED(c))
    }

    // Computes grid layout window sizes and positions.
    func grid(_ m: Monitor) {
        var i: Int32, n: Int32
        var cw: Int32, ch: Int32
        var cols: Int32, rows: Int32, overcols: Int32
        let w = WBox(m.w)
        n = 0
        let targetGappo: Int32 = enableGaps ? Int32(config.gappoh) : 0
        let targetGappi: Int32 = enableGaps ? Int32(config.gappih) : 0
        let singleWidthRatio: Float = 0.9
        let singleHeightRatio: Float = 0.9

        n = m.visibleFakeTilingClients

        if n == 0 { return }

        if n == 1 {
            for c in clients {
                if c.mon !== m { continue }
                if gridCounts(c, m) {
                    cw = i32(Float(w.width - 2 * targetGappo) * singleWidthRatio)
                    ch = i32(Float(w.height - 2 * targetGappo) * singleHeightRatio)
                    let targetGeom = wlrBox(w.x + (w.width - cw) / 2, w.y + (w.height - ch) / 2, cw, ch)
                    clientTileResize(c, targetGeom, false)
                    return
                }
            }
        }

        if n == 2 {
            var colPers: [Float] = [1.0, 1.0]
            // First extracts the existing column ratios of these two windows.
            i = 0
            for c in clients {
                if c.mon !== m { continue }
                if gridCounts(c, m) {
                    if i < 2 { colPers[Int(i)] = c.gridColPer > 0.0 ? c.gridColPer : 1.0 }
                    i += 1
                }
            }

            let sumCol = colPers[0] + colPers[1]
            let availW = Float(w.width - 2 * targetGappo - targetGappi)
            ch = i32(Double(w.height - 2 * targetGappo) * 0.65) // Keeps the pleasing height of 0.65.

            i = 0
            for c in clients {
                if c.mon !== m { continue }
                if gridCounts(c, m) {
                    c.gridColIdx = i
                    c.gridRowIdx = 0
                    c.gridColPer = colPers[Int(i)]
                    c.gridRowPer = 1.0

                    // Computes the current window width dynamically from the
                    // assigned weight.
                    cw = i32(availW * (colPers[Int(i)] / sumCol))

                    var x: Int32 = 0
                    if i == 0 {
                        x = w.x + targetGappo
                    } else if i == 1 {
                        // The second window X coordinate follows right after the
                        // first window.
                        let cw0 = availW * (colPers[0] / sumCol)
                        x = i32(Float(w.x + targetGappo) + cw0 + Float(targetGappi))
                    }
                    let y = w.y + (w.height - ch) / 2 + targetGappo
                    clientTileResize(c, wlrBox(x, y, cw, ch), false)
                    i += 1
                }
            }
            return
        }

        // Computes the column and row counts.
        cols = 0
        while cols <= n / 2 {
            if cols * cols >= n { break }
            cols += 1
        }
        rows = (cols != 0 && (cols - 1) * cols >= n) ? cols - 1 : cols
        overcols = n % cols

        var colPers = [Float](repeating: 1.0, count: Int(cols))
        var rowPers = [Float](repeating: 1.0, count: Int(rows))

        // Extracts the first window ratio.
        i = 0
        for c in clients {
            if c.mon !== m { continue }
            if gridCounts(c, m) {
                let cIdx = i % cols
                let rIdx = i / cols
                if rIdx == 0 { colPers[Int(cIdx)] = c.gridColPer > 0.0 ? c.gridColPer : 1.0 }
                if cIdx == 0 { rowPers[Int(rIdx)] = c.gridRowPer > 0.0 ? c.gridRowPer : 1.0 }
                i += 1
            }
        }

        var sumCol: Float = 0.0, sumRow: Float = 0.0
        for v in colPers { sumCol += v }
        for v in rowPers { sumRow += v }

        let availW = Float(w.width - 2 * targetGappo - (cols - 1) * targetGappi)
        let availH = Float(w.height - 2 * targetGappo - (rows - 1) * targetGappi)

        // Assigns positions and sizes.
        i = 0
        for c in clients {
            if c.mon !== m { continue }
            if gridCounts(c, m) {
                let cIdx = i % cols
                let rIdx = i / cols

                // Fixes properties and marks indices.
                c.gridColPer = colPers[Int(cIdx)]
                c.gridRowPer = rowPers[Int(rIdx)]
                c.gridColIdx = cIdx
                c.gridRowIdx = rIdx

                // X coordinate and width computation.
                var flCx = Float(w.x + targetGappo)
                var flCw: Float = 0.0

                if overcols != 0 && i >= n - overcols {
                    var overW: Float = 0.0
                    for j in 0..<Int(overcols) { overW += availW * (colPers[j] / sumCol) }
                    overW += Float((overcols - 1) * targetGappi)
                    let dx = (Float(w.width) - overW) / 2.0 - Float(targetGappo)

                    flCx += dx
                    for j in 0..<Int(cIdx) { flCx += availW * (colPers[j] / sumCol) + Float(targetGappi) }
                    flCw = availW * (colPers[Int(cIdx)] / sumCol)
                } else {
                    for j in 0..<Int(cIdx) { flCx += availW * (colPers[j] / sumCol) + Float(targetGappi) }
                    flCw = cIdx == cols - 1 ? Float(w.x + w.width - targetGappo) - flCx
                        : availW * (colPers[Int(cIdx)] / sumCol)
                }

                // Y coordinate and height computation.
                var flCy = Float(w.y + targetGappo)
                for j in 0..<Int(rIdx) { flCy += availH * (rowPers[j] / sumRow) + Float(targetGappi) }
                let flCh = rIdx == rows - 1 ? Float(w.y + w.height - targetGappo) - flCy
                    : availH * (rowPers[Int(rIdx)] / sumRow)

                clientTileResize(c, wlrBox(i32(flCx), i32(flCy), i32(flCw), i32(flCh)), false)
                i += 1
            }
        }
    }

    func fair(_ m: Monitor) {
        var n: Int32 = 0
        let w = WBox(m.w)

        n = m.visibleFakeTilingClients
        if n == 0 { return }

        // Gets the gap config.
        var curGappiv: Int32 = enableGaps ? m.gappiv : 0
        var curGappih: Int32 = enableGaps ? m.gappih : 0
        var curGappov: Int32 = enableGaps ? m.gappov : 0
        var curGappoh: Int32 = enableGaps ? m.gappoh : 0

        if config.smartgaps && n == 1 {
            curGappiv = 0; curGappih = 0; curGappov = 0; curGappoh = 0
        }

        // Computes grid row/column counts.
        var cols: Int32 = 0
        while cols <= n {
            if cols * cols >= n { break }
            cols += 1
        }

        let baseRows = n / cols
        let remainder = n % cols
        let firstGroupCols = cols - remainder
        let firstGroupCount = firstGroupCols * baseRows
        let maxRows = baseRows + (remainder > 0 ? 1 : 0)

        // Stores valid clients in an array.
        var arr: [Client] = []
        var colPers = [Float](repeating: 0, count: Int(cols))
        var rowPers = [Float](repeating: 0, count: Int(maxRows))
        var colX = [Float](repeating: 0, count: Int(cols))
        var colW = [Float](repeating: 0, count: Int(cols))
        var rowYBase = [Float](repeating: 0, count: Int(baseRows))
        var rowHBase = [Float](repeating: 0, count: Int(baseRows))
        var rowYMax = [Float](repeating: 0, count: Int(maxRows))
        var rowHMax = [Float](repeating: 0, count: Int(maxRows))
        for c in clients where VISIBLEON(c, m) && ISFAKETILED(c) {
            arr.append(c)
            if arr.count >= Int(n) { break } // Safe bounds.
        }

        func place(_ i: Int32) -> (col: Int32, row: Int32) {
            i < firstGroupCount ? (i / baseRows, i % baseRows)
                : (firstGroupCols + (i - firstGroupCount) / maxRows, (i - firstGroupCount) % maxRows)
        }

        // Two ratio-locking passes directly over the array.
        for (k, c) in arr.enumerated() {
            let (colIdx, rowIdx) = place(Int32(k))
            if c.gridColIdx == colIdx && c.gridColPer > 0.0 { colPers[Int(colIdx)] = c.gridColPer }
            if c.gridRowIdx == rowIdx && c.gridRowPer > 0.0 { rowPers[Int(rowIdx)] = c.gridRowPer }
        }
        for (k, c) in arr.enumerated() {
            let (colIdx, rowIdx) = place(Int32(k))
            if colPers[Int(colIdx)] == 0.0 && c.gridColPer > 0.0 { colPers[Int(colIdx)] = c.gridColPer }
            if rowPers[Int(rowIdx)] == 0.0 && c.gridRowPer > 0.0 { rowPers[Int(rowIdx)] = c.gridRowPer }
        }

        // Fallback strategy and total weight computation.
        var sumCol: Float = 0.0
        for k in 0..<Int(cols) {
            if colPers[k] == 0.0 { colPers[k] = 1.0 }
            sumCol += colPers[k]
        }
        for k in 0..<Int(maxRows) where rowPers[k] == 0.0 { rowPers[k] = 1.0 }

        // Precomputes X coordinates and widths of all columns.
        let availW = Float(w.width - 2 * curGappoh - (cols - 1) * curGappih)
        var nextX = Float(w.x + curGappoh)
        for k in 0..<Int(cols) {
            colX[k] = nextX
            colW[k] = k == Int(cols) - 1 ? Float(w.x + w.width - curGappoh) - nextX : availW * (colPers[k] / sumCol)
            nextX += colW[k] + Float(curGappih)
        }

        // Precomputes two sets of row geometry (handles columns with different row
        // counts).
        var sumRowBase: Float = 0.0
        for k in 0..<Int(baseRows) { sumRowBase += rowPers[k] }
        let availHBase = Float(w.height - 2 * curGappov - (baseRows - 1) * curGappiv)
        var nextY = Float(w.y + curGappov)
        for k in 0..<Int(baseRows) {
            rowYBase[k] = nextY
            rowHBase[k] = k == Int(baseRows) - 1 ? Float(w.y + w.height - curGappov) - nextY
                : availHBase * (rowPers[k] / sumRowBase)
            nextY += rowHBase[k] + Float(curGappiv)
        }

        if remainder > 0 {
            var sumRowMax: Float = 0.0
            for k in 0..<Int(maxRows) { sumRowMax += rowPers[k] }
            let availHMax = Float(w.height - 2 * curGappov - (maxRows - 1) * curGappiv)
            nextY = Float(w.y + curGappov)
            for k in 0..<Int(maxRows) {
                rowYMax[k] = nextY
                rowHMax[k] = k == Int(maxRows) - 1 ? Float(w.y + w.height - curGappov) - nextY
                    : availHMax * (rowPers[k] / sumRowMax)
                nextY += rowHMax[k] + Float(curGappiv)
            }
        }

        // Final rendered layout.
        for (k, c) in arr.enumerated() {
            let i = Int32(k)
            var colIdx: Int32, rowIdx: Int32
            var flCy: Float, flCh: Float

            if i < firstGroupCount {
                colIdx = i / baseRows
                rowIdx = i % baseRows
                flCy = rowYBase[Int(rowIdx)]
                flCh = rowHBase[Int(rowIdx)]
            } else {
                let offset = i - firstGroupCount
                colIdx = firstGroupCols + (offset / maxRows)
                rowIdx = offset % maxRows
                flCy = rowYMax[Int(rowIdx)]
                flCh = rowHMax[Int(rowIdx)]
            }

            c.gridColPer = colPers[Int(colIdx)]
            c.gridRowPer = rowPers[Int(rowIdx)]
            c.gridColIdx = colIdx
            c.gridRowIdx = rowIdx

            let flCx = colX[Int(colIdx)]
            let flCw = colW[Int(colIdx)]

            clientTileResize(c, wlrBox(i32(flCx), i32(flCy), i32(flCw), i32(flCh)), false)
        }
    }







}
