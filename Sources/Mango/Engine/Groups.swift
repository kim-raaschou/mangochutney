import CoreGraphics

package extension MangoServer {
    func groupMembers(_ c: Client) -> [Client] {
        var out: [Client] = []
        var it: Client? = clientGroupHead(c)
        while let m = it { out.append(m); it = m.groupNext }
        return out
    }
}
