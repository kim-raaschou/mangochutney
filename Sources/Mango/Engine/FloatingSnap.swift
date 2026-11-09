import CoreGraphics

package enum FloatingSnap {
    // not in mango: apply_window_snap's arithmetic, apart so it is tested on its own
    static func snapped(_ c: CGRect, others: [CGRect], monitor: CGRect, workArea: CGRect,
                        distance: CGFloat) -> CGRect {
        var left = CGFloat.greatestFiniteMagnitude, right = left, up = left, down = left
        func take(_ v: CGFloat, _ best: inout CGFloat) { if v >= 0 && v < best { best = v } }
        for t in others {
            take(c.minX - t.maxX, &left)
            take(t.minX - c.maxX, &right)
            take(c.minY - t.maxY, &up)
            take(t.minY - c.maxY, &down)
        }
        for r in [monitor, workArea] {
            take(c.minX - r.minX, &left)
            take(r.maxX - c.maxX, &right)
            take(c.minY - r.minY, &up)
            take(r.maxY - c.maxY, &down)
        }
        var f = c
        if left < right && left < distance { f.origin.x -= left }
        if right <= left && right < distance { f.origin.x += right }
        if up < down && up < distance { f.origin.y -= up }
        if down <= up && down < distance { f.origin.y += down }
        return f
    }
}

package extension MangoServer {
    func applyWindowSnap(_ c: Client) {
        guard config.enableFloatingSnap, c.isFloating, let m = c.mon else { return }
        // mango snaps the outer edge while borders are drawn, the window's edge otherwise.
        let bw = renderBorder ? CGFloat(config.borderpx) : 0
        func outer(_ x: Client) -> CGRect { x.noBorder || bw == 0 ? x.frame : x.frame.insetBy(dx: -bw, dy: -bw) }
        let others = clientsAll.filter { $0 !== c && $0.isFloating && !$0.parked && $0.isVisible(on: m) }.map(outer)
        let from = outer(c)
        let to = FloatingSnap.snapped(from, others: others, monitor: m.screen.frame, workArea: m.screen.workArea,
                                      distance: CGFloat(config.snapDistance))
        guard to != from else { return }
        c.floatGeom = c.frame.offsetBy(dx: to.minX - from.minX, dy: to.minY - from.minY)
        arrange(m, .none)
    }
}
