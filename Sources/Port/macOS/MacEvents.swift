import AppKit
import Mango

extension MacWindowSystem: AppWatcherDelegate {
    func windowDiscovered(_ w: DiscoveredWindow) {
        guard server.clientByIdAll(w.id) == nil else { return }
        let c = Client(window: w, monitor: server.selectedMonitor, tags: 0)
        var reasons: Set<AwayReason> = []
        if w.isminimized { reasons.insert(.minimized) }
        if w.isfullscreen { reasons.insert(.fullscreen) }
        if w.isAppHidden { reasons.insert(.hidden) }
        // Port extension: chutney_fullscreen_tag. In fullscreen it is mapped onto its F tag; with another
        // reason, when it is back from that.
        let onFTag = reasons.contains(.fullscreen) && FullscreenTag.isOn(server)
        if onFTag { reasons.remove(.fullscreen) }
        if !reasons.isEmpty {
            foundAway(c, reasons)
            return
        }
        FullscreenTag.mapInFullscreen(server, c, onFTag) {
            let initial = w.isInitial || !server.started
            if let d = memory.back(c) {
                mapBack(c, d, initial: initial)
            } else if initial {
                mapInitial(c)
            } else {
                wlrLog(.debug, "new window \(c.id) \(c.appid) '\(c.title)'")
                server.handleClientMap(c)
            }
        }
    }

    /// handle_client_map's border and geom, around the window where it stands.
    func initClientGeom(_ c: Client) {
        c.bw = CGFloat(server.config.borderpx)
        c.geom = c.geom.insetBy(dx: -c.bw, dy: -c.bw)
        c.floatGeom = c.geom
        c.overviewBackupGeom = c.geom
    }

    private func mapInitial(_ c: Client) {
        initClientGeom(c)
        c.isPendingOpenAnimation = false
        server.clientAddJumpLabelNode(c)
        c.mon = nil
        server.clientInsertTilingOrder(c)
        server.focusStack.insert(c.id, at: 0)
        let frame = c.floatGeom
        let selected = server.selectedMonitor
        server.selectedMonitor = server.monitorAtPoint(c.frame.center) ?? selected
        let (mon, tags) = server.clientSetRules(c, mapped: false)
        server.selectedMonitor = selected
        if !c.iscustompos {
            c.geom = frame
            c.floatGeom = frame
            if c.isfloating, !mon.screen.frame.intersects(frame) {
                let w = mon.screen.workArea
                c.floatGeom = CGRect(x: w.midX - frame.width / 2, y: w.midY - frame.height / 2, width: frame.width, height: frame.height)
            }
        }
        c.mon = mon
        server.clientResetMonTags(c, mon, tags)
        server.checkMatchTagFloatingRule(c, mon)
        wlrLog(.debug, "new window \(c.id) \(c.appid) '\(c.title)' floating=\(c.isfloating) dialog=\(c.mac.isFloatType)")
        scheduleInitialSettle()
    }

    func mapBack(_ c: Client, _ d: DepartedWindow, initial: Bool) {
        initClientGeom(c)
        server.clientAddJumpLabelNode(c)
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
        c.isfloating = d.isfloating
        c.isglobal = d.isglobal
        c.isoverlay = d.isoverlay
        c.isInScratchpad = d.isminimized
        c.isminimized = d.isminimized && !d.isScratchpad
        c.isnamedscratchpad = d.isnamedscratchpad
        c.floatGeom = d.floatFrame.insetBy(dx: -c.bw, dy: -c.bw)
        if c.isfloating { c.geom = c.floatGeom }   // mango's floating client stands at its float_geom
        if let p = d.scrollerProportion { c.scrollerProportion = Float(p) }
        c.iscustomsize = d.iscustomsize
        c.isPendingOpenAnimation = false
        c.mon = mon
        c.tags = d.tags
        wlrLog(.info, "\(c.appName): window \(c.id) is back; restored its tag and place")
        memory.returned(server, c)
        wlrLog(.debug, "new window \(c.id) \(c.appid) '\(c.title)' floating=\(c.isfloating) dialog=\(c.mac.isFloatType) (returned)")
        if initial { scheduleInitialSettle(); return }
        if let cm = c.mon { server.arrange(cm, false, false) }
        server.printstatus(.arrangge)
    }

    private func scheduleInitialSettle() {
        guard !initialSettlePending else { return }
        initialSettlePending = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.initialSettlePending = false
                self.server.arrangeAll(false)
                if self.server.focused == nil, let c = self.server.clientFocusTop(self.server.selectedMonitor) {
                    self.server.clientFocus(c, true)
                }
                self.server.printstatus(.arrangge)
                if self.server.clients.count != self.loggedWindowCount {
                    self.loggedWindowCount = self.server.clients.count
                    wlrLog(.info, "managing \(self.server.clients.count) window(s)")
                }
            }
        }
    }

    func windowDestroyed(id: CGWindowID) {
        hideEdgePlate(id)
        borders.forget(id)
        if away.removeValue(forKey: id) != nil {
            memory.departed.away.remove(id)
            return
        }
        guard let c = server.clientByIdAll(id) else { return }
        server.handleClientUnmap(c)
        server.handleClientDestroy(c)
    }

    func windowFocused(id: CGWindowID) {
        guard let c = server.clientByIdAll(id) else {
            seatFocus = nil   // the keyboard is on a window mango does not manage
            return
        }
        guard let m = monitor(of: c) else { return }
        wlrLog(.debug, "\(c.appName): macOS focused window \(id) (mango's \(m.sel.map(String.init) ?? "none"))")
        if m.isoverview {
            if !m.isJumpMode, server.focused !== c, m === server.selectedMonitor { server.toggleOverview(Arg(tc: c)) }
            return
        }
        if c.groupParked { server.clientFocusGroupMember(c); return }
        if c.nativeFullscreen, !VISIBLEON(c, m) { FullscreenTag.focusedByMacOS(server, c); return }   // Port extension: chutney_fullscreen_tag
        if VISIBLEON(c, m) {
            if m.sel == id && server.selectedMonitor === m { seatFocus = c; restack(); return }
            macOSFocused = c.id
            server.clientFocus(c, false)
            macOSFocused = nil
            return
        }
        if c.isminimized { return }
        server.handleClientActivationRequest(c)
    }

    func windowMinimized(id: CGWindowID, minimized: Bool) {
        if !minimized, away[id] != nil { comeBack(id, .minimized, focus: true); return }
        guard let c = server.clientByIdAll(id) else { return }
        minimizedByMacOS(c, minimized)
    }

    func minimizedByMacOS(_ c: Client, _ minimized: Bool) {
        if minimized && c.ignoreMinimize { goAway(c, .minimized); return }
        if minimized { clientSetMinimized(c, false) }
        server.handleClientRequestMinimize(c, minimized)
    }

    func windowTitleChanged(id: CGWindowID, title: String) {
        if let c = away[id]?.client { c.title = title; return }
        guard let c = server.clientByIdAll(id) else { return }
        c.title = title
        server.handleClientSetTitle(c)
    }

    func appTerminated(pid: pid_t) {
        TabStripView.forget(pid: pid)
        for (id, e) in away where e.client.pid == pid {
            away.removeValue(forKey: id)
            memory.departed.away.remove(id)
        }
        for c in server.clientsAll where c.pid == pid { windowDestroyed(id: c.id) }
    }

    func screensChanged() {
        frameClock.screensChanged()
        server.rebuildMonitors()
        parkAgainAfterScreensChanged()
    }

    func appActivated(pid: pid_t) {
        if seatFocus?.pid != pid { seatFocus = nil }   // another app has the keyboard
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
            if s.fullscreen == false { backFromFullscreen(id) }
            if !s.appHidden { comeBack(id, .hidden) }
            return
        }
        guard let c = server.clientByIdAll(id) else { return }
        c.element = element
        guard let m = c.mon else { return }
        if s.fullscreen == false, c.nativeFullscreen { fullscreenChanged(c, false) }   // Port extension: chutney_fullscreen_tag
        if s.minimized == true || s.fullscreen == true || s.appHidden {
            wlrLog(.info, "\(c.appName): window \(c.id) went away while its element was dead (minimized \(s.minimized ?? false), fullscreen \(s.fullscreen ?? false), hidden \(s.appHidden))")
            if s.minimized == true { minimizedByMacOS(c, true) }
            if s.fullscreen == true, !c.nativeFullscreen { fullscreenChanged(c, true) }   // Port extension: chutney_fullscreen_tag (else away)
            if s.appHidden { goAway(c, .hidden) }
            return
        }
        guard let f = s.frame, f != c.frame else { return }
        c.frame = f
        c.parked = false
        server.arrange(m, false, false)
        server.printstatus(.arrangge)
    }

    func windowGeometryChanged(id: CGWindowID, frame: CGRect, resized: Bool, isfullscreen: Bool?) {
        if let fs = isfullscreen, windowFullscreenRead(id, fs) { return }
        guard let c = server.clientByIdAll(id) else { return }
        moved(c, to: frame, resized: resized)
    }

    /// macOS's fullscreen read again after a Space change: the resize that tells it can come while the
    /// port writes the window, and be missed.
    func windowFullscreen(id: CGWindowID, fullscreen: Bool) {
        windowFullscreenRead(id, fullscreen, late: true)
    }

    /// A window's macOS fullscreen as read: into it, or out of it, where that is news. Whether it was.
    /// `late`: read after a Space change, so macOS may show another Space by now.
    @discardableResult
    func windowFullscreenRead(_ id: CGWindowID, _ fullscreen: Bool, late: Bool = false) -> Bool {
        if !fullscreen, away[id]?.reasons.contains(.fullscreen) == true {
            backFromFullscreen(id)
            return true
        }
        guard let c = server.clientByIdAll(id) else { return false }
        if late, !fullscreen, c.fullscreenPending, !c.nativeFullscreen {   // Port extension: chutney_fullscreen_tag
            FullscreenTag.notTaken(server, c)
            return true
        }
        guard fullscreen != c.nativeFullscreen else { return false }
        fullscreenChanged(c, fullscreen, late: late)
        return true
    }

    /// The active Space changed: each window back from fullscreen meanwhile is placed again, now that
    /// macOS has finished moving it.
    func spaceChanged() {
        FullscreenTag.followSpace(server)   // Port extension: chutney_fullscreen_tag
        let back = fullscreenReturns
        fullscreenReturns.removeAll()
        for id in back { placeAgain(id) }
    }

    /// A window mango manages went into macOS fullscreen (out of the layout, or to its own tag) or out of it.
    func fullscreenChanged(_ c: Client, _ fullscreen: Bool, late: Bool = false) {
        if fullscreen {
            if FullscreenTag.enter(server, c, discovered: late) { return }   // Port extension: chutney_fullscreen_tag
            goAway(c, .fullscreen)
        } else {
            FullscreenTag.leave(server, c)   // Port extension: chutney_fullscreen_tag
            returnedFromFullscreen(c)
        }
    }

    /// An away window out of macOS fullscreen: back in the layout, and the app says which window has the keys.
    func backFromFullscreen(_ id: ClientID) {
        guard let c = away[id]?.client else { return }
        comeBack(id, .fullscreen)
        guard server.clientByIdAll(id) === c else { return }
        askFocus(c)
        returnedFromFullscreen(c)
    }

    /// macOS moves a window out of fullscreen until its Space change is done, which may come before or
    /// after this: it is placed now, and again at the next Space change.
    func returnedFromFullscreen(_ c: Client) {
        placeAgain(c.id)
        fullscreenReturns.insert(c.id)
    }

    /// The window's frame read again and its monitor's layout written.
    func placeAgain(_ id: ClientID) {
        guard let c = server.clientByIdAll(id), let m = c.mon else { return }
        if let real = windowServerFrame(c.id) {
            c.frame = real
            // macOS put it back where it stood before fullscreen: a window it shows is not parked
            if c.parked && !Hider.isParked(real, in: m.screen.frame) {
                c.parked = false
                c.parkRetries = 0
            }
        }
        server.arrange(m, false, false)
        // A window out of view was not parked while macOS had it in fullscreen; mango's scene is
        // unchanged, so it is parked now.
        showOrPark(c)
    }

    func moved(_ c: Client, to actual: CGRect, resized: Bool) {
        guard !missionControl.isActive, !c.leftToMacOS else { return }   // Port extension: chutney_fullscreen_tag (leftToMacOS)
        if c.animation.running { return }
        if server.grabClient === c && (server.cursorMode == CurMove || server.cursorMode == CurResize) { return }
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
