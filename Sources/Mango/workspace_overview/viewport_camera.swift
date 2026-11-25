import CoreGraphics
import Foundation

extension MangoServer {
    func wsovCellLayoutBox(_ cell: WsovCell?) -> WlrBox {
        guard let cell else { return WlrBox() }
        return wsov.layoutAnimating ? cell.layoutCurrent : cell.box
    }

    func wsovLiveClipsToWorkspace(_ cell: WsovCell?) -> Bool {
        guard let cell, wsov.layout == WORKSPACE_OVERVIEW_SCROLL, let m = wsov.mon else {
            return true
        }

        let layout = m.pertag.ltidxs[Int(cell.tag)]
        if wsovScrollsVertically() {
            return layout == .verticalScroller
        }
        if wsovScrollsHorizontally() {
            return layout == .scroller
        }
        return true
    }

    func wsovLiveOverflowClip(_ workspace: WlrBox?, _ monitor: WlrBox?) -> WlrBox {
        guard let workspace, let monitor else { return WlrBox() }

        var clip = monitor
        if wsovScrollsVertically() {
            clip.y = workspace.y
            clip.height = workspace.height
        } else if wsovScrollsHorizontally() {
            clip.x = workspace.x
            clip.width = workspace.width
        } else {
            /* Grid workspace overview keeps every preview inside its frame. */
            return workspace
        }

        var visible = WlrBox()
        if !wlrBoxIntersection(&visible, clip, monitor) {
            return WlrBox()
        }
        return visible
    }

    func wsovItemDisplayBox(_ cell: WsovCell?, _ item: WsovItem?) -> WlrBox {
        guard let cell, let item else { return WlrBox() }

        let cellBox = wsovCellLayoutBox(cell)
        let scaleX =
            Double(MANGO_MAX(1, cellBox.width - 2 * wsovBorderWidth())) /
            Double(MANGO_MAX(1, cell.bufferW))
        let scaleY =
            Double(MANGO_MAX(1, cellBox.height - 2 * wsovBorderWidth())) /
            Double(MANGO_MAX(1, cell.bufferH))
        let localX = Double(item.box.x - cell.box.x - wsovBorderWidth())
        let localY = Double(item.box.y - cell.box.y - wsovBorderWidth())
        let scrollX =
            wsovScrollsHorizontally() ? lround(wsov.scrollOffset) : 0
        let scrollY =
            wsovScrollsVertically() ? lround(wsov.scrollOffset) : 0
        return WlrBox(
            x: cellBox.x - scrollX + wsovBorderWidth() +
                lround(localX * scaleX),
            y: cellBox.y - scrollY + wsovBorderWidth() +
                lround(localY * scaleY),
            width: MANGO_MAX(1, lround(Double(item.box.width) * scaleX)),
            height: MANGO_MAX(1, lround(Double(item.box.height) * scaleY)))
    }

    func wsovItemFinalDisplayBox(_ cell: WsovCell?, _ item: WsovItem?) -> WlrBox {
        guard let cell, let item, !item.isSnapshot, let client = item.client, let m = wsov.mon else {
            return WlrBox()
        }

        let cellBox = cell.box
        let contentW = MANGO_MAX(1, cellBox.width - 2 * wsovBorderWidth())
        let contentH = MANGO_MAX(1, cellBox.height - 2 * wsovBorderWidth())
        let scaleX = Double(contentW) / Double(MANGO_MAX(1, Int(m.m.width)))
        let scaleY = Double(contentH) / Double(MANGO_MAX(1, Int(m.m.height)))
        let localX = client.geom.minX - m.m.minX
        let localY = client.geom.minY - m.m.minY
        let scrollX =
            wsovScrollsHorizontally() ? lround(wsov.scrollOffset) : 0
        let scrollY =
            wsovScrollsVertically() ? lround(wsov.scrollOffset) : 0
        return WlrBox(
            x: cellBox.x - scrollX + wsovBorderWidth() +
                lround(localX * scaleX),
            y: cellBox.y - scrollY + wsovBorderWidth() +
                lround(localY * scaleY),
            width: MANGO_MAX(1, lround(client.geom.width * scaleX)),
            height:
                MANGO_MAX(1, lround(client.geom.height * scaleY)))
    }

    func wsovMonitorClip() -> WlrBox {
        guard let m = wsov.mon else { return WlrBox() }
        return WlrBox(0, 0, Int(m.m.width), Int(m.m.height))
    }

    func wsovIntersectMonitor(_ x: Int, _ y: Int, _ width: Int, _ height: Int,
                              _ visible: inout WlrBox) -> Bool {
        let box = WlrBox(x, y, width, height)
        let clip = wsovMonitorClip()
        visible = WlrBox()
        if box.width <= 0 || box.height <= 0 || clip.width <= 0 ||
            clip.height <= 0 || !wlrBoxIntersection(&visible, box, clip) {
            return false
        }
        return !wlrBoxEmpty(visible)
    }

    func wsovGetCameraView(_ progress: Double, _ view: inout WsovCameraView) -> Bool {
        guard let m = wsov.mon, wsov.cells.count > 0 else { return false }

        let target = wsovCellForTag(wsov.cameraTag) ?? wsov.cells[0]
        let targetBox = wsovCellLayoutBox(target)
        let border = wsovBorderWidth()
        let targetX = Double(targetBox.x + border)
        let targetY = Double(targetBox.y + border)
        let targetW = Double(MANGO_MAX(1, targetBox.width - 2 * border))
        let targetH = Double(MANGO_MAX(1, targetBox.height - 2 * border))
        let finalViewportX =
            wsovScrollsHorizontally() ? wsov.scrollOffset : 0.0
        let finalViewportY =
            wsovScrollsVertically() ? wsov.scrollOffset : 0.0
        let progress = fmax(0.0, fmin(1.0, progress))
        let viewportW = targetW + (m.m.width - targetW) * progress
        let viewportH = targetH + (m.m.height - targetH) * progress
        view.x = targetX + (finalViewportX - targetX) * progress
        view.y = targetY + (finalViewportY - targetY) * progress
        view.scaleX = m.m.width / MANGO_MAX(1.0, viewportW)
        view.scaleY = m.m.height / MANGO_MAX(1.0, viewportH)
        return true
    }

    func wsovCellScreenBox(_ cell: WsovCell?, _ view: WsovCameraView?) -> WlrBox {
        guard let cell, let view else { return WlrBox() }
        let box = wsovCellLayoutBox(cell)
        return WlrBox(
            x: lround((Double(box.x) - view.x) * view.scaleX),
            y: lround((Double(box.y) - view.y) * view.scaleY),
            width: MANGO_MAX(1, lround(Double(box.width) * view.scaleX)),
            height: MANGO_MAX(1, lround(Double(box.height) * view.scaleY)))
    }

    func wsovCellBoxVisible(_ box: WlrBox?) -> Bool {
        var visible = WlrBox()
        guard let box else { return false }
        return wsovIntersectMonitor(box.x, box.y, box.width, box.height, &visible)
    }

    func wsovCellPreviewVisible(_ cell: WsovCell, _ progress: Double) -> Bool {
        var view = WsovCameraView()
        if !wsovGetCameraView(progress, &view) {
            return false
        }
        let box = wsovCellScreenBox(cell, view)
        return wsovCellBoxVisible(box)
    }

    /*
     * A workspace frame can be off-screen while a live scroller child overflows
     * back into the output. Treat that child as visible work; same-axis clipping
     * cannot escape the frame, so it can be culled using the frame alone.
     */
    func wsovCellLiveContentVisible(_ cell: WsovCell?, _ progress: Double) -> Bool {
        var view = WsovCameraView()
        guard let cell, wsovGetCameraView(progress, &view) else { return false }
        let cellBox = wsovCellScreenBox(cell, view)
        if wsovCellBoxVisible(cellBox) {
            return true
        }
        if wsovLiveClipsToWorkspace(cell) {
            return false
        }

        for item in cell.items {
            if item.isSnapshot {
                continue
            }
            let box = WlrBox(
                x: lround((Double(item.box.x) - view.x) * view.scaleX),
                y: lround((Double(item.box.y) - view.y) * view.scaleY),
                width: MANGO_MAX(1, lround(Double(item.box.width) * view.scaleX)),
                height:
                    MANGO_MAX(1, lround(Double(item.box.height) * view.scaleY)))
            if wsovCellBoxVisible(box) {
                return true
            }
        }
        return false
    }

    func wsovCellLiveContentVisibleInView(_ cell: WsovCell, _ view: WsovCameraView) -> Bool {
        let cellBox = wsovCellScreenBox(cell, view)
        if wsovCellBoxVisible(cellBox) {
            return true
        }
        if wsovLiveClipsToWorkspace(cell) {
            return false
        }

        for item in cell.items {
            if item.isSnapshot {
                continue
            }
            let box = WlrBox(
                x: lround((Double(item.box.x) - view.x) * view.scaleX),
                y: lround((Double(item.box.y) - view.y) * view.scaleY),
                width: MANGO_MAX(1, lround(Double(item.box.width) * view.scaleX)),
                height:
                    MANGO_MAX(1, lround(Double(item.box.height) * view.scaleY)))
            if wsovCellBoxVisible(box) {
                return true
            }
        }
        return false
    }

    func wsovPlaceRectClipped(_ rect: WlrSceneRect?, _ x: Int, _ y: Int,
                              _ width: Int, _ height: Int, _ enabled: Bool) {
        var visible = WlrBox()
        guard let rect else { return }
        if !enabled || !wsovIntersectMonitor(x, y, width, height, &visible) {
            wlrSceneNodeSetEnabled(rect, false)
            return
        }
        wlrSceneNodeSetEnabled(rect, true)
        wlrSceneNodeSetPosition(rect, visible.x, visible.y)
        wlrSceneRectSetSize(rect, visible.width, visible.height)
    }

    // not in mango: the buffers have no transform (WL_OUTPUT_TRANSFORM_NORMAL)
    func wsovPlaceBufferClipped(_ node: WlrSceneBuffer?, _ baseSrc: CGRect?, _ x: Int, _ y: Int,
                                _ width: Int, _ height: Int) {
        var visible = WlrBox()
        guard let node else { return }
        guard let buffer = node.buffer,
              wsovIntersectMonitor(x, y, width, height, &visible) else {
            wlrSceneNodeSetEnabled(node, false)
            return
        }

        var src = baseSrc
            ?? CGRect(x: 0, y: 0, width: buffer.width, height: buffer.height)
        if src.width <= 0 || src.height <= 0 {
            src =
                CGRect(x: 0, y: 0, width: buffer.width, height: buffer.height)
        }

        src.origin.x += src.width * Double(visible.x - x) / Double(width)
        src.origin.y += src.height * Double(visible.y - y) / Double(height)
        src.size.width *= Double(visible.width) / Double(width)
        src.size.height *= Double(visible.height) / Double(height)

        wlrSceneNodeSetEnabled(node, true)
        wlrSceneNodeSetPosition(node, visible.x, visible.y)
        wlrSceneBufferSetDestSize(node, visible.width, visible.height)
        wlrSceneBufferSetSourceBox(node, src)
    }

    func wsovOutputScale() -> Double {
        guard let m = wsov.mon else { return 1.0 }
        return fmax(1.0, m.screen.scale)
    }

    func wsovCellAt(_ x: Double, _ y: Double) -> WsovCell? {
        guard wsov.root != nil, let m = wsov.mon else { return nil }

        var lx = x - m.m.minX
        var ly = y - m.m.minY
        if lx < 0 || ly < 0 || lx >= m.m.width || ly >= m.m.height {
            return nil
        }
        if wsovScrollsHorizontally() {
            lx += wsov.scrollOffset
        } else if wsovScrollsVertically() {
            ly += wsov.scrollOffset
        }
        for cell in wsov.cells {
            let box = wsovCellLayoutBox(cell)
            if wlrBoxContainsPoint(box, lx, ly) {
                return cell
            }
        }
        return nil
    }

    func wsovDropCellAt(_ x: Double, _ y: Double) -> WsovCell? {
        let cell = wsovCellAt(x, y)
        guard cell == nil, let m = wsov.mon, x >= m.m.minX,
              x < m.m.minX + m.m.width, y >= m.m.minY,
              y < m.m.minY + m.m.height else {
            return cell
        }

        var lx = x - m.m.minX
        var ly = y - m.m.minY
        if wsovScrollsHorizontally() {
            lx += wsov.scrollOffset
        } else if wsovScrollsVertically() {
            ly += wsov.scrollOffset
        }
        var nearest: WsovCell?
        var best = 1e30
        for candidate in wsov.cells {
            let box = wsovCellLayoutBox(candidate)
            let cx = Double(box.x) + Double(box.width) / 2.0
            let cy = Double(box.y) + Double(box.height) / 2.0
            let dx = cx - lx
            let dy = cy - ly
            let distance = dx * dx + dy * dy
            if distance < best {
                best = distance
                nearest = candidate
            }
        }
        return nearest
    }

    func wsovItemAt(_ cell: WsovCell?, _ x: Double, _ y: Double) -> WsovItem? {
        guard let cell, let m = wsov.mon else { return nil }
        let lx = x - m.m.minX
        let ly = y - m.m.minY
        var hit: WsovItem?
        for item in cell.items {
            if item.isSnapshot {
                continue
            }
            let box = wsovItemDisplayBox(cell, item)
            if wlrBoxContainsPoint(box, lx, ly) &&
                (hit == nil || item.layer >= hit!.layer) {
                hit = item
            }
        }
        return hit
    }

    func wsovHitCellAt(_ x: Double, _ y: Double) -> WsovCell? {
        if let cell = wsovCellAt(x, y) {
            return cell
        }

        /*
         * Live scroller windows may intentionally extend past their workspace on
         * the orthogonal axis. Every workspace now has a live projection, so the
         * same pixels must remain draggable instead of requiring a click inside
         * the frame.
         */
        var bestCell: WsovCell?
        var bestItem: WsovItem?
        for candidate in wsov.cells {
            if wsovLiveClipsToWorkspace(candidate) {
                continue
            }
            guard let item = wsovItemAt(candidate, x, y), wsovItemIsLive(candidate, item) else {
                continue
            }
            if bestItem == nil || item.layer > bestItem!.layer ||
                (item.layer == bestItem!.layer &&
                 candidate.tag == wsov.targetTag) {
                bestCell = candidate
                bestItem = item
            }
        }
        if let bestCell {
            return bestCell
        }
        return nil
    }

    // not in mango: wsov_scene_node_layout_coords is not needed (no bar nodes to capture)

    func wsovApplyCamera(_ progress: Double) {
        guard let m = wsov.mon, wsov.cells.count > 0 else { return }

        var view = WsovCameraView()
        if !wsovGetCameraView(progress, &view) {
            return
        }

        for cell in wsov.cells {
            let cellBox = wsovCellLayoutBox(cell)
            let width = Double(cellBox.width) * view.scaleX
            let height = Double(cellBox.height) * view.scaleY
            let x = (Double(cellBox.x) - view.x) * view.scaleX
            let y = (Double(cellBox.y) - view.y) * view.scaleY

            wsovPlaceRectClipped(cell.frame, lround(x), lround(y),
                                 MANGO_MAX(1, lround(width)),
                                 MANGO_MAX(1, lround(height)), true)
            let contentX = lround(
                (Double(cellBox.x + wsovBorderWidth()) - view.x) * view.scaleX)
            let contentY = lround(
                (Double(cellBox.y + wsovBorderWidth()) - view.y) * view.scaleY)
            let contentW = MANGO_MAX(
                1,
                lround(Double(MANGO_MAX(1, cellBox.width - 2 * wsovBorderWidth())) *
                    view.scaleX))
            let contentH =
                MANGO_MAX(1, lround(Double(MANGO_MAX(1, cellBox.height -
                    2 * wsovBorderWidth())) *
                    view.scaleY))
            wsovPlaceBufferClipped(cell.contents, nil, contentX, contentY,
                                   contentW, contentH)
            wsovPlaceBufferClipped(cell.foreground, nil, contentX, contentY,
                                   contentW, contentH)
            var dimVisible = WlrBox()
            if !cell.dimEnabled ||
                !wsovIntersectMonitor(contentX, contentY, contentW, contentH,
                                      &dimVisible) {
                mangoDimNodeSetEnabled(cell.dim, false)
            } else {
                mangoDimNodeSetEnabled(cell.dim, true)
                mangoDimNodeSetBox(cell.dim, dimVisible.x, dimVisible.y,
                                   dimVisible.width, dimVisible.height)
            }
            let frameW = MANGO_MAX(1, lround(width))
            let frameH = MANGO_MAX(1, lround(height))
            let borderW =
                MANGO_MAX(1, lround(Double(wsovBorderWidth()) *
                    fmin(view.scaleX, view.scaleY)))
            let frameX = lround(x)
            let frameY = lround(y)
            wsovPlaceRectClipped(cell.border[0], frameX, frameY, frameW,
                                 borderW, cell.bordersEnabled)
            wsovPlaceRectClipped(cell.border[1], frameX,
                                 frameY + frameH - borderW, frameW, borderW,
                                 cell.bordersEnabled)
            wsovPlaceRectClipped(cell.border[2], frameX, frameY, borderW,
                                 frameH, cell.bordersEnabled)
            wsovPlaceRectClipped(cell.border[3], frameX + frameW - borderW,
                                 frameY, borderW, frameH,
                                 cell.bordersEnabled)
            // not in mango: no layer previews (no layer shell)
        }
        wsovLayoutLiveProjection()
        if !wsov.closing {
            _ = wsovRenderDirtyCells(false)
        }
        system.outputScheduleFrame(m)
    }
}
