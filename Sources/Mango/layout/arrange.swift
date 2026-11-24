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
        var found = false

        let tag = getMonCurtag(m)
        let currentLayout = m.pertag.ltidxs[tag]

        let keepOwn = !resetProportion && (c.masterSizeWeight > 0.0 || c.stackSizeWeight > 0.0)

        c.masterMfactPer = CGFloat(m.pertag.mfacts[tag])
        for fc in clients {
            if fc === c || !VISIBLEON(fc, m) || !ISTILED(fc) || fc.masterMfactPer <= 0.0 {
                continue
            }
            if currentLayout == .centerTile && (fc.isleftstack != c.isleftstack) {
                continue
            }
            c.masterMfactPer = fc.masterMfactPer
            break
        }

        if keepOwn {
            if !c.iscustomScrollerProportion && c.scrollerProportion <= 0.0 {
                c.scrollerProportion = m.pertag.scrollerDefaultProportion[tag]
            }
            if !c.iscustomScrollerProportionSingle && c.scrollerProportionSingle <= 0.0 {
                c.scrollerProportionSingle = m.pertag.scrollerDefaultProportionSingle[tag]
            }
            return
        }

        /* New client or reset_proportion: copy a neighbour's weight as its own. */
        for fc in clients {
            if VISIBLEON(fc, m) && ISTILED(fc) && fc !== c {
                if currentLayout == .centerTile && (fc.isleftstack != c.isleftstack) {
                    continue
                }
                c.masterSizeWeight = fc.masterSizeWeight
                c.stackSizeWeight = fc.stackSizeWeight
                found = true
                break
            }
        }

        if !found || c.masterSizeWeight <= 0.0 || c.stackSizeWeight <= 0.0 {
            c.masterSizeWeight = 1.0
            c.stackSizeWeight = 1.0
        }

        c.masterInnerPer = c.masterSizeWeight
        c.stackInnerPer = c.stackSizeWeight

        if !c.iscustomScrollerProportion {
            c.scrollerProportion = m.pertag.scrollerDefaultProportion[tag]
        }

        if !c.iscustomScrollerProportionSingle {
            c.scrollerProportionSingle = m.pertag.scrollerDefaultProportionSingle[tag]
        }
    }

    /* Manual resize: freeze the proportions just computed into the weights. */
    func persistTileSizeWeights(_ m: Monitor) {
        for c in clients {
            if !VISIBLEON(c, m) || !ISFAKETILED(c) {
                continue
            }
            if c.ismaster {
                c.masterSizeWeight = c.masterInnerPer
            } else {
                c.stackSizeWeight = c.stackInnerPer
            }
        }
    }

    func resizeTileMasterHorizontal(_ gc: Client, _ isdrag: Bool, _ offsetx: Int32, _ offsety: Int32,
                                    _ type: LayoutKind) {
        var offsetx = offsetx, offsety = offsety
        var deltaX: Float, deltaY: Float
        var next: Client?
        var prev: Client?
        var nextnext: Client?
        var prevprev: Client?
        var beginFindNextnext = false
        var beginFindPrevprev = false
        guard let m = gc.mon, let gi = clients.firstIndex(where: { $0 === gc }) else { return }   // not in mango: gc->mon is set and gc is in server.clients here
        let cursor = system.pointer   // not in mango: the port's cursor

        /* Finds next / nextnext. */
        for tc in clients[(gi + 1)...] {
            if beginFindNextnext && VISIBLEON(tc, m) && ISTILED(tc) {
                nextnext = tc
                break
            }
            if !beginFindNextnext && VISIBLEON(tc, m) && ISTILED(tc) {
                next = tc
                beginFindNextnext = true
                continue
            }
        }

        /* Finds prev / prevprev. */
        for tc in clients[..<gi].reversed() {
            if beginFindPrevprev && VISIBLEON(tc, m) && ISTILED(tc) {
                prevprev = tc
                break
            }
            if !beginFindPrevprev && VISIBLEON(tc, m) && ISTILED(tc) {
                prev = tc
                beginFindPrevprev = true
                continue
            }
        }

        if !startDragWindow && isdrag {
            dragBeginCursorX = Int32(cursor.x)
            dragBeginCursorY = Int32(cursor.y)
            startDragWindow = true
            gc.oldMasterMfactPer = gc.masterMfactPer
            gc.oldMasterInnerPer = gc.masterInnerPer
            gc.oldStackInnerPer = gc.stackInnerPer
            gc.cursorInUpperHalf = cursor.y < CGFloat(Int32(gc.geom.minY) + Int32(gc.geom.height) / 2)
            gc.cursorInLeftHalf = cursor.x < CGFloat(Int32(gc.geom.minX) + Int32(gc.geom.width) / 2)
            gc.dragBeginGeom = gc.geom
        } else {
            if isdrag {
                offsetx = Int32(cursor.x - CGFloat(dragBeginCursorX))
                offsety = Int32(cursor.y - CGFloat(dragBeginCursorY))
            } else {
                gc.oldMasterMfactPer = gc.masterMfactPer
                gc.oldMasterInnerPer = gc.masterInnerPer
                gc.oldStackInnerPer = gc.stackInnerPer
                gc.dragBeginGeom = gc.geom
                gc.cursorInUpperHalf = true
                gc.cursorInLeftHalf = false
            }

            let width = Double(Int32(gc.dragBeginGeom.width)), height = Double(Int32(gc.dragBeginGeom.height))
            if gc.ismaster {
                deltaX = Float(Double(Float(offsetx)) * Double(gc.oldMasterMfactPer) / width)
                deltaY = Float(Double(Float(offsety)) * Double(gc.oldMasterInnerPer) / height)
            } else {
                deltaX = Float(Double(Float(offsetx)) * (1 - Double(gc.oldMasterMfactPer)) / width)
                deltaY = Float(Double(Float(offsety)) * Double(gc.oldStackInnerPer) / height)
            }

            let movingUp: Bool, movingDown: Bool
            if !isdrag {
                movingUp = offsety < 0
                movingDown = offsety > 0
            } else {
                movingUp = cursor.y < CGFloat(dragBeginCursorY)
                movingDown = cursor.y > CGFloat(dragBeginCursorY)
            }

            if gc.ismaster && prev == nil {
                if movingUp {
                    deltaY = -abs(deltaY)
                } else {
                    deltaY = abs(deltaY)
                }
            } else if gc.ismaster, let next, !next.ismaster {
                if movingUp {
                    deltaY = abs(deltaY)
                } else {
                    deltaY = -abs(deltaY)
                }
            } else if !gc.ismaster, let prev, prev.ismaster {
                if movingUp {
                    deltaY = -abs(deltaY)
                } else {
                    deltaY = abs(deltaY)
                }
            } else if !gc.ismaster && next == nil {
                if movingUp {
                    deltaY = abs(deltaY)
                } else {
                    deltaY = -abs(deltaY)
                }
            } else if type == .centerTile && !gc.ismaster && nextnext == nil {
                if movingUp {
                    deltaY = abs(deltaY)
                } else {
                    deltaY = -abs(deltaY)
                }
            } else if type == .centerTile && !gc.ismaster, let prevprev, prevprev.ismaster {
                if movingUp {
                    deltaY = -abs(deltaY)
                } else {
                    deltaY = abs(deltaY)
                }
            } else if (gc.cursorInUpperHalf && movingUp) || (!gc.cursorInUpperHalf && movingDown) {
                deltaY = abs(deltaY) * 2
            } else {
                deltaY = -abs(deltaY) * 2
            }

            if !gc.ismaster && gc.isleftstack && type == .centerTile {
                deltaX = deltaX * -1.0
            }
            if gc.ismaster && type == .centerTile && gc.cursorInLeftHalf {
                deltaX = deltaX * -1.0
            }
            if gc.ismaster && type == .centerTile {
                deltaX = deltaX * 2
            }
            if type == .rightTile {
                deltaX = deltaX * -1.0
            }

            var newMasterMfactPer = Float(Double(gc.oldMasterMfactPer) + Double(deltaX))
            var newMasterInnerPer = Float(Double(gc.oldMasterInnerPer) + Double(deltaY))
            var newStackInnerPer = Float(Double(gc.oldStackInnerPer) + Double(deltaY))

            newMasterMfactPer = max(0.1, min(0.9, newMasterMfactPer))
            newMasterInnerPer = max(0.1, min(0.9, newMasterInnerPer))
            newStackInnerPer = max(0.1, min(0.9, newStackInnerPer))

            // Scales other windows in the same group in real time, keeping the
            // group sum at 1; otherwise the added ratio is not the ratio after
            // arrangement.
            if isdrag {
                if gc.ismaster {
                    /* Master window group: adjusts master_inner_per of all master
                     * windows. */
                    let curOtherSum = Float(1.0 - Double(gc.masterInnerPer))
                    let newOtherSum: Float = 1.0 - newMasterInnerPer
                    if curOtherSum > 0.001 {
                        let scale = newOtherSum / curOtherSum
                        for tc in clients {
                            if VISIBLEON(tc, m) && ISTILED(tc) && tc.ismaster && tc !== gc {
                                tc.masterInnerPer *= CGFloat(scale)
                            }
                        }
                    }
                } else {
                    /* Stack window group: handled separately per layout type. */
                    if type == .centerTile {
                        /* Scales only the stack_inner_per of same-side stack
                         * windows. */
                        let curOtherSum = Float(1.0 - Double(gc.stackInnerPer))
                        let newOtherSum: Float = 1.0 - newStackInnerPer
                        if curOtherSum > 0.001 {
                            let scale = newOtherSum / curOtherSum
                            for tc in clients {
                                if VISIBLEON(tc, m) && ISTILED(tc) && !tc.ismaster && tc !== gc
                                    && tc.isleftstack == gc.isleftstack {
                                    tc.stackInnerPer *= CGFloat(scale)
                                }
                            }
                        }
                    } else {
                        /* TILE / RIGHT_TILE / DECK: all stack windows share one
                         * ratio group. */
                        let curOtherSum = Float(1.0 - Double(gc.stackInnerPer))
                        let newOtherSum: Float = 1.0 - newStackInnerPer
                        if curOtherSum > 0.001 {
                            let scale = newOtherSum / curOtherSum
                            for tc in clients {
                                if VISIBLEON(tc, m) && ISTILED(tc) && !tc.ismaster && tc !== gc {
                                    tc.stackInnerPer *= CGFloat(scale)
                                }
                            }
                        }
                    }
                }
            } else {
                /* Keyboard stepping. */
                for tc in clients {
                    if !VISIBLEON(tc, m) || !ISTILED(tc) {
                        continue
                    }
                    if tc !== gc {
                        if !tc.ismaster && newStackInnerPer != 1.0 && gc.oldStackInnerPer != 1.0
                            && (type != .centerTile || !(gc.isleftstack != tc.isleftstack)) {
                            tc.stackInnerPer = CGFloat(Double(1 - newStackInnerPer)
                                / (1 - Double(gc.oldStackInnerPer)) * Double(tc.stackInnerPer))
                        }
                        if tc.ismaster && newMasterInnerPer != 1.0 && gc.oldMasterInnerPer != 1.0 {
                            tc.masterInnerPer = CGFloat(Double(1.0 - newMasterInnerPer)
                                / (1.0 - Double(gc.oldMasterInnerPer)) * Double(tc.masterInnerPer))
                        }
                    }
                }
            }

            /* Applies the new ratio to the grabbed window itself. */
            gc.masterInnerPer = CGFloat(newMasterInnerPer)
            gc.stackInnerPer = CGFloat(newStackInnerPer)

            /* Broadcasts master_mfact_per to all tiled windows. */
            for tc in clients {
                if VISIBLEON(tc, m) && ISTILED(tc) {
                    tc.masterMfactPer = CGFloat(newMasterMfactPer)
                }
            }

            persistTileSizeWeights(m)

            arrange(m, false, false)
        }
    }

    func resizeTileMasterVertical(_ gc: Client, _ isdrag: Bool, _ offsetx: Int32, _ offsety: Int32,
                                  _ type: LayoutKind) {
        var offsetx = offsetx, offsety = offsety
        var deltaX: Float, deltaY: Float
        var next: Client?
        var prev: Client?
        guard let m = gc.mon, let gi = clients.firstIndex(where: { $0 === gc }) else { return }   // not in mango: gc->mon is set and gc is in server.clients here
        let cursor = system.pointer   // not in mango: the port's cursor

        /* Finds next. */
        for tc in clients[(gi + 1)...] {
            if VISIBLEON(tc, m) && ISTILED(tc) {
                next = tc
                break
            }
        }

        /* Finds prev. */
        for tc in clients[..<gi].reversed() {
            if VISIBLEON(tc, m) && ISTILED(tc) {
                prev = tc
                break
            }
        }

        if !startDragWindow && isdrag {
            dragBeginCursorX = Int32(cursor.x)
            dragBeginCursorY = Int32(cursor.y)
            startDragWindow = true
            gc.oldMasterMfactPer = gc.masterMfactPer
            gc.oldMasterInnerPer = gc.masterInnerPer
            gc.oldStackInnerPer = gc.stackInnerPer
            gc.cursorInUpperHalf = cursor.y < CGFloat(Int32(gc.geom.minY) + Int32(gc.geom.height) / 2)
            gc.cursorInLeftHalf = cursor.x < CGFloat(Int32(gc.geom.minX) + Int32(gc.geom.width) / 2)
            gc.dragBeginGeom = gc.geom
        } else {
            if isdrag {
                offsetx = Int32(cursor.x - CGFloat(dragBeginCursorX))
                offsety = Int32(cursor.y - CGFloat(dragBeginCursorY))
            } else {
                gc.oldMasterMfactPer = gc.masterMfactPer
                gc.oldMasterInnerPer = gc.masterInnerPer
                gc.oldStackInnerPer = gc.stackInnerPer
                gc.dragBeginGeom = gc.geom
                gc.cursorInUpperHalf = true
                gc.cursorInLeftHalf = false
            }

            let width = Double(Int32(gc.dragBeginGeom.width)), height = Double(Int32(gc.dragBeginGeom.height))
            if gc.ismaster {
                deltaX = Float(Double(Float(offsetx)) * Double(gc.oldMasterInnerPer) / width)
                deltaY = Float(Double(Float(offsety)) * Double(gc.oldMasterMfactPer) / height)
            } else {
                deltaX = Float(Double(Float(offsetx)) * Double(gc.oldStackInnerPer) / width)
                deltaY = Float(Double(Float(offsety)) * (1 - Double(gc.oldMasterMfactPer)) / height)
            }

            let movingLeft: Bool, movingRight: Bool
            if !isdrag {
                movingLeft = offsetx < 0
                movingRight = offsetx > 0
            } else {
                movingLeft = cursor.x < CGFloat(dragBeginCursorX)
                movingRight = cursor.x > CGFloat(dragBeginCursorX)
            }

            if gc.ismaster && prev == nil {
                if movingLeft {
                    deltaX = -abs(deltaX)
                } else {
                    deltaX = abs(deltaX)
                }
            } else if gc.ismaster, let next, !next.ismaster {
                if movingLeft {
                    deltaX = abs(deltaX)
                } else {
                    deltaX = -abs(deltaX)
                }
            } else if !gc.ismaster, let prev, prev.ismaster {
                if movingLeft {
                    deltaX = -abs(deltaX)
                } else {
                    deltaX = abs(deltaX)
                }
            } else if !gc.ismaster && next == nil {
                if movingLeft {
                    deltaX = abs(deltaX)
                } else {
                    deltaX = -abs(deltaX)
                }
            } else if (gc.cursorInLeftHalf && movingLeft) || (!gc.cursorInLeftHalf && movingRight) {
                deltaX = abs(deltaX) * 2
            } else {
                deltaX = -abs(deltaX) * 2
            }

            var newMasterMfactPer = Float(Double(gc.oldMasterMfactPer) + Double(deltaY))
            var newMasterInnerPer = Float(Double(gc.oldMasterInnerPer) + Double(deltaX))
            var newStackInnerPer = Float(Double(gc.oldStackInnerPer) + Double(deltaX))

            newMasterMfactPer = max(0.1, min(0.9, newMasterMfactPer))
            newMasterInnerPer = max(0.1, min(0.9, newMasterInnerPer))
            newStackInnerPer = max(0.1, min(0.9, newStackInnerPer))

            // Scales other windows in the same group in real time, keeping the
            // group sum at 1; otherwise the added ratio is not the ratio after
            // arrangement.

            if isdrag {
                if gc.ismaster {
                    let curOtherSum = Float(1.0 - Double(gc.masterInnerPer))
                    let newOtherSum: Float = 1.0 - newMasterInnerPer
                    if curOtherSum > 0.001 {
                        let scale = newOtherSum / curOtherSum
                        for tc in clients {
                            if VISIBLEON(tc, m) && ISTILED(tc) && tc.ismaster && tc !== gc {
                                tc.masterInnerPer *= CGFloat(scale)
                            }
                        }
                    }
                } else {
                    /* All stack windows (vertical layouts have no left/right
                     * distinction). */
                    let curOtherSum = Float(1.0 - Double(gc.stackInnerPer))
                    let newOtherSum: Float = 1.0 - newStackInnerPer
                    if curOtherSum > 0.001 {
                        let scale = newOtherSum / curOtherSum
                        for tc in clients {
                            if VISIBLEON(tc, m) && ISTILED(tc) && !tc.ismaster && tc !== gc {
                                tc.stackInnerPer *= CGFloat(scale)
                            }
                        }
                    }
                }
            } else {
                /* Keyboard stepping. */
                for tc in clients {
                    if !VISIBLEON(tc, m) || !ISTILED(tc) {
                        continue
                    }
                    if tc !== gc {
                        if !tc.ismaster && newStackInnerPer != 1.0 && gc.oldStackInnerPer != 1.0 {
                            tc.stackInnerPer = CGFloat(Double(1 - newStackInnerPer)
                                / (1 - Double(gc.oldStackInnerPer)) * Double(tc.stackInnerPer))
                        }
                        if tc.ismaster && newMasterInnerPer != 1.0 && gc.oldMasterInnerPer != 1.0 {
                            tc.masterInnerPer = CGFloat(Double(1.0 - newMasterInnerPer)
                                / (1.0 - Double(gc.oldMasterInnerPer)) * Double(tc.masterInnerPer))
                        }
                    }
                }
            }

            gc.masterInnerPer = CGFloat(newMasterInnerPer)
            gc.stackInnerPer = CGFloat(newStackInnerPer)

            /* Broadcasts master_mfact_per. */
            for tc in clients {
                if VISIBLEON(tc, m) && ISTILED(tc) {
                    tc.masterMfactPer = CGFloat(newMasterMfactPer)
                }
            }

            persistTileSizeWeights(m)

            arrange(m, false, false)
        }
    }

    func resizeTileDwindle(_ gc: Client, _ isdrag: Bool, _ offsetx: Int32, _ offsety: Int32, _ isvertical: Bool) {
        guard let m = gc.mon else { return }   // not in mango: gc->mon is set here

        if !isdrag {
            dwindleResizeClientStep(m, gc, offsetx, offsety)
            return
        }

        dwindleResizeClient(m, gc)
    }

    func resizeTileGridFair(_ gc: Client, _ isdrag: Bool, _ offsetx: Int32, _ offsety: Int32) {
        var offsetx = offsetx, offsety = offsety
        if gc.isfullscreen || gc.ismaximizescreen {
            return
        }
        guard let m = gc.mon else { return }   // not in mango: gc->mon is set here
        if m.isoverview {
            return
        }

        if m.visibleTilingClients <= 1 {
            return
        }

        // Gets the current layout ID.
        let currentLayout = m.pertag.ltidxs[getMonCurtag(m)]
        let cursor = system.pointer   // not in mango: the port's cursor

        if !startDragWindow && isdrag {
            dragBeginCursorX = Int32(cursor.x)
            dragBeginCursorY = Int32(cursor.y)
            startDragWindow = true

            for c in clients {
                c.oldGridColPer = (c.gridColPer > 0.0) ? c.gridColPer : 1.0
                c.oldGridRowPer = (c.gridRowPer > 0.0) ? c.gridRowPer : 1.0
            }

            gc.oldGridColPer = gc.gridColPer
            gc.oldGridRowPer = gc.gridRowPer

            gc.cursorInLeftHalf = cursor.x < CGFloat(Int32(gc.geom.minX) + Int32(gc.geom.width) / 2)
            gc.cursorInUpperHalf = cursor.y < CGFloat(Int32(gc.geom.minY) + Int32(gc.geom.height) / 2)
            gc.dragBeginGeom = gc.geom
        } else {
            if isdrag {
                offsetx = Int32(cursor.x - CGFloat(dragBeginCursorX))
                offsety = Int32(cursor.y - CGFloat(dragBeginCursorY))
            } else {
                gc.dragBeginGeom = gc.geom
                for c in clients {
                    c.oldGridColPer = (c.gridColPer > 0.0) ? c.gridColPer : 1.0
                    c.oldGridRowPer = (c.gridRowPer > 0.0) ? c.gridRowPer : 1.0
                }
                gc.cursorInUpperHalf = false
                gc.cursorInLeftHalf = false
            }

            // Computes the ratio delta based on screen resolution.
            let deltaX = Float(offsetx) * Float(gc.oldGridColPer) / Float(Int32(gc.dragBeginGeom.width))
            let deltaY = Float(offsety) * Float(gc.oldGridRowPer) / Float(Int32(gc.dragBeginGeom.height))

            var adjCIdx = gc.gridColIdx
            var adjRIdx = gc.gridRowIdx
            var signX: Float = 1.0, signY: Float = 1.0

            if isdrag {
                if gc.cursorInLeftHalf {
                    adjCIdx -= 1
                    signX = -1.0
                } else {
                    adjCIdx += 1
                    signX = 1.0
                }

                if gc.cursorInUpperHalf {
                    adjRIdx -= 1
                    signY = -1.0
                } else {
                    adjRIdx += 1
                    signY = 1.0
                }
            }
            // Keyboard hotkey logic unchanged.
            var maxCol = -1, maxRow = -1, minCol = Int(Int32.max), minRow = Int(Int32.max)
            for tmp in clients {
                if tmp.mon !== m || !VISIBLEON(tmp, m) || !ISTILED(tmp) {
                    continue
                }
                if tmp.gridColIdx > maxCol {
                    maxCol = tmp.gridColIdx
                }
                if tmp.gridRowIdx > maxRow {
                    maxRow = tmp.gridRowIdx
                }
                if tmp.gridColIdx < minCol {
                    minCol = tmp.gridColIdx
                }
                if tmp.gridRowIdx < minRow {
                    minRow = tmp.gridRowIdx
                }
            }

            // not in mango: for the keyboard only; mango overwrites the drag's neighbour with it
            // (a mango bug, docs/afvigelser.md §6)
            if !isdrag {
                adjCIdx = gc.gridColIdx + 1
                adjRIdx = gc.gridRowIdx + 1
                signX = 1.0
                signY = 1.0

                if gc.gridColIdx == maxCol {
                    adjCIdx = gc.gridColIdx - 1
                    signX = -1.0
                }
                if gc.gridRowIdx == maxRow {
                    adjRIdx = gc.gridRowIdx - 1
                    signY = -1.0
                }
                if gc.gridColIdx == minCol {
                    adjCIdx = gc.gridColIdx + 1
                    signX = 1.0
                }
                if gc.gridRowIdx == minRow {
                    adjRIdx = gc.gridRowIdx + 1
                    signY = 1.0
                }
            }

            let dx = deltaX * signX
            let dy = deltaY * signY

            let myOldCol = Float(gc.oldGridColPer)
            let myOldRow = Float(gc.oldGridRowPer)
            var adjOldCol: Float = -1.0, adjOldRow: Float = -1.0

            for c in clients {
                if c.mon !== m || !VISIBLEON(c, m) || !ISTILED(c) {
                    continue
                }
                if c.gridColIdx == adjCIdx && adjOldCol < 0 {
                    adjOldCol = Float(c.oldGridColPer)
                }
                if c.gridRowIdx == adjRIdx && adjOldRow < 0 {
                    adjOldRow = Float(c.oldGridRowPer)
                }
            }

            // Applies the column-width adjustment.
            if adjOldCol > 0.0 {
                var dxClamped = dx
                if myOldCol + dxClamped < 0.1 {
                    dxClamped = 0.1 - myOldCol
                }
                if adjOldCol - dxClamped < 0.1 {
                    dxClamped = adjOldCol - 0.1
                }

                var newMyCol = myOldCol + dxClamped
                var newAdjCol = adjOldCol - dxClamped

                // Handles column boundaries forced to stay locked at 1.0f where the
                // head is a misplaced window.
                if currentLayout == .verticalFair {
                    let nTiling = m.visibleTilingClients
                    var lRows: Int32 = 0
                    while lRows <= nTiling {
                        if lRows * lRows >= nTiling {
                            break
                        }
                        lRows += 1
                    }
                    let baseCols = Int(nTiling / lRows)
                    // When the adjusted boundary is at an asymmetric locked column
                    // (e.g. between col 0 and col 1 with 3 windows).
                    if (gc.gridColIdx == baseCols - 1 && adjCIdx == baseCols)
                        || (gc.gridColIdx == baseCols && adjCIdx == baseCols - 1) {

                        var pCol = (gc.gridColIdx == baseCols - 1)
                            ? (myOldCol + dx) / (myOldCol + adjOldCol)
                            : (adjOldCol - dx) / (myOldCol + adjOldCol)
                        if pCol < 0.01 {
                            pCol = 0.01
                        }
                        if pCol > 0.99 {
                            pCol = 0.99
                        }

                        // Backs out the non-linear real weight value.
                        var newRVarPer = pCol / (1.0 - pCol)
                        if newRVarPer < 0.1 {
                            newRVarPer = 0.1
                        }
                        if newRVarPer > 10.0 {
                            newRVarPer = 10.0
                        }

                        if gc.gridColIdx == baseCols - 1 {
                            newMyCol = newRVarPer
                            newAdjCol = 1.0
                        } else {
                            newMyCol = 1.0
                            newAdjCol = newRVarPer
                        }
                    }
                }

                for c in clients {
                    if c.mon !== m || !VISIBLEON(c, m) || !ISTILED(c) {
                        continue
                    }
                    if c.gridColIdx == gc.gridColIdx {
                        c.gridColPer = CGFloat(newMyCol)
                    }
                    if c.gridColIdx == adjCIdx {
                        c.gridColPer = CGFloat(newAdjCol)
                    }
                }

                for c in clients {
                    if c.mon !== m || !VISIBLEON(c, m) || !ISTILED(c) {
                        continue
                    }
                    if c.gridRowIdx == 0 {
                        if c.gridColIdx == gc.gridColIdx {
                            c.gridColPer = CGFloat(newMyCol)
                        } else if c.gridColIdx == adjCIdx {
                            c.gridColPer = CGFloat(newAdjCol)
                        }
                    }
                }
            }

            // Applies the row-height adjustment.
            if adjOldRow > 0.0 {
                var dyClamped = dy
                if myOldRow + dyClamped < 0.1 {
                    dyClamped = 0.1 - myOldRow
                }
                if adjOldRow - dyClamped < 0.1 {
                    dyClamped = adjOldRow - 0.1
                }

                var newMyRow = myOldRow + dyClamped
                var newAdjRow = adjOldRow - dyClamped

                // Handles row boundaries forced to stay locked at 1.0f where the
                // head is a misplaced window.
                if currentLayout == .fair {
                    let nTiling = m.visibleTilingClients
                    var lCols: Int32 = 0
                    while lCols <= nTiling {
                        if lCols * lCols >= nTiling {
                            break
                        }
                        lCols += 1
                    }
                    let baseRows = Int(nTiling / lCols)
                    // When the adjusted boundary is at an asymmetric locked row
                    // (e.g. between row 0 and row 1 with 3 windows).
                    if (gc.gridRowIdx == baseRows - 1 && adjRIdx == baseRows)
                        || (gc.gridRowIdx == baseRows && adjRIdx == baseRows - 1) {

                        var pRow = (gc.gridRowIdx == baseRows - 1)
                            ? (myOldRow + dy) / (myOldRow + adjOldRow)
                            : (adjOldRow - dy) / (myOldRow + adjOldRow)
                        if pRow < 0.01 {
                            pRow = 0.01
                        }
                        if pRow > 0.99 {
                            pRow = 0.99
                        }

                        // Backs out the non-linear real weight value.
                        var newRVarPer = pRow / (1.0 - pRow)
                        if newRVarPer < 0.1 {
                            newRVarPer = 0.1
                        }
                        if newRVarPer > 10.0 {
                            newRVarPer = 10.0
                        }

                        if gc.gridRowIdx == baseRows - 1 {
                            newMyRow = newRVarPer
                            newAdjRow = 1.0
                        } else {
                            newMyRow = 1.0
                            newAdjRow = newRVarPer
                        }
                    }
                }

                for c in clients {
                    if c.mon !== m || !VISIBLEON(c, m) || !ISTILED(c) {
                        continue
                    }
                    if c.gridRowIdx == gc.gridRowIdx {
                        c.gridRowPer = CGFloat(newMyRow)
                    }
                    if c.gridRowIdx == adjRIdx {
                        c.gridRowPer = CGFloat(newAdjRow)
                    }
                }

                for c in clients {
                    if c.mon !== m || !VISIBLEON(c, m) || !ISTILED(c) {
                        continue
                    }
                    if c.gridColIdx == 0 {
                        if c.gridRowIdx == gc.gridRowIdx {
                            c.gridRowPer = CGFloat(newMyRow)
                        } else if c.gridRowIdx == adjRIdx {
                            c.gridRowPer = CGFloat(newAdjRow)
                        }
                    }
                }
            }

            arrange(m, false, false)
        }
    }

    func resizeTileScroller(_ gc: Client, _ isdrag: Bool, _ offsetx: Int32, _ offsety: Int32, _ isvertical: Bool) {
        var offsetx = offsetx, offsety = offsety

        if gc.isfullscreen || gc.ismaximizescreen {
            return
        }
        guard let m = gc.mon else { return }
        if m.isoverview {
            return
        }

        let tag = getClientTagIdx(gc)
        guard let st = m.pertag.scrollerState[tag] else { return }

        guard let curnode = findScrollerNode(st, gc) else { return }

        var headnode = curnode
        while let p = headnode.prevInStack {
            headnode = p
        }

        let stackHeadClient = headnode.client
        let cursor = system.pointer   // not in mango: the port's cursor

        var deltaX: Float, deltaY: Float
        var newScrollerProportion: Float
        var newStackProportion: Float

        if !startDragWindow && isdrag {
            dragBeginCursorX = Int32(cursor.x)
            dragBeginCursorY = Int32(cursor.y)
            startDragWindow = true

            headnode.client.oldScrollerPproportion = Double(headnode.scrollerProportion)
            gc.scrollerOldStackProportion = curnode.scrollerStackProportion

            gc.cursorInLeftHalf = cursor.x < CGFloat(Int32(gc.geom.minX) + Int32(gc.geom.width) / 2)
            gc.cursorInUpperHalf = cursor.y < CGFloat(Int32(gc.geom.minY) + Int32(gc.geom.height) / 2)
            gc.dragBeginGeom = gc.geom
        } else {
            if isdrag {
                offsetx = Int32(cursor.x - CGFloat(dragBeginCursorX))
                offsety = Int32(cursor.y - CGFloat(dragBeginCursorY))
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
                deltaY = Float(Double(Float(offsety)) * headnode.client.oldScrollerPproportion
                    / Double(Int32(gc.dragBeginGeom.height)))
                deltaX = Float(offsetx) * gc.scrollerOldStackProportion / Float(Int32(gc.dragBeginGeom.width))
            } else {
                deltaX = Float(Double(Float(offsetx)) * headnode.client.oldScrollerPproportion
                    / Double(Int32(gc.dragBeginGeom.width)))
                deltaY = Float(offsety) * gc.scrollerOldStackProportion / Float(Int32(gc.dragBeginGeom.height))
            }

            let movingUp: Bool, movingDown: Bool, movingLeft: Bool, movingRight: Bool
            if !isdrag {
                movingUp = offsety < 0
                movingDown = offsety > 0
                movingLeft = offsetx < 0
                movingRight = offsetx > 0
            } else {
                movingUp = cursor.y < CGFloat(dragBeginCursorY)
                movingDown = cursor.y > CGFloat(dragBeginCursorY)
                movingLeft = cursor.x < CGFloat(dragBeginCursorX)
                movingRight = cursor.x > CGFloat(dragBeginCursorX)
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
                    if movingRight {
                        deltaX = -abs(deltaX)
                    } else {
                        deltaX = abs(deltaX)
                    }
                }
                if curnode.prevInStack == nil && curnode.nextInStack != nil && isdrag {
                    if movingLeft {
                        deltaX = -abs(deltaX)
                    } else {
                        deltaX = abs(deltaX)
                    }
                }
                if isdrag {
                    if movingUp {
                        deltaY = -abs(deltaY)
                    } else {
                        deltaY = abs(deltaY)
                    }
                }
            } else {
                if curnode.nextInStack == nil && curnode.prevInStack != nil && !isdrag {
                    deltaY = deltaY * -1.0
                }
                if curnode.nextInStack == nil && curnode.prevInStack != nil && isdrag {
                    if movingDown {
                        deltaY = -abs(deltaY)
                    } else {
                        deltaY = abs(deltaY)
                    }
                }
                if curnode.prevInStack == nil && curnode.nextInStack != nil && isdrag {
                    if movingUp {
                        deltaY = -abs(deltaY)
                    } else {
                        deltaY = abs(deltaY)
                    }
                }
                if isdrag {
                    if movingLeft {
                        deltaX = -abs(deltaX)
                    } else {
                        deltaX = abs(deltaX)
                    }
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
                        if n !== curnode {
                            n.scrollerStackProportion *= scale
                        }
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

    func resizeTileClient(_ gc: Client, _ isdrag: Bool, _ offsetx: Int32, _ offsety: Int32) {
        if gc.isfullscreen || gc.ismaximizescreen {
            return
        }
        guard let m = gc.mon else { return }

        if m.isoverview {
            return
        }

        /* Coalesce keyboard repeats and pointer motion to once per output frame. */
        if m.lastResizeFrame == m.frameSerial {
            return
        }
        m.lastResizeFrame = m.frameSerial

        let currentLayout = m.pertag.ltidxs[getClientTagIdx(gc)]
        if currentLayout == .tile || currentLayout == .deck || currentLayout == .centerTile
            || currentLayout == .rightTile {
            resizeTileMasterHorizontal(gc, isdrag, offsetx, offsety, currentLayout)
        } else if currentLayout == .verticalTile || currentLayout == .verticalDeck {
            resizeTileMasterVertical(gc, isdrag, offsetx, offsety, currentLayout)
        } else if currentLayout == .scroller {
            resizeTileScroller(gc, isdrag, offsetx, offsety, false)
        } else if currentLayout == .verticalScroller {
            resizeTileScroller(gc, isdrag, offsetx, offsety, true)
        } else if currentLayout == .dwindle {
            resizeTileDwindle(gc, isdrag, offsetx, offsety, true)
        } else if currentLayout == .grid || currentLayout == .verticalGrid || currentLayout == .fair
                    || currentLayout == .verticalFair {
            resizeTileGridFair(gc, isdrag, offsetx, offsety)
        }
    }

    /* If there are no calculation omissions,
    these two functions will never be triggered.
    Just in case to facilitate the final investigation*/

    func checkSizePerValid(_ c: Client) {
        if c.ismaster {
            assert(c.masterInnerPer > 0.0 && c.masterInnerPer <= 1.0)
        } else {
            assert(c.stackInnerPer > 0.0 && c.stackInnerPer <= 1.0)
        }
    }

    func specialKeepBgClient(_ m: Monitor, _ c: Client) -> Bool {
        isSpecialActive(m) && !c.isminimized
            && ((m.pertag.prevtag > 0 && c.tags & (1 << (m.pertag.prevtag - 1)) != 0)
                || c.tags & (m.tagset[m.seltags ^ 1] & ~TAG0_MASK) != 0)
    }

    func resetSizePerMon(_ m: Monitor, _ totalLeftStackWeight: CGFloat, _ totalRightStackWeight: CGFloat,
                         _ totalStackWeight: CGFloat, _ totalMasterWeight: CGFloat,
                         _ masterNum: Int32, _ stackNum: Int32) {
        var i = 0
        let tag = getMonCurtag(m)
        let nmasters = Int(m.pertag.nmasters[tag])
        let centered = m.pertag.ltidxs[tag] == .centerTile

        for c in clients {
            if !VISIBLEON(c, m) || !ISFAKETILED(c) {
                continue
            }

            if totalMasterWeight > 0.0 && i < nmasters {
                c.ismaster = true
                c.masterInnerPer = c.masterSizeWeight / totalMasterWeight

                let stackSide = centered ? totalLeftStackWeight + totalRightStackWeight : totalStackWeight
                c.stackInnerPer = stackSide > 0.0 ? c.stackSizeWeight / (stackSide + c.stackSizeWeight) : 1.0
            } else {
                c.ismaster = false
                c.masterInnerPer = totalMasterWeight > 0.0
                    ? c.masterSizeWeight / (totalMasterWeight + c.masterSizeWeight)
                    : (masterNum > 0 ? CGFloat(1.0 / Float(masterNum)) : 1.0)

                if centered {
                    let side = c.isleftstack ? totalLeftStackWeight : totalRightStackWeight
                    c.stackInnerPer = side > 0.0 ? c.stackSizeWeight / side : 1.0
                } else {
                    c.stackInnerPer = totalStackWeight > 0.0
                        ? c.stackSizeWeight / totalStackWeight
                        : (stackNum > 0 ? CGFloat(1.0 / Float(stackNum)) : 1.0)
                }
            }
            i += 1

            checkSizePerValid(c)
        }
    }

    func preCalculateBeforeArrange(_ m: Monitor, _ wantAnimation: Bool, _ fromView: Bool, _ onlyCalculate: Bool) {
        var totalStackWeight: CGFloat = 0
        var totalMasterWeight: CGFloat = 0
        var totalRightStackWeight: CGFloat = 0
        var totalLeftStackWeight: CGFloat = 0
        var i: Int32 = 0
        var nmasters: Int32 = 0
        var stackIndex: Int32 = 0
        var masterNum: Int32 = 0
        var stackNum: Int32 = 0

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

                if !c.isunglobal {
                    m.visibleClients += 1
                }

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

        nmasters = m.pertag.nmasters[getMonCurtag(m)]

        for c in clients {
            if c.iskilling {
                continue
            }

            if c.mon === m {
                if VISIBLEON(c, m) {
                    if ISFAKETILED(c) {
                        if c.masterSizeWeight <= 0.0 {
                            c.masterSizeWeight = 1.0
                        }
                        if c.stackSizeWeight <= 0.0 {
                            c.stackSizeWeight = 1.0
                        }

                        if i < nmasters {
                            masterNum += 1
                            totalMasterWeight += c.masterSizeWeight
                        } else {
                            stackNum += 1
                            totalStackWeight += c.stackSizeWeight
                            stackIndex = i - nmasters
                            if (stackIndex % 2 != 0) != (m.visibleTilingClients % 2 == 0) {
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

        resetSizePerMon(m, totalLeftStackWeight, totalRightStackWeight, totalStackWeight, totalMasterWeight,
                        masterNum, stackNum)

        specialUpdateDim(m)
    }

    // remap tags through map; unmapped tags stay as-is.
    func tagRemapMask(_ tags: UInt32, _ map: [UInt32]) -> UInt32 {
        var out = tags & ~tagmask

        var i: UInt32 = 1
        while i <= UInt32(config.tagNum) {
            if tags & (1 << (i - 1)) != 0 {
                out |= map[Int(i)] != 0 ? (1 << (map[Int(i)] - 1)) : (1 << (i - 1))
            }
            i += 1
        }
        return out
    }

    // reset a pertag slot to its tagrule state.
    func tagGatherResetSlot(_ m: Monitor, _ tag: UInt32) {
        tagSlotSetDefaults(m, tag)
        m.pertag.noHide[tag] = false
        m.pertag.noRenderBorder[tag] = false
        m.pertag.openAsFloating[tag] = false
        m.pertag.dwindleRoot[tag] = nil
        m.pertag.scrollerState[tag] = nil

        for tr in config.tagRules {
            if tagRuleMatchesMonitor(tr, m) && (tr.id == nil || tr.id == Int(tag)) {
                tagRuleApplyToSlot(m, tr, tag)
            }
        }
        m.pertag.ltidxs[tag] = m.pertag.configLtidxs[tag]
    }

    // move pertag state from src to dst, then reset src.
    func tagGatherMovePertag(_ m: Monitor, _ dst: UInt32, _ src: UInt32) {
        m.pertag.nmasters[dst] = m.pertag.nmasters[src]
        m.pertag.mfacts[dst] = m.pertag.mfacts[src]
        m.pertag.noHide[dst] = m.pertag.noHide[src]
        m.pertag.noRenderBorder[dst] = m.pertag.noRenderBorder[src]
        m.pertag.openAsFloating[dst] = m.pertag.openAsFloating[src]
        m.pertag.scrollerDefaultProportion[dst] = m.pertag.scrollerDefaultProportion[src]
        m.pertag.scrollerDefaultProportionSingle[dst] = m.pertag.scrollerDefaultProportionSingle[src]
        m.pertag.scrollerIgnoreProportionSingle[dst] = m.pertag.scrollerIgnoreProportionSingle[src]
        m.pertag.dwindleRoot[dst] = m.pertag.dwindleRoot[src]
        m.pertag.configLtidxs[dst] = m.pertag.configLtidxs[src]
        m.pertag.ltidxs[dst] = m.pertag.ltidxs[src]
        m.pertag.scrollerState[dst] = m.pertag.scrollerState[src]
        tagGatherResetSlot(m, src)
    }

    // Compact occupied tags on this monitor to 1..k (e.g. 1,3,9 -> 1,2,3).
    func tagGatherApply(_ m: Monitor) {
        var occupied: UInt32 = 0
        var map = [UInt32](repeating: 0, count: Int(tag_num_MAX) + 1)
        var i: UInt32, next: UInt32 = 1, k: UInt32
        var changed = false

        // not in mango: no iscleanuping; the port's monitors are not arranged while they are cleaned up

        // collect occupied tags on this monitor.
        for c in clients {
            if c.mon === m && !c.iskilling && (c.tags & TAG0_MASK) == 0 {
                occupied |= c.tags & tagmask
            }
        }
        // the current view counts as occupied even when empty.
        occupied |= m.tagset[m.seltags] & tagmask

        // old->new mapping and detect gaps.
        i = 1
        while i <= UInt32(config.tagNum) {
            if occupied & (1 << (i - 1)) != 0 {
                map[Int(i)] = next
                next += 1
                if map[Int(i)] != i {
                    changed = true
                }
            } else {
                map[Int(i)] = 0
            }
            i += 1
        }

        if !changed {
            return
        }

        // remap client tags.
        for c in clients {
            if c.mon !== m || c.iskilling || (c.tags & TAG0_MASK) != 0 {
                continue
            }
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
        i = 1
        while i <= UInt32(config.tagNum) {
            if map[Int(i)] != 0 && map[Int(i)] != i {
                tagGatherMovePertag(m, map[Int(i)], i)
            }
            i += 1
        }

        // reset trailing empty slots.
        k = next - 1
        i = k + 1
        while i <= UInt32(config.tagNum) {
            tagGatherResetSlot(m, i)
            i += 1
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

        // not in mango: no iscleanuping or wlr_output->enabled; the port's monitors are enabled

        if m.sel == nil {
            m.sel = clientFocusTop(m)?.id
        }

        if specialHandleEmptyView(m, fromView) {
            return
        }

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

        if m.isoverview {
            overviewlayout.arrange(self, m)
        } else {
            layouts.first { $0.id == m.pertag.ltidxs[getMonCurtag(m)] }!.arrange(self, m)   // not in mango: ltidxs holds the id
        }

        if isTag0 {
            m.gappoh = savedOh
            m.gappov = savedOv
            m.gappih = savedIh
            m.gappiv = savedIv
        }

        // not in mango: client_sync_layer's layers raised and the borders drawn, by the port
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
