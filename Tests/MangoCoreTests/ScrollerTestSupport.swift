@testable import Mango

extension MangoServer {
    /// The ids of `c`'s scroller stack, head first (empty when it has no node).
    func scrollerStack(of id: ClientID) -> [ClientID] {
        guard let c = clientByWindowID(id), let m = c.mon,
              var n = findScrollerNode(m.pertag.scrollerState[getClientTagIdx(c)], c) else { return [] }
        while let p = n.prevInStack { n = p }
        var out: [ClientID] = [n.client.windowID]
        while let x = n.nextInStack { out.append(x.client.windowID); n = x }
        return out
    }

    /// The stacks of the visible scroll-tiled clients on `m`, in client list order.
    func scrollerStacks(_ m: Monitor) -> [[ClientID]] {
        var out: [[ClientID]] = []
        for c in clients where VISIBLEON(c, m) && ISSCROLLTILED(c) {
            let s = scrollerStack(of: c.windowID)
            if let h = s.first, h == c.windowID { out.append(s) }
        }
        return out
    }
}
