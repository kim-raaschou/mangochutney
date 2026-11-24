import AppKit
import Mango

/// What the port wrote to one window's app and what the app answered: the window's place as the port
/// holds it. Written here only.
@MainActor
final class PlacedWindow {
    /// The frames handed to the app and the last one it answered; while they differ the border stands
    /// where the app last put the window (applied; nil: not in view), as wlroots shows both in one frame.
    fileprivate(set) var writeSerial = 0
    fileprivate(set) var confirmedSerial = 0
    fileprivate(set) var applied: CGRect?
    var inSync: Bool { writeSerial == confirmedSerial }
    /// The frames written so far: a read tells whether another was written after it.
    fileprivate(set) var writes = 0
    /// Whether the last frame written was a step of an animation.
    fileprivate(set) var moving = false
    /// Parked because the part mango clips away would land on another monitor.
    fileprivate(set) var offEdge = false
    /// Shown again after it was parked, and the app has not yet moved it back: no border till then, as
    /// wlroots shows the border and the window in one frame.
    fileprivate(set) var comingBack = false
    /// Till then the app's moves are its answers to the port's writes, not the user's.
    fileprivate(set) var ignoreMovesUntil: TimeInterval = 0
    /// The size the app keeps the window at, larger than its tile; nil while it takes its tile.
    fileprivate(set) var refusedSize: CGSize?
    fileprivate(set) var lastReassert: TimeInterval = 0
    fileprivate(set) var retryTarget: CGRect?
    fileprivate(set) var retryCount = 0
    fileprivate(set) var parkRetries = 0
    /// The display whose corner the window is parked in.
    fileprivate(set) var parkedOn: CGDirectDisplayID?
    fileprivate(set) var deferredRetryPending = false
}

/// What the next frame writes and parks, and the windows leaving that wait for those coming back.
/// Written here only.
@MainActor
struct Placing {
    fileprivate(set) var writeAtCommit: Set<ClientID> = []
    fileprivate(set) var parkAtCommit: Set<ClientID> = []
    /// The windows shown again at a frame and the write that puts them in view; the windows leaving
    /// at that frame wait for them (commitFrame).
    fileprivate(set) var arriving: [ClientID: Int] = [:]
    fileprivate(set) var parkWhenArrived: Set<ClientID> = []
    /// mango's skip_frame_timeout and resizing_count_current, per monitor (its display).
    fileprivate var skipFrameTimeout: [CGDirectDisplayID: PortTimer] = [:]
    fileprivate var resizingCountCurrent: [CGDirectDisplayID: Int] = [:]
    fileprivate var bordersFollowQueued = false
}

extension Client {
    /// The size the app keeps the window at, larger than its tile; nil while it takes its tile.
    var refusedSize: CGSize? { mac.placed.refusedSize }
}

extension MacWindowSystem {
    // MARK: What the rest of the port asks and tells

    /// Whether a move of the window is the app answering the port's write, not the user moving it.
    func answersPortsWrite(_ c: Client) -> Bool { clock.now < c.mac.placed.ignoreMovesUntil }

    /// macOS shows the window again (it put it back after fullscreen): it is no longer parked.
    func shownByMacOS(_ c: Client) {
        c.parked = false
        c.mac.placed.parkRetries = 0
    }

    /// What the port knew of the window's place: the size its app kept it at and the writes it was
    /// retrying are not the ones it comes back to.
    func forgetPlacement(_ c: Client) {
        let p = c.mac.placed
        p.refusedSize = nil
        p.retryTarget = nil
        p.retryCount = 0
    }

    /// The app's moves of the window are its answers to the port's write for `seconds`; the watcher drops
    /// them for `atSource`.
    private func holdMoves(_ c: Client, for seconds: TimeInterval, atSource: TimeInterval) {
        c.mac.placed.ignoreMovesUntil = clock.now + seconds
        watcher.suppressGeometry(c.windowID, for: atSource)
    }

    // MARK: wlroots' side of mango's resize and animation

    /// client_set_size. Not in mango: the size is written with the clip; macOS has no configure serial.
    func clientSetSize(_ c: Client, _ width: CGFloat, _ height: CGFloat, _ forceConfigure: Bool) -> UInt32 { 0 }

    /// toplevel->current's min and max size: macOS does not tell them.
    func clientSizeHints(_ c: Client) -> ClientSizeHints { ClientSizeHints() }
    /// The window's size where it stands, and where it stands (the surface is the macOS window).
    func clientGetGeometry(_ c: Client) -> CGRect { CGRect(origin: .zero, size: c.frame.size) }
    func sceneSurfaceCoords(_ c: Client) -> CGPoint { c.frame.origin }

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
        placing.writeAtCommit.insert(c.windowID)
        if let m = monitor(of: c) { frameClock.schedule(m) }
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
        let p = c.mac.placed
        if p.offEdge { hideEdgePlate(c.windowID) }
        if !c.mac.sceneNodeEnabled || !c.mac.sceneSurfaceEnabled {
            placing.parkAtCommit.insert(c.windowID)
            if let m = monitor(of: c) { frameClock.schedule(m) }
        } else {
            placing.parkAtCommit.remove(c.windowID)
            if c.parked {
                c.parked = false
                p.parkRetries = 0
                p.offEdge = false
                p.comingBack = true
            }
        }
    }

    /// wlroots' output commit: the scene as the frame left it is shown. The windows are written where
    /// mango last put them, then the ones whose scene the frame disabled are parked.
    func commitFrame() {
        let writes = placing.writeAtCommit
        placing.writeAtCommit.removeAll()
        var changed = false
        for id in writes {
            guard let c = server.clientByWindowID(id) else { continue }
            let (frame, parked) = (c.frame, c.parked)
            place(c, c.mac.box)
            changed = changed || c.frame != frame || c.parked != parked
            if c.mac.placed.comingBack { placing.arriving[c.windowID] = c.mac.placed.writeSerial }
        }
        let ids = placing.parkAtCommit
        placing.parkAtCommit.removeAll()
        // wlroots shows the frame at once; here each app moves its own window. As mango skips a frame
        // while a client it resized has not answered (handle_output_frame, with no animations and no
        // grab), the windows leaving wait till the ones coming back on their monitor stand in view, or
        // the desktop shows between them; at most mango's 100 ms (skip_frame_timeout).
        var leave = ids
        if !server.config.animations && server.grabClient == nil {
            _ = stillArriving()
            for m in server.monitors where placing.arriving.keys.contains(where: { server.clientByWindowID($0)?.mon === m }) {
                let waiting = ids.filter { server.clientByWindowID($0)?.mon === m }
                guard !waiting.isEmpty else { continue }
                placing.parkWhenArrived.formUnion(waiting)
                leave.subtract(waiting)
                monitorCheckSkipFrameTimeout(m)
            }
        }
        changed = parkDisabled(leave) || changed
        // A disabled scene the port could not park when it was disabled (macOS had the window in
        // fullscreen, or an F tag was viewed) is parked at the first frame that can.
        for c in server.clientsAll where !c.parked && (!c.mac.sceneNodeEnabled || !c.mac.sceneSurfaceEnabled)
            && !leftToMacOS(c) && !fullscreenTagViewed(c) && !ids.contains(c.windowID) && !placing.parkWhenArrived.contains(c.windowID) {
            park(c)
            changed = changed || c.parked
        }
        // A disabled scene goes with its client to another monitor: a window parked in another
        // monitor's corner is parked in its own.
        for c in server.clientsAll where c.parked && (!c.mac.sceneNodeEnabled || !c.mac.sceneSurfaceEnabled) {
            guard let m = monitor(of: c), c.mac.placed.parkedOn != m.screen.displayID else { continue }
            c.parked = false
            c.mac.placed.parkRetries = 0
            park(c)
            changed = true
        }
        // the borders follow the windows as they are now shown, not as the frame left them before
        if changed { server.updateBorders() }
    }

    /// Parks the clients whose scene is still disabled; whether any of them moved.
    func parkDisabled(_ ids: Set<ClientID>) -> Bool {
        var changed = false
        for id in ids {
            guard let c = server.clientByWindowID(id), !c.mac.sceneNodeEnabled || !c.mac.sceneSurfaceEnabled else { continue }
            let parked = c.parked
            park(c)
            changed = changed || c.parked != parked
        }
        return changed
    }

    /// Whether a window shown again is not yet where it was written: its app has not answered.
    func stillArriving() -> Bool {
        placing.arriving = placing.arriving.filter { id, serial in
            guard let c = server.clientByWindowID(id), c.mac.sceneNodeEnabled, c.mac.sceneSurfaceEnabled, !c.parked else { return false }
            return c.mac.placed.confirmedSerial < serial
        }
        return !placing.arriving.isEmpty
    }

    /// The windows that waited for the ones coming back are parked once those on their monitor stand in
    /// view (mango's frame no longer skipped).
    func parkArrived() {
        guard !placing.parkWhenArrived.isEmpty else { return }
        _ = stillArriving()
        let held = Set(placing.arriving.keys.compactMap { server.clientByWindowID($0)?.mon?.screen.displayID })
        let ids = placing.parkWhenArrived.filter { id in
            server.clientByWindowID(id)?.mon.map { !held.contains($0.screen.displayID) } ?? true
        }
        guard !ids.isEmpty else { return }
        placing.parkWhenArrived.subtract(ids)
        for d in Set(placing.skipFrameTimeout.keys).subtracting(held) { monitorStopSkipFrameTimer(d) }
        if parkDisabled(ids) { server.updateBorders() }
    }

    /// mango monitor_check_skip_frame_timeout (monitor.c): the frame waits for the clients resized on
    /// the monitor, at most 100 ms; again from the start when more are resized. A timer, as mango's.
    func monitorCheckSkipFrameTimeout(_ m: Monitor) {
        let d = m.screen.displayID
        let pending = placing.arriving.keys.filter { server.clientByWindowID($0)?.mon === m }.count   // resizing_count_pending
        if placing.skipFrameTimeout[d] != nil && placing.resizingCountCurrent[d] == pending { return }
        placing.skipFrameTimeout[d]?.cancel()
        placing.resizingCountCurrent[d] = pending
        placing.skipFrameTimeout[d] = clock.after(0.1) { [weak self] in   // 100ms
            self?.monitorSkipFrameTimeoutCallback(d)
        }
    }

    /// mango monitor_skip_frame_timeout_callback (monitor.c): no client is waited for any longer, and
    /// the frame is shown: the windows leaving are parked.
    func monitorSkipFrameTimeoutCallback(_ d: CGDirectDisplayID) {
        placing.arriving.removeAll()
        monitorStopSkipFrameTimer(d)
        parkArrived()
    }

    /// mango monitor_stop_skip_frame_timer (monitor.c).
    func monitorStopSkipFrameTimer(_ d: CGDirectDisplayID) {
        placing.skipFrameTimeout[d]?.cancel()
        placing.skipFrameTimeout[d] = nil
        placing.resizingCountCurrent[d] = nil
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
        let p = c.mac.placed
        let comingBack = p.comingBack
        p.comingBack = false
        var held = false
        defer { if comingBack && !held { server.updateBorders() } }
        guard c.mac.sceneNodeEnabled, c.mac.sceneSurfaceEnabled else { return }
        guard !leftToMacOS(c) else { return }   // Port extension: chutney_fullscreen_tag (leftToMacOS)
        if reachesAnotherMonitor(c, box) {
            if !c.parked { park(c); p.offEdge = true }
            if p.offEdge { showEdgePlate(c, box: box) }
            return
        }
        if c.parked {
            guard p.offEdge else { return }
            p.offEdge = false
            hideEdgePlate(c.windowID)
            c.parked = false
            p.parkRetries = 0
        }
        guard let q = writer(for: c.pid) else { return }
        var target = box.rounded()
        let final = !c.animation.running
        if final, let rs = p.refusedSize, !c.isfloating, let m = c.mon,
           rs.width > target.width + 0.5 || rs.height > target.height + 0.5 {
            let size = CGSize(width: max(rs.width, target.width), height: max(rs.height, target.height))
            target.origin = Self.inwardOrigin(target, size: size, in: layoutBounds(m))
        }
        let wasMoving = p.moving
        p.moving = !final
        if target == c.frame && !(final && wasMoving) {
            if final && p.refusedSize != nil { reconcileFrame(c, c.frame) }   // its tile is where it stands: no longer over
            return
        }
        let left = final ? 0 : max(0, Double(c.animation.duration) - Double(getNowInMs() &- c.animation.timeStarted)) / 1000
        holdMoves(c, for: left + 0.4, atSource: left + 0.05)
        p.writes += 1
        let resized = target.size != c.frame.size
        let was = c.frame
        c.frame = target
        if comingBack {
            p.comingBack = true
            held = true
            let sent = clock.now
            // Back at the size it was parked with: the position alone is written (one answer from the app,
            // not three); verifyFrame's read finds a size that is not its tile's.
            send(c, q, target, from: nil, setSize: resized || (final && wasMoving), animating: !final && resized) { [weak self] c in
                guard let self, c.mac.placed.comingBack else { return }
                c.mac.placed.comingBack = false
                wlrLog(.debug, "\(c.appName): window \(c.windowID) back in \(Int((self.clock.now - sent) * 1000)) ms")
            }
        } else {
            send(c, q, target, from: was, setSize: resized, animating: !final && resized)
        }
        if final { verifyFrame(c) }
    }

    /// Every frame the port hands an app. `from` is where the window stands now (nil: out of view): till the
    /// app has answered, its border stays where the app last put it.
    func send(_ c: Client, _ q: WindowWriter, _ frame: CGRect, from: CGRect?, setSize: Bool, animating: Bool = false,
              then: (@MainActor (Client) -> Void)? = nil) {
        let w = c.mac.placed
        if w.inSync { w.applied = from }
        w.writeSerial &+= 1
        let serial = w.writeSerial
        q.setFrame(c.element, id: c.windowID, frame: frame, setSize: setSize, animating: animating) { [weak self, weak c] r in
            guard let self else { return }
            defer { self.parkArrived() }
            guard let c, self.server.clientByWindowID(c.windowID) === c else { return }
            c.mac.placed.applied = r
            c.mac.placed.confirmedSerial = serial
            then?(c)
            self.bordersFollow()
        }
    }

    /// The borders and bars shown again once per main-queue turn for all the apps that answered in it (a
    /// flag, no timer); mango's are unchanged by an answer.
    func bordersFollow() {
        guard !placing.bordersFollowQueued else { return }
        placing.bordersFollowQueued = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.placing.bordersFollowQueued = false
                self.showAgain()
            }
        }
    }

    func verifyFrame(_ c: Client) {
        guard let q = writer(for: c.pid) else { return }
        readBack(c, q)
        let late = max(0.6, c.mac.placed.ignoreMovesUntil - clock.now + 0.15)
        clock.after(late) { [weak self] in
            guard let self, self.server.clientByWindowID(c.windowID) === c else { return }
            self.readBack(c, q)
        }
    }

    func readBack(_ c: Client, _ q: WindowWriter) {
        let settled = !answersPortsWrite(c)
        let write = c.mac.placed.writes
        q.readBack(c.element) { [weak self] actual in
            self?.reconcileFrame(c, actual, settled: settled && c.mac.placed.writes == write)
        }
    }

    func keepPlaced(_ c: Client, at target: CGRect) {
        let p = c.mac.placed
        if p.retryTarget != target { p.retryTarget = target; p.retryCount = 0 }
        guard p.retryCount < 3 else {
            if p.retryCount == 3 {
                p.retryCount += 1
                wlrLog(.debug, "\(c.appName): window \(c.windowID) keeps \(c.frame), not its tile \(target); left there")
            }
            return
        }
        let now = clock.now
        let wait = p.lastReassert + 1.0 - now
        if wait <= 0 {
            p.retryCount += 1
            p.lastReassert = now
            place(c, target)
            return
        }
        guard !p.deferredRetryPending else { return }
        p.deferredRetryPending = true
        clock.after(wait + 0.05) { [weak self] in
            p.deferredRetryPending = false
            guard let self, self.server.clientByWindowID(c.windowID) === c, c.mac.box == target, !c.parked,
                  !c.animation.running, let q = self.writer(for: c.pid) else { return }
            self.readBack(c, q)
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
        guard let actual = actual ?? windowServerFrame(c.windowID), server.clientByWindowID(c.windowID) === c, !c.parked,
              !c.animation.running, server.grabClient !== c else { return }
        let p = c.mac.placed
        let refused = p.refusedSize
        defer { if p.refusedSize != refused { server.onStateChange?() } }
        if MangoServer.frameDistance(actual, c.mac.box) <= 0.5 { p.retryCount = 0; p.refusedSize = nil }
        if let rs = p.refusedSize, actual.width < rs.width - 0.5 || actual.height < rs.height - 0.5 {
            let t = c.mac.box
            p.refusedSize = actual.width > t.width + 0.5 || actual.height > t.height + 0.5 ? actual.size : nil
        }
        // AX answers before the app has moved the window: a move not yet seen is only acted on once settled.
        if !settled && abs(actual.width - c.mac.box.width) <= 0.5 && abs(actual.height - c.mac.box.height) <= 0.5 { return }
        let d = abs(actual.minX - c.frame.minX) + abs(actual.minY - c.frame.minY)
            + abs(actual.width - c.frame.width) + abs(actual.height - c.frame.height)
        let offLayout = !c.isfloating && !SCRATCHPAD_SHOWN(c)
            && MangoServer.frameDistance(actual, c.mac.box) > 0.5
        guard d > 0.5 || offLayout else { return }
        if c.isfloating { userMoved(c, to: actual, resized: false, dragging: false); return }
        c.frame = actual
        let now = clock.now
        let target = c.mac.box
        if !c.isfloating, !SCRATCHPAD_SHOWN(c), MangoServer.frameDistance(actual, target) > 0.5 {
            let larger = actual.width > target.width + 0.5 || actual.height > target.height + 0.5
            let inward = larger && c.mon != nil ? Self.inwardOrigin(target, size: actual.size, in: layoutBounds(c.mon!)) : target.origin
            let atTile = abs(actual.minX - target.minX) <= 1 && abs(actual.minY - target.minY) <= 1
            let atInward = abs(actual.minX - inward.x) <= 1 && abs(actual.minY - inward.y) <= 1
            let refused = (atTile || atInward) && larger
            if !larger { p.refusedSize = nil }
            if refused {
                p.refusedSize = actual.size
                if !atInward, let q = writer(for: c.pid) {
                    c.frame = CGRect(origin: inward, size: actual.size)
                    holdMoves(c, for: 0.5, atSource: 0.5)
                    send(c, q, c.frame, from: actual, setSize: false)
                    server.updateBorders()
                    return
                }
                if settled {
                    if p.retryCount == 0 {
                        keepPlaced(c, at: target)
                        if now - p.lastReassert < 0.01 { return }
                    }
                }
            } else if now - p.lastReassert > 1.0 || actual.width <= target.width + 0.5 && actual.height <= target.height + 0.5 {
                keepPlaced(c, at: target)
                if now - p.lastReassert < 0.01 { return }
            }
        }
        server.updateBorders()
    }

    /// The monitor a client's window is on: its own, or for a parked group member (mango's
    /// client_park leaves it no monitor) the one its group is shown on (mango's client_group_active).
    func monitor(of c: Client) -> Monitor? {
        c.mon ?? server.clientGroupActive(c)?.mon
    }

    /// The port's disabled scene node: the window out of sight in a corner of its monitor.
    func park(_ c: Client) {
        // Port extension: chutney_fullscreen_tag (leftToMacOS, fullscreenTagViewed)
        guard !c.parked, !leftToMacOS(c), !fullscreenTagViewed(c), let m = monitor(of: c), let q = writer(for: c.pid) else { return }
        c.mac.placed.moving = false
        c.mac.placed.parkedOn = m.screen.displayID
        c.parked = true
        let was = c.frame
        c.frame = CGRect(origin: parkedOrigin(c, on: m), size: c.frame.size)
        holdMoves(c, for: 0.5, atSource: 0.5)
        send(c, q, c.frame, from: was, setSize: false)
        q.readBack(c.element) { [weak self] actual in self?.keepHidden(c, seenAt: actual) }
    }

    func parkedOrigin(_ c: Client, on m: Monitor) -> CGPoint {
        let others = server.monitors.filter { $0 !== m }.map { $0.screen.frame }
        return Hider.parkedOrigin(size: c.frame.size, workArea: m.screen.workArea,
                                  corner: Hider.corner(for: m.screen.frame, others: others))
    }

    func parkAgainAfterScreensChanged() {
        for c in server.clientsAll where c.parked {
            guard let m = monitor(of: c), c.frame.origin != parkedOrigin(c, on: m) else { continue }
            c.parked = false
            c.mac.placed.parkRetries = 0
            park(c)
        }
    }

    func keepHidden(_ c: Client, seenAt actual: CGRect?) {
        guard server.clientByWindowID(c.windowID) === c, c.parked, !missionControl.isActive, let m = monitor(of: c),
              let actual = actual ?? windowServerFrame(c.windowID) else { return }
        if Hider.isParked(actual, in: m.screen.frame) { return }
        guard c.mac.placed.parkRetries < 3 else { return }
        c.mac.placed.parkRetries += 1
        wlrLog(.debug, "\(c.appName): window \(c.windowID) is hidden but in view at \(actual); parking it again")
        c.frame = actual
        c.parked = false
        park(c)
    }
}
