import QuartzCore

package struct Grab {
    package enum Mode { case move, resize }
    package let client: Client
    let mode: Mode
    var startMouse: CGPoint
    let startFrame: CGRect
    var right = true, bottom = true
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
                || c.windowRules.contains { $0.confinePointer == true },
            cursorHideOnKeypress: c.cursorHideOnKeypress && !hidden,
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
        if let f = vis.first(where: { ($0.isFloating || $0.scratchpadShown) && $0.frame.contains(p) }) { return f }
        if let s = mon.sel.flatMap({ clientByIdAll($0) }), vis.contains(where: { $0 === s }), s.frame.contains(p) { return s }
        return vis.first { $0.frame.contains(p) }
    }

    func pendingKillClient(_ c: Client) { system.clientSendClose(c) }

    @discardableResult
    func pointerProcessButtonPress(button: Int, pressed: Bool, at p: CGPoint, mods: Modifiers,
                                   bar: BarButton? = nil) -> Bool {
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
            // not in mango: no enable_border_resize; an app's window is resized by its own edges
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
    func pointerBeginMoveResize(_ c: Client?, _ mode: Grab.Mode, at p: CGPoint) -> Bool {
        guard grab == nil else { return false }
        guard let c, !c.isFullscreen, !c.isMaximizeScreen else { return false }
        system.cancelAnimation(c.id)
        if mode == .move && !c.isFloating { clientBeginDragFloat(c, at: p) }
        let start = c.frame
        var g = Grab(client: c, mode: mode, startMouse: p, startFrame: start)
        if mode == .resize && (c.isFloating || c.scratchpadShown) {
            var corner = config.dragCorner
            if corner == 4 { corner = (p.x - start.minX < start.maxX - p.x ? 0 : 1) + (p.y - start.minY < start.maxY - p.y ? 0 : 2) }
            g.right = corner & 1 != 0
            g.bottom = corner & 2 != 0
            if config.dragWarpCursor {
                g.startMouse = CGPoint(x: g.right ? start.maxX : start.minX, y: g.bottom ? start.maxY : start.minY)
                system.warp(to: g.startMouse)
            }
        }
        grab = g
        system.ignoreMoves(c, until: CACurrentMediaTime() + 3600)   // not in mango: the app's own reports of the drag
        return true
    }

    func pointerEndGrabClient(_ g: Grab, at p: CGPoint, followPointer: Bool = true) {
        let c = g.client
        system.ignoreMoves(c, until: CACurrentMediaTime() + 0.4)   // not in mango: the app's last reports of the drag
        defer { system.settle(c) }
        guard let m = c.mon else { grab = nil; return }
        let sm: Monitor = selectedMonitor
        if sm.sel == c.id { sm.sel = nil }
        let target = (followPointer ? monitorAtPoint(p) : monitorAtPoint(c.frame.center)) ?? m
        selectedMonitor = target
        c.homeDisplayID = target.screen.displayID
        clientSetMonitor(c, target, 0, focus: true)
        if !c.isVisible(on: target) { c.tags = target.tagset[target.seltags] }
        let sel = target.sel.flatMap { clientByIdAll($0) }
        target.prevsel = sel.map { !$0.isFloating && !$0.isMinimized && !$0.isMaximizeScreen && !$0.isFullscreen && !$0.isUnglobal } == true ? sel?.id : nil
        target.sel = c.id
        grab = nil
        startDragWindow = false
        lastApplyDragTime = 0
        if dragTile?.client === c {
            dropDraggedTile(at: p)
            if config.dragTileToTile { printstatus(); return }
        }
        arrange(target, g.mode == .resize ? .none : .move)
        applyWindowSnap(c)
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
        if let g = grab {
            let c = g.client
            switch g.mode {
            case .move:
                let f = g.startFrame.offsetBy(dx: p.x - g.startMouse.x, dy: p.y - g.startMouse.y)
                c.isCustomSize = true
                c.floatGeom = f
                updateDragTile(at: p)
                c.frame = f
                c.ignoreMovesUntil = CACurrentMediaTime() + 0.3   // not in mango: the app's report of this move
                system.setFrame(c, f, size: false)
                updateBorders(animating: [c.id: f])
            case .resize:
                if c.isFloating || c.scratchpadShown {
                    c.isCustomSize = true
                    if lastApplyDragTime == 0 || time &- lastApplyDragTime >= dragRefreshIntervalMs(c.mon) {
                        pointerResizeFloatingWindow(g, p)
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

    func pointerResizeFloatingWindow(_ g: Grab, _ p: CGPoint) {
        let c = g.client
        let dx = p.x - g.startMouse.x, dy = p.y - g.startMouse.y
        let s = g.startFrame, least = 1 + 2 * borderWidth(c, on: c.mon ?? selectedMonitor)
        let w = max(least, g.right ? s.width + dx : s.width - dx)
        let h = max(least, g.bottom ? s.height + dy : s.height - dy)
        let f = CGRect(x: g.right ? s.minX : s.maxX - w, y: g.bottom ? s.minY : s.maxY - h, width: w, height: h)
        c.frame = f
        c.floatGeom = f
        c.ignoreMovesUntil = CACurrentMediaTime() + 0.3   // not in mango: the app's report of this move
        system.setFrame(c, f, size: true)
        updateBorders(animating: [c.id: f])
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
