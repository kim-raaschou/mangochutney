import CoreGraphics

@MainActor
package struct OverviewState {
    package let monitor: Monitor
    package let previousSel: ClientID?
    var cards: [ClientID: CGRect]
    var circle = false
    package var members: [ClientID] = []
    package var circleFocus: ClientID?
    package var thumbnails = false
}

package extension MangoServer {
    /// mango is_overcircle_mode (monitor.c)
    func isOvercircleMode(_ m: Monitor) -> Bool {
        // not in mango: no ov_normal_mode
        guard let ov = overviewState, ov.monitor === m else { return false }
        return ov.circle && !m.isJumpMode
    }

    func toggleOverview(onlyCurrent: Bool, circle: Bool = false) {
        if overviewState != nil { leaveOverview(select: nil); return }
        let m = selectedMonitor!
        let tagmask = TagMask.mask(forTagNum: config.tagNum)
        let members: [Client] = clients.filter { c in
            c.mon === m && !c.isMinimized && !c.isUnglobal && c.tags & TagMask.special == 0
                && (!onlyCurrent || c.isVisible(on: m))
        }
        guard !members.isEmpty else {
            titleMessageBarHide(m)
            // not in mango: jump mode ends as when leaving overview (a mango bug, docs/afvigelser.md §6).
            if m.isJumpMode {
                finishJumpMode(m)
            }
            return
        }
        for c in members {
            c.overining = true
            overviewBackup(c)
        }
        let sizes = members.map { c -> (id: ClientID, size: CGSize) in
            let f = c.overviewBackupGeom!
            return (c.id, f.width <= 0 || f.height <= 0 ? CGSize(width: 100, height: 100) : f.size)
        }
        let focusID = m.sel.flatMap { id in members.contains { $0.id == id } ? id : nil } ?? members[0].id
        let cards = circle
            ? OverviewLayout.overviewScaleTab(clients: sizes, focused: focusID, workArea: m.screen.workArea,
                                            gapInner: CGFloat(config.overviewgappi), gapOuter: CGFloat(config.overviewgappo),
                                            centerRatio: CGFloat(config.overcircleCenterRatio),
                                            titleBlockHeight: config.titleMessageBarHeight > 0
                                                ? CGFloat(config.titleMessageBarHeight + config.titleMessageBarGap) : 0)
            : OverviewLayout.overviewScale(clients: sizes, workArea: m.screen.workArea,
                                  gapInner: CGFloat(config.overviewgappi),
                                  gapOuter: CGFloat(config.overviewgappo))
        m.ovbkCurrentTagset = m.tagset[m.seltags]
        m.ovbkPrevTagset = m.tagset[m.seltags ^ 1]
        var state = OverviewState(monitor: m, previousSel: m.sel, cards: cards)
        state.circle = circle
        state.members = members.map(\.id)
        state.circleFocus = circle ? focusID : nil
        if system.canCapture {   // not in mango: the port's side
            state.thumbnails = true
            let look = OverviewLook(focusColor: config.focuscolor, borderColor: config.bordercolor,
                                    mango: (config.rootcolor, CGFloat(config.borderpx), CGFloat(config.borderRadius)))
            overviewState = state
            clientViewOnMonitor(onlyCurrent ? m.tagset[m.seltags] & tagmask : tagmask, on: m, changeFocus: true)
            system.showOverview(overlayCards(state, focused: state.circleFocus ?? m.sel), on: m, look: look)   // not in mango: the port's side
            overviewCardSurfaceAdd(state)
            titleMessageBarUpdateGeometry(m)   // not in mango: client_draw_frame's call (animation/client.c), once at the card
            printstatus()
            return
        }
        system.askToCapture()   // not in mango: the port's side
        overviewState = state
        clientViewOnMonitor(onlyCurrent ? m.tagset[m.seltags] & tagmask : tagmask, on: m, changeFocus: true)
        arrange(m)
        titleMessageBarUpdateGeometry(m)   // not in mango: client_draw_frame's call (animation/client.c), once at the card
        printstatus()
    }


    func fixMonTagsetFromOverview(_ m: Monitor) {
        let tagmask = TagMask.mask(forTagNum: config.tagNum)
        if m.tagset[m.seltags] == m.ovbkPrevTagset & tagmask {
            m.tagset[m.seltags ^ 1] = m.ovbkCurrentTagset
            m.prevTag = TagMask.getTagsFirstTagNum(m.ovbkCurrentTagset) ?? m.prevTag
        } else {
            m.tagset[m.seltags ^ 1] = m.ovbkPrevTagset
            m.prevTag = TagMask.getTagsFirstTagNum(m.ovbkPrevTagset) ?? m.prevTag
        }
    }

    /// Not in mango: card list for the port's overview overlay.
    func overlayCards(_ ov: OverviewState, focused: ClientID?) -> [OverviewCard] {
        ov.cards.compactMap { id, frame in
            guard let c = clientByIdAll(id) else { return nil }
            return OverviewCard(id: id, frame: frame, title: c.title.isEmpty ? c.appName : c.title,
                                pid: c.pid, focused: id == focused)
        }
    }

    func overviewCardSurfaceAdd(_ ov: OverviewState) {
        if ov.thumbnails { system.captureOverviewCards(scale: CGFloat(ov.monitor.screen.scale)) }   // not in mango: the port's side
    }



    func overCircle(forward: Bool) {
        guard var ov = overviewState, ov.circle, !ov.members.isEmpty else { return }
        let ids = ov.members.filter { clientByIdAll($0) != nil }
        guard !ids.isEmpty else { return }
        let members = Set(ids)
        let order = clients.map(\.id).filter { members.contains($0) } + ids.filter { id in !clients.contains { $0.id == id } }
        let i = (ov.circleFocus ?? selectedMonitor.sel).flatMap { order.firstIndex(of: $0) } ?? 0
        let next = order[forward ? (i + 1) % order.count : (i - 1 + order.count) % order.count]
        let sizes = ids.compactMap { id -> (id: ClientID, size: CGSize)? in
            guard let c = clientByIdAll(id) else { return nil }
            let f = c.overviewBackupGeom ?? (c.isFloating ? c.floatGeom : (c.geom ?? c.frame))
            return (id, f.width <= 0 || f.height <= 0 ? CGSize(width: 100, height: 100) : f.size)
        }
        ov.circleFocus = next
        ov.cards = OverviewLayout.overviewScaleTab(clients: sizes, focused: next, workArea: ov.monitor.screen.workArea,
                                            gapInner: CGFloat(config.overviewgappi), gapOuter: CGFloat(config.overviewgappo),
                                            centerRatio: CGFloat(config.overcircleCenterRatio),
                                            titleBlockHeight: config.titleMessageBarHeight > 0
                                                ? CGFloat(config.titleMessageBarHeight + config.titleMessageBarGap) : 0)
        overviewState = ov
        if ov.thumbnails {
            system.updateOverview(overlayCards(ov, focused: next))   // not in mango: the port's side
            if let c = clientByIdAll(next) { clientFocus(c, true) }
            titleMessageBarUpdateGeometry(ov.monitor)   // not in mango: client_draw_frame's call (animation/client.c), once at the card
            return
        }
        overview(ov)
        if let c = clientByIdAll(next) { clientFocus(c, true) }
        titleMessageBarUpdateGeometry(ov.monitor)   // not in mango: client_draw_frame's call (animation/client.c), once at the card
    }

    func overview(_ ov: OverviewState) {
        let m = ov.monitor
        if !ov.thumbnails {   // not in mango: the pictures are the cards; the real windows stay under them
            for c in clientsAll where c.mon === m {
                if let f = ov.cards[c.id] {
                    system.resize(c, to: f, .move)
                } else {
                    system.hide(c)
                }
            }
            updateBorders()
        }

        if m.isJumpMode {
            createJumpHints(m)
        }
    }

    func beginJumpMode(_ m: Monitor) {
        m.isJumpMode = true
        publishInputState()   // not in mango: the event tap's snapshot
    }

    func createJumpHints(_ m: Monitor) {
        // Uses the static default sequence when jump_labels is not configured.
        let jumpLabels = Array(config.jumpLabels)
        if jumpLabels.isEmpty {
            return
        }
        let jumpLabelsLen = jumpLabels.count
        var labelIdx = 0

        for c in clients {
            if c.isVisible(on: m) && !c.isUnglobal {   // not in mango: no X11 popups
                if labelIdx >= jumpLabelsLen {
                    break
                }
                let cChar = jumpLabels[labelIdx]
                c.jumpChar = cChar
                findKeycodesForChar(cChar, &c.jumpKeycodes)

                c.jumpLabelNode?.update(String(cChar), m.screen.scale)
                overviewUpdateJumpLabel(c)
                labelIdx += 1
            }
        }
        publishInputState()   // not in mango: the event tap's snapshot
    }

    func finishJumpMode(_ m: Monitor) {
        if !m.isJumpMode {
            return
        }

        for c in clients {
            if c.mon !== m {
                continue
            }

            c.jumpChar = nil
            c.jumpKeycodes = MultiKeycode()

            if let label = c.jumpLabelNode, label.enabled {
                label.setEnabled(false)
            }
        }
        m.isJumpMode = false
        publishInputState()   // not in mango: the event tap's snapshot
    }

    func overviewUpdateJumpLabel(_ c: Client) {
        guard let m = c.mon, let ov = overviewState, ov.monitor === m, m.isJumpMode, c.jumpChar != nil,
              let label = c.jumpLabelNode else { return }
        // not in mango: the client's card stands for its ov_card_tree and c->animation.current
        guard let cur = ov.cards[c.id] else { return }

        let lw = label.logicalWidth
        let lh = label.logicalHeight
        if lw <= 0 || lh <= 0 {
            if label.enabled {
                label.setEnabled(false)
            }
            return
        }

        let lx = cur.minX + ((cur.width - lw) / 2).rounded(.towardZero)
        let ly = cur.minY + ((cur.height - lh) / 2).rounded(.towardZero)
        let mm = m.screen.frame
        if lx < mm.minX || ly < mm.minY || lx + lw > mm.maxX || ly + lh > mm.maxY {
            if label.enabled {
                label.setEnabled(false)
            }
            return
        }

        label.setPosition(lx, ly)
        if !label.enabled {
            label.setEnabled(true)
            label.raiseToTop()
        }
    }

    /// mango find_keycodes_for_char (config/binding_parse.c)
    func findKeycodesForChar(_ cChar: Character?, _ multiKc: inout MultiKeycode) {
        multiKc = MultiKeycode()

        guard let cChar else { return }

        multiKc = system.findKeycodesForKeysym(cChar)   // not in mango: the port's side (xkb's keymap)
    }

    /// mango toggle_jump (dispatch/bind.c)
    func toggleJump() {
        guard let m = selectedMonitor else { return }

        if overviewState?.monitor !== m {
            beginJumpMode(m)
            toggleOverview(onlyCurrent: false)
            return
        }

        leaveOverview(select: nil)
    }

    /// mango keyboard_find_jump_client (input/keyboard.c)
    func keyboardFindJumpClient(_ m: Monitor, _ keycode: UInt16) -> Client? {
        for c in clients {
            if c.mon !== m {
                continue
            }

            if keycode == c.jumpKeycodes.keycode1 ||
                keycode == c.jumpKeycodes.keycode2 ||
                keycode == c.jumpKeycodes.keycode3 {
                return c
            }
        }

        return nil
    }

    // Saves the window old state when switching from the normal view to overview.
    func overviewBackup(_ c: Client) {
        c.overviewIsFloatingBak = c.isFloating
        c.overviewIsFullscreenBak = c.isFullscreen
        c.overviewIsMaximizeScreenBak = c.isMaximizeScreen
        c.overviewBackupGeom = c.isFloating ? c.floatGeom : (c.geom ?? c.frame)   // not in mango: our geom is without the border, a floating one's is floatGeom
        if c.isFloating {
            c.isFloating = false
        }

        if c.isFullscreen || c.isMaximizeScreen {
            c.isFullscreen = false // Clears the window fullscreen flag.
            c.isMaximizeScreen = false
        }
    }

    // Restores window state when switching back from overview to the normal view.
    func overviewRestore(_ c: Client, thumbnails: Bool) {
        guard let b = c.overviewBackupGeom else { return }
        c.isFloating = c.overviewIsFloatingBak
        c.isFullscreen = c.overviewIsFullscreenBak
        c.isMaximizeScreen = c.overviewIsMaximizeScreenBak
        c.overviewIsFloatingBak = false
        c.overviewIsFullscreenBak = false
        c.overviewIsMaximizeScreenBak = false
        if !thumbnails && !c.isFloating { c.geom = b }   // not in mango: the pictures are the cards; the windows kept their place
        c.overviewBackupGeom = nil
    }

    // not in mango: set_overview's leaving branch, which toggle_overview with a tc runs
    func leaveOverview(select: Client?) {
        guard let ov = overviewState else { return }
        if ov.thumbnails { system.closeOverview() }
        titleMessageBarHide(ov.monitor)
        if ov.monitor.isJumpMode {
            finishJumpMode(ov.monitor)
        }
        overviewState = nil
        let m = ov.monitor
        let sel = select ?? m.sel.flatMap { clientByIdAll($0) }
        let tagmask = TagMask.mask(forTagNum: config.tagNum)
        var target: UInt32
        if let s = sel, s.tags & tagmask != 0 {
            target = getTagsFirstTag(s.tags)
        } else {
            target = m.ovbkCurrentTagset != 0 ? m.ovbkCurrentTagset & tagmask : (m.prevTag > 0 ? 1 << UInt32(m.prevTag - 1) : 1)
            if target == 0 { target = 1 }
        }
        m.tagset[m.seltags] = target
        for id in ov.members {
            guard let c = clientByIdAll(id) else { continue }
            overviewRestore(c, thumbnails: ov.thumbnails)
        }
        clientViewOnMonitor(target, on: m, changeFocus: true)
        fixMonTagsetFromOverview(m)
        for id in ov.members { clientByIdAll(id)?.overining = false }
        if !ov.thumbnails { arrange(m) }
        if let s = sel, s.tags & target != 0 { clientFocus(s, true) }
        printstatus()
    }
}
