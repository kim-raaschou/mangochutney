import CoreGraphics

package extension MangoServer {
    func clientGroupHead(_ c: Client) -> Client {
        var head = c
        while let p = head.groupPrev { head = p }
        return head
    }

    func groupMembers(_ c: Client) -> [Client] {
        var out: [Client] = []
        var it: Client? = clientGroupHead(c)
        while let m = it { out.append(m); it = m.groupNext }
        return out
    }

    func clientGroupJoin(_ c: Client, into target: Client) {
        guard c !== target, c.mon != nil, target.mon != nil, overviewState == nil else { return }
        if c.isGroupMember { clientGroupLeave(c) }
        var oldmon: Monitor?
        if c.mon !== target.mon { oldmon = c.mon; c.mon = target.mon }
        if !target.isGroupMember { target.isGroupFocus = true }
        c.groupNext = target
        if let p = target.groupPrev { p.groupNext = c }
        c.groupPrev = target.groupPrev
        target.groupPrev = c
        clientFocusGroupMember(c)
        if let m = c.mon { arrange(m) }
        if let oldmon { arrange(oldmon) }
    }

    @discardableResult
    func clientGroupLeave(_ c: Client) -> Bool {
        guard c.isGroupFocus, c.isGroupMember, overviewState == nil,
              let rc = c.groupNext ?? c.groupPrev else { return false }
        clientFocusGroupMember(rc)
        clientGroupDetach(c)
        c.isGroupFocus = false
        c.mon = rc.mon
        clientUnpark(c, after: rc)
        focusStack.removeAll { $0 == c.id }
        let at = (focusStack.firstIndex(of: rc.id) ?? -1) + 1
        focusStack.insert(c.id, at: at)
        if !rc.isGroupMember { rc.isGroupFocus = false }
        return true
    }

    func groupFocus(next: Bool) {
        guard let c = focused, c.isGroupMember, overviewState == nil,
              let t = next ? c.groupNext : c.groupPrev else { return }
        clientFocusGroupMember(t)
        if let m = t.mon { arrange(m) }
    }

    package func clientFocusGroupMember(_ c: Client) {
        guard clientGroupSwapFocus(c) else { return }
        clientFocus(c)
        if let m = c.mon { arrange(m) }
    }

    @discardableResult
    func clientGroupSwapFocus(_ c: Client) -> Bool {
        guard c.isGroupMember, !c.isGroupFocus,
              let current = groupMembers(c).first(where: { $0.isGroupFocus }), let m = current.mon,
              overviewState == nil else { return false }
        current.isGroupFocus = false
        c.mon = m
        clientReplace(c, current, isGroupChangeMember: true)
        c.isGroupFocus = true
        return true
    }

    func clientReplace(_ c: Client, _ w: Client, isGroupChangeMember: Bool) {
        c.isFloating = w.isFloating
        c.isUrgent = w.isUrgent
        c.tags = w.tags
        c.geom = w.geom
        c.floatGeom = w.floatGeom
        c.stackInnerPer = w.stackInnerPer
        c.masterInnerPer = w.masterInnerPer
        c.stackSizeWeight = w.stackSizeWeight
        c.masterSizeWeight = w.masterSizeWeight
        c.scrollerStackWeight = w.scrollerStackWeight
        c.masterMfactPer = w.masterMfactPer
        c.scrollerProportion = w.scrollerProportion
        c.isGlobal = w.isGlobal
        c.overviewBackupGeom = w.overviewBackupGeom
        c.isFullscreen = w.isFullscreen
        c.isMaximizeScreen = w.isMaximizeScreen
        c.isInScratchpad = w.isInScratchpad
        c.isMinimized = w.isMinimized
        c.groupParked = false
        if !isGroupChangeMember { clientGroupReplace(w, c) }
        clientUnpark(c, after: w)
        focusStack.removeAll { $0 == c.id }
        focusStack.insert(c.id, at: focusStack.firstIndex(of: w.id) ?? 0)
        if let m = w.mon {
            let layout = m.layout
            for p in m.pertag {
                if layout == .dwindle { p.state.dwindleRoot.replace(w.id, with: c.id, config: config) }
                if layout.isScroller { p.state.scrollerState.replace(w.id, with: c.id) }
            }
        }
        clientPark(w)
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

    func clientPark(_ c: Client) {
        c.groupParked = true
        clients.removeAll { $0 === c }
        focusStack.removeAll { $0 == c.id }
    }

    func clientUnpark(_ c: Client, after anchor: Client) {
        c.groupParked = false
        clients.removeAll { $0 === c }
        let at = clients.firstIndex(where: { $0 === anchor }).map { $0 + 1 } ?? clients.count
        clients.insert(c, at: at)
    }

    func clientGroupDetach(_ c: Client) {
        c.groupPrev?.groupNext = c.groupNext
        c.groupNext?.groupPrev = c.groupPrev
        c.groupPrev = nil
        c.groupNext = nil
        c.isGroupFocus = false
    }


    func clientWantsGroupBar(_ c: Client) -> Bool {
        config.groupBarHeight > 0 && (c.isGroupMember || config.alwaysShowGroupBar)
    }
}
