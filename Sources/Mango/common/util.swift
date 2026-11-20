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

/// mango regex_match (common/util.c)
// not in mango: ICU's regex (NSRegularExpression) stands for PCRE2; its error has no offset, and the
// empty pattern, which ICU refuses, is PCRE2's "(?:)"
func regexMatch(_ pattern: String?, _ str: String?) -> Bool {
    guard let pattern, let str else {
        return false
    }

    let re: NSRegularExpression
    do {
        re = try NSRegularExpression(pattern: pattern.isEmpty ? "(?:)" : pattern)
    } catch {
        mangoError(false, .error, "PCRE2 error: \(error.localizedDescription)\n")
        return false
    }

    return re.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)) != nil
}
