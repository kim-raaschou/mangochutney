import QuartzCore

package struct Grab {
    package enum Mode { case move, resize }
    package let client: Client
    let mode: Mode
    var startMouse: CGPoint
    let startFrame: CGRect
    /// mango's server.resize_edge.
    var resizeEdge: WlrEdges = []
    /// mango's server.grab_is_border_resize.
    var isBorderResize = false
    /// mango's server.grab_pointer_x and _y.
    var grabPointer: CGPoint = .zero
}

package extension MangoServer {
    /// Not in mango: hands binding state to the event-tap thread.
    func publishInputState() {
        let ov = overviewState
        let c = config
        let mode = keyMode
        let sw = switcherState != nil
        let hidden = cursorHidden
        let combo = tagCombo
        system.publishInput(InputState(
            keymode: mode, bindings: c.keyBindings, mouseBindings: c.mouseBindings, axisBindings: c.axisBindings,
            axisTimeout: Double(c.axisBindApplyTimeout) / 1000, overviewFrame: ov?.monitor.screen.frame,
            jumpLabels: ov?.jump.map { Array($0.keys) },
            overcircleActive: ov?.circle == true && ov?.jump == nil, switcherActive: sw, tagCombo: combo,
            wantsMouseMoved: c.sloppyfocus || c.enableHotarea || c.cursorHideTimeout > 0 || hidden
                || c.windowRules.contains { $0.confinePointer == true } || c.enableBorderResize,
            cursorHideOnKeypress: c.cursorHideOnKeypress && !hidden,
            hoverResizeCursor: hoverResizeEdge.isEmpty || grab != nil ? nil : resizeCursorName(hoverResizeEdge, floating: hoverResizeFloating),
            capsHyper: Self.xkbOptions(c.xkbRulesOptions).contains("caps:hyper")
                ? Modifiers.parse("hyper", hyperModifier: c.hyperModifier) : nil))
        publishGlobalKeys()
    }

    static func xkbOptions(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

/// mango keyboard_process_global_keypress
    func publishGlobalKeys() {
        let rules = config.windowRules.filter { $0.globalKeyBinding != nil && ($0.appId != nil || $0.title != nil) }
        guard !rules.isEmpty || publishedGlobalKeys else { return }
        let focusedNow = focused
        let windows = clients
        var keys: [GlobalKey] = []
        for r in rules {
            guard let spec = r.globalKeyBinding, let dash = spec.firstIndex(of: "-"),
                  let mods = Modifiers.parse(String(spec[..<dash]), hyperModifier: config.hyperModifier) else { continue }
            let name = String(spec[spec.index(after: dash)...]).trimmingCharacters(in: .whitespaces)
            guard let target = windows.first(where: {
                $0 !== focusedNow && r.isWindowRuleMatches(appId: $0.bundleId, appName: $0.appName, title: $0.title)
            }), target.pid != focusedNow?.pid else { continue }
            keys.append(GlobalKey(mods: mods, keyName: name, pid: target.pid))
        }
        publishedGlobalKeys = !keys.isEmpty
        system.publishGlobalKeys(keys)
    }

    // not in mango: what the port's event-tap thread decided (Keyboard.handleKeyboardKey), on the main thread
    func handleKeyboardKey(_ actions: [KeyAction]) {
        for a in actions {
            switch a {
            case .leaveOvercircle:
                if let ov = overviewState, ov.circle, ov.jump == nil {
                    leaveOverview(select: ov.circleFocus.flatMap { clientByIdAll($0) })
                }
            case .switcherCommit:
                switcherCommit()
            case .hideCursor:
                if config.cursorHideOnKeypress { pointerHideCursor() }
            case .endTagCombo:
                tagCombo = false
            case .binding(let b, let held):
                _ = dispatch(b.dispatch, rescan: !held)
            case .overviewKey(.escape):
                leaveOverview(select: nil)
            case .overviewKey(.jump(let name)):
                if let id = overviewState?.jump?[name], let c = clientByIdAll(id) { leaveOverview(select: c) }
            case .forward:
                break
            }
        }
    }

/// Not in mango: the port has no scene, so the stacking of node_at_point is spelled out.
    package func clientAtPoint(_ p: CGPoint, on m: Monitor? = nil) -> Client? {
        let mon = m ?? monitorAtPoint(p)
        guard let mon else { return nil }
        if let ov = overviewState, ov.monitor === mon {
            return ov.cards.first { $0.value.contains(p) }.flatMap { clientByIdAll($0.key) }
        }
        let vis = (isSpecialActive(mon) ? specialClients(mon) : visibleClients(mon)).filter { !$0.parked }
        if let f = vis.first(where: { ($0.isFloating || $0.scratchpadShown) && clientGeom($0).contains(p) }) { return f }
        if let s = mon.sel.flatMap({ clientByIdAll($0) }), vis.contains(where: { $0 === s }), clientGeom(s).contains(p) { return s }
        return vis.first { clientGeom($0).contains(p) }
    }

    /// Not in mango: the surface of mango's xytonode; the border is a node, not a surface.
    func surfaceAt(_ c: Client?, _ p: CGPoint) -> ClientID? {
        guard let c, c.frame.contains(p) else { return nil }
        return system.surfaceAt(p)
    }

    /// Not in mango: mango's geom, with the border (our frame is without it).
    func clientGeom(_ c: Client) -> CGRect {
        let bw = borderWidth(c, on: c.mon ?? selectedMonitor)
        return c.frame.insetBy(dx: -bw, dy: -bw)
    }

    func pendingKillClient(_ c: Client) { system.clientSendClose(c) }

    @discardableResult
    func pointerProcessButtonPress(button: Int, pressed: Bool, at p: CGPoint, mods: Modifiers,
                                   bar: BarButton? = nil, borderResizeTaken: Bool = true) -> Bool {
        pointerCursorActivity()
        if pressed {
            if let m = monitorAtPoint(p) { selectedMonitor = m }
            if let sw = switcherState, button == 0 || button == 1 {
                guard let i = sw.layout.tiles.firstIndex(where: { $0.contains(p) }),
                      let sc = clientByIdAll(sw.tiles[i]) else { switcherClose(); return true }
                if button == 0 { switcherCommitClient(sc) } else { pendingKillClient(sc) }
                return true
            }
            let c = bar == nil ? clientAtPoint(p) : nil
            // not in mango: not in overview, and not the focused one again (macOS has focused it with the click)
            if let c, let cm = c.mon, c.isVisible(on: cm), overviewState == nil, selectedMonitor.sel != c.id {
                clientFocus(c)
            }
            if overviewState != nil, let c, button == 0 { leaveOverview(select: c); return true }
            if overviewState != nil, let c, button == 1 { pendingKillClient(c); return true }
            if let bar, !bar.isTab, button == 0, let tc = clientByIdAll(bar.client) {
                if bar.onClose { pendingKillClient(tc); return true }
                clientHandleDecorateClick(tc, isTab: false)
                if !tc.isFullscreen && !tc.isMaximizeScreen { groupBarDrag = (tc, p) }
                return true
            }
            if let bar, bar.isTab, button == 1, config.monocleRightButtonClose, let tc = clientByIdAll(bar.client) {
                pendingKillClient(tc)
                return true
            }
            if let bar, let tc = clientByIdAll(bar.client) { clientHandleDecorateClick(tc, isTab: bar.isTab) }
            let clean = mods.subtracting(.fn)
            if let m = config.mouseBindings.first(where: {
                ($0.mode == "common" || $0.mode == keyMode) && $0.mods == clean && $0.button.cgButtonNumber == button
            }) {
                _ = dispatch(m.dispatch)
                return true
            }
            if bar != nil { return true }
            // not in mango: only a press the event tap took from the app (docs/afvigelser.md §3)
            if button == 0, let c, bar == nil, config.enableBorderResize, borderResizeTaken {
                let edge = clientResizeEdgeAt(c, surfaceAt(c, p), p.x, p.y)
                if !edge.isEmpty && pointerBeginMoveResize(c, .resize, at: p, edge: edge) { return true }
            }
            return false
        }
        groupBarDrag = nil
        if let g = grab, g.mode == .move, let d = dragTile, d.client === g.client,
           let target = groupBarTargetAt(at: p, except: g.client) {
            grab = nil
            startDragWindow = false
            lastApplyDragTime = 0
            dragTile = nil
            system.showDropArea(nil, color: config.dropcolor)
            g.client.isFloating = false
            g.client.floatGeom = d.floatBackup
            clientGroupJoin(g.client, into: target)
            printstatus()
            return true
        }
        if let g = grab {
            pointerEndGrabClient(g, at: p, followPointer: true)
            return true
        }
        return false
    }

    @discardableResult
    func pointerBeginMoveResize(_ c: Client?, _ mode: Grab.Mode, at p: CGPoint, edge: WlrEdges = []) -> Bool {
        guard grab == nil else { return false }
        guard let c, !c.isFullscreen, !c.isMaximizeScreen else { return false }
        system.cancelAnimation(c.id)
        if mode == .move && !c.isFloating { clientBeginDragFloat(c, at: p) }
        let start = c.frame
        var g = Grab(client: c, mode: mode, startMouse: p, startFrame: start)
        g.isBorderResize = !edge.isEmpty
        var cursor = p
        switch mode {
        case .move:
            system.setCursor("grab")
        case .resize:
            if c.isFloating || c.scratchpadShown {
                var resizeEdge = edge
                if resizeEdge.isEmpty {
                    let geom = clientGeom(c)
                    var corner = config.dragCorner
                    if corner == 4 {
                        corner = (p.x - geom.minX < geom.minX + geom.width - p.x ? 0 : 1)
                            + (p.y - geom.minY < geom.minY + geom.height - p.y ? 0 : 2)
                    }
                    resizeEdge = corner & 1 != 0 ? .right : .left
                    resizeEdge.formUnion(corner & 2 != 0 ? .bottom : .top)
                }
                g.resizeEdge = resizeEdge
                var grabX = p.x.rounded(), grabY = p.y.rounded()
                /* A border grab already sits on the grabbed edge; only the
                 * drag_corner path warps the pointer onto it. */
                if config.dragWarpCursor && edge.isEmpty {
                    let geom = clientGeom(c)
                    var warp = p
                    if !resizeEdge.isDisjoint(with: [.left, .right]) {
                        grabX = resizeEdge.contains(.right) ? geom.minX + geom.width : geom.minX
                        warp.x = grabX
                    }
                    if !resizeEdge.isDisjoint(with: [.top, .bottom]) {
                        grabY = resizeEdge.contains(.bottom) ? geom.minY + geom.height : geom.minY
                        warp.y = grabY
                    }
                    system.warp(to: warp)
                    cursor = warp
                }
                g.startMouse = CGPoint(x: grabX, y: grabY)
                system.setCursor(resizeCursorName(resizeEdge, floating: true))
            } else {
                system.setCursor(!edge.isEmpty ? resizeCursorName(edge, floating: false) : "grab")
            }
        }
        g.grabPointer = cursor
        grab = g
        system.grabBegan(c)   // not in mango: the port's side
        return true
    }

    func pointerEndGrabClient(_ g: Grab, at p: CGPoint, followPointer: Bool = true) {
        let c = g.client
        system.grabEnded(c)   // not in mango: the port's side
        defer { system.settle(c) }
        guard let m = c.mon else { grab = nil; return }
        let moved = p != g.grabPointer
        /* A plain click on a resize border must not snap the window; every other
         * grab keeps snapping as before, even when the pointer never moved. */
        let borderResize = g.isBorderResize
        /* Clear the pointer focus, this way if the cursor is over a surface
         * we will send an enter event after which the client will provide
         * us a cursor surface */
        system.setCursor(nil)
        let sm: Monitor = selectedMonitor
        if sm.sel == c.id { sm.sel = nil }
        let target = (followPointer ? monitorAtPoint(p) : monitorAtPoint(c.frame.center)) ?? m
        selectedMonitor = target
        clientUpdateOldmonnameRecord(c, target)
        clientSetMonitor(c, target, 0, focus: true)
        if !c.isVisible(on: target) { c.tags = target.tagset[target.seltags] }
        let sel = target.sel.flatMap { clientByIdAll($0) }
        target.prevsel = sel.map { !$0.isFloating && !$0.isMinimized && !$0.isMaximizeScreen && !$0.isFullscreen && !$0.isUnglobal } == true ? sel?.id : nil
        target.sel = c.id
        grab = nil
        // not in mango: of pointer_process_motion(0, …) only its resize cursor
        let pointed = clientAtPoint(p)
        pointerUpdateResizeCursor(pointed, surfaceAt(pointed, p), p)
        startDragWindow = false
        lastApplyDragTime = 0
        if dragTile?.client === c {
            dropDraggedTile(at: p)
            if config.dragTileToTile { printstatus(); return }
        }
        arrange(target, g.mode == .resize ? .none : .move)
        if !borderResize || moved { applyWindowSnap(c) }
        printstatus()
    }

    func toggleHotarea(_ p: CGPoint) {
        guard let m = selectedMonitor, grab == nil else { return }
        if config.hotareaDisableOnFullscreen, let f = focused, f.isFullscreen, f.isVisible(on: m) {
            m.isInHotarea = false
            return
        }
        let f = m.screen.frame, s = CGFloat(config.hotareaSize)
        let inHotarea: Bool
        switch config.hotareaCorner {
        case 3: inHotarea = p.y > f.maxY - s && p.x > f.maxX - s && p.x <= f.maxX && p.y <= f.maxY
        case 0: inHotarea = p.y < f.minY + s && p.x < f.minX + s && p.x >= f.minX && p.y >= f.minY
        case 1: inHotarea = p.y < f.minY + s && p.x > f.maxX - s && p.x <= f.maxX && p.y >= f.minY
        default: inHotarea = p.y > f.maxY - s && p.x < f.minX + s && p.x >= f.minX && p.y <= f.maxY
        }
        if config.enableHotarea && !m.isInHotarea && inHotarea {
            toggleOverview(onlyCurrent: false, jump: false)
            m.isInHotarea = true
        } else if config.enableHotarea && m.isInHotarea && !inHotarea {
            m.isInHotarea = false
        }
    }

    func pointerConfineRuleClient() -> Client? {
        guard let c = focused, c.confinePointer, let m = c.mon, overviewState?.monitor !== m,
              !c.isMinimized, c.isVisible(on: m) else { return nil }
        return c
    }

    func pointerCheckConfineClient() {
        let c = pointerConfineRuleClient()
        if let c, c.id != confinePointerLast, !c.frame.contains(system.pointer) {
            system.warp(to: CGPoint(x: c.frame.midX, y: c.frame.midY))
        }
        confinePointerLast = c?.id
    }

    func handleCursorMotion(_ p: CGPoint, time: UInt32, speed: CGFloat = 0) {
        let cursor = pointerProcessMotion(p, time: time, speed: speed)
        toggleHotarea(cursor)
    }

    // not in mango: the cursor where the motion left it (wlroots' cursor)
    @discardableResult
    func pointerProcessMotion(_ moved: CGPoint, time: UInt32, speed: CGFloat = 0) -> CGPoint {
        var p = moved
        if time != 0 {
// not in mango: macOS has moved the pointer already, so it is put back inside (a near equivalent).
            if grab == nil, let c = pointerConfineRuleClient() {
                let f = c.frame
                let q = CGPoint(x: min(max(p.x, f.minX + 5), max(f.minX + 5, f.maxX - 5 - 1)),
                                y: min(max(p.y, f.minY + 5), max(f.minY + 5, f.maxY - 5 - 1)))
                if q != p { system.warp(to: q); p = q }
            }
            pointerCursorActivity()
            if config.sloppyfocus, let m = monitorAtPoint(p), m !== selectedMonitor {
                selectedMonitor = m
                printstatus()
            }
        }
        if let d = groupBarDrag {
            let dx = p.x - d.start.x, dy = p.y - d.start.y
            if dx * dx + dy * dy >= 25 {
                groupBarDrag = nil
                let dc = d.client
                if clientByIdAll(dc.id) === dc {
                    if dc.isGroupMember { _ = clientGroupLeave(dc) }
                    clientFocus(dc)
                    pointerBeginMoveResize(dc, .move, at: p)
                }
            }
        }
        let pointed = clientAtPoint(p)
        pointerUpdateResizeCursor(pointed, surfaceAt(pointed, p), p)

        if let g = grab {
            let c = g.client
            switch g.mode {
            case .move:
                let f = g.startFrame.offsetBy(dx: p.x - g.startMouse.x, dy: p.y - g.startMouse.y)
                c.isCustomSize = true
                c.floatGeom = f
                updateDragTile(at: p)
                c.frame = f
                system.setFrame(c, f, size: false)
                updateBorders(animating: [c.id: f])
            case .resize:
                if c.isFloating || c.scratchpadShown {
                    c.isCustomSize = true
                    if lastApplyDragTime == 0 || time &- lastApplyDragTime >= dragRefreshIntervalMs(c.mon) {
                        pointerResizeFloatingWindow(c, p.x, p.y)
                        lastApplyDragTime = time
                    }
                } else {
                    resizeTileClient(c, isdrag: true, offsetX: 0, offsetY: 0, cursor: p, time: time)
                }
            }
            return p
        }
        if let ov = overviewState {
// not in mango: without raising; the real window is under the pictures.
            guard config.sloppyfocus, !ov.circle, let c = clientAtPoint(p), selectedMonitor.sel != c.id else { return p }
            clientFocus(c, raise: false)
            return p
        }
        // not in mango: a held button is an app's own drag (macOS moves its window)
        guard config.sloppyfocus, system.mouseButtons == 0 else { return p }
        guard let m = monitorAtPoint(p), let c = clientAtPoint(p, on: m) else { return p }
        let inside = m.screen.frame.contains(c.frame)
        let scrollTiled = !c.isFloating && !c.isMinimized && !c.isUnglobal
        if inside || !scrollTiled { scrollerFocusLock = false }
        if scrollerFocusLock && !inside { return p }
        let offEdge = scrollTiled && m.layout.isScroller && !inside
        let held = offEdge && (!config.edgeScrollerPointerFocus || Double(speed) < config.edgeScrollerFocusAllowSpeed)
        if !held && (selectedMonitor.sel != c.id || selectedMonitor !== m) { clientFocus(c, raise: false, makeKey: true) }
        if offEdge && m.sel == c.id { scrollerFocusLock = true }
        return p
    }

    func pointerResizeFloatingWindow(_ gc: Client, _ x: CGFloat, _ y: CGFloat) {
        guard var g = grab else { return }
        let edge = g.resizeEdge
        let bw = borderWidth(gc, on: gc.mon ?? selectedMonitor)
        let minW = 1 + 2 * bw
        let minH = 1 + 2 * bw
        var cdx: CGFloat = 0, cdy: CGFloat = 0
        let geom = clientGeom(gc)
        var box = geom

        if !edge.isDisjoint(with: [.left, .right]) {
            cdx = x.rounded() - g.startMouse.x
            if edge.contains(.right) {
                if geom.width + cdx < minW { cdx = minW - geom.width }
                box.size.width = geom.width + cdx
            } else {
                if geom.width - cdx < minW { cdx = geom.width - minW }
                box.origin.x = geom.minX + cdx
                box.size.width = geom.width - cdx
            }
        }

        if !edge.isDisjoint(with: [.top, .bottom]) {
            cdy = y.rounded() - g.startMouse.y
            if edge.contains(.bottom) {
                if geom.height + cdy < minH { cdy = minH - geom.height }
                box.size.height = geom.height + cdy
            } else {
                if geom.height - cdy < minH { cdy = geom.height - minH }
                box.origin.y = geom.minY + cdy
                box.size.height = geom.height - cdy
            }
        }

        let f = box.insetBy(dx: bw, dy: bw)   // not in mango: our frame is without the border
        gc.floatGeom = f

        gc.frame = f
        system.setFrame(gc, f, size: true)
        updateBorders(animating: [gc.id: f])
        g.startMouse.x += cdx
        g.startMouse.y += cdy
        grab = g
    }

    /// mango client_resize_grab (pointer.c).
    func clientResizeGrab(_ c: Client) -> CGFloat {
        if config.borderResizeSize > 0 { return CGFloat(config.borderResizeSize) }
        return borderWidth(c, on: c.mon ?? selectedMonitor)
    }

    /* Returns the subset of `cand` edges of `c` that face another tiled window on
     * the same monitor. Tiled layouts pack windows flush against their neighbours
     * (separated only by the inner gap), so an edge is shared exactly when a tiled
     * window lies on that side of `c` and overlaps it on the perpendicular axis.
     * The neighbour's box is compared as-is, no gap/decoration knowledge needed. */
    func tiledSharedEdges(_ c: Client, _ cand: WlrEdges) -> WlrEdges {
        let a = clientGeom(c)
        var shared: WlrEdges = []

        for o in clients {
            guard o !== c, o.mon === c.mon, let om = o.mon, o.isVisible(on: om), Self.isTiled(o) else { continue }

            let b = clientGeom(o)
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

    /// mango ISTILED (client.h).
    static func isTiled(_ c: Client) -> Bool {
        !c.isFloating && !c.isMinimized && !c.isMaximizeScreen && !c.isFullscreen && !c.isUnglobal
    }

    func clientResizeEdgeAt(_ c: Client, _ surface: ClientID?, _ x: CGFloat, _ y: CGFloat) -> WlrEdges {
        if c.parked { return [] }   // not in mango: c->scene->node.enabled is the port's parked
        if c.isFullscreen || c.isMaximizeScreen || c.overviewIsMaximizeScreenBak || c.overviewIsFullscreenBak { return [] }
        /* A popup or any other child surface sitting on the border grab strip
         * must keep receiving its own input instead of resizing the parent. */
        if let surface, surface != c.id { return [] }
        guard let m = c.mon, overviewState?.monitor !== m, c.isVisible(on: m) else { return [] }

        var t = clientResizeGrab(c)
        if t <= 0 { return [] }

        let g = clientGeom(c)
        if x < g.minX || x >= g.minX + g.width || y < g.minY || y >= g.minY + g.height { return [] }

        t = min(t, (g.width / 2).rounded(.down))
        t = min(t, (g.height / 2).rounded(.down))

        var edge: WlrEdges = []
        if x < g.minX + t { edge.insert(.left) }
        if x >= g.minX + g.width - t { edge.insert(.right) }
        if y < g.minY + t { edge.insert(.top) }
        if y >= g.minY + g.height - t { edge.insert(.bottom) }

        if !edge.isEmpty && !c.isFloating {
            if !Self.isTiled(c) { return [] }
            edge = tiledSharedEdges(c, edge)
        }

        return edge
    }

    func resizeCursorName(_ edge: WlrEdges, floating: Bool) -> String {
        if floating { return wlrXcursorGetResizeName(edge) }
        return !edge.isDisjoint(with: [.left, .right]) ? "col-resize" : "row-resize"
    }

    func pointerUpdateResizeCursor(_ c: Client?, _ surface: @autoclosure () -> ClientID?, _ p: CGPoint) {
        // not in mango: cursor_mode CurNormal is no grab and no button held
        guard grab == nil, system.mouseButtons == 0 else { return }

        var edge: WlrEdges = []
        if config.enableBorderResize && !cursorHidden, let c {
            edge = clientResizeEdgeAt(c, surface(), p.x, p.y)
        }

        let floating = !edge.isEmpty && c?.isFloating == true
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
            system.setCursor(resizeCursorName(edge, floating: floating))
        } else if changed && !previous.isEmpty {
            /* Leaving the strip hands the cursor back to the client: drop the
             * pointer focus so pointer_focus() re-enters and the client sends
             * its own cursor again. No remembered client cursor is replayed. */
            system.setCursor(nil)
        }
    }

    @discardableResult
    func fireGestureMotion(_ dir: Direction, _ fingers: Int) -> Bool {
        let mods = system.modifiers.subtracting(.fn)
        var handled = false
        for b in config.gestureBindings where (b.mode == "common" || b.mode == keyMode) && b.mods == mods
            && b.fingers == fingers && !b.isUndir && (b.direction == nil || b.direction == dir) {
            if b.dispatch.name == "moveresize" { continue }
            _ = dispatch(b.dispatch)
            handled = true
        }
        return handled
    }
}
