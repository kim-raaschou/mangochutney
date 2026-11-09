import AppKit
import Mango

extension MacWindowSystem {
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
        var above: [(c: Client, now: CGRect, to: CGRect)] = []
        for (c, t) in sorted {
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

    func resize(_ c: Client, to tile: CGRect, _ anim: ArrangeAnimation, cover: CGRect? = nil, now: CGRect? = nil) {
        guard let q = writer(for: c.pid), let m = c.mon else { return }
        c.geom = tile.rounded()
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
        let a = server.clientAnimation(c, to: target, anim, current: c.frame, shown: !wasParked)
        let from = a.from, curve = a.curve, total = a.durationMs
        let animate = total > 0
        let animationEnd = CACurrentMediaTime() + Double(total) / 1000
        c.ignoreMovesUntil = animationEnd + 0.4
        watcher.suppressGeometry(c.id, until: animationEnd + 0.05)
        c.frame = target
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

    func verifyFrame(_ c: Client) {
        guard let q = writer(for: c.pid) else { return }
        readBack(c, q)
        let late = max(0.6, c.ignoreMovesUntil - CACurrentMediaTime() + 0.15)
        DispatchQueue.main.asyncAfter(deadline: .now() + late) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.server.clientByIdAll(c.id) === c else { return }
                self.readBack(c, q)
            }
        }
    }

    func readBack(_ c: Client, _ q: WindowWriter) {
        let settled = CACurrentMediaTime() >= c.ignoreMovesUntil
        let write = c.writes
        q.readBack(c.element) { [weak self] actual in
            self?.reconcileFrame(c, actual, settled: settled && c.writes == write)
        }
    }

    func keepPlaced(_ c: Client, at target: CGRect) {
        if c.retryTarget != target { c.retryTarget = target; c.retryCount = 0 }
        guard c.retryCount < 3 else {
            if c.retryCount == 3 {
                c.retryCount += 1
                wlrLog(.debug, "\(c.appName): window \(c.id) keeps \(c.frame), not its tile \(target); left there")
            }
            return
        }
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

    func layoutBounds(_ m: Monitor) -> CGRect {
        let tiles = server.tiledClients(m).compactMap(\.geom).reduce(CGRect.null) { $0.union($1) }
        return tiles.isNull ? m.screen.workArea : tiles.intersection(m.screen.workArea)
    }

    static func inwardOrigin(_ tile: CGRect, size: CGSize, in bounds: CGRect) -> CGPoint {
        var o = tile.origin
        if o.x + size.width > bounds.maxX { o.x = max(bounds.minX, bounds.maxX - size.width) }
        if o.y + size.height > bounds.maxY { o.y = max(bounds.minY, bounds.maxY - size.height) }
        return o
    }

    func reconcileFrame(_ c: Client, _ actual: CGRect?, settled: Bool = false) {
        guard let actual = actual ?? windowServerFrame(c.id), server.clientByIdAll(c.id) === c, !c.parked,
              !animator.isAnimating(c.id), server.grab?.client !== c else { return }
        let refused = c.refusedSize
        defer { if c.refusedSize != refused { server.onStateChange?() } }
        if let t = c.geom, MangoServer.frameDistance(actual, t) <= 0.5 { c.retryCount = 0; c.refusedSize = nil }
        if let t = c.geom, let rs = c.refusedSize, actual.width < rs.width - 0.5 || actual.height < rs.height - 0.5 {
            c.refusedSize = actual.width > t.width + 0.5 || actual.height > t.height + 0.5 ? actual.size : nil
        }
        let d = abs(actual.minX - c.frame.minX) + abs(actual.minY - c.frame.minY)
            + abs(actual.width - c.frame.width) + abs(actual.height - c.frame.height)
        let offLayout = !c.isFloating && !c.scratchpadShown
            && c.geom.map { MangoServer.frameDistance(actual, $0) > 0.5 } == true
        guard d > 0.5 || offLayout else { return }
        if c.isFloating { userMoved(c, to: actual, resized: false, dragging: false); return }
        c.frame = actual
        let now = CACurrentMediaTime()
        if !c.isFloating, !c.scratchpadShown, let target = c.geom, MangoServer.frameDistance(actual, target) > 0.5 {
            let larger = actual.width > target.width + 0.5 || actual.height > target.height + 0.5
            let inward = larger && c.mon != nil ? Self.inwardOrigin(target, size: actual.size, in: layoutBounds(c.mon!)) : target.origin
            let atTile = abs(actual.minX - target.minX) <= 1 && abs(actual.minY - target.minY) <= 1
            let atInward = abs(actual.minX - inward.x) <= 1 && abs(actual.minY - inward.y) <= 1
            let refused = (atTile || atInward) && larger
            if !larger { c.refusedSize = nil }
            if refused {
                c.refusedSize = actual.size
                if !atInward, let q = writer(for: c.pid) {
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
                        if now - c.lastReassert < 0.01 { return }
                    }
                }
            } else if now - c.lastReassert > 1.0 || actual.width <= target.width + 0.5 && actual.height <= target.height + 0.5 {
                keepPlaced(c, at: target)
                if now - c.lastReassert < 0.01 { return }
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

    func parkedOrigin(_ c: Client, on m: Monitor) -> CGPoint {
        let others = server.monitors.filter { $0 !== m }.map { $0.screen.frame }
        return Hider.parkedOrigin(size: c.frame.size, workArea: m.screen.workArea,
                                  corner: Hider.corner(for: m.screen.frame, others: others))
    }

    func parkAgainAfterScreensChanged() {
        for c in server.clientsAll where c.parked {
            guard let m = c.mon, c.frame.origin != parkedOrigin(c, on: m) else { continue }
            c.parked = false
            c.parkRetries = 0
            hide(c)
        }
    }

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
