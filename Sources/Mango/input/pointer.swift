import CoreGraphics

// not in mango: pointer_surface_scale (Xwayland); the pointer constraints (pointer_constraint_sync_region,
// pointer_region_closest_point, pointer_constraint_hint_position, pointer_locked_constraint_applies,
// pointer_follow_constraint_hint, pointer_client_visible, pointer_constraint_surface_visible,
// pointer_warp_into_constraint, pointer_confine_client, handle_pointer_constraint_commit,
// handle_new_pointer_constraint, pointer_constrain_cursor, pointer_warp_to_constraint_hint,
// handle_pointer_constraint_destroy); the client's cursor image (handle_last_cursor_surface_destroy,
// handle_request_set_cursor_shape, handle_request_set_cursor); libinput's settings (pointer_set_accel,
// configure_pointer, pointer_create); drag and drop (handle_drag_icon_destroy, handle_request_start_drag,
// handle_start_drag, server.seat->drag); handle_new_virtual_pointer; handle_cursor_frame and the seat's
// motion and frame events; handle_cursor_motion_absolute (the port gives every motion to
// handle_cursor_motion); the relative pointer, the idle notifier, ipc_notify_device_event, the session
// lock, check_trackpad_disabled (MangoCompat) and unmanaged (X11) clients. device.c, switch.c, tablet.c
// and touch.c have no macOS part.

/* Resize corners. */
let TOP_LEFT = 0, TOP_RIGHT = 1, BOTTOM_LEFT = 2, BOTTOM_RIGHT = 3

/* Trackpad swipe directions. */
let SWIPE_UP: UInt32 = 0, SWIPE_DOWN: UInt32 = 1, SWIPE_LEFT: UInt32 = 2, SWIPE_RIGHT: UInt32 = 3

/* Cursor states. */
package let CurNormal: UInt32 = 0, CurPressed: UInt32 = 1, CurMove: UInt32 = 2, CurResize: UInt32 = 3 /* cursor */

/* Scroll wheel direction. */
let AxisUp: UInt32 = 0, AxisDown: UInt32 = 1, AxisLeft: UInt32 = 2, AxisRight: UInt32 = 3

let CONFINE_POINTER_MARGIN: CGFloat = 5

package extension MangoServer {
    func pointerClientWarpBox(_ c: Client) -> CGRect {
        var box = c.animation.current
        if box.width <= 0 || box.height <= 0 || box.minX < c.geom.minX ||
            box.minY < c.geom.minY || box.minX + box.width > c.geom.minX + c.geom.width ||
            box.minY + box.height > c.geom.minY + c.geom.height {
            box = c.geom
        }
        return box
    }

    func pointerCursorOutsideClient(_ c: Client) -> Bool {
        let box = pointerClientWarpBox(c)
        let cursor = system.pointer
        return cursor.x < box.minX || cursor.y < box.minY ||
            cursor.x >= box.minX + box.width ||
            cursor.y >= box.minY + box.height
    }

    func pointerConfineRuleClient() -> Client? {
        var c: Client?

        if let focused = system.keyboardFocusedSurface {
            c = focused
        }
        if c == nil, let sm = selectedMonitor {
            c = sm.sel.flatMap { clientByIdAll($0) }
        }

        // not in mango: mapped is being in the client list
        guard let c, c.confinePointer, clientByIdAll(c.id) === c, let m = c.mon,
              !m.isoverview, !c.isminimized, VISIBLEON(c, m),
              c.platform.sceneNodeEnabled else {
            return nil
        }
        return c
    }

    func pointerCheckConfineClient() {
        let c = pointerConfineRuleClient()

        if let c, c !== confinePointerLast, pointerCursorOutsideClient(c) {
            let box = pointerClientWarpBox(c)
            system.warp(to: CGPoint(x: box.minX + box.width / 2.0, y: box.minY + box.height / 2.0))
        }
        confinePointerLast = c
    }

    func pointerClientDestroyed(_ c: Client) {
        if confinePointerLast === c {
            confinePointerLast = nil
        }
    }

    func toggleHotarea(_ xRoot: Int32, _ yRoot: Int32) {
        // Computes the hot-area coordinates in the lower-left corner; supports
        // multiple monitors.
        let arg = Arg()

        // At startup selected_monitor may be NULL while the mouse is already in the
        // hot area, so this must be checked to avoid a crash.
        guard let sm = selectedMonitor else { return }

        if grabClient != nil { return }

        if config.hotareaDisableOnFullscreen {
            if let focused = sm.sel.flatMap({ clientByIdAll($0) }), focused.isfullscreen,
               VISIBLEON(focused, sm) {
                sm.isInHotarea = false
                return
            }
        }

        // not in mango: C's int and unsigned arithmetic spelled out
        let mx = Int32(sm.m.minX), my = Int32(sm.m.minY)
        let mw = Int32(sm.m.width), mh = Int32(sm.m.height)
        let size = Int32(config.hotareaSize)
        let ux = UInt32(bitPattern: xRoot), uy = UInt32(bitPattern: yRoot)

        // Computes different hot-area coordinates for each hot corner.
        let hx: UInt32, hy: UInt32

        switch config.hotareaCorner {
        case BOTTOM_RIGHT: // Bottom-right corner
            hx = UInt32(bitPattern: mx &+ mw &- size)
            hy = UInt32(bitPattern: my &+ mh &- size)
        case TOP_LEFT: // Top-left corner
            hx = UInt32(bitPattern: mx &+ size)
            hy = UInt32(bitPattern: my &+ size)
        case TOP_RIGHT: // Top-right corner
            hx = UInt32(bitPattern: mx &+ mw &- size)
            hy = UInt32(bitPattern: my &+ size)
        default: // Bottom-left corner (default)
            hx = UInt32(bitPattern: mx &+ size)
            hy = UInt32(bitPattern: my &+ mh &- size)
        }

        // Checks whether the pointer is inside the hot area.
        let inHotarea: Bool

        switch config.hotareaCorner {
        case BOTTOM_RIGHT: // Bottom-right corner
            inHotarea = uy > hy && ux > hx &&
                xRoot <= (mx &+ mw) &&
                yRoot <= (my &+ mh)
        case TOP_LEFT: // Top-left corner
            inHotarea = uy < hy && ux < hx &&
                xRoot >= mx &&
                yRoot >= my
        case TOP_RIGHT: // Top-right corner
            inHotarea = uy < hy && ux > hx &&
                xRoot <= (mx &+ mw) &&
                yRoot >= my
        default: // Bottom-left corner (default)
            inHotarea = uy > hy && ux < hx &&
                xRoot >= mx &&
                yRoot <= (my &+ mh)
        }

        if config.enableHotarea && !sm.isInHotarea && inHotarea {
            /* Hot-area entry: uses the normal grid layout. */
            sm.ovNormalMode = true
            toggleOverview(arg)
            sm.isInHotarea = true
        } else if config.enableHotarea && sm.isInHotarea && !inHotarea {
            sm.isInHotarea = false
        }
    }

    /// mango client_resize_grab (pointer.c).
    func clientResizeGrab(_ c: Client) -> CGFloat {
        if config.borderResizeSize > 0 { return CGFloat(config.borderResizeSize) }
        return CGFloat(Int32(c.bw))
    }

    /* Returns the subset of `cand` edges of `c` that face another tiled window on
     * the same monitor. Tiled layouts pack windows flush against their neighbours
     * (separated only by the inner gap), so an edge is shared exactly when a tiled
     * window lies on that side of `c` and overlaps it on the perpendicular axis.
     * The neighbour's box is compared as-is, no gap/decoration knowledge needed. */
    func tiledSharedEdges(_ c: Client, _ cand: WlrEdges) -> WlrEdges {
        let a = c.geom
        var shared: WlrEdges = []

        for o in clients {
            if o === c || o.mon !== c.mon || !VISIBLEON(o, o.mon) || !ISTILED(o) { continue }

            let b = o.geom
            let voverlap = a.minY < b.minY + b.height && b.minY < a.minY + a.height
            let hoverlap = a.minX < b.minX + b.width && b.minX < a.minX + a.width

            if cand.contains(.left) && !shared.contains(.left) && voverlap && b.minX + b.width <= a.minX {
                shared.insert(.left)
            }
            if cand.contains(.right) && !shared.contains(.right) && voverlap && b.minX >= a.minX + a.width {
                shared.insert(.right)
            }
            if cand.contains(.top) && !shared.contains(.top) && hoverlap && b.minY + b.height <= a.minY {
                shared.insert(.top)
            }
            if cand.contains(.bottom) && !shared.contains(.bottom) && hoverlap && b.minY >= a.minY + a.height {
                shared.insert(.bottom)
            }

            if shared.intersection(cand) == cand { break }
        }
        return shared
    }

    func clientResizeEdgeAt(_ c: Client?, _ surface: ClientID?, _ x: CGFloat, _ y: CGFloat) -> WlrEdges {
        guard let c, c.platform.sceneNodeEnabled else { return [] }
        if ISFULLSCREEN(c) { return [] }
        /* A popup or any other child surface sitting on the border grab strip
         * must keep receiving its own input instead of resizing the parent. */
        if let surface, surface != c.id { return [] }
        guard let m = c.mon, !m.isoverview, VISIBLEON(c, m) else { return [] }

        var t = clientResizeGrab(c)
        if t <= 0 { return [] }

        let g = c.geom
        if x < g.minX || x >= g.minX + g.width || y < g.minY || y >= g.minY + g.height { return [] }

        t = min(t, CGFloat(Int32(g.width) / 2))
        t = min(t, CGFloat(Int32(g.height) / 2))

        var edge: WlrEdges = []
        if x < g.minX + t { edge.insert(.left) }
        if x >= g.minX + g.width - t { edge.insert(.right) }
        if y < g.minY + t { edge.insert(.top) }
        if y >= g.minY + g.height - t { edge.insert(.bottom) }

        if !edge.isEmpty && !c.isfloating {
            if !ISTILED(c) { return [] }
            edge = tiledSharedEdges(c, edge)
        }

        return edge
    }

    func resizeCursorName(_ edge: WlrEdges, _ floating: Bool) -> String {
        if floating { return wlrXcursorGetResizeName(edge) }
        return !edge.isDisjoint(with: [.left, .right]) ? "col-resize" : "row-resize"
    }

    func pointerUpdateResizeCursor(_ c: Client?, _ surface: ClientID?) {
        if cursorMode != CurNormal { return }

        var edge: WlrEdges = []
        if config.enableBorderResize && !cursorHidden, let c {
            let cursor = system.pointer
            edge = clientResizeEdgeAt(c, surface, cursor.x, cursor.y)
        }

        let floating = !edge.isEmpty && c?.isfloating == true
        let changed = edge != hoverResizeEdge || floating != hoverResizeFloating
        let previous = hoverResizeEdge
        if changed {
            hoverResizeEdge = edge
            hoverResizeFloating = floating
            publishInputState()   // not in mango: the event tap takes the press on the strip
        }

        if cursorHidden { return }

        if !edge.isEmpty {
            /* The strip owns the cursor while it is hovered. Re-applying is a
             * no-op when unchanged (wlr_cursor_set_xcursor compares names), so
             * this also repairs the image after an idle hide. */
            system.setCursor(resizeCursorName(edge, floating))
        } else if changed && !previous.isEmpty {
            /* Leaving the strip hands the cursor back to the client: drop the
             * pointer focus so pointer_focus() re-enters and the client sends
             * its own cursor again. No remembered client cursor is replayed. */
            system.seatPointerClearFocus()
            system.setCursor(nil)   // not in mango: the arrow until the app sets its own (docs/afvigelser.md §3)
        }
    }

    func pointerResizeFloatingWindow(_ gc: Client, _ x: CGFloat, _ y: CGFloat) {
        let edge = resizeEdge
        let bw = CGFloat(Int32(gc.bw))
        let minW = 1 + 2 * bw
        let minH = 1 + 2 * bw
        var cdx: CGFloat = 0, cdy: CGFloat = 0
        var box = gc.geom

        if !edge.isDisjoint(with: [.left, .right]) {
            cdx = x.rounded() - grabOffsetX
            if edge.contains(.right) {
                if gc.geom.width + cdx < minW { cdx = minW - gc.geom.width }
                box.size.width = gc.geom.width + cdx
            } else {
                if gc.geom.width - cdx < minW { cdx = gc.geom.width - minW }
                box.origin.x = gc.geom.minX + cdx
                box.size.width = gc.geom.width - cdx
            }
        }

        if !edge.isDisjoint(with: [.top, .bottom]) {
            cdy = y.rounded() - grabOffsetY
            if edge.contains(.bottom) {
                if gc.geom.height + cdy < minH { cdy = minH - gc.geom.height }
                box.size.height = gc.geom.height + cdy
            } else {
                if gc.geom.height - cdy < minH { cdy = gc.geom.height - minH }
                box.origin.y = gc.geom.minY + cdy
                box.size.height = gc.geom.height - cdy
            }
        }

        gc.floatGeom = box

        resize(gc, box, ResizeOpts(interact: true, dragEdge: edge))
        grabOffsetX += cdx
        grabOffsetY += cdy
    }

    func clientBeginDragFloat(_ c: Client) {
        c.dragToTile = true
        exitScrollerStack(c)
        clientSetFloating(c, true, false)
        c.dragTileFloatBackupGeom = c.floatGeom
        c.oldStackInnerPer = 0.0
        c.oldMasterInnerPer = 0.0
        if let m = c.mon { setSizePer(m, c) }
    }

    @discardableResult
    func pointerBeginMoveResize(_ gc: Client?, _ mode: UInt32, _ x: CGFloat, _ y: CGFloat, _ edge: WlrEdges) -> Bool {
        if cursorMode != CurNormal && cursorMode != CurPressed { return false }

        guard let gc, mode == CurMove || mode == CurResize,
              !gc.isfullscreen, !gc.ismaximizescreen else {
            grabClient = nil
            return false
        }

        grabClient = gc
        grabIsBorderResize = !edge.isEmpty
        system.grabBegan(gc)   // not in mango: the port's side

        if !gc.isfloating && mode == CurMove {
            clientBeginDragFloat(gc)
        }

        if gc.dragToTile && config.dragTileToTile && config.dragTileSmall {
            gc.geom.origin.x = x.rounded() - 150
            gc.geom.origin.y = y.rounded() - 150
            gc.geom.size.width = 300
            gc.geom.size.height = 300
            resize(gc, gc.geom, ResizeOpts(interact: true))
        }

        cursorMode = mode
        switch mode {
        case CurMove:
            grabOffsetX = (x - gc.geom.minX).rounded(.towardZero)
            grabOffsetY = (y - gc.geom.minY).rounded(.towardZero)
            system.setCursor("grab")
        default:
            if gc.isfloating {
                var resizeEdge = edge
                if resizeEdge.isEmpty {
                    var corner = config.dragCorner
                    if corner == 4 {
                        corner = (x - gc.geom.minX < gc.geom.minX + gc.geom.width - x ? 0 : 1)
                            + (y - gc.geom.minY < gc.geom.minY + gc.geom.height - y ? 0 : 2)
                    }
                    resizeEdge = corner & 1 != 0 ? .right : .left
                    resizeEdge.formUnion(corner & 2 != 0 ? .bottom : .top)
                }
                self.resizeEdge = resizeEdge

                var grabX = x.rounded()
                var grabY = y.rounded()
                /* A border grab already sits on the grabbed edge; only the
                 * drag_corner path warps the pointer onto it. */
                if config.dragWarpCursor && edge.isEmpty {
                    var warpX = x, warpY = y
                    if !resizeEdge.isDisjoint(with: [.left, .right]) {
                        grabX = resizeEdge.contains(.right) ? gc.geom.minX + gc.geom.width : gc.geom.minX
                        warpX = grabX
                    }
                    if !resizeEdge.isDisjoint(with: [.top, .bottom]) {
                        grabY = resizeEdge.contains(.bottom) ? gc.geom.minY + gc.geom.height : gc.geom.minY
                        warpY = grabY
                    }
                    system.warp(to: CGPoint(x: warpX, y: warpY))
                }
                grabOffsetX = grabX
                grabOffsetY = grabY

                system.setCursor(resizeCursorName(resizeEdge, true))
            } else {
                system.setCursor(!edge.isEmpty ? resizeCursorName(edge, false) : "grab")
            }
        }

        let cursor = system.pointer
        grabPointerX = cursor.x
        grabPointerY = cursor.y

        return true
    }

    func pointerEndGrabClient(_ followPointer: Bool) {
        guard let gc = grabClient, cursorMode != CurNormal, cursorMode != CurPressed else { return }
        system.grabEnded(gc)   // not in mango: the port's side
        defer { system.settle(gc) }   // not in mango: the port's side

        let cursor = system.pointer
        let moved = cursor.x != grabPointerX || cursor.y != grabPointerY
        /* A plain click on a resize border must not snap the window; every other
         * grab keeps snapping as before, even when the pointer never moved. */
        let borderResize = grabIsBorderResize
        grabIsBorderResize = false

        cursorMode = CurNormal
        /* Clear the pointer focus, this way if the cursor is over a surface
         * we will send an enter event after which the client will provide
         * us a cursor surface */
        system.seatPointerClearFocus()
        system.setCursor(nil)   // not in mango: the arrow until the app sets its own (docs/afvigelser.md §3)
        pointerProcessMotion(0, 0, 0)
        /* Drop the window off on its new monitor */
        if selectedMonitor.sel == gc.id {
            selectedMonitor.sel = nil
        }
        var targetMon = followPointer
            ? monitorAtPoint(cursor)
            : monitorAtPoint(CGPoint(x: gc.geom.minX + CGFloat(Int32(gc.geom.width) / 2),
                                     y: gc.geom.minY + CGFloat(Int32(gc.geom.height) / 2)))
        if targetMon == nil { targetMon = gc.mon }
        if let targetMon { setSelectedMonitor(targetMon) }   // not in mango: selected_monitor is never NULL here
        let sm: Monitor = selectedMonitor
        clientUpdateOldmonnameRecord(gc, sm)
        clientSetMonitor(gc, sm, 0, focus: true)
        /* if the view changed mid-drag, drop onto the current tag
         * instead of silently returning to the original one */
        if !VISIBLEON(gc, sm) {
            gc.tags = sm.tagset[sm.seltags]
        }
        sm.prevsel = ISTILED(sm.sel.flatMap { clientByIdAll($0) }) ? sm.sel : nil
        sm.sel = gc.id
        grabClient = nil
        startDragWindow = false
        if gc.dragToTile && config.dragTileToTile {
            pointerPlaceDragTile(gc)
            gc.floatGeom = gc.dragTileFloatBackupGeom
        } else if !borderResize || moved {
            applyWindowSnap(gc)
        }
        gc.dragToTile = false
        if let dc = dropClient {
            dc.enableDropAreaDraw = false
            clientSetDropArea(dc)
            dropClient = nil
        }
    }

    func groupBarTargetAt(_ x: CGFloat, _ y: CGFloat, _ ignore: Client?) -> Client? {
        let p = CGPoint(x: x, y: y)
        var owner: Client?
        // not in mango: the group bars are the port's panels, so node_at_point's walk is spelled out;
        // a bar lies at the bottom of its client's layer
        if let m = monitorAtPoint(p), !m.isoverview {
            let vis = (isSpecialActive(m) ? specialClients(m) : visibleClients(m)).filter { $0 !== ignore && $0.platform.sceneNodeEnabled }
            let window = vis.filter { clientGeom($0).contains(p) }.map { clientTargetLayer($0) }.max()
            let bars = vis.filter { g in
                guard clientCheckTabNodeVisible(g, on: m), let s = clientDrawGroupBar(g, computeEdgeOffsets(g)) else { return false }
                return CGRect(x: s.frame.minX, y: s.frame.minY, width: s.frame.width, height: s.barHeight).contains(p)
            }
            if let bar = bars.max(by: { clientTargetLayer($0) < clientTargetLayer($1) }),
               window.map({ clientTargetLayer(bar) > $0 }) ?? true {
                owner = bar
            }
        }

        let target = clientGroupActive(owner)
        return target !== ignore ? target : nil
    }

    // not in mango: no device and no unaccelerated deltas (the relative pointer protocol)
    func pointerProcessMotion(_ time: UInt32, _ dx: Double, _ dy: Double) {
        var dx = dx, dy = dy
        var closetDropClient: Client?
        var shouldLock = false

        /* time is 0 in internal calls meant to restore pointer focus. */
        if time != 0 {
            if let ruleClient = pointerConfineRuleClient() {
                let box = pointerClientWarpBox(ruleClient)
                let minX = box.minX + ruleClient.bw + CONFINE_POINTER_MARGIN
                let minY = box.minY + ruleClient.bw + CONFINE_POINTER_MARGIN
                var maxX = box.minX + box.width - ruleClient.bw - CONFINE_POINTER_MARGIN - 1
                var maxY = box.minY + box.height - ruleClient.bw - CONFINE_POINTER_MARGIN - 1

                if maxX < minX {
                    maxX = minX
                }
                if maxY < minY {
                    maxY = minY
                }
                // not in mango: macOS has moved the pointer already, so it is put back inside (a near equivalent)
                let cursor = system.pointer
                let confined = CGPoint(x: min(max(cursor.x, minX), maxX), y: min(max(cursor.y, minY), maxY))
                if confined != cursor {
                    system.warp(to: confined)
                    dx -= cursor.x - confined.x
                    dy -= cursor.y - confined.y
                }
            }

            // not in mango: no wlr_cursor_move, macOS moves the pointer
            pointerCursorActivity()

            /* Update selected_monitor (even while dragging a window) */
            if config.sloppyfocus {
                let oldmon = selectedMonitor
                if let m = monitorAtPoint(system.pointer) { setSelectedMonitor(m) }   // not in mango: the pointer is always on a monitor
                if oldmon !== selectedMonitor {
                    printstatus([.monitor, .allMonitors])
                }
            }
        }

        /* Find the client under the pointer and send the event along. */
        let cursor = system.pointer
        var c = nodeAtPoint(cursor)
        var surface = surfaceAt(c, cursor)
        // not in mango: node_at_point's client is its surface's toplevel; the port finds them apart
        if let s = surface, let top = system.toplevelFromWlrSurface(s) { c = top }

        // not in mango: no hover on a group bar's close button (docs/afvigelser.md §4)

        if cursorMode == CurPressed,
           surface != system.pointerFocusedSurface,
           let focused = system.pointerFocusedSurface, let w = clientByIdAll(focused) {
            c = w
            surface = focused
        }

        if groupBarDragPending {
            let ddx = cursor.x - groupBarDragX
            let ddy = cursor.y - groupBarDragY
            if ddx * ddx + ddy * ddy >= 25.0 {
                let dc = groupBarDragClient
                groupBarDragPending = false
                groupBarDragClient = nil
                if let dc, !dc.iskilling {
                    if clientIsGroupMember(dc) {
                        _ = clientGroupLeave(dc)
                    }
                    clientFocus(dc, true)
                    pointerBeginMoveResize(dc, CurMove, cursor.x, cursor.y, [])
                }
            }
        }

        pointerUpdateResizeCursor(c, surface)

        /* If we are currently grabbing the mouse, handle and return */
        if cursorMode == CurMove, let gc = grabClient {
            /* Move the grabbed client to the new position. */
            gc.iscustomsize = true
            gc.floatGeom = CGRect(x: cursor.x.rounded() - grabOffsetX,
                                  y: cursor.y.rounded() - grabOffsetY,
                                  width: gc.geom.width,
                                  height: gc.geom.height)
            var target: Client?
            if gc.dragToTile {
                target = groupBarTargetAt(cursor.x, cursor.y, gc)
            }
            dropToGroup = target != nil
            if config.dragTileToTile && gc.dragToTile {
                closetDropClient = target ?? findClosestTiledClient(gc)
            } else {
                closetDropClient = target
            }

            if let closet = closetDropClient, let dc = dropClient, closet !== dc {
                dc.enableDropAreaDraw = false
                clientSetDropArea(dc)
                dropClient = closet
                closet.enableDropAreaDraw = true
                clientSetDropArea(closet)
            } else if let closet = closetDropClient {
                dropClient = closet
                closet.enableDropAreaDraw = true
                clientSetDropArea(closet)
            } else if let dc = dropClient {
                dc.enableDropAreaDraw = false
                clientSetDropArea(dc)
                dropClient = nil
            }
            resize(gc, gc.floatGeom, ResizeOpts(interact: true))
            return
        } else if cursorMode == CurResize, let gc = grabClient {
            if gc.isfloating {
                gc.iscustomsize = true
                if let m = gc.mon, m.lastResizeFrame != m.frameSerial {
                    m.lastResizeFrame = m.frameSerial
                    pointerResizeFloatingWindow(gc, cursor.x, cursor.y)
                }
                return
            } else {
                resizeTileClient(gc, true, 0, 0)
                return
            }
        }

        /* If there's no client surface under the cursor, set the cursor image
         * to a default. This is what makes the cursor image appear when you
         * move it off of a client or over its border. */
        if surface == nil && !cursorHidden {
            system.setCursor("default")
        }

        if let c, c.mon != nil, !c.animation.running,
           INSIDEMON(c) || !ISSCROLLTILED(c) {
            scrollerFocusLock = false
        }

        shouldLock = false
        var speed = 0.0

        if config.edgeScrollerPointerFocus {
            speed = (dx * dx + dy * dy).squareRoot()
        }

        let outside = c.map { $0.mon != nil && !INSIDEMON($0) } ?? false
        if !scrollerFocusLock || !outside {
            let offEdge = c.map { ISSCROLLTILED($0) && $0.mon.map { isScrollerLayout($0) } == true && outside } ?? false
            if offEdge {
                shouldLock = true
            }

            if !((!config.edgeScrollerPointerFocus ||
                  speed < config.edgeScrollerFocusAllowSpeed) && offEdge) {
                pointerFocus(c, surface, time)
            }

            if shouldLock, let c, let cm = c.mon, ISTILED(c), cm.sel == c.id {
                scrollerFocusLock = true
            }
        }

        // not in mango: no wlr_seat_pointer_notify_frame for time 0 (the seat sends the app nothing)
    }

    // not in mango: the event's fields (no device)
    func handleCursorMotion(_ time: UInt32, _ dx: Double, _ dy: Double) {
        /* The cursor doesn't move unless we tell it to. The cursor
         * automatically handles constraining the motion to the output layout,
         * as well as any special configuration applied for the specific input
         * device which generated the event. You can pass NULL for the device if
         * you want to move the cursor around without any input. */

        pointerProcessMotion(time, dx, dy)
        let cursor = system.pointer
        toggleHotarea(Int32(cursor.x), Int32(cursor.y))
    }

    // not in mango: no surface-local coordinates (the seat sends the app no enter or motion)
    func pointerFocus(_ c: Client?, _ surface: ClientID?, _ time: UInt32) {
        /* A data-device drag owns pointer focus, while its keyboard grab keeps the
         * previous keyboard surface. Do not turn each drag motion into a focus
         * change: the keyboard focus would be restored after the drag ends. */
        if config.sloppyfocus && !startDragWindow,
           let c, time != 0, c.platform.sceneNodeEnabled,
           c.mon == nil || !isOvercircleMode(c.mon), !c.animation.tagining,
           surface != system.pointerFocusedSurface ||
            (selectedMonitor != nil && selectedMonitor.isoverview && selectedMonitor.sel != c.id),
           VISIBLEON(c, c.mon) {
            clientFocus(c, false)
        }

        /* If surface is NULL, clear pointer focus */
        guard let surface else {
            system.seatPointerClearFocus()
            return
        }

        /* Let the client know that the mouse cursor has entered one
         * of its surfaces, and make keyboard focus follow if desired.
         * wlroots makes this a no-op if surface is already focused */

        if c == nil || c?.mon == nil || c?.mon?.isoverview == false {
            // don't let window get pointer focus,
            // avoid game window force grab pointer in overview mode
            system.seatPointerNotifyEnter(surface)
        }
    }

    func pointerCursorActivity() {
        hideCursorSource?.timerUpdate(Int32(config.cursorHideTimeout * 1000))

        if !cursorHidden { return }

        cursorHidden = false
        publishInputState()   // not in mango: the event tap's snapshot

        if drawsOverlays { system.setCursorHidden(false) }   // not in mango: the port's side
    }

    @discardableResult
    func pointerHideCursor() -> Int32 {
        if drawsOverlays { system.setCursorHidden(true) }   // not in mango: the port's side
        cursorHidden = true
        publishInputState()   // not in mango: the event tap's snapshot
        return 1
    }

    func pointerWarpToClient(_ c: Client) {
        // not in mango: in the overview mango's geom is the card; ours is the window under it
        let g = (c.mon?.isoverview == true ? c.mon?.ovCards[c.id] : nil) ?? c.geom
        guard let m = c.mon else { return }
        if g.minX >= m.m.minX && g.minY >= m.m.minY && g.minX + g.width <= m.m.minX + m.m.width
            && g.minY + g.height <= m.m.minY + m.m.height {
            system.warp(to: CGPoint(x: g.minX + g.width / 2.0, y: g.minY + g.height / 2.0))
            pointerProcessMotion(0, 0, 0)
        }
    }

    package func pointerWarpToMonitor(_ m: Monitor) {
        system.warp(to: CGPoint(x: m.w.minX + m.w.width / 2.0, y: m.w.minY + m.w.height / 2.0))
        system.setCursor("default")
        pointerCursorActivity()
    }

    func findClosestTiledClient(_ c: Client) -> Client? {
        var closest: Client?
        var minDist = Int.max
        let cursor = system.pointer
        let cursorMon = monitorAtPoint(cursor)

        for tc in clients {
            if tc === c || !ISTILED(tc) || !VISIBLEON(tc, cursorMon) { continue }

            if cursor.x >= tc.geom.minX &&
                cursor.x < tc.geom.minX + tc.geom.width &&
                cursor.y >= tc.geom.minY &&
                cursor.y < tc.geom.minY + tc.geom.height {
                return tc
            }

            let dx = Int(Int32((tc.geom.minX + CGFloat(Int32(tc.geom.width) / 2) - cursor.x).rounded(.towardZero)))
            let dy = Int(Int32((tc.geom.minY + CGFloat(Int32(tc.geom.height) / 2) - cursor.y).rounded(.towardZero)))
            let dist = dx * dx + dy * dy

            if dist < minDist {
                minDist = dist
                closest = tc
            }
        }

        return closest
    }

    func pointerPlaceDragTile(_ c: Client) {
        let closest = findClosestTiledClient(c)

        if let closest, let cm = closest.mon {
            let layout = cm.pertag.ltidxs[getClientTagIdx(closest)]

            if closest.dropDirection == UNDIR {
                clientSetFloating(c, false, false)
                wlListSafeReinsertPrev(closest, c)
                arrange(cm, false, false)
                return
            }

            if layout == .scroller {
                scrollerDropTile(c, closest, false)
                return
            }
            if layout == .verticalScroller {
                scrollerDropTile(c, closest, true)
                return
            }
            if layout == .dwindle, let m = c.mon {
                let tag = getClientTagIdx(c)
                let insertBefore = closest.dropDirection == LEFT || closest.dropDirection == UP
                let splitH = closest.dropDirection == LEFT || closest.dropDirection == RIGHT
                dwindleInsert(&m.pertag.dwindleRoot[tag], c, closest, Float(config.dwindleSplitRatio), insertBefore,
                              splitH, !config.dwindleDropSimpleSplit)
                clientSetFloating(c, false, false)
                return
            }

            if layout == .rightTile {
                if closest.dropDirection == LEFT {
                    wlListSafeReinsertNext(closest, c)
                } else if closest.dropDirection == RIGHT {
                    wlListSafeReinsertPrev(closest, c)
                } else if closest.dropDirection == UP {
                    wlListSafeReinsertPrev(closest, c)
                } else {
                    wlListSafeReinsertNext(closest, c)
                }
                clientSetFloating(c, false, false)
                return
            }

            if closest.dropDirection == LEFT || closest.dropDirection == UP {
                wlListSafeReinsertPrev(closest, c)
            } else {
                wlListSafeReinsertNext(closest, c)
            }
        }

        clientSetFloating(c, false, false)
    }

    // not in mango: the button as macOS numbers it, `p` where the press was, `bar` the port's bar panel that
    // took the press, `borderResizeTaken` whether the event tap took it from the app
    @discardableResult
    func pointerProcessButtonPress(button: Int, pressed: Bool, at p: CGPoint, mods: Modifiers,
                                   bar: BarButton? = nil, borderResizeTaken: Bool = true) -> Bool {
        var c: Client?
        let oldPointerFocusSurface = system.pointerFocusedSurface

        pointerCursorActivity()

        if trackpadGestureDragActive() {
            return true
        }

        system.keyboardCancelPendingReleaseBind()

        if pressed {
            cursorMode = CurPressed
            if let m = monitorAtPoint(p) { setSelectedMonitor(m) }   // not in mango: the pointer is always on a monitor

            if switcherIsActive() && (button == 0 || button == 1) {
                let switcherC =
                    switcherClientAt(p.x, p.y)
                if switcherC == nil {
                    switcherClose()
                } else if button == 0 {
                    switcherCommitClient(switcherC!)
                } else {
                    pendingKillClient(switcherC!)
                }
                system.seatPointerClearFocus()
                return true
            }

            // not in mango: a press on the port's bar panels comes as `bar`, not under node_at_point
            c = bar == nil ? nodeAtPoint(p) : nil
            let surface = bar == nil ? surfaceAt(c, p) : nil
            if let c {
                if c.platform.sceneNodeEnabled && VISIBLEON(c, c.mon) {
                    clientFocus(c, true)
                }

                if surface != oldPointerFocusSurface {
                    system.seatPointerClearFocus()
                    pointerProcessMotion(0, 0, 0)
                }
            }

            // In overview mode, left click jumps and right click closes windows.
            if let sm = selectedMonitor, sm.isoverview, button == 0, let c {
                toggleOverview(Arg(tc: c))
                return true
            }

            if let sm = selectedMonitor, sm.isoverview, button == 1, let c {
                pendingKillClient(c)
                return true
            }

            if let bar, !bar.isTab, button == 0, let tc = clientByIdAll(bar.client) {
                if bar.onClose {
                    pendingKillClient(tc)
                    return true
                }

                clientHandleDecorateClick(tc, isTab: false)

                if !tc.isfullscreen && !tc.ismaximizescreen {
                    groupBarDragPending = true
                    groupBarDragClient = tc
                    groupBarDragX = p.x
                    groupBarDragY = p.y
                }
                return true
            }

            /* Optionally close the clicked tab with a right click. */
            if let bar, bar.isTab, button == 1, config.monocleRightButtonClose, let tc = clientByIdAll(bar.client) {
                pendingKillClient(tc)
                return true
            }

            // handle click on tile node
            if let bar, let tc = clientByIdAll(bar.client) { clientHandleDecorateClick(tc, isTab: bar.isTab) }

            let clean = mods.subtracting(.fn)

            for m in config.mouseBindings {
                if (m.mode == "common" || m.mode == keyMode) &&
                    clean == m.mods &&
                    button == m.button.cgButtonNumber {
                    _ = dispatch(m.dispatch)
                    return true
                }
            }

            /* Don't send the press to the surface that a bar/tab click switched
             * to. The seat drops its release too, so the client never sees a
             * click. */
            if bar != nil { return true }

            // not in mango: only a press the event tap took from the app (docs/afvigelser.md §3)
            if button == 0, let c, bar == nil, config.enableBorderResize, borderResizeTaken {
                let edge = clientResizeEdgeAt(c, surface, p.x, p.y)
                if !edge.isEmpty && pointerBeginMoveResize(c, CurResize, p.x, p.y, edge) {
                    return true
                }
            }
            return false
        }

        groupBarDragPending = false
        dropToGroup = false
        groupBarDragClient = nil
        if cursorMode == CurMove, let jc = grabClient, jc.dragToTile {
            if let target = groupBarTargetAt(p.x, p.y, jc) {
                system.grabEnded(jc)   // not in mango: the port's side
                grabClient = nil
                cursorMode = CurNormal
                startDragWindow = false
                jc.dragToTile = false
                if let dc = dropClient {
                    dc.enableDropAreaDraw = false
                    clientSetDropArea(dc)
                    dropClient = nil
                }
                clientGroupJoin(jc, target)
                system.seatPointerClearFocus()
                return true
            }
        }
        /* If you released any buttons, we exit interactive move/resize mode. */
        if cursorMode != CurNormal && cursorMode != CurPressed {
            pointerEndGrabClient(true)
            return true
        } else {
            cursorMode = CurNormal
        }
        /* If the event wasn't handled by the compositor, return false */
        return false
    }
}

/// Not in mango: mango's pointer decisions, taken on the port's event-tap thread (macOS wants the answer at once).
package enum Pointer {
    package enum ButtonPress: Equatable {
        case switcher
        case overview
        case mouseBinding(MouseBinding)
        case borderResize
        case none
    }

    /// mango pointer_process_button_press (pointer.c), what the event tap must know at once.
    package static func pointerProcessButtonPress(button: Int, at p: CGPoint, mods: Modifiers, switcherActive: Bool,
                                                  overviewFrame: CGRect?, mouseBindings: [MouseBinding],
                                                  mode: String, hoverResizeEdge: Bool = false) -> ButtonPress {
        if switcherActive && (button == 0 || button == 1) { return .switcher }
        if let f = overviewFrame, f.contains(p), button == 0 || button == 1 { return .overview }
        let mods = mods.subtracting(.fn)
        if let b = mouseBindings.first(where: {
            ($0.mode == "common" || $0.mode == mode) && $0.mods == mods && $0.button.cgButtonNumber == button
        }) {
            return .mouseBinding(b)
        }
        if button == 0 && hoverResizeEdge { return .borderResize }
        return .none
    }

    /// mango handle_cursor_axis (pointer.c)
    // not in mango: the event's orientation, delta and time; the binding found is run on the main thread,
    // and nil forwards the event to the app
    package static func handleCursorAxis(vertical: Bool, delta: Double, timeMsec: UInt32, mods: Modifiers,
                                         axisBindings: [AxisBinding], mode: String, axisBindApplyTimeout: UInt32,
                                         axisApplyTime: inout UInt32, axisApplyDir: inout Int32)
        -> (binding: AxisBinding, fires: Bool)? {
        let mods = mods.subtracting(.fn)
        let adir: UInt32

        if vertical {
            adir = delta > 0 ? AxisDown : AxisUp
        } else {
            adir = delta > 0 ? AxisRight : AxisLeft
        }

        for a in axisBindings {
            if (a.mode == "common" || a.mode == mode) &&
                mods == a.mods && // Same modifier set
                (a.dir == UInt32(ALLDIR) || adir == a.dir) { // Wheel direction matches and a handler exists
                if timeMsec &- axisApplyTime > axisBindApplyTimeout ||
                    Double(axisApplyDir) * delta < 0 {
                    axisApplyTime = timeMsec
                    axisApplyDir = delta > 0 ? 1 : -1
                    return (a, true) // If matched, do not forward this scroll event to the
                    // client.
                } else {
                    axisApplyDir = delta > 0 ? 1 : -1
                    axisApplyTime = timeMsec
                    return (a, false)
                }
            }
        }

        return nil
    }
}
