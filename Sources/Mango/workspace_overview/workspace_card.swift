import CoreGraphics
import Foundation

extension MangoServer {
    func wsovScrollsHorizontally() -> Bool {
        wsov.layout == WORKSPACE_OVERVIEW_SCROLL &&
            config.workspaceOverviewScrollDirection == .horizontal
    }

    func wsovScrollsVertically() -> Bool {
        wsov.layout == WORKSPACE_OVERVIEW_SCROLL &&
            config.workspaceOverviewScrollDirection == .vertical
    }

    func wsovBorderWidth() -> Int {
        wsov.layout == WORKSPACE_OVERVIEW_SCROLL
            ? 0
            : config.workspaceOverviewBorderWidth
    }

    func wsovUpdateScrollBounds() {
        guard let m = wsov.mon, wsov.cells.count > 0,
              wsov.layout == WORKSPACE_OVERVIEW_SCROLL else {
            wsov.scrollOffset = 0.0
            wsov.scrollMin = 0.0
            wsov.scrollMax = 0.0
            return
        }

        let gap = Double(config.workspaceOverviewGap)
        var contentExtent = 0.0
        for cell in wsov.cells {
            let box = wsovCellLayoutBox(cell)
            let extent = Double(wsovScrollsHorizontally() ? box.x + box.width
                : box.y + box.height)
            contentExtent = fmax(contentExtent, extent)
        }

        let viewportExtent =
            wsovScrollsHorizontally() ? m.m.width : m.m.height
        let itemExtent = Double(wsovScrollsHorizontally() ? wsov.cells[0].box.width
            : wsov.cells[0].box.height)
        let pad = fmax(0.0, (viewportExtent - itemExtent) / 2.0) + gap
        wsov.scrollMin = -pad
        wsov.scrollMax =
            fmax(wsov.scrollMin, contentExtent - viewportExtent + pad)
        wsov.scrollOffset =
            fmax(wsov.scrollMin, fmin(wsov.scrollMax, wsov.scrollOffset))
    }

    func wsovClampScroll(_ offset: Double) -> Double {
        fmax(wsov.scrollMin, fmin(wsov.scrollMax, offset))
    }

    func wsovScrollTo(_ offset: Double) -> Bool {
        let clamped = wsovClampScroll(offset)
        if abs(clamped - wsov.scrollOffset) < 0.5 {
            return false
        }
        wsov.scrollOffset = clamped
        return true
    }

    func wsovAnimateScrollTo(_ offset: Double) -> Bool {
        let clamped = wsovClampScroll(offset)
        if abs(clamped - wsov.scrollOffset) < 0.5 {
            return false
        }
        if !config.animations {
            wsov.scrollAnimating = false
            wsov.scrollOffset = clamped
            return true
        }

        wsov.scrollAnimationFrom = wsov.scrollOffset
        wsov.scrollAnimationTo = clamped
        wsov.scrollAnimationDurationMs = Double(animationCurveDurationMs(
            config.animationCurveWsovMove, UInt32(config.animationDurationWsovMove)))
        wsov.scrollAnimating = true
        wsov.scrollAnimationStart = wsovNowMs()
        wsovAttachFrameListener()
        if let m = wsov.mon { system.outputScheduleFrame(m) }
        return true
    }

    func wsovUpdateScrollAnimation() {
        if !wsov.scrollAnimating {
            return
        }
        let elapsedMs = wsovElapsedMs(wsov.scrollAnimationStart)
        let curve = config.animationCurveWsovMove
        var t =
            elapsedMs / MANGO_MAX(1.0, wsov.scrollAnimationDurationMs)
        t = fmax(0.0, fmin(1.0, t))
        let eased = findAnimationCurveFor(t, curve)
        wsov.scrollOffset =
            wsov.scrollAnimationFrom +
            (wsov.scrollAnimationTo - wsov.scrollAnimationFrom) * eased
        if elapsedMs >= wsov.scrollAnimationDurationMs {
            wsov.scrollOffset = wsov.scrollAnimationTo
            wsov.scrollAnimating = false
        }
    }

    func wsovScrollStride() -> Double {
        if wsov.cells.count <= 0 {
            return 1.0
        }
        if wsov.cells.count > 1 {
            return Double(wsovScrollsHorizontally()
                ? wsov.cells[1].box.x - wsov.cells[0].box.x
                : wsov.cells[1].box.y - wsov.cells[0].box.y)
        }
        let extent = Double(wsovScrollsHorizontally() ? wsov.cells[0].box.width
            : wsov.cells[0].box.height)
        return extent + Double(config.workspaceOverviewGap)
    }

    func wsovStepScrollWorkspaces(_ direction: Int32, _ count: UInt32) -> Bool {
        if direction == 0 || count == 0 ||
            wsov.layout != WORKSPACE_OVERVIEW_SCROLL {
            return false
        }
        var current = -1
        let centerTag = wsovCellForTag(wsov.scrollCenterTag) != nil
            ? wsov.scrollCenterTag
            : wsov.targetTag
        for (i, cell) in wsov.cells.enumerated() where cell.tag == centerTag {
            current = i
            break
        }
        if current < 0 {
            return false
        }
        let offset = Int(MANGO_MIN(count, UInt32(wsov.cells.count)))
        let next = direction > 0
            ? MANGO_MIN(wsov.cells.count - 1, current + offset)
            : MANGO_MAX(0, current - offset)
        if next == current {
            return false
        }

        let target = wsov.cells[next]
        wsov.targetTag = target.tag
        wsov.scrollCenterTag = target.tag
        wsov.cameraTag = target.tag
        wsovAnimateScrollToTarget()
        wsovRefreshTargetSelection()
        return true
    }

    func wsovApplyScrollWheel(_ notches: Double, _ timeMsec: UInt32) {
        var direction: Int32 = notches > 0 ? 1 : -1
        let continuing =
            wsov.scrollWheel.tracking && direction == wsov.scrollWheel.direction
        if !continuing {
            wsov.scrollWheel.accum = 0.0
            wsov.scrollWheel.direction = direction
            wsov.scrollWheel.tracking = true
        }

        var velocity = 0.0
        if continuing {
            let dt = Double(timeMsec &- wsov.scrollWheel.lastTimeMsec)
            velocity = abs(notches) * 1000.0 / fmax(1.0, dt)
        }
        wsov.scrollWheel.lastTimeMsec = timeMsec

        var factor = 1.0
        let thresholdInterval =
            fmax(1.0, Double(config.workspaceOverviewScrollDecelStartInterval))
        let thresholdVelocity = 1000.0 / thresholdInterval
        let gain =
            fmax(0.0, fmin(1.0, Double(config.workspaceOverviewScrollDecelGain)))
        if velocity > thresholdVelocity {
            let outputVelocity =
                thresholdVelocity + (velocity - thresholdVelocity) * gain
            factor = outputVelocity / velocity
        }

        let credit = fmin(1024.0, abs(notches) * factor)
        wsov.scrollWheel.accum += Double(direction) * credit
        let whole = trunc(wsov.scrollWheel.accum)
        if whole == 0.0 {
            return
        }
        wsov.scrollWheel.accum -= whole

        direction = whole > 0.0 ? 1 : -1
        let count = UInt32(fmin(abs(whole), Double(UInt32.max)))
        _ = wsovStepScrollWorkspaces(direction, count)
    }

    func wsovUpdateDragScroll(_ x: Double, _ y: Double) {
        var direction: Int32 = 0
        if wsov.layout == WORKSPACE_OVERVIEW_SCROLL && wsov.pressed &&
            wsov.moved && wsov.hasDragClient, let m = wsov.mon {
            let lx = x - m.m.minX
            let ly = y - m.m.minY
            if lx >= 0 && ly >= 0 && lx < m.m.width &&
                ly < m.m.height {
                let along = wsovScrollsHorizontally() ? lx : ly
                let viewport = wsovScrollsHorizontally() ? m.m.width
                    : m.m.height
                let edge = fmax(24.0, fmin(96.0, viewport * 0.05))
                if along < edge {
                    direction = -1
                } else if along > viewport - edge {
                    direction = 1
                }
            }
        }
        if direction == wsov.dragScrollDirection {
            return
        }

        wsov.dragScrollDirection = direction
        wsov.dragScrollFrameValid = false
        if direction == 0 {
            return
        }
        wsovAttachFrameListener()
        if let m = wsov.mon { system.outputScheduleFrame(m) }
    }

    func wsovAdvanceDragScroll() -> Bool {
        if wsov.mon == nil || wsov.dragScrollDirection == 0 {
            return false
        }

        let now = wsovNowMs()
        if !wsov.dragScrollFrameValid {
            wsov.dragScrollLastFrame = now
            wsov.dragScrollFrameValid = true
            return false
        }
        var dt = (now - wsov.dragScrollLastFrame) / 1000.0
        wsov.dragScrollLastFrame = now
        dt = fmax(0.001, fmin(0.05, dt))

        let speed =
            wsovScrollStride() * Double(config.workspaceOverviewDragScrollSpeed)
        let offset =
            wsov.scrollOffset + Double(wsov.dragScrollDirection) * speed * dt
        if !wsovScrollTo(offset) {
            return false
        }
        let cursor = system.pointer
        wsovUpdateDropIndicator(cursor.x, cursor.y)
        return true
    }

    func wsovScrollToTarget() {
        if wsov.layout != WORKSPACE_OVERVIEW_SCROLL {
            return
        }
        if wsovCellForTag(wsov.scrollCenterTag) == nil {
            wsov.scrollCenterTag = wsov.targetTag
        }
        guard let target = wsovCellForTag(wsov.scrollCenterTag), let m = wsov.mon else { return }
        let box = wsovCellLayoutBox(target)
        let center = wsovScrollsHorizontally() ? Double(box.x) + Double(box.width) / 2.0
            : Double(box.y) + Double(box.height) / 2.0
        let viewportCenter = wsovScrollsHorizontally()
            ? m.m.width / 2.0
            : m.m.height / 2.0
        _ = wsovScrollTo(center - viewportCenter)
    }

    func wsovAnimateScrollToFinalTarget() {
        if wsov.layout != WORKSPACE_OVERVIEW_SCROLL {
            return
        }
        if wsovCellForTag(wsov.scrollCenterTag) == nil {
            wsov.scrollCenterTag = wsov.targetTag
        }
        guard let target = wsovCellForTag(wsov.scrollCenterTag), let m = wsov.mon else { return }
        let box = target.box
        let center = wsovScrollsHorizontally() ? Double(box.x) + Double(box.width) / 2.0
            : Double(box.y) + Double(box.height) / 2.0
        let viewportCenter = wsovScrollsHorizontally()
            ? m.m.width / 2.0
            : m.m.height / 2.0
        _ = wsovAnimateScrollTo(center - viewportCenter)
    }

    func wsovAnimateScrollToTarget() {
        if wsov.layout != WORKSPACE_OVERVIEW_SCROLL {
            return
        }
        guard let target = wsovCellForTag(wsov.targetTag), let m = wsov.mon else { return }
        let box = wsovCellLayoutBox(target)
        let center = wsovScrollsHorizontally() ? Double(box.x) + Double(box.width) / 2.0
            : Double(box.y) + Double(box.height) / 2.0
        let viewportCenter = wsovScrollsHorizontally()
            ? m.m.width / 2.0
            : m.m.height / 2.0
        if wsovAnimateScrollTo(center - viewportCenter) {
            wsovApplyCamera(wsov.progress)
        }
    }

    func wsovSetCellBox(_ cell: WsovCell, _ x: Int, _ y: Int, _ width: Int, _ height: Int) {
        cell.box = WlrBox(x: x, y: y, width: width, height: height)
        cell.bufferW = cell.box.width - 2 * wsovBorderWidth()
        cell.bufferH = cell.box.height - 2 * wsovBorderWidth()
        cell.layoutCurrent = cell.box

        wlrSceneNodeSetPosition(cell.frame, cell.box.x, cell.box.y)
        wlrSceneRectSetSize(cell.frame, cell.box.width, cell.box.height)
        wlrSceneNodeSetPosition(cell.contents,
                                cell.box.x + wsovBorderWidth(),
                                cell.box.y + wsovBorderWidth())
        wlrSceneBufferSetDestSize(cell.contents, cell.bufferW,
                                  cell.bufferH)
        wlrSceneNodeSetPosition(cell.foreground,
                                cell.box.x + wsovBorderWidth(),
                                cell.box.y + wsovBorderWidth())
        wlrSceneBufferSetDestSize(cell.foreground, cell.bufferW,
                                  cell.bufferH)
    }

    func wsovGridCols(_ count: Int) -> Int {
        MANGO_MAX(1, Int(ceil(sqrt(Double(MANGO_MAX(1, count))))))
    }

    func wsovLayoutGridCells() {
        guard let m = wsov.mon else { return }
        let n = wsov.cells.count
        let cols = wsovGridCols(n)
        let rows = (n + cols - 1) / cols
        let gap = config.workspaceOverviewGap
        let availW = MANGO_MAX(1, Int(m.m.width))
        let availH = MANGO_MAX(1, Int(m.m.height))
        let aspect = Double(m.m.width) / Double(m.m.height)
        var cellW = MANGO_MAX(1, (availW - (cols - 1) * gap) / cols)
        var cellH = lround(Double(cellW) / aspect)
        let maxCellH = MANGO_MAX(1, (availH - (rows - 1) * gap) / rows)
        if cellH > maxCellH {
            cellH = maxCellH
            cellW = lround(Double(cellH) * aspect)
        }
        if n == 1 {
            let maxSingleW =
                MANGO_MIN(availW, MANGO_MAX(1, lround(Double(availW) * 0.9)))
            if cellW > maxSingleW {
                cellW = maxSingleW
                cellH = MANGO_MAX(1, lround(Double(cellW) / aspect))
            }
        }
        cellW = MANGO_MAX(2 * wsovBorderWidth() + 1, cellW)
        cellH = MANGO_MAX(2 * wsovBorderWidth() + 1, cellH)
        let gridH = rows * cellH + (rows - 1) * gap
        let gridY = MANGO_MAX(0, (availH - gridH) / 2)

        for i in 0..<n {
            let col = i % cols
            let row = i / cols
            let rowStart = row * cols
            let rowEnd = MANGO_MIN(rowStart + cols, n)
            let rowLen = rowEnd - rowStart
            let rowW = rowLen * cellW + (rowLen - 1) * gap
            let rowX = MANGO_MAX(0, (availW - rowW) / 2)
            let sx = rowX + col * (cellW + gap)
            let sy = gridY + row * (cellH + gap)
            wsovSetCellBox(wsov.cells[i], sx, sy, cellW, cellH)
        }
    }

    func wsovLayoutScrollCells() {
        guard let m = wsov.mon else { return }
        let n = wsov.cells.count
        let gap = config.workspaceOverviewGap
        let availW = MANGO_MAX(1, Int(m.m.width))
        let availH = MANGO_MAX(1, Int(m.m.height))
        let aspect = Double(m.m.width) / Double(m.m.height)
        let fitW = MANGO_MAX(
            1, lround(Double(availW) * Double(config.workspaceOverviewScrollRatio)))
        let fitH = MANGO_MAX(
            1, lround(Double(availH) * Double(config.workspaceOverviewScrollRatio)))
        var cellW = MANGO_MIN(fitW, MANGO_MAX(1, lround(Double(fitH) * aspect)))
        var cellH = MANGO_MAX(1, lround(Double(cellW) / aspect))
        cellW = MANGO_MAX(2 * wsovBorderWidth() + 1, cellW)
        cellH = MANGO_MAX(2 * wsovBorderWidth() + 1, cellH)
        let centerX = MANGO_MAX(0, (availW - cellW) / 2)
        let centerY = MANGO_MAX(0, (availH - cellH) / 2)

        for i in 0..<n {
            let sx = wsovScrollsHorizontally() ? i * (cellW + gap) : centerX
            let sy = wsovScrollsVertically() ? i * (cellH + gap) : centerY
            wsovSetCellBox(wsov.cells[i], sx, sy, cellW, cellH)
        }
    }

    func wsovLayoutCells() {
        if wsov.mon == nil || wsov.cells.count <= 0 {
            return
        }
        if wsov.layout == WORKSPACE_OVERVIEW_SCROLL {
            wsovLayoutScrollCells()
        } else {
            wsovLayoutGridCells()
        }
        wsovUpdateScrollBounds()
    }

    func wsovUpdateLayoutAnimation() {
        if !wsov.layoutAnimating {
            return
        }

        let elapsedMs = wsovElapsedMs(wsov.layoutAnimationStart)
        var eased = 0.0
        let curve = config.animationCurveWsovMove
        var t = elapsedMs / MANGO_MAX(1.0, wsov.layoutAnimationDurationMs)
        t = fmax(0.0, fmin(1.0, t))
        eased = findAnimationCurveFor(t, curve)
        let finished = elapsedMs >= wsov.layoutAnimationDurationMs
        for cell in wsov.cells {
            if finished {
                cell.layoutCurrent = cell.box
                continue
            }
            let from = cell.layoutFrom
            cell.layoutCurrent = WlrBox(
                x: lround(Double(from.x) +
                    Double(cell.box.x - from.x) * eased),
                y: lround(Double(from.y) +
                    Double(cell.box.y - from.y) * eased),
                width: MANGO_MAX(
                    1, lround(Double(from.width) +
                        Double(cell.box.width - from.width) *
                        eased)),
                height: MANGO_MAX(
                    1, lround(Double(from.height) +
                        Double(cell.box.height - from.height) *
                        eased)))
        }
        if finished {
            wsov.layoutAnimating = false
        }
    }

    func wsovDestroyCells() {
        wsovCancelScheduledRender()
        wsovClearLiveProjection(false)
        for cell in wsov.cells {
            if let contents = cell.contents {
                wlrSceneNodeDestroy(contents)
            }
            if let foreground = cell.foreground {
                wlrSceneNodeDestroy(foreground)
            }
            mangoDimNodeDestroy(cell.dim)
            if let frame = cell.frame {
                wlrSceneNodeDestroy(frame)
            }
            for j in 0..<4 {
                if let b = cell.border[j] {
                    wlrSceneNodeDestroy(b)
                }
            }
            // not in mango: no buffer pool, live trees, layer previews or bar items to free
        }
        wsov.cells = []
    }

    func wsovCreateCells() -> Bool {
        let oldCellCount = wsov.cells.count
        let oldScrollOffset = wsov.scrollOffset
        var snapshot: [(tag: UInt32, box: WlrBox)] = []
        if oldCellCount > 0 {
            for cell in wsov.cells {
                snapshot.append((tag: cell.tag, box: wsovCellLayoutBox(cell)))
            }
        }

        wsovDestroyCells()
        var count = 0
        let occupied = wsovCollectWorkspaceTags(wsov.mon, &count)
        if count <= 0 {
            return false
        }
        guard let root = wsov.root else { return false }

        for tag in stride(from: 1, through: config.tagNum, by: 1) {
            if occupied & wsovTagBit(UInt32(tag)) == 0 {
                continue
            }

            let cell = WsovCell()
            wsov.cells.append(cell)
            cell.tag = UInt32(tag)
            cell.bordersEnabled = true
            cell.frame = wlrSceneRectCreate(root, 1, 1, config.rootcolor)
            for i in 0..<4 {
                cell.border[i] =
                    wlrSceneRectCreate(root, 1, 1, config.bordercolor)
            }
            cell.contents = wlrSceneBufferCreate(root, nil)
            cell.foreground = wlrSceneBufferCreate(root, nil)
            cell.dim = mangoDimNodeCreate(root, RGBA(r: 0, g: 0, b: 0, a: 0))
        }

        wsovLayoutCells()
        wsov.layoutAnimating = false
        for cell in wsov.cells {
            cell.layoutFrom = cell.box
            for old in snapshot where old.tag == cell.tag {
                cell.layoutFrom = old.box
                if config.animations &&
                    !wlrBoxEqual(cell.layoutFrom, cell.box) {
                    wsov.layoutAnimating = true
                }
                break
            }
        }
        if config.animations && wsov.layoutAnimating {
            for cell in wsov.cells {
                cell.layoutCurrent = cell.layoutFrom
            }
            wsov.layoutAnimationDurationMs =
                Double(animationCurveDurationMs(config.animationCurveWsovMove,
                                                UInt32(config.animationDurationWsovMove)))
            wsov.layoutAnimationStart = wsovNowMs()
            wsovAttachFrameListener()
        }
        // not in mango: no layer previews (no layer shell, wsov_create_layer_previews)
        wsovSelectDefaultTarget()
        /*
         * Keep the scroll anchor independent from target_tag. Pointer hover may
         * change the selected target without moving the viewport, while the wheel
         * must continue from the workspace that is currently centered.
         */
        if wsovCellForTag(wsov.scrollCenterTag) == nil {
            wsov.scrollCenterTag = wsov.targetTag
        }
        wsov.cameraTag = wsov.targetTag
        if oldCellCount > 0 && config.animations {
            /*
             * Removing an occupied workspace changes the scroll bounds and can
             * make the selected workspace jump several positions. Keep the old
             * viewport as the animation start instead of letting layout_cells()
             * clamp it to the new final position first.
             */
            wsov.scrollOffset = oldScrollOffset
            wsovAnimateScrollToFinalTarget()
        } else {
            wsovScrollToTarget()
        }
        wsovSyncMonitorSelection()
        wsovCaptureWorkspaceLayouts()
        for cell in wsov.cells {
            cell.contentsDirty = true
            cell.foregroundDirty = true
        }
        wsovRebuildLiveProjection()
        wsovRenderAll()
        wsovUpdateStyles()
        wsovApplyCamera(wsov.progress)
        if wsovRefreshAnimatedCells() {
            wsov.clientAnimating = true
            wsovAttachFrameListener()
            if let m = wsov.mon { system.outputScheduleFrame(m) }
        }
        return true
    }
}
