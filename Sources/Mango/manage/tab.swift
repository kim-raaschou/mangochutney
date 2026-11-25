import CoreGraphics

package final class TagTabNode {
    var prev: TagTabNode?
    var next: TagTabNode?
    var allNext: TagTabNode?
    var client: Client
    init(client: Client) { self.client = client }
}

package final class TagTabState {
    var head: TagTabNode?
    var tail: TagTabNode?
    var allFirst: TagTabNode?
    var focusId: ClientID = 0
    var count: Int32 = 0
}

package extension MangoServer {
    private func tabHead(_ c: Client) -> Client {
        clientChainHead(c, \.tabPrev)
    }

    func tabGetAdjacentMember(_ c: Client?, _ next: Bool) -> Client? {
        guard let c, c.tabPrev != nil || c.tabNext != nil else { return nil }

        if let target = next ? c.tabNext : c.tabPrev { return target }

        var target = c
        if next {
            while let p = target.tabPrev { target = p }
        } else {
            while let n = target.tabNext { target = n }
        }
        return target !== c ? target : nil
    }

    func tabIsMember(_ c: Client?) -> Bool {
        guard let c else { return false }
        return c.tabPrev != nil || c.tabNext != nil
    }

    private func tabBarSetEnabled(_ c: Client, _ on: Bool) {
        // not in mango: the port draws the bar of a client whose tab_bar node is enabled
        c.tabBarEnabled = on
    }

    private func tabLayoutEnabledForTag(_ m: Monitor?, _ tag: UInt32) -> Bool {
        guard let m, tag < PERTAG_SLOTS else { return false }
        let id = m.pertag.ltidxs[tag]
        if id == .monocle { return config.monocleTabMode }
        if id == .deck || id == .verticalDeck { return config.deckTabMode }
        return false
    }

    private func isTabLayout(_ m: Monitor?) -> Bool {
        guard let m else { return false }
        return tabLayoutEnabledForTag(m, getMonCurtag(m))
    }

    func tabLayoutActive(_ m: Monitor?) -> Bool {
        guard let m else { return false }
        return !m.isoverview && isTabLayout(m)
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

    private func tabClientInState(_ m: Monitor, _ c: Client?) -> Bool {
        guard let c else { return false }
        return VISIBLEON(c, m) && tabStateOk(c) && tabIsStackCandidate(m, c)
    }

    private func tabMemberInView(_ c: Client?, _ m: Monitor?) -> Bool {
        guard let c, let m else { return false }
        return c.mon === m && !m.isoverview && VISIBLEON(c, m)
    }

    private func tabFocusCanRender(_ c: Client?) -> Bool {
        guard let c else { return false }
        return !c.isfullscreen && !c.ismaximizescreen
    }

    private func ensureTabState(_ m: Monitor?, _ tag: UInt32) -> TagTabState? {
        guard let m, tag < PERTAG_SLOTS else { return nil }
        if m.pertag.tabState[tag] == nil {
            m.pertag.tabState[tag] = TagTabState()
        }
        return m.pertag.tabState[tag]
    }

    // not in mango: clear_tab_state frees the nodes; ARC does (docs/afvigelser.md §5)

    private func findTabNode(_ state: TagTabState?, _ client: Client?) -> TagTabNode? {
        guard let state, let client else { return nil }
        var node = state.allFirst
        while let n = node {
            if n.client === client { return n }
            node = n.allNext
        }
        return nil
    }

    private func tabNodeCreate(_ state: TagTabState, _ client: Client) -> TagTabNode {
        let node = TagTabNode(client: client)
        node.allNext = state.allFirst
        state.allFirst = node
        state.count += 1
        return node
    }

    private func tabNodeAppend(_ state: TagTabState, _ node: TagTabNode) {
        node.prev = state.tail
        node.next = nil
        if let tail = state.tail {
            tail.next = node
        } else {
            state.head = node
        }
        state.tail = node
    }

    private func tabNodeRemove(_ state: TagTabState?, _ node: TagTabNode?) {
        guard let state, let node else { return }

        if let prev = node.prev {
            prev.next = node.next
        } else if state.head === node {
            state.head = node.next
        }
        if let next = node.next {
            next.prev = node.prev
        } else if state.tail === node {
            state.tail = node.prev
        }
        if state.count > 0 { state.count -= 1 }
        if state.focusId == node.client.id { state.focusId = 0 }

        if state.allFirst === node {
            state.allFirst = node.allNext
        } else {
            var link = state.allFirst
            while let l = link, l.allNext !== node { link = l.allNext }
            link?.allNext = node.allNext
        }
    }

    private func clearTabProjection(_ m: Monitor) {
        for c in clients {
            if c.mon !== m { continue }
            // not in mango: no workspace overview (wsov_hidden)
            let wasHidden = c.isTabHidden
            c.tabPrev = nil
            c.tabNext = nil
            c.isTabFocus = false
            c.isTabHidden = false
            tabBarSetEnabled(c, false)
            if wasHidden { clientUpdateVisibility(c) }
        }
    }

    private func updateTabState(_ m: Monitor) {
        let tag = getMonCurtag(m)
        guard let state = ensureTabState(m, tag) else { return }

        var node = state.allFirst
        while let n = node {
            let next = n.allNext
            if !tabClientInState(m, n.client) { tabNodeRemove(state, n) }
            node = next
        }

        for c in clients {
            if !tabClientInState(m, c) { continue }
            if findTabNode(state, c) == nil {
                tabNodeAppend(state, tabNodeCreate(state, c))
            }
        }
    }

    private func getTabStateFocus(_ m: Monitor, _ state: TagTabState) -> Client? {
        var selected: Client?
        var remembered: Client?
        var fallback: Client?

        var node = state.head
        while let n = node {
            node = n.next
            if n.client.mon !== m { continue }
            if fallback == nil { fallback = n.client }
            if n.client === m.sel && n.client.isfocusing { selected = n.client }
            if state.focusId != 0 && n.client.id == state.focusId { remembered = n.client }
        }

        let focus = selected ?? remembered ?? fallback
        if focus == nil { state.focusId = 0 }
        return focus
    }

    func tabClientHiddenOnTag(_ m: Monitor?, _ tag: UInt32, _ c: Client?) -> Bool {
        guard let m, tag != 0, tag < PERTAG_SLOTS, let c, c.mon === m, tabLayoutEnabledForTag(m, tag) else {
            return false
        }

        guard let state = m.pertag.tabState[tag], state.count >= 2, state.focusId != 0,
              state.focusId != c.id, tabStateOk(c), !c.isglobal else { return false }

        let layoutId = m.pertag.ltidxs[tag]
        if (layoutId == .deck || layoutId == .verticalDeck) && c.ismaster { return false }
        let bit: UInt32 = 1 << (tag - 1)
        return c.tags & bit != 0
    }

    private func tabRefreshBars(_ head: Client?) {
        guard let head, head.mon != nil else { return }

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

    private func syncTabStateToClients(_ m: Monitor, _ tag: UInt32) {
        let state = m.pertag.tabState[tag]
        clearTabProjection(m)
        guard let state else { return }

        let focus = getTabStateFocus(m, state)
        if let focus { state.focusId = focus.id }

        var head: Client?
        var tail: Client?
        var count: Int32 = 0
        var node = state.head
        while let n = node {
            node = n.next
            let c = n.client
            if c.mon !== m { continue }
            if head == nil { head = c }
            c.tabPrev = tail
            c.tabNext = nil
            tail?.tabNext = c
            c.isTabFocus = c === focus
            c.isTabHidden = false
            tail = c
            count += 1
        }

        if count >= 2 { tabRefreshBars(head) }
    }

    func tabSyncCurrent(_ m: Monitor?) {
        guard let m else { return }
        if !isTabLayout(m) {
            clearTabProjection(m)
            return
        }
        let tag = getMonCurtag(m)
        syncTabStateToClients(m, tag)
    }

    // not in mango: tab_update_input_penetration (the port's bars take clicks only where drawn)

    func tabSyncFocus(_ c: Client?) {
        guard let c, let m = c.mon else { return }
        let tag = getMonCurtag(m)
        guard let state = ensureTabState(m, tag), findTabNode(state, c) != nil else { return }
        state.focusId = c.id
        if !tabIsMember(c) || c.isTabFocus { return }

        let head = tabHead(c)
        var it: Client? = head
        while let x = it {
            x.isTabFocus = x === c
            it = x.tabNext
        }

        tabRefreshBars(head)
    }

    @discardableResult
    func tabRemoveClientInTag(_ m: Monitor, _ tag: UInt32, _ c: Client) -> Bool {
        let state = m.pertag.tabState[tag]
        var changed = false
        while let node = findTabNode(state, c) {
            tabNodeRemove(state, node)
            changed = true
        }
        return changed
    }

    @discardableResult
    func tabReplaceClientInTag(_ m: Monitor, _ tag: UInt32, _ old: Client, _ new: Client) -> Bool {
        if old === new { return false }
        guard let state = m.pertag.tabState[tag] else { return false }
        guard let oldNode = findTabNode(state, old) else { return false }
        if let newNode = findTabNode(state, new), newNode !== oldNode {
            tabNodeRemove(state, newNode)
        }
        if state.focusId == old.id { state.focusId = new.id }
        oldNode.client = new
        while let node = findTabNode(state, old) {
            tabNodeRemove(state, node)
        }
        return true
    }

    func tabSyncMonitor(_ m: Monitor) {
        // not in mango: no wlr_output->enabled or iscleanuping; the port's monitors are enabled
        if m.isoverview { return }

        if !isTabLayout(m) {
            clearTabProjection(m)
            return
        }

        let tag = getMonCurtag(m)
        updateTabState(m)
        syncTabStateToClients(m, tag)
    }

    func cleanupMonitorTab(_ m: Monitor) {
        for tag in 0..<PERTAG_SLOTS {
            m.pertag.tabState[tag] = nil
        }
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
                .init(id: cur.windowID, title: cur.title.isEmpty ? cur.appName : cur.title, focused: cur.isTabFocus,
                      pid: cur.pid, frame: box)
            },
            above: c.windowID, plain: !ported)
    }
}
