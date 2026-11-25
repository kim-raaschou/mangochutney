import CoreGraphics
import Foundation

// not in mango: no unmanaged or X11 clients (client_is_unmanaged, client_is_x11_popup), no swallowing, and
// no fade-out clients (the close animation is macOS's); every Client has a mapped surface

extension MangoServer {
    func wsovTagBit(_ tag: UInt32) -> UInt32 {
        if tag < 1 || tag > UInt32(config.tagNum) {
            return 0
        }
        return 1 << (tag - 1)
    }

    func wsovClientTags(_ c: Client?) -> UInt32 {
        guard let c else { return 0 }
        return c.isglobal ? TAGMASK : (c.tags & TAGMASK)
    }

    func wsovCellTagsForClient(_ c: Client?) -> UInt32 {
        var tags: UInt32 = 0
        guard let c else { return tags }
        for cell in wsov.cells {
            for item in cell.items where item.client === c {
                tags |= wsovTagBit(cell.tag)
                break
            }
        }
        return tags
    }

    func wsovLayoutAffectedTags(_ m: Monitor) -> UInt32 {
        var activeTags = m.tagset[m.seltags] & TAGMASK
        if activeTags == 0 {
            activeTags = wsovTagBit(getMonCurtag(m))
        }
        /*
         * client_view_on_monitor() toggles seltags, so the inactive set is the
         * view we just left. Include both sides as well as pertag history: moving a
         * client can change the layout of the source workspace without changing
         * the destination workspace membership.
         */
        let previousTags = m.tagset[m.seltags ^ 1] & TAGMASK
        var tags = activeTags | previousTags |
            wsovTagBit(m.pertag.curtag) |
            wsovTagBit(m.pertag.prevtag)
        for c in clients {
            if c.mon !== m || c.iskilling {
                continue
            }
            if c.isglobal || c.tags & (activeTags | previousTags) != 0 {
                tags |= wsovClientTags(c)
            }
        }
        return tags
    }

    func wsovClientBaseEligible(_ c: Client?) -> Bool {
        guard let c, let cm = c.mon, cm === wsov.mon, !c.iskilling, !c.isminimized,
              !c.isunglobal, c.tags & TAG0_MASK == 0 else {
            return false
        }
        return true
    }

    func wsovClientEligible(_ c: Client?) -> Bool {
        wsovClientBaseEligible(c) && !c!.isTabHidden
    }

    func workspaceOverviewActiveWorkspaceWillEmpty(_ c: Client?) -> Bool {
        guard workspaceOverviewIsActive(), let c, let m = wsov.mon, c.mon === m else {
            return false
        }

        let active = m.tagset[m.seltags] & TAGMASK
        if c.tags & active == 0 {
            return false
        }

        for other in clients {
            if other === c || !wsovClientEligible(other) {
                continue
            }
            if other.isglobal || other.tags & active != 0 {
                return false
            }
        }
        return true
    }

    func wsovClientOnTag(_ c: Client?, _ tag: UInt32) -> Bool {
        if !wsovClientBaseEligible(c) ||
            (wsov.mon?.isWsOverview == true &&
             tabClientHiddenOnTag(wsov.mon, tag, c)) {
            return false
        }
        if c!.isglobal {
            return true
        }
        let bit = wsovTagBit(tag)
        return bit != 0 && c!.tags & bit != 0
    }

    func wsovFocusTopForTag(_ tag: UInt32) -> Client? {
        for c in focusStack {
            if wsovClientOnTag(c, tag) {
                return c
            }
        }
        return nil
    }

    func wsovSyncMonitorSelection() {
        guard let m = wsov.mon, wsov.targetTag != 0 else { return }
        guard let top = wsovFocusTopForTag(wsov.targetTag) else { return }
        if m.sel !== top || !top.isfocusing {
            clientFocus(top, false)
        }
        if m.sel !== top {
            m.sel = top
        }
    }

    func wsovTagHasNormalClient(_ tag: UInt32) -> Bool {
        let bit = wsovTagBit(tag)
        if bit == 0 {
            return false
        }

        for c in clients {
            if wsovClientEligible(c) && !c.isglobal && c.tags & bit != 0 {
                return true
            }
        }
        return false
    }

    func wsovCollectWorkspaceTags(_ m: Monitor?, _ count: inout Int) -> UInt32 {
        var mask: UInt32 = 0
        var n = 0

        guard let m else {
            count = 0
            return 0
        }

        if m.workspaceOverviewScope == ALL_WORKSPACE {
            count = config.tagNum
            return (UInt32(1) << UInt32(config.tagNum)) - 1
        }

        for tag in stride(from: 1, through: config.tagNum, by: 1) {
            let bit = wsovTagBit(UInt32(tag))
            if wsovTagHasNormalClient(UInt32(tag)) ||
                (config.workspaceOverviewOccupiedKeepSeenTags != 0 &&
                 wsov.retainedTags & bit != 0) {
                mask |= wsovTagBit(UInt32(tag))
                n += 1
            }
        }
        count = n
        return mask
    }

    func wsovCellForTag(_ tag: UInt32) -> WsovCell? {
        for cell in wsov.cells where cell.tag == tag {
            return cell
        }
        return nil
    }

    func wsovSelectDefaultTarget() {
        if wsov.cells.count <= 0 {
            wsov.targetTag = 0
            return
        }
        if wsovCellForTag(wsov.targetTag) != nil {
            return
        }

        let previousTarget = wsov.targetTag
        /*
         * The target workspace itself was removed. Continue to the nearest
         * following occupied workspace; when there is none, use the nearest
         * preceding one instead of jumping back to the first workspace.
         */
        if previousTarget != 0 {
            for cell in wsov.cells where cell.tag > previousTarget {
                wsov.targetTag = cell.tag
                return
            }
            for cell in wsov.cells.reversed() where cell.tag < previousTarget {
                wsov.targetTag = cell.tag
                return
            }
        }

        let active = wsov.mon!.tagset[wsov.mon!.seltags] & TAGMASK
        for cell in wsov.cells where active & wsovTagBit(cell.tag) != 0 {
            wsov.targetTag = cell.tag
            return
        }
        wsov.targetTag = wsov.cells[0].tag
    }

    func wsovSetTargetFromPoint(_ x: Double, _ y: Double) -> Bool {
        var cell = wsovHitCellAt(x, y)
        if cell == nil {
            cell = wsovDropCellAt(x, y)
        }
        guard let cell, cell.tag != wsov.targetTag else { return false }

        wsov.targetTag = cell.tag
        wsov.cameraTag = cell.tag
        return true
    }

    func wsovSettleTagAnimations(_ m: Monitor, _ tags: UInt32) {
        for c in clients {
            if c.mon !== m || c.iskilling {
                continue
            }
            if !c.isglobal && c.tags & tags == 0 {
                continue
            }
            if !c.animation.tagining && !c.animation.tagouting &&
                c.animation.action != .tag {
                continue
            }
            c.animation.running = false
            c.animation.tagining = false
            c.animation.tagouting = false
            c.animation.tagouted = false
            c.needOutputFlush = false
            clientSetFinishGeometry(c)
            clientUpdateVisibility(c)
        }
    }

    func wsovCellHasClient(_ cell: WsovCell, _ client: Client?) -> Bool {
        guard let client else { return false }
        for item in cell.items where item.client === client {
            return true
        }
        return false
    }

    func wsovRenderSelectionClients(_ previous: Client?, _ current: Client?) {
        if previous === current {
            return
        }
        for cell in wsov.cells {
            if wsovCellHasClient(cell, previous) ||
                wsovCellHasClient(cell, current) {
                _ = wsovRenderCell(cell, wsovOutputScale())
            }
        }
    }

    func wsovApplyTargetSelection(_ activateView: Bool) {
        guard let m = wsov.mon, !wsov.closing else { return }
        let previous = m.sel
        let previousLiveCell = wsov.liveCell
        if activateView {
            wsovActivateTargetTag()
        }
        wsovSyncMonitorSelection()
        if wsov.liveCell == nil || wsov.liveCell!.tag != wsov.targetTag {
            wsovRebuildLiveProjection()
        } else {
            wsovLayoutLiveProjection()
        }
        /*
         * The old live cell needs its complete off-screen copy immediately after
         * the live projection moves. Focusing the same client (notably a floating
         * global window) makes the selection diff empty, so it cannot be relied on
         * to repaint that cell. Repaint both sides before the scroll animation
         * advances to avoid a one-frame gap in either preview.
         */
        if let previousLiveCell {
            _ = wsovRenderCell(previousLiveCell, wsovOutputScale())
        }
        if let live = wsov.liveCell, live !== previousLiveCell {
            _ = wsovRenderCell(live, wsovOutputScale())
        }
        wsovRenderSelectionClients(previous, wsov.mon?.sel)
        wsovUpdateStyles()
        wsovApplyCamera(wsov.progress)
    }

    func wsovRefreshTargetSelection() { wsovApplyTargetSelection(true) }

    func wsovActiveCameraTag() -> UInt32 {
        guard let m = wsov.mon else { return 0 }
        let current = getMonCurtag(m)
        if wsovCellForTag(current) != nil {
            return current
        }

        let active = m.tagset[m.seltags] & TAGMASK
        for cell in wsov.cells {
            let tag = cell.tag
            if active & wsovTagBit(tag) != 0 {
                return tag
            }
        }
        return 0
    }

    func wsovTargetCell() -> WsovCell? {
        wsovCellForTag(wsov.targetTag)
    }

    func wsovSelectDirection(_ dirX: Int, _ dirY: Int) {
        guard let current = wsovTargetCell(), wsov.cells.count > 1 else { return }

        let currentBox = wsovCellLayoutBox(current)
        let currentL = currentBox.x
        let currentR = currentBox.x + currentBox.width
        let currentT = currentBox.y
        let currentB = currentBox.y + currentBox.height
        let currentCx = currentL + currentBox.width / 2
        let currentCy = currentT + currentBox.height / 2

        var target: WsovCell?
        var bestDistance = Int64.max
        var bestCenterDistance = Int64.max
        for cell in wsov.cells {
            if cell === current {
                continue
            }

            let box = wsovCellLayoutBox(cell)
            let left = box.x
            let right = box.x + box.width
            let top = box.y
            let bottom = box.y + box.height
            let centerX = left + box.width / 2
            let centerY = top + box.height / 2
            var mainDistance: Int64 = 0
            var orthDistance: Int64 = 0
            var matchDirection = false

            if dirX < 0 {
                if centerX < currentCx ||
                    (centerX == currentCx && left < currentL) {
                    matchDirection = true
                    mainDistance = Int64(currentL - right)
                    orthDistance = Int64(bottom < currentT
                        ? currentT - bottom
                        : (top > currentB ? top - currentB : 0))
                }
            } else if dirX > 0 {
                if centerX > currentCx ||
                    (centerX == currentCx && left > currentL) {
                    matchDirection = true
                    mainDistance = Int64(left - currentR)
                    orthDistance = Int64(bottom < currentT
                        ? currentT - bottom
                        : (top > currentB ? top - currentB : 0))
                }
            } else if dirY < 0 {
                if centerY < currentCy ||
                    (centerY == currentCy && top < currentT) {
                    matchDirection = true
                    mainDistance = Int64(currentT - bottom)
                    orthDistance = Int64(right < currentL
                        ? currentL - right
                        : (left > currentR ? left - currentR : 0))
                }
            } else if dirY > 0 {
                if centerY > currentCy ||
                    (centerY == currentCy && top > currentT) {
                    matchDirection = true
                    mainDistance = Int64(top - currentB)
                    orthDistance = Int64(right < currentL
                        ? currentL - right
                        : (left > currentR ? left - currentR : 0))
                }
            }
            if !matchDirection {
                continue
            }

            let orthOverlap = dirX != 0 ? (bottom >= currentT && top <= currentB)
                : (right >= currentL && left <= currentR)
            if config.focusdirOnlyZoneOverlap && !orthOverlap {
                continue
            }

            var penalty: Int64 = 0
            if mainDistance < 0 {
                penalty = 10000000000
                mainDistance = -mainDistance
            }
            let distance = penalty + mainDistance * mainDistance +
                orthDistance * orthDistance
            let centerDistance = dirY != 0 ? abs(Int64(centerX) - Int64(currentCx))
                : abs(Int64(centerY) - Int64(currentCy))
            if distance < bestDistance ||
                (distance == bestDistance &&
                 centerDistance < bestCenterDistance) {
                bestDistance = distance
                bestCenterDistance = centerDistance
                target = cell
            }
        }

        guard let target else { return }

        wsov.targetTag = target.tag
        wsov.scrollCenterTag = target.tag
        wsov.cameraTag = wsov.targetTag
        wsovAnimateScrollToTarget()
        wsovRefreshTargetSelection()
    }

    func wsovActivateTargetTag() {
        guard workspaceOverviewIsActive(), !wsov.closing, let m = wsov.mon,
              wsov.targetTag != 0 else {
            return
        }
        let targetBit = wsovTagBit(wsov.targetTag)
        if targetBit == 0 ||
            m.tagset[m.seltags] & TAGMASK == targetBit {
            return
        }
        clientViewOnMonitor(Arg(ui: targetBit), false, m, true)
    }
}
