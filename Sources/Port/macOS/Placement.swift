import AppKit
import Mango

/// mango's resize and hide (resize_client, show_hide_client) on macOS: a window is put
/// where mango wants it with Accessibility writes, read back, written again when its app
/// did not take it, and its refused sizes learned; a hidden window is parked in a corner.
/// Windows covered by others are not animated (docs/plan-kerne-backend.md, trin 3).
extension MacWindowSystem {
    /// Places windows front to back, as the window server stacks them. A window it shows
    /// wholly under an opaque one placed before it, where the window server has them now
    /// and at their targets, is not animated: nobody sees it. Every frame is an
    /// Accessibility write, and eleven windows of a monocle tag resizing together, ten of
    /// them covered, loaded the machine so that every app was slow to resize. A window this
    /// arrange raises, or the selected one (macOS raises it as it takes focus), is never
    /// taken as covered.
    func resize(_ placements: [(Client, CGRect)], _ anim: ArrangeAnimation, rising: Set<ClientID>) {
        var animated = server.config.animations && placements.count > 1
        if case .none = anim { animated = false }
        guard animated else {
            for (c, t) in placements { resize(c, to: t, anim) }
            return
        }
        var rank: [CGWindowID: Int] = [:]
        var shown: [CGWindowID: StackedWindow] = [:]
        for (i, w) in stackingOrder().enumerated() where rank[w.id] == nil { rank[w.id] = i; shown[w.id] = w }
        let sorted = placements.enumerated().sorted {
            (rank[$0.element.0.id] ?? .max, $0.offset) < (rank[$1.element.0.id] ?? .max, $1.offset)
        }.map(\.element)
        // Opaque windows placed so far: where each is, and where it goes.
        var above: [(c: Client, now: CGRect, to: CGRect)] = []
        for (c, t) in sorted {
            // Where the window server has it: an app that refused a size is larger than asked.
            let now = shown[c.id]?.frame ?? c.frame
            let to = t.rounded()
            var cover: CGRect?
            if rank[c.id] != nil, !rising.contains(c.id), let v = above.first(where: { $0.now.contains(now) && $0.to.contains(to) }) {
                cover = animator.covered(v.c.id) ?? v.c.frame
            }
            resize(c, to: t, anim, cover: cover, now: now)
            if shown[c.id]?.opaque == true { above.append((c, now, to)) }
        }
    }

    /// Move a client to `target`, animating per config. `cover`: the client is under
    /// another window, which keeps this covered through its own move; `now`: where the
    /// window server has the client (the front-to-back resize).
    func resize(_ c: Client, to tile: CGRect, _ anim: ArrangeAnimation, cover: CGRect? = nil, now: CGRect? = nil) {
        guard let q = writer(for: c.pid), let m = c.mon else { return }
        c.geom = tile.rounded()
        // Not in mango: a window its app keeps larger than its tiles is written where it
        // grows inward (the app takes the place and keeps its own size).
        var target = tile.rounded()
        if let rs = c.refusedSize, !c.isFloating, rs.width > target.width + 0.5 || rs.height > target.height + 0.5 {
            let size = CGSize(width: max(rs.width, target.width), height: max(rs.height, target.height))
            target.origin = Self.inwardOrigin(target, size: size, in: layoutBounds(m))
        }
        let wasParked = c.parked
        c.parked = false
        c.parkRetries = 0
        if !wasParked && !c.isPendingOpenAnimation && c.frame == target && !animator.isAnimating(c.id) { return }

        let moving = !wasParked && !c.isPendingOpenAnimation
        c.writes += 1
        // mango's resize decides the animation; the port draws it.
        let a = server.clientAnimation(c, to: target, anim, current: c.frame, shown: !wasParked)
        let from = a.from, curve = a.curve, total = a.durationMs
        let animate = total > 0
        // Our own moves: dropped by the app thread while the animation runs (a hop per
        // frame otherwise), then recorded by moved until `ignoreMovesUntil`
        // (an app that applies the frame late or adjusts it reports it), not reacted to.
        let animationEnd = CACurrentMediaTime() + Double(total) / 1000
        c.ignoreMovesUntil = animationEnd + 0.4
        watcher.suppressGeometry(c.id, until: animationEnd + 0.05)
        c.frame = target
        // Covered: no frames. It goes now where it stays covered (its target, if that is
        // inside the cover; else it waits where it is, or in the cover) and takes its
        // target with the last frame.
        var waitAt: CGRect?
        if moving, let cover, !cover.isEmpty {
            waitAt = cover.contains(target) ? target : cover.contains(now ?? from) ? now ?? from : cover
        }
        if animate && from != target && total > 0 && waitAt != target {
            animator.animate(id: c.id, element: c.element, queue: q, from: from, to: target, durationMs: total,
                             curve: curve, waitingAt: waitAt) { [weak self] in self?.verifyFrame(c) }
        } else {
            animator.cancel(c.id)
            q.setFrame(c.element, id: c.id, frame: target)
            verifyFrame(c)
        }
    }

    /// Read back the real frame after our write (now, and once more shortly after for
    /// apps that adjust asynchronously, e.g. Electron) so borders and `c.frame`
    /// match the window even when the app refused the requested size.
    func verifyFrame(_ c: Client) {
        guard let q = writer(for: c.pid) else { return }
        readBack(c, q)
        // A late frame or an adjustment arrives as the app's own move/resize notification
        // and is recorded (moved). One more read just after `ignoreMovesUntil`
        // for apps that never report it (Java, Teams repositioning itself): recorded moves
        // are not reacted to, so without it such a window would stay off its layout.
        let late = max(0.6, c.ignoreMovesUntil - CACurrentMediaTime() + 0.15)
        DispatchQueue.main.asyncAfter(deadline: .now() + late) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.server.clientByIdAll(c.id) === c else { return }
                self.readBack(c, q)
            }
        }
    }

    /// Reads the window's frame and reconciles it. The answer is `settled` when it was
    /// asked for after `ignoreMovesUntil` and no write came in between: the app has had
    /// its time to apply the write. An answer read right after a write can still be the
    /// app's old frame (Electron apps such as Claude and VS Code take a size and apply it
    /// a moment later).
    func readBack(_ c: Client, _ q: WindowWriter) {
        let settled = CACurrentMediaTime() >= c.ignoreMovesUntil
        let write = c.writes
        q.readBack(c.element) { [weak self] actual in
            self?.reconcileFrame(c, actual, settled: settled && c.writes == write)
        }
    }

    /// Put a tiled window back on its layout frame: now if the last attempt is more
    /// than a second ago, otherwise as soon as it is (never dropped). At most 3 attempts
    /// per target, so an app that insists on moving itself is not fought forever.
    func keepPlaced(_ c: Client, at target: CGRect) {
        if c.retryTarget != target { c.retryTarget = target; c.retryCount = 0 }
        guard c.retryCount < 3 else { return }
        let now = CACurrentMediaTime()
        let wait = c.lastReassert + 1.0 - now
        if wait <= 0 {
            c.retryCount += 1
            c.lastReassert = now
            resize(c, to: target, .none)
            return
        }
        guard !c.deferredRetryPending else { return }
        c.deferredRetryPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + wait + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                c.deferredRetryPending = false
                guard let self, self.server.clientByIdAll(c.id) === c, c.geom == target, !c.parked,
                      !self.animator.isAnimating(c.id), let q = self.writer(for: c.pid) else { return }
                self.readBack(c, q)
            }
        }
    }

    /// Not in mango: the area mango's layout fills on a monitor, its tiled windows together:
    /// the work area inside the outer gaps as mango applied them (smartgaps, the special
    /// tag's gaps). The work area when nothing is tiled.
    func layoutBounds(_ m: Monitor) -> CGRect {
        let tiles = server.tiledClients(m).compactMap(\.geom).reduce(CGRect.null) { $0.union($1) }
        return tiles.isNull ? m.screen.workArea : tiles.intersection(m.screen.workArea)
    }

    /// Not in mango: where a window its app keeps larger than its tile stands. mango's
    /// compositor clips such a window; macOS cannot, so it keeps the tile's top-left corner
    /// and goes over its neighbour, but never past the area the layout fills (`bounds`,
    /// inside the outer gaps): from an edge it would cross it grows inward.
    static func inwardOrigin(_ tile: CGRect, size: CGSize, in bounds: CGRect) -> CGPoint {
        var o = tile.origin
        if o.x + size.width > bounds.maxX { o.x = max(bounds.minX, bounds.maxX - size.width) }
        if o.y + size.height > bounds.maxY { o.y = max(bounds.minY, bounds.maxY - size.height) }
        return o
    }

    func reconcileFrame(_ c: Client, _ actual: CGRect?, settled: Bool = false) {
        // An app busy right after a debugger pause does not answer the read-back; the
        // window server knows where the window is without asking it, so the border
        // follows the window and not where it was meant to go.
        guard let actual = actual ?? windowServerFrame(c.id), server.clientByIdAll(c.id) === c, !c.parked,
              !animator.isAnimating(c.id), server.grab?.client !== c else { return }
        // Not in mango: larger than its tile, or not any more: the state's watchers are told (the
        // menu bar's chutney_overlap_warning).
        let refused = c.refusedSize
        defer { if c.refusedSize != refused { server.onStateChange?() } }
        if let t = c.geom, MangoServer.frameDistance(actual, t) <= 0.5 { c.retryCount = 0; c.refusedSize = nil }
        // A size learned from an old frame (an app that applies sizes late answers the
        // first read-back with the size it had) is not its minimum: once the window shows
        // a smaller size, that size is what it keeps, or none when it fits its tile.
        if let t = c.geom, let rs = c.refusedSize, actual.width < rs.width - 0.5 || actual.height < rs.height - 0.5 {
            c.refusedSize = actual.width > t.width + 0.5 || actual.height > t.height + 0.5 ? actual.size : nil
        }
        let d = abs(actual.minX - c.frame.minX) + abs(actual.minY - c.frame.minY)
            + abs(actual.width - c.frame.width) + abs(actual.height - c.frame.height)
        // Compare with the layout too: the app's own move notification may already have
        // set `frame` to where it stopped (Claude halfway through an animation), and then
        // the window would never be put back.
        let offLayout = !c.isFloating && !c.scratchpadShown
            && c.geom.map { MangoServer.frameDistance(actual, $0) > 0.5 } == true
        guard d > 0.5 || offLayout else { return }   // frames are whole points: 1 pt off is off
        // A floating window the app put elsewhere: userMoved, as for the app's own move.
        if c.isFloating { userMoved(c, to: actual, resized: false, dragging: false); return }
        c.frame = actual
        // A tiled window that did not end where the layout put it. Somewhere else, or smaller
        // (the app was busy during the write, the size was lost mid-animation): it is put
        // back, now or once the 1 s rate limit allows. Where mango put it but larger (the
        // app's minimum size, a fixed aspect ratio): mango's tile stays and the window
        // overlaps its neighbour, as mango's compositor would clip it, growing inward from a
        // screen edge it would cross (inwardOrigin, docs/afvigelser.md); it is asked once
        // more, from the late read-back, then left as it is.
        let now = CACurrentMediaTime()
        if !c.isFloating, !c.scratchpadShown, let target = c.geom, MangoServer.frameDistance(actual, target) > 0.5 {
            let larger = actual.width > target.width + 0.5 || actual.height > target.height + 0.5
            // Larger than its tile: its place grows inward from an edge it would cross.
            let inward = larger && c.mon != nil ? Self.inwardOrigin(target, size: actual.size, in: layoutBounds(c.mon!)) : target.origin
            let atTile = abs(actual.minX - target.minX) <= 1 && abs(actual.minY - target.minY) <= 1
            let atInward = abs(actual.minX - inward.x) <= 1 && abs(actual.minY - inward.y) <= 1
            let refused = (atTile || atInward) && larger
            if !larger { c.refusedSize = nil }
            if refused {
                c.refusedSize = actual.size
                if !atInward, let q = writer(for: c.pid) {
                    // Not in mango: in from the edge, at its own size (a position, no size).
                    c.frame = CGRect(origin: inward, size: actual.size)
                    c.ignoreMovesUntil = now + 0.5
                    watcher.suppressGeometry(c.id, until: c.ignoreMovesUntil)
                    q.setFrame(c.element, id: c.id, frame: c.frame, setSize: false)
                    server.updateBorders()
                    return
                }
                if settled {
                    if c.retryCount == 0 {
                        keepPlaced(c, at: target)
                        if now - c.lastReassert < 0.01 { return }   // placed just now
                    }
                }
            } else if now - c.lastReassert > 1.0 || actual.width <= target.width + 0.5 && actual.height <= target.height + 0.5 {
                keepPlaced(c, at: target)
                if now - c.lastReassert < 0.01 { return }   // placed just now
            }
        }
        server.updateBorders()
    }

    func hide(_ c: Client, tagout t: TagoutAnimation) {
        guard !c.parked, let q = writer(for: c.pid), t.durationMs > 0, c.frame != t.to else {
            c.tagouting = false
            hide(c)
            return
        }
        let end = CACurrentMediaTime() + Double(t.durationMs) / 1000
        c.ignoreMovesUntil = end + 0.4
        watcher.suppressGeometry(c.id, until: end + 0.05)
        let from = c.frame
        c.frame = t.to
        animator.animate(id: c.id, element: c.element, queue: q, from: from, to: t.to, durationMs: t.durationMs,
                         curve: t.curve) { [weak self] in
            // mango tagouted: hidden once out, unless it was shown again meanwhile.
            guard let self, c.tagouting, self.server.clientByIdAll(c.id) === c else { return }
            c.tagouting = false
            self.hide(c)
        }
    }

    func hide(_ c: Client) {
        guard !c.parked, let m = c.mon, let q = writer(for: c.pid) else { return }
        animator.cancel(c.id)
        c.parked = true
        c.frame = CGRect(origin: parkedOrigin(c, on: m), size: c.frame.size)
        c.ignoreMovesUntil = CACurrentMediaTime() + 0.5
        watcher.suppressGeometry(c.id, until: c.ignoreMovesUntil)
        q.setFrame(c.element, id: c.id, frame: c.frame, setSize: false)
        q.readBack(c.element) { [weak self] actual in self?.keepHidden(c, seenAt: actual) }
    }

    /// Where `c` is parked on `m`: the corner of its display that touches no other.
    func parkedOrigin(_ c: Client, on m: Monitor) -> CGPoint {
        let others = server.monitors.filter { $0 !== m }.map { $0.screen.frame }
        return Hider.parkedOrigin(size: c.frame.size, workArea: m.screen.workArea,
                                  corner: Hider.corner(for: m.screen.frame, others: others))
    }

    /// After the displays change: a parked window is parked again where its display's corner
    /// is now. Its old corner can lie inside a display that moved or grew, and macOS moves
    /// only windows that end up off every display.
    func parkAgainAfterScreensChanged() {
        for c in server.clientsAll where c.parked {
            guard let m = c.mon, c.frame.origin != parkedOrigin(c, on: m) else { continue }
            c.parked = false
            c.parkRetries = 0
            hide(c)
        }
    }

    /// A parked window must stay parked: the app may not have taken the move (busy), or
    /// moves its hidden window back into view itself (Arc did, playing a video). Seen by
    /// the read-back after parking and by the app's own move notifications; parked again
    /// at most three times until the window is next placed.
    func keepHidden(_ c: Client, seenAt actual: CGRect?) {
        guard server.clientByIdAll(c.id) === c, c.parked, !missionControl.isActive, let m = c.mon,
              let actual = actual ?? windowServerFrame(c.id) else { return }
        if Hider.isParked(actual, in: m.screen.frame) { return }
        guard c.parkRetries < 3 else { return }
        c.parkRetries += 1
        wlrLog(.debug, "\(c.appName): window \(c.id) is hidden but in view at \(actual); parking it again")
        c.frame = actual
        c.parked = false
        hide(c)
    }
}
