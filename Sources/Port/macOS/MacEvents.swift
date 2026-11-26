import AppKit
import Mango

extension MacWindowSystem: AppWatcherDelegate {
    func windowDiscovered(_ w: DiscoveredWindow) {
        guard server.clientByWindowID(w.id) == nil else { return }
        let c = Client(window: w, monitor: server.selectedMonitor, tags: 0)
        c.bw = CGFloat(server.config.borderpx)   // handle_new_xdg_toplevel
        server.initClientProperties(c)   // handle_client_commit's initial commit
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
                wlrLog(.debug, "new window \(c.windowID) \(c.appid) '\(c.title)'")
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
        c.id = server.generateClientId()   // handle_client_map
        initClientGeom(c)
        c.isPendingOpenAnimation = false
        server.clientAddJumpLabelNode(c)
        c.mon = nil
        server.clientInsertTilingOrder(c)
        server.focusStack.insert(c, at: 0)
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
        wlrLog(.debug, "new window \(c.windowID) \(c.appid) '\(c.title)' floating=\(c.isfloating) dialog=\(c.mac.isFloatType)")
        scheduleInitialSettle()
    }

    func mapBack(_ c: Client, _ d: DepartedWindow, initial: Bool) {
        c.id = server.generateClientId()   // handle_client_map
        initClientGeom(c)
        server.clientAddJumpLabelNode(c)
        c.mon = nil
        server.clients.insert(c, at: DepartedWindow.insertionIndex(of: c.windowID, snapshot: d.orderSnapshot,
                                                                   into: server.clients.map(\.windowID)))
        server.focusStack.append(c)
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
        // handle_client_unmap's init_client_properties cleared them; the window is back as it left
        if d.isfullscreen { server.clientSetFullscreen(c, true, rearrange: false) }
        if d.ismaximizescreen { server.clientSetMaximizeScreen(c, true, rearrange: false) }
        wlrLog(.info, "\(c.appName): window \(c.windowID) is back; restored its tag and place")
        memory.returned(server, c)
        wlrLog(.debug, "new window \(c.windowID) \(c.appid) '\(c.title)' floating=\(c.isfloating) dialog=\(c.mac.isFloatType) (returned)")
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
        guard let c = server.clientByWindowID(id) else { return }
        server.handleClientUnmap(c)
        server.handleClientDestroy(c)
    }

    func windowFocused(id: CGWindowID) {
        guard let c = server.clientByWindowID(id) else {
            seatFocus = nil   // the keyboard is on a window mango does not manage
            return
        }
        guard let m = monitor(of: c) else { return }
        wlrLog(.debug, "\(c.appName): macOS focused window \(id) (mango's \(m.sel.map { String($0.windowID) } ?? "none"))")
        if m.isoverview {
            if !m.isJumpMode, server.focused !== c, m === server.selectedMonitor { server.toggleOverview(Arg(tc: c)) }
            return
        }
        if server.clientIsParked(c) { server.clientFocusGroupMember(c); return }
        if nativeFullscreen(c), !VISIBLEON(c, m) { FullscreenTag.focusedByMacOS(server, c); return }   // Port extension: chutney_fullscreen_tag
        if VISIBLEON(c, m) {
            if m.sel?.windowID == id && server.selectedMonitor === m { seatFocus = c; restack(); return }
            macOSFocused = c.windowID
            server.clientFocus(c, false)
            macOSFocused = nil
            return
        }
        if c.isminimized { return }
        server.handleClientActivationRequest(c)
    }

    func windowMinimized(id: CGWindowID, minimized: Bool) {
        if !minimized, away[id] != nil { comeBack(id, .minimized, focus: true); return }
        guard let c = server.clientByWindowID(id) else { return }
        minimizedByMacOS(c, minimized)
    }

    func minimizedByMacOS(_ c: Client, _ minimized: Bool) {
        if minimized && c.ignoreMinimize { goAway(c, .minimized); return }
        if minimized { clientSetMinimized(c, false) }
        server.handleClientRequestMinimize(c, minimized)
    }

    func windowTitleChanged(id: CGWindowID, title: String) {
        if let c = away[id]?.client { c.title = title; return }
        guard let c = server.clientByWindowID(id) else { return }
        c.title = title
        server.handleClientSetTitle(c)
    }

    func appTerminated(pid: pid_t) {
        TabStripView.forget(pid: pid)
        for (id, e) in away where e.client.pid == pid {
            away.removeValue(forKey: id)
            memory.departed.away.remove(id)
        }
        for c in server.clientsAll where c.pid == pid { windowDestroyed(id: c.windowID) }
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
        guard let c = server.clientByWindowID(id) else { return }
        c.element = element
        guard let m = c.mon else { return }
        if s.fullscreen == false, nativeFullscreen(c) { fullscreenChanged(c, false) }   // Port extension: chutney_fullscreen_tag
        if s.minimized == true || s.fullscreen == true || s.appHidden {
            wlrLog(.info, "\(c.appName): window \(c.windowID) went away while its element was dead (minimized \(s.minimized ?? false), fullscreen \(s.fullscreen ?? false), hidden \(s.appHidden))")
            if s.minimized == true { minimizedByMacOS(c, true) }
            if s.fullscreen == true, !nativeFullscreen(c) { fullscreenChanged(c, true) }   // Port extension: chutney_fullscreen_tag (else away)
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
        guard let c = server.clientByWindowID(id) else { return }
        moved(c, to: frame, resized: resized)
    }

    func moved(_ c: Client, to actual: CGRect, resized: Bool) {
        guard !missionControl.isActive, !leftToMacOS(c) else { return }   // Port extension: chutney_fullscreen_tag (leftToMacOS)
        if c.animation.running { return }
        if server.grabClient === c && (server.cursorMode == CurMove || server.cursorMode == CurResize) { return }
        if c.parked { keepHidden(c, seenAt: actual); return }
        if answersPortsWrite(c) {
            if actual != c.frame {
                c.frame = actual
                server.updateBorders()
            }
            return
        }
        userMoved(c, to: actual, resized: resized, dragging: mouseButtons & 1 != 0)
    }
}
