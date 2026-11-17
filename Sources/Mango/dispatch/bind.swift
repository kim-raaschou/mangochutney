import Foundation
import CoreGraphics

/* The generic argument carried by a binding action. */
package struct Arg {
    var i: Int32 = 0
    var i2: Int32 = 0
    var f: Float = 0
    var f2: Float = 0
    var v: String?
    var v2: String?
    var v3: String?
    var ui: UInt32 = 0
    var ui2: UInt32 = 0
    var tc: Client?

    // not in mango: C's designated initializer, `(Arg){.ui = …, .tc = …}`
    package init(i: Int32 = 0, i2: Int32 = 0, f: Float = 0, f2: Float = 0, v: String? = nil, v2: String? = nil,
                 v3: String? = nil, ui: UInt32 = 0, ui2: UInt32 = 0, tc: Client? = nil) {
        self.i = i; self.i2 = i2; self.f = f; self.f2 = f2; self.v = v; self.v2 = v2; self.v3 = v3
        self.ui = ui; self.ui2 = ui2; self.tc = tc
    }
}

let PREV: Int32 = 0, NEXT: Int32 = 1
let MON_PREV: Int32 = -1, MON_NEXT: Int32 = -2
let FORCE: Int32 = 0, UNFORCE: Int32 = 1
let OVERCIRCLE_PREV = PREV, OVERCIRCLE_NEXT = NEXT, OVERCIRCLE_CURRENT_PREV: Int32 = 2, OVERCIRCLE_CURRENT_NEXT: Int32 = 3

// not in mango: FuncType, a dispatcher as a method of the server
package typealias FuncType = @MainActor (MangoServer) -> (Arg) -> Int32

package extension MangoServer {
    func bindToView(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }
        var target = arg.ui

        if config.viewCurrentToBack && selectedMonitor.pertag.curtag != 0
            && (target & TAGMASK) == selectedMonitor.tagset[selectedMonitor.seltags] {
            if selectedMonitor.pertag.prevtag != 0 {
                target = 1 << (selectedMonitor.pertag.prevtag - 1)
            } else {
                // prevtag==0: previous view was the special workspace,
                // decide by the other tagset
                target = (selectedMonitor.tagset[selectedMonitor.seltags ^ 1] & TAG0_MASK) != 0 ? TAG0_MASK : 0
            }
        }

        if !config.viewCurrentToBack && (target & TAGMASK) == selectedMonitor.tagset[selectedMonitor.seltags] {
            return 0
        }

        if Int32(bitPattern: target) == Int32.min && selectedMonitor.pertag.curtag == 0 {
            if config.viewCurrentToBack && selectedMonitor.pertag.prevtag != 0 {
                target = 1 << (selectedMonitor.pertag.prevtag - 1)
            } else {
                target = 0
            }
        }

        // TAG0_MASK is INT_MIN too; handle it before the all-tags branch
        if target == TAG0_MASK {
            clientSwitchView(Arg(i: arg.i, ui: target), true)
            return 0
        }

        if target == 0 || Int32(bitPattern: target) == Int32.min {
            clientSwitchView(Arg(i: arg.i, ui: ~0 & TAGMASK), false)
        } else {
            clientSwitchView(Arg(i: arg.i, ui: target), true)
        }
        return 0
    }

    func changeVt(_ arg: Arg) -> Int32 {
        // not in mango: macOS has no virtual terminals (MangoCompat)
        return 1
    }

    func createVirtualOutput(_ arg: Arg) -> Int32 {
        // not in mango: virtual outputs are a wlroots backend's (MangoCompat)
        return 0
    }

    func destroyAllVirtualOutput(_ arg: Arg) -> Int32 {
        // not in mango: virtual outputs are a wlroots backend's (MangoCompat)
        return 0
    }

    func resetGaps(_ arg: Arg) -> Int32 {
        if selectedMonitor != nil && isSpecialActive(selectedMonitor) {
            setgaps(Int32(config.specialGappoh), Int32(config.specialGappov),
                    Int32(config.specialGappih), Int32(config.specialGappiv))
        } else {
            setgaps(Int32(config.gappoh), Int32(config.gappov), Int32(config.gappih), Int32(config.gappiv))
        }
        return 0
    }

    func exchangeClient(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }
        guard let c = arg.tc ?? focused, !c.isfloating else { return 0 }

        if (c.isfullscreen || c.ismaximizescreen) && !(c.mon.map { isScrollerLayout($0) } ?? false) { return 0 }

        var tc = directionSelect(arg)
        tc = getFocusedStackClient(tc, arg.tc)

        guard let tc else { return 0 }

        clientExchange(c, tc)
        return 0
    }

    func moveClient(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        guard let c = arg.tc ?? focused, let cm = c.mon, !c.isfloating else { return 0 }

        if (c.isfullscreen || c.ismaximizescreen) && !isScrollerLayout(cm) { return 0 }

        let tc = directionSelect(arg)

        if let tc {
            if tc.mon !== c.mon {
                clientMoveToMonitor(c, tc, arg.i)
            } else if let tm = tc.mon, tm.pertag.ltidxs[getMonCurtag(tm)] == .dwindle {
                dwindleMoveNextTo(c, tc, Float(config.dwindleSplitRatio), arg.i)
            } else if let t2 = getFocusedStackClient(tc, c) {
                clientExchange(c, t2)
            }
        } else if let m = monitorFromDirection(arg.i) {
            clientJumpToMonitor(c, m, arg.i)
        }

        if config.warpcursor { pointerWarpToClient(c) }
        return 0
    }

    func exchangeStackClient(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        guard let c = arg.tc ?? focused, !c.isfloating, !c.isfullscreen, !c.ismaximizescreen else { return 0 }
        let tc: Client?
        if arg.i == NEXT {
            tc = getNextStackClient(c, reverse: false)
        } else {
            tc = getNextStackClient(c, reverse: true)
        }
        if let tc { clientExchange(c, tc) }
        return 0
    }

    func focusDirection(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        let sel = focused
        // not in mango: not in the overview, whose cards are no monocle (a mango bug, docs/afvigelser.md §6)
        if isMonocleLayout(selectedMonitor), !selectedMonitor.isoverview, let sel, !sel.isfloating,
           arg.i == LEFT || arg.i == RIGHT {
            var a = arg
            a.i = arg.i == LEFT ? PREV : NEXT
            return focusStack(a)
        }

        var c = directionSelect(arg)

        if let sc = c, sc.mon !== selectedMonitor && !config.focusCrossMonitor { return 0 }

        if let sc = c, !selectedMonitor.isoverview {
            if sc.mon !== selectedMonitor {
                guard let m = sc.mon else { return 0 }
                c = clientFocusTop(m)
                if c == nil { return 0 }
                setSelectedMonitor(m)
            } else {
                c = getFocusedStackClient(sc, arg.tc)
            }
        }
        if let c {
            clientFocus(c, true)
            if config.warpcursor { pointerWarpToClient(c) }
        } else {
            // no cross-tag/monitor jumps inside the special workspace
            if !isSpecialActive(selectedMonitor) {
                if config.focusCrossTag {
                    if arg.i == LEFT || arg.i == UP { viewShiftTagHaveClient(Arg(), -1) }
                    if arg.i == RIGHT || arg.i == DOWN { viewShiftTagHaveClient(Arg(), 1) }
                } else if config.focusCrossMonitor {
                    _ = focusMonitor(arg)
                }
            }
        }
        return 0
    }

    func focusWindowOrWorkspace(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        if selectedMonitor.isoverview { return 0 }

        var c = directionSelect(arg)
        if !selectedMonitor.isoverview {
            c = getFocusedStackClient(c, arg.tc)
        }
        if let c, c.mon === selectedMonitor {
            clientFocus(c, true)
            if config.warpcursor { pointerWarpToClient(c) }
            return 0
        }

        if !isSpecialActive(selectedMonitor) {
            let dir = arg.i

            if dir == LEFT || dir == UP {
                if !viewShiftTagHaveClient(Arg(), -1) { viewShiftTag(Arg(), -1) }
            } else if dir == RIGHT || dir == DOWN {
                if !viewShiftTagHaveClient(Arg(), 1) { viewShiftTag(Arg(), 1) }
            }
        }

        return 0
    }

    func clientGroupJoin(_ needJoinClient: Client?, _ needReplaceClient: Client?) {
        var oldmon: Monitor?

        guard let needJoinClient, let joinMon = needJoinClient.mon else { return }

        guard let needReplaceClient, needReplaceClient.mon != nil else { return }

        if needJoinClient === needReplaceClient { return }

        if joinMon.isoverview { return }

        if needJoinClient.isGroupMember {
            _ = groupLeave(Arg(tc: needJoinClient))
        }

        if needJoinClient.mon !== needReplaceClient.mon {
            oldmon = needJoinClient.mon
            needJoinClient.mon = needReplaceClient.mon
        }

        if !needReplaceClient.isGroupMember {
            needReplaceClient.isGroupFocus = true
        }

        needJoinClient.groupNext = needReplaceClient

        if let p = needReplaceClient.groupPrev {
            p.groupNext = needJoinClient
        }

        needJoinClient.groupPrev = needReplaceClient.groupPrev

        needReplaceClient.groupPrev = needJoinClient

        clientFocusGroupMember(needJoinClient)
        // not in mango: client_sync_tiled_hint (no macOS part)
        if let m = needJoinClient.mon { arrange(m, false, false) }

        // oldmon may already be destroyed.
        if let oldmon {
            arrange(oldmon, false, false)
        }
    }

    func groupJoin(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        guard let needJoinClient = arg.tc ?? focused, let m = needJoinClient.mon else { return 0 }

        if m.isoverview { return 0 }

        clientGroupJoin(needJoinClient, directionSelect(arg))

        return 0
    }

    @discardableResult
    func clientGroupLeave(_ tc: Client?) -> Bool {
        guard let tc, let tm = tc.mon, tc.isGroupFocus else { return false }
        if !tc.isGroupMember { return false }

        if tm.isoverview { return false }

        let wasVisible = tc.tagVisible
        guard let rc = tc.groupNext ?? tc.groupPrev else { return false }

        clientFocusGroupMember(rc)
        clientGroupDetach(tc)

        tc.isGroupFocus = false
        tc.mon = rc.mon
        clientUnpark(tc, rc)
        /* rc stays focused: put tc right behind it in the focus stack. */
        focusStack.removeAll { $0 == tc.id }
        focusStack.insert(tc.id, at: (focusStack.firstIndex(of: rc.id) ?? -1) + 1)

        tc.tagVisible = wasVisible
        clientUpdateVisibility(tc)

        if !rc.isGroupMember {
            rc.isGroupFocus = false
        }

        return true
    }

    func groupLeave(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }
        let tc = arg.tc ?? focused
        if clientGroupLeave(tc), let m = tc?.mon {
            arrange(m, false, false)
        }

        return 0
    }

    func focusLast(_ arg: Arg) -> Int32 {
        var tc: Client?
        var begin = false
        var target: UInt32 = 0

        for id in focusStack {
            guard let c = clientByIdAll(id) else { continue }
            // not in mango: every Client is a mapped, managed window
            if c.iskilling || c.isminimized || c.isunglobal { continue }

            if selectedMonitor != nil && selectedMonitor.sel == nil {
                tc = c
                break
            }

            if selectedMonitor != nil && c.id == selectedMonitor.sel && !begin {
                begin = true
                continue
            }

            if begin {
                tc = c
                break
            }
        }

        guard let tc else { return 0 }

        if Int32(bitPattern: tc.tags) > 0 {
            clientFocus(tc, true)
            target = getTagsFirstTag(tc.tags)
            clientSwitchView(Arg(ui: target), true)
        }
        return 0
    }

    func toggleTrackpadEnable(_ arg: Arg) -> Int32 {
        // not in mango: disable_trackpad; macOS has no API to switch the trackpad off (MangoCompat)
        return 0
    }

    func focusMonitor(_ arg: Arg) -> Int32 {
        var tm: Monitor?

        if arg.i == MON_NEXT || arg.i == MON_PREV {
            tm = monitorFromCycle(arg.i)
        } else if arg.i != UNDIR {
            tm = monitorFromDirection(arg.i)
        } else if let v = arg.v {
            // not in mango: no disabled outputs
            for m in monitors where MonitorSpec(mango: v).matchMonitorSpec(name: m.screen.name) {
                tm = m
                break
            }
        } else {
            return 0
        }

        guard let tm, tm !== selectedMonitor else { return 0 }

        setSelectedMonitor(tm)
        if config.warpcursor {
            pointerWarpToMonitor(selectedMonitor)
        }
        let c = arg.tc ?? clientFocusTop(selectedMonitor)
        if c == nil {
            selectedMonitor.sel = nil
            system.keyboardNotifyClearFocus()   // not in mango: the port's wlr_seat_*_notify_clear_focus
            clientFocus(nil, false)
        } else {
            clientFocus(c, true)
        }

        return 0
    }

    func focusStack(_ arg: Arg) -> Int32 {
        guard let sel = arg.tc ?? clientFocusTop(selectedMonitor) else { return 0 }
        let tc: Client?

        if arg.i == NEXT {
            tc = getNextStackClient(sel, reverse: false)
        } else {
            tc = getNextStackClient(sel, reverse: true)
        }

        guard let tc else { return 0 }

        clientFocus(tc, true)
        if config.warpcursor { pointerWarpToClient(tc) }
        return 0
    }

    /*
     * overcircle: opens/cycles overview (centered tab layout)
     * - not in overview: enters overview
     * - already in overview: cycles windows of the current monitor in insertion
     * order and rearranges.
     */
    func overCircle(_ arg: Arg) -> Int32 {
        guard let m = selectedMonitor, grabClient == nil else { return 0 }

        let sel = arg.tc ?? focused

        let next = arg.i == OVERCIRCLE_NEXT || arg.i == OVERCIRCLE_CURRENT_NEXT
        let current = arg.i == OVERCIRCLE_CURRENT_NEXT || arg.i == OVERCIRCLE_CURRENT_PREV

        if m.isoverview && !m.isJumpMode && !m.ovNormalMode, let sel {
            m.ovTabLayout = true
            publishInputState()   // not in mango: the event tap's snapshot
            guard let tc = next ? getNextStackClient(sel, reverse: false) : getNextStackClient(sel, reverse: true) else {
                return 0
            }

            clientFocus(tc, true)

            arrange(m, true, false)
            return 0
        }

        m.ovTabLayout = true
        _ = toggleOverview(Arg(i: current ? 1 : 0, tc: arg.tc))
        if !m.isoverview {
            m.ovTabLayout = false
            publishInputState()   // not in mango: the event tap's snapshot
        }
        return 0
    }

    func groupFocus(_ arg: Arg) -> Int32 {
        guard let c = arg.tc ?? focused, c.mon != nil else { return 0 }

        if !c.isGroupMember {
            return 0
        }

        if c.mon?.isoverview == true { return 0 }

        let tc: Client?

        if arg.i == NEXT {
            tc = c.groupNext
        } else {
            tc = c.groupPrev
        }

        guard let tc else { return 0 }

        clientFocusGroupMember(tc)
        if let m = tc.mon { arrange(m, false, false) }
        return 0
    }

    func incNmaster(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }
        let tag = getMonCurtag(selectedMonitor)
        selectedMonitor.pertag.nmasters[tag] = max(selectedMonitor.pertag.nmasters[tag] + arg.i, 0)
        arrange(selectedMonitor, false, false)
        return 0
    }

    func increaseGaps(_ arg: Arg) -> Int32 {
        guard let sm = selectedMonitor else { return 0 }
        if isSpecialActive(sm) {
            // not in mango: increase_gaps adds to the normal gaps on the special tag too (a mango bug, docs/afvigelser.md §6)
            setgaps(sm.specialGappoh + arg.i, sm.specialGappov + arg.i, sm.specialGappih + arg.i, sm.specialGappiv + arg.i)
        } else {
            setgaps(sm.gappoh + arg.i, sm.gappov + arg.i, sm.gappih + arg.i, sm.gappiv + arg.i)
        }
        return 0
    }

    func increaseInnerGap(_ arg: Arg) -> Int32 {
        guard let sm = selectedMonitor else { return 0 }
        setgaps(sm.gappoh, sm.gappov, sm.gappih + arg.i, sm.gappiv + arg.i)
        return 0
    }

    func increaseOuterGap(_ arg: Arg) -> Int32 {
        guard let sm = selectedMonitor else { return 0 }
        setgaps(sm.gappoh + arg.i, sm.gappov + arg.i, sm.gappih, sm.gappiv)
        return 0
    }

    func increaseInnerHorizontalGap(_ arg: Arg) -> Int32 {
        guard let sm = selectedMonitor else { return 0 }
        setgaps(sm.gappoh, sm.gappov, sm.gappih + arg.i, sm.gappiv)
        return 0
    }

    func increaseInnerVerticalGap(_ arg: Arg) -> Int32 {
        guard let sm = selectedMonitor else { return 0 }
        setgaps(sm.gappoh, sm.gappov, sm.gappih, sm.gappiv + arg.i)
        return 0
    }

    func increaseOuterHorizontalGap(_ arg: Arg) -> Int32 {
        guard let sm = selectedMonitor else { return 0 }
        setgaps(sm.gappoh + arg.i, sm.gappov, sm.gappih, sm.gappiv)
        return 0
    }

    func increaseOuterVerticalGap(_ arg: Arg) -> Int32 {
        guard let sm = selectedMonitor else { return 0 }
        setgaps(sm.gappoh, sm.gappov + arg.i, sm.gappih, sm.gappiv)
        return 0
    }

    func setMasterFactor(_ arg: Arg) -> Int32 {
        guard let sm = selectedMonitor else { return 0 }
        let f: Float = arg.f < 1.0 ? arg.f + sm.pertag.mfacts[getMonCurtag(sm)] : arg.f - 1.0
        if f < 0.1 || f > 0.9 { return 0 }

        sm.pertag.mfacts[getMonCurtag(sm)] = f
        for c in clients where VISIBLEON(c, sm) && ISTILED(c) {
            c.masterMfactPer = CGFloat(f)
        }
        arrange(sm, false, false)
        return 0
    }

    func killClient(_ arg: Arg) -> Int32 {
        let c = arg.tc ?? (selectedMonitor != nil ? focused : nil)
        if let c {
            if arg.i == FORCE {
                clientPendingForceKill(c)
            } else {
                pendingKillClient(c)
            }
        }
        return 0
    }

    func smartKillClient(_ arg: Arg) -> Int32 {
        guard let c = arg.tc ?? (selectedMonitor != nil ? focused : nil), let cm = c.mon else { return 0 }

        if clientOnlyInOneTag(c) {
            pendingKillClient(c)
            return 0
        }

        let viewTags = cm.tagset[cm.seltags] & TAGMASK
        let remainingTags = c.tags & ~viewTags
        if remainingTags == 0 {
            pendingKillClient(c)
            return 0
        }

        c.tags = remainingTags
        // not in mango: client_reparent_group (no macOS part)
        clientFocus(clientFocusTop(selectedMonitor), true)
        arrange(cm, false, false)
        return 0
    }

    func moveResize(_ arg: Arg) -> Int32 {
        if cursorMode != CurNormal && cursorMode != CurPressed {
            return 0
        }

        let p = system.pointer
        let c = nodeAtPoint(p)   // not in mango: no group bar under the cursor (the port's bars take their own clicks)
        pointerBeginMoveResize(c, arg.ui, p.x, p.y, [])
        return 0
    }

    func moveWindow(_ arg: Arg) -> Int32 {
        guard let c = arg.tc ?? (selectedMonitor != nil ? focused : nil), !c.isfullscreen else { return 0 }
        if !c.isfloating {
            clientSetFloating(c, true, false)
        }

        switch arg.ui {
        case NUM_TYPE_MINUS:
            c.geom.origin.x -= CGFloat(arg.i)
        case NUM_TYPE_PLUS:
            c.geom.origin.x += CGFloat(arg.i)
        default:
            c.geom.origin.x = CGFloat(arg.i)
        }

        switch arg.ui2 {
        case NUM_TYPE_MINUS:
            c.geom.origin.y -= CGFloat(arg.i2)
        case NUM_TYPE_PLUS:
            c.geom.origin.y += CGFloat(arg.i2)
        default:
            c.geom.origin.y = CGFloat(arg.i2)
        }

        c.iscustomsize = true
        c.floatGeom = c.geom
        resize(c, c.geom, ResizeOpts(interact: false))
        return 0
    }

    func quit(_ arg: Arg) -> Int32 {
        system.quit()   // not in mango: wl_display_terminate; the port ends the app
        return 0
    }

    func resizeWindow(_ arg: Arg) -> Int32 {
        guard let c = arg.tc ?? (selectedMonitor != nil ? focused : nil) else { return 0 }
        var offsetx: Int32 = 0, offsety: Int32 = 0

        if c.isfullscreen || c.ismaximizescreen { return 0 }

        let animationsStateBackup = config.animations
        if !c.isfloating {
            config.animations = false
        }

        if ISTILED(c) {
            switch arg.ui {
            case NUM_TYPE_MINUS:
                offsetx = -arg.i
            case NUM_TYPE_PLUS:
                offsetx = arg.i
            default:
                offsetx = arg.i
            }

            switch arg.ui2 {
            case NUM_TYPE_MINUS:
                offsety = -arg.i2
            case NUM_TYPE_PLUS:
                offsety = arg.i2
            default:
                offsety = arg.i2
            }
            resizeTileClient(c, isdrag: false, offsetX: CGFloat(offsetx), offsetY: CGFloat(offsety))
            config.animations = animationsStateBackup
            return 0
        }

        switch arg.ui {
        case NUM_TYPE_MINUS:
            c.geom.size.width -= CGFloat(arg.i)
        case NUM_TYPE_PLUS:
            c.geom.size.width += CGFloat(arg.i)
        default:
            c.geom.size.width = CGFloat(arg.i)
        }

        switch arg.ui2 {
        case NUM_TYPE_MINUS:
            c.geom.size.height -= CGFloat(arg.i2)
        case NUM_TYPE_PLUS:
            c.geom.size.height += CGFloat(arg.i2)
        default:
            c.geom.size.height = CGFloat(arg.i2)
        }

        c.iscustomsize = true
        c.floatGeom = c.geom
        resize(c, c.geom, ResizeOpts(interact: false))
        config.animations = animationsStateBackup
        return 0
    }

    func restoreMinimized(_ arg: Arg) -> Int32 {
        if selectedMonitor != nil && selectedMonitor.isoverview { return 0 }

        var c: Client?
        var focused = selectedMonitor != nil ? self.focused : nil
        if focused == nil && selectedMonitor != nil {
            focused = clientFocusTop(selectedMonitor)
        }

        /* 1. If focused window or any shown scratchpad exists, evict it */
        if let focused, SCRATCHPAD_SHOWN(focused) {
            c = focused
        } else {
            for tc in clients where (tc.mon === selectedMonitor || config.scratchpadCrossMonitor) && SCRATCHPAD_SHOWN(tc) {
                c = tc
                break
            }
        }

        /* 2. Otherwise, find a minimized window to restore */
        if c == nil {
            c = clients.first { $0.isminimized && !$0.isnamedscratchpad }
        }

        guard let c else { return 0 }

        if !c.ignoreMinimize { system.clientSetMinimized(c, false) }   // not in mango: macOS's own minimize undone

        let isfloatingBeforeScratchpad = c.isfloatingBeforeScratchpad

        /* Clear scratchpad & minimized state */
        c.isInScratchpad = false
        c.isfloatingBeforeScratchpad = false
        c.isnamedscratchpad = false
        clientPendingMinimizedState(c, false)
        c.iscustomsize = false

        /* Restore to the tag where a window currently is focused */
        if let focused, focused !== c, focused.tags != 0 {
            c.tags = focused.tags
        } else {
            c.tags = selectedMonitor.tagset[selectedMonitor.seltags]
        }
        c.oldtags = c.tags
        c.mon = selectedMonitor

        c.isPendingOpenAnimation = true
        clientSetFloating(c, isfloatingBeforeScratchpad, true)
        bordersDirty = true   // not in mango: client_update_border_color; the port draws the borders at once
        clientFocus(c, true)
        pointerWarpToClient(c)
        return 0
    }

    func setLayout(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        for jk in layouts.indices {
            if layouts[jk].name == arg.v {
                selectedMonitor.pertag.ltidxs[getMonCurtag(selectedMonitor)] = layouts[jk].id   // not in mango: ltidxs holds the id
                clearFullscreenAndMaximizedState(selectedMonitor)
                arrange(selectedMonitor, false, false)
                printstatus(.arrangge)
                return 0
            }
        }
        return 0
    }

    func setKeyMode(_ arg: Arg) -> Int32 {
        keyMode = String(decoding: (arg.v ?? "").utf8.prefix(27), as: UTF8.self)
        // not in mango: key_mode.isdefault is keyMode == "default", read where it is used
        printstatus(.keymode)
        return 1
    }

    func setProportion(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        if selectedMonitor.isoverview || !isScrollerLayout(selectedMonitor) { return 0 }

        if selectedMonitor.visibleTilingClients == 1 && !config.scrollerIgnoreProportionSingle { return 0 }

        guard var tc = arg.tc ?? focused else { return 0 }

        tc = scrollGetStackHeadClient(tc)

        guard let m = tc.mon else { return 0 }   // not in mango: tc->mon is always set here
        let tag = getMonCurtag(m)
        let st = m.pertag.scrollerState[tag]
        var node: ScrollerStackNode?

        if let st { node = findScrollerNode(st, tc) }

        if let node { node.scrollerProportion = arg.f }
        tc.scrollerProportion = arg.f

        let maxClientWidth = UInt32(truncatingIfNeeded: WBox(m.w).width - 2 * Int32(config.scrollerStructs) - Int32(config.gappih))
        tc.geom.size.width = CGFloat(i32(Float(maxClientWidth) * arg.f))

        arrange(m, false, false)
        return 0
    }

    func switchProportionPreset(_ arg: Arg) -> Int32 {
        var targetProportion: Float = 0
        if selectedMonitor == nil { return 0 }

        if config.scrollerProportionPreset.isEmpty { return 0 }

        if selectedMonitor.isoverview || !isScrollerLayout(selectedMonitor) { return 0 }

        if selectedMonitor.visibleTilingClients == 1 && !config.scrollerIgnoreProportionSingle { return 0 }

        guard var tc = arg.tc ?? focused else { return 0 }

        if tc.isfloating { return 0 } // Do not switch scroller proportions for floating windows

        tc = scrollGetStackHeadClient(tc)

        guard let m = tc.mon else { return 0 }   // not in mango: tc->mon is always set here
        let tag = getMonCurtag(m)
        let st = m.pertag.scrollerState[tag]
        var node: ScrollerStackNode?

        if let st { node = findScrollerNode(st, tc) }

        let currentProportion = node?.scrollerProportion ?? tc.scrollerProportion

        let preset = config.scrollerProportionPreset.map { Float($0) }
        for i in preset.indices where preset[i] == currentProportion {
            if i == preset.count - 1 {
                targetProportion = preset[0]
            } else {
                targetProportion = preset[i + 1]
            }
            break
        }

        if targetProportion == 0.0 {
            targetProportion = preset[0]
        }

        if let node { node.scrollerProportion = targetProportion }
        tc.scrollerProportion = targetProportion

        let maxClientWidth = UInt32(truncatingIfNeeded: WBox(m.w).width - 2 * Int32(config.scrollerStructs) - Int32(config.gappih))
        tc.geom.size.width = CGFloat(i32(Float(maxClientWidth) * targetProportion))

        arrange(m, false, false)
        return 0
    }

    func smartMoveWindow(_ arg: Arg) -> Int32 {
        var nx: Int32, ny: Int32
        var buttom: Int32, top: Int32, left: Int32, right: Int32, tar: Int32
        if selectedMonitor == nil { return 0 }
        guard let c = arg.tc ?? focused, !c.isfullscreen, c.mon != nil else { return 0 }
        if !c.isfloating {
            clientSetFloating(c, true, false)
        }
        guard let cm = c.mon else { return 0 }   // not in mango: c->mon is always set here
        let g = WBox(c.geom), w = WBox(cm.w)
        nx = g.x
        ny = g.y

        switch arg.i {
        case UP:
            tar = -99999
            top = g.y
            ny -= w.height / 4

            for tc in clients {
                if !VISIBLEON(tc, selectedMonitor) || !tc.isfloating || tc === c { continue }
                let t = WBox(tc.geom)
                if g.x + g.width < t.x || g.x > t.x + t.width { continue }
                buttom = t.y + t.height + Int32(config.gappiv)
                if top > buttom && ny < buttom {
                    tar = max(tar, buttom)
                }
            }

            ny = tar == -99999 ? ny : tar
            ny = max(ny, w.y + cm.gappov)
        case DOWN:
            tar = 99999
            buttom = g.y + g.height
            ny += w.height / 4

            for tc in clients {
                if !VISIBLEON(tc, selectedMonitor) || !tc.isfloating || tc === c { continue }
                let t = WBox(tc.geom)
                if g.x + g.width < t.x || g.x > t.x + t.width { continue }
                top = t.y - Int32(config.gappiv)
                if buttom < top && (ny + g.height) > top {
                    tar = min(tar, top - g.height)
                }
            }
            ny = tar == 99999 ? ny : tar
            ny = min(ny, w.y + w.height - g.height - cm.gappov)
        case LEFT:
            tar = -99999
            left = g.x
            nx -= w.width / 6

            for tc in clients {
                if !VISIBLEON(tc, selectedMonitor) || !tc.isfloating || tc === c { continue }
                let t = WBox(tc.geom)
                if g.y + g.height < t.y || g.y > t.y + t.height { continue }
                right = t.x + t.width + Int32(config.gappih)
                if left > right && nx < right {
                    tar = max(tar, right)
                }
            }

            nx = tar == -99999 ? nx : tar
            nx = max(nx, w.x + cm.gappoh)
        case RIGHT:
            tar = 99999
            right = g.x + g.width
            nx += w.width / 6
            for tc in clients {
                if !VISIBLEON(tc, selectedMonitor) || !tc.isfloating || tc === c { continue }
                let t = WBox(tc.geom)
                if g.y + g.height < t.y || g.y > t.y + t.height { continue }
                left = t.x - Int32(config.gappih)
                if right < left && (nx + g.width) > left {
                    tar = min(tar, left - g.width)
                }
            }
            nx = tar == 99999 ? nx : tar
            nx = min(nx, w.x + w.width - g.width - cm.gappoh)
        default:
            break
        }

        c.floatGeom = wlrBox(nx, ny, g.width, g.height)
        c.iscustomsize = true
        resize(c, c.floatGeom, ResizeOpts(interact: true))
        return 0
    }

    func smartResizeWindow(_ arg: Arg) -> Int32 {
        var nw: Int32, nh: Int32
        var buttom: Int32, top: Int32, left: Int32, right: Int32, tar: Int32
        if selectedMonitor == nil { return 0 }
        guard let c = arg.tc ?? focused, !c.isfullscreen else { return 0 }
        if !c.isfloating {
            clientSetFloating(c, true, false)
        }
        let g = WBox(c.geom), w = WBox(selectedMonitor.w)
        nw = g.width
        nh = g.height

        switch arg.i {
        case UP:
            nh -= w.height / 8
            nh = max(nh, w.height / 10)
        case DOWN:
            tar = -99999
            buttom = g.y + g.height
            nh += w.height / 8

            for tc in clients {
                if !VISIBLEON(tc, selectedMonitor) || !tc.isfloating || tc === c { continue }
                let t = WBox(tc.geom)
                if g.x + g.width < t.x || g.x > t.x + t.width { continue }
                top = t.y - Int32(config.gappiv)
                if buttom < top && (nh + g.y) > top {
                    tar = max(tar, top - g.y)
                }
            }
            nh = tar == -99999 ? nh : tar
            if g.y + nh + Int32(config.gappov) > w.y + w.height {
                nh = w.y + w.height - g.y - Int32(config.gappov)
            }
        case LEFT:
            nw -= w.width / 16
            nw = max(nw, w.width / 10)
        case RIGHT:
            tar = 99999
            right = g.x + g.width
            nw += w.width / 16
            for tc in clients {
                if !VISIBLEON(tc, selectedMonitor) || !tc.isfloating || tc === c { continue }
                let t = WBox(tc.geom)
                if g.y + g.height < t.y || g.y > t.y + t.height { continue }
                left = t.x - Int32(config.gappih)
                if right < left && (nw + g.x) > left {
                    tar = min(tar, left - g.x)
                }
            }

            nw = tar == 99999 ? nw : tar
            if g.x + nw + Int32(config.gappoh) > w.x + w.width {
                nw = w.x + w.width - g.x - Int32(config.gappoh)
            }
        default:
            break
        }

        c.floatGeom = wlrBox(g.x, g.y, nw, nh)
        c.iscustomsize = true
        resize(c, c.floatGeom, ResizeOpts(interact: true))
        return 0
    }

    func centerWindow(_ arg: Arg) -> Int32 {
        guard let c = arg.tc ?? (selectedMonitor != nil ? focused : nil) else { return 0 }

        if c.isfullscreen || c.ismaximizescreen { return 0 }

        if c.isfloating {
            c.floatGeom = clientCenterGeometry(c, c.mon, c.geom, 0, 0)
            c.iscustomsize = true
            resize(c, c.floatGeom, ResizeOpts(interact: true))
            return 0
        }

        if !isScrollerLayout(selectedMonitor) { return 0 }

        let stackHead = scrollGetStackHeadClient(c)
        let w = WBox(selectedMonitor.w)
        if selectedMonitor.pertag.ltidxs[getMonCurtag(selectedMonitor)] == .scroller {
            stackHead.geom.origin.x = CGFloat(w.x + (w.width - Int32(stackHead.geom.width)) / 2)
        } else {
            stackHead.geom.origin.y = CGFloat(w.y + (w.height - Int32(stackHead.geom.height)) / 2)
        }

        arrange(selectedMonitor, false, false)
        return 0
    }

    func spawnShell(_ arg: Arg) -> Int32 {
        guard let v = arg.v else { return 0 }

        system.spawnShell(v)   // not in mango: fork and execlp, the port's
        return 0
    }

    func spawn(_ arg: Arg) -> Int32 {
        guard let v = arg.v else { return 0 }

        system.spawn(v)   // not in mango: fork, wordexp and execvp, the port's
        return 0
    }

    func spawnOnEmpty(_ arg: Arg) -> Int32 {
        var isEmpty = true

        for c in clients where arg.ui & c.tags != 0 && c.mon === selectedMonitor {
            isEmpty = false
            break
        }
        if !isEmpty {
            clientSwitchView(arg, true)
            return 0
        } else {
            clientSwitchView(arg, true)
            _ = spawnShell(arg)
        }
        return 0
    }

    func switchKeyboardLayout(_ arg: Arg) -> Int32 {
        // not in mango: keyboard layouts are switched by macOS (MangoCompat)
        return 0
    }

    func switchLayout(_ arg: Arg) -> Int32 {
        var targetLayoutName: String?

        if selectedMonitor == nil { return 0 }

        let tag = getMonCurtag(selectedMonitor)
        let current = layouts.first { $0.id == selectedMonitor.pertag.ltidxs[tag] }!.name   // not in mango: ltidxs holds the id

        if !config.circleLayout.isEmpty {
            for jk in config.circleLayout.indices where config.circleLayout[jk] == current {
                targetLayoutName = jk == config.circleLayout.count - 1 ? config.circleLayout[0] : config.circleLayout[jk + 1]
                break
            }

            if targetLayoutName == nil {
                targetLayoutName = config.circleLayout[0]
            }

            for ji in layouts.indices where layouts[ji].name == targetLayoutName {
                selectedMonitor.pertag.ltidxs[tag] = layouts[ji].id

                break
            }
            clearFullscreenAndMaximizedState(selectedMonitor)
            arrange(selectedMonitor, false, false)
            printstatus(.arrangge)
            return 0
        }

        for jk in layouts.indices where layouts[jk].name == current {
            selectedMonitor.pertag.ltidxs[tag] = jk == layouts.count - 1 ? layouts[0].id : layouts[jk + 1].id
            clearFullscreenAndMaximizedState(selectedMonitor)
            arrange(selectedMonitor, false, false)
            printstatus(.arrangge)
            return 0
        }
        return 0
    }

    func tag(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }
        let targetClient = arg.tc ?? focused
        tagClient(arg, targetClient)
        return 0
    }

    func tagMonitor(_ arg: Arg) -> Int32 {
        var m: Monitor?
        if selectedMonitor == nil { return 0 }
        guard let c = arg.tc ?? clientFocusTop(selectedMonitor) else { return 0 }

        if arg.i == MON_NEXT || arg.i == MON_PREV {
            m = monitorFromCycle(arg.i)
        } else if arg.i != UNDIR {
            m = monitorFromDirection(arg.i)
        } else if let v = arg.v {
            // not in mango: no disabled outputs
            for cm in monitors where MonitorSpec(mango: v).matchMonitorSpec(name: cm.screen.name) {
                m = cm
                break
            }
        } else {
            return 0
        }

        guard let m else { return 0 }

        let newtags = arg.ui != 0 ? arg.ui : arg.i2 != 0 ? c.tags : 0
        let target: UInt32

        if c.mon === m {
            clientSwitchView(Arg(ui: newtags), true)
            return 0
        }

        if !clientSetMonitorAdapted(c, m, newtags, focus: true) { return 0 }

        setSelectedMonitor(c.mon)
        target = getTagsFirstTag(c.tags)

        clientSwitchView(Arg(ui: target), true)
        clientFocus(c, true)
        if c.isfloating {
            resize(c, c.geom, ResizeOpts(interact: true))
        } else {
            arrange(selectedMonitor, false, false)
        }
        if config.warpcursor, let cm = c.mon {
            pointerWarpToMonitor(cm)
        }
        return 0
    }

    func tagSilent(_ arg: Arg) -> Int32 {
        guard let targetClient = arg.tc ?? (selectedMonitor != nil ? focused : nil) else { return 0 }

        targetClient.tags = (arg.ui & TAG0_MASK) != 0 ? TAG0_MASK : (arg.ui & TAGMASK)
        // not in mango: client_reparent_group (no macOS part)
        for fc in clients where fc !== targetClient && targetClient.tags & fc.tags != 0
            && ISFULLSCREEN(fc) && !targetClient.isfloating {
            clearFullscreenFlag(fc)
        }
        clientFocus(clientFocusTop(selectedMonitor), true)
        if let m = targetClient.mon { arrange(m, false, false) }
        return 0
    }

    func tagToLeft(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        let sel = arg.tc ?? focused
        if sel != nil && (selectedMonitor.tagset[selectedMonitor.seltags] & TAGMASK).nonzeroBitCount == 1 {
            var target = selectedMonitor.tagset[selectedMonitor.seltags] >> 1

            if target == 0 {
                if !config.tagCarousel { return 0 }
                target = (1 << UInt32(config.tagNum - 1)) & TAGMASK
                selectedMonitor.carouselAnimDir = -1
            }

            let a = Arg(i: arg.i, ui: target & TAGMASK, tc: sel)
            _ = tag(a)
            selectedMonitor.carouselAnimDir = 0
        }
        return 0
    }

    func tagToRight(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        let sel = arg.tc ?? focused
        if sel != nil && (selectedMonitor.tagset[selectedMonitor.seltags] & TAGMASK).nonzeroBitCount == 1 {
            var target = selectedMonitor.tagset[selectedMonitor.seltags] << 1

            if target & TAGMASK == 0 {
                if !config.tagCarousel { return 0 }
                target = 1
                selectedMonitor.carouselAnimDir = 1
            }

            let a = Arg(i: arg.i, ui: target & TAGMASK, tc: sel)
            _ = tag(a)
            selectedMonitor.carouselAnimDir = 0
        }
        return 0
    }

    func toggleNamedScratchpad(_ arg: Arg) -> Int32 {
        let argId = arg.v
        let argTitle = arg.v2

        if selectedMonitor != nil && selectedMonitor.isoverview { return 0 }

        let targetClient = getClientByIdOrTitle(argId, argTitle)

        guard let targetClient else {
            if let v3 = arg.v3 {   // not in mango: Swift's optional; parse_func_name always sets v3
                let argSpawn = Arg(v: v3)
                _ = spawnShell(argSpawn)
            }
            return 0
        }

        targetClient.isnamedscratchpad = true
        applyNamedScratchpad(targetClient)
        return 0
    }

    func toggleRenderBorder(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }
        renderBorder.toggle()
        arrange(selectedMonitor, false, false)
        return 0
    }

    func toggleScratchpad(_ arg: Arg) -> Int32 {
        var shown: Client?
        var hidden: Client?

        if selectedMonitor != nil && selectedMonitor.isoverview { return 0 }

        for c in clients {
            if !config.scratchpadCrossMonitor && c.mon !== selectedMonitor {
                continue
            }

            if config.singleScratchpad && c.isnamedscratchpad && !c.isminimized {
                setMinimized(c)
                continue
            }

            if c.isnamedscratchpad { continue }

            if shown == nil && SCRATCHPAD_SHOWN(c) {
                shown = c
            } else if c.isInScratchpad {
                hidden = c // LIFO insertion puts the oldest scratchpad last.
            }
        }

        if let shown {
            _ = switchScratchpadClientState(shown)
        } else if let hidden {
            _ = switchScratchpadClientState(hidden)
        }
        return 0
    }

    private func specialTagMigrateClients(_ target: Monitor) {
        var layoutCopied = false

        for c in clients {
            guard let oldmon = c.mon, oldmon !== target, !c.iskilling, c.tags & TAG0_MASK != 0 else { continue }

            if !layoutCopied {
                monitorCopyTagLayout(target, oldmon, 0)
                layoutCopied = true
            }
            _ = clientSetMonitorAdapted(c, target, TAG0_MASK, focus: false)
        }
    }

    private func specialTagPreviousTagset(_ m: Monitor) -> UInt32 {
        let previous = m.tagset[m.seltags ^ 1] & TAGMASK
        return previous != 0 ? previous : (m.pertag.prevtag != 0 ? (1 << (m.pertag.prevtag - 1)) : 1)
    }

    private func specialTagPrepareTarget(_ target: Monitor?) {
        guard config.specialTagCrossMonitor, let target else { return }   // not in mango: no disabled outputs

        for m in monitors {
            if m === target || m.isoverview || !isSpecialActive(m) {   // not in mango: no disabled outputs
                continue
            }
            clientViewOnMonitor(Arg(ui: specialTagPreviousTagset(m)), true, m, false)
        }

        specialTagMigrateClients(target)
    }

    // toggle the special workspace view on a given monitor
    func toggleSpecialTagMon(_ m: Monitor?) {
        guard let m, !m.isoverview else { return }

        setSelectedMonitor(m)
        if isSpecialActive(m) {
            /* Toggle back to previous tagset (supports multi-tag views) */
            clientViewOnMonitor(Arg(ui: specialTagPreviousTagset(m)), true, m, true)
        } else {
            specialTagPrepareTarget(m)
            /* Switch to tag 0 */
            clientSwitchView(Arg(ui: TAG0_MASK), true)
        }
    }

    func toggleSpecialTag(_ arg: Arg) -> Int32 {
        let m = arg.tc?.mon ?? selectedMonitor
        toggleSpecialTagMon(m)
        return 0
    }

    private func tagSpecialTagInternal(_ arg: Arg, _ silent: Bool) {
        if selectedMonitor == nil { return }
        guard let c = arg.tc ?? focused else { return }

        let m: Monitor = c.mon ?? selectedMonitor
        if c.tags & TAG0_MASK != 0 {
            /* Return window from tag 0 to normal tag */
            let target: UInt32 = m.pertag.prevtag > 0
                ? (1 << (m.pertag.prevtag - 1))
                : (m.pertag.curtag > 0 ? (1 << (m.pertag.curtag - 1)) : 1)
            if silent {
                _ = tagSilent(Arg(ui: target, tc: c))
            } else {
                _ = tag(Arg(ui: target, tc: c))
            }

        } else {
            /* Send window to tag 0 */
            specialTagPrepareTarget(m)
            if silent {
                _ = tagSilent(Arg(ui: TAG0_MASK, tc: c))
            } else {
                _ = tag(Arg(ui: TAG0_MASK, tc: c))
                /* Switch to tag 0 so user sees the window */
                if !isSpecialActive(m) {
                    _ = toggleSpecialTag(Arg())
                }
            }
        }
    }

    func tagSpecialTag(_ arg: Arg) -> Int32 {
        tagSpecialTagInternal(arg, false)
        return 0
    }

    func tagSpecialSilent(_ arg: Arg) -> Int32 {
        tagSpecialTagInternal(arg, true)
        return 0
    }

    func toggleFakeFullscreen(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }
        if let sel = arg.tc ?? clientFocusTop(selectedMonitor) {
            clientSetFakeFullscreen(sel, !sel.isfakefullscreen)
        }
        return 0
    }

    func toggleFloating(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil || grabClient != nil { return 0 }

        let sel = arg.tc ?? clientFocusTop(selectedMonitor)

        if selectedMonitor != nil && selectedMonitor.isoverview { return 0 }

        guard let sel else { return 0 }

        var isfloating = sel.isfloating

        if sel.isfullscreen || sel.ismaximizescreen {
            isfloating = true
        } else {
            isfloating = !sel.isfloating
        }

        clientSetFloating(sel, isfloating, false)
        return 0
    }

    func toggleFullscreen(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        guard let sel = arg.tc ?? clientFocusTop(selectedMonitor) else { return 0 }

        sel.isInScratchpad = false
        sel.isnamedscratchpad = false

        if sel.isfullscreen {
            clientSetFullscreen(sel, false, rearrange: true)
        } else {
            clientSetFullscreen(sel, true, rearrange: true)
        }
        return 0
    }

    func toggleGlobal(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        guard let c = arg.tc ?? focused else { return 0 }

        if c.isInScratchpad {
            c.isInScratchpad = false
            c.isnamedscratchpad = false
        }
        c.isglobal.toggle()
        updateBorders()   // not in mango: client_update_border_color; the port draws the borders at once
        return 0
    }

    func toggleGaps(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        enableGaps.toggle()
        arrange(selectedMonitor, false, false)
        return 0
    }

    func toggleGroupBar(_ arg: Arg) -> Int32 {
        config.alwaysShowGroupBar.toggle()

        // not in mango: no disabled outputs
        for m in monitors {
            arrange(m, false, false)
        }
        return 0
    }

    func toggleMaximizeScreen(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        guard let sel = arg.tc ?? clientFocusTop(selectedMonitor) else { return 0 }

        sel.isInScratchpad = false
        sel.isnamedscratchpad = false

        if sel.ismaximizescreen {
            clientSetMaximizeScreen(sel, false, rearrange: true)
        } else {
            clientSetMaximizeScreen(sel, true, rearrange: true)
        }

        updateBorders()   // not in mango: client_update_border_color; the port draws the borders at once
        return 0
    }

    func toggleOverlay(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        guard let c = arg.tc ?? focused, let m = c.mon, !c.isfullscreen else { return 0 }

        c.isoverlay.toggle()

        clientRaiseLayers(m)   // not in mango: client_reparent_group; the port raises the layers
        updateBorders()   // not in mango: client_update_border_color; the port draws the borders at once
        return 0
    }

    func toggleTag(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        var newtags: UInt32
        guard let sel = arg.tc ?? clientFocusTop(selectedMonitor) else { return 0 }
        if let sm = sel.mon, sm.isoverview { return 0 }
        // special workspace windows only belong to tag0; use tag_special_tag to
        // move them back to a normal tag
        if sel.tags & TAG0_MASK != 0 { return 0 }

        if Int32(bitPattern: arg.ui) == Int32.min && sel.tags != (~0 & TAGMASK) {
            newtags = ~0 & TAGMASK
        } else if Int32(bitPattern: arg.ui) == Int32.min && sel.tags == (~0 & TAGMASK) {
            guard let sm = sel.mon else { return 0 }   // not in mango: sel->mon is always set here
            var tag = sm.pertag.curtag
            if tag == 0 {
                tag = getTagsFirstTagNum(sm.tagset[sm.seltags])
            }
            if tag == 0 {
                tag = 1
            }
            newtags = 1 << (tag - 1)
        } else {
            newtags = sel.tags ^ (arg.ui & TAGMASK)
        }

        if newtags != 0 {
            sel.tags = newtags
            // not in mango: client_reparent_group (no macOS part)
            clientFocus(clientFocusTop(selectedMonitor), true)
            arrange(selectedMonitor, false, false)
        }
        printstatus(.arrangge)
        return 0
    }

    func toggleView(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }
        if selectedMonitor.isoverview { return 0 }

        let newtagset: UInt32
        let target: UInt32

        target = arg.ui == 0 ? ~0 & TAGMASK : arg.ui

        newtagset = selectedMonitor.tagset[selectedMonitor.seltags] ^ (target & TAGMASK)

        if newtagset != 0 {
            selectedMonitor.tagset[selectedMonitor.seltags] = newtagset
            clientFocus(clientFocusTop(selectedMonitor), true)
            for c in clients where VISIBLEON(c, selectedMonitor) && ISTILED(c) {
                setSizePer(selectedMonitor, c, resetProportion: true)
            }
            arrange(selectedMonitor, false, false)
        }
        printstatus(.arrangge)
        return 0
    }

    private func tagsLastTagNum(_ tags: UInt32) -> UInt32 {
        var last: UInt32 = 0

        for i in 1...UInt32(config.tagNum) where tags & (1 << (i - 1)) != 0 {
            last = i
        }
        return last
    }

    private func tagGatherLastTagNum(_ m: Monitor) -> UInt32 {
        var last: UInt32 = 0

        for c in clients {
            if c.mon !== m || c.iskilling || (c.tags & TAG0_MASK) != 0 { continue }
            let n = tagsLastTagNum(c.tags & TAGMASK)
            if n > last { last = n }
        }

        last += 1
        if last > UInt32(config.tagNum) { last = UInt32(config.tagNum) }
        return last
    }

    @discardableResult
    func viewShiftTag(_ arg: Arg, _ dir: Int) -> Bool {
        var wrapped = false

        guard let m = selectedMonitor else { return false }

        if m.isoverview || m.pertag.curtag == 0 { return false }

        let cur = getTagsFirstTagNum(m.tagset[m.seltags])
        let last = config.tagGather ? tagGatherLastTagNum(m) : UInt32(config.tagNum)
        var target = m.tagset[m.seltags]

        if dir < 0 {
            target >>= 1

            if target == 0 {
                if !config.tagCarousel { return false }
                target = 1 << (last - 1)
                wrapped = true
            }
        } else {
            target <<= 1

            if config.tagCarousel && cur >= last {
                target = 1
                wrapped = true
            } else if target & TAGMASK == 0 {
                return false
            }
        }

        target &= TAGMASK

        if target == (m.tagset[m.seltags] & TAGMASK) { return false }

        if wrapped { m.carouselAnimDir = dir < 0 ? -1 : 1 }

        clientSwitchView(Arg(i: arg.i, ui: target), true)
        m.carouselAnimDir = 0
        return true
    }

    @discardableResult
    func viewShiftTagHaveClient(_ arg: Arg, _ dir: Int) -> Bool {
        guard let sm = selectedMonitor else { return false }

        if sm.isoverview || isSpecialActive(sm) { return false }

        var n: UInt32 = 0
        let current = getTagsFirstTagNum(sm.tagset[sm.seltags])
        var found = false
        var wrapped = false

        if dir < 0 {
            var k = current
            while k > 1 {
                k -= 1
                if getTagStatus(k, sm) != 0 { n = k; found = true; break }
            }

            if !found && config.tagCarousel {
                var k = UInt32(config.tagNum)
                while k > current {
                    if getTagStatus(k, sm) != 0 { n = k; found = true; wrapped = true; break }
                    k -= 1
                }
            }
        } else {
            var k = current + 1
            while k <= UInt32(config.tagNum) {
                if getTagStatus(k, sm) != 0 { n = k; found = true; break }
                k += 1
            }

            if !found && config.tagCarousel {
                var k: UInt32 = 1
                while k < current {
                    if getTagStatus(k, sm) != 0 { n = k; found = true; wrapped = true; break }
                    k += 1
                }
            }
        }

        if found {
            if wrapped { sm.carouselAnimDir = dir < 0 ? -1 : 1 }
            clientSwitchView(Arg(i: arg.i, ui: (1 << (n - 1)) & TAGMASK), true)
            sm.carouselAnimDir = 0
            return true
        }
        return false
    }

    func viewToLeft(_ arg: Arg) -> Int32 {
        viewShiftTag(arg, -1)
        return 0
    }

    func viewToRight(_ arg: Arg) -> Int32 {
        viewShiftTag(arg, 1)
        return 0
    }

    func viewInsert(_ arg: Arg) -> Int32 {
        guard let sm = selectedMonitor, !sm.isoverview else { return 0 }

        let curmask = sm.tagset[sm.seltags] & TAGMASK
        if curmask == 0 || (curmask & (curmask - 1)) != 0 { return 0 }
        let cur = getTagsFirstTagNum(curmask)
        if cur == 0 { return 0 }

        let target: UInt32
        if arg.i == NEXT {
            if cur >= UInt32(config.tagNum) { return 0 }
            target = cur + 1
        } else if cur == 1 {
            target = cur
        } else if getTagStatus(cur - 1, sm) == 0 {
            target = cur - 1
        } else {
            target = cur
        }

        if getTagStatus(target, sm) == 0 {
            clientSwitchView(Arg(ui: (1 << (target - 1)) & TAGMASK), true)
            return 0
        }

        if target >= UInt32(config.tagNum) || getTagStatus(UInt32(config.tagNum), sm) != 0 { return 0 }

        viewInsertShiftTags(sm, target)
        let tagGatherBak = config.tagGather
        config.tagGather = false
        clientSwitchView(Arg(ui: (1 << (target - 1)) & TAGMASK), true)
        config.tagGather = tagGatherBak
        return 0
    }

    func viewToLeftHaveClient(_ arg: Arg) -> Int32 {
        viewShiftTagHaveClient(arg, -1)
        return 0
    }

    func viewToRightHaveClient(_ arg: Arg) -> Int32 {
        viewShiftTagHaveClient(arg, 1)
        return 0
    }

    func viewprevHaveClient(_ arg: Arg) -> Int32 {
        viewShiftTagHaveClient(arg, -1)
        return 0
    }

    func viewnextHaveClient(_ arg: Arg) -> Int32 {
        viewShiftTagHaveClient(arg, 1)
        return 0
    }

    func viewCrossMonitor(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        _ = focusMonitor(Arg(i: UNDIR, v: arg.v))
        clientViewOnMonitor(arg, true, selectedMonitor, true)
        return 0
    }

    func tagCrossMonitor(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        guard let c = arg.tc ?? focused else { return 0 }

        if let v = arg.v, MonitorSpec(mango: v).matchMonitorSpec(name: selectedMonitor.screen.name) {
            tagClient(arg, c)
            return 0
        }

        let a = Arg(i: UNDIR, v: arg.v, ui: arg.ui, tc: c)
        _ = tagMonitor(a)
        return 0
    }

    func comboView(_ arg: Arg) -> Int32 {
        let newtags = arg.ui & TAGMASK

        if newtags == 0 || selectedMonitor == nil { return 0 }

        if tagCombo {
            selectedMonitor.tagset[selectedMonitor.seltags] |= newtags
            clientFocus(clientFocusTop(selectedMonitor), true)
            arrange(selectedMonitor, false, false)
        } else {
            tagCombo = true
            clientSwitchView(Arg(ui: newtags), true)
        }

        printstatus(.arrangge)
        return 0
    }

    func zoom(_ arg: Arg) -> Int32 {
        var sel: Client? = arg.tc ?? clientFocusTop(selectedMonitor)

        guard let s0 = sel, selectedMonitor != nil, !s0.isfloating else { return 0 }

        var found: Client?
        for c in clients where VISIBLEON(c, selectedMonitor) && !c.isfloating {
            if c !== sel { found = c; break }
            sel = nil
        }

        guard let c = found else { return 0 }

        let z = sel ?? c
        clients.removeAll { $0 === z }
        clients.insert(z, at: 0)

        clientFocus(z, true)
        arrange(selectedMonitor, false, false)
        return 0
    }

    func setoption(_ arg: Arg) -> Int32 {
        ConfigParser.parseOption(&config, arg.v ?? "", arg.v2 ?? "", 0, baseDirectory: configURL.deletingLastPathComponent())
        config.overrideConfig()
        updateGlobalVar()   // not in mango: override_config's last step
        resetOption()
        return 0
    }

    func minimizeWindow(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        if selectedMonitor != nil && selectedMonitor.isoverview { return 0 }

        if let c = arg.tc ?? focused, !c.isminimized {
            setMinimized(c)
        }
        return 0
    }

    func fixMonTagsetFromOverview(_ m: Monitor) {
        if m.tagset[m.seltags] == m.ovbkPrevTagset & TAGMASK {
            m.tagset[m.seltags ^ 1] = m.ovbkCurrentTagset
            m.pertag.prevtag = getTagsFirstTagNum(m.ovbkCurrentTagset)
        } else {
            m.tagset[m.seltags ^ 1] = m.ovbkPrevTagset
            m.pertag.prevtag = getTagsFirstTagNum(m.ovbkPrevTagset)
        }
    }

    private func overviewClientOnCurrentTags(_ c: Client, _ onlyCurrent: Bool, _ currentTags: UInt32) -> Bool {
        !onlyCurrent || c.isglobal || c.tags & currentTags != 0
    }

    /* Enter or leave overview mode on the selected monitor. */
    private func setOverview(_ arg: Arg, _ enter: Bool) {
        let m: Monitor = selectedMonitor
        let sel = arg.tc ?? focused
        var target: UInt32 = 0
        var visibleClientNumber = 0
        let onlyCurrent = arg.i == 1
        var currentTags: UInt32 = 0
        defer { publishInputState() }   // not in mango: the event tap's snapshot

        m.isoverview = enter

        if !enter {
            m.ovTabLayout = false
            titleMessageBarHide(m)
            if m.isJumpMode {
                finishJumpMode(m)
            }
        }

        if enter {
            currentTags = m.tagset[m.seltags] & TAGMASK
            for c in clients where c.mon === m {
                // not in mango: no unmanaged clients or X11 popups
                if !c.isminimized && !c.isunglobal && c.tags & TAG0_MASK == 0
                    && overviewClientOnCurrentTags(c, onlyCurrent, currentTags) {
                    visibleClientNumber += 1
                }
            }
            if visibleClientNumber > 0 {
                m.ovbkCurrentTagset = m.tagset[m.seltags]
                m.ovbkPrevTagset = m.tagset[m.seltags ^ 1]
                target = onlyCurrent ? currentTags : (~0 & TAGMASK)
            } else {
                m.isoverview = false
                m.ovTabLayout = false
                titleMessageBarHide(m)
                // not in mango: jump mode ends as when leaving overview (a mango bug, docs/afvigelser.md §6).
                if m.isJumpMode {
                    finishJumpMode(m)
                }
                // not in mango: the hot area's normal mode ends too (a mango bug, docs/afvigelser.md §6).
                m.ovNormalMode = false
                return
            }
        } else if let sel, sel.tags & TAGMASK != 0 {
            target = getTagsFirstTag(sel.tags)
        } else {
            target = m.ovbkCurrentTagset != 0
                ? (m.ovbkCurrentTagset & TAGMASK)
                : (m.pertag.prevtag != 0 ? 1 << (m.pertag.prevtag - 1) : 1)
            if target == 0 {
                target = 1
            }
        }

        if enter {
            // not in mango: no pointer focus to clear; the cursor is macOS'

            for c in clients where c.mon === m {
                // not in mango: every Client is a mapped window
                if c.isunglobal || c.isminimized || c.tags & TAG0_MASK != 0
                    || !overviewClientOnCurrentTags(c, onlyCurrent, currentTags) {
                    continue
                }
                c.animation.overining = true
                if !m.isJumpMode && !m.ovNormalMode {
                    /* Tab layout: skip view arrangement first; set it when the
                     * unified rearrange runs after entering. */
                    c.animation.overviewEnterAnimSet = true
                } else {
                    /* Other modes: set zoom during view arrangement. */
                    c.animation.overviewEnterAnimSet = false
                }
                overviewBackup(c)
            }
            overviewCardsShow(m)   // not in mango: the port's pictures, overview_backup_surface's card trees
        } else {
            m.ovNormalMode = false /* Clears hot-area normal mode when exiting overview. */

            m.tagset[m.seltags] = target
            overviewCardsClose(m)   // not in mango: the port's pictures, overview_destroy_card
            for c in clients where c.mon === m && !c.iskilling && !c.isunglobal && !c.isminimized && c.tags & TAG0_MASK == 0 {
                overviewRestore(c, target)
            }
        }

        clientSwitchView(Arg(ui: target), false)

        /* Tab layout: rearrange after entering. */
        if enter && !m.isJumpMode && !m.ovNormalMode {
            for cc in clients where cc.mon === m && cc.tags & TAG0_MASK == 0 {
                cc.animation.overviewEnterAnimSet = false
            }
            arrange(m, true, false)
        }
        if enter {
            overviewCardSurfaceAdd(m)   // not in mango: the port's thumbnails of the cards
        }
        fixMonTagsetFromOverview(m)
        printstatus(.arrangge)   // not in mango: refresh_monitors_workspaces_status is ext-workspace's

        if !enter, let sel, sel.tags & target != 0 {
            clientFocus(sel, true)
        }
    }

    @discardableResult
    func toggleOverview(_ arg: Arg) -> Int32 {
        guard let m = selectedMonitor, grabClient == nil else { return 0 }

        setOverview(arg, !m.isoverview)
        return 0
    }

    @discardableResult
    func enterOverview(_ arg: Arg) -> Int32 {
        guard let m = selectedMonitor, grabClient == nil, !m.isoverview else { return 0 }

        setOverview(arg, true)
        return 0
    }

    @discardableResult
    func leaveOverview(_ arg: Arg) -> Int32 {
        guard let m = selectedMonitor, grabClient == nil, m.isoverview else { return 0 }

        setOverview(arg, false)
        return 0
    }

    @discardableResult
    func toggleJump(_ arg: Arg) -> Int32 {
        guard let m = selectedMonitor else { return 0 }
        // not in mango: begin_jump_mode stays on when toggle_overview refuses a grab (a mango bug, docs/afvigelser.md §6)
        if grabClient != nil { return 0 }

        if !m.isoverview {
            beginJumpMode(m)
            toggleOverview(arg)
            return 0
        }

        if m.isoverview {
            toggleOverview(arg)
        }

        return 0
    }

    func disableMonitor(_ arg: Arg) -> Int32 {
        // not in mango: displays are managed by macOS (MangoCompat)
        return 0
    }

    func enableMonitor(_ arg: Arg) -> Int32 {
        // not in mango: displays are managed by macOS (MangoCompat)
        return 0
    }

    func toggleMonitor(_ arg: Arg) -> Int32 {
        // not in mango: displays are managed by macOS (MangoCompat)
        return 0
    }

    func sleepMonitor(_ arg: Arg) -> Int32 {
        // not in mango: displays are managed by macOS (MangoCompat)
        return 0
    }

    func wakeupMonitor(_ arg: Arg) -> Int32 {
        // not in mango: displays are managed by macOS (MangoCompat)
        return 0
    }

    func sleepToggleMonitor(_ arg: Arg) -> Int32 {
        // not in mango: displays are managed by macOS (MangoCompat)
        return 0
    }

    func scrollerApplyStack(_ c: Client?, _ targetClient: Client?, _ direction: Int32) {
        guard let c, let m = c.mon, !c.isfloating, isScrollerLayout(m) else { return }

        let tag = getClientTagIdx(c)

        let isHorizontal = m.pertag.ltidxs[tag] == .scroller

        if isHorizontal && (direction == UP || direction == DOWN) { return }
        if !isHorizontal && (direction == LEFT || direction == RIGHT) { return }

        let st = ensureScrollerState(m, tag)

        guard let cnode = findScrollerNode(st, c) else { return }

        let tnode = targetClient.flatMap { findScrollerNode(st, $0) }

        if direction == UNDIR, let targetClient, targetClient.mon === c.mon {
            scrollerInsertStack(c, targetClient, false)
            return
        }

        if cnode.prevInStack != nil || cnode.nextInStack != nil {
            let moveOutReferNode = cnode.prevInStack ?? cnode.nextInStack!
            scrollerNodeRemove(st, cnode)

            updateScrollerState(m)

            let stackHead = scrollGetStackHeadClient(moveOutReferNode.client)
            let stackTail = scrollGetStackTailClient(moveOutReferNode.client)

            if direction == LEFT || direction == UP {
                if c !== stackHead { wlListSafeReinsertPrev(stackHead, c) }
            } else if direction == RIGHT || direction == DOWN {
                if c !== stackTail { wlListSafeReinsertNext(stackHead, c) }
            }
            syncScrollerStateToClients(m, tag)
            arrange(m, false, false)
            return
        }

        guard let tnode, let targetClient, targetClient.mon === c.mon else { return }

        var tail = tnode
        while let n = tail.nextInStack { tail = n }

        scrollerInsertStack(c, tail.client, false)

        if c !== tail.client {
            clients.removeAll { $0 === c }
            if let i = clients.firstIndex(where: { $0 === tail.client }) { clients.insert(c, at: i + 1) }
        }
    }

    func scrollerStack(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }
        guard let c = arg.tc ?? focused, c.mon != nil, !c.isfloating, isScrollerLayout(selectedMonitor) else { return 0 }

        let targetClient = findClientByDirection(c, arg, false)

        scrollerApplyStack(c, targetClient, arg.i)
        return 0
    }

    func toggleAllFloating(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        guard let ref = arg.tc ?? focused else { return 0 }

        let shouldFloating = !ref.isfloating

        for c in clients where VISIBLEON(c, selectedMonitor) {
            if c.isfloating && !shouldFloating {
                c.oldMasterInnerPer = 0
                c.oldStackInnerPer = 0
                setSizePer(selectedMonitor, c, resetProportion: false)
            }

            if c.isfloating != shouldFloating {
                clientSetFloating(c, shouldFloating, false)
            }
        }

        for id in focusStack.reversed() {
            guard let c = clientByIdAll(id), VISIBLEON(c, selectedMonitor) else { continue }
            clientRaiseGroup(c)
            clientRaiseTab(c)
        }
        return 0
    }

    func dwindleSetSplitDirection(_ c: Client, _ istoggle: Bool, _ horizontal: Bool) {
        guard let m = c.mon else { return }   // not in mango: c->mon is always set here
        let tag = getClientTagIdx(c)
        if m.pertag.ltidxs[tag] != .dwindle { return }

        guard let leaf = dwindleFindLeaf(m.pertag.dwindleRoot[tag], c) else { return }

        if istoggle {
            leaf.customLeafSplitH = !leaf.customLeafSplitH
        } else if horizontal {
            leaf.customLeafSplitH = true
        } else {
            leaf.customLeafSplitH = false
        }
        updateBorders()   // not in mango: client_draw_split_border; the port draws the split in the border's overlay
    }

    func dwindleToggleSplitDirection(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        guard let c = arg.tc ?? focused, c.mon != nil, !c.isfloating else { return 0 }
        dwindleSetSplitDirection(c, true, false)
        return 0
    }

    func dwindleSplitHorizontal(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        guard let c = arg.tc ?? focused, c.mon != nil, !c.isfloating else { return 0 }
        dwindleSetSplitDirection(c, false, true)
        return 0
    }

    func dwindleSplitVertical(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }

        guard let c = arg.tc ?? focused, c.mon != nil, !c.isfloating else { return 0 }
        dwindleSetSplitDirection(c, false, false)
        return 0
    }

    func dwindleToggleCurrentSplit(_ arg: Arg) -> Int32 {
        if selectedMonitor == nil { return 0 }
        guard let c = arg.tc ?? focused, let m = c.mon, !c.isfloating else { return 0 }

        let tag = getClientTagIdx(c)
        if m.pertag.ltidxs[tag] != .dwindle { return 0 }

        let root = m.pertag.dwindleRoot[tag]
        guard let leaf = dwindleFindLeaf(root, c), let parent = leaf.parent else { return 0 }

        parent.splitH = !parent.splitH
        parent.splitLocked = true

        arrange(m, false, false)
        return 0
    }

    func focusById(_ arg: Arg) -> Int32 {
        guard selectedMonitor != nil, let tc = arg.tc else { return 0 }

        clientActive(tc)
        return 0
    }

    func loadConfigFile(_ arg: Arg) -> Int32 {
        // not in mango: cli_config_path is configURL, empty for the default path
        let v = arg.v ?? ""
        configURL = v.isEmpty ? ConfigParser.defaultConfigURL() : URL(fileURLWithPath: v)
        return reloadConfig(arg)
    }
}
