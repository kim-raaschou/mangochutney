import CoreGraphics

/// mango Layout (layout/layout.h). Not in mango: no predict function; the id is the layout's LayoutKind.
package struct Layout {
    package let symbol: String
    package let arrange: @MainActor (MangoServer, Monitor) -> Void
    package let name: String
    package let id: LayoutKind
}

@MainActor package let overviewlayout = Layout(symbol: "󰃇", arrange: { $0.overview($1) }, name: "overview", id: .grid)

@MainActor package let layouts: [Layout] = [
    // At least two are required; fewer than two cannot be removed.
    /* symbol     arrange function   name */
    Layout(symbol: "T", arrange: { $0.tile($1) }, name: "tile", id: .tile), // Tiled layout
    Layout(symbol: "S", arrange: { $0.scroller($1) }, name: "scroller", id: .scroller), // Scroll layout
    Layout(symbol: "G", arrange: { $0.grid($1) }, name: "grid", id: .grid), // Grid layout
    Layout(symbol: "M", arrange: { $0.monocle($1) }, name: "monocle", id: .monocle), // Single layout
    Layout(symbol: "K", arrange: { $0.deck($1) }, name: "deck", id: .deck), // Card layout
    Layout(symbol: "CT", arrange: { $0.centerTile($1) }, name: "center_tile", id: .centerTile), // Centered layout
    Layout(symbol: "RT", arrange: { $0.rightTile($1) }, name: "right_tile", id: .rightTile), // Right layout
    Layout(symbol: "VS", arrange: { $0.verticalScroller($1) }, name: "vertical_scroller", id: .verticalScroller), // Vertical scroll layout
    Layout(symbol: "VT", arrange: { $0.verticalTile($1) }, name: "vertical_tile", id: .verticalTile), // Vertical tiled layout
    Layout(symbol: "VG", arrange: { $0.verticalGrid($1) }, name: "vertical_grid", id: .verticalGrid), // Vertical grid layout
    Layout(symbol: "VK", arrange: { $0.verticalDeck($1) }, name: "vertical_deck", id: .verticalDeck), // Vertical card layout
    Layout(symbol: "DW", arrange: { $0.dwindle($1) }, name: "dwindle", id: .dwindle),
    Layout(symbol: "F", arrange: { $0.fair($1) }, name: "fair", id: .fair),
    Layout(symbol: "VF", arrange: { $0.verticalFair($1) }, name: "vertical_fair", id: .verticalFair),
]

package extension MangoServer {
    func setSizePer(_ m: Monitor, _ c: Client, resetProportion: Bool = false) {
        let keepOwn = !resetProportion && (c.masterSizeWeight > 0 || c.stackSizeWeight > 0)
        let centered = isCentertileLayout(m)
        let tiled = tiledClients(m)
        c.masterMfactPer = CGFloat(m.pertag.mfacts[getMonCurtag(m)])
        for fc in tiled where fc !== c && fc.masterMfactPer > 0 {
            if centered && fc.isleftstack != c.isleftstack { continue }
            c.masterMfactPer = fc.masterMfactPer
            break
        }
        let curtag = getMonCurtag(m)
        if keepOwn {
            if !c.iscustomScrollerProportion && c.scrollerProportion <= 0.0 {
                c.scrollerProportion = m.pertag.scrollerDefaultProportion[curtag]
            }
            if !c.iscustomScrollerProportionSingle && c.scrollerProportionSingle <= 0.0 {
                c.scrollerProportionSingle = m.pertag.scrollerDefaultProportionSingle[curtag]
            }
            return
        }
        var found = false
        for fc in tiled where fc !== c {
            if centered && fc.isleftstack != c.isleftstack { continue }
            c.masterSizeWeight = fc.masterSizeWeight
            c.stackSizeWeight = fc.stackSizeWeight
            found = true
            break
        }
        if !found || c.masterSizeWeight <= 0 || c.stackSizeWeight <= 0 {
            c.masterSizeWeight = 1
            c.stackSizeWeight = 1
        }
        c.masterInnerPer = c.masterSizeWeight
        c.stackInnerPer = c.stackSizeWeight
        if !c.iscustomScrollerProportion { c.scrollerProportion = m.pertag.scrollerDefaultProportion[curtag] }
        if !c.iscustomScrollerProportionSingle { c.scrollerProportionSingle = m.pertag.scrollerDefaultProportionSingle[curtag] }
    }

    func persistTileSizeWeights(_ m: Monitor) {
        for c in clients where VISIBLEON(c, m) && !c.isfloating && !c.isminimized && !c.isunglobal {
            if c.ismaster { c.masterSizeWeight = c.masterInnerPer } else { c.stackSizeWeight = c.stackInnerPer }
        }
    }

    // not in mango: resize_tile_master_horizontal and _vertical in one; `vertical` says which
    func resizeTileMaster(_ gc: Client, isdrag: Bool, offsetX: CGFloat, offsetY: CGFloat, cursor: CGPoint,
                          type: LayoutKind, vertical: Bool) {
        guard let m = gc.mon else { return }
        let tiled = tiledClients(m)
        guard let gi = tiled.firstIndex(where: { $0 === gc }) else { return }
        let next = gi + 1 < tiled.count ? tiled[gi + 1] : nil
        let nextnext = gi + 2 < tiled.count ? tiled[gi + 2] : nil
        let prev = gi > 0 ? tiled[gi - 1] : nil
        let prevprev = gi > 1 ? tiled[gi - 2] : nil
        let geom = gc.geom
        if !startDragWindow && isdrag {
            dragBeginCursor = cursor
            startDragWindow = true
            gc.oldMasterMfactPer = gc.masterMfactPer
            gc.oldMasterInnerPer = gc.masterInnerPer
            gc.oldStackInnerPer = gc.stackInnerPer
            gc.cursorInUpperHalf = cursor.y < geom.minY + (geom.height / 2).rounded(.towardZero)
            gc.cursorInLeftHalf = cursor.x < geom.minX + (geom.width / 2).rounded(.towardZero)
            gc.dragBeginGeom = geom
            return
        }
        var ox = offsetX, oy = offsetY
        if isdrag {
            ox = cursor.x - dragBeginCursor.x
            oy = cursor.y - dragBeginCursor.y
        } else {
            gc.oldMasterMfactPer = gc.masterMfactPer
            gc.oldMasterInnerPer = gc.masterInnerPer
            gc.oldStackInnerPer = gc.stackInnerPer
            gc.dragBeginGeom = geom
            gc.cursorInUpperHalf = true
            gc.cursorInLeftHalf = false
        }
        let bw = Float(max(1, gc.dragBeginGeom.width)), bh = Float(max(1, gc.dragBeginGeom.height))
        let oldMfact = Float(gc.oldMasterMfactPer), oldMInner = Float(gc.oldMasterInnerPer), oldSInner = Float(gc.oldStackInnerPer)
        var across: Float, along: Float
        if !vertical {
            across = Float(ox) * (gc.ismaster ? oldMfact : 1 - oldMfact) / bw
            along = Float(oy) * (gc.ismaster ? oldMInner : oldSInner) / bh
        } else {
            along = Float(ox) * (gc.ismaster ? oldMInner : oldSInner) / bw
            across = Float(oy) * (gc.ismaster ? oldMfact : 1 - oldMfact) / bh
        }
        let back: Bool, forth: Bool
        let first = vertical ? gc.cursorInLeftHalf : gc.cursorInUpperHalf
        if !isdrag {
            back = (vertical ? ox : oy) < 0
            forth = (vertical ? ox : oy) > 0
        } else {
            back = vertical ? cursor.x < dragBeginCursor.x : cursor.y < dragBeginCursor.y
            forth = vertical ? cursor.x > dragBeginCursor.x : cursor.y > dragBeginCursor.y
        }
        if gc.ismaster && prev == nil {
            along = back ? -abs(along) : abs(along)
        } else if gc.ismaster, let next, !next.ismaster {
            along = back ? abs(along) : -abs(along)
        } else if !gc.ismaster, let prev, prev.ismaster {
            along = back ? -abs(along) : abs(along)
        } else if !gc.ismaster && next == nil {
            along = back ? abs(along) : -abs(along)
        } else if !vertical && type == .centerTile && !gc.ismaster && nextnext == nil {
            along = back ? abs(along) : -abs(along)
        } else if !vertical && type == .centerTile && !gc.ismaster, let prevprev, prevprev.ismaster {
            along = back ? -abs(along) : abs(along)
        } else if (first && back) || (!first && forth) {
            along = abs(along) * 2
        } else {
            along = -abs(along) * 2
        }
        if !vertical {
            if !gc.ismaster && gc.isleftstack && type == .centerTile { across = -across }
            if gc.ismaster && type == .centerTile && gc.cursorInLeftHalf { across = -across }
            if gc.ismaster && type == .centerTile { across *= 2 }
            if type == .rightTile { across = -across }
        }
        let newMfact = max(0.1, min(0.9, oldMfact + across))
        let newMInner = max(0.1, min(0.9, oldMInner + along))
        let newSInner = max(0.1, min(0.9, oldSInner + along))
        if isdrag {
            if gc.ismaster {
                let cur = 1 - Float(gc.masterInnerPer), new = 1 - newMInner
                if cur > 0.001 {
                    for tc in tiled where tc.ismaster && tc !== gc { tc.masterInnerPer *= CGFloat(new / cur) }
                }
            } else {
                let cur = 1 - Float(gc.stackInnerPer), new = 1 - newSInner
                if cur > 0.001 {
                    for tc in tiled where !tc.ismaster && tc !== gc
                        && (vertical || type != .centerTile || tc.isleftstack == gc.isleftstack) {
                        tc.stackInnerPer *= CGFloat(new / cur)
                    }
                }
            }
        } else {
            for tc in tiled where tc !== gc {
                if !tc.ismaster && newSInner != 1 && oldSInner != 1
                    && (vertical || type != .centerTile || tc.isleftstack == gc.isleftstack) {
                    tc.stackInnerPer = CGFloat((1 - newSInner) / (1 - oldSInner)) * tc.stackInnerPer
                }
                if tc.ismaster && newMInner != 1 && oldMInner != 1 {
                    tc.masterInnerPer = CGFloat((1 - newMInner) / (1 - oldMInner)) * tc.masterInnerPer
                }
            }
        }
        gc.masterInnerPer = CGFloat(newMInner)
        gc.stackInnerPer = CGFloat(newSInner)
        for tc in tiled { tc.masterMfactPer = CGFloat(newMfact) }
        persistTileSizeWeights(m)
        if !isdrag {
            arrange(m, false, false)
            return
        }
        arrange(m, false, false)
    }

    func resizeTileDwindle(_ gc: Client, isdrag: Bool, offsetX: CGFloat, offsetY: CGFloat, cursor: CGPoint) {
        guard let m = gc.mon else { return }
        if !isdrag {
            dwindleResizeClientStep(m, gc, Int32(offsetX), Int32(offsetY))
            return
        }

        dwindleResizeClient(m, gc)
    }

    func resizeTileGridFair(_ gc: Client, isdrag: Bool, offsetX: CGFloat, offsetY: CGFloat, cursor: CGPoint) {
        guard let m = gc.mon, !gc.isfullscreen, !gc.ismaximizescreen, !m.isoverview else { return }
        let tiled = tiledClients(m)
        guard tiled.count > 1 else { return }
        func recordOldShares() {
            for c in clientsAll {
                c.oldGridColPer = c.gridColPer > 0 ? c.gridColPer : 1
                c.oldGridRowPer = c.gridRowPer > 0 ? c.gridRowPer : 1
            }
        }
        if !startDragWindow && isdrag {
            dragBeginCursor = cursor
            startDragWindow = true
            recordOldShares()
            gc.oldGridColPer = gc.gridColPer
            gc.oldGridRowPer = gc.gridRowPer
            let geom = directionGeom(gc)
            gc.cursorInLeftHalf = cursor.x < geom.minX + (geom.width / 2).rounded(.towardZero)
            gc.cursorInUpperHalf = cursor.y < geom.minY + (geom.height / 2).rounded(.towardZero)
            gc.dragBeginGeom = geom
            return
        }
        var ox = offsetX, oy = offsetY
        if isdrag {
            ox = cursor.x - dragBeginCursor.x
            oy = cursor.y - dragBeginCursor.y
        } else {
            gc.dragBeginGeom = directionGeom(gc)
            recordOldShares()
            gc.cursorInUpperHalf = false
            gc.cursorInLeftHalf = false
        }
        let deltaX = Float(ox) * Float(gc.oldGridColPer) / Float(max(1, gc.dragBeginGeom.width))
        let deltaY = Float(oy) * Float(gc.oldGridRowPer) / Float(max(1, gc.dragBeginGeom.height))
        var adjC = gc.gridColIdx, adjR = gc.gridRowIdx
        var signX: Float = 1, signY: Float = 1

        if isdrag {
            if gc.cursorInLeftHalf {
                adjC -= 1
                signX = -1
            } else {
                adjC += 1
                signX = 1
            }

            if gc.cursorInUpperHalf {
                adjR -= 1
                signY = -1
            } else {
                adjR += 1
                signY = 1
            }
        }
        // Keyboard hotkey logic unchanged.
        let maxCol = tiled.map(\.gridColIdx).max() ?? 0, minCol = tiled.map(\.gridColIdx).min() ?? 0
        let maxRow = tiled.map(\.gridRowIdx).max() ?? 0, minRow = tiled.map(\.gridRowIdx).min() ?? 0

        // not in mango: for the keyboard only; mango overwrites the drag's neighbour with it
        // (a mango bug, docs/afvigelser.md §6)
        if !isdrag {
            adjC = gc.gridColIdx + 1
            adjR = gc.gridRowIdx + 1
            signX = 1
            signY = 1

            if gc.gridColIdx == maxCol { adjC = gc.gridColIdx - 1; signX = -1 }
            if gc.gridRowIdx == maxRow { adjR = gc.gridRowIdx - 1; signY = -1 }
            if gc.gridColIdx == minCol { adjC = gc.gridColIdx + 1; signX = 1 }
            if gc.gridRowIdx == minRow { adjR = gc.gridRowIdx + 1; signY = 1 }
        }
        let dx = deltaX * signX, dy = deltaY * signY
        let myOldCol = Float(gc.oldGridColPer), myOldRow = Float(gc.oldGridRowPer)
        var adjOldCol: Float = -1, adjOldRow: Float = -1
        for c in tiled {
            if c.gridColIdx == adjC && adjOldCol < 0 { adjOldCol = Float(c.oldGridColPer) }
            if c.gridRowIdx == adjR && adjOldRow < 0 { adjOldRow = Float(c.oldGridRowPer) }
        }
        let n = tiled.count
        func lockedShare(_ mine: Float, _ adj: Float, _ d: Float, first: Bool) -> (Float, Float) {
            var p = first ? (mine + d) / (mine + adj) : (adj - d) / (mine + adj)
            p = min(max(p, 0.01), 0.99)
            let v = min(max(p / (1 - p), 0.1), 10)
            return first ? (v, 1) : (1, v)
        }
        if adjOldCol > 0 {
            var d = dx
            if myOldCol + d < 0.1 { d = 0.1 - myOldCol }
            if adjOldCol - d < 0.1 { d = adjOldCol - 0.1 }
            var (newMy, newAdj) = (myOldCol + d, adjOldCol - d)
            if m.layout == .verticalFair {
                var rows = 0
                while rows * rows < n { rows += 1 }
                let baseCols = n / rows
                if (gc.gridColIdx == baseCols - 1 && adjC == baseCols) || (gc.gridColIdx == baseCols && adjC == baseCols - 1) {
                    (newMy, newAdj) = lockedShare(myOldCol, adjOldCol, dx, first: gc.gridColIdx == baseCols - 1)
                }
            }
            for c in tiled {
                if c.gridColIdx == gc.gridColIdx { c.gridColPer = CGFloat(newMy) }
                if c.gridColIdx == adjC { c.gridColPer = CGFloat(newAdj) }
            }
        }
        if adjOldRow > 0 {
            var d = dy
            if myOldRow + d < 0.1 { d = 0.1 - myOldRow }
            if adjOldRow - d < 0.1 { d = adjOldRow - 0.1 }
            var (newMy, newAdj) = (myOldRow + d, adjOldRow - d)
            if m.layout == .fair {
                var cols = 0
                while cols * cols < n { cols += 1 }
                let baseRows = n / cols
                if (gc.gridRowIdx == baseRows - 1 && adjR == baseRows) || (gc.gridRowIdx == baseRows && adjR == baseRows - 1) {
                    (newMy, newAdj) = lockedShare(myOldRow, adjOldRow, dy, first: gc.gridRowIdx == baseRows - 1)
                }
            }
            for c in tiled {
                if c.gridRowIdx == gc.gridRowIdx { c.gridRowPer = CGFloat(newMy) }
                if c.gridRowIdx == adjR { c.gridRowPer = CGFloat(newAdj) }
            }
        }
        arrange(m, false, false)
    }

    func resizeTileScroller(_ gc: Client, isdrag: Bool, offsetX: CGFloat, offsetY: CGFloat, cursor: CGPoint,
                            vertical isvertical: Bool) {
        if gc.isfullscreen || gc.ismaximizescreen { return }
        guard let m = gc.mon else { return }
        if m.isoverview { return }

        let tag = getClientTagIdx(gc)
        guard let st = m.pertag.scrollerState[tag] else { return }

        guard let curnode = findScrollerNode(st, gc) else { return }

        var headnode = curnode
        while let p = headnode.prevInStack { headnode = p }

        let stackHeadClient = headnode.client

        var deltaX: Float, deltaY: Float
        var newScrollerProportion: Float
        var newStackProportion: Float
        var offsetx = Int32(offsetX), offsety = Int32(offsetY)

        if !startDragWindow && isdrag {
            dragBeginCursor = cursor   // not in mango: the port's cursor
            startDragWindow = true

            headnode.client.oldScrollerPproportion = Double(headnode.scrollerProportion)
            gc.scrollerOldStackProportion = curnode.scrollerStackProportion

            gc.cursorInLeftHalf = cursor.x < gc.geom.minX + (gc.geom.width / 2).rounded(.towardZero)
            gc.cursorInUpperHalf = cursor.y < gc.geom.minY + (gc.geom.height / 2).rounded(.towardZero)
            gc.dragBeginGeom = gc.geom
        } else {
            if isdrag {
                offsetx = Int32(cursor.x - dragBeginCursor.x)
                offsety = Int32(cursor.y - dragBeginCursor.y)
            } else {
                gc.oldMasterMfactPer = gc.masterMfactPer
                gc.oldMasterInnerPer = gc.masterInnerPer
                gc.oldStackInnerPer = gc.stackInnerPer
                gc.dragBeginGeom = gc.geom
                stackHeadClient.oldScrollerPproportion = Double(headnode.scrollerProportion)
                gc.scrollerOldStackProportion = curnode.scrollerStackProportion
                gc.cursorInUpperHalf = false
                gc.cursorInLeftHalf = false
            }

            if isvertical {
                deltaY = Float(Double(offsety) * headnode.client.oldScrollerPproportion / Double(Int32(gc.dragBeginGeom.height)))
                deltaX = Float(offsetx) * gc.scrollerOldStackProportion / Float(Int32(gc.dragBeginGeom.width))
            } else {
                deltaX = Float(Double(offsetx) * headnode.client.oldScrollerPproportion / Double(Int32(gc.dragBeginGeom.width)))
                deltaY = Float(offsety) * gc.scrollerOldStackProportion / Float(Int32(gc.dragBeginGeom.height))
            }

            let movingUp: Bool, movingDown: Bool, movingLeft: Bool, movingRight: Bool
            if !isdrag {
                movingUp = offsety < 0
                movingDown = offsety > 0
                movingLeft = offsetx < 0
                movingRight = offsetx > 0
            } else {
                movingUp = cursor.y < dragBeginCursor.y
                movingDown = cursor.y > dragBeginCursor.y
                movingLeft = cursor.x < dragBeginCursor.x
                movingRight = cursor.x > dragBeginCursor.x
            }

            if (gc.cursorInUpperHalf && movingUp) || (!gc.cursorInUpperHalf && movingDown) {
                deltaY = abs(deltaY)
            } else {
                deltaY = -abs(deltaY)
            }

            if (gc.cursorInLeftHalf && movingLeft) || (!gc.cursorInLeftHalf && movingRight) {
                deltaX = abs(deltaX)
            } else {
                deltaX = -abs(deltaX)
            }

            if isvertical {
                if curnode.nextInStack == nil && curnode.prevInStack != nil && !isdrag {
                    deltaX = deltaX * -1.0
                }
                if curnode.nextInStack == nil && curnode.prevInStack != nil && isdrag {
                    if movingRight { deltaX = -abs(deltaX) } else { deltaX = abs(deltaX) }
                }
                if curnode.prevInStack == nil && curnode.nextInStack != nil && isdrag {
                    if movingLeft { deltaX = -abs(deltaX) } else { deltaX = abs(deltaX) }
                }
                if isdrag {
                    if movingUp { deltaY = -abs(deltaY) } else { deltaY = abs(deltaY) }
                }
            } else {
                if curnode.nextInStack == nil && curnode.prevInStack != nil && !isdrag {
                    deltaY = deltaY * -1.0
                }
                if curnode.nextInStack == nil && curnode.prevInStack != nil && isdrag {
                    if movingDown { deltaY = -abs(deltaY) } else { deltaY = abs(deltaY) }
                }
                if curnode.prevInStack == nil && curnode.nextInStack != nil && isdrag {
                    if movingUp { deltaY = -abs(deltaY) } else { deltaY = abs(deltaY) }
                }
                if isdrag {
                    if movingLeft { deltaX = -abs(deltaX) } else { deltaX = abs(deltaX) }
                }
            }

            if isvertical {
                newScrollerProportion = Float(headnode.client.oldScrollerPproportion + Double(deltaY))
                newStackProportion = gc.scrollerOldStackProportion + deltaX
            } else {
                newScrollerProportion = Float(headnode.client.oldScrollerPproportion + Double(deltaX))
                newStackProportion = gc.scrollerOldStackProportion + deltaY
            }

            newScrollerProportion = max(0.1, min(1.0, newScrollerProportion))
            newStackProportion = max(0.1, min(0.9, newStackProportion))

            // Keeps the sum at 1 so later arrange normalization does not swallow
            // the offset.
            if isdrag {
                let currentOtherSum: Float = 1.0 - curnode.scrollerStackProportion
                let newOtherSum: Float = 1.0 - newStackProportion
                if currentOtherSum > 0.001 {
                    let scale = newOtherSum / currentOtherSum
                    var tc: ScrollerStackNode? = headnode
                    while let n = tc {
                        if n !== curnode { n.scrollerStackProportion *= scale }
                        tc = n.nextInStack
                    }
                }
            } else {
                // Keyboard stepping.
                if gc.scrollerOldStackProportion != 1.0 {
                    var tc: ScrollerStackNode? = headnode
                    while let n = tc {
                        if n !== curnode {
                            n.scrollerStackProportion = (1.0 - newStackProportion)
                                / (1.0 - gc.scrollerOldStackProportion) * n.scrollerStackProportion
                        }
                        tc = n.nextInStack
                    }
                }
            }

            curnode.scrollerStackProportion = newStackProportion

            if m.visibleScrollTilingClients > 1 || config.scrollerIgnoreProportionSingle {
                headnode.scrollerProportion = newScrollerProportion
            }

            var stnode: ScrollerStackNode? = headnode
            while let n = stnode {
                n.scrollerStackWeight = n.scrollerStackProportion
                stnode = n.nextInStack
            }

            /* Syncs back to the global fields. */
            syncScrollerStateToClients(m, tag)

            arrange(m, false, false)
        }
    }

    func resizeTileClient(_ gc: Client, isdrag: Bool = false, offsetX: CGFloat, offsetY: CGFloat, cursor: CGPoint = .zero) {
        guard let m = gc.mon, !gc.isfullscreen, !gc.ismaximizescreen, !m.isoverview else { return }
        let layout = m.pertag.ltidxs[getClientTagIdx(gc)]
        switch layout {
        case .tile, .deck, .centerTile, .rightTile:
            resizeTileMaster(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor,
                             type: layout, vertical: false)
        case .verticalTile, .verticalDeck:
            resizeTileMaster(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor,
                             type: layout, vertical: true)
        case .scroller:
            resizeTileScroller(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor, vertical: false)
        case .verticalScroller:
            resizeTileScroller(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor, vertical: true)
        case .dwindle:
            resizeTileDwindle(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor)
        case .grid, .verticalGrid, .fair, .verticalFair:
            resizeTileGridFair(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor)
        default:
            break
        }
    }

    func specialKeepBgClient(_ m: Monitor, _ c: Client) -> Bool {
        isSpecialActive(m) && !c.isminimized
            && ((m.pertag.prevtag > 0 && c.tags & (1 << (m.pertag.prevtag - 1)) != 0)
                || c.tags & (m.tagset[m.seltags ^ 1] & ~TAG0_MASK) != 0)
    }

    // not in mango: `fake`, the windows wl_list_for_each with VISIBLEON and ISFAKETILED finds
    func resetSizePerMon(_ m: Monitor, _ fake: [Client], totalLeftStackWeight totalLeft: CGFloat,
                         totalRightStackWeight totalRight: CGFloat, totalStackWeight totalStack: CGFloat,
                         totalMasterWeight totalMaster: CGFloat, masterNum: Int, stackNum: Int) {
        let nmasters = m.pertag.nmasters[getMonCurtag(m)]
        let centered = isCentertileLayout(m)
        for (i, c) in fake.enumerated() {
            if totalMaster > 0 && i < nmasters {
                c.ismaster = true
                c.masterInnerPer = c.masterSizeWeight / totalMaster
                let stackSide = centered ? totalLeft + totalRight : totalStack
                c.stackInnerPer = stackSide > 0 ? c.stackSizeWeight / (stackSide + c.stackSizeWeight) : 1
            } else {
                c.ismaster = false
                c.masterInnerPer = totalMaster > 0 ? c.masterSizeWeight / (totalMaster + c.masterSizeWeight)
                    : (masterNum > 0 ? 1 / CGFloat(masterNum) : 1)
                if centered {
                    let side = c.isleftstack ? totalLeft : totalRight
                    c.stackInnerPer = side > 0 ? c.stackSizeWeight / side : 1
                } else {
                    c.stackInnerPer = totalStack > 0 ? c.stackSizeWeight / totalStack
                        : (stackNum > 0 ? 1 / CGFloat(stackNum) : 1)
                }
            }
        }
    }

    func preCalculateBeforeArrange(_ m: Monitor, _ wantAnimation: Bool, _ fromView: Bool, _ onlyCalculate: Bool) {
        var totalStackWeight: CGFloat = 0
        var totalMasterWeight: CGFloat = 0
        var totalRightStackWeight: CGFloat = 0
        var totalLeftStackWeight: CGFloat = 0
        var i = 0
        var nmasters = 0
        var stackIndex = 0
        var masterNum = 0
        var stackNum = 0

        m.visibleClients = 0
        m.visibleTilingClients = 0
        m.visibleScrollTilingClients = 0
        m.visibleFakeTilingClients = 0
        m.hideClients = 0

        let tag = getMonCurtag(m)
        let st = m.pertag.scrollerState[tag]

        let curLayout = m.pertag.ltidxs[tag]
        if curLayout == .scroller || curLayout == .verticalScroller {
            updateScrollerState(m)
        }

        for c in clients {
            if fromView && (c.isglobal || c.isunglobal) {
                setSizePer(m, c, resetProportion: true)
            }

            // not in mango: client_check_tab_node_visible; the port draws the bars from the state

            if c.mon === m && (c.isglobal || c.isunglobal) {
                c.tags = m.tagset[m.seltags]
            }

            if fromView && m.sel == nil && c.isglobal && VISIBLEON(c, m) {
                clientFocus(c, true)
            }

            if c.isminimized {
                m.hideClients += 1
            }

            if VISIBLEON(c, m) {
                if fromView && !clientOnlyInOneTag(c) {
                    setSizePer(m, c, resetProportion: true)
                }

                if !c.isunglobal { m.visibleClients += 1 }

                if ISTILED(c) {
                    m.visibleTilingClients += 1

                    /* Updates the visible scroll-client count. */
                    if let st {
                        let n = findScrollerNode(st, c)
                        if let n, n.prevInStack == nil { /* Is a stack head. */
                            m.visibleScrollTilingClients += 1
                        }
                    } else if ISSCROLLTILED(c) {
                        m.visibleScrollTilingClients += 1
                    }
                }

                if ISFAKETILED(c) {
                    m.visibleFakeTilingClients += 1
                }
            }
        }

        nmasters = Int(m.pertag.nmasters[getMonCurtag(m)])

        var fake: [Client] = []   // not in mango: reset_size_per_mon's VISIBLEON and ISFAKETILED clients
        for c in clients {
            if c.iskilling { continue }

            if c.mon === m {
                if VISIBLEON(c, m) {
                    if ISFAKETILED(c) {
                        fake.append(c)
                        if c.masterSizeWeight <= 0.0 { c.masterSizeWeight = 1.0 }
                        if c.stackSizeWeight <= 0.0 { c.stackSizeWeight = 1.0 }

                        if i < nmasters {
                            masterNum += 1
                            totalMasterWeight += c.masterSizeWeight
                        } else {
                            stackNum += 1
                            totalStackWeight += c.stackSizeWeight
                            stackIndex = i - nmasters
                            if (stackIndex % 2 == 1) != (m.visibleTilingClients % 2 == 0) {
                                c.isleftstack = false
                                totalRightStackWeight += c.stackSizeWeight
                            } else {
                                c.isleftstack = true
                                totalLeftStackWeight += c.stackSizeWeight
                            }
                        }
                        i += 1
                    }

                    // not in mango: the unmanaged global client stays where it is
                    if !onlyCalculate && !c.isunglobal {
                        setArrangeVisible(m, c, wantAnimation)
                    }
                } else if specialKeepBgClient(m, c) {
                    c.tagVisible = true
                    clientUpdateVisibility(c)
                    c.animation.running = false
                    c.animation.tagining = false
                    c.animation.tagouting = false
                } else if !onlyCalculate && c !== grabClient {
                    setArrangeHidden(m, c, wantAnimation)
                }

                // not in mango: client_sync_layer; the port raises the clients at the end of arrange
            }

            if !onlyCalculate && c.mon === m && c.ismaximizescreen && !c.animation.tagouted
                && !c.animation.tagouting && VISIBLEON(c, m) {
                resetMaximizescreenSize(c)
            }
        }

        resetSizePerMon(m, fake, totalLeftStackWeight: totalLeftStackWeight, totalRightStackWeight: totalRightStackWeight,
                        totalStackWeight: totalStackWeight, totalMasterWeight: totalMasterWeight,
                        masterNum: masterNum, stackNum: stackNum)

        specialUpdateDim(m)
    }

    // remap tags through map; unmapped tags stay as-is.
    func tagRemapMask(_ tags: UInt32, _ map: [UInt32]) -> UInt32 {
        var out = tags & ~TAGMASK

        for i in 1...UInt32(config.tagNum) where tags & (1 << (i - 1)) != 0 {
            out |= map[Int(i)] != 0 ? (1 << (map[Int(i)] - 1)) : (1 << (i - 1))
        }
        return out
    }

    func tagGatherApply(_ m: Monitor) {
        var occupied: UInt32 = 0
        var map = [UInt32](repeating: 0, count: Int(tag_num_MAX) + 1)
        var next: UInt32 = 1
        var changed = false

        // collect occupied tags on this monitor.
        for c in clients where c.mon === m && !c.iskilling && (c.tags & TAG0_MASK) == 0 {
            occupied |= c.tags & tagmask
        }
        // the current view counts as occupied even when empty.
        occupied |= m.tagset[m.seltags] & tagmask

        // old->new mapping and detect gaps.
        for i in 1...UInt32(config.tagNum) {
            if occupied & (1 << (i - 1)) != 0 {
                map[Int(i)] = next
                next += 1
                if map[Int(i)] != i { changed = true }
            } else {
                map[Int(i)] = 0
            }
        }

        if !changed { return }

        // remap client tags.
        for c in clients {
            if c.mon !== m || c.iskilling || (c.tags & TAG0_MASK) != 0 { continue }
            c.tags = tagRemapMask(c.tags, map)
        }

        // remap current/previous views (and overview backups).
        m.tagset[m.seltags] = tagRemapMask(m.tagset[m.seltags], map)
        m.tagset[m.seltags ^ 1] = tagRemapMask(m.tagset[m.seltags ^ 1], map)
        m.ovbkCurrentTagset = tagRemapMask(m.ovbkCurrentTagset, map)
        m.ovbkPrevTagset = tagRemapMask(m.ovbkPrevTagset, map)

        // keep view indices; empty tags stay unchanged.
        if m.pertag.curtag <= UInt32(config.tagNum) && map[Int(m.pertag.curtag)] != 0 {
            m.pertag.curtag = map[Int(m.pertag.curtag)]
        }
        if m.pertag.prevtag <= UInt32(config.tagNum) && map[Int(m.pertag.prevtag)] != 0 {
            m.pertag.prevtag = map[Int(m.pertag.prevtag)]
        }

        // move per-tag state in ascending order so later moves don't clobber
        // earlier sources.
        for i in 1...UInt32(config.tagNum) where map[Int(i)] != 0 && map[Int(i)] != i {
            tagGatherMovePertag(m, map[Int(i)], i)
        }

        // reset trailing empty slots.
        let k = next - 1
        if k + 1 <= UInt32(config.tagNum) {
            for i in (k + 1)...UInt32(config.tagNum) { tagGatherResetSlot(m, i) }
        }
    }

    func specialHandleEmptyView(_ m: Monitor, _ fromView: Bool) -> Bool {
        if !isSpecialActive(m) {
            m.specialEmptyView = false
            return false
        }
        if specialHasClients(m) {
            m.specialEmptyView = false
            return false
        }
        if fromView {
            m.specialEmptyView = true
            return false
        }
        if !m.specialEmptyView {
            toggleSpecialTagMon(m)
            return true
        }
        return false
    }

    func arrange(_ m: Monitor, _ wantAnimation: Bool, _ fromView: Bool) {
        guard started else { return }   // not in mango: no arrange before the port has its windows

        // not in mango: the overview before pre_calculate_before_arrange; its cards are the port's pictures
        if m.isoverview {
            m.hideClients = 0
            for c in clients where c.isminimized { m.hideClients += 1 }
            overviewlayout.arrange(self, m)
            return
        }

        if m.sel == nil {
            m.sel = clientFocusTop(m)?.id
        }

        if specialHandleEmptyView(m, fromView) { return }

        preCalculateBeforeArrange(m, wantAnimation, fromView, false)
        /* Must run after pre_calculate: global windows get their tags rewritten
         * there. */
        tabSyncMonitor(m)

        let isTag0 = isSpecialActive(m)
        // not in mango: special_sync_top_layer (macOS has no layer shell)
        let savedOh = m.gappoh, savedOv = m.gappov
        let savedIh = m.gappih, savedIv = m.gappiv

        if isTag0 {
            m.gappoh = m.specialGappoh
            m.gappov = m.specialGappov
            m.gappih = m.specialGappih
            m.gappiv = m.specialGappiv
        }

        layouts.first { $0.id == m.pertag.ltidxs[getMonCurtag(m)] }!.arrange(self, m)   // not in mango: ltidxs holds the id

        if isTag0 {
            m.gappoh = savedOh
            m.gappov = savedOv
            m.gappih = savedIh
            m.gappiv = savedIv
        }

        // not in mango: client_sync_layer's layers, raised by the port
        clientRaiseLayers(m)
        updateBorders()

        // gather after layout/animation setup so tag-switch animations still play.
        if config.tagGather {
            tagGatherApply(m)
        }

        if !startDragWindow {
            pointerProcessMotion(0, 0, 0)
            // not in mango: no check_idle_inhibitor (macOS's)
        }

        printstatus(.arrangge)
    }


    /// Not in mango: client_sync_layer's scene layers; the port raises the fullscreen, maximized,
    /// scratchpad and overlay clients, the selected one last.
    func clientRaiseLayers(_ m: Monitor) {
        var raise: [Client] = []
        for c in visibleClients(m) where !c.isunglobal && !c.dragToTile {
            if SCRATCHPAD_SHOWN(c) || c.isfullscreen || c.ismaximizescreen || c.isoverlay { raise.append(c) }
        }
        if m.layout.isMonocleLike, let s = m.sel.flatMap({ clientByIdAll($0) }), !s.isfloating { raise.insert(s, at: 0) }

        let sel = m.sel.flatMap { clientByIdAll($0) }
        for c in raise where c !== sel {
            if let sel, sel.pid == c.pid { continue }
            system.raise(c)
        }
        if let sel, raise.contains(where: { $0 === sel }) { system.raise(sel) }
    }
}
