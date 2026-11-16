import CoreGraphics

/// mango struct ScrollerStackNode (layout/scroll.h).
package final class ScrollerStackNode {
    package var client: Client
    package var scrollerProportion: Float = 0
    package var scrollerStackProportion: Float = 0
    package var scrollerStackWeight: Float = 0
    package var scrollerProportionSingle: Float = 0

    package var nextInStack: ScrollerStackNode?
    package weak var prevInStack: ScrollerStackNode?
    package var allNext: ScrollerStackNode?

    init(client: Client) { self.client = client }
}

/// mango struct TagScrollerState (layout/scroll.h).
package final class TagScrollerState {
    package var allFirst: ScrollerStackNode? /* Singly linked list head for all nodes. */
    package var count: Int32 = 0
}

package extension MangoServer {
    /* Gets or creates the scroller state for a given tag of the specified monitor.
     */
    @discardableResult
    func ensureScrollerState(_ m: Monitor, _ tag: UInt32) -> TagScrollerState {
        if m.pertag.scrollerState[tag] == nil {
            let st = TagScrollerState()
            m.pertag.scrollerState[tag] = st
        }
        return m.pertag.scrollerState[tag]!
    }

    /* Finds the node for a client in the tag state (returns NULL if absent). */
    func findScrollerNode(_ st: TagScrollerState?, _ c: Client) -> ScrollerStackNode? {
        guard let st else { return nil }
        var n = st.allFirst
        while let node = n {
            if node.client === c { return node }
            n = node.allNext
        }
        return nil
    }

    /* Creates a new node and inserts it into the tag state all list. */
    @discardableResult
    func scrollerNodeCreate(_ st: TagScrollerState, _ c: Client) -> ScrollerStackNode {
        let n = ScrollerStackNode(client: c)
        n.scrollerProportion = c.scrollerProportion
        n.scrollerStackWeight = c.scrollerStackProportion
        n.scrollerProportionSingle = c.scrollerProportionSingle
        n.nextInStack = nil
        n.prevInStack = nil
        n.allNext = st.allFirst
        st.allFirst = n
        st.count += 1
        return n
    }

    func scrollerNodeRemove(_ st: TagScrollerState?, _ target: ScrollerStackNode?) {
        guard let st, let target else { return }

        /* Saves the neighbours. */
        let prev = target.prevInStack
        let next = target.nextInStack

        /* Unlinks from the stack list. */
        if let prev { prev.nextInStack = next }
        if let next { next.prevInStack = prev }

        /* Unlinks from the all list. */
        if st.allFirst === target {
            st.allFirst = target.allNext
            st.count -= 1
        } else {
            var indirect = st.allFirst
            while let n = indirect, n.allNext !== target { indirect = n.allNext }
            if let n = indirect {
                n.allNext = target.allNext
                st.count -= 1
            }
        }
        target.nextInStack = nil
        target.prevInStack = nil
        target.allNext = nil
    }

    /* Clears all scroller state for a tag. */
    func clearScrollerState(_ st: TagScrollerState?) {
        guard let st else { return }
        var n = st.allFirst
        while let node = n {
            let next = node.allNext
            node.nextInStack = nil
            node.allNext = nil
            n = next
        }
        st.allFirst = nil
        st.count = 0
    }

    /* Cleans up scroller state of all tags when a Monitor is destroyed. */
    func cleanupMonitorScroller(_ m: Monitor) {
        for t in 0..<UInt32(PERTAG_SLOTS) {
            if m.pertag.scrollerState[t] != nil {
                clearScrollerState(m.pertag.scrollerState[t])
                m.pertag.scrollerState[t] = nil
            }
        }
    }

    /* Syncs a tag state back to the global fields of all clients. */
    func syncScrollerStateToClients(_ m: Monitor, _ tag: UInt32) {
        guard let st = m.pertag.scrollerState[tag] else { return }
        var n = st.allFirst
        while let node = n {
            let c = node.client
            c.scrollerProportion = node.scrollerProportion
            c.scrollerStackProportion = node.scrollerStackWeight
            c.scrollerProportionSingle = node.scrollerProportionSingle
            n = node.allNext
        }
    }

    func verticalScrollAdjustFullandmax(_ c: Client, _ targetGeom: inout CGRect) {
        guard let m = c.mon else { return }
        let w = WBox(m.screen.workArea), mm = WBox(m.screen.frame)
        var curGappiv: Int32 = enableGaps ? m.gappiv : 0
        var curGappov: Int32 = enableGaps ? m.gappov : 0
        var curGappoh: Int32 = enableGaps ? m.gappoh : 0

        curGappiv = config.smartgaps && m.visibleScrollTilingClients == 1 ? 0 : curGappiv
        curGappov = config.smartgaps && m.visibleScrollTilingClients == 1 ? 0 : curGappov
        curGappoh = config.smartgaps && m.visibleScrollTilingClients == 1 ? 0 : curGappoh
        _ = curGappiv

        if c.isfullscreen {
            targetGeom.size.width = CGFloat(mm.width)
            targetGeom.size.height = CGFloat(mm.height)
            targetGeom.origin.x = CGFloat(mm.x)
            return
        }

        if c.ismaximizescreen {
            targetGeom.size.width = CGFloat(w.width - 2 * curGappoh)
            targetGeom.size.height = CGFloat(w.height - 2 * curGappov)
            targetGeom.origin.x = CGFloat(w.x + curGappoh)
            return
        }

        targetGeom.size.width = CGFloat(w.width - 2 * curGappoh)
        targetGeom.origin.x = CGFloat(w.x + (w.width - Int32(targetGeom.width)) / 2)
    }

    func verticalCheckScrollerRootInsideMon(_ c: Client?, _ geometry: inout CGRect) {
        guard let c, let m = c.mon else { return }
        if !GEOMINSIDEMON(geometry, m) {
            let w = WBox(m.screen.workArea)
            geometry.origin.y = CGFloat(w.y + (w.height - Int32(geometry.height)) / 2)
        }
    }

    func horizontalScrollAdjustFullandmax(_ c: Client, _ targetGeom: inout CGRect) {
        guard let m = c.mon else { return }
        let w = WBox(m.screen.workArea), mm = WBox(m.screen.frame)
        var curGappih: Int32 = enableGaps ? m.gappih : 0
        var curGappoh: Int32 = enableGaps ? m.gappoh : 0
        var curGappov: Int32 = enableGaps ? m.gappov : 0

        curGappih = config.smartgaps && m.visibleScrollTilingClients == 1 ? 0 : curGappih
        curGappoh = config.smartgaps && m.visibleScrollTilingClients == 1 ? 0 : curGappoh
        curGappov = config.smartgaps && m.visibleScrollTilingClients == 1 ? 0 : curGappov
        _ = curGappih

        if c.isfullscreen {
            targetGeom.size.height = CGFloat(mm.height)
            targetGeom.size.width = CGFloat(mm.width)
            targetGeom.origin.y = CGFloat(mm.y)
            return
        }

        if c.ismaximizescreen {
            targetGeom.size.height = CGFloat(w.height - 2 * curGappov)
            targetGeom.size.width = CGFloat(w.width - 2 * curGappoh)
            targetGeom.origin.y = CGFloat(w.y + curGappov)
            return
        }

        targetGeom.size.height = CGFloat(w.height - 2 * curGappov)
        targetGeom.origin.y = CGFloat(w.y + (w.height - Int32(targetGeom.height)) / 2)
    }

    func horizontalCheckScrollerRootInsideMon(_ c: Client?, _ geometry: inout CGRect) {
        guard let c, let m = c.mon else { return }
        if !GEOMINSIDEMON(geometry, m) {
            let w = WBox(m.screen.workArea)
            geometry.origin.x = CGFloat(w.x + (w.width - Int32(geometry.width)) / 2)
        }
    }

    /* scroller_stack_proportion = scroller_stack_weight / total weight. Nodes with
     * no weight yet get an equal share; positive weights are never rewritten. */
    private func scrollerNormalizeStackWeights(_ head: ScrollerStackNode?) {
        var iter = head
        var totalWeight: Float = 0.0
        var counted: Int32 = 0

        while let n = iter {
            if n.scrollerStackWeight > 0.0 {
                totalWeight += n.scrollerStackWeight
                counted += 1
            }
            iter = n.nextInStack
        }

        if totalWeight <= 0.0 {
            iter = head
            while let n = iter {
                n.scrollerStackWeight = 1.0
                totalWeight += 1.0
                iter = n.nextInStack
            }
        } else {
            let average = totalWeight / Float(counted)
            iter = head
            while let n = iter {
                if n.scrollerStackWeight <= 0.0 {
                    n.scrollerStackWeight = average
                    totalWeight += average
                }
                iter = n.nextInStack
            }
        }

        iter = head
        while let n = iter {
            n.scrollerStackProportion = n.scrollerStackWeight / totalWeight
            iter = n.nextInStack
        }
    }

    func scrollerArrangeStackNode(_ head: ScrollerStackNode?, _ geometry: CGRect, _ gappiv: Int32,
                                  _ ctx: LayoutContext?) {
        var stackSize: Int32 = 0
        var iter = head
        while let n = iter {
            stackSize += 1
            iter = n.nextInStack
        }
        if stackSize == 0 { return }

        /* Normalized ratio. */
        scrollerNormalizeStackWeights(head)

        /* Vertical arrangement (horizontal stack). */
        var clientHeight: Int32
        var currentY = Int32(geometry.minY)
        var remainClientHeight = Int32(geometry.height) - (stackSize - 1) * gappiv
        var remainProportion: Float = 1.0

        iter = head
        while let n = iter {
            clientHeight = i32(Float(remainClientHeight) * (n.scrollerStackProportion / remainProportion))
            let clientGeom = wlrBox(Int32(geometry.minX), currentY, Int32(geometry.width), clientHeight)
            clientTileResize(n.client, clientGeom, false, ctx)
            remainProportion -= n.scrollerStackProportion
            remainClientHeight -= clientHeight
            currentY += clientHeight + gappiv
            iter = n.nextInStack
        }
    }

    func scrollerArrangeStackVerticalNode(_ head: ScrollerStackNode?, _ geometry: CGRect, _ gappih: Int32,
                                          _ ctx: LayoutContext?) {
        var stackSize: Int32 = 0
        var iter = head
        while let n = iter {
            stackSize += 1
            iter = n.nextInStack
        }
        if stackSize == 0 { return }

        /* Normalized ratio. */
        scrollerNormalizeStackWeights(head)

        /* Horizontal arrangement (vertical stack). */
        var clientWidth: Int32
        var currentX = Int32(geometry.minX)
        var remainClientWidth = Int32(geometry.width) - (stackSize - 1) * gappih
        var remainProportion: Float = 1.0

        iter = head
        while let n = iter {
            clientWidth = i32(Float(remainClientWidth) * (n.scrollerStackProportion / remainProportion))
            let clientGeom = wlrBox(currentX, Int32(geometry.minY), clientWidth, Int32(geometry.height))
            clientTileResize(n.client, clientGeom, false, ctx)
            remainProportion -= n.scrollerStackProportion
            remainClientWidth -= clientWidth
            currentX += clientWidth + gappih
            iter = n.nextInStack
        }
    }

    /// not in mango: the stack heads of the visible scroll-tiled clients, in client list order
    /// (scroller_core's two passes over server.clients)
    private func scrollerHeads(_ m: Monitor, _ st: TagScrollerState) -> [ScrollerStackNode] {
        var heads: [ScrollerStackNode] = []
        for c in clients where VISIBLEON(c, m) && ISSCROLLTILED(c) {
            if let node = findScrollerNode(st, c), node.prevInStack == nil {
                if !heads.contains(where: { $0 === node }) { heads.append(node) }
            }
        }
        return heads
    }

    private func scrollerCore(_ m: Monitor, _ ctx: LayoutContext?) {
        let tag = getMonCurtag(m)
        let st = ensureScrollerState(m, tag)
        let scrollerDefaultProportionSingle = m.pertag.scrollerDefaultProportionSingle[tag]
        let scrollerIgnoreProportionSingle = m.pertag.scrollerIgnoreProportionSingle[tag]
        let w = WBox(m.screen.workArea), mm = WBox(m.screen.frame)
        let structs = Int32(config.scrollerStructs)

        /* Collects all stack heads in global client list order to keep the visual
         * order correct. */
        let heads = scrollerHeads(m, st)
        let nHeads = Int32(heads.count)

        if nHeads == 0 {
            syncScrollerStateToClients(m, tag)
            return
        }

        m.visibleScrollTilingClients = nHeads

        var curGappih: Int32 = enableGaps ? m.gappih : 0
        var curGappoh: Int32 = enableGaps ? m.gappoh : 0
        var curGappov: Int32 = enableGaps ? m.gappov : 0
        let curGappiv: Int32 = enableGaps ? m.gappiv : 0
        if config.smartgaps && nHeads == 1 {
            curGappih = 0; curGappoh = 0; curGappov = 0
        }
        let maxClientWidth = w.width - 2 * structs - curGappih

        /* Single-client special case. */
        if nHeads == 1 && !scrollerIgnoreProportionSingle && !heads[0].client.isfullscreen
            && !heads[0].client.ismaximizescreen {
            let head = heads[0]
            let singleProportion = head.scrollerProportionSingle > 0.0
                ? head.scrollerProportionSingle : scrollerDefaultProportionSingle
            var targetGeom = CGRect.zero
            targetGeom.size.height = CGFloat(w.height - 2 * curGappov)
            targetGeom.size.width = CGFloat(i32(Float(w.width - 2 * curGappoh) * singleProportion))
            targetGeom.origin.x = CGFloat(w.x + (w.width - Int32(targetGeom.width)) / 2)
            targetGeom.origin.y = CGFloat(w.y + (w.height - Int32(targetGeom.height)) / 2)
            horizontalCheckScrollerRootInsideMon(head.client, &targetGeom)
            scrollerArrangeStackNode(head, targetGeom, curGappiv, ctx)
            syncScrollerStateToClients(m, tag)
            return
        }

        let sel = m.sel.flatMap { clientByIdAll($0) }
        let prevsel = m.prevsel.flatMap { clientByIdAll($0) }
        var rootNode: ScrollerStackNode?
        if let sel, ISSCROLLTILED(sel) {
            rootNode = findScrollerNode(st, sel)
            while let p = rootNode?.prevInStack { rootNode = p }
        }
        if rootNode == nil, let prevsel, ISSCROLLTILED(prevsel) {
            rootNode = findScrollerNode(st, prevsel)
            while let p = rootNode?.prevInStack { rootNode = p }
        }
        if rootNode == nil {
            rootNode = heads[Int(nHeads / 2)] /* Simple fallback. */
        }

        var focusIndex: Int32 = -1
        for i in 0..<Int(nHeads) where heads[i] === rootNode {
            focusIndex = Int32(i)
            break
        }
        if focusIndex < 0 { focusIndex = nHeads / 2 }
        let fi = Int(focusIndex)

        /* Decides whether scrolling, overspread, or centering is needed. */
        var needScroller = false
        var overOverspreadToLeft = false
        let rootClient = rootNode!.client
        let rg = WBox(rootClient.geom)

        if rg.x >= w.x + structs && rg.x + rg.width <= w.x + w.width - structs {
            needScroller = false
        } else {
            needScroller = true
        }

        var needApplyOverspread = config.scrollerPreferOverspread && nHeads > 1
            && (focusIndex == 0 || focusIndex == nHeads - 1) && heads[fi].scrollerProportion < 1.0

        if needApplyOverspread {
            if focusIndex == 0 {
                overOverspreadToLeft = true
            } else {
                overOverspreadToLeft = false
            }
            if overOverspreadToLeft
                && (!INSIDEMON(heads[1].client) || heads[1].scrollerProportion + heads[0].scrollerProportion >= 1.0) {
                needScroller = true
            } else if !overOverspreadToLeft
                && (!INSIDEMON(heads[fi - 1].client)
                    || heads[fi - 1].scrollerProportion + heads[fi].scrollerProportion >= 1.0) {
                needScroller = true
            } else {
                needApplyOverspread = false
            }
        }

        var prevselClause = prevsel == nil
        if let prevsel {
            prevselClause = ISSCROLLTILED(prevsel)
                && (prevsel.scrollerProportion * Float(maxClientWidth)) + (heads[fi].scrollerProportion * Float(maxClientWidth))
                > Float(w.width - 2 * structs - curGappih)
        }
        let needApplyCenter = config.scrollerFocusCenter || nHeads == 1
            || (config.scrollerPreferCenter && !needApplyOverspread && prevselClause)

        if nHeads == 1 && scrollerIgnoreProportionSingle {
            needScroller = true
        }
        if startDragWindow { needScroller = false }

        var targetGeom = CGRect.zero
        targetGeom.size.height = CGFloat(w.height - 2 * curGappov)
        targetGeom.size.width = CGFloat(i32(Float(maxClientWidth) * heads[fi].scrollerProportion))
        targetGeom.origin.y = CGFloat(w.y + (w.height - Int32(targetGeom.height)) / 2)
        horizontalScrollAdjustFullandmax(heads[fi].client, &targetGeom)

        if heads[fi].client.isfullscreen {
            targetGeom.origin.x = CGFloat(mm.x)
            horizontalCheckScrollerRootInsideMon(heads[fi].client, &targetGeom)
            scrollerArrangeStackNode(heads[fi], targetGeom, curGappiv, ctx)
        } else if heads[fi].client.ismaximizescreen {
            targetGeom.origin.x = CGFloat(w.x + curGappoh)
            horizontalCheckScrollerRootInsideMon(heads[fi].client, &targetGeom)
            scrollerArrangeStackNode(heads[fi], targetGeom, curGappiv, ctx)
        } else if needScroller {
            if needApplyCenter {
                targetGeom.origin.x = CGFloat(w.x + (w.width - Int32(targetGeom.width)) / 2)
            } else if needApplyOverspread {
                if overOverspreadToLeft {
                    targetGeom.origin.x = CGFloat(w.x + structs)
                } else {
                    targetGeom.origin.x = CGFloat(i32(Float(w.x) + (Float(w.width)
                        - heads[fi].scrollerProportion * Float(maxClientWidth) - Float(structs))))
                }
            } else {
                targetGeom.origin.x = rg.x > w.x + w.width / 2
                    ? CGFloat(i32(Float(w.x) + (Float(w.width)
                        - heads[fi].scrollerProportion * Float(maxClientWidth) - Float(structs))))
                    : CGFloat(w.x + structs)
            }
            horizontalCheckScrollerRootInsideMon(heads[fi].client, &targetGeom)
            scrollerArrangeStackNode(heads[fi], targetGeom, curGappiv, ctx)
        } else {
            targetGeom.origin.x = CGFloat(rg.x)
            horizontalCheckScrollerRootInsideMon(heads[fi].client, &targetGeom)
            scrollerArrangeStackNode(heads[fi], targetGeom, curGappiv, ctx)
        }

        /* Arranges the left stack. */
        if fi >= 1 {
            for i in 1...fi {
                let cur = heads[fi - i]
                var leftGeom = CGRect.zero
                leftGeom.size.height = CGFloat(w.height - 2 * curGappov)
                leftGeom.size.width = CGFloat(i32(Float(maxClientWidth) * cur.scrollerProportion))
                horizontalScrollAdjustFullandmax(cur.client, &leftGeom)
                leftGeom.origin.x = CGFloat(Int32(heads[fi - i + 1].client.geom.minX) - curGappih - Int32(leftGeom.width))
                scrollerArrangeStackNode(cur, leftGeom, curGappiv, ctx)
            }
        }

        /* Arranges the right stack. */
        if Int(nHeads) - fi > 1 {
            for i in 1..<(Int(nHeads) - fi) {
                let cur = heads[fi + i]
                var rightGeom = CGRect.zero
                rightGeom.size.height = CGFloat(w.height - 2 * curGappov)
                rightGeom.size.width = CGFloat(i32(Float(maxClientWidth) * cur.scrollerProportion))
                horizontalScrollAdjustFullandmax(cur.client, &rightGeom)
                let prev = WBox(heads[fi + i - 1].client.geom)
                rightGeom.origin.x = CGFloat(prev.x + curGappih + prev.width)
                scrollerArrangeStackNode(cur, rightGeom, curGappiv, ctx)
            }
        }

        syncScrollerStateToClients(m, tag)
    }

    private func verticalScrollerCore(_ m: Monitor, _ ctx: LayoutContext?) {
        let tag = getMonCurtag(m)
        var barHeight: Int32 = 0
        let st = ensureScrollerState(m, tag)
        let scrollerDefaultProportionSingle = m.pertag.scrollerDefaultProportionSingle[tag]
        let scrollerIgnoreProportionSingle = m.pertag.scrollerIgnoreProportionSingle[tag]
        let w = WBox(m.screen.workArea), mm = WBox(m.screen.frame)
        let structs = Int32(config.scrollerStructs)

        /* Collects stack heads in global order. */
        let heads = scrollerHeads(m, st)
        let nHeads = Int32(heads.count)

        if nHeads == 0 {
            syncScrollerStateToClients(m, tag)
            return
        }

        m.visibleScrollTilingClients = nHeads

        var curGappiv: Int32 = enableGaps ? m.gappiv : 0
        var curGappov: Int32 = enableGaps ? m.gappov : 0
        var curGappoh: Int32 = enableGaps ? m.gappoh : 0
        let curGappih: Int32 = enableGaps ? m.gappih : 0
        if config.smartgaps && nHeads == 1 {
            curGappiv = 0; curGappov = 0; curGappoh = 0
        }
        let maxClientHeight = w.height - 2 * structs - curGappiv

        if nHeads == 1 && !scrollerIgnoreProportionSingle && !heads[0].client.isfullscreen
            && !heads[0].client.ismaximizescreen {
            let head = heads[0]
            let singleProportion = head.scrollerProportionSingle > 0.0
                ? head.scrollerProportionSingle : scrollerDefaultProportionSingle
            var targetGeom = CGRect.zero
            targetGeom.size.width = CGFloat(w.width - 2 * curGappoh)
            targetGeom.size.height = CGFloat(i32(Float(w.height - 2 * curGappov) * singleProportion))
            targetGeom.origin.y = CGFloat(w.y + (w.height - Int32(targetGeom.height)) / 2)
            targetGeom.origin.x = CGFloat(w.x + (w.width - Int32(targetGeom.width)) / 2)
            verticalCheckScrollerRootInsideMon(head.client, &targetGeom)
            scrollerArrangeStackVerticalNode(head, targetGeom, curGappih, ctx)
            syncScrollerStateToClients(m, tag)
            return
        }

        let sel = m.sel.flatMap { clientByIdAll($0) }
        let prevsel = m.prevsel.flatMap { clientByIdAll($0) }
        var rootNode: ScrollerStackNode?
        if let sel, ISSCROLLTILED(sel) {
            rootNode = findScrollerNode(st, sel)
            while let p = rootNode?.prevInStack { rootNode = p }
        }
        if rootNode == nil, let prevsel, ISSCROLLTILED(prevsel) {
            rootNode = findScrollerNode(st, prevsel)
            while let p = rootNode?.prevInStack { rootNode = p }
        }
        if rootNode == nil {
            rootNode = heads[Int(nHeads / 2)]
        }

        var focusIndex: Int32 = -1
        for i in 0..<Int(nHeads) where heads[i] === rootNode {
            focusIndex = Int32(i)
            break
        }
        if focusIndex < 0 { focusIndex = nHeads / 2 }
        let fi = Int(focusIndex)

        var needScroller = false
        var overOverspreadToUp = false
        let rootClient = rootNode!.client
        let rg = WBox(rootClient.geom)

        if rg.y >= w.y + structs && rg.y + rg.height <= w.y + w.height - structs {
            needScroller = false
        } else {
            needScroller = true
        }

        var needApplyOverspread = config.scrollerPreferOverspread && nHeads > 1
            && (focusIndex == 0 || focusIndex == nHeads - 1) && heads[fi].scrollerProportion < 1.0

        if needApplyOverspread {
            if focusIndex == 0 {
                overOverspreadToUp = true
            } else {
                overOverspreadToUp = false
            }
            if overOverspreadToUp
                && (!INSIDEMON(heads[1].client) || heads[1].scrollerProportion + heads[0].scrollerProportion >= 1.0) {
                needScroller = true
            } else if !overOverspreadToUp
                && (!INSIDEMON(heads[fi - 1].client)
                    || heads[fi - 1].scrollerProportion + heads[fi].scrollerProportion >= 1.0) {
                needScroller = true
            } else {
                needApplyOverspread = false
            }
        }

        var prevselClause = prevsel == nil
        if let prevsel {
            prevselClause = ISSCROLLTILED(prevsel)
                && (prevsel.scrollerProportion * Float(maxClientHeight)) + (heads[fi].scrollerProportion * Float(maxClientHeight))
                > Float(w.height - 2 * structs - curGappiv)
        }
        let needApplyCenter = config.scrollerFocusCenter || nHeads == 1
            || (config.scrollerPreferCenter && !needApplyOverspread && prevselClause)

        if nHeads == 1 && scrollerIgnoreProportionSingle {
            needScroller = true
        }
        if startDragWindow { needScroller = false }

        var targetGeom = CGRect.zero
        targetGeom.size.width = CGFloat(w.width - 2 * curGappoh)
        targetGeom.size.height = CGFloat(i32(Float(maxClientHeight) * heads[fi].scrollerProportion))
        targetGeom.origin.x = CGFloat(w.x + (w.width - Int32(targetGeom.width)) / 2)
        verticalScrollAdjustFullandmax(heads[fi].client, &targetGeom)

        if heads[fi].client.isfullscreen {
            targetGeom.origin.y = CGFloat(mm.y)
            verticalCheckScrollerRootInsideMon(heads[fi].client, &targetGeom)
            scrollerArrangeStackVerticalNode(heads[fi], targetGeom, curGappih, ctx)
        } else if heads[fi].client.ismaximizescreen {
            targetGeom.origin.y = CGFloat(w.y + curGappov)
            verticalCheckScrollerRootInsideMon(heads[fi].client, &targetGeom)
            scrollerArrangeStackVerticalNode(heads[fi], targetGeom, curGappih, ctx)
        } else if needScroller {
            if needApplyCenter {
                targetGeom.origin.y = CGFloat(w.y + (w.height - Int32(targetGeom.height)) / 2)
            } else if needApplyOverspread {
                if overOverspreadToUp {
                    targetGeom.origin.y = CGFloat(w.y + structs)
                } else {
                    targetGeom.origin.y = CGFloat(i32(Float(w.y) + (Float(w.height)
                        - heads[fi].scrollerProportion * Float(maxClientHeight) - Float(structs))))
                }
            } else {
                targetGeom.origin.y = rg.y > w.y + w.height / 2
                    ? CGFloat(i32(Float(w.y) + (Float(w.height)
                        - heads[fi].scrollerProportion * Float(maxClientHeight) - Float(structs))))
                    : CGFloat(w.y + structs)
            }
            verticalCheckScrollerRootInsideMon(heads[fi].client, &targetGeom)
            scrollerArrangeStackVerticalNode(heads[fi], targetGeom, curGappih, ctx)
        } else {
            barHeight = !rootClient.isfullscreen && clientWantsGroupBar(rootClient) ? Int32(config.groupBarHeight) : 0

            targetGeom.origin.y = CGFloat(rg.y - barHeight)
            verticalCheckScrollerRootInsideMon(heads[fi].client, &targetGeom)
            scrollerArrangeStackVerticalNode(heads[fi], targetGeom, curGappih, ctx)
        }

        if fi >= 1 {
            for i in 1...fi {
                let cur = heads[fi - i]
                var upGeom = CGRect.zero
                upGeom.size.width = CGFloat(w.width - 2 * curGappoh)
                upGeom.size.height = CGFloat(i32(Float(maxClientHeight) * cur.scrollerProportion))
                verticalScrollAdjustFullandmax(cur.client, &upGeom)

                let below = heads[fi - i + 1].client
                barHeight = !below.isfullscreen && clientWantsGroupBar(below) ? Int32(config.groupBarHeight) : 0

                upGeom.origin.y = CGFloat(Int32(below.geom.minY) - curGappiv - Int32(upGeom.height) - barHeight)
                scrollerArrangeStackVerticalNode(cur, upGeom, curGappih, ctx)
            }
        }

        if Int(nHeads) - fi > 1 {
            for i in 1..<(Int(nHeads) - fi) {
                let cur = heads[fi + i]
                var downGeom = CGRect.zero
                downGeom.size.width = CGFloat(w.width - 2 * curGappoh)
                downGeom.size.height = CGFloat(i32(Float(maxClientHeight) * cur.scrollerProportion))
                verticalScrollAdjustFullandmax(cur.client, &downGeom)
                let prev = WBox(heads[fi + i - 1].client.geom)
                downGeom.origin.y = CGFloat(prev.y + curGappiv + prev.height)
                scrollerArrangeStackVerticalNode(cur, downGeom, curGappih, ctx)
            }
        }

        syncScrollerStateToClients(m, tag)
    }

    func scrollerRemoveClient(_ c: Client) {
        for m in monitors {
            for t in 0..<UInt32(PERTAG_SLOTS) {
                guard let st = m.pertag.scrollerState[t] else { continue }
                if let node = findScrollerNode(st, c) {
                    scrollerNodeRemove(st, node)
                }
            }
        }
    }

    func scrollerInsertStack(_ c: Client, _ targetClient: Client?, _ insertBefore: Bool) {
        guard let targetClient, targetClient.mon === c.mon else { return }

        if c.isfullscreen { clientSetFullscreen(c, false, rearrange: true) }
        if c.ismaximizescreen { clientSetMaximizeScreen(c, false, rearrange: true) }

        guard let m = c.mon else { return }
        let tag = getMonCurtag(m)
        let st = ensureScrollerState(m, tag)

        if let cnode = findScrollerNode(st, c) { scrollerNodeRemove(st, cnode) }

        let tnode = findScrollerNode(st, targetClient) ?? scrollerNodeCreate(st, targetClient)

        let newnode = scrollerNodeCreate(st, c)
        /* Inserts the new node before or after tnode. */
        if insertBefore {
            newnode.nextInStack = tnode
            newnode.prevInStack = tnode.prevInStack
            if let p = tnode.prevInStack { p.nextInStack = newnode }
            tnode.prevInStack = newnode
            wlListSafeReinsertPrev(tnode.client, c)
        } else {
            newnode.prevInStack = tnode
            newnode.nextInStack = tnode.nextInStack
            if let n = tnode.nextInStack { n.prevInStack = newnode }
            tnode.nextInStack = newnode
            wlListSafeReinsertNext(tnode.client, c)
        }

        /* Handles fullscreen/maximized state of the stack head. */
        var head = tnode
        while let p = head.prevInStack { head = p }
        let stackHead = head.client
        if stackHead.ismaximizescreen { clientSetMaximizeScreen(stackHead, false, rearrange: true) }
        if stackHead.isfullscreen { clientSetFullscreen(stackHead, false, rearrange: true) }

        /* Syncs to the Client fields. */
        syncScrollerStateToClients(m, tag)

        arrange(m, false, false)
    }

    func scrollerDropTile(_ c: Client, _ closest: Client, _ vertical: Bool) {
        // Must update first; otherwise nodes inside still hold cnode info and
        // stack_head/stack_tail would point at the wrong clients.
        if let m = c.mon { updateScrollerState(m) }

        let stackHead = scrollGetStackHeadClient(closest)
        let stackTail = scrollGetStackTailClient(closest)

        if vertical {
            if closest.dropDirection == .left {
                clientSetFloating(c, false, false)
                scrollerInsertStack(c, closest, true)
                return
            } else if closest.dropDirection == .right {
                clientSetFloating(c, false, false)
                scrollerInsertStack(c, closest, false)
                return
            } else if closest.dropDirection == .up {
                if c !== stackHead { wlListSafeReinsertPrev(stackHead, c) }
            } else if closest.dropDirection == .down {
                if c !== stackTail { wlListSafeReinsertNext(stackHead, c) }
            }
        } else {
            if closest.dropDirection == .up {
                clientSetFloating(c, false, false)
                scrollerInsertStack(c, closest, true)
                return
            } else if closest.dropDirection == .down {
                clientSetFloating(c, false, false)
                scrollerInsertStack(c, closest, false)
                return
            } else if closest.dropDirection == .left {
                if c !== stackHead { wlListSafeReinsertPrev(stackHead, c) }
            } else if closest.dropDirection == .right {
                if c !== stackTail { wlListSafeReinsertNext(stackHead, c) }
            }
        }

        clientSetFloating(c, false, false)
    }

    func scrollGetStackHeadClient(_ c: Client) -> Client {
        guard let m = c.mon else { return c }
        let tag = getClientTagIdx(c)
        if let st = m.pertag.scrollerState[tag], var n = findScrollerNode(st, c) {
            while let p = n.prevInStack { n = p }
            return n.client
        }
        return c
    }

    func scrollGetStackTailClient(_ c: Client) -> Client {
        guard let m = c.mon else { return c }
        let tag = getClientTagIdx(c)
        if let st = m.pertag.scrollerState[tag], var n = findScrollerNode(st, c) {
            while let x = n.nextInStack { n = x }
            return n.client
        }
        return c
    }

    func updateScrollerState(_ m: Monitor) {
        let tag = getMonCurtag(m)
        let st = ensureScrollerState(m, tag)

        /* Collects all currently visible scroller tiled windows. */
        let vis = clients.filter { VISIBLEON($0, m) && ISSCROLLTILED($0) }

        var n = st.allFirst
        while let node = n {
            let found = vis.contains { $0 === node.client }
            let next = node.allNext
            if !found { scrollerNodeRemove(st, node) }
            n = next
        }

        /* Creates nodes for newly visible windows. */
        for c in vis where findScrollerNode(st, c) == nil {
            scrollerNodeCreate(st, c)
        }
    }

    func scrollerSwapNodesInSameStack(_ n1: ScrollerStackNode, _ n2: ScrollerStackNode) {
        let tmpSc = n1.scrollerProportion
        let tmpSt = n1.scrollerStackProportion
        let tmpSw = n1.scrollerStackWeight
        n1.scrollerProportion = n2.scrollerProportion
        n1.scrollerStackProportion = n2.scrollerStackProportion
        n1.scrollerStackWeight = n2.scrollerStackWeight
        n2.scrollerProportion = tmpSc
        n2.scrollerStackProportion = tmpSt
        n2.scrollerStackWeight = tmpSw

        let p1 = n1.prevInStack
        let next1 = n1.nextInStack
        let p2 = n2.prevInStack
        let next2 = n2.nextInStack

        if n1.nextInStack === n2 {
            n1.nextInStack = next2
            n2.prevInStack = p1
            n1.prevInStack = n2
            n2.nextInStack = n1
            if let p1 { p1.nextInStack = n2 }
            if let next2 { next2.prevInStack = n1 }
        } else if n2.nextInStack === n1 {
            n2.nextInStack = next1
            n1.prevInStack = p2
            n2.prevInStack = n1
            n1.nextInStack = n2
            if let p2 { p2.nextInStack = n1 }
            if let next1 { next1.prevInStack = n2 }
        } else {
            if let p1 { p1.nextInStack = n2 }
            if let next1 { next1.prevInStack = n2 }
            if let p2 { p2.nextInStack = n1 }
            if let next2 { next2.prevInStack = n1 }
            n1.prevInStack = p2
            n1.nextInStack = next2
            n2.prevInStack = p1
            n2.nextInStack = next1
        }
    }

    func scrollerSwapDifferentStacks(_ head1: ScrollerStackNode, _ head2: ScrollerStackNode) {
        let head1C = head1.client
        let head2C = head2.client
        let tail1C = scrollGetStackTailClient(head1C)
        let tail2C = scrollGetStackTailClient(head2C)

        // not in mango: the list's links spliced as one swap of the two runs head..tail in the array
        guard let a0 = clients.firstIndex(where: { $0 === head1C }), let a1 = clients.firstIndex(where: { $0 === tail1C }),
              let b0 = clients.firstIndex(where: { $0 === head2C }), let b1 = clients.firstIndex(where: { $0 === tail2C }),
              a0 <= a1, b0 <= b1, a1 < b0 || b1 < a0 else { return }
        let (f0, f1, s0, s1) = a1 < b0 ? (a0, a1, b0, b1) : (b0, b1, a0, a1)
        let first = Array(clients[f0...f1]), middle = Array(clients[(f1 + 1)..<s0]), second = Array(clients[s0...s1])
        clients.replaceSubrange(f0...s1, with: second + middle + first)
    }

    func exchangeTwoScrollerClients(_ c1: Client, _ c2: Client) {
        guard let m1 = c1.mon, let m2 = c2.mon else { return }

        let tag1 = getMonCurtag(m1)
        let tag2 = getMonCurtag(m2)

        let st1 = ensureScrollerState(m1, tag1)
        let n1 = findScrollerNode(st1, c1)

        let st2 = ensureScrollerState(m2, tag2)
        let n2 = findScrollerNode(st2, c2)

        if n1 == nil && n2 == nil { return }

        if m1 !== m2 && (n1?.prevInStack != nil || n2?.prevInStack != nil
            || n1?.nextInStack != nil || n2?.nextInStack != nil) {
            return
        }

        clientSwapLayoutProperties(c1, c2)

        if let n1, let n2 {
            var head1 = n1
            while let p = head1.prevInStack { head1 = p }
            var head2 = n2
            while let p = head2.prevInStack { head2 = p }

            if head1 === head2 {
                scrollerSwapNodesInSameStack(n1, n2)
                syncScrollerStateToClients(m1, tag1)
                wlListSwap(c1, c2)
            } else {
                scrollerSwapDifferentStacks(head1, head2)
            }
        } else {
            wlListSwap(c1, c2)
        }

        if m1 !== m2 {
            clientSwapMonitorsAndTags(c1, c2)
        }
        finishExchangeArrangeAndFocus(c1, c2, m1, m2)
    }

    func scroller(_ m: Monitor) { scrollerCore(m, nil) }

    func verticalScroller(_ m: Monitor) { verticalScrollerCore(m, nil) }
}
