@testable import Mango

extension MangoServer {
    /// The tab chain on m, head first.
    func tabChain(_ m: Monitor) -> [Client] {
        guard let head = clients.first(where: { $0.mon === m && $0.tabPrev == nil && $0.tabNext != nil }) else { return [] }
        var out: [Client] = []
        var it: Client? = head
        while let x = it { out.append(x); it = x.tabNext }
        return out
    }

    /// The member of m's tab chain that is shown.
    func tabFocus(_ m: Monitor) -> Client? { tabChain(m).first { $0.isTabFocus } }
}
