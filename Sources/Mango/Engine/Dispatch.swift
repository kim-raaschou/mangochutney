import Foundation

package extension MangoServer {
    /// Not in mango: a binding's or IPC's dispatcher, run as keyboard.c and ipc.c run it, or the port's (PortHooks).
    /// `notGiven` is a field the binding does not give: "0" from the keybinding parser, "" from IPC.
    @discardableResult
    func dispatch(_ d: Dispatch, target: Client? = nil, rescan: Bool = true, notGiven: String = "0") -> String? {
        var arg = Arg()
        // not in mango: setoption's fields a binding does not give are "", not "0" (a mango bug, docs/afvigelser.md §6)
        let a = (0..<5).map { $0 < d.args.count ? d.args[$0] : d.name == "setoption" ? "" : notGiven }
        if let fn = BindingParser.parseFuncName(d.name, &arg, a[0], a[1], a[2], a[3], a[4]) {
            defer { if rescan { system.rescan() } }   // not in mango: the port's side
            arg.tc = target
            _ = fn(self)(arg)
            return nil
        }
        guard Dispatch.isKnown(d.name) else { return "unknown function" }
        defer { if rescan { system.rescan() } }   // not in mango: the port's side
        // Port extension: not in mango. The port's own dispatchers (chutney_*).
        if let ext = portHooks.extraDispatchers[d.name] {
            if let error = ext(self, d) { return error }
        }
        printstatus(.arrangge)
        return nil
    }
}
