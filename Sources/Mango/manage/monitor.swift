import CoreGraphics

@MainActor public func isSpecialActive(_ m: Monitor?) -> Bool {
    guard let m else { return false }
    return !m.isoverview && (m.tagset[m.seltags] & TAG0_MASK) != 0
}

@MainActor public func getMonCurtag(_ m: Monitor?) -> UInt32 {
    guard let m else { return 0 }
    // special workspace uses slot 0; all-tags is an ordinary multi-tag view
    // and follows its first tag
    if isSpecialActive(m) { return 0 }
    return m.pertag.curtag != 0 ? m.pertag.curtag : 1
}

package extension MangoServer {
    // true if m still has a live (not minimized/destroyed) special window
    func specialHasClients(_ m: Monitor?) -> Bool {
        guard let m else { return false }
        for c in clients {
            if c.mon === m && !c.iskilling && !c.isminimized && (c.tags & TAG0_MASK) != 0 {
                return true
            }
        }
        return false
    }

    func getMonitorActiveTagset(_ m: Monitor?) -> UInt32 {
        guard let m else { return 0 }
        if isSpecialActive(m) {
            let prevSet = m.tagset[m.seltags ^ 1] & TAGMASK
            return prevSet != 0 ? prevSet : (m.pertag.prevtag != 0 ? (1 << (m.pertag.prevtag - 1)) : 1)
        }
        return m.tagset[m.seltags]
    }

    // not in mango: wlr_output_layout_adjacent_output and _farthest_output, from the selected monitor's position
    func monitorFromDirection(_ dir: Int32) -> Monitor? {
        guard let sm = selectedMonitor else { return nil }
        let ref = sm.m, p = ref.origin
        func inDirection(_ b: CGRect, _ dirs: [Int32]) -> Bool {
            dirs.contains { d in
                switch d {
                case LEFT: return b.maxX <= ref.minX
                case RIGHT: return b.minX >= ref.maxX
                case UP: return b.maxY <= ref.minY
                case DOWN: return b.minY >= ref.maxY
                default: return false
                }
            }
        }
        func distance(_ b: CGRect) -> CGFloat {
            let x = min(max(p.x, b.minX), b.maxX - 1), y = min(max(p.y, b.minY), b.maxY - 1)
            return (x - p.x) * (x - p.x) + (y - p.y) * (y - p.y)
        }
        let others = monitors.filter { $0 !== sm }
        if let next = others.filter({ inDirection($0.m, [dir]) }).min(by: { distance($0.m) < distance($1.m) }) {
            return next
        }
        let rest: [Int32] = [LEFT, RIGHT, UP, DOWN].filter { $0 != dir }
        var farthest: Monitor?, maxDistance: CGFloat = 0
        for o in others where inDirection(o.m, rest) {
            let d = distance(o.m)
            if d > maxDistance { maxDistance = d; farthest = o }
        }
        if let farthest { return farthest }
        return sm
    }

    func monitorFromCycle(_ dir: Int32) -> Monitor? {
        guard let sm = selectedMonitor, var i = monitors.firstIndex(where: { $0 === sm }) else { return nil }

        let nmons = monitors.count

        for _ in 0..<nmons {
            // not in mango: the wrap skips the list head, which mango reads as a monitor (a mango bug, docs/afvigelser.md §6)
            if dir == MON_NEXT {
                i = (i + 1) % nmons
            } else {
                i = (i - 1 + nmons) % nmons
            }
            let m = monitors[i]
            if m !== sm { return m }   // not in mango: no disabled outputs
        }
        return nil
    }

    func isScrollerLayout(_ m: Monitor) -> Bool {
        if m.pertag.ltidxs[getMonCurtag(m)] == .scroller { return true }

        if m.pertag.ltidxs[getMonCurtag(m)] == .verticalScroller { return true }

        return false
    }

    func isMonocleLayout(_ m: Monitor) -> Bool {
        if m.pertag.ltidxs[getMonCurtag(m)] == .monocle { return true }

        return false
    }

    func isCentertileLayout(_ m: Monitor) -> Bool {
        if m.pertag.ltidxs[getMonCurtag(m)] == .centerTile { return true }

        return false
    }

    func isOvercircleMode(_ m: Monitor?) -> Bool {
        guard let m else { return false }
        return m.isoverview && m.ovTabLayout && !m.isJumpMode && !m.ovNormalMode
    }

    // not in mango: special_sync_top_layer (macOS has no layer shell)

    // sync the special overlay dim layer to the monitor and view state
    func specialUpdateDim(_ m: Monitor?) {
        guard let m, drawsOverlays else { return }   // not in mango: drawsOverlays is the port's
        // not in mango: the port's dim rect, over the special windows
        system.showSpecialDim(on: m, alpha: isSpecialActive(m) ? config.specialDim : nil,
                              over: Set(clients.filter { $0.mon === m && $0.tags & TAG0_MASK != 0 && !$0.isminimized }.map(\.id)))
    }

    func getTagStatus(_ tag: UInt32, _ m: Monitor) -> UInt32 {
        var status: UInt32 = 0
        for c in clients {
            if c.mon === m && c.tags & (1 << (tag - 1)) & TAGMASK != 0 {
                if c.isurgent {
                    status = 2
                    break
                }
                status = 1
            }
        }
        return status
    }

    func getTagsFirstTagNum(_ sourceTags: UInt32) -> UInt32 {
        var i: UInt32 = 0, tag: UInt32 = 0

        if sourceTags == 0 { return 0 }

        if sourceTags & TAG0_MASK != 0 { return 0 }

        while tag & 1 == 0 && sourceTags != 0 && i < UInt32(config.tagNum) {
            tag = sourceTags >> i
            i += 1
        }

        if i == 1 {
            return 1
        } else if i >= UInt32(config.tagNum) {
            return UInt32(config.tagNum)
        } else {
            return i
        }
    }

    func monitorCopyTagLayout(_ target: Monitor, _ source: Monitor, _ tag: UInt32) {
        if tag >= PERTAG_SLOTS { return }

        let dst = target.pertag
        let src = source.pertag

        dst.nmasters[tag] = src.nmasters[tag]
        dst.mfacts[tag] = src.mfacts[tag]
        dst.noHide[tag] = src.noHide[tag]
        dst.noRenderBorder[tag] = src.noRenderBorder[tag]
        dst.openAsFloating[tag] = src.openAsFloating[tag]
        dst.scrollerDefaultProportion[tag] = src.scrollerDefaultProportion[tag]
        dst.scrollerDefaultProportionSingle[tag] = src.scrollerDefaultProportionSingle[tag]
        dst.scrollerIgnoreProportionSingle[tag] = src.scrollerIgnoreProportionSingle[tag]
        dst.ltidxs[tag] = src.ltidxs[tag]

        /* Layout trees and scroller nodes are monitor-owned and rebuilt on the
         * target after the clients have moved. */
    }

    // Gets the tagmask of the first tag in tags.
    func getTagsFirstTag(_ sourceTags: UInt32) -> UInt32 {
        var i: UInt32 = 0, tag: UInt32 = 0

        if sourceTags == 0 {
            return isSpecialActive(selectedMonitor) ? TAG0_MASK
                : (selectedMonitor != nil
                    ? 1 << (selectedMonitor.pertag.curtag != 0 ? selectedMonitor.pertag.curtag - 1 : 0)
                    : 1)
        }

        if sourceTags & TAG0_MASK != 0 { return TAG0_MASK }

        while tag & 1 == 0 && sourceTags != 0 && i < UInt32(config.tagNum) {
            tag = sourceTags >> i
            i += 1
        }

        if i == 1 {
            return 1
        } else if i >= UInt32(config.tagNum) {
            return 1 << (UInt32(config.tagNum) - 1)
        } else {
            return 1 << (i - 1)
        }
    }

    // not in mango: wlr_output_layout_output_at over the monitors' boxes
    func monitorAtPoint(_ p: CGPoint) -> Monitor? {
        monitors.first { $0.m.contains(p) }
    }

    // not in mango: wlr_output_layout_closest_point over the monitors' boxes
    func getMonitorNearestTo(_ p: CGPoint) -> Monitor? {
        if let m = monitorAtPoint(p) { return m }
        return monitors.min { a, b in a.m.center.distance(to: p) < b.m.center.distance(to: p) }
    }

    // not in mango: the port reports a screen where wlroots reports a wlr_output; no modes, rules or scene to set up
    func handleNewOutput(_ screen: Screen) {
        let m = Monitor(screen: screen, config: config)

        // Adds it to the global monitor list.
        monitors.insert(m, at: 0)

        // Applies the tag rule.
        parseTagrule(m)

        specialUpdateDim(m)

        handleOutputLayoutChange()

        printstatus(.arrangge)
    }

    // not in mango: no fade-out clients, layers, workspaces or scene to tear down
    func handleOutputDestroy(_ m: Monitor) {
        monitors.removeAll { $0 === m }

        monitorClose(m)
        titleMessageBarFinish(m)

        cleanupMonitorScroller(m)   // not in mango: no cleanup_monitor_dwindle, ARC frees the trees
    }

    func setSelectedMonitor(_ m: Monitor?) { selectedMonitor = m }

    func monitorClose(_ m: Monitor) {
        /* update selected_monitor if needed and
         * move closed monitor's clients to the focused one */
        let nmons = monitors.count

        if gestureDriveMon === m {
            gestureDriveActive = false
            gestureDriveMon = nil
        }

        if m.isoverview {
            // not in mango: the closed monitor's overview, not the selected one's (a mango bug, docs/afvigelser.md §6)
            let keep = selectedMonitor
            selectedMonitor = m
            toggleOverview(Arg())
            selectedMonitor = keep
        }

        if nmons == 0 {
            setSelectedMonitor(nil)
        } else if m === selectedMonitor {
            /* don't switch to disabled monitors */
            setSelectedMonitor(monitors.first)
        }

        for c in clients {
            if c.mon === m {
                if selectedMonitor == nil {
                    clientSetGroupMon(c, nil)
                } else {
                    clientSetGroupMon(c, selectedMonitor)
                }
                // record the oldmonname which is used to restore
                if c.oldmonname == nil {
                    clientUpdateOldmonnameRecord(c, m)
                }
            }
        }
        if let sm = selectedMonitor {
            clientFocus(clientFocusTop(sm), true)
            printstatus(.arrangge)
        }
    }

    func handleOutputLayoutChange() {
        /*
         * Called whenever the output layout changes: adding or removing a
         * monitor, changing an output's mode or position, etc. This is where
         * the change officially happens and we update geometry, window
         * positions, focus, and the stored configuration in wlroots'
         * output-manager implementation.
         */
        // not in mango: no disabled outputs, no background or lock rects; the port reports the screens it has

        for m in monitors {
            let oldx = m.m.minX
            let oldy = m.m.minY
            /* Get the effective monitor geometry to use for surfaces */
            m.m = m.screen.frame
            m.w = m.m
            let monPosOffsetx = m.m.minX - oldx
            let monPosOffsety = m.m.minY - oldy

            for c in clients {
                // floating window position auto adjust the change of monitor
                // position
                if c.isfloating && c.mon === m {
                    c.geom.origin.x += monPosOffsetx
                    c.geom.origin.y += monPosOffsety
                    c.floatGeom = c.geom
                    if VISIBLEON(c, m) { resize(c, c.geom, ResizeOpts(interact: true)) }
                }

                // restore window to old monitor
                if let cm = c.mon, cm !== m, c.oldmonname == m.screen.displayID {
                    clientChangeMon(c, m)
                }
            }

            specialUpdateDim(m)

            /* Calculate the effective monitor geometry to use for clients */
            m.w = m.screen.workArea   // not in mango: arrange_layers, macOS's work area
            /* Don't move clients to the left output when plugging monitors */
            arrange(m, false, false)
            /* make sure fullscreen clients have the right size */
            if let c = clientFocusTop(m), c.isfullscreen {
                resize(c, m.m, ResizeOpts(interact: false))
            }

            if selectedMonitor == nil { setSelectedMonitor(m) }
        }

        if let sm = selectedMonitor {
            for c in clients {
                if c.mon == nil { c.mon = sm }
                if c.tags == 0 && !c.isInScratchpad {
                    c.tags = sm.tagset[sm.seltags]
                    setSizePer(sm, c)
                }
            }
            if started { clientFocus(clientFocusTop(sm), true) }   // not in mango: no focus before the port has its windows
        }

        // not in mango: no cursor image, output manager, xdg-output or XWayland to update
    }

    func handleOutputFrame(_ m: Monitor) {
        var needMoreFrames = false

        m.frameSerial &+= 1

        // not in mango: no layers and no fade-out clients to draw (macOS draws them)

        for c in clientsAll {
            needMoreFrames = clientDrawFrame(c) || needMoreFrames
        }

        // not in mango: no frame skipping while clients resize; the port commits nothing

        // not in mango: the port draws every client's border at once
        if bordersDirty {
            bordersDirty = false
            updateBorders()
        }

        // If more frames are needed, ensure the next frame is scheduled.
        if needMoreFrames {
            requestFreshAllMonitors()
        }
    }

    func setgaps(_ oh: Int32, _ ov: Int32, _ ih: Int32, _ iv: Int32) {
        guard let sm = selectedMonitor else { return }
        if isSpecialActive(sm) {
            sm.specialGappoh = max(oh, 0)
            sm.specialGappov = max(ov, 0)
            sm.specialGappih = max(ih, 0)
            sm.specialGappiv = max(iv, 0)
        } else {
            sm.gappoh = max(oh, 0)
            sm.gappov = max(ov, 0)
            sm.gappih = max(ih, 0)
            sm.gappiv = max(iv, 0)
        }
        arrange(sm, false, false)
    }
}
