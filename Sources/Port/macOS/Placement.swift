import AppKit
import Mango

extension MacWindowSystem {
    // MARK: wlroots' side of mango's resize and animation

    /// client_set_size. Not in mango: the size is written with the clip; macOS has no configure serial.
    func clientSetSize(_ c: Client, _ width: CGFloat, _ height: CGFloat, _ forceConfigure: Bool) -> UInt32 { 0 }

    /// toplevel->current's min and max size: macOS does not tell them.
    func clientSizeHints(_ c: Client) -> ClientSizeHints { ClientSizeHints() }

    func sceneNodeSetPosition(_ c: Client, _ x: CGFloat, _ y: CGFloat) {
        c.mac.nodePosition = CGPoint(x: x, y: y)
    }

    /// macOS cannot clip another app's window: it is drawn whole, at the size of mango's box without the
    /// border, where the scene node stands, and written when the frame is shown. Where mango's clip would
    /// cut it at its monitor's edge and the rest would land on another monitor, it is parked instead
    /// (docs/afvigelser.md).
    func sceneSubsurfaceTreeSetClip(_ c: Client, _ clip: CGRect) {
        let node = c.mac.nodePosition
        c.mac.box = CGRect(x: node.x + c.bw, y: node.y + c.bw,
                           width: c.animation.current.width - 2 * c.bw, height: c.animation.current.height - 2 * c.bw)
        writeAtCommit.insert(c.id)
        if let m = c.mon { frameClock.schedule(m) }
    }

    func sceneNodeSetEnabled(_ c: Client, _ enabled: Bool) {
        c.mac.sceneNodeEnabled = enabled
        showOrPark(c)
    }

    func sceneSurfaceSetEnabled(_ c: Client, _ enabled: Bool) {
        c.mac.sceneSurfaceEnabled = enabled
        showOrPark(c)
    }

    func outputScheduleFrame(_ m: Monitor) { frameClock.schedule(m) }

    /// A disabled scene is parked out of sight when the frame is shown (wlroots' output commit), after
    /// the windows shown in the same frame are written; an enabled one is written where mango next puts it.
    func showOrPark(_ c: Client) {
        if c.mac.offEdge { hideEdgePlate(c.id) }
        if !c.mac.sceneNodeEnabled || !c.mac.sceneSurfaceEnabled {
            parkAtCommit.insert(c.id)
            if let m = c.mon { frameClock.schedule(m) }
        } else {
            parkAtCommit.remove(c.id)
            if c.parked {
                c.parked = false
                c.parkRetries = 0
                c.mac.offEdge = false
            }
        }
    }

    /// wlroots' output commit: the scene as the frame left it is shown. The windows are written where
    /// mango last put them, then the ones whose scene the frame disabled are parked.
    func commitFrame() {
        let writes = writeAtCommit
        writeAtCommit.removeAll()
        var changed = false
        for id in writes {
            guard let c = server.clientByIdAll(id) else { continue }
            let (frame, parked) = (c.frame, c.parked)
            place(c, c.mac.box)
            changed = changed || c.frame != frame || c.parked != parked
        }
        let ids = parkAtCommit
        parkAtCommit.removeAll()
        for id in ids {
            guard let c = server.clientByIdAll(id), !c.mac.sceneNodeEnabled || !c.mac.sceneSurfaceEnabled else { continue }
            let parked = c.parked
            park(c)
            changed = changed || c.parked != parked
        }
        // the borders follow the windows as they are now shown, not as the frame left them before
        if changed { server.updateBorders() }
    }

    /// Where mango clips the window at its monitor's edge (client_is_ignore_output_clip is false) and
    /// the part beyond would be drawn on another monitor.
    func reachesAnotherMonitor(_ c: Client, _ box: CGRect) -> Bool {
        guard let m = c.mon, !server.clientIsIgnoreOutputClip(c), !m.screen.frame.contains(box) else { return false }
        return server.monitors.contains { o in
            o !== m && !o.screen.frame.intersection(box).isEmpty
        }
    }

    /// Writes the window's frame: each step of an animation, and at its end the frame it is to keep.
    func place(_ c: Client, _ box: CGRect) {
        c.mac.box = box
        guard c.mac.sceneNodeEnabled, c.mac.sceneSurfaceEnabled else { return }
        guard !c.leftToMacOS else { return }   // Port extension: chutney_fullscreen_tag (leftToMacOS)
        if reachesAnotherMonitor(c, box) {
            if !c.parked { park(c); c.mac.offEdge = true }
            if c.mac.offEdge { showEdgePlate(c, box: box) }
            return
        }
        if c.parked {
            guard c.mac.offEdge else { return }
            c.mac.offEdge = false
            hideEdgePlate(c.id)
            c.parked = false
            c.parkRetries = 0
        }
        guard let q = writer(for: c.pid) else { return }
        var target = box.rounded()
        let final = !c.animation.running
        if final, let rs = c.refusedSize, !c.isfloating, let m = c.mon,
           rs.width > target.width + 0.5 || rs.height > target.height + 0.5 {
            let size = CGSize(width: max(rs.width, target.width), height: max(rs.height, target.height))
            target.origin = Self.inwardOrigin(target, size: size, in: layoutBounds(m))
        }
        let wasMoving = c.mac.moving
        c.mac.moving = !final
        if target == c.frame && !(final && wasMoving) {
            if final && c.refusedSize != nil { reconcileFrame(c, c.frame) }   // its tile is where it stands: no longer over
            return
        }
        let now = CACurrentMediaTime()
        let left = final ? 0 : max(0, Double(c.animation.duration) - Double(getNowInMs() &- c.animation.timeStarted)) / 1000
        c.ignoreMovesUntil = now + left + 0.4
        watcher.suppressGeometry(c.id, until: now + left + 0.05)
        c.writes += 1
        let resized = target.size != c.frame.size
        c.frame = target
        q.setFrame(c.element, id: c.id, frame: target, setSize: final || resized, animating: !final && resized)
        if final { verifyFrame(c) }
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
            place(c, target)
            return
        }
        guard !c.deferredRetryPending else { return }
        c.deferredRetryPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + wait + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                c.deferredRetryPending = false
                guard let self, self.server.clientByIdAll(c.id) === c, c.mac.box == target, !c.parked,
                      !c.animation.running, let q = self.writer(for: c.pid) else { return }
                self.readBack(c, q)
            }
        }
    }

    func layoutBounds(_ m: Monitor) -> CGRect {
        let tiles = server.tiledClients(m).map(\.tile).reduce(CGRect.null) { $0.union($1) }
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
              !c.animation.running, server.grab?.client !== c else { return }
        let refused = c.refusedSize
        defer { if c.refusedSize != refused { server.onStateChange?() } }
        if MangoServer.frameDistance(actual, c.mac.box) <= 0.5 { c.retryCount = 0; c.refusedSize = nil }
        if let rs = c.refusedSize, actual.width < rs.width - 0.5 || actual.height < rs.height - 0.5 {
            let t = c.mac.box
            c.refusedSize = actual.width > t.width + 0.5 || actual.height > t.height + 0.5 ? actual.size : nil
        }
        let d = abs(actual.minX - c.frame.minX) + abs(actual.minY - c.frame.minY)
            + abs(actual.width - c.frame.width) + abs(actual.height - c.frame.height)
        let offLayout = !c.isfloating && !SCRATCHPAD_SHOWN(c)
            && MangoServer.frameDistance(actual, c.mac.box) > 0.5
        guard d > 0.5 || offLayout else { return }
        if c.isfloating { userMoved(c, to: actual, resized: false, dragging: false); return }
        c.frame = actual
        let now = CACurrentMediaTime()
        let target = c.mac.box
        if !c.isfloating, !SCRATCHPAD_SHOWN(c), MangoServer.frameDistance(actual, target) > 0.5 {
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

    /// The port's disabled scene node: the window out of sight in a corner of its monitor.
    func park(_ c: Client) {
        // Port extension: chutney_fullscreen_tag (leftToMacOS, fullscreenTagViewed)
        guard !c.parked, !c.leftToMacOS, !fullscreenTagViewed(c), let m = c.mon, let q = writer(for: c.pid) else { return }
        c.mac.moving = false
        c.parked = true
        c.frame = CGRect(origin: parkedOrigin(c, on: m), size: c.frame.size)
        c.ignoreMovesUntil = CACurrentMediaTime() + 0.5
        watcher.suppressGeometry(c.id, until: c.ignoreMovesUntil)
        q.setFrame(c.element, id: c.id, frame: c.frame, setSize: false)
        q.readBack(c.element) { [weak self] actual in self?.keepHidden(c, seenAt: actual) }
    }

    /// Port extension: chutney_fullscreen_tag. While an F tag is viewed the desktop's windows are in
    /// another Space: they stay where they are.
    func fullscreenTagViewed(_ c: Client) -> Bool {
        guard let m = c.mon else { return false }
        return FullscreenTag.isFullscreenView(m, server.config)
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
            park(c)
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
        park(c)
    }
}
