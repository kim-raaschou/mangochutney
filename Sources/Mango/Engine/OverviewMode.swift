import CoreGraphics

package extension MangoServer {
    /// mango is_overcircle_mode (monitor.c)
    func isOvercircleMode(_ m: Monitor?) -> Bool {
        guard let m else { return false }
        return m.isoverview && m.ovTabLayout && !m.isJumpMode && !m.ovNormalMode
    }

    func fixMonTagsetFromOverview(_ m: Monitor) {
        let tagmask = TagMask.mask(forTagNum: config.tagNum)
        if m.tagset[m.seltags] == m.ovbkPrevTagset & tagmask {
            m.tagset[m.seltags ^ 1] = m.ovbkCurrentTagset
            m.prevTag = TagMask.getTagsFirstTagNum(m.ovbkCurrentTagset) ?? 0
        } else {
            m.tagset[m.seltags ^ 1] = m.ovbkPrevTagset
            m.prevTag = TagMask.getTagsFirstTagNum(m.ovbkPrevTagset) ?? 0
        }
    }

    func overviewClientOnCurrentTags(_ c: Client, _ onlyCurrent: Bool, _ currentTags: UInt32) -> Bool {
        !onlyCurrent || c.isGlobal || c.tags & currentTags != 0
    }

    /* Enter or leave overview mode on the selected monitor. */
    func setOverview(tc: Client?, onlyCurrent: Bool, enter: Bool) {
        let m: Monitor = selectedMonitor
        let sel = tc ?? m.sel.flatMap { clientByIdAll($0) }
        var target: UInt32 = 0
        var visibleClientNumber = 0
        var currentTags: UInt32 = 0
        let tagmask = TagMask.mask(forTagNum: config.tagNum)
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
            currentTags = m.tagset[m.seltags] & tagmask
            for c in clients where c.mon === m {
                // not in mango: no unmanaged clients or X11 popups
                if !c.isMinimized && !c.isUnglobal && c.tags & TagMask.special == 0
                    && overviewClientOnCurrentTags(c, onlyCurrent, currentTags) {
                    visibleClientNumber += 1
                }
            }
            if visibleClientNumber > 0 {
                m.ovbkCurrentTagset = m.tagset[m.seltags]
                m.ovbkPrevTagset = m.tagset[m.seltags ^ 1]
                target = onlyCurrent ? currentTags : tagmask
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
        } else if let sel, sel.tags & tagmask != 0 {
            target = getTagsFirstTag(sel.tags)
        } else {
            target = m.ovbkCurrentTagset != 0
                ? (m.ovbkCurrentTagset & tagmask)
                : (m.prevTag != 0 ? 1 << UInt32(m.prevTag - 1) : 1)
            if target == 0 {
                target = 1
            }
        }

        if enter {
            // not in mango: no pointer focus to clear; the cursor is macOS'

            for c in clients where c.mon === m {
                // not in mango: every Client is a mapped window
                if c.isUnglobal || c.isMinimized || c.tags & TagMask.special != 0
                    || !overviewClientOnCurrentTags(c, onlyCurrent, currentTags) {
                    continue
                }
                c.overining = true
                overviewBackup(c)
            }
            overviewCardsShow(m)   // not in mango: the port's pictures, overview_backup_surface's card trees
        } else {
            m.ovNormalMode = false /* Clears hot-area normal mode when exiting overview. */

            m.tagset[m.seltags] = target
            overviewCardsClose(m)   // not in mango: the port's pictures, overview_destroy_card
            for c in clients where c.mon === m && !c.isUnglobal && !c.isMinimized && c.tags & TagMask.special == 0 {
                overviewRestore(c, target)
            }
        }

        clientSwitchView(target, wantAnimation: false)

        /* Tab layout: rearrange after entering. */
        if enter && !m.isJumpMode && !m.ovNormalMode {
            arrange(m)
        }
        if enter {
            overviewCardSurfaceAdd(m)
        }
        fixMonTagsetFromOverview(m)
        printstatus()   // not in mango: refresh_monitors_workspaces_status is ext-workspace's

        if !enter, let sel, sel.tags & target != 0 {
            clientFocus(sel, true)
        }
    }

    /// mango toggle_overview (dispatch/bind.c)
    func toggleOverview(tc: Client? = nil, onlyCurrent: Bool = false) {
        guard let m = selectedMonitor, grab == nil else { return }

        setOverview(tc: tc, onlyCurrent: onlyCurrent, enter: !m.isoverview)
    }

    /// mango enter_overview (dispatch/bind.c)
    func enterOverview(tc: Client? = nil) {
        guard let m = selectedMonitor, grab == nil, !m.isoverview else { return }

        setOverview(tc: tc, onlyCurrent: false, enter: true)
    }

    /// mango leave_overview (dispatch/bind.c)
    func leaveOverview(tc: Client? = nil) {
        guard let m = selectedMonitor, grab == nil, m.isoverview else { return }

        setOverview(tc: tc, onlyCurrent: false, enter: false)
    }

    /// mango over_circle (dispatch/bind.c)
    func overCircle(_ dir: String, tc: Client? = nil) {
        guard let m = selectedMonitor, grab == nil else { return }

        let sel = tc ?? m.sel.flatMap { clientByIdAll($0) }

        let d = dir.lowercased()
        let next = d == "next" || d == "current_next"
        let current = d == "current_next" || d == "current_prev"

        if m.isoverview && !m.isJumpMode && !m.ovNormalMode, let sel {
            m.ovTabLayout = true
            publishInputState()   // not in mango: the event tap's snapshot
            guard let tc = next ? getNextStackClient(sel, reverse: false) : getNextStackClient(sel, reverse: true) else {
                return
            }

            clientFocus(tc, true)

            arrange(m)
            return
        }

        m.ovTabLayout = true
        toggleOverview(tc: tc, onlyCurrent: current)
        if !m.isoverview {
            m.ovTabLayout = false
            publishInputState()   // not in mango: the event tap's snapshot
        }
    }

    /// Not in mango: card list for the port's overview overlay.
    func overlayCards(_ m: Monitor) -> [OverviewCard] {
        m.ovCards.compactMap { id, frame in
            guard let c = clientByIdAll(id) else { return nil }
            return OverviewCard(id: id, frame: frame, title: c.title.isEmpty ? c.appName : c.title,
                                pid: c.pid, focused: id == m.sel)
        }
    }

    /// Not in mango: the port's overlay, where mango's card trees are.
    func overviewCardsShow(_ m: Monitor) {
        m.ovThumbnails = system.canCapture
        m.ovCards = [:]
        if m.ovThumbnails {
            let look = OverviewLook(focusColor: config.focuscolor, borderColor: config.bordercolor,
                                    mango: (config.rootcolor, CGFloat(config.borderpx), CGFloat(config.borderRadius)))
            system.showOverview([], on: m, look: look)
        } else {
            system.askToCapture()
        }
    }

    /// Not in mango: the port's overlay closes with the cards.
    func overviewCardsClose(_ m: Monitor) {
        if m.ovThumbnails { system.closeOverview(on: m) }
        m.ovThumbnails = false
        m.ovCards = [:]
    }

    func overviewCardSurfaceAdd(_ m: Monitor) {
        if m.ovThumbnails { system.captureOverviewCards(on: m, scale: CGFloat(m.screen.scale)) }   // not in mango: the port's side
    }

    /// Not in mango: the overview's items, VISIBLEON and not unglobal, with overview_backup_geom's size.
    func overviewItems(_ m: Monitor) -> [(id: ClientID, size: CGSize)] {
        clients.filter { $0.mon === m && $0.isVisible(on: m) && !$0.isUnglobal }.map { c in
            let f = c.overviewBackupGeom ?? .zero
            return (c.id, f.width <= 0 || f.height <= 0 ? CGSize(width: 100, height: 100) : f.size)
        }
    }

    func overviewScale(_ m: Monitor) {
        let items = overviewItems(m)
        if items.isEmpty { return }
        overviewTileResize(m, OverviewLayout.overviewScale(clients: items, workArea: m.screen.workArea,
                                                           gapInner: CGFloat(config.overviewgappi),
                                                           gapOuter: CGFloat(config.overviewgappo)))
    }

    func overviewScaleTab(_ m: Monitor) {
        let items = overviewItems(m)
        if items.isEmpty { return }
        overviewTileResize(m, OverviewLayout.overviewScaleTab(
            clients: items, focused: m.sel, workArea: m.screen.workArea,
            gapInner: CGFloat(config.overviewgappi), gapOuter: CGFloat(config.overviewgappo),
            centerRatio: CGFloat(config.overcircleCenterRatio),
            titleBlockHeight: config.titleMessageBarHeight > 0
                ? CGFloat(config.titleMessageBarHeight + config.titleMessageBarGap) : 0))
    }

    // not in mango: client_tile_resize of each card; the pictures are the cards, the real windows stay under them
    func overviewTileResize(_ m: Monitor, _ cards: [ClientID: CGRect]) {
        m.ovCards = cards
        if m.ovThumbnails {
            for id in cards.keys { clientByIdAll(id)?.overining = false }
            system.updateOverview(overlayCards(m), on: m)
            return
        }
        for c in clientsAll where c.mon === m {
            if let f = cards[c.id] {
                system.resize(c, to: f, .move)
            } else {
                system.hide(c)
            }
        }
        updateBorders()
    }

    func overview(_ m: Monitor) {
        if m.ovTabLayout && !m.isJumpMode && !m.ovNormalMode {
            overviewScaleTab(m)
        } else {
            overviewScale(m)
        }

        if m.isJumpMode {
            createJumpHints(m)
        }
        titleMessageBarUpdateGeometry(m)   // not in mango: client_draw_frame's call (animation/client.c), once at the card
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
        guard let m = c.mon, m.isoverview, m.isJumpMode, c.jumpChar != nil,
              let label = c.jumpLabelNode else { return }
        // not in mango: the client's card stands for its ov_card_tree and c->animation.current
        guard let cur = m.ovCards[c.id] else { return }

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
    func toggleJump(tc: Client? = nil) {
        guard let m = selectedMonitor else { return }

        if !m.isoverview {
            beginJumpMode(m)
            toggleOverview(tc: tc)
            return
        }

        if m.isoverview {
            toggleOverview(tc: tc)
        }
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
        c.tagouting = false   // not in mango: no tagining or tagouted
        c.overviewBackupGeom = c.isFloating ? c.floatGeom : (c.geom ?? c.frame)   // not in mango: our geom is without the border, a floating one's is floatGeom
        if c.isFloating {
            c.isFloating = false
        }

        if c.isFullscreen || c.isMaximizeScreen {
            c.isFullscreen = false // Clears the window fullscreen flag.
            c.isMaximizeScreen = false
        }
    }

    // Returns 0 when the target window shares its tag with other windows.
    func wantRestoreFullscreen(_ targetClient: Client) -> Bool {
        for c in clients where c !== targetClient && c.tags == targetClient.tags && c.id == selectedMonitor.sel {
            guard let m = c.mon else { continue }
            let layout = m.pertag[TagMask.getTagsFirstTagNum(c.tags) ?? 0].layout
            if layout != .scroller && layout != .verticalScroller {
                return false
            }
        }

        return true
    }

    // Restores window state when switching back from overview to the normal view.
    func overviewRestore(_ c: Client, _ target: UInt32) {
        // not in mango: a client mapped in overview has no backup and keeps its state (a mango bug, docs/afvigelser.md §6)
        guard let b = c.overviewBackupGeom else { return }

        c.isFloating = c.overviewIsFloatingBak
        c.isFullscreen = c.overviewIsFullscreenBak
        c.isMaximizeScreen = c.overviewIsMaximizeScreenBak
        c.overviewIsFloatingBak = false
        c.overviewIsFullscreenBak = false
        c.overviewIsMaximizeScreenBak = false
        if !c.isFloating { c.geom = b }   // not in mango: a floating one's backup is its floatGeom
        c.overviewBackupGeom = nil

        if c.isFloating {
            // not in mango: arrange places a floating client at its floatGeom
        } else if c.isFullscreen || c.isMaximizeScreen {
            if wantRestoreFullscreen(c) && c.isMaximizeScreen {
                clientSetMaximizeScreen(c, true, rearrange: false)
            } else if wantRestoreFullscreen(c) && c.isFullscreen {
                clientSetFullscreen(c, true, rearrange: false)
            } else {
                c.isFullscreen = false
                c.isMaximizeScreen = false
                clientSetFullscreen(c, false, rearrange: false)
            }
        } else if target & c.tags & TagMask.mask(forTagNum: config.tagNum) == 0 {
            // not in mango: is_restoring_from_ov's resize; the geom is the backup, and the window is placed when shown
        }
    }
}
