import CoreGraphics
import Foundation

// not in mango: the cells' buffers hold the windows the port draws as pictures, not a GL render pass
// (wsov_retain_texture, wsov_release_textures, wsov_rebind_pass, wsov_pick_buffer_format,
// wsov_create_buffer, wsov_release_cell_buffers, wsov_acquire_cell_buffer, wsov_render_scene_buffer,
// wsov_render_scene_surfaces, wsov_add_rect, wsov_render_bar_item_at); no bar nodes to capture, the port
// draws the group and tab bars (wsov_capture_bar_rect, wsov_capture_bar_buffer, wsov_capture_bar,
// wsov_clear_cell_bars, wsov_draw_group_bar_for_capture, wsov_draw_tabbar_for_capture,
// wsov_group_capture_owner); no fade-out clients (wsov_snapshot_item_add, wsov_fadeout_client_alive)

extension MangoServer {
    func wsovItemAdd(_ cell: WsovCell, _ c: Client) {
        let item = WsovItem(client: c)
        item.borderWidth = c.bw
        cell.items.append(item)
        cell.items[cell.items.count - 1].layer = clientTargetLayer(c)
    }

    func wsovCellItemForClient(_ cell: WsovCell?, _ c: Client?) -> WsovItem? {
        guard let cell, let c else { return nil }
        for item in cell.items where !item.isSnapshot && item.client === c {
            return item
        }
        return nil
    }

    /// mango wsov_item_stack_compare (offscreen_texture.c)
    // not in mango: within a layer the capture's order (the focus stack, oldest first) stands for the scene's
    // sibling order (wsov_scene_node_sibling_index), the port's stacking
    func wsovItemStackCompare(_ a: WsovItem, _ b: WsovItem) -> Bool {
        a.layer < b.layer
    }

    func wsovCaptureCellItems(_ cell: WsovCell) {
        cell.items = []
        for c in focusStack.reversed() {
            if !wsovClientOnTag(c, cell.tag) {
                continue
            }
            wsovItemAdd(cell, c)
            cell.items[cell.items.count - 1].workspaceGeom = WlrBox(c.animation.current)
        }
        /*
         * Reproduce Mango's scene stack for every preview. Scene layers dominate;
         * within one layer (for example LyrTop when float_full_to_top is enabled),
         * the real scene sibling order still decides which window is on top.
         */
        if cell.items.count > 1 {
            cell.items = stableSorted(cell.items, by: wsovItemStackCompare)
        }
    }

    /// Not in mango: qsort with the capture's order kept within a layer.
    private func stableSorted(_ items: [WsovItem], by less: (WsovItem, WsovItem) -> Bool) -> [WsovItem] {
        items.enumerated().sorted { l, r in
            less(l.element, r.element) || (!less(r.element, l.element) && l.offset < r.offset)
        }.map(\.element)
    }

    func wsovCaptureCellBars(_ cell: WsovCell) {
        // not in mango: no bar nodes to capture; the port draws the group and tab bars
    }

    func wsovPositionCellItems(_ cell: WsovCell) {
        guard let m = wsov.mon else { return }
        let scaleX = Double(cell.bufferW) / Double(MANGO_MAX(1, Int(m.m.width)))
        let scaleY = Double(cell.bufferH) / Double(MANGO_MAX(1, Int(m.m.height)))
        for item in cell.items {
            let geo = item.workspaceGeom
            let x = cell.box.x + wsovBorderWidth() +
                lround((Double(geo.x) - m.m.minX) * scaleX)
            let y = cell.box.y + wsovBorderWidth() +
                lround((Double(geo.y) - m.m.minY) * scaleY)
            let w = MANGO_MAX(1, lround(Double(geo.width) * scaleX))
            let h = MANGO_MAX(1, lround(Double(geo.height) * scaleY))
            item.box = WlrBox(x, y, w, h)
            item.renderScale = fmin(scaleX, scaleY)
            item.renderScaleX = scaleX
            item.renderScaleY = scaleY
        }
    }

    func wsovCaptureWorkspaceTags(_ tags: UInt32) {
        if !workspaceOverviewIsActive() || wsov.cells.count <= 0 {
            return
        }
        let savedCapturingLayout = wsov.capturingLayout
        wsov.capturingLayout = true

        guard let m = wsov.mon else { return }
        var selected: UInt32 = 0
        for cell in wsov.cells {
            let bit = wsovTagBit(cell.tag)
            if tags & bit != 0 {
                selected |= bit
            }
        }
        if selected == 0 {
            wsov.capturingLayout = savedCapturingLayout
            return
        }

        system.holdWrites(true)   // not in mango: the port holds back what arrange writes while mango measures
        let savedTags = [m.tagset[0], m.tagset[1]]
        let savedSeltags = m.seltags
        let savedCurtag = m.pertag.curtag
        let savedPrevtag = m.pertag.prevtag
        let savedSel = m.sel
        let savedPrevsel = m.prevsel
        let savedTagGather = config.tagGather

        syncTagRatioStateFromClients(m, savedCurtag)
        config.tagGather = false

        for c in clients {
            if c.mon === m &&
                (c.isglobal || c.tags & selected != 0) {
                c.wsovHidden = false
                clientUpdateVisibility(c)
            }
        }

        for cell in wsov.cells {
            let tag = cell.tag
            if selected & wsovTagBit(tag) == 0 {
                continue
            }
            m.tagset[savedSeltags] = wsovTagBit(tag)
            m.pertag.curtag = tag
            arrange(m, false, true)
            wsovSettleTagAnimations(m, selected)
            wsovCaptureCellItems(cell)
            wsovCaptureCellBars(cell)
        }

        m.seltags = savedSeltags
        m.tagset[0] = savedTags[0]
        m.tagset[1] = savedTags[1]
        m.pertag.curtag = savedCurtag
        m.pertag.prevtag = savedPrevtag
        arrange(m, false, true)
        wsovSettleTagAnimations(m, selected)
        m.sel = savedSel
        m.prevsel = savedPrevsel
        config.tagGather = savedTagGather

        for c in clients {
            if c.mon === m &&
                (c.isglobal || c.tags & selected != 0) {
                c.wsovHidden = true
                clientUpdateVisibility(c)
            }
        }
        system.holdWrites(false)   // not in mango: the port writes what arrange left
        for cell in wsov.cells {
            if selected & wsovTagBit(cell.tag) != 0 {
                wsovPositionCellItems(cell)
            }
        }
        wsov.capturingLayout = savedCapturingLayout
    }

    func wsovCaptureWorkspaceLayouts() {
        var tags: UInt32 = 0
        for cell in wsov.cells {
            tags |= wsovTagBit(cell.tag)
        }
        wsovCaptureWorkspaceTags(tags)
    }

    /// mango wsov_render_client (offscreen_texture.c), what it draws: the window's frame and its content
    // not in mango: the content is the port's picture of the window, drawn for a live client too (no live
    // surfaces)
    func wsovRenderClient(_ cell: WsovCell, _ item: WsovItem, _ bufferScale: Double) -> WlrBuffer.Item? {
        guard let c = item.client else { return nil }
        let cellX = cell.box.x + wsovBorderWidth()
        let cellY = cell.box.y + wsovBorderWidth()
        let renderScaleX = item.renderScaleX * bufferScale
        let renderScaleY = item.renderScaleY * bufferScale
        let renderScale = fmin(renderScaleX, renderScaleY)
        let windowBox = WlrBox(
            x: lround(Double(item.box.x - cellX) * bufferScale),
            y: lround(Double(item.box.y - cellY) * bufferScale),
            width: lround(Double(item.box.width) * bufferScale),
            height: lround(Double(item.box.height) * bufferScale))

        let frameColor = !item.isSnapshot ? getBorderColor(c) : config.bordercolor
        let borderX = !item.isSnapshot && item.borderWidth > 0
            ? MANGO_MAX(1, lround(Double(item.borderWidth) * renderScaleX))
            : 0
        let borderY = !item.isSnapshot && item.borderWidth > 0
            ? MANGO_MAX(1, lround(Double(item.borderWidth) * renderScaleY))
            : 0

        if !item.isSnapshot && (windowBox.width <= 2 || windowBox.height <= 2) {
            return WlrBuffer.Item(client: c.windowID, box: windowBox.cgRect, borderX: Double(borderX),
                                  borderY: Double(borderY), borderColor: frameColor, picture: false)
        }

        if renderScale <= 0.0 {
            return WlrBuffer.Item(client: c.windowID, box: windowBox.cgRect, borderX: Double(borderX),
                                  borderY: Double(borderY), borderColor: frameColor, picture: false)
        }
        return WlrBuffer.Item(client: c.windowID, box: windowBox.cgRect, borderX: Double(borderX),
                              borderY: Double(borderY), borderColor: frameColor)
    }

    func wsovRenderCellLayerRange(_ cell: WsovCell, _ firstLayer: Int, _ endLayer: Int,
                                  _ bufferScale: Double) -> [WlrBuffer.Item] {
        var out: [WlrBuffer.Item] = []
        for layer in firstLayer..<endLayer {
            for item in cell.items {
                if item.layer.rawValue != layer ||
                    wsovDragHidesItem(cell, item.client) {
                    continue
                }
                if let drawn = wsovRenderClient(cell, item, bufferScale) {
                    out.append(drawn)
                }
            }
        }
        return out
    }

    func wsovCellHasLayerRange(_ cell: WsovCell, _ firstLayer: Int, _ endLayer: Int) -> Bool {
        for item in cell.items {
            if item.layer.rawValue >= firstLayer &&
                item.layer.rawValue < endLayer {
                return true
            }
        }
        return false
    }

    func wsovRenderCellPart(_ cell: WsovCell, _ target: WlrSceneBuffer?, _ firstLayer: Int, _ endLayer: Int,
                            _ bufferScale: Double) {
        guard let target else { return }
        if !wsovCellHasLayerRange(cell, firstLayer, endLayer) {
            wlrSceneBufferSetBuffer(target, nil)
            return
        }

        let bufferW = MANGO_MAX(1, lround(Double(cell.bufferW) * bufferScale))
        let bufferH = MANGO_MAX(1, lround(Double(cell.bufferH) * bufferScale))

        let background = RGBA(r: 0, g: 0, b: 0, a: 0)
        let items = wsovRenderCellLayerRange(cell, firstLayer, endLayer,
                                             bufferScale)

        wlrSceneBufferSetBuffer(target, WlrBuffer(width: bufferW, height: bufferH, background: background,
                                                  items: items))
        wlrSceneBufferSetSourceBox(target, nil)
        // not in mango: the buffer holds the live windows too, so it is placed at once as their surfaces would be
        wsovPlaceCellBuffer(cell, target)
    }

    /// Not in mango: wsov_apply_camera's placing of a cell's buffer, for one buffer.
    func wsovPlaceCellBuffer(_ cell: WsovCell, _ target: WlrSceneBuffer) {
        var view = WsovCameraView()
        if !wsovGetCameraView(wsov.progress, &view) {
            return
        }
        let cellBox = wsovCellLayoutBox(cell)
        let contentX = lround(
            (Double(cellBox.x + wsovBorderWidth()) - view.x) * view.scaleX)
        let contentY = lround(
            (Double(cellBox.y + wsovBorderWidth()) - view.y) * view.scaleY)
        let contentW = MANGO_MAX(
            1, lround(Double(MANGO_MAX(1, cellBox.width - 2 * wsovBorderWidth())) * view.scaleX))
        let contentH = MANGO_MAX(
            1, lround(Double(MANGO_MAX(1, cellBox.height - 2 * wsovBorderWidth())) * view.scaleY))
        wsovPlaceBufferClipped(target, nil, contentX, contentY, contentW, contentH)
    }

    func wsovPrepareCellForRender(_ cell: WsovCell?) {
        guard let cell, cell.capturePending, let m = wsov.mon else { return }
        wsovCaptureCellItems(cell)
        /* Only the active view owns the global tab projection. Other workspaces
         * retain their last complete strip snapshot. */
        if cell.tag == getMonCurtag(m) {
            wsovCaptureCellBars(cell)
        }
        wsovPositionCellItems(cell)
        cell.capturePending = false
        cell.contentsDirty = true
        cell.foregroundDirty = true
    }

    func wsovRenderCellRaw(_ cell: WsovCell?, _ bufferScale: Double) {
        guard let cell, cell.contents != nil, cell.foreground != nil, cell.bufferW > 0,
              cell.bufferH > 0 else {
            return
        }

        wsovRenderCellPart(cell, cell.contents, 0, Lyr.top.rawValue, bufferScale)
        wsovRenderCellPart(cell, cell.foreground, Lyr.top.rawValue, Lyr.block.rawValue + 1,
                           bufferScale)
        cell.contentsDirty = false
        cell.foregroundDirty = false
    }

    func wsovRenderCell(_ cell: WsovCell?, _ bufferScale: Double) -> Bool {
        guard let cell else { return false }
        if !wsovCellPreviewVisible(cell, wsov.progress) {
            cell.contentsDirty = true
            cell.foregroundDirty = true
            return false
        }
        wsovPrepareCellForRender(cell)
        wsovRenderCellRaw(cell, bufferScale)
        return true
    }

    func wsovRefreshAnimatedCells() -> Bool {
        if !workspaceOverviewIsActive() {
            return false
        }

        var anyAnimated = false
        for cell in wsov.cells {
            if !wsovCellLiveContentVisible(cell, wsov.progress) {
                if !cell.capturePending {
                    cell.capturePending = true
                    cell.contentsDirty = true
                    cell.foregroundDirty = true
                }
                continue
            }
            var animated = false

            for c in clients {
                if !wsovClientOnTag(c, cell.tag) {
                    continue
                }
                if c.animation.running || c.needOutputFlush {
                    animated = true
                    break
                }
            }
            if !animated {
                continue
            }

            cell.capturePending = true
            wsovPrepareCellForRender(cell)
            anyAnimated = true
        }
        return anyAnimated
    }

    func wsovRenderDirtyCells(_ applyCamera: Bool) -> Bool {
        var rendered = false
        for cell in wsov.cells {
            if !cell.contentsDirty && !cell.foregroundDirty {
                continue
            }
            if !wsovCellPreviewVisible(cell, wsov.progress) {
                continue
            }
            wsovPrepareCellForRender(cell)

            if cell.contentsDirty {
                wsovRenderCellPart(cell, cell.contents, 0, Lyr.top.rawValue,
                                   wsovOutputScale())
            }
            if cell.foregroundDirty {
                wsovRenderCellPart(cell, cell.foreground, Lyr.top.rawValue, Lyr.block.rawValue + 1,
                                   wsovOutputScale())
            }
            cell.contentsDirty = false
            cell.foregroundDirty = false
            rendered = true
        }

        if rendered && applyCamera {
            wsovApplyCamera(wsov.progress)
        }
        return rendered
    }

    func wsovFlushDirtyCells() {
        wsov.renderIdle = nil
        if !workspaceOverviewIsActive() || wsov.closing {
            return
        }
        if wsov.animating || wsov.layoutAnimating || wsov.scrollAnimating {
            return
        }
        _ = wsovRenderDirtyCells(true)
    }

    func wsovScheduleDirtyRender() {
        if wsov.animating || wsov.layoutAnimating || wsov.scrollAnimating {
            return
        }
        if wsov.renderIdle != nil {
            return
        }
        wsov.renderIdle = system.eventLoop.addIdle { [weak self] in self?.wsovFlushDirtyCells() }
        if wsov.renderIdle == nil {
            wsovFlushDirtyCells()
        }
    }

    func wsovCancelScheduledRender() {
        guard let idle = wsov.renderIdle else { return }
        idle.remove()
        wsov.renderIdle = nil
    }

    func wsovRenderAll() {
        let bufferScale = wsovOutputScale()
        for cell in wsov.cells {
            _ = wsovRenderCell(cell, bufferScale)
        }
    }

    func wsovRenderTags(_ tags: UInt32) {
        let bufferScale = wsovOutputScale()
        for cell in wsov.cells where tags & wsovTagBit(cell.tag) != 0 {
            _ = wsovRenderCell(cell, bufferScale)
        }
    }
}
