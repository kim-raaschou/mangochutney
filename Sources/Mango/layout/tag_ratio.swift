import CoreGraphics

package final class TagRatioNode {
    var client: Client?
    var masterMfact: CGFloat = 0
    var masterWeight: CGFloat = 0
    var stackWeight: CGFloat = 0
    var gridCol: Float = 0
    var gridRow: Float = 0
    var seen = false
    var allNext: TagRatioNode?
    init(client: Client?) { self.client = client }
}

package final class TagRatioState {
    var allFirst: TagRatioNode?
    var count: Int32 = 0
}

package extension MangoServer {
    // not in mango: the layout's id (ltidxs holds the LayoutKind)
    func layoutUsesTagRatios(_ layout: LayoutKind?) -> Bool {
        guard let layout else { return false }
        switch layout {
        case .tile, .grid, .deck, .centerTile, .rightTile, .verticalTile, .verticalGrid, .verticalDeck, .fair,
             .verticalFair:
            return true
        default:
            return false
        }
    }

    private func findRatioNode(_ state: TagRatioState?, _ c: Client?) -> TagRatioNode? {
        guard let state, let c else { return nil }
        var node = state.allFirst
        while let n = node {
            if n.client === c { return n }
            node = n.allNext
        }
        return nil
    }

    private func ratioNodeCreate(_ state: TagRatioState, _ c: Client?, _ mfact: CGFloat) -> TagRatioNode {
        let node = TagRatioNode(client: c)
        node.masterMfact = mfact
        node.masterWeight = 1.0
        node.stackWeight = 1.0
        node.gridCol = 1.0
        node.gridRow = 1.0
        node.allNext = state.allFirst
        state.allFirst = node
        state.count += 1
        return node
    }

    private func ratioNodeRemove(_ state: TagRatioState?, _ target: TagRatioNode?) {
        guard let state, let target else { return }
        if state.allFirst === target {
            state.allFirst = target.allNext
        } else {
            var link = state.allFirst
            while let l = link, l.allNext !== target { link = l.allNext }
            guard let l = link else { return }
            l.allNext = target.allNext
        }
        if state.count > 0 { state.count -= 1 }
    }

    @discardableResult
    func ensureTagRatioState(_ m: Monitor?, _ tag: UInt32) -> TagRatioState? {
        guard let m, tag < PERTAG_SLOTS else { return nil }
        if m.pertag.tagRatioState[tag] == nil {
            m.pertag.tagRatioState[tag] = TagRatioState()
        }
        return m.pertag.tagRatioState[tag]
    }

    // not in mango: clear_tag_ratio_state frees the nodes; ARC does (docs/afvigelser.md §5)

    private func ratioNodeBelongs(_ m: Monitor, _ c: Client?) -> Bool {
        guard let c else { return false }
        let tags = c.isminimized ? c.oldtags : c.tags
        return c.mon === m && !c.isunglobal && !c.iskilling && (c.isglobal || tags & m.tagset[m.seltags] != 0)
    }

    private func updateTagRatioState(_ m: Monitor, _ tag: UInt32) {
        guard let state = ensureTagRatioState(m, tag) else { return }

        var node = state.allFirst
        while let n = node {
            n.seen = false
            node = n.allNext
        }

        var templateNode: TagRatioNode?
        for c in clients {
            if !ratioNodeBelongs(m, c) { continue }
            if let node = findRatioNode(state, c) {
                node.seen = true
                if templateNode == nil { templateNode = node }
                continue
            }
            let node = ratioNodeCreate(state, c, CGFloat(m.pertag.mfacts[tag]))
            node.seen = true
            if let templateNode {
                node.masterMfact = templateNode.masterMfact
                node.masterWeight = templateNode.masterWeight
                node.stackWeight = templateNode.stackWeight
            } else {
                templateNode = node
            }
        }

        node = state.allFirst
        while let n = node {
            let next = n.allNext
            if !n.seen { ratioNodeRemove(state, n) }
            node = next
        }
    }

    func tagRatioStateSeedClient(_ c: Client?) {
        guard let c, let m = c.mon else { return }
        let tag = getMonCurtag(m)
        if !layoutUsesTagRatios(m.pertag.ltidxs[tag]) { return }
        guard let state = ensureTagRatioState(m, tag), ratioNodeBelongs(m, c), findRatioNode(state, c) == nil else {
            return
        }
        let node = ratioNodeCreate(state, c, CGFloat(m.pertag.mfacts[tag]))
        node.masterMfact = c.masterMfactPer
        node.masterWeight = c.masterSizeWeight
        node.stackWeight = c.stackSizeWeight
        node.gridCol = c.gridColPer
        node.gridRow = c.gridRowPer
    }

    private func syncTagRatioStateToClients(_ m: Monitor, _ tag: UInt32) {
        guard let state = m.pertag.tagRatioState[tag] else { return }
        var node = state.allFirst
        while let n = node {
            node = n.allNext
            guard let c = n.client else { continue }
            c.masterMfactPer = n.masterMfact
            c.masterSizeWeight = n.masterWeight
            c.stackSizeWeight = n.stackWeight
            c.gridColPer = n.gridCol
            c.gridRowPer = n.gridRow
        }
    }

    func syncTagRatioStateFromClients(_ m: Monitor?, _ tag: UInt32) {
        guard let m, tag < PERTAG_SLOTS, layoutUsesTagRatios(m.pertag.ltidxs[tag]) else { return }
        guard let state = m.pertag.tagRatioState[tag] else { return }
        var node = state.allFirst
        while let n = node {
            node = n.allNext
            guard let c = n.client else { continue }
            n.masterMfact = c.masterMfactPer
            n.masterWeight = c.masterSizeWeight
            n.stackWeight = c.stackSizeWeight
            n.gridCol = c.gridColPer
            n.gridRow = c.gridRowPer
        }
    }

    func tagRatioStateClientCount(_ m: Monitor?, _ tag: UInt32) -> Int32 {
        guard let m, tag < PERTAG_SLOTS, let state = m.pertag.tagRatioState[tag] else { return 0 }
        return state.count
    }

    func tagRatioStateBegin(_ m: Monitor?, _ tag: UInt32, _ fromView: Bool) {
        guard let m, tag < PERTAG_SLOTS, layoutUsesTagRatios(m.pertag.ltidxs[tag]) else { return }
        if !fromView { syncTagRatioStateFromClients(m, tag) }
        updateTagRatioState(m, tag)
        syncTagRatioStateToClients(m, tag)
    }

    func tagRatioStateRemoveClientInTag(_ m: Monitor, _ tag: UInt32, _ c: Client) {
        let state = m.pertag.tagRatioState[tag]
        while let node = findRatioNode(state, c) { ratioNodeRemove(state, node) }
    }

    func tagRatioStateReplaceClientInTag(_ m: Monitor, _ tag: UInt32, _ old: Client, _ new: Client) {
        if old === new { return }
        guard let state = m.pertag.tagRatioState[tag] else { return }
        guard let oldNode = findRatioNode(state, old) else { return }
        while let newNode = findRatioNode(state, new), newNode !== oldNode { ratioNodeRemove(state, newNode) }
        oldNode.client = new
        while let node = findRatioNode(state, old) { ratioNodeRemove(state, node) }
    }

    func tagRatioStateCopy(_ target: Monitor?, _ dstTag: UInt32, _ source: Monitor?, _ srcTag: UInt32) {
        guard let target, let source, dstTag < PERTAG_SLOTS, srcTag < PERTAG_SLOTS else { return }
        if target === source && dstTag == srcTag { return }

        target.pertag.tagRatioState[dstTag] = nil

        guard let src = source.pertag.tagRatioState[srcTag] else { return }
        guard let dst = ensureTagRatioState(target, dstTag) else { return }
        var node = src.allFirst
        while let n = node {
            node = n.allNext
            let copy = ratioNodeCreate(dst, n.client, n.masterMfact)
            copy.masterWeight = n.masterWeight
            copy.stackWeight = n.stackWeight
            copy.gridCol = n.gridCol
            copy.gridRow = n.gridRow
        }
    }

    func tagRatioStateMove(_ m: Monitor?, _ dstTag: UInt32, _ srcTag: UInt32) {
        guard let m, dstTag < PERTAG_SLOTS, srcTag < PERTAG_SLOTS, dstTag != srcTag else { return }
        m.pertag.tagRatioState[dstTag] = m.pertag.tagRatioState[srcTag]
        m.pertag.tagRatioState[srcTag] = nil
    }

    func tagRatioStateReset(_ m: Monitor?, _ tag: UInt32) {
        guard let m, tag < PERTAG_SLOTS else { return }
        m.pertag.tagRatioState[tag] = nil
    }

    func cleanupMonitorTagRatioStates(_ m: Monitor?) {
        guard let m else { return }
        for tag in 0..<PERTAG_SLOTS { tagRatioStateReset(m, tag) }
    }

    func tagRatioStateSetMasterMfact(_ m: Monitor, _ tag: UInt32, _ mfact: CGFloat) {
        guard let state = ensureTagRatioState(m, tag) else { return }
        m.pertag.mfacts[tag] = Float(mfact)
        let current = getMonCurtag(m) == tag
        var node = state.allFirst
        while let n = node {
            node = n.allNext
            n.masterMfact = mfact
            if current, let c = n.client { c.masterMfactPer = mfact }
        }
    }
}
