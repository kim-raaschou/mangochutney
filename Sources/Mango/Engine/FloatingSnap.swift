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
