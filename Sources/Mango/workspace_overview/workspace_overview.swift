import CoreGraphics
import Foundation

/* mango WorkspaceOverviewScope (common/types.h) */
let ALL_WORKSPACE: Int32 = 0, OCCUPIED_WORKSPACE: Int32 = 1
/* mango WorkspaceOverviewLayout (common/types.h) */
let WORKSPACE_OVERVIEW_GRID: Int32 = 0, WORKSPACE_OVERVIEW_SCROLL: Int32 = 1

// mango workspace_overview_internal.h's types

/// mango struct wsov_item
// not in mango: no scene (the client's scene is the port's)
package final class WsovItem {
    package var client: Client?
    var layer: Lyr = .bg
    var borderWidth: CGFloat = 0
    var isSnapshot = false
    package var box = WlrBox()
    var workspaceGeom = WlrBox()
    var renderScale = 0.0
    var renderScaleX = 0.0
    var renderScaleY = 0.0
    init(client: Client?) { self.client = client }
}

/// mango struct wsov_cell
// not in mango: no buffer pool, live scene trees, live surfaces or clients and their live state (the port
// draws every window as a picture), bar items (the port draws the bars) or layer previews (no layer shell)
package final class WsovCell {
    package var tag: UInt32 = 0
    package var box = WlrBox()
    var frame: WlrSceneRect!
    var border: [WlrSceneRect?] = [nil, nil, nil, nil]
    var contents: WlrSceneBuffer!
    var foreground: WlrSceneBuffer!
    var dim: MangoDimNode?
    package var items: [WsovItem] = []
    var bufferW = 0
    var bufferH = 0
    var layoutFrom = WlrBox()
    var layoutCurrent = WlrBox()
    var bordersEnabled = false
    var dimEnabled = false
    var contentsDirty = false
    var foregroundDirty = false
    var capturePending = false
    init() {}
}

/// mango WsovScrollWheelState
struct WsovScrollWheelState {
    var accum = 0.0
    var lastTimeMsec: UInt32 = 0
    var direction: Int32 = 0
    var tracking = false
}

/// mango struct wsov_background_effects (the build without scenefx has none)
final class WsovBackgroundEffects {}

/// mango struct wsov_state
// not in mango: the times are milliseconds (getNowInMs) for struct timespec; no direct layer trees (no layer
// shell); the frame listener is frame_active, which the port's frame calls (handleOutputFrame)
package final class WsovState {
    package var mon: Monitor?
    package var layout: Int32 = WORKSPACE_OVERVIEW_GRID
    package var root: WlrSceneTree?
    var background: WlrSceneRect?
    var backgroundEffects: WsovBackgroundEffects?
    package var cells: [WsovCell] = []
    var renderIdle: EventSource?
    var rebuildIdle: EventSource?

    var animating = false
    package var closing = false
    var layersDirty = false
    var capturingLayout = false
    var clientAnimating = false
    var layoutAnimating = false
    var liveLayoutDirty = false
    var liveLayoutFlushing = false
    package var frameActive = false
    package var progress = 0.0
    var animationFrom = 0.0
    var animationTo = 0.0
    var animationStart = 0.0
    var layoutAnimationStart = 0.0
    var layoutAnimationDurationMs = 0.0
    var cameraTag: UInt32 = 0
    var retainedTags: UInt32 = 0
    var closeTag: UInt32 = 0
    var closeClient: Client?
    var closeFocusExplicit = false

    package var pressed = false
    var moved = false
    var hasDragClient = false
    var sourceTag: UInt32 = 0
    package var targetTag: UInt32 = 0
    var scrollCenterTag: UInt32 = 0
    var dragReturnTag: UInt32 = 0
    var dragClient: Client?
    var dragStartX = 0
    var dragStartY = 0
    var dragGrabX = 0
    var dragGrabY = 0
    var dragSourceWidth = 0
    var dragSourceHeight = 0
    var dragPreviewX = 0
    var dragPreviewY = 0
    var dragBuffer: WlrSceneBuffer?
    var dragWidth = 0
    var dragHeight = 0
    var dragBarHeight = 0
    var dropFill: WlrSceneRect?
    var dropIndicatorVisible = false
    var dragFloatingChanged = false
    var dragWasFloating = false
    var dragWasDragToTile = false
    var dragSavedFloatGeom = CGRect.zero

    /* Primary workspace-strip coordinate shown at the viewport origin. */
    package var scrollOffset = 0.0
    var scrollMin = 0.0
    var scrollMax = 0.0
    var scrollAnimating = false
    var scrollAnimationFrom = 0.0
    var scrollAnimationTo = 0.0
    var scrollAnimationDurationMs = 0.0
    var scrollAnimationStart = 0.0
    var scrollWheel = WsovScrollWheelState()
    var dragScrollDirection: Int32 = 0
    var dragScrollLastFrame = 0.0
    var dragScrollFrameValid = false
    var liveCell: WsovCell?
    package init() {}
}

/// mango struct wsov_camera_view
struct WsovCameraView {
    var x = 0.0
    var y = 0.0
    var scaleX = 0.0
    var scaleY = 0.0
}

@MainActor package var wsov = WsovState()

extension MangoServer {
    func wsovBackgroundEffectsCreate(_ parent: WlrSceneTree?, _ width: Int, _ height: Int) -> WsovBackgroundEffects? {
        return nil
    }

    func wsovBackgroundEffectsUpdate(_ effects: WsovBackgroundEffects?, _ width: Int, _ height: Int) {
    }

    func wsovBackgroundEffectsDestroy(_ effects: WsovBackgroundEffects?) {
    }

    func wsovFlushRebuild() {
        wsov.rebuildIdle = nil
        wsovRebuild()
    }

    func wsovScheduleRebuild() {
        if wsov.rebuildIdle != nil {
            return
        }
        wsov.rebuildIdle = system.eventLoop.addIdle { [weak self] in self?.wsovFlushRebuild() }
        if wsov.rebuildIdle == nil {
            wsovRebuild()
        }
    }

    func wsovCancelScheduledRebuild() {
        guard let idle = wsov.rebuildIdle else { return }
        idle.remove()
        wsov.rebuildIdle = nil
    }

    func wsovHideClients(_ hidden: Bool) {
        for c in clients {
            if c.mon !== wsov.mon {
                continue
            }
            c.wsovHidden = hidden
            clientUpdateVisibility(c)
        }
    }

    func wsovStartAnimation(_ closing: Bool, _ target: Double) {
        if !config.animations {
            wsov.closing = closing
            wsov.layoutAnimating = false
            wsov.animating = false
            wsov.animationTo = target
            wsov.progress = target
            wsovApplyCamera(target)
            if closing {
                wsovFinalizeClose(wsov.closeTag)
            } else {
                wsovDetachFrameListener()
            }
            return
        }

        wsov.animationFrom = fmax(0.0, fmin(1.0, wsov.progress))
        wsov.animationTo = fmax(0.0, fmin(1.0, target))
        wsov.closing = closing
        wsov.animating = true
        wsov.animationStart = wsovNowMs()
        wsovAttachFrameListener()
        if let m = wsov.mon { system.outputScheduleFrame(m) }
    }

    func wsovResumeOpenAnimation() {
        if !workspaceOverviewIsActive() || !wsov.closing {
            return
        }

        wsov.targetTag = wsov.cameraTag
        wsov.closeTag = 0
        wsov.closeClient = nil
        wsov.closeFocusExplicit = false
        wsov.layersDirty = true
        wsovSetBordersEnabled(true)
        wsovUpdateStyles()
        wsovRebuildLiveProjection()
        wsovRenderTags(wsovTagBit(wsov.targetTag))
        wsovStartAnimation(false, 1.0)
    }

    func wsovClose(_ focusTag: UInt32, _ focusClient: Client?) {
        if !workspaceOverviewIsActive() || wsov.closing {
            return
        }
        let pointerClose = wsov.pressed
        let previousTarget = wsov.targetTag
        wsovCancelScheduledRender()
        wsovCancelDrag()
        wsov.scrollAnimating = false
        wsov.closeClient = focusClient
        wsov.closeFocusExplicit = pointerClose
        if !config.animations {
            wsovFinalizeClose(focusTag)
            return
        }

        wsovSetDimEnabled(false)
        wsovSetBordersEnabled(false)
        wsov.closing = true
        wsov.layersDirty = false
        /* Keep the live projection through the close animation so surface effects
         * continue to scale with the workspace. wsov_destroy_cells() removes them
         * only after the animation reaches its final frame. */
        wsov.closeTag = focusTag
        var cameraTag = focusTag != 0 ? focusTag : wsovActiveCameraTag()
        if cameraTag == 0 || wsovCellForTag(cameraTag) == nil {
            cameraTag = previousTarget
        }
        wsov.cameraTag = cameraTag
        wsovApplyCamera(wsov.progress)
        wsovStartAnimation(true, 0.0)
    }

    func wsovFinishClientGeometry(_ c: Client) {
        if c.animation.running && c.animation.action == .move {
            system.sceneNodeSetPosition(c, c.animation.current.minX, c.animation.current.minY)   // not in mango: the port's wlr_scene_node_set_position
            c.needOutputFlush = true
            return
        }
        clientSetFinishGeometry(c)
    }

    func wsovFinalizeClose(_ focusTag: UInt32) {
        if !workspaceOverviewIsActive() {
            return
        }

        guard let m = wsov.mon else { return }
        var focusClient = wsov.closeClient
        let focusExplicit = wsov.closeFocusExplicit
        wsovCancelScheduledRebuild()
        wsovCancelDrag()
        wsov.closing = true
        m.isWsOverview = false

        wsovDetachFrameListener()
        system.seatPointerClearFocus()
        system.keyboardNotifyClearFocus()   // not in mango: no exclusive focus (no layer shell)
        wsovDestroyCells()
        // not in mango: no direct layer trees or layer fade-outs (no layer shell)
        wsovBackgroundEffectsDestroy(wsov.backgroundEffects)
        if let root = wsov.root {
            wlrSceneNodeDestroy(root)
        }
        wsov.root = nil
        wsov.background = nil
        wsov.backgroundEffects = nil

        if focusTag != 0 {
            clientViewOnMonitor(Arg(ui: wsovTagBit(focusTag)), false, m, false)
        } else {
            arrange(m, false, false)
        }

        /* Arrange the destination view while windows are still hidden. Only then
         * reveal the scene, avoiding a one-frame flash of every workspace. */
        for c in clients {
            if c.mon === m {
                wsovFinishClientGeometry(c)
            }
        }
        wsovHideClients(false)
        // not in mango: no fade-out clients (the close animation is macOS's)
        wsov = WsovState()
        pointerCursorActivity()

        if !focusExplicit && focusClient == nil {
            focusClient = clientFocusTop(m)
        }
        clientFocus(focusClient, true)
        // not in mango: no reset_exclusive_layers_focus (no layer shell)
        pointerProcessMotion(0, 0, 0)
        system.outputScheduleFrame(m)
        publishInputState()   // not in mango: the event tap's snapshot
    }

    package func workspaceOverviewIsActive() -> Bool {
        wsov.mon?.isWsOverview == true && wsov.root != nil
    }

    package func workspaceOverviewIsActiveOn(_ m: Monitor?) -> Bool {
        workspaceOverviewIsActive() && wsov.mon === m
    }

    func workspaceOverviewIsClosingOn(_ m: Monitor?) -> Bool {
        m != nil && wsov.mon === m && wsov.closing
    }

    package func workspaceOverviewPointerIsPressed() -> Bool {
        workspaceOverviewIsActive() && wsov.pressed
    }

    func wsovUpdateRootGeometry(_ m: Monitor?) {
        guard let root = wsov.root, let m else { return }
        wlrSceneNodeSetPosition(root, Int(m.m.minX), Int(m.m.minY))
        wsovBackgroundEffectsUpdate(wsov.backgroundEffects, Int(m.m.width), Int(m.m.height))
        if let background = wsov.background {
            wlrSceneRectSetSize(background, Int(m.m.width), Int(m.m.height))
            let color = wsov.backgroundEffects != nil
                ? RGBA(r: 0, g: 0, b: 0, a: 0)
                : config.rootcolor
            wlrSceneRectSetColor(background, color)
        }
    }

    func wsovOpen(_ m: Monitor?, _ layout: Int32) -> Bool {
        guard let m, !workspaceOverviewIsActive(), !m.isoverview else { return false }

        wsov = WsovState()
        wsov.mon = m
        wsov.layout = layout
        if m.workspaceOverviewScope == OCCUPIED_WORKSPACE &&
            config.workspaceOverviewOccupiedKeepSeenTags != 0 {
            for tag in stride(from: 1, through: config.tagNum, by: 1) {
                if wsovTagHasNormalClient(UInt32(tag)) {
                    wsov.retainedTags |= wsovTagBit(UInt32(tag))
                }
            }
            wsov.retainedTags |= wsovTagBit(getMonCurtag(m))
        }
        var count = 0
        _ = wsovCollectWorkspaceTags(m, &count)
        if count <= 0 {
            wsov = WsovState()
            return false
        }

        m.isWsOverview = true

        wsov.root = wlrSceneTreeCreate(layers[Lyr.specialOverlay.rawValue])
        // not in mango: no direct layer trees (no layer shell, wsov_sync_direct_layers)
        wsov.backgroundEffects =
            wsovBackgroundEffectsCreate(wsov.root, Int(m.m.width), Int(m.m.height))
        wsov.background = wlrSceneRectCreate(wsov.root!, Int(m.m.width), Int(m.m.height),
                                             config.rootcolor)
        wsovUpdateRootGeometry(m)
        if !wsovCreateDropIndicator() {
            wsovFinalizeClose(0)
            return false
        }
        wsov.animating = config.animations
        wsov.progress = config.animations ? 0.0 : 1.0
        wsov.animationFrom = 0.0
        wsov.animationTo = 1.0
        wsov.animationStart = wsovNowMs()

        wsovHideClients(true)
        system.seatPointerClearFocus()
        system.keyboardNotifyClearFocus()   // not in mango: no exclusive focus (no layer shell)
        pointerCursorActivity()
        if !cursorHidden {
            system.setCursor("default")
        }

        if !wsovCreateCells() {
            wsovFinalizeClose(0)
            return false
        }
        if wsov.animating || wsov.layoutAnimating {
            wsovAttachFrameListener()
        }
        system.outputScheduleFrame(m)
        publishInputState()   // not in mango: the event tap's snapshot
        return true
    }

    func wsovRebuild() {
        if !workspaceOverviewIsActive() {
            return
        }
        if wsov.closing {
            return
        }
        wsovCancelScheduledRebuild()

        wsovCancelDrag()
        wsov.scrollAnimating = false
        if !wsovCreateCells() {
            wsovFinalizeClose(0)
            return
        }
        if let m = wsov.mon { system.outputScheduleFrame(m) }
    }

    func wsovRefreshWorkspaceTags(_ tags: UInt32) -> Bool {
        guard workspaceOverviewIsActive(), !wsov.closing, let m = wsov.mon, wsov.cells.count > 0 else {
            return false
        }

        var current: UInt32 = 0
        for cell in wsov.cells {
            current |= wsovTagBit(cell.tag)
        }

        /* Empty workspaces keep their cells in ALL_WORKSPACE mode. Only occupied
         * mode can remove a cell and thereby change every preview's grid position.
         */
        if m.workspaceOverviewScope == OCCUPIED_WORKSPACE {
            var expectedCount = 0
            let expected = wsovCollectWorkspaceTags(m, &expectedCount)
            if expectedCount != wsov.cells.count || expected != current {
                return false
            }
        }

        let tags = tags & current
        if tags == 0 {
            return true
        }

        wsovSyncMonitorSelection()
        for cell in wsov.cells {
            if tags & wsovTagBit(cell.tag) == 0 {
                continue
            }
            wsovCaptureCellItems(cell)
            /*
             * Keep cached strip snapshots for inactive workspaces. They were
             * captured under their own tag by the layout-change path; replacing
             * them here would apply the active tag's projection to every cell.
             */
            if cell.tag == getMonCurtag(m) {
                wsovCaptureCellBars(cell)
            }
            wsovPositionCellItems(cell)
        }

        wsovLayoutLiveProjection()
        wsovRenderTags(tags)
        wsovUpdateStylesTags(tags)
        if wsovRefreshAnimatedCells() {
            wsov.clientAnimating = true
            wsovAttachFrameListener()
        }
        system.outputScheduleFrame(m)
        return true
    }

    func wsovRefreshWorkspaceOrRebuild(_ tags: UInt32) {
        if !wsovRefreshWorkspaceTags(tags) {
            wsovRebuild()
        }
    }

    func toggleWorkspaceOverview(_ arg: Arg) -> Int32 {
        guard let m = selectedMonitor, grabClient == nil, !m.isoverview else { return 0 }
        if workspaceOverviewIsActive() {
            if wsov.closing {
                wsovResumeOpenAnimation()
            } else {
                wsovClose(wsov.targetTag, nil)
            }
        } else {
            m.workspaceOverviewScope =
                arg.i == OCCUPIED_WORKSPACE ? OCCUPIED_WORKSPACE : ALL_WORKSPACE
            let layout = arg.i2 == WORKSPACE_OVERVIEW_SCROLL
                ? WORKSPACE_OVERVIEW_SCROLL
                : WORKSPACE_OVERVIEW_GRID
            _ = wsovOpen(m, layout)
        }
        return 0
    }

    func enterWorkspaceOverview(_ arg: Arg) -> Int32 {
        guard let m = selectedMonitor, grabClient == nil, !m.isoverview else { return 0 }
        if workspaceOverviewIsActive() {
            wsovResumeOpenAnimation()
        } else {
            m.workspaceOverviewScope =
                arg.i == OCCUPIED_WORKSPACE ? OCCUPIED_WORKSPACE : ALL_WORKSPACE
            let layout = arg.i2 == WORKSPACE_OVERVIEW_SCROLL
                ? WORKSPACE_OVERVIEW_SCROLL
                : WORKSPACE_OVERVIEW_GRID
            _ = wsovOpen(m, layout)
        }
        return 0
    }

    func leaveWorkspaceOverview(_ arg: Arg) -> Int32 {
        if workspaceOverviewIsActive() {
            wsovClose(0, nil)
        }
        return 0
    }
}
