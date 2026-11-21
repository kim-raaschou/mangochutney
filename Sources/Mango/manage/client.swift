import Foundation
import CoreGraphics

package let UP: Int32 = 0, DOWN: Int32 = 1, LEFT: Int32 = 2, RIGHT: Int32 = 3, UNDIR: Int32 = 4, ALLDIR: Int32 = 5 /* smartmovewin */

package extension MangoServer {
    func getClientTagIdx(_ c: Client?) -> UInt32 {
        guard let c, c.tags & TAG0_MASK == 0 else { return 0 }
        return getTagsFirstTagNum(c.tags)
    }

    func clientGetClip(_ c: Client) -> CGRect {
        // not in mango: the xdg geometry's offset (clip->x, clip->y) is 0
        CGRect(x: 0, y: 0, width: c.geom.width - 2 * c.bw, height: c.geom.height - 2 * c.bw)
    }

    func clientIsFloatType(_ c: Client) -> Bool { c.platform.isFloatType }
    func clientSetSizeBound(_ c: Client) {
        let state = system.clientSizeHints(c)   // not in mango: the port's toplevel->current min and max size

        if c.geom.width - 2 * c.bw < state.minWidth && state.minWidth > 0 {
            c.geom.size.width = state.minWidth + 2 * c.bw
        }
        if c.geom.height - 2 * c.bw < state.minHeight && state.minHeight > 0 {
            c.geom.size.height = state.minHeight + 2 * c.bw
        }
        if c.geom.width - 2 * c.bw > state.maxWidth && state.maxWidth > 0 {
            c.geom.size.width = state.maxWidth + 2 * c.bw
        }
        if c.geom.height - 2 * c.bw > state.maxHeight && state.maxHeight > 0 {
            c.geom.size.height = state.maxHeight + 2 * c.bw
        }
    }

    func checkHitNoBorder(_ c: Client) -> Bool {
        guard let m = c.mon, c.tags != 0 else { return false }
        let isoverview = m.isoverview
        var hitNoBorder = false
        if !renderBorder { hitNoBorder = true }
        if !isoverview && m.pertag.noRenderBorder[getClientTagIdx(c)] { hitNoBorder = true }
        if config.noBorderWhenSingle
            && ((ISSCROLLTILED(c) && m.visibleFakeTilingClients == 1) || m.visibleClients == 1) {
            hitNoBorder = true
        }
        if config.monocleNoBorder && ISFAKETILED(c) && !isoverview && isMonocleLayout(m) { hitNoBorder = true }
        return hitNoBorder
    }

    func getClientByIdOrTitle(_ argId: String?, _ argTitle: String?) -> Client? {
        var targetClient: Client?
        var argId = argId, argTitle = argTitle
        for c in clients {
            if !config.scratchpadCrossMonitor && c.mon !== selectedMonitor {
                continue
            }

            // not in mango: no swallowing (c->swallowing)
            let appid = c.appid
            let title = c.title

            if let a = argId, a.hasPrefix("none") {
                argId = nil
            }

            if let t = argTitle, t.hasPrefix("none") {
                argTitle = nil
            }

            // not in mango: the app's name matches the id too (macOS app ids are bundle ids)
            func idMatch(_ id: String) -> Bool {
                regexMatch(id, appid)
                    || regexMatch(id, c.appName)
            }
            func titleMatch(_ t: String) -> Bool { regexMatch(t, title) }

            if (argTitle.map(titleMatch) == true && argId == nil) ||
                (argId.map(idMatch) == true && argTitle == nil) ||
                (argId.map(idMatch) == true && argTitle.map(titleMatch) == true) {
                targetClient = c
                break
            }
        }
        return targetClient
    }

    func clientCenterGeometry(_ c: Client?, _ tm: Monitor?, _ geom: CGRect, _ offsetx: Int = 0, _ offsety: Int = 0) -> CGRect {
        var tempbox = geom
        var offset: CGFloat = 0
        var len: CGFloat = 0
        guard let m = tm ?? selectedMonitor else { return geom }

        let cbw: CGFloat = c.map { checkHitNoBorder($0) ? $0.bw : 0 } ?? 0

        if !(c?.noForceCenter ?? false) {
            tempbox.origin.x = m.w.minX + ((m.w.width - geom.width) / 2).rounded(.towardZero)
            tempbox.origin.y = m.w.minY + ((m.w.height - geom.height) / 2).rounded(.towardZero)
        } else {
            tempbox.origin = geom.origin
        }

        tempbox.size = geom.size

        if offsetx != 0 {
            len = ((m.w.width - tempbox.width - 2 * CGFloat(m.gappoh)) / 2).rounded(.towardZero)
            offset = (len * (CGFloat(offsetx) / 100.0)).rounded(.towardZero)
            tempbox.origin.x += offset

            // Keeps the window inside the screen.
            if tempbox.minX < m.m.minX {
                tempbox.origin.x = m.m.minX - cbw
            }
            if tempbox.minX + tempbox.width > m.m.minX + m.m.width {
                tempbox.origin.x = m.m.minX + m.m.width - tempbox.width + cbw
            }
        }
        if offsety != 0 {
            len = ((m.w.height - tempbox.height - 2 * CGFloat(m.gappov)) / 2).rounded(.towardZero)
            offset = (len * (CGFloat(offsety) / 100.0)).rounded(.towardZero)
            tempbox.origin.y += offset

            // Keeps the window inside the screen.
            if tempbox.minY < m.m.minY {
                tempbox.origin.y = m.m.minY - cbw
            }
            if tempbox.minY + tempbox.height > m.m.minY + m.m.height {
                tempbox.origin.y = m.m.minY + m.m.height - tempbox.height + cbw
            }
        }

        return tempbox
    }

    func centerTiledSelect(_ m: Monitor) -> Client? {
        var targetC: Client?
        var miniDistance: Int64 = -1
        for c in clients {
            if VISIBLEON(c, m) && ISSCROLLTILED(c) && !c.isfloating {   // not in mango: every Client is mapped and managed
                let dirx = Int64(c.geom.minX) + Int64(c.geom.width) / 2 - (Int64(m.w.minX) + Int64(m.w.width) / 2)
                let diry = Int64(c.geom.minY) + Int64(c.geom.height) / 2 - (Int64(m.w.minY) + Int64(m.w.height) / 2)
                let distance = dirx * dirx + diry * diry
                if distance < miniDistance || miniDistance == -1 {
                    miniDistance = distance
                    targetC = c
                }
            }
        }
        return targetC
    }

    func findClientByDirection(_ tc: Client, _ arg: Arg, _ findfloating: Bool) -> Client? {
        let t = directionGeom(tc)
        let tl = Int64(t.minX.rounded()), tr = Int64(t.maxX.rounded()), tt = Int64(t.minY.rounded()), tb = Int64(t.maxY.rounded())
        let tcx = tl + (tr - tl) / 2, tcy = tt + (tb - tt) / 2
        var best: Client?, bestSame: Client?
        var distance = Int64.max, sameDistance = Int64.max, bestCenter = Int64.max, bestSameCenter = Int64.max
        for step in 0..<2 {
            if step == 1 && best != nil { break }
            for c in clients {
                guard let cm = c.mon, c !== tc else { continue }
                if !findfloating && c.isfloating { continue }
                if !VISIBLEON(c, cm) || c.isunglobal { continue }
                if !config.focusCrossMonitor && cm !== tc.mon { continue }
                if c.tags & cm.tagset[cm.seltags] == 0 && !c.isglobal { continue }
                let g = directionGeom(c)
                let l = Int64(g.minX.rounded()), r = Int64(g.maxX.rounded()), tp = Int64(g.minY.rounded()), b = Int64(g.maxY.rounded())
                let cx = l + (r - l) / 2, cy = tp + (b - tp) / 2
                var main: Int64 = 0, orth: Int64 = 0
                switch arg.i {
                case LEFT:
                    guard cx < tcx || (cx == tcx && l < tl) else { continue }
                    main = tl - r; orth = b < tt ? tt - b : (tp > tb ? tp - tb : 0)
                case RIGHT:
                    guard cx > tcx || (cx == tcx && l > tl) else { continue }
                    main = l - tr; orth = b < tt ? tt - b : (tp > tb ? tp - tb : 0)
                case UP:
                    guard cy < tcy || (cy == tcy && tp < tt) else { continue }
                    main = tt - b; orth = r < tl ? tl - r : (l > tr ? l - tr : 0)
                case DOWN:
                    guard cy > tcy || (cy == tcy && tp > tt) else { continue }
                    main = tp - tb; orth = r < tl ? tl - r : (l > tr ? l - tr : 0)
                default:
                    continue
                }
                let overlap = arg.i == LEFT || arg.i == RIGHT ? (b >= tt && tp <= tb) : (r >= tl && l <= tr)
                if config.focusdirOnlyZoneOverlap && !overlap { continue }
                if step == 0 {
                    guard let m = tc.mon, cm === m else { continue }
                    if !m.isoverview && !clientIsInSameStack(tc, c, nil) { continue }
                }
                var penalty: Int64 = 0
                if main < 0 { penalty = 10_000_000_000; main = -main }
                let d = penalty + main * main + orth * orth
                let center = abs(arg.i == UP || arg.i == DOWN ? cx - tcx : cy - tcy)
                if d < distance || (d == distance && center < bestCenter) {
                    distance = d; bestCenter = center; best = c
                }
                if cm === tc.mon && (d < sameDistance || (d == sameDistance && center < bestSameCenter)) {
                    sameDistance = d; bestSameCenter = center; bestSame = c
                }
            }
        }
        return bestSame ?? best
    }

    /// Not in mango: c->geom, or the card in the overview's pictures.
    func directionGeom(_ c: Client) -> CGRect {
        if let m = c.mon, m.isoverview, let card = m.ovCards[c.id] { return card }
        return c.geom
    }

    func directionSelect(_ arg: Arg) -> Client? {
        guard let tc = arg.tc ?? selectedMonitor.sel.flatMap({ clientByIdAll($0) }) else { return nil }

        if (tc.isfullscreen || tc.ismaximizescreen) && (!isScrollerLayout(selectedMonitor) || tc.isfloating) {
            return nil
        }

        return findClientByDirection(tc, arg, true)
    }

    package func clientFocusTop(_ m: Monitor?) -> Client? {
        guard let m else { return nil }
        for id in focusStack {
            if let c = clientByIdAll(id), !c.iskilling, !c.isunglobal, VISIBLEON(c, m) { return c }
        }
        return nil
    }

    func getNextStackClient(_ c: Client, reverse: Bool) -> Client? {
        guard let m = c.mon, let i = clients.firstIndex(where: { $0 === c }) else { return nil }
        let n = clients.count
        for k in 1..<max(n, 1) {
            let x = clients[reverse ? (i - k + n) % n : (i + k) % n]
            if x.isunglobal { continue }
            if x !== c, x.mon != nil, VISIBLEON(x, m) { return x }
        }
        return nil
    }

    package func getBorderColor(_ c: Client) -> RGBA {
        let isFocused = c.mon === selectedMonitor && selectedMonitor.sel == c.id
        if c.mon !== selectedMonitor { return config.bordercolor }
        if c.isurgent { return config.urgentcolor }
        guard isFocused else { return config.bordercolor }
        if c.isInScratchpad { return config.scratchpadcolor }
        if c.isglobal { return config.globalcolor }
        if c.isoverlay { return config.overlaycolor }
        if c.ismaximizescreen { return config.maximizescreencolor }
        return config.focuscolor
    }

    func clientOnlyInOneTag(_ c: Client) -> Bool {
        if c.tags & TAG0_MASK != 0 { return true }
        return (c.tags & TAGMASK).nonzeroBitCount == 1
    }

    func clientIsInSameStack(_ sc: Client, _ tc: Client, _ fc: Client?) -> Bool {
        guard let m = sc.mon else { return false }
        let layout = m.pertag.ltidxs[getClientTagIdx(sc)]
        if !layout.isScroller && tc.mon !== selectedMonitor && (tc.isfullscreen || tc.ismaximizescreen) { return true }
        switch layout {
        case .monocle:
            return !tc.isTabHidden
        case .scroller, .verticalScroller:
            let sourceStackHead = scrollGetStackHeadClient(sc)
            let targetStackHead = scrollGetStackHeadClient(tc)
            let fcHead = fc.map { scrollGetStackHeadClient($0) }

            if fc != nil && fcHead === sourceStackHead { return false }
            if sourceStackHead === targetStackHead {
                return true
            } else {
                return false
            }
        case .tile, .verticalTile, .deck, .verticalDeck, .rightTile:
            if tc.tabPrev != nil || tc.tabNext != nil { return !tc.isTabHidden }
            if tc.ismaster != sc.ismaster { return false }
            if let fc, fc.ismaster == sc.ismaster { return false }
            return true
        case .centerTile:
            if tc.ismaster != sc.ismaster { return false }
            if let fc, fc.ismaster == sc.ismaster { return false }
            return directionGeom(sc).minX == directionGeom(tc).minX
        default:
            return false
        }
    }

    private func dwindleNodeDepth(_ node: DwindleNode?) -> Int32 {
        var depth: Int32 = 0
        var n = node
        while let x = n, x.parent != nil {
            depth += 1
            n = x.parent
        }
        return depth
    }

    private func dwindleNodeLca(_ a: DwindleNode?, _ b: DwindleNode?) -> DwindleNode? {
        guard var a, var b else { return nil }

        var da = dwindleNodeDepth(a)
        var db = dwindleNodeDepth(b)
        while da > db, let p = a.parent {
            a = p
            da -= 1
        }
        while db > da, let p = b.parent {
            b = p
            db -= 1
        }
        while a !== b {
            guard let pa = a.parent, let pb = b.parent else { return nil }
            a = pa
            b = pb
        }
        return a
    }

    /* Dwindle keeps a binary split tree. The focus memory may only kick in when the
     * target `sc` lives in the branch that is directly attached to `fc`, i.e. the
     * sibling subtree created when `fc` itself was split. If the target sits in a
     * higher ancestor branch, it is not part of fc's own subtree and the move is
     * left untouched. Within that directly attached branch the most recently
     * focused client wins, so the focus order is remembered for any tree shape. */
    func dwindleFocusBlockRoot(_ root: DwindleNode?, _ sc: Client, _ fc: Client?) -> DwindleNode? {
        let scLeaf = dwindleFindLeaf(root, sc)
        let fcLeaf = fc.flatMap { dwindleFindLeaf(root, $0) }
        guard let scLeaf, let fcLeaf, scLeaf !== fcLeaf, fcLeaf.parent != nil else { return nil }

        /* sc must be inside the branch that is directly attached to fc, so the
         * lca of both leaves has to be fc's own parent. Anything above it is an
         * ancestor branch of fc and must not use the focus memory. */
        guard let lca = dwindleNodeLca(scLeaf, fcLeaf), lca === fcLeaf.parent else { return nil }

        guard let branch = lca.first === fcLeaf ? lca.second : lca.first, branch.isSplit else { return nil }
        return branch
    }

    func dwindleFocusBlockHasClient(_ node: DwindleNode?, _ c: Client) -> Bool {
        guard let node else { return false }
        if !node.isSplit { return node.client === c }
        return dwindleFocusBlockHasClient(node.first, c) || dwindleFocusBlockHasClient(node.second, c)
    }

    func getFocusedStackClient(_ sc: Client?, _ customFocusClient: Client?) -> Client? {
        guard let sc, !sc.isfloating, let fc = customFocusClient ?? focused, !fc.isfloating, let m = sc.mon else { return sc }
        var isDwindle = false
        var dwindleBlock: DwindleNode?
        let tag = getClientTagIdx(sc)
        if m.pertag.ltidxs[tag] == .dwindle {
            isDwindle = true
            dwindleBlock = dwindleFocusBlockRoot(m.pertag.dwindleRoot[tag], sc, fc)
        }
        for id in focusStack {
            guard let tc = clientByIdAll(id), !tc.iskilling, !tc.isunglobal, VISIBLEON(tc, m), tc !== fc else { continue }
            if isDwindle {
                if dwindleBlock != nil && dwindleFocusBlockHasClient(dwindleBlock, tc) { return tc }
                continue
            }
            if clientIsInSameStack(sc, tc, fc) { return tc }
        }
        return sc
    }

    func applyRuleProperties(_ c: Client, _ r: ConfigWinRule) {
        if let v = r.noFocus { c.noFocus = v }
        if let v = r.confinePointer { c.confinePointer = v }
        if let v = r.noForceCenter { c.noForceCenter = v }
        if let v = r.isfloating { c.isfloating = v }
        if let v = r.isfullscreen { c.isfullscreen = v }
        if let v = r.isfakefullscreen { c.isfakefullscreen = v }
        if let v = r.noBorder { c.noBorder = v }
        if let v = r.noAnimation { c.noAnimation = v }
        if let v = r.noSizeHint { c.noSizeHint = v }
        if let v = r.isopensilent { c.isopensilent = v }
        if let v = r.istagsilent { c.istagsilent = v }
        if let v = r.isnamedscratchpad { c.isnamedscratchpad = v }
        if let v = r.isglobal { c.isglobal = v }
        if let v = r.isoverlay { c.isoverlay = v }
        if let v = r.ignoreMinimize { c.ignoreMinimize = v }
        if let v = r.isUnmanagedGlobal { c.isunglobal = v }
        if let v = r.scrollerProportion, v > 0 { c.scrollerProportion = Float(v); c.iscustomScrollerProportion = true }
        if let v = r.scrollerProportionSingle, v > 0 { c.scrollerProportionSingle = Float(v); c.iscustomScrollerProportionSingle = true }
        if let v = r.animationTypeOpen { c.animationTypeOpen = v }
        // not in mango: the rule fields MangoCompat lists as impossible on macOS are not applied
    }

    func setFloatMalposition(_ tc: Client) {
        guard let m = tc.mon else { return }
        // not in mango: a fullscreen or maximized client keeps its float_geom (a mango bug, docs/afvigelser.md §6)
        if ISFULLSCREEN(tc) { return }
        let w = m.w
        let offset = min(w.width / 20, w.height / 20).rounded(.towardZero)
        var x = tc.geom.minX, y = tc.geom.minY
        var xreverse: CGFloat = 1, yreverse: CGFloat = 1
        for c in clients where c.isfloating && c !== tc && VISIBLEON(c, m)
            && abs(x - c.geom.minX) < offset && abs(y - c.geom.minY) < offset {
            x = c.geom.minX + offset * xreverse
            y = c.geom.minY + offset * yreverse
            if x < w.minX { x += offset; xreverse = 1 }
            if y < w.minY { y += offset; yreverse = 1 }
            if x + tc.geom.width > w.maxX { x -= offset; xreverse = -1 }
            if y + tc.geom.height > w.maxY { y -= offset; yreverse = -1 }
        }
        tc.geom.origin = CGPoint(x: x, y: y)
        tc.floatGeom.origin = tc.geom.origin
    }

    package func clientResetMonTags(_ c: Client, _ mon: Monitor, _ newtags: UInt32) {
        if newtags == 0 && !mon.isoverview {
            c.tags = mon.tagset[mon.seltags]
        } else if newtags == 0 && mon.isoverview {
            c.tags = mon.ovbkCurrentTagset
        } else if newtags != 0 {
            let masked = (newtags & TAG0_MASK) != 0 ? TAG0_MASK : (newtags & TAGMASK)
            c.tags = masked != 0 ? masked : mon.tagset[mon.seltags]
        } else {
            c.tags = mon.tagset[mon.seltags]
        }
    }

    package func checkMatchTagFloatingRule(_ c: Client, _ mon: Monitor) {
        if c.tags != 0 && !c.isfloating, mon.pertag.openAsFloating[getTagsFirstTagNum(c.tags)] {
            c.isfloating = true
        }
    }

    // not in mango: `mapped` false gives the rules alone, without their action, for a window the port
    // found mapped already (at start, back after sleep) and places itself; its once rules are spent
    @discardableResult
    package func clientSetRules(_ c: Client, mapped: Bool = true) -> (mon: Monitor, tags: UInt32) {
        var newtags: UInt32 = 0

        let parent = system.clientGetParent(c)

        var mon: Monitor = parent?.mon ?? selectedMonitor

        c.isfloating = clientIsFloatType(c) || parent != nil

        for i in config.windowRules.indices {
            let r = config.windowRules[i]
            guard r.isWindowRuleMatches(appId: c.bundleId, appName: c.appName, title: c.title) else { continue }
            if r.once && r.isOnceApplied { continue }
            if r.once { config.windowRules[i].isOnceApplied = true }

            applyRuleProperties(c, r)

            // // set tags
            if let t = r.tags, t != 0 {
                newtags |= t
            } else if let parent {
                newtags = parent.tags
            }

            if let spec = r.monitor {
                for m in monitors where spec.matchMonitorSpec(m.screen) { mon = m }
            }

            if c.isnamedscratchpad { c.isfloating = true }

            let full = mon.m
            if let w = r.width, w > 1 { c.floatGeom.size.width = CGFloat(w) } else if let w = r.width, w > 0 { c.floatGeom.size.width = (full.width * CGFloat(w)).rounded() }
            if let h = r.height, h > 1 { c.floatGeom.size.height = CGFloat(h) } else if let h = r.height, h > 0 { c.floatGeom.size.height = (full.height * CGFloat(h)).rounded() }
            if (r.width ?? 0) > 0 || (r.height ?? 0) > 0 { c.iscustomsize = true }

            let ox = r.offsetX ?? 0, oy = r.offsetY ?? 0
            if ox != 0 || oy != 0 {
                c.iscustompos = true
                c.floatGeom = clientCenterGeometry(c, mon, c.floatGeom, ox, oy)
                c.geom = c.floatGeom
            }
            if c.isfloating {
                c.geom = c.floatGeom.width > 0 && c.floatGeom.height > 0 ? c.floatGeom : c.geom
            }
        }

        // not in mango: no requested fullscreen_output (no xdg request)

        if newtags == 0, let parent, parent.tags & TAG0_MASK != 0 {
            newtags = TAG0_MASK
        } else if newtags == 0 && isSpecialActive(mon) {
            newtags = TAG0_MASK
        }

        setSizePer(mon, c)

        // if no geom rule hit and is normal winodw, use the center pos and record
        // the hit size
        if !c.iscustompos {
            let pendingCenterGeom = c.iscustomsize ? c.floatGeom : c.geom
            c.floatGeom = clientCenterGeometry(c, mon, pendingCenterGeom, 0, 0)
            c.geom = c.floatGeom
        } else if !c.iscustomsize {
            c.floatGeom = c.geom
        }

        /*-----------------------apply rule action-------------------------*/

        if !mapped { return (mon, newtags) }

        let fullscreenStateBackup = c.isfullscreen   // not in mango: no client_wants_fullscreen (no xdg request)

        let shouldInitGetFocus = !c.isopensilent
            && (!c.istagsilent || newtags == 0 || newtags & mon.tagset[mon.seltags] != 0)
        if !shouldInitGetFocus {
            focusStack.removeAll { $0 == c.id }
            focusStack.append(c.id)
        }

        clientSetMonitor(c, mon, newtags, focus: shouldInitGetFocus)
        // not in mango: client_reparent_group (no macOS part)

        if !c.isfloating {
            c.oldStackInnerPer = c.stackInnerPer
            c.oldMasterInnerPer = c.masterInnerPer
        }

        if let cm = c.mon, !(cm === selectedMonitor && c.tags & cm.tagset[cm.seltags] != 0),
           !c.isopensilent, !c.istagsilent {
            c.animation.tagFromRule = true
            clientViewOnMonitor(Arg(ui: c.tags), true, cm, true)
        }

        clientSetFullscreen(c, fullscreenStateBackup, rearrange: true)

        if c.isfakefullscreen {
            clientSetFakeFullscreen(c, true)
        }

        if let cm = c.mon, !c.isfloating {
            for fc in clients where fc !== c && c.tags & fc.tags != 0 && VISIBLEON(fc, cm)
                && ISFULLSCREEN(fc) {
                clearFullscreenFlag(fc)
                arrange(cm, false, false)
            }
        }

        if c.isfloating && !c.iscustompos && !c.isnamedscratchpad {
            clients.removeAll { $0 === c }
            clients.append(c)
            setFloatMalposition(c)
        }

        if c.isnamedscratchpad { applyNamedScratchpad(c) }
        return (mon, newtags)
    }

    func applyWindowSnap(_ c: Client) {
        func inner(_ x: Client) -> CGRect {
            let xbw: CGFloat = !renderBorder || x.fakeNoBorder ? x.bw : 0
            return x.geom.insetBy(dx: xbw, dy: xbw)
        }

        guard let m = c.mon, !c.iskilling else { return }

        if !c.isfloating || !config.enableFloatingSnap { return }

        // not in mango: the snap distances are worked out apart (FloatingSnap), as apply_window_snap does
        let others = clients.filter { $0.isfloating && !$0.iskilling && VISIBLEON($0, m) }.map(inner)
        let from = inner(c)
        let to = FloatingSnap.snapped(from, others: others, monitor: m.m, workArea: m.w,
                                      distance: CGFloat(config.snapDistance))
        c.geom.origin.x += to.minX - from.minX
        c.geom.origin.y += to.minY - from.minY

        c.floatGeom = c.geom
        resize(c, c.geom, ResizeOpts(interact: false))
    }

    package func clientInsertTilingOrder(_ c: Client) {
        var atClient: Client?

        if config.newIsMaster && selectedMonitor != nil && !isScrollerLayout(selectedMonitor) {
            clients.insert(c, at: 0)
        } else if selectedMonitor != nil && isScrollerLayout(selectedMonitor)
                    && selectedMonitor.visibleScrollTilingClients > 0 {
            if let sel = selectedMonitor.sel.flatMap({ clientByIdAll($0) }), ISSCROLLTILED(sel),
               VISIBLEON(sel, selectedMonitor) {
                atClient = scrollGetStackTailClient(sel)
            } else {
                atClient = centerTiledSelect(selectedMonitor)
            }

            if let atClient, let i = clients.firstIndex(where: { $0 === atClient }) {
                clients.insert(c, at: i + 1)
            } else {
                clients.append(c)
            }
        } else {
            clients.append(c)
        }
    }

    package func handleClientMap(_ c: Client) {
        guard clientByIdAll(c.id) == nil else { return }
        c.bw = CGFloat(config.borderpx)

        // init client geom
        c.geom.size.width += 2 * c.bw
        c.geom.size.height += 2 * c.bw
        c.floatGeom = c.geom
        c.overviewBackupGeom = c.geom
        // not in mango: no split indicator, group or tab bar, dim, drop area, border, shadow, blur or
        // shield nodes (the port draws bars and borders)
        clientAddJumpLabelNode(c)
        c.mon = nil
        clientInsertTilingOrder(c)
        focusStack.insert(c.id, at: 0)
        clientSetRules(c)

        if let cm = c.mon, cm.isoverview {
            overviewBackupSurface(c)
        }

        // not in mango: arrange, not resize, until a floating client's geom is its float_geom (docs/afvigelser.md, arrange)
        if let cm = c.mon { arrange(cm, false, false) }
        printstatus(.arrangge)
    }

    package func handleClientUnmap(_ c: Client) {
        let id = c.id
        guard clientByIdAll(id) === c else { return }
        c.iskilling = true
        if c.tabPrev != nil || c.tabNext != nil { tabDetachClient(c) }
        switcherRemoveClient(c)
        let targetNode = c.mon.flatMap { findScrollerNode($0.pertag.scrollerState[getClientTagIdx(c)], c) }
        let stackPrev = targetNode?.prevInStack?.client
        let stackNext = targetNode?.nextInStack?.client
        // Port extension: not in mango. Its group and its place in the order, for when the
        // window comes back (macOS reports windows gone and back around sleep).
        let group = c.isGroupMember ? groupMembers(c) : []

        if let label = c.jumpLabelNode {
            label.destroy()
            c.jumpLabelNode = nil
        }

        let replaced = c.isGroupMember && c.isGroupFocus && (c.groupNext ?? c.groupPrev) != nil
        if c.isGroupMember {
            if c.isGroupFocus, let r = c.groupNext ?? c.groupPrev {
                r.mon = c.mon
                clientReplace(r, c, isGroupChangeMember: false)
            }
            clientGroupDetach(c)
        }
        if !replaced {
            scrollerRemoveClient(c)
            dwindleRemoveClient(c)
        }
        let order = clients.map(\.id)
        clients.removeAll { $0 === c }
        portHooks.windowLeaving?(self, c, group.map(\.id), group.first { $0.isGroupFocus }?.id, order)   // Port extension
        focusStack.removeAll { $0 == id }
        if c === grabClient {
            cursorMode = CurNormal
            grabClient = nil
            if let dc = dropClient {
                dc.enableDropAreaDraw = false
                clientSetDropArea(dc)
                dropClient = nil
            }
        }

        if c === dropClient {
            dropClient = nil
            system.showDropArea(nil, color: config.dropcolor)   // not in mango: the port's one drop area, mango's goes with the client's scene
        }

        // not in mango: the pending group-bar drag lets go of it, as of drop_client (a mango bug, docs/afvigelser.md §6)
        if c === groupBarDragClient {
            groupBarDragPending = false
            groupBarDragClient = nil
        }

        for m in monitors {
            if m.sel == id { m.sel = nil }
            if m.prevsel == id { m.prevsel = nil }
        }
        if let m = c.mon, m === selectedMonitor {
            var nextfocus = stackNext ?? stackPrev ?? clientFocusTop(selectedMonitor)

            if let n = nextfocus, !VISIBLEON(n, selectedMonitor) { nextfocus = clientFocusTop(selectedMonitor) }

            if let nextfocus { clientFocus(nextfocus, true) }

            if nextfocus == nil && selectedMonitor.isoverview { toggleOverview(Arg()) }
        }

        // not in mango: c left clients and focus_stack above; no fade-out, swallowing or scene nodes
        let unmappedFrom = c.mon
        clientSetMonitor(c, nil, 0, focus: true)
        // not in mango: client_set_monitor's focus step, which clientIsParked skips for a client off the list
        if unmappedFrom != nil && !replaced { clientFocus(clientFocusTop(selectedMonitor), true) }

        // not in mango: of init_client_properties only iskilling and drag_to_tile; the port keeps an away window's state
        c.iskilling = false
        c.dragToTile = false

        printstatus(.arrangge)
        pointerProcessMotion(0, 0, 0)
    }

    package func handleClientDestroy(_ c: Client) {
        switcherRemoveClient(c)
        pointerClientDestroyed(c)
    }

    package func handleClientRequestMinimize(_ c: Client, _ minimized: Bool) {
        guard clientByIdAll(c.id) === c, c.mon != nil, !c.isminimized, !c.groupParked else { return }
// not in mango: no client_set_minimized; the port has done the Dock's part.
        if minimized && !c.ignoreMinimize {
            setMinimized(c)
        }
    }

    package func handleClientSetTitle(_ c: Client) {
        guard clientByIdAll(c.id) === c else { return }
        drawBars()   // not in mango: client_update_group_bar_title and client_update_tab_bar_title; the port draws all bars
        titleMessageBarUpdateTitle(c)
        if let m = c.mon, c === clientFocusTop(m) { printstatus(.arrangge) }
    }

    package func handleClientActivationRequest(_ c: Client) {
        guard clientByIdAll(c.id) === c else { return }
        if config.focusOnActivate && !c.istagsilent && c.id != selectedMonitor.sel {
            if c.tags & TAG0_MASK != 0, let m = c.mon {
                if isSpecialActive(m) {
                    clientFocus(c, true)
                } else {
                    toggleSpecialTagMon(m)
                }
                return
            }
            clientActive(c)
        } else if c !== clientFocusTop(selectedMonitor) {
            c.isurgent = true
            updateBorders()
            printstatus(.arrangge)
        }
    }

    func pendingKillClient(_ c: Client) { system.clientSendClose(c) }
    package func clientFocus(_ c: Client?, _ lift: Bool) {
        let oldKeyboardFocusSurface = system.keyboardFocusedSurface

        if let c, c.iskilling { return }

        if let c, clientByIdAll(c.id) !== c { return }

        if let c, c.noFocus { return }

        /* Raise client in stacking order if requested */
        if let c, lift {
            clientRaiseGroup(c)
            clientRaiseTab(c)
        }

        if let c, oldKeyboardFocusSurface === c, selectedMonitor.sel != nil {
            return
        }

        if let c, let m = c.mon {
            selectedMonitor = m
            m.prevsel = m.sel
            m.sel = c.id
            // not in mango: no isfocusing

            tabSyncFocus(c)

            // not in mango: client_check_tab_node_visible, idle inhibit, vrr and opacity; the port draws
            // the bars from sel

            // decide whether need to re-arrange

            // change focus link position
            focusStack.removeAll { $0 == c.id }
            focusStack.insert(c.id, at: 0)

            if let p = m.prevsel.flatMap({ clientByIdAll($0) }), TAGMATCH(p, m), TAGMATCH(c, m), !c.isfloating,
               isScrollerLayout(m) || isMonocleLayout(m) || c.tabPrev != nil || c.tabNext != nil {
                arrange(m, false, false)
            } else {
                updateBorders()   // not in mango: the port's side
            }

            // change border color
            c.isurgent = false
        }

        /* Deactivate old client if focus is changing */
        if let old = oldKeyboardFocusSurface, c == nil || old !== c {
            // not in mango: no layer shell (exclusive_focus); client_wants_focus is X11's
            system.clientActivateSurface(old, false)
        }
        system.restack()   // not in mango: the port's side
        if let cm = c?.mon, cm.isoverview, cm.ovThumbnails {
            system.updateOverview(overlayCards(cm), on: cm)   // not in mango: the port's side
        }
        if c != nil { printstatus(.arrangge) }   // not in mango: with no client, after sel is cleared; the port's status reads it at once

        guard let c else {
            let sm: Monitor = selectedMonitor
            if let id = sm.sel, !(clientByIdAll(id).map { $0.isVisible(on: sm) && !$0.iskilling } ?? false) {
                sm.sel = nil
            }
            printstatus(.arrangge)
            updateBorders()   // not in mango: the port's side

            system.keyboardNotifyClearFocus()
            pointerCheckConfineClient()
            return
        }

        /* Change cursor surface */
        pointerProcessMotion(0, 0, 0)

        /* Have a client, so focus its top-level wlr_surface */
        system.clientNotifyEnter(c)

        /* Activate the new client */
        system.clientActivateSurface(c, true)

        pointerCheckConfineClient()
    }

    func clientActive(_ c: Client) {
        // not in mango: no unmanaged clients (client_is_unmanaged) and no swallowing (c->swallowdby)

        if c.mon == nil && !clientGroupSwapFocus(c) { return }

        if c.isInScratchpad {
            let visible = SCRATCHPAD_SHOWN(c) && c.mon.map { c.tags & $0.tagset[$0.seltags] != 0 } == true
            if visible {
                clientFocus(c, true)
            } else if c.isnamedscratchpad {
                applyNamedScratchpad(c)
            } else {
                _ = switchScratchpadClientState(c)
            }
            return
        }

        if c.isminimized {
            c.isInScratchpad = false
            c.isnamedscratchpad = false
            bordersDirty = true   // not in mango: client_update_border_color; the port draws the borders at once
            showHideClient(c)
            if let m = c.mon { arrange(m, true, false) }
            return
        }
        let target = getTagsFirstTag(c.tags)
        clientViewOnMonitor(Arg(ui: target), true, c.mon, true)
        clientFocus(c, true)
    }

    package func clientViewOnMonitor(_ arg: Arg, _ wantAnimation: Bool, _ m: Monitor?, _ changefocus: Bool) {
        var wantAnimation = wantAnimation
        var tmptag: UInt32

        guard let m, !(arg.ui != (~0 & TAGMASK) && m.isoverview) else { return }

        if arg.ui == 0 { return }

        if arg.ui == UInt32.max {
            if m.tagset[0] != m.tagset[1] {
                m.pertag.prevtag = getTagsFirstTagNum(m.tagset[m.seltags])
                m.seltags ^= 1 /* toggle sel tagset */
                m.pertag.curtag = getTagsFirstTagNum(m.tagset[m.seltags])
            } else {
                return
            }
        } else {
            if (m.tagset[m.seltags] & arg.ui & (TAGMASK | TAG0_MASK)) != 0 { wantAnimation = false }

            m.seltags ^= 1 /* toggle sel tagset */

            if arg.ui & (TAGMASK | TAG0_MASK) != 0 {
                m.tagset[m.seltags] = arg.ui & (TAGMASK | TAG0_MASK)
                tmptag = m.pertag.curtag

                if arg.ui & TAG0_MASK != 0 {
                    m.pertag.curtag = 0
                } else {
                    var i: UInt32 = 0
                    while arg.ui & (1 << i) == 0 && i < UInt32(config.tagNum) && arg.ui != 0 { i += 1 }
                    m.pertag.curtag = i >= UInt32(config.tagNum) ? UInt32(config.tagNum) : i + 1
                }

                m.pertag.prevtag = tmptag == m.pertag.curtag ? m.pertag.prevtag : tmptag
            } else {
                tmptag = m.pertag.prevtag
                m.pertag.prevtag = m.pertag.curtag
                m.pertag.curtag = tmptag
            }
        }

        if changefocus { clientFocus(clientFocusTop(m), true) }
        arrange(m, wantAnimation, true)
        printstatus(.arrangge)
    }

    func clientSwitchView(_ arg: Arg, _ wantAnimation: Bool) {
        if arg.i != 0 {
            clientViewOnMonitor(arg, wantAnimation, selectedMonitor, true)
            // not in mango: no disabled outputs
            for m in monitors where m !== selectedMonitor {
                // only arrange, not change monitor focus
                clientViewOnMonitor(arg, wantAnimation, m, false)
            }
        } else {
            clientViewOnMonitor(arg, wantAnimation, selectedMonitor, true)
        }
    }

    func tagClient(_ arg: Arg, _ targetClient: Client?) {
        if let targetClient, arg.ui & (TAGMASK | TAG0_MASK) != 0 {
            targetClient.tags = arg.ui & TAG0_MASK != 0 ? TAG0_MASK : arg.ui & TAGMASK
            // not in mango: client_reparent_group (no macOS part)

            for fc in clients where fc !== targetClient && targetClient.tags & fc.tags != 0 && ISFULLSCREEN(fc)
                && !targetClient.isfloating {
                clearFullscreenFlag(fc)
            }
            if arg.ui & TAG0_MASK != 0, let cm = targetClient.mon {
                arrange(cm, false, false)
            }
            clientSwitchView(Arg(i: arg.i, ui: arg.ui), true)

        } else {
            clientSwitchView(arg, true)
        }

        clientFocus(targetClient, true)
        printstatus(.arrangge)
    }

    func showHideClient(_ c: Client) {
        guard let m = c.mon else { return }
        if !c.ignoreMinimize { system.clientSetMinimized(c, false) }   // not in mango: macOS's own minimize undone
        setSizePer(m, c)
        let target = getTagsFirstTag(c.oldtags)
        if !c.isInScratchpad {
            tagClient(Arg(ui: target), c)
        } else {
            c.tags = m.tagset[m.seltags]
            c.isminimized = false
            arrange(m, false, false)
        }
        clientPendingMinimizedState(c, false)
        clientFocus(c, true)
    }

    package func clientSetMonitor(_ c: Client, _ m: Monitor?, _ newtags: UInt32, focus: Bool) {
        let oldmon = c.mon
        if oldmon === m { return }
        if let oldmon, oldmon.sel == c.id { oldmon.sel = nil }
        if let oldmon, oldmon.prevsel == c.id { oldmon.prevsel = nil }
        c.mon = m
        if let oldmon { arrange(oldmon, false, false) }
        if clientIsParked(c) { return }

        if let m {
            /* Make sure window actually overlaps with the monitor */
            resize(c, c.geom, ResizeOpts(interact: false))
            clientResetMonTags(c, m, newtags)
            checkMatchTagFloatingRule(c, m)
            clientSetFloating(c, c.isfloating)
            clientSetFullscreen(c, c.isfullscreen, rearrange: true)
        }
        if focus { clientFocus(clientFocusTop(selectedMonitor), true) }
    }

    func clientAdaptGeometryToMonitor(_ c: Client, _ oldmon: Monitor) {
        guard let cm = c.mon else { return }
        let from = oldmon.w, to = cm.w
        guard from.width > 0, from.height > 0, to.width > 0, to.height > 0 else { return }

        c.floatGeom.size = CGSize(width: (c.floatGeom.width * to.width / from.width).rounded(.towardZero),
                                  height: (c.floatGeom.height * to.height / from.height).rounded(.towardZero))
        c.floatGeom = clientCenterGeometry(c, cm, c.floatGeom)
    }

    func clientSetMonitorAdapted(_ c: Client, _ m: Monitor, _ newtags: UInt32, focus: Bool) -> Bool {
        guard let oldmon = c.mon, oldmon !== m else { return false }

        clientSetMonitor(c, m, newtags, focus: focus)
        if c.mon !== m { return false }

        clientUpdateOldmonnameRecord(c, m)
        c.parked = false   // not in mango: the system places it on the new display
        clientAdaptGeometryToMonitor(c, oldmon)
        if c.isfloating { c.geom = c.floatGeom }
        return true
    }

    func clientChangeMon(_ c: Client, _ m: Monitor?) {
        clientSetMonitor(c, m, c.tags, focus: true)
        c.parked = false   // not in mango: the system places it on the new display
        if c.isfloating {
            c.geom = clientCenterGeometry(c, c.mon, c.geom)
            c.floatGeom = c.geom
        }
    }

    func viewInsertShiftTags(_ m: Monitor, _ target: UInt32) {
        var map = [UInt32](repeating: 0, count: Int(tag_num_MAX) + 1)

        if target < 1 || target >= UInt32(config.tagNum) { return }

        if getTagStatus(UInt32(config.tagNum), m) != 0 { return }

        for i in 1...UInt32(config.tagNum) {
            if i < target {
                map[Int(i)] = i
            } else if i < UInt32(config.tagNum) {
                map[Int(i)] = i + 1
            } else {
                map[Int(i)] = i
            }
        }

        for c in clients {
            if c.mon !== m || c.iskilling { continue }
            c.tags = tagRemapMask(c.tags, map)
        }

        m.tagset[m.seltags] = tagRemapMask(m.tagset[m.seltags], map)
        m.tagset[m.seltags ^ 1] = tagRemapMask(m.tagset[m.seltags ^ 1], map)
        m.ovbkCurrentTagset = tagRemapMask(m.ovbkCurrentTagset, map)
        m.ovbkPrevTagset = tagRemapMask(m.ovbkPrevTagset, map)

        if m.pertag.curtag <= UInt32(config.tagNum) && map[Int(m.pertag.curtag)] != 0 {
            m.pertag.curtag = map[Int(m.pertag.curtag)]
        }
        if m.pertag.prevtag <= UInt32(config.tagNum) && map[Int(m.pertag.prevtag)] != 0 {
            m.pertag.prevtag = map[Int(m.pertag.prevtag)]
        }

        var i = UInt32(config.tagNum) - 1
        while i >= target {
            tagGatherMovePertag(m, i + 1, i)
            i -= 1
        }
    }

    func clientSetFloating(_ c: Client, _ floating: Bool, _ wantAnimation: Bool = false) {
        let oldFloatingState = c.isfloating
        c.isfloating = floating
        var windowSizeOutofrange = false

        guard let m = c.mon, !c.iskilling else { return }

        var targetBox = c.geom

        if floating && c !== grabClient {
            if c.isfullscreen {
                clientPendingFullscreenState(c, false)
                system.clientNotifyFullscreen(c, false)
            }

            clientPendingMaximizedState(c, false)
            exitScrollerStack(c)

            // Recomputes the centered coordinates.
            if !c.iscustompos {
                targetBox = clientCenterGeometry(c, m, targetBox, 0, 0)
            } else {
                targetBox = c.geom
            }

            // restore to the memeroy geom
            if c.floatGeom.width > 0 && c.floatGeom.height > 0 {
                if c.floatGeom.width >= m.w.width - CGFloat(config.gappoh) {
                    c.floatGeom.size.width = (m.w.width * 0.9).rounded(.towardZero)
                    windowSizeOutofrange = true
                }
                if c.floatGeom.height >= m.w.height - CGFloat(config.gappov) {
                    c.floatGeom.size.height = (m.w.height * 0.9).rounded(.towardZero)
                    windowSizeOutofrange = true
                }
                if windowSizeOutofrange {
                    c.floatGeom = clientCenterGeometry(c, m, c.floatGeom, 0, 0)
                }
                resize(c, c.floatGeom, ResizeOpts(interact: false))
            } else {
                resize(c, targetBox, ResizeOpts(interact: false))
            }
        } else if c.isfloating && c === grabClient {
            // not in mango: no need_float_size_reduce (no X11 size hints)
        } else {
            c.isInScratchpad = false
            c.isnamedscratchpad = false
            setSizePer(m, c)
            // Makes fullscreen windows on the current tag exit fullscreen so they
            // join tiling.
            for fc in clients where fc !== c && VISIBLEON(fc, m) && c.tags & fc.tags != 0
                && ISFULLSCREEN(fc) && oldFloatingState {
                clearFullscreenFlag(fc)
            }
        }

        // not in mango: client_reparent_group, client_set_maximized and client_sync_tiled_hint (no macOS part)

        arrange(m, wantAnimation, false)

        if !c.isfloating {
            c.oldMasterInnerPer = c.masterInnerPer
            c.oldStackInnerPer = c.stackInnerPer
        }

        bordersDirty = true   // not in mango: client_update_border_color; the port draws the borders at once
        printstatus(.arrangge)
    }

    func clientSetFullscreen(_ c: Client, _ fullscreen: Bool, rearrange: Bool) {
        guard let m = c.mon, !c.iskilling, c !== grabClient else { return }

        if m.isoverview { return }

        c.isfullscreen = fullscreen

        system.clientNotifyFullscreen(c, fullscreen)
        clientPendingFullscreenState(c, fullscreen)

        if fullscreen {
            // not in mango: client_set_maximized (no macOS part)

            clientPendingMaximizedState(c, false)

            exitScrollerStack(c)
            c.isfakefullscreen = false

            c.bw = 0
            if !isScrollerLayout(m) || c.isfloating {
                resize(c, m.m, ResizeOpts(interact: true))
            }
        } else {
            c.bw = c.noBorder ? 0 : CGFloat(config.borderpx)
            if c.isfloating { clientSetFloating(c, true, false) }
        }

        // not in mango: client_reparent_group, check_vrr_enable and check_keep_idle_inhibit (no macOS part)

        if rearrange { arrange(m, false, false) }
    }

    func clientSetFakeFullscreen(_ c: Client, _ fakefullscreen: Bool) {
        c.isfakefullscreen = fakefullscreen
        guard c.mon != nil else { return }
        if c.isfullscreen { clientSetFullscreen(c, false, rearrange: true) }

        // not in mango: client_notify_fullscreen (telling a macOS window it is fullscreen takes it out of the layout)
    }

    func maximizeScreenGaps(_ c: Client) -> (gappoh: CGFloat, gappov: CGFloat) {
        var gappoh = CGFloat(config.gappoh), gappov = CGFloat(config.gappov)
        if config.monocleNoGap, let m = c.mon, !m.isoverview, isMonocleLayout(m) {
            gappoh = 0
            gappov = 0
        }
        return (gappoh, gappov)
    }

    func clientSetMaximizeScreen(_ c: Client, _ maximizescreen: Bool, rearrange: Bool) {
        guard let m = c.mon, !c.iskilling, c !== grabClient else { return }

        if m.isoverview { return }

        clientPendingMaximizedState(c, maximizescreen)

        if maximizescreen {
            if c.isfullscreen {
                clientPendingFullscreenState(c, false)
                system.clientNotifyFullscreen(c, false)
            }

            exitScrollerStack(c)

            let (gappoh, gappov) = maximizeScreenGaps(c)

            let w = m.w
            var maximizescreenBox = CGRect(x: w.minX + gappoh, y: w.minY + gappov,
                                           width: w.width - 2 * gappoh, height: w.height - 2 * gappov)

            if clientWantsGroupBar(c) {
                maximizescreenBox.size.height -= CGFloat(config.groupBarHeight)
                maximizescreenBox.origin.y += CGFloat(config.groupBarHeight)
            }

            if !isScrollerLayout(m) || c.isfloating {
                resize(c, maximizescreenBox, ResizeOpts(interact: false))
            }
        } else {
            c.bw = c.noBorder ? 0 : CGFloat(config.borderpx)
            if c.isfloating { clientSetFloating(c, true, false) }
        }

        // not in mango: client_reparent_group and client_set_maximized (no macOS part)

        if rearrange { arrange(m, false, false) }
    }

    func resetMaximizescreenSize(_ c: Client) {
        guard let m = c.mon else { return }   // not in mango: c->mon is always set here
        let (gappoh, gappov) = maximizeScreenGaps(c)

        let w = m.w
        var geom = CGRect(x: w.minX + gappoh, y: w.minY + gappov, width: w.width - 2 * gappoh, height: w.height - 2 * gappov)

        if clientWantsGroupBar(c) {
            geom.size.height -= CGFloat(config.groupBarHeight)
            geom.origin.y += CGFloat(config.groupBarHeight)
        }

        resize(c, geom, ResizeOpts(interact: false))
    }

    func setMinimized(_ c: Client) {
        guard let m = c.mon, grabClient !== c else { return }

        if !c.isInScratchpad {
            c.isfloatingBeforeScratchpad = c.isfloating
        }

        c.isglobal = false
        c.oldtags = m.tagset[m.seltags]
        c.tags = 0
        clientPendingMinimizedState(c, true)
        c.isInScratchpad = true
        // not in mango: client_reparent_group (no macOS part)

        clientFocus(clientFocusTop(selectedMonitor), true)
        arrange(m, false, false)
        clients.removeAll { $0 === c }
        clients.insert(c, at: 0)
    }

    func exitScrollerStack(_ c: Client) {
        guard let m = c.mon else { return }

        let tag = getClientTagIdx(c)
        if let st = m.pertag.scrollerState[tag] {
            if let n = findScrollerNode(st, c) {
                c.scrollerProportion = n.scrollerProportion
                c.scrollerProportionSingle = n.scrollerProportionSingle
                c.scrollerStackProportion = n.scrollerStackWeight
                scrollerNodeRemove(st, n)
                return
            }
        }
    }

    func clearFullscreenAndMaximizedState(_ m: Monitor) {
        for fc in clients where VISIBLEON(fc, m) && (fc.isfullscreen || fc.ismaximizescreen) {
            clearFullscreenFlag(fc)
        }
    }

    func clearFullscreenFlag(_ c: Client) {
        guard let m = c.mon else { return }
        let layout = m.pertag.ltidxs[getClientTagIdx(c)]
        if !c.isfloating && (layout.isScroller || (layout == .monocle && config.monocleTabMode)) { return }
        if c.isfullscreen { clientSetFullscreen(c, false, rearrange: true) }
        if c.ismaximizescreen { clientSetMaximizeScreen(c, false, rearrange: true) }
    }

    func clientPendingFullscreenState(_ c: Client, _ isfullscreen: Bool) {
        c.isfullscreen = isfullscreen
        // not in mango: no foreign toplevel
    }

    func clientPendingMaximizedState(_ c: Client, _ ismaximized: Bool) {
        c.ismaximizescreen = ismaximized
        // not in mango: no foreign toplevel
    }

    func clientPendingMinimizedState(_ c: Client, _ isminimized: Bool) {
        c.isminimized = isminimized
        // not in mango: no foreign toplevel
    }

    func showScratchpad(_ c: Client) {
        guard let m = c.mon else { return }
        if c.isfullscreen || c.ismaximizescreen {
            clientPendingFullscreenState(c, false)
            clientPendingMaximizedState(c, false)
            c.bw = c.noBorder ? 0 : CGFloat(config.borderpx)
        }

        if !c.isfloating { clientSetFloating(c, true) }

        if !c.iscustomsize {
            let w = m.w
            c.geom.size = CGSize(width: (w.width * CGFloat(config.scratchpadWidthRatio)).rounded(.towardZero),
                                 height: (w.height * CGFloat(config.scratchpadHeightRatio)).rounded(.towardZero))
            // Recomputes the centered coordinates.
            let g = clientCenterGeometry(c, m, c.geom)
            c.floatGeom = g; c.geom = g; c.animainitGeom = g; c.animation.current = g
            c.iscustomsize = true
            resize(c, c.geom, ResizeOpts(interact: false))
        }

        // not in mango: client_reparent_group (no macOS part)
        c.oldtags = m.tagset[m.seltags]
        clients.removeAll { $0 === c }
        clients.insert(c, at: 0)
        showHideClient(c)
        bordersDirty = true   // not in mango: client_update_border_color; the port draws the borders at once
    }

    func switchScratchpadClientState(_ c: Client) -> Bool {
        guard let old = c.mon, c.isInScratchpad else { return false }
        let shown = SCRATCHPAD_SHOWN(c)
        if config.scratchpadCrossMonitor && old !== selectedMonitor {
            // Saves the original monitor for size computation.
            c.scratchpadSwitchingMon = true
            c.mon = selectedMonitor
            // not in mango: reset_foreign_tolevel (no foreign toplevel)
            clientUpdateOldmonnameRecord(c, selectedMonitor)

            clientAdaptGeometryToMonitor(c, old)

            // Only a visible scratchpad needs focus and returns true.
            if shown {
                c.tags = getTagsFirstTag(selectedMonitor.tagset[selectedMonitor.seltags])
                resize(c, c.floatGeom, ResizeOpts(interact: false))
                arrange(selectedMonitor, false, false)
                clientFocus(c, true)
                c.scratchpadSwitchingMon = false
                return true
            } else {
                resize(c, c.floatGeom, ResizeOpts(interact: false))
                c.scratchpadSwitchingMon = false
            }
        }
        guard let m = c.mon else { return false }
        if shown && m.tagset[m.seltags] & c.tags != 0 {
            setMinimized(c)
            return true
        }
        c.tags = m.tagset[m.seltags]
        c.oldtags = c.tags
        c.scratchpadTagin = true
        if shown {
            arrange(m, false, false)
            clientFocus(c, true)
        } else {
            showScratchpad(c)
        }
        return true
    }

    func applyNamedScratchpad(_ target: Client) {
        for c in clients {
            if !config.scratchpadCrossMonitor && c.mon !== selectedMonitor { continue }
            if config.singleScratchpad && SCRATCHPAD_SHOWN(c) && c !== target { setMinimized(c) }
        }
        if !target.isInScratchpad { setMinimized(target) }
        _ = switchScratchpadClientState(target)
    }

    func clientExchange(_ c1: Client, _ c2: Client) {
        guard let m1 = c1.mon, let m2 = c2.mon, config.exchangeCrossMonitor || m1 === m2 else { return }

        let layout1 = m1.pertag.ltidxs[getClientTagIdx(c1)]
        let layout2 = m2.pertag.ltidxs[getClientTagIdx(c2)]

        if layout1 == .scroller || layout2 == .scroller || layout1 == .verticalScroller || layout2 == .verticalScroller {
            exchangeTwoScrollerClients(c1, c2)
            return
        }

        if layout1 == .dwindle && layout2 == .dwindle {
            dwindleSwapClients(c1, c2)
            return
        }

        clientSwapLayoutProperties(c1, c2)

        wlListSwap(c1, c2)

        if m1 !== m2 {
            clientSwapMonitorsAndTags(c1, c2)
        }

        finishExchangeArrangeAndFocus(c1, c2, m1, m2)
    }



    func clientIsParked(_ c: Client?) -> Bool {
        guard let c else { return false }
        return !clients.contains { $0 === c }
    }

    private func clientUnlink(_ c: Client?) {
        guard let c, !clientIsParked(c) else { return }
        clients.removeAll { $0 === c }
        focusStack.removeAll { $0 == c.id }
    }

    func clientPark(_ c: Client?) {
        if let c, c.tabPrev != nil || c.tabNext != nil { tabDetachClient(c) }
        clientUnlink(c)
        guard let c else { return }
        c.animation.running = false
        c.mon = nil
        c.groupParked = true   // not in mango: the port's mark of a parked member (clientsAll)
    }

    func clientUnpark(_ c: Client?, _ anchor: Client?) {
        guard let c else { return }

        if let anchor, !clientIsParked(anchor) {
            wlListSafeReinsertNext(anchor, c)
            focusStack.removeAll { $0 == c.id }   // wl_list_safe_reinsert_prev on the focus stack
            focusStack.insert(c.id, at: focusStack.firstIndex(of: anchor.id) ?? 0)
        } else if clientIsParked(c) {
            clients.append(c)
            focusStack.insert(c.id, at: 0)
        }
        c.groupParked = false   // not in mango: the port's mark of a parked member (clientsAll)
    }

    func clientReplace(_ c: Client, _ w: Client, isGroupChangeMember: Bool) {
        c.bw = w.bw
        c.isfloating = w.isfloating
        c.isurgent = w.isurgent
        c.tags = w.tags
        c.geom = w.geom
        c.floatGeom = w.floatGeom
        c.stackInnerPer = w.stackInnerPer
        c.masterInnerPer = w.masterInnerPer
        c.stackSizeWeight = w.stackSizeWeight
        c.masterSizeWeight = w.masterSizeWeight
        c.masterMfactPer = w.masterMfactPer
        c.scrollerProportion = w.scrollerProportion
        c.scrollerStackProportion = w.scrollerStackProportion
        c.isglobal = w.isglobal
        c.overviewBackupGeom = w.overviewBackupGeom
        c.overviewBackedUp = w.overviewBackedUp   // not in mango: a mango bug, docs/afvigelser.md §6
        c.animation.current = w.animation.current
        c.isInScratchpad = w.isInScratchpad
        c.isfloatingBeforeScratchpad = w.isfloatingBeforeScratchpad
        if !isGroupChangeMember { clientGroupReplace(w, c) }   // not in mango: no swallowing (is_swallow)

        tabReplaceClient(w, c)

        clientUnpark(c, w)
        // not in mango: the group bar's focus, w's overview card and foreign toplevel are the port's side

        if let cm = c.mon, cm.isoverview {
            overviewBackupSurface(c)
        }

        w.jumpLabelNode?.setEnabled(false)

        c.tagVisible = w.tagVisible
        w.tagVisible = false
        clientUpdateVisibility(w)
        clientUpdateVisibility(c)

        clientPendingFullscreenState(c, w.isfullscreen)
        clientPendingMaximizedState(c, w.ismaximizescreen)
        clientPendingMinimizedState(c, w.isminimized)

        if let m = w.mon {
            let layout = m.pertag.ltidxs[getClientTagIdx(w)]
            for i in 0..<Int(PERTAG_SLOTS) {
                if layout == .dwindle {
                    dwindleRemove(&m.pertag.dwindleRoot[i], c)
                    if let dnode = dwindleFindLeaf(m.pertag.dwindleRoot[i], w) { dnode.client = c }
                }

                // scroller
                if layout == .scroller || layout == .verticalScroller {
                    guard let st = m.pertag.scrollerState[UInt32(i)] else { continue }
                    if let cn = findScrollerNode(st, c) { scrollerNodeRemove(st, cn) }

                    if let wn = findScrollerNode(st, w) { wn.client = c }
                }
            }

            /* Syncs the global client fields of the currently active tag. */
            if layout == .scroller || layout == .verticalScroller {
                syncScrollerStateToClients(m, getClientTagIdx(w))
            }
        } else {
            return
        }

        if w.iskilling {
            clientUnlink(w)
        } else {
            clientPark(w)
        }
    }

    func monitorMoveDirection(_ from: Monitor, _ to: Monitor) -> Int32 {
        guard from !== to else { return UNDIR }
        let dx = (Int64(to.m.minX) + Int64(to.m.width) / 2) - (Int64(from.m.minX) + Int64(from.m.width) / 2)
        let dy = (Int64(to.m.minY) + Int64(to.m.height) / 2) - (Int64(from.m.minY) + Int64(from.m.height) / 2)
        let adx = dx < 0 ? -dx : dx
        let ady = dy < 0 ? -dy : dy

        if adx == 0 && ady == 0 { return UNDIR }
        if adx >= ady { return dx > 0 ? RIGHT : LEFT }
        return dy > 0 ? DOWN : UP
    }

    func clientReassignMonitor(_ c: Client, _ m: Monitor) {
        guard let old = c.mon, old !== m else { return }
        if old.sel == c.id { old.sel = nil }
        if old.prevsel == c.id { old.prevsel = nil }
        c.mon = m
        c.parked = false   // not in mango: the system places it on the new display
        if !VISIBLEON(c, m) { clientResetMonTags(c, m, 0) }
        m.sel = c.id
        setSelectedMonitor(m)
    }

    @discardableResult
    func clientJumpToMonitor(_ c: Client, _ m: Monitor, _ dir: Int32) -> Bool {
        guard let old = c.mon, old !== m, config.exchangeCrossMonitor,
              monitorMoveDirection(old, m) == dir else { return false }
        clientReassignMonitor(c, m)
        arrange(old, false, false)
        arrange(m, false, false)
        return true
    }

    func clientMoveToMonitor(_ c: Client, _ target: Client, _ dir: Int32) {
        guard let src = c.mon, let dst = target.mon, c !== target, src !== dst, config.exchangeCrossMonitor,
              monitorMoveDirection(src, dst) == dir else { return }
        let layout = dst.layout
        if layout == .dwindle {
            dwindleMoveNextTo(c, target, Float(config.dwindleSplitRatio), dir)
            return
        }
        let insertBefore = dir == RIGHT || dir == UP

        clientReassignMonitor(c, dst)

        if layout == .scroller || layout == .verticalScroller {
            let alongAxis = layout == .verticalScroller ? (dir == UP || dir == DOWN) : (dir == LEFT || dir == RIGHT)
            if !alongAxis {
                scrollerInsertStack(c, target, insertBefore)
            } else if insertBefore {
                let head = scrollGetStackHeadClient(target)
                wlListSafeReinsertPrev(head, c)
            } else {
                let tail = scrollGetStackTailClient(target)
                wlListSafeReinsertNext(tail, c)
            }
        } else if insertBefore {
            wlListSafeReinsertPrev(target, c)
        } else {
            wlListSafeReinsertNext(target, c)
        }
        arrange(src, false, false)
        arrange(dst, false, false)
    }

    func clientUpdateOldmonnameRecord(_ c: Client, _ m: Monitor) {
        if c.iskilling { return }
        // not in mango: no mapped test; every Client is a mapped window
        c.oldmonname = m.screen.displayID
    }

    func clientSetBounds(_ c: Client, _ bbox: CGRect) {
        /* set minimum possible */
        c.geom.size.width = max(1 + 2 * c.bw, c.geom.width)
        c.geom.size.height = max(1 + 2 * c.bw, c.geom.height)

        if c.geom.minX >= bbox.minX + bbox.width { c.geom.origin.x = bbox.minX + bbox.width - c.geom.width }
        if c.geom.minY >= bbox.minY + bbox.height { c.geom.origin.y = bbox.minY + bbox.height - c.geom.height }
        if c.geom.minX + c.geom.width <= bbox.minX { c.geom.origin.x = bbox.minX }
        if c.geom.minY + c.geom.height <= bbox.minY { c.geom.origin.y = bbox.minY }
    }

    func clientSwapLayoutProperties(_ c1: Client, _ c2: Client) {
        // grid property swap
        (c1.gridColPer, c2.gridColPer) = (c2.gridColPer, c1.gridColPer)
        (c1.gridRowPer, c2.gridRowPer) = (c2.gridRowPer, c1.gridRowPer)
        (c1.gridColIdx, c2.gridColIdx) = (c2.gridColIdx, c1.gridColIdx)
        (c1.gridRowIdx, c2.gridRowIdx) = (c2.gridRowIdx, c1.gridRowIdx)

        // master / stack property swap
        (c1.masterInnerPer, c2.masterInnerPer) = (c2.masterInnerPer, c1.masterInnerPer)
        (c1.masterMfactPer, c2.masterMfactPer) = (c2.masterMfactPer, c1.masterMfactPer)
        (c1.stackInnerPer, c2.stackInnerPer) = (c2.stackInnerPer, c1.stackInnerPer)
        (c1.masterSizeWeight, c2.masterSizeWeight) = (c2.masterSizeWeight, c1.masterSizeWeight)
        (c1.stackSizeWeight, c2.stackSizeWeight) = (c2.stackSizeWeight, c1.stackSizeWeight)
    }

    func clientSwapMonitorsAndTags(_ c1: Client, _ c2: Client) {
        let tmpMon = c2.mon
        let tmpTags = c2.tags
        c2.mon = c1.mon
        c1.mon = tmpMon
        c2.tags = c1.tags
        c1.tags = tmpTags
    }

    func finishExchangeArrangeAndFocus(_ c1: Client, _ c2: Client, _ m1: Monitor, _ m2: Monitor) {
        if m1 !== m2 {
            if let cm = c1.mon { arrange(cm, false, false) }
            if let cm = c2.mon { arrange(cm, false, false) }
        } else {
            if let cm = c1.mon { arrange(cm, false, false) }
        }

        // not in mango: wl_list_safe_reinsert_next on the focus stack, which holds ids here
        if let i = focusStack.firstIndex(of: c1.id), !(i + 1 < focusStack.count && focusStack[i + 1] == c2.id), c1 !== c2 {
            focusStack.removeAll { $0 == c2.id }
            focusStack.insert(c2.id, at: focusStack.firstIndex(of: c1.id)! + 1)
        }

        if config.warpcursor { pointerWarpToClient(c1) }
    }

    func clientTileResize(_ c: Client, _ box: CGRect, _ interact: Bool, _ ctx: LayoutContext?) {
        var geo = box
        if let ctx, let probe = ctx.probe {
            if c === probe { ctx.out = geo }
            return
        }

        guard ISFAKETILED(c), let m = c.mon else { return }

        if !m.isoverview && !c.isfullscreen && clientWantsGroupBar(c) {
            geo.origin.y = geo.minY + CGFloat(config.groupBarHeight)
            geo.size.height -= CGFloat(config.groupBarHeight)
        }

        if !m.isoverview && !c.isfullscreen && config.tabBarHeight > 0 && (c.tabPrev != nil || c.tabNext != nil) {
            geo.origin.y = geo.minY + CGFloat(config.tabBarHeight)
            geo.size.height -= CGFloat(config.tabBarHeight)
        }

        if (!c.isfullscreen && !c.ismaximizescreen) || isScrollerLayout(m) {
            if m.isoverview && overviewCardTileResize(c, geo) { return }   // not in mango: the box is the client's card (the port's picture)
            resize(c, geo, ResizeOpts(interact: interact))
        }
    }

    /* Single place judging whether a window's nodes should be enabled.
     * Each flag below is owned by the mechanism that sets it; this only reads. */
    func clientShouldVisible(_ c: Client) -> Bool {
        // not in mango: no snapshot_temp_visible (no close animation)

        if c.isminimized && !c.animation.tagouting { return false }

        if c.isClipToHide { return false }

        // not in mango: the client's card stands for its ov_card_tree and overview_scene_surface
        if let m = c.mon, m.isoverview, m.ovCards[c.id] != nil { return true }

        if c.isTabHidden { return false }

        if c.iskilling { return false }

        if c.animation.tagouting { return true }

        if clientGestureDriven(c) && (c.animation.tagining || c.animation.tagouting) { return true }

        return c.tagVisible
    }

    func clientUpdateVisibility(_ c: Client) {
        // not in mango: client_update_input_penetration (macOS gives a moving window its clicks)

        let show = clientShouldVisible(c)

        if c.platform.sceneNodeEnabled != show {
            system.sceneNodeSetEnabled(c, show)   // not in mango: the port's wlr_scene_node_set_enabled
        }

        let surfaceShow = !c.isSurfaceHidden

        if c.platform.sceneSurfaceEnabled != surfaceShow {
            system.sceneSurfaceSetEnabled(c, surfaceShow)   // not in mango: the port's wlr_scene_node_set_enabled
        }
    }

    func clientPendingForceKill(_ c: Client?) {
        guard let c else { return }
        kill(c.pid, SIGKILL)
    }

    func clientAddJumpLabelNode(_ c: Client) {
        // not in mango: the port's side (mango_jump_label_node_create)
        c.jumpLabelNode = system.mangoJumpLabelNodeCreate(
            c, mangoBarDecorationApplyConfig(config.jumplabeldata, mango: .mangoJumpLabel))
        guard let label = c.jumpLabelNode else { return }
        /* In overview, labels must be displayed above the card tree. */
        // not in mango: the port's label is its own panel, above the overview's
        label.setEnabled(false)
    }

    // scene layer a client belongs to; only clients actually tagged with tag 0
    // belong to the special layers
    public func clientTargetLayer(_ c: Client) -> Lyr {
        let specialOverlay = c.tags & TAG0_MASK != 0

        if c.isoverlay {
            return specialOverlay ? .specialOverlay : .overlay
        }

        if config.floatFullToTop {
            if specialOverlay {
                return c.isfloating || c.isfullscreen ? .top
                    : c.ismaximizescreen ? .specialMaximize
                    : .specialTile
            }

            if let m = c.mon, isSpecialActive(m) {
                return c.isfullscreen ? .fullscreen
                    : c.isfloating ? .float
                    : c.ismaximizescreen ? .maximize
                    : .tile
            }

            return c.isfloating || c.isfullscreen ? .top
                : c.ismaximizescreen ? .maximize
                : .tile
        }

        if specialOverlay {
            return c.isfullscreen ? .specialFullscreen
                : c.isfloating ? .specialFloat
                : c.ismaximizescreen ? .specialMaximize
                : .specialTile
        }

        return c.isfullscreen ? .fullscreen
            : c.isfloating ? .float
            : c.ismaximizescreen ? .maximize
            : .tile
    }

    func clientWantsGroupBar(_ c: Client) -> Bool {
        c.isGroupMember || config.alwaysShowGroupBar
    }

    @discardableResult
    func clientGroupSwapFocus(_ c: Client) -> Bool {
        guard c.isGroupMember, !c.isGroupFocus,
              let current = groupMembers(c).first(where: { $0.isGroupFocus }), let m = current.mon,
              !m.isoverview else { return false }
        current.isGroupFocus = false
        c.mon = m
        clientReplace(c, current, isGroupChangeMember: true)
        c.isGroupFocus = true
        // not in mango: mango_bar_decoration_set_focus and client_reparent_group (the port draws the bar)
        return true
    }

    package func clientFocusGroupMember(_ c: Client) {
        guard clientGroupSwapFocus(c) else { return }
        clientFocus(c, true)
        if let m = c.mon { arrange(m, false, false) }
    }

    // not in mango: returns show for the port's group bar instead of setting the bar nodes
    func clientCheckTabNodeVisible(_ c: Client, on m: Monitor) -> Bool {
        !m.isoverview && config.groupBarHeight > 0 && clientWantsGroupBar(c) && TAGMATCH(c, m) && ISNORMAL(c)
            && !c.isfullscreen
            && !c.parked   // not in mango: a window macOS has parked off screen
    }

    func clientRaiseGroup(_ c: Client) {
        if c.mon == nil { return }

        var cur: Client? = clientGroupHead(c)
        while let it = cur {
            // not in mango: the group bar is placed by the port's restack
            system.raise(it)
            cur = it.groupNext
        }
    }

    func clientHandleDecorateClick(_ c: Client, isTab: Bool) {
        if isTab {
            tabFocusMember(c)
        } else if !c.isGroupMember {
            clientFocus(c, true)
        } else {
            clientFocusGroupMember(c)
        }
    }

    func clientSetGroupMon(_ c: Client, _ m: Monitor?) {
        var cur: Client? = clientGroupHead(c)
        while let x = cur {
            if !clientIsParked(x) { clientChangeMon(x, m) }
            cur = x.groupNext
        }
    }

    func clientSetGroupConfig(_ c: Client) {
        var cur: Client? = clientGroupHead(c)
        while let it = cur {
            it.jumpLabelNode?.applyConfig(mangoBarDecorationApplyConfig(config.jumplabeldata, mango: .mangoJumpLabel))
            // not in mango: the drop area, split indicators and group bar are drawn by the port from the config
            cur = it.groupNext
        }
    }

    // not in mango: the chain's prev and next fields as key paths, not offsets
    func clientChainHead(_ c: Client, _ prev: ReferenceWritableKeyPath<Client, Client?>) -> Client {
        var head = c
        while true {
            guard let p = head[keyPath: prev] else { break }
            head = p
        }
        return head
    }

    func clientGroupHead(_ c: Client) -> Client {
        clientChainHead(c, \.groupPrev)
    }

    // not in mango: the chain's prev and next fields as key paths, not offsets
    func clientGroupFocused(_ c: Client?) -> Client? {
        var it = c
        while let x = it {
            if x.isGroupFocus { return x }
            it = x.groupNext
        }
        return nil
    }

    func clientGroupActive(_ c: Client?) -> Client? {
        guard let c else { return nil }
        var it: Client? = clientGroupHead(c)
        while let x = it {
            if x.mon != nil { return x }
            it = x.groupNext
        }
        return nil
    }

    func clientChainUnlink(_ c: Client, _ prevKey: ReferenceWritableKeyPath<Client, Client?>,
                           _ nextKey: ReferenceWritableKeyPath<Client, Client?>) {
        let prev = c[keyPath: prevKey]
        let next = c[keyPath: nextKey]
        prev?[keyPath: nextKey] = next
        next?[keyPath: prevKey] = prev
        c[keyPath: prevKey] = nil
        c[keyPath: nextKey] = nil
    }

    func clientGroupDetach(_ c: Client) {
        clientChainUnlink(c, \.groupPrev, \.groupNext)
        c.isGroupFocus = false
        // not in mango: client_group_mark_dirty (no output flush)
    }

    func clientGroupReplace(_ old: Client, _ new: Client) {
        clientGroupDetach(new)
        new.groupPrev = old.groupPrev
        new.groupNext = old.groupNext
        old.groupPrev?.groupNext = new
        old.groupNext?.groupPrev = new
        old.groupPrev = nil
        old.groupNext = nil
        new.isGroupFocus = old.groupParked || !new.isGroupMember ? false : old.isGroupFocus
    }
}
