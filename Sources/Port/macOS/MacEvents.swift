import AppKit
import Mango

/// The Accessibility events of other apps' windows, given to mango's handlers as wlroots
/// gives them (handle_client_map, handle_client_unmap and handle_client_destroy,
/// handle_client_activation_request, handle_client_request_minimize,
/// handle_client_set_title), plus userMoved, the macOS layer's own. What only macOS has
/// (hidden and frozen apps, windows that come back around sleep, native fullscreen, our
/// own writes settling) stays here (docs/plan-kerne-backend.md, trin 5).
extension MacWindowSystem: AppWatcherDelegate {
    /// A window found. A new one is mango's handle_client_map. Not in mango: one that was
    /// there when mango started, or is back after sleep or a restart, is placed here instead
    /// (mango starts with no windows, and has none that come back): it keeps its place, takes
    /// no focus, and a window back gets its old tags, monitor and place in the order.
    func windowDiscovered(_ w: DiscoveredWindow) {
        guard server.clientByIdAll(w.id) == nil else { return }
        let c = Client(window: w, monitor: server.selectedMonitor, tags: 0)
        // not in mango: a window macOS has away is mapped when it is back
        var reasons: Set<AwayReason> = []
        if w.isMinimized { reasons.insert(.minimized) }
        if w.isFullscreen { reasons.insert(.fullscreen) }
        if w.isAppHidden { reasons.insert(.hidden) }
        if !reasons.isEmpty { foundAway(c, reasons); return }
        let initial = w.isInitial || !server.started
        if let d = memory.back(c) {
            mapBack(c, d, initial: initial)
        } else if initial {
            mapInitial(c)
        } else {
            server.handleClientMap(c)
        }
        Log.debug("focus: new window \(w.id) mapped; mango's is \(server.focused.map { "\($0.appName) \($0.id)" } ?? "none")")
    }

    /// A window there when mango started: mango's rules (client_apply_rules, before the map),
    /// on the monitor it is on, where it is; laid out once all are in.
    private func mapInitial(_ c: Client) {
        c.isNew = false
        c.mon = nil
        server.clientInsertTilingOrder(c)
        server.focusStack.insert(c.id, at: 0)
        let frame = c.floatGeom
        // mango's rules start from the selected monitor: the one the window is on
        let selected = server.selectedMonitor
        server.selectedMonitor = server.monitorAtPoint(c.frame.center) ?? selected
        let (mon, tags) = server.clientApplyRules(c, mapped: false)
        server.selectedMonitor = selected
        if !c.isCustomPos {
            c.floatGeom = frame
            if c.isFloating, !mon.screen.frame.intersects(frame) {
                let w = mon.screen.workArea
                c.floatGeom = CGRect(x: w.midX - frame.width / 2, y: w.midY - frame.height / 2, width: frame.width, height: frame.height)
            }
        }
        server.layoutStateInsert(c, on: mon)
        c.mon = mon
        server.clientResetMonTags(c, mon, tags)
        server.checkMatchTagFloatingRule(c, mon)
        Log.debug("new window \(c.id) \(c.appid) '\(c.title)' floating=\(c.isFloating) dialog=\(c.mac.isFloatType)")
        scheduleInitialSettle()
    }

    /// A window back after sleep or a restart: mango's rules, then what it had when it left;
    /// between its old neighbours in the order, last in the focus stack, not focused.
    func mapBack(_ c: Client, _ d: DepartedWindow, initial: Bool) {
        c.mon = nil
        server.clients.insert(c, at: DepartedWindow.insertionIndex(of: c.id, snapshot: d.orderSnapshot,
                                                                   into: server.clients.map(\.id)))
        server.focusStack.append(c.id)
        var (mon, _) = server.clientApplyRules(c, mapped: false)
        c.oldmonname = d.homeDisplayID
        if let m = server.monitors.first(where: { $0.screen.displayID == d.displayID }) {
            mon = m
        } else {
            c.oldmonname = d.displayID
        }
        c.isFloating = d.isFloating
        c.isGlobal = d.isGlobal
        c.isOverlay = d.isOverlay
        c.isInScratchpad = d.isMinimized
        c.isMinimized = d.isMinimized && !d.isScratchpad
        c.isNamedScratchpad = d.isNamedScratchpad
        c.floatGeom = d.floatFrame
        c.scrollerProportion = d.scrollerProportion
        c.isCustomSize = d.isCustomSize
        c.isNew = false
        server.layoutStateInsert(c, on: mon)
        c.mon = mon
        c.tags = d.tags
        Log.info("\(c.appName): window \(c.id) is back; restored its tag and place")
        memory.returned(server, c)
        Log.debug("new window \(c.id) \(c.appid) '\(c.title)' floating=\(c.isFloating) dialog=\(c.mac.isFloatType) (returned)")
        if initial { scheduleInitialSettle(); return }
        if let cm = c.mon { server.arrange(cm, .move) }
        server.printstatus()
    }

    /// The windows found at start are laid out once, after the events already waiting, so
    /// the apps whose first scans arrived together are laid out in one go (no timer).
    private func scheduleInitialSettle() {
        guard !initialSettlePending else { return }
        initialSettlePending = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.initialSettlePending = false
                self.server.arrangeAll(.none)
                if self.server.focused == nil, let c = self.server.clientFocusTop(self.server.selectedMonitor) {
                    self.server.clientFocus(c)
                }
                self.server.printstatus()
                if self.server.clients.count != self.loggedWindowCount {
                    self.loggedWindowCount = self.server.clients.count
                    Log.info("managing \(self.server.clients.count) window(s)")
                }
            }
        }
    }

    /// A window gone on macOS is unmapped and destroyed at once.
    func windowDestroyed(id: CGWindowID) {
        if away.removeValue(forKey: id) != nil { return }   // unmapped already
        guard let c = server.clientByIdAll(id) else { return }
        server.handleClientUnmap(c)
        server.handleClientDestroy(c)
    }

    /// Not in mango: macOS has focused the window already (a click, the Dock, ⌘Tab) and says
    /// so afterwards. A click on a window in view is mango's click, which focuses it; in
    /// overview another window than mango's is the window chosen; a parked group member takes its group's place; a
    /// hidden scratchpad window stays hidden. Only a window out of view is mango's
    /// activation request.
    func windowFocused(id: CGWindowID) {
        guard let c = server.clientByIdAll(id), let m = c.mon else { return }
        Log.debug("focus: macOS focused \(c.appName) \(id); mango's is \(server.focused.map { "\($0.appName) \($0.id)" } ?? "none")")
        if let ov = server.overviewState {
            // mango's own focus said back (focusdir, focusstack in overview): the overview stays. An echo
            // that comes after mango has moved on again is taken as a window chosen.
            if ov.jump == nil, server.focused !== c { server.leaveOverview(select: c) }
            return
        }
        if c.groupParked { server.clientFocusGroupMember(c); return }
        if c.isVisible(on: m) {
            if m.sel == id && server.selectedMonitor === m { restack(); return }
            server.clientFocus(c, raise: false)
            return
        }
        if c.isMinimized { return }
        server.handleClientActivationRequest(c)
    }

    func windowMinimized(id: CGWindowID, minimized: Bool) {
        if !minimized, away[id] != nil { comeBack(id, .minimized, focus: true); return }
        guard let c = server.clientByIdAll(id) else { return }
        minimizedByMacOS(c, minimized)
    }

    /// Not in mango: the Dock has minimized the window already (⌘M, the yellow button).
    /// Without ignore_minimize mango takes the minimize: the window comes back from the Dock
    /// at once and mango's handler puts it in its minimized pool. With it (mango's default)
    /// mango refuses, which macOS cannot: the window is away in the Dock (AwayWindows).
    func minimizedByMacOS(_ c: Client, _ minimized: Bool) {
        if minimized && c.ignoreMinimize { goAway(c, .minimized); return }
        if minimized { unminimize(c) }
        server.handleClientRequestMinimize(c, minimized)
    }

    func windowTitleChanged(id: CGWindowID, title: String) {
        if let c = away[id]?.client { c.title = title; return }
        guard let c = server.clientByIdAll(id) else { return }
        c.title = title
        server.handleClientSetTitle(c)
    }

    func appTerminated(pid: pid_t) {
        for (id, e) in away where e.client.pid == pid { away.removeValue(forKey: id) }
        for c in server.clientsAll where c.pid == pid { windowDestroyed(id: c.id) }
    }

    func screensChanged() {
        animator.screensChanged()
        server.handleOutputLayoutChange()
        parkAgainAfterScreensChanged()   // not in mango: the hidden windows' corners moved too
    }

    func appActivated(pid: pid_t) {
        Log.debug("focus: \(NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)") became active")
        restack(pid: pid)   // activation brings the app's windows above our overlays
        watcher.requestFocusReport(pid: pid)   // answers via windowFocused
    }

    func appHidden(pid: pid_t, hidden: Bool) {
        if hidden {
            for c in server.clientsAll where c.pid == pid { goAway(c, .hidden) }
            for e in away.values where e.client.pid == pid { goAway(e.client, .hidden) }
        } else {
            for (id, e) in away where e.client.pid == pid { comeBack(id, .hidden) }
        }
    }

    func windowReacquired(id: CGWindowID, element: AXUIElement, state s: ReacquiredState) {
        memory.departed.endWave()
        if let c = away[id]?.client {
            // Away while the element was dead: back if what kept it away is over.
            c.element = element
            if s.minimized == false { comeBack(id, .minimized) }
            if s.fullscreen == false { comeBack(id, .fullscreen) }
            if !s.appHidden { comeBack(id, .hidden) }
            return
        }
        guard let c = server.clientByIdAll(id) else { return }
        c.element = element   // even without a monitor (display change): it is the only live one
        guard let m = c.mon else { return }
        animator.cancel(c.id)
        // While the element was dead our writes went nowhere and the app reported
        // nothing. Take the window as it is now; arrange then puts it back where the
        // layout has it (or parks it again) if it is not there.
        if s.minimized == true || s.fullscreen == true || s.appHidden {
            Log.info("\(c.appName): window \(c.id) went away while its element was dead (minimized \(s.minimized ?? false), fullscreen \(s.fullscreen ?? false), hidden \(s.appHidden))")
            if s.minimized == true { minimizedByMacOS(c, true) }
            if s.fullscreen == true { goAway(c, .fullscreen) }
            if s.appHidden { goAway(c, .hidden) }
            return
        }
        guard let f = s.frame, f != c.frame else { return }
        c.frame = f
        c.parked = false
        server.arrange(m, .none)
        server.printstatus()
    }

    func appResponding(pid: pid_t, responding: Bool) {
        if responding {
            for (id, e) in away where e.client.pid == pid && e.reasons.contains(.stuck) {
                Log.info("\(e.client.appName): window \(id) answers again")
                comeBack(id, .stuck)
            }
            return
        }
        for c in server.clientsAll where c.pid == pid {
            guard let m = c.mon, Self.isStuckAway(realFrame: windowServerFrame(c.id), screen: m.screen.frame) else { continue }
            // Frozen while parked: frames written to it are not applied until it answers.
            if let real = windowServerFrame(c.id) { c.frame = real }
            goAway(c, .stuck)
        }
    }

    /// A frozen app's window counts as away when the window server has it parked (a
    /// sliver in a corner) or nowhere on its screen. A frozen window that is in view stays
    /// in the layout where it is.
    nonisolated static func isStuckAway(realFrame: CGRect?, screen: CGRect) -> Bool {
        guard let f = realFrame else { return false }
        return Hider.isParked(f, in: screen) || !f.intersects(screen)
    }

    func windowGeometryChanged(id: CGWindowID, frame: CGRect, resized: Bool, isFullscreen: Bool?) {
        if isFullscreen == false, away[id]?.reasons.contains(.fullscreen) == true { comeBack(id, .fullscreen); return }
        if isFullscreen == true, let c = server.clientByIdAll(id) { goAway(c, .fullscreen); return }
        guard let c = server.clientByIdAll(id) else { return }
        moved(c, to: frame, resized: resized)
    }

    /// A move/resize we did not cause: user drag, or the app moved itself.
    func moved(_ c: Client, to actual: CGRect, resized: Bool) {
        guard !missionControl.isActive else { return }
        if animator.isAnimating(c.id) { return }
        if server.grab?.client === c { return }
        if c.parked { keepHidden(c, seenAt: actual); return }
        if CACurrentMediaTime() < c.ignoreMovesUntil {
            // Our own write settling. `c.frame` was set to the *requested* frame;
            // the app may have clamped it (minimum size, aspect ratio, ...). Record
            // what it actually did so borders follow the real window and the next
            // arrange does not skip it as "already in place".
            if actual != c.frame {
                c.frame = actual
                server.updateBorders()
            }
            return
        }
        userMoved(c, to: actual, resized: resized, dragging: mouseButtons & 1 != 0)
    }
}
