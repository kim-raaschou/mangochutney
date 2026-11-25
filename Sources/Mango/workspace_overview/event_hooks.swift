import CoreGraphics
import Foundation

// not in mango: no layer shell (workspace_overview_layers_changed, workspace_overview_layer_fadeout_parent),
// no opacity animations (macOS cannot set another app's opacity)

extension MangoServer {
    /// Not in mango: clock_gettime(CLOCK_MONOTONIC) in milliseconds, the port's clock (getNowInMs).
    func wsovNowMs() -> Double { Double(getNowInMs()) }

    func wsovElapsedMs(_ start: Double) -> Double {
        wsovNowMs() - start
    }

    func wsovProcessFrame() {
        if !workspaceOverviewIsActive() {
            return
        }

        if wsov.layersDirty {
            wsov.layersDirty = false
            if let root = wsov.root { wlrSceneNodeRaiseToTop(root) }
            // not in mango: no direct layer trees or layer previews (no layer shell)
        }

        let clientAnimating = wsovRefreshAnimatedCells()
        let clientAnimationFinished = wsov.clientAnimating && !clientAnimating
        wsov.clientAnimating = clientAnimating
        wsovFlushLiveLayout()
        if clientAnimationFinished {
            for cell in wsov.cells {
                if !wsovCellLiveContentVisible(cell, wsov.progress) {
                    cell.capturePending = true
                    cell.contentsDirty = true
                    cell.foregroundDirty = true
                    continue
                }
                wsovCaptureCellItems(cell)
                wsovPositionCellItems(cell)
                cell.capturePending = false
                cell.contentsDirty = true
                cell.foregroundDirty = true
            }
        }

        if !config.animations {
            wsov.layoutAnimating = false
            if wsov.scrollAnimating {
                wsov.scrollOffset = wsov.scrollAnimationTo
            }
            wsov.scrollAnimating = false
            wsov.progress = wsov.animationTo
            wsov.animating = false
            if wsov.closing {
                wsovApplyCamera(wsov.progress)
                wsovFinalizeClose(wsov.closeTag)
                return
            }
            wsovScheduleDirtyRender()
        }

        let dragScrolling = wsov.pressed && wsov.moved && wsov.hasDragClient &&
            wsov.dragScrollDirection != 0
        if !wsov.layoutAnimating && !wsov.scrollAnimating && !wsov.animating &&
            !dragScrolling && !clientAnimating && !clientAnimationFinished {
            wsovScheduleDirtyRender()
            wsovDetachFrameListener()
            return
        }

        if wsov.layoutAnimating {
            wsovUpdateLayoutAnimation()
        }
        if wsov.scrollAnimating {
            wsovUpdateScrollAnimation()
        }
        if dragScrolling {
            _ = wsovAdvanceDragScroll()
        }

        if wsov.animating {
            let curve = wsov.closing
                ? config.animationCurveWsovClose
                : config.animationCurveWsovOpen
            let duration = animationCurveDurationMs(
                curve, UInt32(wsov.closing ? config.animationDurationWsovClose
                    : config.animationDurationWsovOpen))
            var t = wsovElapsedMs(wsov.animationStart) /
                MANGO_MAX(1.0, Double(duration))
            t = fmax(0.0, fmin(1.0, t))
            let eased = animationCurveEase(curve, t)
            wsov.progress = wsov.animationFrom +
                (wsov.animationTo - wsov.animationFrom) * eased
            if t >= 1.0 {
                wsov.progress = wsov.animationTo
                wsov.animating = false
            }
        }

        _ = wsovRenderDirtyCells(false)
        wsovApplyCamera(wsov.progress)
        if !wsov.animating && wsov.closing {
            wsovFinalizeClose(wsov.closeTag)
        } else if !wsov.layoutAnimating && !wsov.scrollAnimating &&
            !wsov.animating && !dragScrolling && !clientAnimating {
            wsovScheduleDirtyRender()
            wsovDetachFrameListener()
        }
    }

    func wsovHandleFrame() {
        if wsov.closing {
            return
        }
        wsovProcessFrame()
    }

    func wsovAttachFrameListener() {
        guard let m = wsov.mon else { return }
        if wsov.frameActive {
            return
        }
        wsov.frameActive = true
        system.outputScheduleFrame(m)
    }

    func wsovDetachFrameListener() {
        wsov.frameActive = false
    }

    func workspaceOverviewPrepareOutputFrame(_ m: Monitor) {
        if !workspaceOverviewIsActiveOn(m) {
            return
        }
        if wsov.frameActive && wsov.closing {
            wsovProcessFrame()
            return
        }
        wsovFlushLiveLayout()
    }

    /// mango workspace_overview_client_commit (event_hooks.c)
    // not in mango: never called, the port has no client commits (handle_client_commit)
    func workspaceOverviewClientCommit(_ c: Client) {
        if !workspaceOverviewIsActive() || c.mon !== wsov.mon {
            return
        }
        let currentLayer = clientTargetLayer(c)
        for cell in wsov.cells {
            if !wsovClientOnTag(c, cell.tag) {
                continue
            }

            var found = false
            for item in cell.items {
                if item.client !== c {
                    continue
                }
                found = true
                if wsovItemIsLive(cell, item) {
                    break
                }
                if item.layer < .top || currentLayer < .top {
                    cell.contentsDirty = true
                }
                if item.layer >= .top || currentLayer >= .top {
                    cell.foregroundDirty = true
                }
                break
            }
            if !found {
                cell.contentsDirty = true
                cell.foregroundDirty = true
            }
        }
        wsovMarkLiveLayoutDirty()
        wsovScheduleDirtyRender()
        if c.isPendingOpenAnimation || c.needOutputFlush ||
            c.animation.running {
            wsov.clientAnimating = true
            wsovAttachFrameListener()
        }
    }

    func workspaceOverviewClientFrame(_ c: Client?) {
        guard workspaceOverviewIsActive(), let c, c.mon === wsov.mon else { return }
        wsovMarkLiveLayoutDirty()
    }

    func workspaceOverviewClientAdded(_ c: Client?) {
        guard workspaceOverviewIsActive(), let c, c.mon === wsov.mon else { return }
        c.wsovHidden = true
        clientUpdateVisibility(c)
        system.seatPointerClearFocus()
        system.keyboardNotifyClearFocus()
        wsovRefreshWorkspaceOrRebuild(wsovClientTags(c))
        if !wsov.closing && workspaceOverviewIsActive() {
            wsovRebuildLiveProjection()
            wsovRenderTags(wsovTagBit(wsov.targetTag))
        }
        if !wsov.closing && workspaceOverviewIsActive() &&
            (c.isPendingOpenAnimation || c.needOutputFlush ||
             c.animation.running) {
            wsov.clientAnimating = true
            wsovAttachFrameListener()
        }
    }

    func workspaceOverviewClientRemoved(_ c: Client?) {
        guard workspaceOverviewIsActive(), let c, c.mon === wsov.mon else { return }
        if c === wsov.closeClient {
            wsov.closeClient = nil
        }
        if c === wsov.dragClient {
            wsovCancelDrag()
        }
        c.wsovHidden = false
        wsovRefreshWorkspaceOrRebuild(wsovClientTags(c))
        if !wsov.closing && workspaceOverviewIsActive() {
            wsovRebuildLiveProjection()
            wsovRenderTags(wsovTagBit(wsov.targetTag))
        }
    }

    func workspaceOverviewClientReplaced(_ old: Client?, _ new: Client?) {
        guard workspaceOverviewIsActive(), let old, let new, old !== new else { return }
        if wsov.dragClient === old {
            wsov.dragClient = new
        }
        if wsov.closeClient === old {
            wsov.closeClient = new
        }
    }

    func workspaceOverviewClientTagsChanged(_ c: Client?) {
        guard workspaceOverviewIsActive(), !wsov.closing, let c, c.mon === wsov.mon else { return }
        let oldTags = wsovCellTagsForClient(c)
        let newTags = wsovClientTags(c)
        wsovRefreshWorkspaceOrRebuild(oldTags | newTags)
        if !wsov.closing && workspaceOverviewIsActive() {
            wsovRebuildLiveProjection()
            wsovRenderTags(wsovTagBit(wsov.targetTag))
        }
    }

    func workspaceOverviewClientTitleChanged(_ c: Client?) {
        guard workspaceOverviewIsActive(), !wsov.closing, let c, let m = wsov.mon, c.mon === m else { return }

        for cell in wsov.cells {
            if !wsovClientOnTag(c, cell.tag) {
                continue
            }
            wsovCaptureCellBars(cell)
            _ = wsovRenderCell(cell, wsovOutputScale())
        }
        system.outputScheduleFrame(m)
    }

    func workspaceOverviewClientStackChanged(_ c: Client?) {
        guard workspaceOverviewIsActive(), !wsov.closing, let c, c.mon === wsov.mon else { return }
        let tags = wsovCellTagsForClient(c) | wsovClientTags(c)
        wsovRefreshWorkspaceOrRebuild(tags)
        if wsov.closing || !workspaceOverviewIsActive() {
            return
        }
        wsovRebuildLiveProjection()
        wsovRenderTags(wsovTagBit(wsov.targetTag))
        wsovUpdateStylesTags(tags | wsovTagBit(wsov.targetTag))
        if let m = wsov.mon { system.outputScheduleFrame(m) }
    }

    func workspaceOverviewLayoutChanged(_ m: Monitor) {
        if !workspaceOverviewIsActiveOn(m) || wsov.closing ||
            wsov.capturingLayout {
            return
        }
        let tags = wsovLayoutAffectedTags(m)
        let previousTarget = wsov.targetTag
        let currentViewTag = getMonCurtag(m)
        let currentViewBit = wsovTagBit(currentViewTag)
        let keepViewTag = m.workspaceOverviewScope == OCCUPIED_WORKSPACE &&
            config.workspaceOverviewOccupiedKeepSeenTags != 0 &&
            currentViewBit != 0
        if keepViewTag {
            wsov.retainedTags |= currentViewBit
        }
        let viewTargetAvailable =
            currentViewTag != 0 &&
            (wsovCellForTag(currentViewTag) != nil || keepViewTag)
        let targetChanged =
            viewTargetAvailable && currentViewTag != previousTarget
        if viewTargetAvailable {
            wsov.targetTag = currentViewTag
            wsov.cameraTag = currentViewTag
            if targetChanged {
                wsov.scrollCenterTag = currentViewTag
            }
        }
        wsovSettleTagAnimations(m, tags)
        wsovCaptureWorkspaceTags(tags)
        wsovRefreshWorkspaceOrRebuild(tags)
        if !workspaceOverviewIsActive() || wsov.closing {
            return
        }

        if targetChanged {
            if wsov.layout == WORKSPACE_OVERVIEW_SCROLL {
                wsovAnimateScrollToTarget()
            }
            wsovApplyTargetSelection(false)
        }
    }

    func workspaceOverviewClientUnmapped(_ c: Client?, _ activateTarget: Bool) {
        guard workspaceOverviewIsActive(), !wsov.closing, let c, let m = wsov.mon else { return }
        let tags = wsovClientTags(c)
        let oldTargetTag = wsov.targetTag
        let previousCameraTag = wsov.cameraTag
        wsovSelectDefaultTarget()
        wsov.cameraTag = wsov.targetTag
        let previous = m.sel
        let targetBit = wsovTagBit(wsov.targetTag)
        let switchWorkspace = activateTarget && targetBit != 0 &&
            m.tagset[m.seltags] & targetBit == 0
        if switchWorkspace {
            clientViewOnMonitor(Arg(ui: targetBit), false, m, true)
            wsovCaptureWorkspaceTags(targetBit)
        }
        wsovSyncMonitorSelection()
        wsovRebuildLiveProjection()
        if switchWorkspace {
            wsovRenderTags(targetBit)
        } else {
            wsovRenderSelectionClients(previous, m.sel)
        }
        wsovUpdateStylesTags(tags | wsovTagBit(oldTargetTag) | targetBit)
        if switchWorkspace || previousCameraTag != wsov.cameraTag {
            wsovApplyCamera(wsov.progress)
        }
    }

    func workspaceOverviewMonitorDestroy(_ m: Monitor) {
        if workspaceOverviewIsActiveOn(m) {
            wsovFinalizeClose(0)
        }
    }

    func workspaceOverviewMonitorChanged(_ m: Monitor) {
        if !workspaceOverviewIsActiveOn(m) || wsov.closing {
            return
        }
        wsovUpdateRootGeometry(m)
        wsovScheduleRebuild()
    }

    func workspaceOverviewReload() {
        guard workspaceOverviewIsActive(), !wsov.closing, let m = wsov.mon else { return }
        wsovUpdateRootGeometry(m)
        wsovScheduleRebuild()
    }
}
