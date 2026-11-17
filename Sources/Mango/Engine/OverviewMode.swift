import CoreGraphics

package extension MangoServer {

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
        clients.filter { $0.mon === m && VISIBLEON($0, m) && !$0.isunglobal }.map { c in
            let f = c.overviewBackupGeom
            return (c.id, f.width <= 0 || f.height <= 0 ? CGSize(width: 100, height: 100) : f.size)
        }
    }

    func overviewScale(_ m: Monitor) {
        let items = overviewItems(m)
        if items.isEmpty { return }
        overviewTileResize(m, OverviewLayout.overviewScale(clients: items, workArea: m.w,
                                                           gapInner: CGFloat(config.overviewgappi),
                                                           gapOuter: CGFloat(config.overviewgappo)))
    }

    func overviewScaleTab(_ m: Monitor) {
        let items = overviewItems(m)
        if items.isEmpty { return }
        overviewTileResize(m, OverviewLayout.overviewScaleTab(
            clients: items, focused: m.sel, workArea: m.w,
            gapInner: CGFloat(config.overviewgappi), gapOuter: CGFloat(config.overviewgappo),
            centerRatio: CGFloat(config.overcircleCenterRatio),
            titleBlockHeight: config.titleMessageBarHeight > 0
                ? CGFloat(config.titleMessageBarHeight + config.titleMessageBarGap) : 0))
    }

    // not in mango: client_tile_resize of each card; the pictures are the cards, the real windows stay under them
    func overviewTileResize(_ m: Monitor, _ cards: [ClientID: CGRect]) {
        m.ovCards = cards
        if m.ovThumbnails {
            for id in cards.keys { clientByIdAll(id)?.animation.overining = false }
            system.updateOverview(overlayCards(m), on: m)
            return
        }
        for c in clientsAll where c.mon === m {
            if let f = cards[c.id] {
                c.tagVisible = true   // not in mango: the card is the window itself
                resize(c, f, ResizeOpts())
            } else {
                c.tagVisible = false   // not in mango: a window with no card is hidden
                clientUpdateVisibility(c)
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
            if VISIBLEON(c, m) && !c.isunglobal {   // not in mango: no X11 popups
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
        let mm = m.m
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

    // Saves the window old state when switching from the normal view to overview.
    func overviewBackup(_ c: Client) {
        c.overviewIsfloatingbak = c.isfloating
        c.overviewIsfullscreenbak = c.isfullscreen
        c.overviewIsmaximizescreenbak = c.ismaximizescreen
        c.animation.tagining = false
        c.animation.tagouted = false
        c.animation.tagouting = false
        c.overviewBackupGeom = c.geom
        c.overviewBackedUp = true   // not in mango: a mango bug, docs/afvigelser.md §6
        c.overviewBackupBw = c.bw
        if c.isfloating {
            c.isfloating = false
        }

        if c.isfullscreen || c.ismaximizescreen {
            c.isfullscreen = false // Clears the window fullscreen flag.
            c.ismaximizescreen = false
        }
        c.bw = c.noBorder ? 0 : CGFloat(config.borderpx)
    }

    // Returns 0 when the target window shares its tag with other windows.
    func wantRestoreFullscreen(_ targetClient: Client) -> Bool {
        for c in clients where c !== targetClient && c.tags == targetClient.tags && c.id == selectedMonitor.sel {
            guard let m = c.mon else { continue }
            let layout = m.pertag.ltidxs[getClientTagIdx(c)]
            if layout != .scroller && layout != .verticalScroller {
                return false
            }
        }

        return true
    }

    // Restores window state when switching back from overview to the normal view.
    func overviewRestore(_ c: Client, _ target: UInt32) {
        // not in mango: a client mapped in overview has no backup and keeps its state (a mango bug, docs/afvigelser.md §6)
        guard c.overviewBackedUp else { return }
        c.overviewBackedUp = false

        c.isfloating = c.overviewIsfloatingbak
        c.isfullscreen = c.overviewIsfullscreenbak
        c.ismaximizescreen = c.overviewIsmaximizescreenbak
        c.overviewIsfloatingbak = false
        c.overviewIsfullscreenbak = false
        c.overviewIsmaximizescreenbak = false
        c.geom = c.overviewBackupGeom
        c.bw = c.overviewBackupBw
        c.animation.tagining = false

        if c.isfloating {
            // not in mango: arrange places a floating client at its floatGeom
        } else if c.isfullscreen || c.ismaximizescreen {
            if wantRestoreFullscreen(c) && c.ismaximizescreen {
                clientSetMaximizeScreen(c, true, rearrange: false)
            } else if wantRestoreFullscreen(c) && c.isfullscreen {
                clientSetFullscreen(c, true, rearrange: false)
            } else {
                c.isfullscreen = false
                c.ismaximizescreen = false
                clientSetFullscreen(c, false, rearrange: false)
            }
        } else if target & c.tags & TAGMASK == 0 {
            // not in mango: is_restoring_from_ov's resize; the geom is the backup, and the window is placed when shown
        }
    }
}
