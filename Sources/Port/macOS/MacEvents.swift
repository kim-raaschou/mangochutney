import AppKit
import Mango

extension MacWindowSystem: AppWatcherDelegate {
    func windowDiscovered(_ w: DiscoveredWindow) {
        guard server.clientByIdAll(w.id) == nil else { return }
        let c = Client(window: w, monitor: server.selectedMonitor, tags: 0)
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
    }

    private func mapInitial(_ c: Client) {
        c.isPendingOpenAnimation = false
        c.mon = nil
        server.clientInsertTilingOrder(c)
        server.focusStack.insert(c.id, at: 0)
        let frame = c.floatGeom
        let selected = server.selectedMonitor
        server.selectedMonitor = server.monitorAtPoint(c.frame.center) ?? selected
        let (mon, tags) = server.clientSetRules(c, mapped: false)
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
        wlrLog(.debug, "new window \(c.id) \(c.appid) '\(c.title)' floating=\(c.isFloating) dialog=\(c.mac.isFloatType)")
        scheduleInitialSettle()
    }

    func mapBack(_ c: Client, _ d: DepartedWindow, initial: Bool) {
        c.mon = nil
        server.clients.insert(c, at: DepartedWindow.insertionIndex(of: c.id, snapshot: d.orderSnapshot,
                                                                   into: server.clients.map(\.id)))
        server.focusStack.append(c.id)
        var (mon, _) = server.clientSetRules(c, mapped: false)
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
        c.isPendingOpenAnimation = false
        server.layoutStateInsert(c, on: mon)
        c.mon = mon
        c.tags = d.tags
        wlrLog(.info, "\(c.appName): window \(c.id) is back; restored its tag and place")
        memory.returned(server, c)
        wlrLog(.debug, "new window \(c.id) \(c.appid) '\(c.title)' floating=\(c.isFloating) dialog=\(c.mac.isFloatType) (returned)")
        if initial { scheduleInitialSettle(); return }
        if let cm = c.mon { server.arrange(cm, .move) }
        server.printstatus()
    }

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
                    wlrLog(.info, "managing \(self.server.clients.count) window(s)")
                }
            }
        }
    }

    func windowDestroyed(id: CGWindowID) {
        if away.removeValue(forKey: id) != nil { return }
        guard let c = server.clientByIdAll(id) else { return }
        server.handleClientUnmap(c)
        server.handleClientDestroy(c)
    }

    func windowFocused(id: CGWindowID) {
        guard let c = server.clientByIdAll(id), let m = c.mon else { return }
        wlrLog(.debug, "\(c.appName): macOS focused window \(id) (mango's \(m.sel.map(String.init) ?? "none"))")
        if let ov = server.overviewState {
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
        parkAgainAfterScreensChanged()
    }

    func appActivated(pid: pid_t) {
        restack(pid: pid)
        watcher.requestFocusReport(pid: pid)
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
            c.element = element
            if s.minimized == false { comeBack(id, .minimized) }
            if s.fullscreen == false { comeBack(id, .fullscreen) }
            if !s.appHidden { comeBack(id, .hidden) }
            return
        }
        guard let c = server.clientByIdAll(id) else { return }
        c.element = element
        guard let m = c.mon else { return }
        animator.cancel(c.id)
        if s.minimized == true || s.fullscreen == true || s.appHidden {
            wlrLog(.info, "\(c.appName): window \(c.id) went away while its element was dead (minimized \(s.minimized ?? false), fullscreen \(s.fullscreen ?? false), hidden \(s.appHidden))")
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
                wlrLog(.info, "\(e.client.appName): window \(id) answers again")
                comeBack(id, .stuck)
            }
            return
        }
        for c in server.clientsAll where c.pid == pid {
            guard let m = c.mon, Self.isStuckAway(realFrame: windowServerFrame(c.id), screen: m.screen.frame) else { continue }
            if let real = windowServerFrame(c.id) { c.frame = real }
            goAway(c, .stuck)
        }
    }

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

    func moved(_ c: Client, to actual: CGRect, resized: Bool) {
        guard !missionControl.isActive else { return }
        if animator.isAnimating(c.id) { return }
        if server.grab?.client === c { return }
        if c.parked { keepHidden(c, seenAt: actual); return }
        if CACurrentMediaTime() < c.ignoreMovesUntil {
            if actual != c.frame {
                c.frame = actual
                server.updateBorders()
            }
            return
        }
        userMoved(c, to: actual, resized: resized, dragging: mouseButtons & 1 != 0)
    }
}
