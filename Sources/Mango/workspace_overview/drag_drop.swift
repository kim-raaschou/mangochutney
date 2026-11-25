import CoreGraphics
import Foundation

extension MangoServer {
    func wsovCreateDropIndicator() -> Bool {
        guard let root = wsov.root else { return false }

        let dropFill = wlrSceneRectCreate(root, 1, 1, RGBA(r: 0, g: 0, b: 0, a: 0))
        wsov.dropFill = dropFill
        wsovSetRectColor(dropFill, config.dropcolor)
        wsovHideDropIndicator()
        return true
    }

    func wsovDragHidesItem(_ cell: WsovCell, _ c: Client?) -> Bool {
        wsov.moved && wsov.hasDragClient && c === wsov.dragClient &&
            cell.tag == wsov.sourceTag
    }

    func wsovDragHidesGroup(_ cell: WsovCell, _ groupHead: Client?) -> Bool {
        if !wsov.moved || !wsov.hasDragClient || groupHead == nil ||
            cell.tag != wsov.sourceTag {
            return false
        }
        var cur = groupHead
        while let c = cur {
            if c === wsov.dragClient {
                return true
            }
            cur = c.groupNext
        }
        return false
    }

    func wsovDestroyDragBuffer() {
        if let dragBuffer = wsov.dragBuffer {
            wlrSceneNodeDestroy(dragBuffer)
            wsov.dragBuffer = nil
        }
        wsov.dragWidth = 0
        wsov.dragHeight = 0
        wsov.dragBarHeight = 0
        wsov.dragSourceWidth = 0
        wsov.dragSourceHeight = 0
        wsov.dragPreviewX = 0
        wsov.dragPreviewY = 0
    }

    func wsovBeginDragFloating(_ c: Client?) {
        guard let c, !wsov.dragFloatingChanged else { return }

        wsov.dragWasFloating = c.isfloating
        wsov.dragWasDragToTile = c.dragToTile
        wsov.dragSavedFloatGeom = c.floatGeom
        if c.isfloating {
            return
        }
        /* The drag itself must not clear fullscreen/maximized. Leave that decision
         * to the normal arrange path after the window is dropped on its target. */
        if c.isfullscreen || c.ismaximizescreen {
            return
        }

        /* Match the normal move-drag path: a tiled window leaves the tiling model
         * as soon as the drag starts, then returns to it on drop or cancel. */
        c.dragToTile = true
        exitScrollerStack(c)
        clientSetFloating(c, true, false)
        c.oldStackInnerPer = 0.0
        c.oldMasterInnerPer = 0.0
        if let m = c.mon { setSizePer(m, c, resetProportion: false) }
        wsov.dragFloatingChanged = true
    }

    func wsovRestoreDragFloating() {
        if wsov.dragFloatingChanged, let c = wsov.dragClient {
            c.floatGeom = wsov.dragSavedFloatGeom
            c.dragToTile = wsov.dragWasDragToTile
            if c.mon != nil && c.isfloating {
                clientSetFloating(c, false, false)
            } else {
                c.isfloating = false
            }
        }
        wsov.dragFloatingChanged = false
        wsov.dragWasFloating = false
        wsov.dragWasDragToTile = false
        wsov.dragSavedFloatGeom = .zero
    }

    func wsovCaptureDragGroupBars(_ c: Client?) -> Bool {
        // not in mango: no bar nodes; the port draws the group bars
        return false
    }

    // not in mango: the window is drawn into the buffer as the port's picture (no GL render pass), and
    // no group bar strip above it (the port draws the bars)
    func wsovCreateDragBuffer(_ item: WsovItem?) -> Bool {
        wsovDestroyDragBuffer()
        guard let item, item.box.width > 0, item.box.height > 0, let root = wsov.root else {
            return false
        }

        let width = item.client?.isfloating == true
            ? MANGO_MAX(1, item.box.width)
            : MANGO_MIN(item.box.width, 900)
        let workspaceWidth =
            MANGO_MAX(1, item.workspaceGeom.width > 0 ? item.workspaceGeom.width
                : item.box.width)
        let workspaceHeight = MANGO_MAX(1, item.workspaceGeom.height > 0
            ? item.workspaceGeom.height
            : item.box.height)
        let outputScale = wsovOutputScale()
        let renderScale = Double(width) / Double(workspaceWidth)
        let windowHeight =
            MANGO_MAX(1, lround(Double(workspaceHeight) * renderScale))
        var barHeight = 0
        if wsovCaptureDragGroupBars(item.client) {
            barHeight =
                MANGO_MAX(1, lround(Double(config.groupBarHeight) * renderScale))
        }
        let height = barHeight + windowHeight
        let bufferWidth = MANGO_MAX(1, lround(Double(width) * outputScale))
        let bufferHeight = MANGO_MAX(1, lround(Double(height) * outputScale))

        let background = RGBA(r: config.rootcolor.r, g: config.rootcolor.g,
                              b: config.rootcolor.b, a: 1.0)
        var items: [WlrBuffer.Item] = []
        if let client = item.client {
            items.append(WlrBuffer.Item(client: client.windowID, box: CGRect(
                x: 0, y: Double(barHeight) * outputScale,
                width: Double(width) * outputScale, height: Double(windowHeight) * outputScale)))
        }
        let buffer = WlrBuffer(width: bufferWidth, height: bufferHeight, background: background, items: items)

        let dragBuffer = wlrSceneBufferCreate(root, buffer)
        wsov.dragBuffer = dragBuffer
        wlrSceneBufferSetDestSize(dragBuffer, width, height)
        wlrSceneNodeRaiseToTop(dragBuffer)
        wsov.dragBarHeight = barHeight
        wsov.dragWidth = width
        wsov.dragHeight = height
        wsov.dragSourceWidth = item.box.width
        wsov.dragSourceHeight = item.box.height
        return true
    }

    func wsovCancelDrag() {
        let hadDrag =
            wsov.pressed || wsov.moved || wsov.hasDragClient || wsov.dragBuffer != nil
        let returnTag = wsov.dragReturnTag
        wsovHideDropIndicator()
        wsovRestoreDragFloating()
        wsovDestroyDragBuffer()
        wsov.pressed = false
        wsov.moved = false
        wsov.hasDragClient = false
        wsov.dragScrollDirection = 0
        wsov.dragScrollFrameValid = false
        wsov.dragClient = nil
        wsov.sourceTag = 0
        wsov.dragReturnTag = 0
        if hadDrag && returnTag != 0 {
            wsov.targetTag = returnTag
            wsov.cameraTag = returnTag
        }
        if wsov.mon != nil && !cursorHidden {
            system.setCursor("default")
        }
    }

    func wsovItemIsDropTarget(_ item: WsovItem?) -> Bool {
        guard let item, !item.isSnapshot, let client = item.client else { return false }
        return client !== wsov.dragClient && ISTILED(client)
    }

    func wsovCellTilingCount(_ cell: WsovCell?) -> Int32 {
        var count: Int32 = 0
        guard let cell else { return 0 }
        for item in cell.items {
            if !item.isSnapshot && item.client !== wsov.dragClient &&
                ISTILED(item.client) {
                count += 1
            }
        }
        return count
    }

    func wsovDropItemAt(_ cell: WsovCell?, _ x: Double, _ y: Double) -> WsovItem? {
        let hit = wsovItemAt(cell, x, y)
        if wsovItemIsDropTarget(hit) {
            return hit
        }
        guard let cell, let m = wsov.mon else { return nil }

        var nearest: WsovItem?
        var best = 1e30
        let lx = x - m.m.minX
        let ly = y - m.m.minY
        for item in cell.items {
            if !wsovItemIsDropTarget(item) {
                continue
            }
            let box = wsovItemDisplayBox(cell, item)
            let cx = Double(box.x) + Double(box.width) / 2.0
            let cy = Double(box.y) + Double(box.height) / 2.0
            let distance = (cx - lx) * (cx - lx) + (cy - ly) * (cy - ly)
            if distance < best {
                best = distance
                nearest = item
            }
        }
        return nearest
    }

    func wsovGetDropTarget(_ x: Double, _ y: Double, _ cellOut: inout WsovCell?,
                           _ itemOut: inout WsovItem?, _ zoneOut: inout WlrBox,
                           _ directionOut: inout Int32) -> Bool {
        guard let cell = wsovDropCellAt(x, y), let m = wsov.mon, wsov.dragClient != nil,
              !wsov.dragWasFloating else {
            return false
        }

        guard let item = wsovDropItemAt(cell, x, y), let client = item.client else {
            return false
        }

        let layout = m.pertag.ltidxs[Int(cell.tag)]
        let itemBox = wsovItemFinalDisplayBox(cell, item)
        if itemBox.width <= 0 || itemBox.height <= 0 {
            return false
        }
        let relX = x - m.m.minX - Double(itemBox.x)
        let relY = y - m.m.minY - Double(itemBox.y)
        var zone = (x: Int32(0), y: Int32(0), width: Int32(0), height: Int32(0))
        let direction = clientDropZone(
            layout, client.ismaster, wsovCellTilingCount(cell), relX,
            relY, Int32(itemBox.width), Int32(itemBox.height), &zone)
        zone.x += Int32(itemBox.x)
        zone.y += Int32(itemBox.y)
        client.dropDirection = direction

        cellOut = cell
        itemOut = item
        zoneOut = WlrBox(Int(zone.x), Int(zone.y), Int(zone.width), Int(zone.height))
        directionOut = direction
        return true
    }

    func wsovHideDropIndicator() {
        wsov.dropIndicatorVisible = false
        if let dropFill = wsov.dropFill {
            wlrSceneNodeSetEnabled(dropFill, false)
        }
    }

    func wsovUpdateDropIndicator(_ x: Double, _ y: Double) {
        var cell: WsovCell?
        var item: WsovItem?
        var zone = WlrBox()
        var direction: Int32 = 0
        if !wsovGetDropTarget(x, y, &cell, &item, &zone, &direction) ||
            zone.width <= 0 || zone.height <= 0 {
            wsovHideDropIndicator()
            return
        }
        guard let cell else { return }

        if cell.tag != wsov.targetTag {
            wsov.targetTag = cell.tag
            wsov.cameraTag = cell.tag
            wsovRefreshTargetSelection()
        }

        let width = MANGO_MAX(1, zone.width)
        let height = MANGO_MAX(1, zone.height)
        wsovPlaceRectClipped(wsov.dropFill, zone.x, zone.y, width, height,
                             true)
        guard let dropFill = wsov.dropFill else { return }

        wsov.dropIndicatorVisible = true

        wlrSceneNodeRaiseToTop(dropFill)
        if let dragBuffer = wsov.dragBuffer {
            wlrSceneNodeRaiseToTop(dragBuffer)
        }
    }

    func wsovPlaceFloating(_ c: Client?, _ cell: WsovCell?) {
        guard let c, let cell, let m = wsov.mon else { return }
        let width = MANGO_MAX(64, c.floatGeom.width > 0 ? c.floatGeom.width
            : c.geom.width)
        let height = MANGO_MAX(64, c.floatGeom.height > 0 ? c.floatGeom.height
            : c.geom.height)
        let cellBox = wsovCellLayoutBox(cell)
        let scaleX = m.m.width /
            Double(MANGO_MAX(1, cellBox.width - 2 * wsovBorderWidth()))
        let scaleY = m.m.height /
            Double(MANGO_MAX(1, cellBox.height - 2 * wsovBorderWidth()))
        let cameraCell = wsovCellForTag(wsov.cameraTag) ?? cell
        let cameraBox = wsovCellLayoutBox(cameraCell)
        let progress = fmax(0.0, fmin(1.0, wsov.progress))
        let finalViewportX =
            wsovScrollsHorizontally() ? wsov.scrollOffset : 0.0
        let finalViewportY =
            wsovScrollsVertically() ? wsov.scrollOffset : 0.0
        let border = Double(wsovBorderWidth())
        let viewportX =
            Double(cameraBox.x) + border +
            (finalViewportX - Double(cameraBox.x) - border) * progress
        let viewportY =
            Double(cameraBox.y) + border +
            (finalViewportY - Double(cameraBox.y) - border) * progress
        var viewportW =
            Double(MANGO_MAX(1, cameraBox.width - 2 * wsovBorderWidth()))
        var viewportH =
            Double(MANGO_MAX(1, cameraBox.height - 2 * wsovBorderWidth()))
        viewportW += (m.m.width - viewportW) * progress
        viewportH += (m.m.height - viewportH) * progress
        let cameraScaleX =
            m.m.width / MANGO_MAX(1.0, viewportW)
        let cameraScaleY =
            m.m.height / MANGO_MAX(1.0, viewportH)
        let previewStripX =
            viewportX + Double(wsov.dragPreviewX) / cameraScaleX
        let previewStripY =
            viewportY +
            Double(wsov.dragPreviewY + wsov.dragBarHeight) / cameraScaleY
        let contentX = previewStripX - Double(cellBox.x) - border
        let contentY = previewStripY - Double(cellBox.y) - border
        let nx = Int(m.m.minX) + lround(contentX * scaleX)
        let ny = Int(m.m.minY) + lround(contentY * scaleY)
        c.floatGeom = CGRect(x: nx, y: ny, width: Int(width), height: Int(height))
        resize(c, c.floatGeom,
               ResizeOpts(interact: false, skipAnimation: true))
    }

    func wsovFinishDrop(_ x: Double, _ y: Double) {
        let c = wsov.dragClient
        guard let c, var target = wsovDropCellAt(x, y), wsovClientEligible(c), let m = wsov.mon else {
            let tags = wsovClientTags(c) | wsovTagBit(wsov.sourceTag)
            wsovCancelDrag()
            wsovRefreshWorkspaceOrRebuild(tags)
            return
        }

        var over: WsovItem?
        var targetOut: WsovCell? = target
        var zone = WlrBox()
        var direction: Int32 = 0
        _ = wsovGetDropTarget(x, y, &targetOut, &over, &zone, &direction)
        if let targetOut { target = targetOut }
        let wasFloating = wsov.dragWasFloating

        let sourceBit = wsovTagBit(wsov.sourceTag)
        let targetBit = wsovTagBit(target.tag)
        let oldTags = c.isglobal ? 0 : c.tags
        let mods = system.keyboardHardModifiers()

        if !c.isglobal && target.tag != wsov.sourceTag {
            if mods.contains(.ctrl) {
                c.tags = targetBit
            } else if mods.contains(.shift) {
                c.tags |= targetBit
            } else {
                c.tags = (c.tags & ~sourceBit) | targetBit
            }
            c.tags &= TAGMASK
            if c.tags == 0 {
                c.tags = targetBit
            }
            // not in mango: client_reparent_group (no macOS part)
        }
        clearFullscreenForIncomingTiledClient(c)

        clientViewOnMonitor(Arg(ui: targetBit), false, m, false)
        if let over {
            pointerPlaceDragTileOn(c, over.client)
        }
        if wasFloating {
            wsovPlaceFloating(c, target)
        }

        wsovRestoreDragFloating()
        clientFocus(c, true)
        arrange(m, false, false)

        wsovHideDropIndicator()
        wsov.pressed = false
        wsov.moved = false
        wsov.hasDragClient = false
        wsov.dragScrollDirection = 0
        wsov.dragScrollFrameValid = false
        wsov.dragClient = nil
        wsov.sourceTag = 0
        wsov.targetTag = target.tag
        wsov.scrollCenterTag = target.tag
        wsov.cameraTag = target.tag
        wsovAnimateScrollToTarget()
        wsov.dragReturnTag = 0
        wsovDestroyDragBuffer()
        if !cursorHidden {
            system.setCursor("default")
        }
        var affectedTags = sourceBit | targetBit
        if c.isglobal {
            affectedTags |= TAGMASK
        } else {
            affectedTags |= oldTags | c.tags
        }
        wsovRefreshWorkspaceOrRebuild(affectedTags)
    }
}
