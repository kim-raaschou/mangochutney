import Foundation

// not in mango: mango's wl_list helpers (common/util.c) on server.clients, which is an array here
package extension MangoServer {
    /// mango wl_list_safe_reinsert_prev (common/util.c): l2 goes just before l1.
    func wlListSafeReinsertPrev(_ l1: Client, _ l2: Client) {
        if l1 === l2 { return }
        guard let i1 = clients.firstIndex(where: { $0 === l1 }) else { return }
        if i1 > 0 && clients[i1 - 1] === l2 { return }

        clients.removeAll { $0 === l2 }
        clients.insert(l2, at: clients.firstIndex(where: { $0 === l1 })!)
    }

    /// mango wl_list_safe_reinsert_next (common/util.c): l2 goes just after l1.
    func wlListSafeReinsertNext(_ l1: Client, _ l2: Client) {
        if l1 === l2 { return }
        guard let i1 = clients.firstIndex(where: { $0 === l1 }) else { return }
        if i1 + 1 < clients.count && clients[i1 + 1] === l2 { return }

        clients.removeAll { $0 === l2 }
        clients.insert(l2, at: clients.firstIndex(where: { $0 === l1 })! + 1)
    }

    /// mango wl_list_swap (common/util.c).
    func wlListSwap(_ a: Client, _ b: Client) {
        guard let i = clients.firstIndex(where: { $0 === a }), let j = clients.firstIndex(where: { $0 === b }) else { return }
        clients.swapAt(i, j)
    }
}
