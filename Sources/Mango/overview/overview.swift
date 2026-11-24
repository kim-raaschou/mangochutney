import CoreGraphics

// not in mango: the card trees (ov_card_surface, overview_card_surface_add, overview_layout_card,
// overview_destroy_card, overview_card_set_corner_radii) are the port's pictures, one panel per monitor

package extension MangoServer {

    // Returns 0 when the target window shares its tag with other windows.
    func wantRestoreFullscreen(_ targetClient: Client) -> Bool {
        for c in clients {
            if c !== targetClient && c.tags == targetClient.tags &&
                c === selectedMonitor.sel && c.mon != nil &&
                c.mon!.pertag.ltidxs[Int(getTagsFirstTagNum(c.tags))] != .scroller &&
                c.mon!.pertag.ltidxs[Int(getTagsFirstTagNum(c.tags))] != .verticalScroller {
                return false
            }
        }

        return true
    }

    func overviewCardSurfaceAdd(_ m: Monitor) {
        if m.ovThumbnails { system.captureOverviewCards(on: m, scale: CGFloat(m.screen.scale)) }   // not in mango: the port's side
    }

    /// Not in mango: card list for the port's overview overlay.
    func overlayCards(_ m: Monitor) -> [OverviewCard] {
        m.ovCards.compactMap { id, frame in
            guard let c = clientByIdAll(id) else { return nil }
            return OverviewCard(id: id, frame: frame, title: c.title.isEmpty ? c.appName : c.title,
                                pid: c.pid, focused: id == m.sel?.id)
        }
    }

    /// Not in mango: client_tile_resize in the overview, where the box is the client's card. With the
    /// port's pictures the window stays under them; without them the card is the window itself.
    func overviewCardTileResize(_ c: Client, _ box: CGRect) -> Bool {
        guard let m = c.mon else { return false }
        m.ovCards[c.id] = box
        if m.ovThumbnails {
            c.animation.overining = false
            return true
        }
        c.tagVisible = true
        return false
    }

    /// Not in mango: overview_layout_card for all cards at once (the port's pictures), the windows
    /// without a card hidden where the cards are the windows, and client_draw_frame's title bar.
    func overviewLayoutCards(_ m: Monitor) {
        if m.ovThumbnails {
            system.updateOverview(overlayCards(m), on: m)
        } else {
            for c in clientsAll where c.mon === m && m.ovCards[c.id] == nil && !c.isunglobal {
                c.tagVisible = false
                clientUpdateVisibility(c)
            }
            updateBorders()
        }
        if config.titleMessageBarHeight > 0 && isOvercircleMode(m) && m.sel.map({ m.ovCards[$0.id] != nil }) == true {
            titleMessageBarUpdateGeometry(m)
        }
    }

    func overviewUpdateJumpLabel(_ c: Client) {
        // not in mango: the client's card stands for its ov_card_tree and c->animation.current
        guard let m = c.mon, let cur = m.ovCards[c.id], m.isoverview, m.isJumpMode, c.jumpChar != nil,
              let label = c.jumpLabelNode else { return }

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

        label.setPosition(lx, ly)   // not in mango: on the screen, as the port has no client scene tree
        if !label.enabled {
            label.setEnabled(true)
            label.raiseToTop()
        }
    }

    /// Not in mango: the port's overlay closes with the cards.
    func overviewCardsClose(_ m: Monitor) {
        if m.ovThumbnails { system.closeOverview(on: m) }
        m.ovThumbnails = false
        m.ovCards = [:]
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

    // Entering overview: saves and disables the real scene_surface tree and builds
    // an independent card tree to display content.
    func overviewBackupSurface(_ c: Client) {
        // not in mango: the real surface tree and the card tree are the port's (overviewCardsShow)

        // In overview every tag window must show its card and must not be disabled
        // by the subtree hiding logic.
        c.isClipToHide = false
        clientUpdateVisibility(c)
    }

    // Saves the window old state when switching from the normal view to overview.
    func overviewBackup(_ c: Client) {
        c.overviewIsfloatingbak = c.isfloating
        c.overviewIsfullscreenbak = c.isfullscreen
        c.overviewIsmaximizescreenbak = c.ismaximizescreen
        c.overviewIsfullscreenbak = c.isfullscreen
        c.animation.tagining = false
        c.animation.tagouted = false
        c.animation.tagouting = false
        c.overviewBackupGeom = c.geom
        c.overviewBackedUp = true   // not in mango: a mango bug, docs/afvigelser.md §6
        c.overviewBackupBw = c.bw
        if c.isfloating {
            c.isfloating = false
        }

        overviewBackupSurface(c)

        if c.isfullscreen || c.ismaximizescreen {
            clientPendingFullscreenState(c, false) // Clears the window fullscreen flag.
            clientPendingMaximizedState(c, false)
        }
        c.bw = c.noBorder ? 0 : CGFloat(config.borderpx)

        // not in mango: client_set_tiled (xdg) and client_sync_layer (the port raises the clients after arrange)
    }

    // Restores window state when switching back from overview to the normal view.
    func overviewRestore(_ c: Client, _ arg: Arg) {
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
        c.isRestoringFromOv = arg.ui & c.tags & TAGMASK == 0 ? true : false

        // Destroys the card tree and restores the real scene_surface tree.
        // not in mango: the card tree is the port's (overviewCardsClose)
        clientUpdateVisibility(c)

        if c.isfloating {
            // XRaiseWindow(display, c->win); // Raise the floating window to the
            // top
            resize(c, c.overviewBackupGeom, ResizeOpts(interact: false))
        } else if c.isfullscreen || c.ismaximizescreen {
            if wantRestoreFullscreen(c) && c.ismaximizescreen {
                clientSetMaximizeScreen(c, true, rearrange: false)
            } else if wantRestoreFullscreen(c) && c.isfullscreen {
                clientSetFullscreen(c, true, rearrange: false)
            } else {
                clientPendingFullscreenState(c, false)
                clientPendingMaximizedState(c, false)
                clientSetFullscreen(c, false, rearrange: false)
            }
        } else {
            if c.isRestoringFromOv {
                c.isRestoringFromOv = false
                resize(c, c.overviewBackupGeom, ResizeOpts(interact: false))
            }
        }

        if c.bw == 0 && !c.isfullscreen { // Windows created while in overview
                                          // mode have no bw record.
            c.bw = c.noBorder ? 0 : CGFloat(config.borderpx)
        }

        // not in mango: client_set_tiled (xdg) and client_sync_layer (the port raises the clients after arrange)
    }
}
