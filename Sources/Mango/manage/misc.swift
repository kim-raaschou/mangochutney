import CoreGraphics

// not in mango: get_parent_process, is_descendant_process (swallowing), get_layout_abbr, client_at_point
// (the overview's cards are the port's), and the protocols (decoration, idle inhibit, session lock,
// capture, selection, drm lease)

package extension MangoServer {
    /// mango node_at_point (misc.c)
    // not in mango: the port has no scene, so the stacking is spelled out and the client returned
    package func nodeAtPoint(_ p: CGPoint, on m: Monitor? = nil) -> Client? {
        let mon = m ?? monitorAtPoint(p)
        guard let mon else { return nil }
        if mon.isoverview {
            // not in mango: a card where it stands (a floating client's) lies over the grid
            let hits = mon.ovCards.filter { $0.value.contains(p) }.compactMap { clientByIdAll($0.key) }
            return hits.first { $0.isfloating } ?? hits.first
        }
        let hits = (isSpecialActive(mon) ? specialClients(mon) : visibleClients(mon))
            .filter { !$0.parked && clientGeom($0).contains(p) }
        // not in mango: node_at_point's walk from the top layer down, as the topmost layer among the hits
        guard let layer = hits.map({ clientTargetLayer($0) }).max() else { return nil }
        let top = hits.filter { clientTargetLayer($0) == layer }
        // not in mango: within the layer the window server's stacking, else the focus stack
        if let s = system.surfaceAt(p), let c = top.first(where: { $0.id == s }) { return c }
        for id in focusStack { if let c = top.first(where: { $0.id == id }) { return c } }
        return top.first
    }

    /// Not in mango: the surface of mango's node_at_point: the window under the point, or the client's own
    /// on its border (a rect node); the port's own windows (bars, overview) are none.
    func surfaceAt(_ c: Client?, _ p: CGPoint) -> ClientID? {
        if let s = system.surfaceAt(p) { return s }
        if let c, c.geom.contains(p) { return c.id }
        return nil
    }

    /// Not in mango: mango's geom, with the border (our frame is without it).
    func clientGeom(_ c: Client) -> CGRect {
        let bw = borderWidth(c, on: c.mon ?? selectedMonitor)
        return c.frame.insetBy(dx: -bw, dy: -bw)
    }
}
