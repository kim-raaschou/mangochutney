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
        let vis = (isSpecialActive(mon) ? specialClients(mon) : visibleClients(mon)).filter { !$0.parked }
        if let f = vis.first(where: { ($0.isfloating || SCRATCHPAD_SHOWN($0)) && clientGeom($0).contains(p) }) { return f }
        if let s = mon.sel.flatMap({ clientByIdAll($0) }), vis.contains(where: { $0 === s }), clientGeom(s).contains(p) { return s }
        return vis.first { clientGeom($0).contains(p) }
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
