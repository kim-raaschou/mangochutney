import CoreGraphics

package extension MangoServer {
    func tabLayoutIdSupported(_ id: LayoutKind) -> Bool {
        if id == .monocle { return config.monocleTabMode }
        if id == .deck || id == .verticalDeck { return config.deckTabMode }
        return false
    }

    func tabLayoutEnabled(_ m: Monitor) -> Bool { tabLayoutIdSupported(m.layout) }

    func tabLayoutActive(_ m: Monitor) -> Bool { !m.isoverview && tabLayoutEnabled(m) }

    func tabStateOk(_ c: Client) -> Bool {
        guard c.mon != nil, !c.isMinimized else { return false }
        return !c.isFloating && !c.isUnglobal && !c.isInScratchpad
    }

    func tabIsStackCandidate(_ m: Monitor, _ target: Client) -> Bool {
        if m.layout == .monocle { return true }
        if m.layout != .deck && m.layout != .verticalDeck { return false }
        return !target.isMaster
    }

    // not in mango: the tab chain of the tags in view, as tab_member_kept keeps it (mango links it per window)
    func tabMembers(_ m: Monitor) -> [Client] {
        guard config.tabBarHeight > 0, tabLayoutActive(m) else { return [] }
        let members = visibleClients(m).filter { tabStateOk($0) && tabIsStackCandidate(m, $0) }
        return members.count >= 2 ? members : []
    }

    func tabChainFocus(_ members: [Client], on m: Monitor) -> Client? {
        let sel = members.first { $0.id == m.sel }
        let focus = sel ?? members.first(where: { $0.isTabFocus }) ?? members.first
        for c in members { c.isTabFocus = c === focus }
        return focus
    }

    // not in mango: client_tile_resize's tab strip, over the frames of a layout that is pure here
    func reserveTabStrip(_ frames: inout [ClientID: CGRect], on m: Monitor) {
        let members = tabMembers(m)
        guard !members.isEmpty else { return }
        let h = CGFloat(config.tabBarHeight)
        for c in members {
            guard var f = frames[c.id], f.height > h else { continue }
            f.origin.y += h
            f.size.height -= h
            frames[c.id] = f
        }
    }

    var barsInsideBorder: Bool {
        // Port extension: not in mango. The bars inside the border (chutney_macos_appearance).
        portHooks.barsInsideBorder?(self) ?? false
    }

    func mangoBarDecorationApplyConfig(_ set: DecorateStyle, mango: DecorateStyle) -> DecorateStyle {
        set.setValueDefault(from: mango)
    }

    func topBars(_ c: Client, tabMember: Bool) -> CGFloat {
        (clientWantsGroupBar(c) ? CGFloat(config.groupBarHeight) : 0) + (tabMember ? CGFloat(config.tabBarHeight) : 0)
    }

    func clientCheckTabNodeVisible(_ c: Client, on m: Monitor) -> Bool {
        clientWantsGroupBar(c) && !m.isoverview && !c.isFullscreen && !c.parked && c.isVisible(on: m)
    }

    // not in mango: client_set_clip's client_draw_group_bar and client_draw_tabbar for every client at once
    func tabRefreshBars(animating: [ClientID: CGRect] = [:]) {
        guard drawsOverlays else { return }
        var strips: [TabStrip] = []
        var groups: [TabStrip] = []
        for m in monitors {
            for c in visibleClients(m) where clientCheckTabNodeVisible(c, on: m) {
                if let s = clientDrawGroupBar(c, computeEdgeOffsets(c, animating: animating), animating: animating) {
                    groups.append(s)
                }
            }
            guard let f = tabChainFocus(tabMembers(m), on: m), !f.parked else { continue }   // not in mango: parked is the port's
            if let s = clientDrawTabbar(f, computeEdgeOffsets(f, animating: animating), animating: animating) {
                strips.append(s)
            }
        }
        var style = TabStripStyle(accent: config.focuscolor, accentWidth: CGFloat(min(3, max(1, config.borderpx))))
        style.decorate = mangoBarDecorationApplyConfig(config.tabbardata, mango: .mangoTabBar)
        system.drawTabBars(strips, style: style)
        style.decorate = mangoBarDecorationApplyConfig(config.groupbardata, mango: .mangoGroupBar)
        system.drawGroupBars(groups, style: style)
    }

    // not in mango: c->animation.current, the box the window is drawn in
    func animationCurrent(_ c: Client, animating: [ClientID: CGRect]) -> CGRect {
        let bw = c.mon.map { borderWidth(c, on: $0) } ?? 0
        return shownFrame(c, animating: animating).insetBy(dx: -bw, dy: -bw)
    }

    func clientIsIgnoreOutputClip(_ c: Client, animating: [ClientID: CGRect]) -> Bool {
        // not in mango: animation.tagining is a running tag animation that is not a tagout
        let running = animating[c.id] != nil || system.clientAnimationRunning(c)
        let tagining = running && c.action == .tag && !c.tagouting
        return grab?.client === c || (!Self.isScrollTiled(c) && !tagining && !c.tagouting)
    }

    /// mango compute_edge_offsets (animation/client.c): x left, y top, width right, height bottom.
    func computeEdgeOffsets(_ c: Client, animating: [ClientID: CGRect]) -> CGRect {
        guard let mon = c.mon, !clientIsIgnoreOutputClip(c, animating: animating) else { return .zero }
        let cur = animationCurrent(c, animating: animating), m = mon.screen.frame
        return CGRect(x: max(0, m.minX - cur.minX), y: max(0, m.minY - cur.minY),
                      width: max(0, cur.maxX - m.maxX), height: max(0, cur.maxY - m.maxY))
    }

    // not in mango: the edge clipping both bars share, as client_draw_tabbar and client_draw_group_bar write it
    func clipBar(_ anchor: CGRect, y: CGFloat, height: CGFloat, _ offsets: CGRect, on m: Monitor) -> CGRect {
        var tabX = anchor.minX, tabY = y, tw = anchor.width, th = height
        if offsets.minY > 0 {
            tabY = m.screen.frame.minY
            th = height - offsets.minY
        }
        if offsets.height > 0 { th = th - max(0, offsets.height - anchor.height) }
        if offsets.width > 0 { tw = tw - offsets.width }
        if offsets.minX > 0 {
            tabX = m.screen.frame.minX
            tw = tw - offsets.minX
        }
        return CGRect(x: tabX, y: tabY, width: tw, height: th)
    }

    // not in mango: global_draw_tab_bar and global_draw_group_bar for every member, side by side
    func barSegments(_ bar: CGRect, _ members: [Client]) -> [CGRect] {
        let count = members.count
        let tw = Int(bar.width.rounded(.towardZero))
        let barW = tw / count, rem = tw % count
        var x = bar.minX
        return (0..<count).map { i in
            let w = CGFloat(barW + (i < rem ? 1 : 0))
            defer { x += w }
            return CGRect(x: x, y: bar.minY, width: w, height: bar.height)
        }
    }

    func clientDrawTabbar(_ c: Client, _ offsets: CGRect, animating: [ClientID: CGRect]) -> TabStrip? {
        guard let m = c.mon, c.isTabFocus else { return nil }
        let members = tabMembers(m)
        guard tabLayoutActive(m), !c.isFullscreen, !c.isMaximizeScreen else { return nil }
        let count = members.count
        if count < 2 { return nil }
        var anchor = animationCurrent(c, animating: animating)
        let running = animating[c.id] != nil || system.clientAnimationRunning(c)   // not in mango: c->animation.running
        if running && c.action == .open {
            let bw = borderWidth(c, on: m)
            anchor = (c.geom ?? c.frame).insetBy(dx: -bw, dy: -bw)
        }
        // Port extension: not in mango. The bars inside the border (chutney_macos_appearance).
        let ported = barsInsideBorder
        if ported { anchor = anchor.insetBy(dx: borderWidth(c, on: m), dy: borderWidth(c, on: m)) }
        let groupH = clientWantsGroupBar(c) ? CGFloat(config.groupBarHeight) : 0
        /* Tab strip sits above the group strip when both are present. */
        let h = CGFloat(config.tabBarHeight)
        let bar = clipBar(anchor, y: anchor.minY - h - groupH, height: h, offsets, on: m)
        // not in mango: mango leaves the bars where they were, the port draws none
        if bar.width <= 0 || bar.height <= 0 { return nil }
        let radius = system.windowCornerRadius   // not in mango: the port's side
        let under = groupH > 0 || !ported ? 0 : min(radius, anchor.height)
        return TabStrip(
            frame: CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: bar.height + under),
            barHeight: bar.height, cornerRadius: radius,
            segments: zip(members, barSegments(bar, members)).map { cur, box in
                .init(id: cur.id, title: cur.title.isEmpty ? cur.appName : cur.title, focused: cur.isTabFocus,
                      pid: cur.pid, frame: box)
            },
            above: c.id, plain: !ported)
    }

    func clientDrawGroupBar(_ c: Client, _ offsets: CGRect, animating: [ClientID: CGRect]) -> TabStrip? {
        guard let m = c.mon, clientWantsGroupBar(c) else { return nil }
        /* Owner hidden by tab: hide the whole strip, otherwise its nodes (they are
         * not children of the window) would float over the visible window. */
        if c.isTabHidden { return nil }
        let members = groupMembers(c)
        var current = animationCurrent(c, animating: animating)
        // Port extension: not in mango. The bars inside the border (chutney_macos_appearance).
        let ported = barsInsideBorder
        if ported { current = current.insetBy(dx: borderWidth(c, on: m), dy: borderWidth(c, on: m)) }
        let h = CGFloat(config.groupBarHeight)
        let bar = clipBar(current, y: current.minY - h, height: h, offsets, on: m)
        if bar.width <= 0 || bar.height <= 0 { return nil }
        let radius = system.windowCornerRadius   // not in mango: the port's side
        let under = ported ? min(radius, current.height) : 0
        let sel = selectedMonitor.sel
        return TabStrip(
            frame: CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: bar.height + under),
            barHeight: bar.height, cornerRadius: radius,
            segments: zip(members, barSegments(bar, members)).map { cur, box in
                .init(id: cur.id, title: cur.title.isEmpty ? cur.appName : cur.title, focused: cur.id == sel,
                      pid: cur.pid, frame: box)
            },
            above: c.id,
            closeButton: config.groupBarCloseButtonEnable
                ? .init(size: CGFloat(config.groupBarButtonSize), margin: CGFloat(config.groupBarButtonMargin),
                        color: config.groupBarButtonColor)
                : nil,
            plain: !ported)
    }

    func clientHandleDecorateClick(_ c: Client, isTab: Bool) {
        if isTab {
            tabFocusMember(c.id)
        } else if !c.isGroupMember {
            clientFocus(c, true)
        } else {
            clientFocusGroupMember(c)
        }
    }

    func tabFocusMember(_ id: CGWindowID) {
        guard let c = clientByIdAll(id), let m = c.mon else { return }
        clientFocus(c, true)
        arrange(m, .none)
    }
}
