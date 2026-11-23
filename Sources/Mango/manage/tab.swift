import CoreGraphics

package extension MangoServer {
    private func tabHead(_ c: Client) -> Client {
        clientChainHead(c, \.tabPrev)
    }

    func tabIsMember(_ c: Client?) -> Bool {
        guard let c else { return false }
        return c.tabPrev != nil || c.tabNext != nil
    }

    private func tabBarSetEnabled(_ c: Client, _ on: Bool) {
        // not in mango: the port draws the bar of a client whose tab_bar node is enabled
        c.tabBarEnabled = on
    }

    private func tabChainFocus(_ head: Client) {
        var sel: Client?
        var focus: Client?

        var it: Client? = head
        while let x = it {
            if let m = x.mon, x.id == m.sel { sel = x }
            if focus == nil && x.isTabFocus { focus = x }
            it = x.tabNext
        }

        let f = sel ?? focus ?? head

        it = head
        while let x = it {
            x.isTabFocus = x === f
            it = x.tabNext
        }
    }

    private func tabLeave(_ c: Client) {
        clientChainUnlink(c, \.tabPrev, \.tabNext)
        c.isTabFocus = false
        tabBarSetEnabled(c, false)
        tabMemberCount -= 1
        clientUpdateVisibility(c)
    }

    func tabLayoutIdSupported(_ id: LayoutKind) -> Bool {
        if id == .monocle { return config.monocleTabMode }
        if id == .deck || id == .verticalDeck { return config.deckTabMode }
        return false
    }

    private func tabLayoutEnabled(_ m: Monitor?) -> Bool {
        guard let m else { return false }
        return tabLayoutIdSupported(m.pertag.ltidxs[getMonCurtag(m)])
    }

    func tabLayoutActive(_ m: Monitor?) -> Bool {
        guard let m else { return false }
        return !m.isoverview && tabLayoutEnabled(m)
    }

    private func tabStateOk(_ c: Client) -> Bool {
        if c.mon == nil || c.iskilling || c.isminimized { return false }
        if c.isfloating || c.isunglobal || c.isInScratchpad { return false }
        return true
    }

    private func tabIsStackCandidate(_ m: Monitor, _ target: Client) -> Bool {
        let id = m.pertag.ltidxs[getMonCurtag(m)]
        if id == .monocle { return true }
        if id != .deck && id != .verticalDeck { return false }
        return !target.ismaster
    }

    private func tabMemberKept(_ m: Monitor, _ cur: UInt32, _ c: Client) -> Bool {
        tabLayoutEnabled(m) && (c.tags & cur) != 0 && tabStateOk(c) && tabIsStackCandidate(m, c)
    }

    private func tabMemberInView(_ c: Client?, _ m: Monitor?) -> Bool {
        guard let c, let m else { return false }
        return c.mon === m && !m.isoverview && VISIBLEON(c, m)
    }

    private func tabFocusCanRender(_ c: Client?) -> Bool {
        guard let c else { return false }
        return !c.isfullscreen && !c.ismaximizescreen
    }

    private func tabRefreshBars(_ head: Client) {
        var members: Int32 = 0
        var focus = head

        var it: Client? = head
        while let x = it {
            if x.isTabFocus { focus = x }
            if tabMemberInView(x, head.mon) { members += 1 }
            it = x.tabNext
        }

        let stacked = members >= 2
        let strip = stacked && tabFocusCanRender(focus)
        // not in mango: no layer to reparent the bars to (the port places them)

        it = head
        while let x = it {
            let inView = tabMemberInView(x, head.mon)
            if inView { x.isTabHidden = stacked && !x.isTabFocus }
            tabBarSetEnabled(x, strip && inView)
            clientUpdateVisibility(x)
            it = x.tabNext
        }
    }

    // not in mango: tab_update_input_penetration (the port's bars take clicks only where drawn)

    func tabSyncFocus(_ c: Client?) {
        guard let c, tabIsMember(c), !c.isTabFocus else { return }

        let head = tabHead(c)
        var it: Client? = head
        while let x = it {
            x.isTabFocus = x === c
            it = x.tabNext
        }

        tabRefreshBars(head)
    }

    func tabDetachClient(_ c: Client) {
        if !tabIsMember(c) { return }

        let head = tabHead(c)
        let next = c.tabNext

        tabLeave(c)

        guard let rest = head === c ? next : head else { return }

        if rest.tabNext == nil {
            tabLeave(rest)
            return
        }

        tabChainFocus(rest)
        tabRefreshBars(rest)
    }

    func tabReplaceClient(_ old: Client, _ new: Client) {
        if !tabIsMember(old) { return }

        let wasFocus = old.isTabFocus
        let wasHidden = old.isTabHidden

        if tabIsMember(new) {
            if tabHead(new) === tabHead(old) {
                tabDetachClient(old)
                if wasFocus { tabSyncFocus(new) }
                return
            }
            tabLeave(new)
        }

        new.tabPrev = old.tabPrev
        new.tabNext = old.tabNext
        old.tabPrev?.tabNext = new
        old.tabNext?.tabPrev = new

        old.tabPrev = nil
        old.tabNext = nil
        old.isTabFocus = false
        old.isTabHidden = false
        tabBarSetEnabled(old, false)

        new.isTabFocus = wasFocus
        new.isTabHidden = wasHidden
    }

    func tabSyncMonitor(_ m: Monitor) {
        if m.isoverview { return }

        if !tabLayoutEnabled(m) && tabMemberCount == 0 { return }

        let cur = m.tagset[m.seltags]
        let canMerge = tabLayoutEnabled(m)

        for c in clients {
            if !tabIsMember(c) || c.mon !== m { continue }
            if tabMemberKept(m, cur, c) { continue }
            tabDetachClient(c)
        }

        var head: Client?, tail: Client?
        for c in clients {
            if c.mon !== m || (c.tags & cur) == 0 { continue }
            if !tabIsMember(c) {
                if c.isTabHidden {
                    c.isTabHidden = false
                    clientUpdateVisibility(c)
                }
                if !canMerge { continue }
                if !tabStateOk(c) || !tabIsStackCandidate(m, c) { continue }
                tabMemberCount += 1
            }

            if tabIsMember(c) { clientChainUnlink(c, \.tabPrev, \.tabNext) }

            c.tabPrev = tail
            c.tabNext = nil
            if let tail {
                tail.tabNext = c
            } else {
                head = c
            }
            tail = c
        }

        guard let head, head.tabNext != nil else {
            if head != nil { tabMemberCount -= 1 }
            return
        }

        tabChainFocus(head)
        tabRefreshBars(head)
    }

    func tabFocusMember(_ c: Client) {
        guard tabIsMember(c), let m = c.mon else { return }

        clientFocus(c, true)
        arrange(m, false, false)
    }

    func clientRaiseTab(_ c: Client) {
        guard c.mon != nil, tabIsMember(c) else { return }

        let head = tabHead(c)

        var it: Client? = head
        while let x = it {
            if x !== c && clientTargetLayer(x) == clientTargetLayer(c) {
                system.raise(c)   // not in mango: wlr_scene_node_place_above, the port's restack
            }
            // not in mango: the tab bar is raised by the port's restack
            it = x.tabNext
        }
    }

    // not in mango: client_reparent_tab, client_add_tab_bar, client_remove_tab_bar,
    // client_update_tab_bar_title, client_set_tab_bar_config and global_draw_tab_bar
    // (the port draws the bars, with their titles, from client_draw_tabbar's strip)

    // not in mango: returns the strip for the port to draw instead of placing the bar nodes
    func clientDrawTabbar(_ c: Client, _ offsets: IVec2) -> TabStrip? {
        guard let m = c.mon, c.isTabFocus else { return nil }

        let head = tabHead(c)

        if !tabLayoutActive(m) || !tabFocusCanRender(c) {
            var it: Client? = head
            while let x = it {
                tabBarSetEnabled(x, false)
                it = x.tabNext
            }
            return nil
        }

        var members: [Client] = []   // not in mango: the members in view, counted
        var it: Client? = head
        while let x = it {
            if tabMemberInView(x, m) { members.append(x) }
            it = x.tabNext
        }
        let count = members.count

        if count < 2 { return nil }
        guard c.tabBarEnabled else { return nil }   // not in mango: a disabled node is not drawn

        var anchor = c.animation.current
        if c.animation.running && c.animation.action == .open {
            anchor = c.geom
        }
        // Port extension: not in mango. The bars inside the border (chutney_macos_appearance).
        let ported = barsInsideBorder
        if ported { anchor = anchor.insetBy(dx: borderWidth(c, on: m), dy: borderWidth(c, on: m)) }
        let groupH = clientWantsGroupBar(c) ? CGFloat(config.groupBarHeight) : 0
        /* Tab strip sits above the group strip when both are present. */
        let h = CGFloat(config.tabBarHeight)
        let bar = clipBar(anchor, y: anchor.minY - h - groupH, height: h, offsets, on: m)

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
}
