import CoreGraphics

package extension MangoServer {



    func groupMembers(_ c: Client) -> [Client] {
        var out: [Client] = []
        var it: Client? = clientGroupHead(c)
        while let m = it { out.append(m); it = m.groupNext }
        return out
    }

    func clientGroupJoin(_ c: Client, into target: Client) {
        guard c !== target, let cm = c.mon, target.mon != nil, !cm.isoverview else { return }
        if c.isGroupMember { clientGroupLeave(c) }
        var oldmon: Monitor?
        if c.mon !== target.mon { oldmon = c.mon; c.mon = target.mon }
        if !target.isGroupMember { target.isGroupFocus = true }
        c.groupNext = target
        if let p = target.groupPrev { p.groupNext = c }
        c.groupPrev = target.groupPrev
        target.groupPrev = c
        clientFocusGroupMember(c)
        if let m = c.mon { arrange(m, false, false) }
        if let oldmon { arrange(oldmon, false, false) }
    }

    @discardableResult
    func clientGroupLeave(_ c: Client) -> Bool {
        guard c.isGroupFocus, c.isGroupMember, c.mon?.isoverview != true,
              let rc = c.groupNext ?? c.groupPrev else { return false }
        clientFocusGroupMember(rc)
        clientGroupDetach(c)
        c.isGroupFocus = false
        c.mon = rc.mon
        clientUnpark(c, rc)
        focusStack.removeAll { $0 == c.id }
        let at = (focusStack.firstIndex(of: rc.id) ?? -1) + 1
        focusStack.insert(c.id, at: at)
        if !rc.isGroupMember { rc.isGroupFocus = false }
        return true
    }

    func groupFocus(next: Bool) {
        guard let c = focused, c.isGroupMember, c.mon?.isoverview != true,
              let t = next ? c.groupNext : c.groupPrev else { return }
        clientFocusGroupMember(t)
        if let m = t.mon { arrange(m, false, false) }
    }












}
