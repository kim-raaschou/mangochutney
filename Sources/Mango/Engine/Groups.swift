import CoreGraphics

package extension MangoServer {
    // not in mango: the group from client_group_head along group_next
    func groupMembers(_ c: Client) -> [Client] {
        var out: [Client] = []
        var it: Client? = clientGroupHead(c)
        while let m = it { out.append(m); it = m.groupNext }
        return out
    }
}
