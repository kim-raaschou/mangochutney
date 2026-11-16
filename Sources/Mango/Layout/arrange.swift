import CoreGraphics

/// mango Layout (layout/layout.h). Not in mango: no predict function; the id is the layout's LayoutKind.
package struct Layout {
    package let symbol: String
    package let arrange: @MainActor (MangoServer, Monitor) -> Void
    package let name: String
    package let id: LayoutKind
}

@MainActor package let overviewlayout = Layout(symbol: "󰃇", arrange: { $0.overview($1) }, name: "overview", id: .grid)

@MainActor package let layouts: [Layout] = [
    // At least two are required; fewer than two cannot be removed.
    /* symbol     arrange function   name */
    Layout(symbol: "T", arrange: { $0.tile($1) }, name: "tile", id: .tile), // Tiled layout
    Layout(symbol: "S", arrange: { $0.scroller($1) }, name: "scroller", id: .scroller), // Scroll layout
    Layout(symbol: "G", arrange: { $0.grid($1) }, name: "grid", id: .grid), // Grid layout
    Layout(symbol: "M", arrange: { $0.monocle($1) }, name: "monocle", id: .monocle), // Single layout
    Layout(symbol: "K", arrange: { $0.deck($1) }, name: "deck", id: .deck), // Card layout
    Layout(symbol: "CT", arrange: { $0.centerTile($1) }, name: "center_tile", id: .centerTile), // Centered layout
    Layout(symbol: "RT", arrange: { $0.rightTile($1) }, name: "right_tile", id: .rightTile), // Right layout
    Layout(symbol: "VS", arrange: { $0.verticalScroller($1) }, name: "vertical_scroller", id: .verticalScroller), // Vertical scroll layout
    Layout(symbol: "VT", arrange: { $0.verticalTile($1) }, name: "vertical_tile", id: .verticalTile), // Vertical tiled layout
    Layout(symbol: "VG", arrange: { $0.verticalGrid($1) }, name: "vertical_grid", id: .verticalGrid), // Vertical grid layout
    Layout(symbol: "VK", arrange: { $0.verticalDeck($1) }, name: "vertical_deck", id: .verticalDeck), // Vertical card layout
    Layout(symbol: "DW", arrange: { $0.dwindle($1) }, name: "dwindle", id: .dwindle),
    Layout(symbol: "F", arrange: { $0.fair($1) }, name: "fair", id: .fair),
    Layout(symbol: "VF", arrange: { $0.verticalFair($1) }, name: "vertical_fair", id: .verticalFair),
]

package extension MangoServer {
    func specialKeepBgClient(_ m: Monitor, _ c: Client) -> Bool {
        isSpecialActive(m) && !c.isminimized
            && ((m.pertag.prevtag > 0 && c.tags & (1 << (m.pertag.prevtag - 1)) != 0)
                || c.tags & (m.tagset[m.seltags ^ 1] & ~TAG0_MASK) != 0)
    }

    func preCalculateBeforeArrange(_ m: Monitor, _ wantAnimation: Bool, _ fromView: Bool, _ onlyCalculate: Bool) {
        var totalStackWeight: CGFloat = 0
        var totalMasterWeight: CGFloat = 0
        var totalRightStackWeight: CGFloat = 0
        var totalLeftStackWeight: CGFloat = 0
        var i = 0
        var nmasters = 0
        var stackIndex = 0
        var masterNum = 0
        var stackNum = 0

        m.visibleClients = 0
        m.visibleTilingClients = 0
        m.visibleScrollTilingClients = 0
        m.visibleFakeTilingClients = 0
        m.hideClients = 0

        let tag = getMonCurtag(m)
        let st = m.pertag.scrollerState[tag]

        let curLayout = m.pertag.ltidxs[tag]
        if curLayout == .scroller || curLayout == .verticalScroller {
            updateScrollerState(m)
        }

        for c in clients {
            if fromView && (c.isglobal || c.isunglobal) {
                setSizePer(m, c, resetProportion: true)
            }

            // not in mango: client_check_tab_node_visible; the port draws the bars from the state

            if c.mon === m && (c.isglobal || c.isunglobal) {
                c.tags = m.tagset[m.seltags]
            }

            if fromView && m.sel == nil && c.isglobal && VISIBLEON(c, m) {
                clientFocus(c, true)
            }

            if c.isminimized {
                m.hideClients += 1
            }

            if VISIBLEON(c, m) {
                if fromView && !clientOnlyInOneTag(c) {
                    setSizePer(m, c, resetProportion: true)
                }

                if !c.isunglobal { m.visibleClients += 1 }

                if ISTILED(c) {
                    m.visibleTilingClients += 1

                    /* Updates the visible scroll-client count. */
                    if let st {
                        let n = findScrollerNode(st, c)
                        if let n, n.prevInStack == nil { /* Is a stack head. */
                            m.visibleScrollTilingClients += 1
                        }
                    } else if ISSCROLLTILED(c) {
                        m.visibleScrollTilingClients += 1
                    }
                }

                if ISFAKETILED(c) {
                    m.visibleFakeTilingClients += 1
                }
            }
        }

        nmasters = Int(m.pertag.nmasters[getMonCurtag(m)])

        var fake: [Client] = []   // not in mango: reset_size_per_mon's VISIBLEON and ISFAKETILED clients
        for c in clients {
            if c.iskilling { continue }

            if c.mon === m {
                if VISIBLEON(c, m) {
                    if ISFAKETILED(c) {
                        fake.append(c)
                        if c.masterSizeWeight <= 0.0 { c.masterSizeWeight = 1.0 }
                        if c.stackSizeWeight <= 0.0 { c.stackSizeWeight = 1.0 }

                        if i < nmasters {
                            masterNum += 1
                            totalMasterWeight += c.masterSizeWeight
                        } else {
                            stackNum += 1
                            totalStackWeight += c.stackSizeWeight
                            stackIndex = i - nmasters
                            if (stackIndex % 2 == 1) != (m.visibleTilingClients % 2 == 0) {
                                c.isleftstack = false
                                totalRightStackWeight += c.stackSizeWeight
                            } else {
                                c.isleftstack = true
                                totalLeftStackWeight += c.stackSizeWeight
                            }
                        }
                        i += 1
                    }

                    // not in mango: until the dispatchers are mango's (trin 6) a floating client's
                    // geom is its float_geom here, kept on the display by the port
                    if c.isfloating || SCRATCHPAD_SHOWN(c) {
                        c.geom = system.keepOnDisplay(clientSetBounds(c, c.floatGeom, sceneGeometry), m)
                    }

                    // not in mango: the unmanaged global client and the tile being dragged stay where they are
                    if !onlyCalculate && !c.isunglobal && dragTile?.client !== c {
                        setArrangeVisible(m, c, wantAnimation)
                    }
                } else if specialKeepBgClient(m, c) {
                    c.tagVisible = true
                    clientUpdateVisibility(c)
                    c.animation.running = false
                    c.animation.tagining = false
                    c.animation.tagouting = false
                } else if !onlyCalculate && c !== grab?.client {
                    setArrangeHidden(m, c, wantAnimation)
                }

                // not in mango: client_sync_layer; the port raises the clients at the end of arrange
            }

            if !onlyCalculate && c.mon === m && c.ismaximizescreen && !c.animation.tagouted
                && !c.animation.tagouting && VISIBLEON(c, m) {
                resetMaximizescreenSize(c)
            }
        }

        resetSizePerMon(m, fake, totalLeftStackWeight: totalLeftStackWeight, totalRightStackWeight: totalRightStackWeight,
                        totalStackWeight: totalStackWeight, totalMasterWeight: totalMasterWeight,
                        masterNum: masterNum, stackNum: stackNum)

        specialUpdateDim(m)
    }

    func specialHandleEmptyView(_ m: Monitor, _ fromView: Bool) -> Bool {
        if !isSpecialActive(m) {
            m.specialEmptyView = false
            return false
        }
        if specialHasClients(m) {
            m.specialEmptyView = false
            return false
        }
        if fromView {
            m.specialEmptyView = true
            return false
        }
        if !m.specialEmptyView {
            toggleSpecialTagMon(m)
            return true
        }
        return false
    }

    func arrange(_ m: Monitor, _ wantAnimation: Bool, _ fromView: Bool) {
        guard started else { return }   // not in mango: no arrange before the port has its windows

        // not in mango: the overview before pre_calculate_before_arrange; its cards are the port's pictures
        if m.isoverview {
            m.hideClients = 0
            for c in clients where c.isminimized { m.hideClients += 1 }
            overviewlayout.arrange(self, m)
            return
        }

        if m.sel == nil {
            m.sel = clientFocusTop(m)?.id
        }

        if specialHandleEmptyView(m, fromView) { return }

        preCalculateBeforeArrange(m, wantAnimation, fromView, false)
        /* Must run after pre_calculate: global windows get their tags rewritten
         * there. */
        tabSyncMonitor(m)

        let isTag0 = isSpecialActive(m)
        // not in mango: special_sync_top_layer (macOS has no layer shell)
        let savedOh = m.gappoh, savedOv = m.gappov
        let savedIh = m.gappih, savedIv = m.gappiv

        if isTag0 {
            m.gappoh = m.specialGappoh
            m.gappov = m.specialGappov
            m.gappih = m.specialGappih
            m.gappiv = m.specialGappiv
        }

        layouts.first { $0.id == m.pertag.ltidxs[getMonCurtag(m)] }!.arrange(self, m)   // not in mango: ltidxs holds the id

        if isTag0 {
            m.gappoh = savedOh
            m.gappov = savedOv
            m.gappih = savedIh
            m.gappiv = savedIv
        }

        // not in mango: client_sync_layer's layers, raised by the port
        clientRaiseLayers(m)
        updateBorders()

        // gather after layout/animation setup so tag-switch animations still play.
        if config.tagGather {
            tagGatherApply(m)
        }

        // not in mango: pointer_process_motion(0, …) and check_idle_inhibitor (macOS moves the pointer's focus)

        printstatus(.arrangge)
    }


    /// Not in mango: client_sync_layer's scene layers; the port raises the fullscreen, maximized,
    /// scratchpad and overlay clients, the selected one last.
    func clientRaiseLayers(_ m: Monitor) {
        var raise: [Client] = []
        for c in visibleClients(m) where !c.isunglobal && dragTile?.client !== c {
            if SCRATCHPAD_SHOWN(c) || c.isfullscreen || c.ismaximizescreen || c.isoverlay { raise.append(c) }
        }
        if m.layout.isMonocleLike, let s = m.sel.flatMap({ clientByIdAll($0) }), !s.isfloating { raise.insert(s, at: 0) }

        let sel = m.sel.flatMap { clientByIdAll($0) }
        for c in raise where c !== sel {
            if let sel, sel.pid == c.pid { continue }
            system.raise(c)
        }
        if let sel, raise.contains(where: { $0 === sel }) { system.raise(sel) }
    }
}
