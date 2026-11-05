import Foundation

package extension MangoServer {
    @discardableResult
    public func dispatch(_ d: Dispatch, target: Client? = nil, rescan: Bool = true) -> String? {
        guard Dispatch.isKnown(d.name) else { return "unknown function" }
        defer {
            if rescan { system.rescan() }
            portHooks.saveLayout?(self, false)   // Port extension: not in mango (the layout kept across a restart)
        }
        let c = target ?? focused
        let m: Monitor = c?.mon ?? selectedMonitor
        let a0 = d.arg(0), a1 = d.arg(1)

        switch d.name {
        case "focusstack":
            focusStack(NextPrev(mangoArg: a0), from: target)
        case "focusdir":
            guard let dir = Direction(mangoName: a0) else { return "invalid direction" }
            focusDirection(dir)
        case "focus_window_or_workspace":
            guard let dir = Direction(mangoName: a0) else { return "invalid direction" }
            focusWindowOrWorkspace(dir)
        case "focuslast":
            let selID = selectedMonitor.sel
            var begin = false
            var tc: Client?
            for id in focusStack {
                guard let fc = clientByIdAll(id), !fc.isMinimized, !fc.isUnglobal,
                      !fc.groupParked else { continue }
                if selID == nil { tc = fc; break }
                if fc.id == selID && !begin { begin = true; continue }
                if begin { tc = fc; break }
            }
            guard let tc, tc.tags != 0, tc.tags & TagMask.special == 0 else { return nil }
            clientFocus(tc)
            clientSwitchView(getTagsFirstTag(tc.tags))
        case "focusid":
            guard let target else { return "client not found" }
            clientActive(target)
        case "focusmon":
            guard let target = parseMonitorArg(a0, relativeTo: selectedMonitor) else { return "monitor not found" }
            focusMonitor(target)
        case "tagmon":
            guard let c = target ?? clientFocusTop(selectedMonitor),
                  let tm = parseMonitorArg(a0, relativeTo: selectedMonitor) else { return nil }
            tagMonitor(c, to: tm, newtags: ValueParse.atoi(a1) != 0 ? c.tags : 0)

        case "exchange_client":
            guard let c, !c.isFloating, let dir = Direction(mangoName: a0) else { return nil }
            if (c.isFullscreen || c.isMaximizeScreen) && !m.layout.isScroller { return nil }
            if let tc = getFocusedStackClient(directionSelect(dir, from: target), target) { clientExchange(c, tc) }
        case "exchange_stack_client":
            guard let c, !c.isFloating, !c.isFullscreen, !c.isMaximizeScreen else { return nil }
            if let tc = getNextStackClient(c, reverse: NextPrev(mangoArg: a0) == .prev) { clientExchange(c, tc) }
        case "move_client":
            guard let c, let cm = c.mon, !c.isFloating, let dir = Direction(mangoName: a0) else { return nil }
            if (c.isFullscreen || c.isMaximizeScreen) && !cm.layout.isScroller { return nil }
            if let tc = directionSelect(dir, from: target) {
                if tc.mon !== cm {
                    clientMoveToMonitor(c, tc, dir)
                } else if cm.layout == .dwindle {
                    dwindleMoveNextTo(c, tc, dir)
                } else if let t2 = getFocusedStackClient(tc, c) {
                    clientExchange(c, t2)
                }
            } else if let tm = monitorFromDirection(dir, from: selectedMonitor) {
                _ = clientJumpToMonitor(c, tm, dir)
            }
            if config.warpcursor { pointerWarpToClient(c) }
        case "zoom":
            guard var sel: Client? = target ?? clientFocusTop(selectedMonitor), let s0 = sel, !s0.isFloating else { return nil }
            var found: Client?
            for fc in clients where fc.isVisible(on: selectedMonitor) && !fc.isFloating {
                if fc !== sel { found = fc; break }
                sel = nil
            }
            guard let first = found else { return nil }
            let z = sel ?? first
            clients.removeAll { $0 === z }
            clients.insert(z, at: 0)
            // not in mango: the port keeps the scroller's column order in its state; the
            // column of the window put first goes first, as mango's list order makes it.
            if let zm = z.mon, zm.layout.isScroller { zm.current.state.scrollerState.moveColumnToFront(z.id) }
            clientFocus(z)
            arrange(selectedMonitor)

        case "incnmaster":
            let sm: Monitor = selectedMonitor
            sm.current.settings.nmaster = max(0, sm.current.settings.nmaster + (Int(a0) ?? 0))
            arrange(sm)
        case "setmfact":
            guard let f = finiteDouble(a0) else { return "invalid argument" }
            let sm: Monitor = selectedMonitor
            let nf = f < 1.0 ? Double(sm.current.settings.mfact) + f : f - 1.0
            guard nf >= 0.1 && nf <= 0.9 else { return nil }
            sm.current.settings.mfact = CGFloat(nf)
            for t in tiledClients(sm) { t.masterMfactPer = CGFloat(nf) }
            arrange(sm)
        case "setlayout":
            guard let k = LayoutKind(name: a0) else { return "unknown layout" }
            setLayout(k, on: selectedMonitor)
        case "switch_layout":
            let sm: Monitor = selectedMonitor
            if !config.circleLayout.isEmpty {
                let names = config.circleLayout
                let target = names.firstIndex(of: sm.layout.name).map { names[($0 + 1) % names.count] } ?? names[0]
                if let k = LayoutKind(name: target) {
                    setLayout(k, on: sm)
                } else {
                    clearFullscreenAndMaximizedState(sm)
                    arrange(sm)
                    printstatus()
                }
            } else {
                let all = LayoutKind.allCases
                let i = all.firstIndex(of: sm.layout).map { ($0 + 1) % all.count } ?? 0
                setLayout(all[i], on: sm)
            }
        case "set_proportion":
            guard let c, selectedMonitor.layout.isScroller, overviewState?.monitor !== selectedMonitor,
                  let f = finiteDouble(a0) else { return nil }
            setProportion(c, CGFloat(f))
        case "switch_proportion_preset":
            guard let c, selectedMonitor.layout.isScroller, overviewState?.monitor !== selectedMonitor,
                  !c.isFloating, !config.scrollerProportionPreset.isEmpty else { return nil }
            let presets = config.scrollerProportionPreset.map { CGFloat($0) }
            let cur = scrollGetStackHeadClient(c).scrollerProportion ?? m.current.settings.scrollerDefaultProportion
            let next: CGFloat
            if let i = presets.firstIndex(where: { abs($0 - cur) < 0.001 }) {
                next = NextPrev(mangoArg: a0) == .next
                    ? presets[(i + 1) % presets.count]
                    : presets[(i - 1 + presets.count) % presets.count]
            } else {
                next = presets[0]
            }
            setProportion(c, next)
        case "scroller_stack":
            guard let c, c.mon != nil, !c.isFloating, selectedMonitor.layout.isScroller,
                  let dir = Direction(mangoName: a0) else { return nil }
            let ids = tiledClients(m).map(\.id)
            if m.current.state.scrollerState.scrollerApplyStack(c.id, direction: dir, vertical: m.layout == .verticalScroller, clientOrder: ids) {
                arrange(m)
            }
        case "centerwin":
            guard let c, !c.isFullscreen, !c.isMaximizeScreen else { return nil }
            if c.isFloating {
                let w = m.screen.workArea
                c.floatGeom = clientCenterGeometry(c, c.floatGeom, in: w).rounded()
                c.isCustomSize = true
            } else if selectedMonitor.layout.isScroller {
                m.current.state.scrollerState.centerWindow(c.id)
            }
            arrange(m)

        case "view":
            bindToView(TagMask.parseTagMask(a0), allMonitors: ValueParse.atoi(a1) != 0)
        case "comboview":
            let newtags = TagMask.parseTagMask(a0) & TagMask.mask(forTagNum: config.tagNum)
            guard newtags != 0 else { return nil }
            if tagCombo {
                selectedMonitor.tagset[selectedMonitor.seltags] |= newtags
                clientFocus(clientFocusTop(selectedMonitor))
                arrange(selectedMonitor, .none)
            } else {
                tagCombo = true
                clientViewOnMonitor(newtags, on: selectedMonitor)
            }
            printstatus()
        case "toggleview":
            guard overviewState?.monitor !== selectedMonitor else { return nil }
            let ui = TagMask.parseTagMask(a0)
            let target = ui == 0 ? TagMask.all : ui
            let n = selectedMonitor.tagset[selectedMonitor.seltags] ^ (target & TagMask.mask(forTagNum: config.tagNum))
            guard n != 0 else { printstatus(); return nil }
            selectedMonitor.tagset[selectedMonitor.seltags] = n
            clientFocus(clientFocusTop(selectedMonitor))
            for t in tiledClients(selectedMonitor) { setSizePer(selectedMonitor, t, resetProportion: true) }
            arrange(selectedMonitor)
        case "viewtoleft", "viewtoright":
            viewShiftTag(d.name == "viewtoright" ? 1 : -1, allMonitors: ValueParse.atoi(a0) != 0)
        case "viewtoleft_have_client", "viewtoright_have_client", "viewprev_have_client", "viewnext_have_client":
            let fwd = d.name == "viewtoright_have_client" || d.name == "viewnext_have_client"
            viewShiftTagHaveClient(fwd ? 1 : -1, allMonitors: ValueParse.atoi(a0) != 0)
        case "view_insert":
            viewInsert(next: NextPrev(mangoArg: a0) == .next)
        case "viewcrossmon":
            guard let target = parseMonitorArg(a1, relativeTo: selectedMonitor) else { return "monitor not found" }
            focusMonitor(target)
            clientViewOnMonitor(TagMask.parseTagMask(a0), on: target)
        case "tag":
            tagClient(c, TagMask.parseTagMask(a0), allMonitors: ValueParse.atoi(a1) != 0)
        case "tagsilent":
            guard let c else { return nil }
            let n = normalizeTagMask(TagMask.parseTagMask(a0))
            let mask = n & TagMask.special != 0 ? TagMask.special : n
            guard mask != 0 else { return nil }
            tagSilent(c, mask, on: m)
        case "tagtoleft", "tagtoright":
            let sm: Monitor = selectedMonitor
            let tagmask = TagMask.mask(forTagNum: config.tagNum)
            guard let c, (sm.tagset[sm.seltags] & tagmask).nonzeroBitCount == 1 else { return nil }
            var t: UInt32
            if d.name == "tagtoleft" {
                t = sm.tagset[sm.seltags] >> 1
                if t == 0 {
                    guard config.tagCarousel else { return nil }
                    t = (1 << UInt32(config.tagNum - 1)) & tagmask
                    sm.carouselAnimDir = -1
                }
            } else {
                t = sm.tagset[sm.seltags] << 1
                if t & tagmask == 0 {
                    guard config.tagCarousel else { return nil }
                    t = 1
                    sm.carouselAnimDir = 1
                }
            }
            tagClient(c, t & tagmask, allMonitors: ValueParse.atoi(a0) != 0)
            sm.carouselAnimDir = 0
        case "tagcrossmon":
            guard let c else { return nil }
            let mask = TagMask.parseTagMask(a0)
            if MonitorSpec(mango: a1).matchMonitorSpec(name: selectedMonitor.screen.name) {
                tagClient(c, mask)
                return nil
            }
            guard let tm = monitors.first(where: { MonitorSpec(mango: a1).matchMonitorSpec(name: $0.screen.name) }) else { return nil }
            tagMonitor(c, to: tm, newtags: mask)
        case "toggletag":
            guard let sel = target ?? clientFocusTop(selectedMonitor), let sm = sel.mon else { return nil }
            if overviewState?.monitor === sm { return nil }
            if sel.tags & TagMask.special != 0 { return nil }
            let ui = TagMask.parseTagMask(a0)
            let all = TagMask.mask(forTagNum: config.tagNum)
            var newtags: UInt32
            if ui == TagMask.special && sel.tags != all {
                newtags = all
            } else if ui == TagMask.special && sel.tags == all {
                var tag = sm.curtag
                if tag == 0 { tag = TagMask.getTagsFirstTagNum(sm.tagset[sm.seltags]) ?? 0 }
                if tag == 0 { tag = 1 }
                newtags = 1 << UInt32(tag - 1)
            } else {
                newtags = sel.tags ^ (ui & all)
            }
            if newtags != 0 {
                sel.tags = newtags
                clientFocus(clientFocusTop(selectedMonitor))
                arrange(selectedMonitor)
            }

        case "killclient":
            guard let c else { return nil }
            if a0.lowercased() == "force" { kill(c.pid, SIGKILL) } else { pendingKillClient(c) }
        case "smartkillclient":
            guard let c, let cm = c.mon else { return nil }
            if clientOnlyInOneTag(c) { pendingKillClient(c); return nil }
            let remaining = c.tags & ~(cm.tagset[cm.seltags] & TagMask.mask(forTagNum: config.tagNum))
            if remaining == 0 { pendingKillClient(c); return nil }
            c.tags = remaining
            clientFocus(clientFocusTop(selectedMonitor))
            arrange(cm)
        case "togglefloating":
            guard grab == nil, overviewState?.monitor !== selectedMonitor,
                  let c = target ?? clientFocusTop(selectedMonitor) else { return nil }
            let floating = c.isFullscreen || c.isMaximizeScreen ? true : !c.isFloating
            clientSetFloating(c, floating)
        case "toggle_all_floating":
            guard let ref = c else { return nil }
            let shouldFloating = !ref.isFloating
            for v in clients where v.isVisible(on: selectedMonitor) {
                if v.isFloating && !shouldFloating {
                    v.oldMasterInnerPer = 0
                    v.oldStackInnerPer = 0
                    setSizePer(selectedMonitor, v)
                }
                if v.isFloating != shouldFloating { clientSetFloating(v, shouldFloating) }
            }
        case "togglefullscreen":
            guard let c = target ?? clientFocusTop(selectedMonitor) else { return nil }
            c.isInScratchpad = false
            c.isNamedScratchpad = false
            clientApplyFullscreen(c, !c.isFullscreen, rearrange: true)
            updateBorders()
        case "togglefakefullscreen":
            guard let c = target ?? clientFocusTop(selectedMonitor) else { return nil }
            clientSetFakeFullscreen(c, !c.isFakeFullscreen)
        case "togglemaximizescreen":
            guard let c = target ?? clientFocusTop(selectedMonitor) else { return nil }
            c.isInScratchpad = false
            c.isNamedScratchpad = false
            clientSetMaximizeScreen(c, !c.isMaximizeScreen, rearrange: true)
            updateBorders()
        case "toggleglobal":
            guard let c else { return nil }
            if c.isInScratchpad {
                c.isInScratchpad = false
                c.isNamedScratchpad = false
            }
            c.isGlobal.toggle()
            updateBorders()
        case "toggleoverlay":
            guard let c, c.mon != nil, !c.isFullscreen else { return nil }
            c.isOverlay.toggle()
            arrange(m, .none)
        case "toggle_render_border":
            renderBorder.toggle()
            arrange(selectedMonitor)

        case "minimized":
            guard overviewState?.monitor !== selectedMonitor, let c, !c.isMinimized else { return nil }
            setMinimized(c)
        case "restore_minimized":
            guard overviewState?.monitor !== selectedMonitor else { return nil }
            let sm: Monitor = selectedMonitor
            let focused = sm.sel.flatMap { clientByIdAll($0) } ?? clientFocusTop(sm)
            var r: Client?
            if let f = focused, f.scratchpadShown {
                r = f
            } else {
                r = clients.first { ($0.mon === sm || config.scratchpadCrossMonitor) && $0.scratchpadShown }
            }
            if r == nil { r = clients.first { $0.isMinimized && !$0.isNamedScratchpad } }
            guard let r else { return nil }
            if !r.ignoreMinimize { system.unminimize(r) }   // not in mango: macOS's own minimize undone
            r.isInScratchpad = false
            r.isNamedScratchpad = false
            r.isMinimized = false
            r.isCustomSize = false
            if let f = focused, f !== r, f.tags != 0 { r.tags = f.tags } else { r.tags = sm.tagset[sm.seltags] }
            r.oldTags = r.tags
            r.mon = sm
            clientSetFloating(r, false)
            arrange(sm)
            clientFocus(r)
            pointerWarpToClient(r)
        case "toggle_scratchpad":
            toggleScratchpad()
        case "toggle_named_scratchpad":
            toggleNamedScratchpad(appId: a0, title: a1, command: d.args.count > 2 ? d.args[2...].joined(separator: ",") : "")
        case "toggle_special_tag":
            toggleSpecialTagMon(target?.mon ?? selectedMonitor)
        case "tag_special_tag", "tag_special_silent":
            guard let c else { return nil }
            let cm = c.mon ?? selectedMonitor!
            let silent = d.name == "tag_special_silent"
            if c.tags & TagMask.special != 0 {
                let back: UInt32 = cm.prevTag > 0 ? 1 << UInt32(cm.prevTag - 1) : (cm.curtag > 0 ? 1 << UInt32(cm.curtag - 1) : 1)
                if silent { tagSilent(c, back, on: cm) } else { tagClient(c, back) }
            } else if silent {
                tagSilent(c, TagMask.special, on: cm)
            } else {
                tagClient(c, TagMask.special)
                if !isSpecialActive(cm) { toggleSpecialTagMon(selectedMonitor) }
            }

        case "movewin":
            guard let c, !c.isFullscreen else { return nil }
            if !c.isFloating { clientSetFloating(c, true) }
            c.floatGeom.origin.x = relOrAbs(a0, c.floatGeom.minX)
            c.floatGeom.origin.y = relOrAbs(a1, c.floatGeom.minY)
            c.isCustomSize = true
            arrange(m, .none)
        case "resizewin":
            guard let c, !c.isFullscreen, !c.isMaximizeScreen else { return nil }
            let animationsBackup = config.animations
            if !c.isFloating { config.animations = false }
            defer { config.animations = animationsBackup }
            if !c.isFloating && !c.isMinimized && !c.isUnglobal {
                resizeTileClient(c, offsetX: CGFloat(finiteDouble(a0) ?? 0), offsetY: CGFloat(finiteDouble(a1) ?? 0))
            } else {
                c.floatGeom.size.width = max(1, relOrAbs(a0, c.floatGeom.width))
                c.floatGeom.size.height = max(1, relOrAbs(a1, c.floatGeom.height))
                c.isCustomSize = true
                arrange(m)
            }
        case "smartmovewin":
            guard let c, let dir = Direction(mangoName: a0) else { return nil }
            smartMoveWindow(c, dir)
        case "smartresizewin":
            guard let c, !c.isFullscreen, let dir = Direction(mangoName: a0) else { return nil }
            smartResizeWindow(c, dir)
        case "moveresize":
            let p = system.pointer
            pointerBeginMoveResize(clientAtPoint(p), a0 == "curresize" ? .resize : .move, at: p)
        case "incgaps":
            let sm: Monitor = selectedMonitor
            let n = CGFloat(Int(a0) ?? 0)
            setgaps(sm, Gaps(ih: sm.gaps.ih + n, iv: sm.gaps.iv + n, oh: sm.gaps.oh + n, ov: sm.gaps.ov + n))
        case "togglegaps":
            enableGaps.toggle()
            arrange(selectedMonitor)

        case "toggleoverview":
            guard grab == nil else { return nil }
            toggleOverview(onlyCurrent: a0 == "1", jump: false)
        case "enteroverview":
            guard grab == nil else { return nil }
            if overviewState == nil { toggleOverview(onlyCurrent: false, jump: false) }
        case "leaveoverview":
            guard grab == nil else { return nil }
            if overviewState != nil { leaveOverview(select: focused) }
        case "overcircle":
            guard grab == nil else { return nil }
            let dir = a0.lowercased()
            let next = dir == "next" || dir == "current_next"
            if var ov = overviewState, ov.monitor === selectedMonitor, ov.jump == nil, let sel = focused {
                if !ov.circle {
                    ov.circle = true
                    ov.circleFocus = sel.id
                    overviewState = ov
                }
                overCircle(forward: next)
            } else if overviewState != nil {
                leaveOverview(select: nil)
            } else {
                toggleOverview(onlyCurrent: dir.hasPrefix("current"), jump: false, circle: true)
            }
        case "switcher":
            switcher(a0)
        case "togglejump":
            guard grab == nil else { return nil }
            if overviewState == nil { toggleOverview(onlyCurrent: false, jump: true) } else { leaveOverview(select: nil) }

        case "dwindle_toggle_split_direction":
            guard let c else { return nil }
            m.current.state.dwindleRoot.dwindleSetSplitDirection(c.id, horizontal: nil)
        case "dwindle_toggle_current_split":
            guard let c else { return nil }
            m.current.state.dwindleRoot.dwindleToggleCurrentSplit(for: c.id)
            arrange(m)
        case "dwindle_split_horizontal":
            guard let c else { return nil }
            m.current.state.dwindleRoot.dwindleSetSplitDirection(c.id, horizontal: true)
        case "dwindle_split_vertical":
            guard let c else { return nil }
            m.current.state.dwindleRoot.dwindleSetSplitDirection(c.id, horizontal: false)

        case "spawn":
            system.spawn(combineArgsUntilEmpty(d.args))
        case "spawn_shell":
            system.spawnShell(combineArgsUntilEmpty(d.args))
        case "spawn_on_empty":
            let mask = TagMask.parseTagMask(a1)
            let empty = !clients.contains { $0.mon === selectedMonitor && $0.tags & mask != 0 }
            clientSwitchView(mask)
            if empty { system.spawnShell(a0) }
        case "reload_config":
            reloadConfig()
        case "load_config_file":
            configURL = a0 == "0" || a0.isEmpty ? ConfigParser.defaultConfigURL()
                : URL(fileURLWithPath: (a0 as NSString).expandingTildeInPath)
            reloadConfig()
        case "quit":
            system.quit()
        case "setkeymode":
            keyMode = a0
            printstatus()
        case "setoption":
            let value = d.args.dropFirst().joined(separator: ",")
            switch ConfigOptions.parseOption(key: a0, value: value, to: &config) {
            case .unknown: Log.info("setoption: unknown option \(a0)")
            case .invalid(let msg): Log.info("setoption: \(msg)")
            case .applied, .ignored: break
            }
            config.overrideConfig()
            resetOption()
        case "groupjoin":
            guard let c, !((c.isFullscreen || c.isMaximizeScreen) && (!m.layout.isScroller || c.isFloating)),
                  let dir = Direction(mangoName: a0),
                  let target = directionSelect(dir, from: c) else { return nil }
            clientGroupJoin(c, into: target)
        case "groupleave":
            guard let c else { return nil }
            if clientGroupLeave(c), let cm = c.mon { arrange(cm) }
        case "groupfocus":
            groupFocus(next: NextPrev(mangoArg: a0) == .next)
        case "togglegroupbar":
            config.alwaysShowGroupBar.toggle()
            arrangeAll(.move)
        default:
            // Port extension: not in mango. A dispatcher of the port's own (chutney_focus_app).
            if let ext = portHooks.extraDispatchers[d.name] {
                if let error = ext(self, d) { return error }
            } else {
                Log.debug("dispatcher \(d.name) is not supported on macOS")
            }
        }
        printstatus()
        return nil
    }

    /// Not in mango: rejects nan and inf arguments.
    func finiteDouble(_ s: String) -> Double? {
        guard let v = Double(s.trimmingCharacters(in: .whitespaces)), v.isFinite else { return nil }
        return v
    }

    func combineArgsUntilEmpty(_ args: [String]) -> String {
        var parts: [String] = []
        for a in args {
            if a.isEmpty || a == "0" { break }
            parts.append(a)
        }
        return parts.joined(separator: ",")
    }

    // not in mango: parse_num_type and move_window's switch on it, at the dispatch (the arguments are kept as text)
    func relOrAbs(_ s: String, _ current: CGFloat) -> CGFloat {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let v = finiteDouble(t) else { return current }
        if t.hasPrefix("+") || t.hasPrefix("-") { return current + CGFloat(v) }
        return CGFloat(v)
    }

    func clientOnlyInOneTag(_ c: Client) -> Bool {
        if c.tags & TagMask.special != 0 { return true }
        return (c.tags & TagMask.mask(forTagNum: config.tagNum)).nonzeroBitCount == 1
    }

    func tagClient(_ target: Client?, _ ui: UInt32, allMonitors: Bool = false) {
        let tagmask = TagMask.mask(forTagNum: config.tagNum)
        if let c = target, ui & (tagmask | TagMask.special) != 0 {
            c.tags = ui & TagMask.special != 0 ? TagMask.special : ui & tagmask
            for fc in clients where fc !== c && c.tags & fc.tags != 0 && (fc.isFullscreen || fc.isMaximizeScreen)
                && !c.isFloating {
                clearFullscreenFlag(fc)
            }
            if ui & TagMask.special != 0, let cm = c.mon { arrange(cm) }
        }
        clientSwitchView(ui, allMonitors: allMonitors)
        clientFocus(target)
        printstatus()
    }

    func clientSwitchView(_ ui: UInt32, allMonitors: Bool = false, wantAnimation: Bool = true) {
        clientViewOnMonitor(ui, on: selectedMonitor, changeFocus: true, wantAnimation: wantAnimation)
        if allMonitors {
            for mon in monitors where mon !== selectedMonitor {
                clientViewOnMonitor(ui, on: mon, changeFocus: false, wantAnimation: wantAnimation)
            }
        }
    }

    func tagSilent(_ c: Client, _ mask: UInt32, on m: Monitor) {
        c.tags = mask
        for fc in clients where fc !== c && c.tags & fc.tags != 0 && (fc.isFullscreen || fc.isMaximizeScreen) && !c.isFloating {
            clearFullscreenFlag(fc)
        }
        clientFocus(clientFocusTop(selectedMonitor))
        arrange(m)
    }

    /// Not in mango: the inline & TAGMASK masking as a helper.
    func normalizeTagMask(_ mask: UInt32) -> UInt32 {
        if mask == TagMask.all { return TagMask.mask(forTagNum: config.tagNum) }
        let valid = TagMask.mask(forTagNum: config.tagNum) | TagMask.special
        return mask & valid
    }

    func clientActive(_ c: Client) {
        if c.isMinimized {
            c.isInScratchpad = false
            c.isNamedScratchpad = false
            showHideClient(c)
            if let m = c.mon { arrange(m) }
            return
        }
        if let cm = c.mon { clientViewOnMonitor(getTagsFirstTag(c.tags), on: cm, changeFocus: true) }
        clientFocus(c)
    }

    package func getTagsFirstTag(_ tags: UInt32) -> UInt32 {
        let m: Monitor = selectedMonitor
        if tags == 0 { return isSpecialActive(m) ? TagMask.special : 1 << UInt32(m.curtag > 0 ? m.curtag - 1 : 0) }
        if tags & TagMask.special != 0 { return TagMask.special }
        let normal = tags & ~TagMask.special
        let i = normal.trailingZeroBitCount
        return i >= config.tagNum ? 1 << UInt32(config.tagNum - 1) : 1 << UInt32(i)
    }

    func bindToView(_ mask: UInt32, allMonitors: Bool) {
        let m: Monitor = selectedMonitor
        var target = mask
        let cur = m.tagset[m.seltags]
        let all = TagMask.mask(forTagNum: config.tagNum)
        if config.viewCurrentToBack && m.curtag != 0 && target & all == cur {
            if m.prevTag != 0 { target = 1 << UInt32(m.prevTag - 1) }
            else { target = m.tagset[m.seltags ^ 1] & TagMask.special != 0 ? TagMask.special : 0 }
        }
        if !config.viewCurrentToBack && target & all == cur { return }
        if target == TagMask.special && m.curtag == 0 {
            target = config.viewCurrentToBack && m.prevTag != 0 ? 1 << UInt32(m.prevTag - 1) : 0
        }
        clientSwitchView(target == 0 ? all : target, allMonitors: allMonitors, wantAnimation: target != 0)
    }

    package func clientViewOnMonitor(_ rawMask: UInt32, on m: Monitor, changeFocus: Bool? = nil, wantAnimation: Bool = true) {
        if let ov = overviewState, ov.monitor === m, rawMask != TagMask.mask(forTagNum: config.tagNum) { return }
        guard rawMask != 0 else { return }
        var wantAnimation = wantAnimation
        if rawMask == TagMask.all {
            guard m.tagset[0] != m.tagset[1] else { return }
            m.prevTag = TagMask.getTagsFirstTagNum(m.tagset[m.seltags]) ?? 0
            m.seltags ^= 1
            m.curtag = TagMask.getTagsFirstTagNum(m.tagset[m.seltags]) ?? 0
        } else {
            let mask = normalizeTagMask(rawMask)
            if m.tagset[m.seltags] & mask != 0 { wantAnimation = false }
            m.seltags ^= 1
            if mask != 0 {
                m.tagset[m.seltags] = mask
                let tmptag = m.curtag
                if mask & TagMask.special != 0 {
                    m.curtag = 0
                } else {
                    let i = mask.trailingZeroBitCount
                    m.curtag = i >= config.tagNum ? config.tagNum : i + 1
                }
                m.prevTag = tmptag == m.curtag ? m.prevTag : tmptag
            } else {
                let tmptag = m.prevTag
                m.prevTag = m.curtag
                m.curtag = tmptag
            }
        }
        let forward = m.carouselAnimDir != 0 ? m.carouselAnimDir > 0 : m.curtag > m.prevTag
        for c in clients where c.isVisible(on: m) && (c.isGlobal || c.isUnglobal || (c.tags & ~TagMask.special).nonzeroBitCount > 1) {
            setSizePer(m, c, resetProportion: true)
        }
        if changeFocus ?? (m === selectedMonitor) { clientFocus(clientFocusTop(m)) }
        arrange(m, wantAnimation ? .tag(forward: forward) : .move)
        printstatus()
    }

    func getTagStatus(_ tag: Int, on m: Monitor) -> Bool {
        let bit: UInt32 = 1 << UInt32(tag - 1)
        return clientsAll.contains { $0.mon === m && $0.tags & bit != 0 && !$0.isMinimized }
    }

    func tagGatherLastTagNum(_ m: Monitor) -> Int {
        var last = 0
        for c in clients where c.mon === m && c.tags & TagMask.special == 0 {
            let normal = c.tags & TagMask.mask(forTagNum: config.tagNum)
            if normal != 0 { last = max(last, 32 - normal.leadingZeroBitCount) }
        }
        return min(last + 1, config.tagNum)
    }

    @discardableResult
    func viewShiftTag(_ dir: Int, allMonitors: Bool = false) -> Bool {
        let m: Monitor = selectedMonitor
        if overviewState?.monitor === m || m.curtag == 0 { return false }
        let tagmask = TagMask.mask(forTagNum: config.tagNum)
        let cur = TagMask.getTagsFirstTagNum(m.tagset[m.seltags]) ?? 1
        let last = config.tagGather ? tagGatherLastTagNum(m) : config.tagNum
        var target = m.tagset[m.seltags]
        var wrapped = false
        if dir < 0 {
            target >>= 1
            if target == 0 {
                if !config.tagCarousel { return false }
                target = 1 << UInt32(last - 1)
                wrapped = true
            }
        } else {
            target <<= 1
            if config.tagCarousel && cur >= last {
                target = 1
                wrapped = true
            } else if target & tagmask == 0 {
                return false
            }
        }
        target &= tagmask
        if target == m.tagset[m.seltags] & tagmask { return false }
        if wrapped { m.carouselAnimDir = dir < 0 ? -1 : 1 }
        clientSwitchView(target, allMonitors: allMonitors)
        m.carouselAnimDir = 0
        return true
    }

    @discardableResult
    func viewShiftTagHaveClient(_ dir: Int, allMonitors: Bool = false) -> Bool {
        let m: Monitor = selectedMonitor
        if overviewState?.monitor === m || isSpecialActive(m) { return false }
        let current = TagMask.getTagsFirstTagNum(m.tagset[m.seltags]) ?? 1
        var found: Int?
        var wrapped = false
        if dir < 0 {
            found = stride(from: current - 1, through: 1, by: -1).first { getTagStatus($0, on: m) }
            if found == nil && config.tagCarousel {
                found = stride(from: config.tagNum, to: current, by: -1).first { getTagStatus($0, on: m) }
                wrapped = found != nil
            }
        } else {
            found = current + 1 <= config.tagNum ? (current + 1...config.tagNum).first { getTagStatus($0, on: m) } : nil
            if found == nil && config.tagCarousel && current > 1 {
                found = (1..<current).first { getTagStatus($0, on: m) }
                wrapped = found != nil
            }
        }
        guard let n = found else { return false }
        if wrapped { m.carouselAnimDir = dir < 0 ? -1 : 1 }
        clientSwitchView((1 << UInt32(n - 1)) & TagMask.mask(forTagNum: config.tagNum), allMonitors: allMonitors)
        m.carouselAnimDir = 0
        return true
    }

    func viewInsert(next: Bool) {
        let m: Monitor = selectedMonitor
        guard overviewState?.monitor !== m else { return }
        let tagmask = TagMask.mask(forTagNum: config.tagNum)
        let curmask = m.tagset[m.seltags] & tagmask
        guard curmask != 0, curmask & (curmask - 1) == 0, let cur = TagMask.getTagsFirstTagNum(curmask), cur > 0 else { return }
        var target: Int
        if next {
            if cur >= config.tagNum { return }
            target = cur + 1
        } else if cur == 1 {
            target = cur
        } else if !getTagStatus(cur - 1, on: m) {
            target = cur - 1
        } else {
            target = cur
        }
        if !getTagStatus(target, on: m) {
            clientSwitchView((1 << UInt32(target - 1)) & tagmask)
            return
        }
        if target >= config.tagNum || getTagStatus(config.tagNum, on: m) { return }
        viewInsertShiftTags(m, target)
        let bak = config.tagGather
        config.tagGather = false
        clientSwitchView((1 << UInt32(target - 1)) & tagmask)
        config.tagGather = bak
    }

    func tagRemapMask(_ tags: UInt32, _ map: [Int]) -> UInt32 {
        let tagmask = TagMask.mask(forTagNum: config.tagNum)
        var out = tags & ~tagmask
        for i in 1...config.tagNum where tags & (1 << UInt32(i - 1)) != 0 {
            out |= map[i] != 0 ? 1 << UInt32(map[i] - 1) : 1 << UInt32(i - 1)
        }
        return out
    }

    func viewInsertShiftTags(_ m: Monitor, _ target: Int) {
        guard target >= 1, target < config.tagNum, !getTagStatus(config.tagNum, on: m) else { return }
        var map = [Int](repeating: 0, count: config.tagNum + 1)
        for i in 1...config.tagNum { map[i] = i < target ? i : (i < config.tagNum ? i + 1 : i) }
        for c in clientsAll where c.mon === m { c.tags = tagRemapMask(c.tags, map) }
        m.tagset[m.seltags] = tagRemapMask(m.tagset[m.seltags], map)
        m.tagset[m.seltags ^ 1] = tagRemapMask(m.tagset[m.seltags ^ 1], map)
        m.ovbkCurrentTagset = tagRemapMask(m.ovbkCurrentTagset, map)
        m.ovbkPrevTagset = tagRemapMask(m.ovbkPrevTagset, map)
        if m.curtag <= config.tagNum && m.curtag > 0 && map[m.curtag] != 0 { m.curtag = map[m.curtag] }
        if m.prevTag <= config.tagNum && m.prevTag > 0 && map[m.prevTag] != 0 { m.prevTag = map[m.prevTag] }
        for i in stride(from: config.tagNum - 1, through: target, by: -1) {
            m.tagGatherMovePertag(dst: i + 1, src: i, config: config)
        }
    }

    func tagGatherApply(_ m: Monitor) {
        let tagmask = TagMask.mask(forTagNum: config.tagNum)
        var occupied: UInt32 = 0
        for c in clientsAll where c.mon === m && c.tags & TagMask.special == 0 { occupied |= c.tags & tagmask }
        occupied |= m.tagset[m.seltags] & tagmask
        var map = [Int](repeating: 0, count: config.tagNum + 1)
        var next = 1, changed = false
        for i in 1...config.tagNum where occupied & (1 << UInt32(i - 1)) != 0 {
            map[i] = next
            next += 1
            if map[i] != i { changed = true }
        }
        guard changed else { return }
        for c in clientsAll where c.mon === m && c.tags & TagMask.special == 0 { c.tags = tagRemapMask(c.tags, map) }
        m.tagset[m.seltags] = tagRemapMask(m.tagset[m.seltags], map)
        m.tagset[m.seltags ^ 1] = tagRemapMask(m.tagset[m.seltags ^ 1], map)
        m.ovbkCurrentTagset = tagRemapMask(m.ovbkCurrentTagset, map)
        m.ovbkPrevTagset = tagRemapMask(m.ovbkPrevTagset, map)
        if m.curtag <= config.tagNum && m.curtag > 0 && map[m.curtag] != 0 { m.curtag = map[m.curtag] }
        if m.prevTag <= config.tagNum && m.prevTag > 0 && map[m.prevTag] != 0 { m.prevTag = map[m.prevTag] }
        for i in 1...config.tagNum where map[i] != 0 && map[i] != i {
            m.tagGatherMovePertag(dst: map[i], src: i, config: config)
        }
        if next <= config.tagNum {
            for i in next...config.tagNum { m.tagGatherResetSlot(i, config: config) }
        }
    }

    func setLayout(_ k: LayoutKind, on m: Monitor) {
        m.current.layout = k
        clearFullscreenAndMaximizedState(m)
        arrange(m)
        printstatus()
    }

    func setProportion(_ c: Client, _ p: CGFloat) {
        guard let m = c.mon, overviewState?.monitor !== m, m.layout.isScroller else { return }
        if tiledClients(m).count == 1 && !config.scrollerIgnoreProportionSingle { return }
        scrollGetStackHeadClient(c).scrollerProportion = p
        arrange(m)
    }

    func scrollGetStackHeadClient(_ c: Client) -> Client {
        c.mon?.current.state.scrollerState.column(of: c.id).first.flatMap { clientByIdAll($0) } ?? c
    }

    func setgaps(_ m: Monitor, _ g: Gaps) {
        let clamped = Gaps(ih: max(g.ih, 0), iv: max(g.iv, 0), oh: max(g.oh, 0), ov: max(g.ov, 0))
        if isSpecialActive(m) { m.specialGaps = clamped } else { m.gaps = clamped }
        arrange(m)
    }

    func smartResizeWindow(_ c: Client, _ dir: Direction) {
        let sm: Monitor = selectedMonitor
        if !c.isFloating { clientSetFloating(c, true) }
        let w = sm.screen.workArea
        let g = c.floatGeom
        var nw = g.width, nh = g.height
        let others = clients.filter { $0 !== c && $0.isFloating && $0.isVisible(on: sm) }.map(\.floatGeom)
        switch dir {
        case .up:
            nh -= (w.height / 8).rounded(.towardZero)
            nh = max(nh, (w.height / 10).rounded(.towardZero))
        case .down:
            var tar = -CGFloat.infinity
            let bottom = g.maxY
            nh += (w.height / 8).rounded(.towardZero)
            for t in others where !(g.maxX < t.minX || g.minX > t.maxX) {
                let top = t.minY - CGFloat(config.gappiv)
                if bottom < top && nh + g.minY > top { tar = max(tar, top - g.minY) }
            }
            if tar != -.infinity { nh = tar }
            if g.minY + nh + CGFloat(config.gappov) > w.maxY { nh = w.maxY - g.minY - CGFloat(config.gappov) }
        case .left:
            nw -= (w.width / 16).rounded(.towardZero)
            nw = max(nw, (w.width / 10).rounded(.towardZero))
        case .right:
            var tar = CGFloat.infinity
            let right = g.maxX
            nw += (w.width / 16).rounded(.towardZero)
            for t in others where !(g.maxY < t.minY || g.minY > t.maxY) {
                let left = t.minX - CGFloat(config.gappih)
                if right < left && nw + g.minX > left { tar = min(tar, left - g.minX) }
            }
            if tar != .infinity { nw = tar }
            if g.minX + nw + CGFloat(config.gappoh) > w.maxX { nw = w.maxX - g.minX - CGFloat(config.gappoh) }
        }
        c.floatGeom = CGRect(x: g.minX, y: g.minY, width: nw, height: nh)
        c.isCustomSize = true
        if let cm = c.mon { arrange(cm, .none) }
    }

    func smartMoveWindow(_ c: Client, _ dir: Direction) {
        guard let m = c.mon, !c.isFullscreen else { return }
        if !c.isFloating { clientSetFloating(c, true) }
        let bw = borderWidth(c, on: m)
        let g = c.floatGeom.insetBy(dx: -bw, dy: -bw)
        let w = m.screen.workArea
        let ih = CGFloat(config.gappih), iv = CGFloat(config.gappiv)
        let others = clients.filter { $0 !== c && $0.isFloating && $0.isVisible(on: selectedMonitor) }.map { o in
            o.floatGeom.insetBy(dx: -borderWidth(o, on: m), dy: -borderWidth(o, on: m))
        }
        var nx = g.minX, ny = g.minY
        switch dir {
        case .up:
            ny -= (w.height / 4).rounded(.towardZero)
            var tar = -CGFloat.infinity
            for t in others where !(g.maxX < t.minX || g.minX > t.maxX) {
                let bottom = t.maxY + iv
                if g.minY > bottom && ny < bottom { tar = max(tar, bottom) }
            }
            if tar != -.infinity { ny = tar }
            ny = max(ny, w.minY + m.gaps.ov)
        case .down:
            ny += (w.height / 4).rounded(.towardZero)
            var tar = CGFloat.infinity
            for t in others where !(g.maxX < t.minX || g.minX > t.maxX) {
                let top = t.minY - iv
                if g.maxY < top && ny + g.height > top { tar = min(tar, top - g.height) }
            }
            if tar != .infinity { ny = tar }
            ny = min(ny, w.maxY - g.height - m.gaps.ov)
        case .left:
            nx -= (w.width / 6).rounded(.towardZero)
            var tar = -CGFloat.infinity
            for t in others where !(g.maxY < t.minY || g.minY > t.maxY) {
                let right = t.maxX + ih
                if g.minX > right && nx < right { tar = max(tar, right) }
            }
            if tar != -.infinity { nx = tar }
            nx = max(nx, w.minX + m.gaps.oh)
        case .right:
            nx += (w.width / 6).rounded(.towardZero)
            var tar = CGFloat.infinity
            for t in others where !(g.maxY < t.minY || g.minY > t.maxY) {
                let left = t.minX - ih
                if g.maxX < left && nx + g.width > left { tar = min(tar, left - g.width) }
            }
            if tar != .infinity { nx = tar }
            nx = min(nx, w.maxX - g.width - m.gaps.oh)
        }
        c.floatGeom = CGRect(x: nx, y: ny, width: g.width, height: g.height).insetBy(dx: bw, dy: bw)
        c.isCustomSize = true
        arrange(m, .move)
    }

    func setSizePer(_ m: Monitor, _ c: Client, resetProportion: Bool = false) {
        let keepOwn = !resetProportion && (c.masterSizeWeight > 0 || c.stackSizeWeight > 0)
        let centered = m.layout == .centerTile
        let tiled = tiledClients(m)
        c.masterMfactPer = m.current.settings.mfact
        for fc in tiled where fc !== c && fc.masterMfactPer > 0 {
            if centered && fc.isLeftStack != c.isLeftStack { continue }
            c.masterMfactPer = fc.masterMfactPer
            break
        }
        let pt = m.current.settings
        if keepOwn {
            if !c.isCustomScrollerProportion && (c.scrollerProportion ?? 0) <= 0 {
                c.scrollerProportion = pt.scrollerDefaultProportion
            }
            if !c.isCustomScrollerProportionSingle && (c.scrollerProportionSingle ?? 0) <= 0 {
                c.scrollerProportionSingle = pt.scrollerDefaultProportionSingle
            }
            return
        }
        var found = false
        for fc in tiled where fc !== c {
            if centered && fc.isLeftStack != c.isLeftStack { continue }
            c.masterSizeWeight = fc.masterSizeWeight
            c.stackSizeWeight = fc.stackSizeWeight
            found = true
            break
        }
        if !found || c.masterSizeWeight <= 0 || c.stackSizeWeight <= 0 {
            c.masterSizeWeight = 1
            c.stackSizeWeight = 1
        }
        c.masterInnerPer = c.masterSizeWeight
        c.stackInnerPer = c.stackSizeWeight
        if !c.isCustomScrollerProportion { c.scrollerProportion = pt.scrollerDefaultProportion }
        if !c.isCustomScrollerProportionSingle { c.scrollerProportionSingle = pt.scrollerDefaultProportionSingle }
    }

    // not in mango: `fake`, the windows wl_list_for_each with VISIBLEON and ISFAKETILED finds
    func resetSizePerMon(_ m: Monitor, _ fake: [Client], totalLeftStackWeight totalLeft: CGFloat,
                         totalRightStackWeight totalRight: CGFloat, totalStackWeight totalStack: CGFloat,
                         totalMasterWeight totalMaster: CGFloat, masterNum: Int, stackNum: Int) {
        let nmasters = m.current.settings.nmaster
        let centered = m.layout == .centerTile
        for (i, c) in fake.enumerated() {
            if totalMaster > 0 && i < nmasters {
                c.isMaster = true
                c.masterInnerPer = c.masterSizeWeight / totalMaster
                let stackSide = centered ? totalLeft + totalRight : totalStack
                c.stackInnerPer = stackSide > 0 ? c.stackSizeWeight / (stackSide + c.stackSizeWeight) : 1
            } else {
                c.isMaster = false
                c.masterInnerPer = totalMaster > 0 ? c.masterSizeWeight / (totalMaster + c.masterSizeWeight)
                    : (masterNum > 0 ? 1 / CGFloat(masterNum) : 1)
                if centered {
                    let side = c.isLeftStack ? totalLeft : totalRight
                    c.stackInnerPer = side > 0 ? c.stackSizeWeight / side : 1
                } else {
                    c.stackInnerPer = totalStack > 0 ? c.stackSizeWeight / totalStack
                        : (stackNum > 0 ? 1 / CGFloat(stackNum) : 1)
                }
            }
        }
    }

    func persistTileSizeWeights(_ m: Monitor) {
        for c in clients where c.isVisible(on: m) && !c.isFloating && !c.isMinimized && !c.isUnglobal {
            if c.isMaster { c.masterSizeWeight = c.masterInnerPer } else { c.stackSizeWeight = c.stackInnerPer }
        }
    }

    func resizeTileClient(_ gc: Client, isdrag: Bool = false, offsetX: CGFloat, offsetY: CGFloat, cursor: CGPoint = .zero,
                          time: UInt32 = 0) {
        guard let m = gc.mon, !gc.isFullscreen, !gc.isMaximizeScreen, overviewState?.monitor !== m else { return }
        let layout = m.pertag[TagMask.getTagsFirstTagNum(gc.tags) ?? m.getMonCurtag].layout
        switch layout {
        case .tile, .deck, .centerTile, .rightTile:
            resizeTileMaster(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor, time: time,
                             type: layout, vertical: false)
        case .verticalTile, .verticalDeck:
            resizeTileMaster(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor, time: time,
                             type: layout, vertical: true)
        case .scroller:
            resizeTileScroller(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor, time: time, vertical: false)
        case .verticalScroller:
            resizeTileScroller(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor, time: time, vertical: true)
        case .dwindle:
            resizeTileDwindle(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor, time: time)
        case .grid, .verticalGrid, .fair, .verticalFair:
            resizeTileGridFair(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor, time: time)
        default:
            break
        }
    }

    // not in mango: resize_tile_master_horizontal and _vertical in one; `vertical` says which
    func resizeTileMaster(_ gc: Client, isdrag: Bool, offsetX: CGFloat, offsetY: CGFloat, cursor: CGPoint,
                          time: UInt32, type: LayoutKind, vertical: Bool) {
        guard let m = gc.mon else { return }
        let tiled = tiledClients(m)
        guard let gi = tiled.firstIndex(where: { $0 === gc }) else { return }
        let next = gi + 1 < tiled.count ? tiled[gi + 1] : nil
        let nextnext = gi + 2 < tiled.count ? tiled[gi + 2] : nil
        let prev = gi > 0 ? tiled[gi - 1] : nil
        let prevprev = gi > 1 ? tiled[gi - 2] : nil
        let geom = gc.geom ?? gc.frame
        if !startDragWindow && isdrag {
            dragBeginCursor = cursor
            startDragWindow = true
            gc.oldMasterMfactPer = gc.masterMfactPer
            gc.oldMasterInnerPer = gc.masterInnerPer
            gc.oldStackInnerPer = gc.stackInnerPer
            gc.cursorInUpperHalf = cursor.y < geom.minY + (geom.height / 2).rounded(.towardZero)
            gc.cursorInLeftHalf = cursor.x < geom.minX + (geom.width / 2).rounded(.towardZero)
            gc.dragBeginGeom = geom
            return
        }
        var ox = offsetX, oy = offsetY
        if isdrag {
            ox = cursor.x - dragBeginCursor.x
            oy = cursor.y - dragBeginCursor.y
        } else {
            gc.oldMasterMfactPer = gc.masterMfactPer
            gc.oldMasterInnerPer = gc.masterInnerPer
            gc.oldStackInnerPer = gc.stackInnerPer
            gc.dragBeginGeom = geom
            gc.cursorInUpperHalf = true
            gc.cursorInLeftHalf = false
        }
        let bw = Float(max(1, gc.dragBeginGeom.width)), bh = Float(max(1, gc.dragBeginGeom.height))
        let oldMfact = Float(gc.oldMasterMfactPer), oldMInner = Float(gc.oldMasterInnerPer), oldSInner = Float(gc.oldStackInnerPer)
        var across: Float, along: Float
        if !vertical {
            across = Float(ox) * (gc.isMaster ? oldMfact : 1 - oldMfact) / bw
            along = Float(oy) * (gc.isMaster ? oldMInner : oldSInner) / bh
        } else {
            along = Float(ox) * (gc.isMaster ? oldMInner : oldSInner) / bw
            across = Float(oy) * (gc.isMaster ? oldMfact : 1 - oldMfact) / bh
        }
        let back: Bool, forth: Bool
        let first = vertical ? gc.cursorInLeftHalf : gc.cursorInUpperHalf
        if !isdrag {
            back = (vertical ? ox : oy) < 0
            forth = (vertical ? ox : oy) > 0
        } else {
            back = vertical ? cursor.x < dragBeginCursor.x : cursor.y < dragBeginCursor.y
            forth = vertical ? cursor.x > dragBeginCursor.x : cursor.y > dragBeginCursor.y
        }
        if gc.isMaster && prev == nil {
            along = back ? -abs(along) : abs(along)
        } else if gc.isMaster, let next, !next.isMaster {
            along = back ? abs(along) : -abs(along)
        } else if !gc.isMaster, let prev, prev.isMaster {
            along = back ? -abs(along) : abs(along)
        } else if !gc.isMaster && next == nil {
            along = back ? abs(along) : -abs(along)
        } else if !vertical && type == .centerTile && !gc.isMaster && nextnext == nil {
            along = back ? abs(along) : -abs(along)
        } else if !vertical && type == .centerTile && !gc.isMaster, let prevprev, prevprev.isMaster {
            along = back ? -abs(along) : abs(along)
        } else if (first && back) || (!first && forth) {
            along = abs(along) * 2
        } else {
            along = -abs(along) * 2
        }
        if !vertical {
            if !gc.isMaster && gc.isLeftStack && type == .centerTile { across = -across }
            if gc.isMaster && type == .centerTile && gc.cursorInLeftHalf { across = -across }
            if gc.isMaster && type == .centerTile { across *= 2 }
            if type == .rightTile { across = -across }
        }
        let newMfact = max(0.1, min(0.9, oldMfact + across))
        let newMInner = max(0.1, min(0.9, oldMInner + along))
        let newSInner = max(0.1, min(0.9, oldSInner + along))
        if isdrag {
            if gc.isMaster {
                let cur = 1 - Float(gc.masterInnerPer), new = 1 - newMInner
                if cur > 0.001 {
                    for tc in tiled where tc.isMaster && tc !== gc { tc.masterInnerPer *= CGFloat(new / cur) }
                }
            } else {
                let cur = 1 - Float(gc.stackInnerPer), new = 1 - newSInner
                if cur > 0.001 {
                    for tc in tiled where !tc.isMaster && tc !== gc
                        && (vertical || type != .centerTile || tc.isLeftStack == gc.isLeftStack) {
                        tc.stackInnerPer *= CGFloat(new / cur)
                    }
                }
            }
        } else {
            for tc in tiled where tc !== gc {
                if !tc.isMaster && newSInner != 1 && oldSInner != 1
                    && (vertical || type != .centerTile || tc.isLeftStack == gc.isLeftStack) {
                    tc.stackInnerPer = CGFloat((1 - newSInner) / (1 - oldSInner)) * tc.stackInnerPer
                }
                if tc.isMaster && newMInner != 1 && oldMInner != 1 {
                    tc.masterInnerPer = CGFloat((1 - newMInner) / (1 - oldMInner)) * tc.masterInnerPer
                }
            }
        }
        gc.masterInnerPer = CGFloat(newMInner)
        gc.stackInnerPer = CGFloat(newSInner)
        for tc in tiled { tc.masterMfactPer = CGFloat(newMfact) }
        persistTileSizeWeights(m)
        if !isdrag {
            arrange(m, .move)
            return
        }
        if lastApplyDragTime == 0 || time &- lastApplyDragTime >= dragRefreshIntervalMs(m) {
            arrange(m, .none)
            lastApplyDragTime = time
        }
    }

    func resizeTileScroller(_ gc: Client, isdrag: Bool, offsetX: CGFloat, offsetY: CGFloat, cursor: CGPoint,
                            time: UInt32, vertical: Bool) {
        guard let m = gc.mon else { return }
        let pt = m.pertag[TagMask.getTagsFirstTagNum(gc.tags) ?? m.getMonCurtag]
        let col = pt.state.scrollerState.column(of: gc.id).compactMap { clientByIdAll($0) }
        guard let ci = col.firstIndex(where: { $0 === gc }), let head = col.first else { return }
        func proportions() -> [Float] {
            let raw = col.map { Float($0.scrollerStackWeight) }
            let positive = raw.filter { $0 > 0 }
            var w = raw
            if positive.isEmpty { w = raw.map { _ in 1 } } else {
                let avg = positive.reduce(0, +) / Float(positive.count)
                for i in w.indices where w[i] <= 0 { w[i] = avg }
            }
            let total = w.reduce(0, +)
            return w.map { $0 / total }
        }
        var props = proportions()
        let headProportion = head.scrollerProportion ?? pt.settings.scrollerDefaultProportion
        let geom = gc.geom ?? gc.frame
        if !startDragWindow && isdrag {
            dragBeginCursor = cursor
            startDragWindow = true
            head.oldScrollerProportion = headProportion
            gc.scrollerOldStackProportion = CGFloat(props[ci])
            gc.cursorInLeftHalf = cursor.x < geom.minX + (geom.width / 2).rounded(.towardZero)
            gc.cursorInUpperHalf = cursor.y < geom.minY + (geom.height / 2).rounded(.towardZero)
            gc.dragBeginGeom = geom
            return
        }
        var ox = offsetX, oy = offsetY
        if isdrag {
            ox = cursor.x - dragBeginCursor.x
            oy = cursor.y - dragBeginCursor.y
        } else {
            gc.dragBeginGeom = geom
            head.oldScrollerProportion = headProportion
            gc.scrollerOldStackProportion = CGFloat(props[ci])
            gc.cursorInUpperHalf = false
            gc.cursorInLeftHalf = false
        }
        let bw = Float(max(1, gc.dragBeginGeom.width)), bh = Float(max(1, gc.dragBeginGeom.height))
        let oldHead = Float(head.oldScrollerProportion), oldStack = Float(gc.scrollerOldStackProportion)
        var dx: Float, dy: Float
        if vertical {
            dy = Float(oy) * oldHead / bh
            dx = Float(ox) * oldStack / bw
        } else {
            dx = Float(ox) * oldHead / bw
            dy = Float(oy) * oldStack / bh
        }
        let movingUp = isdrag ? cursor.y < dragBeginCursor.y : oy < 0
        let movingDown = isdrag ? cursor.y > dragBeginCursor.y : oy > 0
        let movingLeft = isdrag ? cursor.x < dragBeginCursor.x : ox < 0
        let movingRight = isdrag ? cursor.x > dragBeginCursor.x : ox > 0
        dy = (gc.cursorInUpperHalf && movingUp) || (!gc.cursorInUpperHalf && movingDown) ? abs(dy) : -abs(dy)
        dx = (gc.cursorInLeftHalf && movingLeft) || (!gc.cursorInLeftHalf && movingRight) ? abs(dx) : -abs(dx)
        let hasNext = ci + 1 < col.count, hasPrev = ci > 0
        if vertical {
            if !hasNext && hasPrev && !isdrag { dx = -dx }
            if !hasNext && hasPrev && isdrag { dx = movingRight ? -abs(dx) : abs(dx) }
            if !hasPrev && hasNext && isdrag { dx = movingLeft ? -abs(dx) : abs(dx) }
            if isdrag { dy = movingUp ? -abs(dy) : abs(dy) }
        } else {
            if !hasNext && hasPrev && !isdrag { dy = -dy }
            if !hasNext && hasPrev && isdrag { dy = movingDown ? -abs(dy) : abs(dy) }
            if !hasPrev && hasNext && isdrag { dy = movingUp ? -abs(dy) : abs(dy) }
            if isdrag { dx = movingLeft ? -abs(dx) : abs(dx) }
        }
        let newScroller = max(0.1, min(1, oldHead + (vertical ? dy : dx)))
        let newStack = max(0.1, min(0.9, oldStack + (vertical ? dx : dy)))
        if isdrag {
            let cur = 1 - props[ci], new = 1 - newStack
            if cur > 0.001 { for k in props.indices where k != ci { props[k] *= new / cur } }
        } else if oldStack != 1 {
            for k in props.indices where k != ci { props[k] = (1 - newStack) / (1 - oldStack) * props[k] }
        }
        props[ci] = newStack
        let heads = pt.state.scrollerState.columns(for: tiledClients(m).map(\.id)).count
        if heads > 1 || config.scrollerIgnoreProportionSingle {
            head.scrollerProportion = CGFloat(newScroller)
        }
        for (k, c) in col.enumerated() { c.scrollerStackWeight = CGFloat(props[k]) }
        if !isdrag {
            arrange(m, .move)
            return
        }
        if lastApplyDragTime == 0 || time &- lastApplyDragTime >= dragRefreshIntervalMs(m) {
            arrange(m, .none)
            lastApplyDragTime = time
        }
    }

    func resizeTileDwindle(_ gc: Client, isdrag: Bool, offsetX: CGFloat, offsetY: CGFloat, cursor: CGPoint, time: UInt32) {
        guard let m = gc.mon else { return }
        let tree = m.current.state.dwindleRoot
        if !isdrag {
            tree.dwindleResizeClientStep(gc.id, dx: offsetX, dy: offsetY, config: config)
            arrange(m)
            return
        }
        if lastApplyDragTime == 0 || time &- lastApplyDragTime >= dragRefreshIntervalMs(m) {
            if tree.dwindleResizeClient(gc.id, startDragWindow: &startDragWindow, dragBeginCursor: &dragBeginCursor,
                                        cursor: cursor, smartResize: config.dwindleSmartResize) {
                arrange(m, .none)
            }
            lastApplyDragTime = time
        }
    }

    func resizeTileGridFair(_ gc: Client, isdrag: Bool, offsetX: CGFloat, offsetY: CGFloat, cursor: CGPoint, time: UInt32) {
        guard let m = gc.mon, !gc.isFullscreen, !gc.isMaximizeScreen, overviewState?.monitor !== m else { return }
        let tiled = tiledClients(m)
        guard tiled.count > 1 else { return }
        func recordOldShares() {
            for c in clientsAll {
                c.oldGridColPer = c.gridColPer > 0 ? c.gridColPer : 1
                c.oldGridRowPer = c.gridRowPer > 0 ? c.gridRowPer : 1
            }
        }
        if !startDragWindow && isdrag {
            dragBeginCursor = cursor
            startDragWindow = true
            recordOldShares()
            gc.oldGridColPer = gc.gridColPer
            gc.oldGridRowPer = gc.gridRowPer
            let geom = directionGeom(gc)
            gc.cursorInLeftHalf = cursor.x < geom.minX + (geom.width / 2).rounded(.towardZero)
            gc.cursorInUpperHalf = cursor.y < geom.minY + (geom.height / 2).rounded(.towardZero)
            gc.dragBeginGeom = geom
            return
        }
        var ox = offsetX, oy = offsetY
        if isdrag {
            ox = cursor.x - dragBeginCursor.x
            oy = cursor.y - dragBeginCursor.y
        } else {
            gc.dragBeginGeom = directionGeom(gc)
            recordOldShares()
            gc.cursorInUpperHalf = false
            gc.cursorInLeftHalf = false
        }
        let deltaX = Float(ox) * Float(gc.oldGridColPer) / Float(max(1, gc.dragBeginGeom.width))
        let deltaY = Float(oy) * Float(gc.oldGridRowPer) / Float(max(1, gc.dragBeginGeom.height))
        let maxCol = tiled.map(\.gridColIdx).max() ?? 0, minCol = tiled.map(\.gridColIdx).min() ?? 0
        let maxRow = tiled.map(\.gridRowIdx).max() ?? 0, minRow = tiled.map(\.gridRowIdx).min() ?? 0
        var adjC = gc.gridColIdx + 1, adjR = gc.gridRowIdx + 1
        var signX: Float = 1, signY: Float = 1
        if gc.gridColIdx == maxCol { adjC = gc.gridColIdx - 1; signX = -1 }
        if gc.gridRowIdx == maxRow { adjR = gc.gridRowIdx - 1; signY = -1 }
        if gc.gridColIdx == minCol { adjC = gc.gridColIdx + 1; signX = 1 }
        if gc.gridRowIdx == minRow { adjR = gc.gridRowIdx + 1; signY = 1 }
        let dx = deltaX * signX, dy = deltaY * signY
        let myOldCol = Float(gc.oldGridColPer), myOldRow = Float(gc.oldGridRowPer)
        var adjOldCol: Float = -1, adjOldRow: Float = -1
        for c in tiled {
            if c.gridColIdx == adjC && adjOldCol < 0 { adjOldCol = Float(c.oldGridColPer) }
            if c.gridRowIdx == adjR && adjOldRow < 0 { adjOldRow = Float(c.oldGridRowPer) }
        }
        let n = tiled.count
        func lockedShare(_ mine: Float, _ adj: Float, _ d: Float, first: Bool) -> (Float, Float) {
            var p = first ? (mine + d) / (mine + adj) : (adj - d) / (mine + adj)
            p = min(max(p, 0.01), 0.99)
            let v = min(max(p / (1 - p), 0.1), 10)
            return first ? (v, 1) : (1, v)
        }
        if adjOldCol > 0 {
            var d = dx
            if myOldCol + d < 0.1 { d = 0.1 - myOldCol }
            if adjOldCol - d < 0.1 { d = adjOldCol - 0.1 }
            var (newMy, newAdj) = (myOldCol + d, adjOldCol - d)
            if m.layout == .verticalFair {
                var rows = 0
                while rows * rows < n { rows += 1 }
                let baseCols = n / rows
                if (gc.gridColIdx == baseCols - 1 && adjC == baseCols) || (gc.gridColIdx == baseCols && adjC == baseCols - 1) {
                    (newMy, newAdj) = lockedShare(myOldCol, adjOldCol, dx, first: gc.gridColIdx == baseCols - 1)
                }
            }
            for c in tiled {
                if c.gridColIdx == gc.gridColIdx { c.gridColPer = CGFloat(newMy) }
                if c.gridColIdx == adjC { c.gridColPer = CGFloat(newAdj) }
            }
        }
        if adjOldRow > 0 {
            var d = dy
            if myOldRow + d < 0.1 { d = 0.1 - myOldRow }
            if adjOldRow - d < 0.1 { d = adjOldRow - 0.1 }
            var (newMy, newAdj) = (myOldRow + d, adjOldRow - d)
            if m.layout == .fair {
                var cols = 0
                while cols * cols < n { cols += 1 }
                let baseRows = n / cols
                if (gc.gridRowIdx == baseRows - 1 && adjR == baseRows) || (gc.gridRowIdx == baseRows && adjR == baseRows - 1) {
                    (newMy, newAdj) = lockedShare(myOldRow, adjOldRow, dy, first: gc.gridRowIdx == baseRows - 1)
                }
            }
            for c in tiled {
                if c.gridRowIdx == gc.gridRowIdx { c.gridRowPer = CGFloat(newMy) }
                if c.gridRowIdx == adjR { c.gridRowPer = CGFloat(newAdj) }
            }
        }
        if !isdrag {
            arrange(m, .none)
            return
        }
        if lastApplyDragTime == 0 || time &- lastApplyDragTime >= dragRefreshIntervalMs(m) {
            arrange(m, .none)
            lastApplyDragTime = time
        }
    }

    func clientExchange(_ c1: Client, _ c2: Client) {
        guard c1 !== c2, let m1 = c1.mon, let m2 = c2.mon, config.exchangeCrossMonitor || m1 === m2 else { return }
        func swapList() {
            guard let i = clients.firstIndex(where: { $0 === c1 }), let j = clients.firstIndex(where: { $0 === c2 }) else { return }
            clients.swapAt(i, j)
        }
        func swapLayoutProperties() {
            (c1.masterInnerPer, c2.masterInnerPer) = (c2.masterInnerPer, c1.masterInnerPer)
            (c1.stackInnerPer, c2.stackInnerPer) = (c2.stackInnerPer, c1.stackInnerPer)
            (c1.masterSizeWeight, c2.masterSizeWeight) = (c2.masterSizeWeight, c1.masterSizeWeight)
            (c1.stackSizeWeight, c2.stackSizeWeight) = (c2.stackSizeWeight, c1.stackSizeWeight)
            (c1.masterMfactPer, c2.masterMfactPer) = (c2.masterMfactPer, c1.masterMfactPer)
            (c1.gridColPer, c2.gridColPer) = (c2.gridColPer, c1.gridColPer)
            (c1.gridRowPer, c2.gridRowPer) = (c2.gridRowPer, c1.gridRowPer)
            (c1.gridColIdx, c2.gridColIdx) = (c2.gridColIdx, c1.gridColIdx)
            (c1.gridRowIdx, c2.gridRowIdx) = (c2.gridRowIdx, c1.gridRowIdx)
        }
        func swapMonitorsAndTags() {
            (c1.mon, c2.mon) = (m2, m1)
            (c1.tags, c2.tags) = (c2.tags, c1.tags)
        }
        if m1.layout.isScroller || m2.layout.isScroller {
            let s1 = m1.current.state.scrollerState, s2 = m2.current.state.scrollerState
            let col1 = s1.column(of: c1.id), col2 = s2.column(of: c2.id)
            if col1.isEmpty && col2.isEmpty { return }
            if m1 !== m2 && (col1.count > 1 || col2.count > 1) { return }
            swapLayoutProperties()
            if m1 === m2 && !col1.isEmpty && !col2.isEmpty {
                let sameStack = col1.contains(c2.id)
                s1.exchangeTwoScrollerClients(c1.id, c2.id)
                if sameStack { swapList() }
            } else {
                swapList()
            }
            if m1 !== m2 { swapMonitorsAndTags() }
        } else if m1.layout == .dwindle && m2.layout == .dwindle {
            swapLayoutProperties()
            if m1 === m2 {
                m1.current.state.dwindleRoot.dwindleSwapClients(c1.id, c2.id)
            } else {
                m1.current.state.dwindleRoot.replace(c1.id, with: c2.id, config: config)
                m2.current.state.dwindleRoot.replace(c2.id, with: c1.id, config: config)
                swapMonitorsAndTags()
            }
            swapList()
        } else {
            swapLayoutProperties()
            swapList()
            if m1 !== m2 { swapMonitorsAndTags() }
        }
        arrange(m1)
        if m2 !== m1 { arrange(m2) }
        focusStack.removeAll { $0 == c2.id }
        if let i = focusStack.firstIndex(of: c1.id) { focusStack.insert(c2.id, at: i + 1) }
        if config.warpcursor { pointerWarpToClient(c1) }
    }

    func focusStack(_ dir: NextPrev, from target: Client? = nil) {
        guard let sel = target ?? clientFocusTop(selectedMonitor),
              let tc = getNextStackClient(sel, reverse: dir == .prev) else { return }
        clientFocus(tc)
        if config.warpcursor { pointerWarpToClient(tc) }
    }

    func getNextStackClient(_ c: Client, reverse: Bool) -> Client? {
        guard let m = c.mon, let i = clients.firstIndex(where: { $0 === c }) else { return nil }
        let n = clients.count
        for k in 1..<max(n, 1) {
            let x = clients[reverse ? (i - k + n) % n : (i + k) % n]
            if x.isUnglobal { continue }
            if x !== c, x.mon != nil, x.isVisible(on: m) { return x }
        }
        return nil
    }

    func focusDirection(_ dir: Direction) {
        let m = selectedMonitor!
        if m.layout == .monocle, let sel = focused, !sel.isFloating, dir.isHorizontal {
            focusStack(dir == .right ? .next : .prev)
            return
        }
        var c = directionSelect(dir)
        if overviewState?.monitor !== m { c = getFocusedStackClient(c, nil) }
        if let c {
            clientFocus(c)
            if config.warpcursor { pointerWarpToClient(c) }
        } else if !isSpecialActive(m) {
            if config.focusCrossTag {
                viewShiftTagHaveClient(dir == .right || dir == .down ? 1 : -1)
            } else if config.focusCrossMonitor, let target = monitorFromDirection(dir, from: m) {
                focusMonitor(target)
            }
        }
    }

    func focusWindowOrWorkspace(_ dir: Direction) {
        let m = selectedMonitor!
        if overviewState?.monitor === m { return }
        let c = getFocusedStackClient(directionSelect(dir), nil)
        if let c, c.mon === m {
            clientFocus(c)
            if config.warpcursor { pointerWarpToClient(c) }
            return
        }
        guard !isSpecialActive(m) else { return }
        let forward = dir == .right || dir == .down
        if !viewShiftTagHaveClient(forward ? 1 : -1) { viewShiftTag(forward ? 1 : -1) }
    }

    func directionSelect(_ dir: Direction, from: Client? = nil) -> Client? {
        guard let tc = from ?? focused else { return nil }
        if (tc.isFullscreen || tc.isMaximizeScreen) && (!selectedMonitor.layout.isScroller || tc.isFloating) { return nil }
        return findClientByDirection(tc, dir, findFloating: true)
    }

    /// Not in mango: stands for c->geom with its border.
    func directionGeom(_ c: Client) -> CGRect {
        if let ov = overviewState, ov.monitor === c.mon, let card = ov.cards[c.id] { return card }
        let g = c.isFloating ? c.floatGeom : (c.geom ?? c.frame)
        guard let m = c.mon else { return g }
        let bw = borderWidth(c, on: m)
        return g.insetBy(dx: -bw, dy: -bw)
    }

    func findClientByDirection(_ tc: Client, _ dir: Direction, findFloating: Bool) -> Client? {
        let t = directionGeom(tc)
        let tl = Int64(t.minX.rounded()), tr = Int64(t.maxX.rounded()), tt = Int64(t.minY.rounded()), tb = Int64(t.maxY.rounded())
        let tcx = tl + (tr - tl) / 2, tcy = tt + (tb - tt) / 2
        var best: Client?, bestSame: Client?
        var distance = Int64.max, sameDistance = Int64.max, bestCenter = Int64.max, bestSameCenter = Int64.max
        for step in 0..<2 {
            if step == 1 && best != nil { break }
            for c in clients {
                guard let cm = c.mon, c !== tc else { continue }
                if !findFloating && c.isFloating { continue }
                if !c.isVisible(on: cm) || c.isUnglobal { continue }
                if !config.focusCrossMonitor && cm !== tc.mon { continue }
                if c.tags & cm.tagset[cm.seltags] == 0 && !c.isGlobal { continue }
                let g = directionGeom(c)
                let l = Int64(g.minX.rounded()), r = Int64(g.maxX.rounded()), tp = Int64(g.minY.rounded()), b = Int64(g.maxY.rounded())
                let cx = l + (r - l) / 2, cy = tp + (b - tp) / 2
                var main: Int64 = 0, orth: Int64 = 0
                switch dir {
                case .left:
                    guard cx < tcx || (cx == tcx && l < tl) else { continue }
                    main = tl - r; orth = b < tt ? tt - b : (tp > tb ? tp - tb : 0)
                case .right:
                    guard cx > tcx || (cx == tcx && l > tl) else { continue }
                    main = l - tr; orth = b < tt ? tt - b : (tp > tb ? tp - tb : 0)
                case .up:
                    guard cy < tcy || (cy == tcy && tp < tt) else { continue }
                    main = tt - b; orth = r < tl ? tl - r : (l > tr ? l - tr : 0)
                case .down:
                    guard cy > tcy || (cy == tcy && tp > tt) else { continue }
                    main = tp - tb; orth = r < tl ? tl - r : (l > tr ? l - tr : 0)
                }
                let overlap = dir.isHorizontal ? (b >= tt && tp <= tb) : (r >= tl && l <= tr)
                if config.focusdirOnlyZoneOverlap && !overlap { continue }
                if step == 0 {
                    guard let m = tc.mon, cm === m else { continue }
                    if overviewState?.monitor !== m && !clientIsInSameStack(tc, c, nil) { continue }
                }
                var penalty: Int64 = 0
                if main < 0 { penalty = 10_000_000_000; main = -main }
                let d = penalty + main * main + orth * orth
                let center = abs(dir.isHorizontal ? cy - tcy : cx - tcx)
                if d < distance || (d == distance && center < bestCenter) {
                    distance = d; bestCenter = center; best = c
                }
                if cm === tc.mon && (d < sameDistance || (d == sameDistance && center < bestSameCenter)) {
                    sameDistance = d; bestSameCenter = center; bestSame = c
                }
            }
        }
        return bestSame ?? best
    }


    func clientIsInSameStack(_ sc: Client, _ tc: Client, _ fc: Client?) -> Bool {
        guard let m = sc.mon else { return false }
        let layout = m.layout
        if !layout.isScroller && tc.mon !== selectedMonitor && (tc.isFullscreen || tc.isMaximizeScreen) { return true }
        switch layout {
        case .monocle:
            return !tc.isTabHidden
        case .scroller, .verticalScroller:
            func head(_ c: Client) -> ClientID? {
                guard let cm = c.mon else { return nil }
                return cm.current.state.scrollerState.column(of: c.id).first ?? c.id
            }
            if let fc, head(fc) == head(sc) { return false }
            return head(sc) == head(tc)
        case .tile, .verticalTile, .deck, .verticalDeck, .rightTile:
            if tabMembers(m).contains(where: { $0 === tc }) { return !tc.isTabHidden }
            if tc.isMaster != sc.isMaster { return false }
            if let fc, fc.isMaster == sc.isMaster { return false }
            return true
        case .centerTile:
            if tc.isMaster != sc.isMaster { return false }
            if let fc, fc.isMaster == sc.isMaster { return false }
            return directionGeom(sc).minX == directionGeom(tc).minX
        default:
            return false
        }
    }

    func getFocusedStackClient(_ sc: Client?, _ customFocusClient: Client?) -> Client? {
        guard let sc, !sc.isFloating, let fc = customFocusClient ?? focused, !fc.isFloating, let m = sc.mon else { return sc }
        let block: Set<ClientID>? = m.layout == .dwindle ? m.current.state.dwindleRoot.dwindleFocusBlockRoot(sc.id, fc.id) : nil
        for id in focusStack {
            guard let tc = clientByIdAll(id), !tc.isUnglobal, tc.isVisible(on: m), tc !== fc else { continue }
            if m.layout == .dwindle {
                if let block, block.contains(tc.id) { return tc }
                continue
            }
            if clientIsInSameStack(sc, tc, fc) { return tc }
        }
        return sc
    }

    func monitorFromDirection(_ dir: Direction, from m: Monitor) -> Monitor? {
        let ref = m.screen.frame, p = ref.origin
        func inDirection(_ b: CGRect, _ dirs: [Direction]) -> Bool {
            dirs.contains { d in
                switch d {
                case .left: return b.maxX <= ref.minX
                case .right: return b.minX >= ref.maxX
                case .up: return b.maxY <= ref.minY
                case .down: return b.minY >= ref.maxY
                }
            }
        }
        func distance(_ b: CGRect) -> CGFloat {
            let x = min(max(p.x, b.minX), b.maxX - 1), y = min(max(p.y, b.minY), b.maxY - 1)
            return (x - p.x) * (x - p.x) + (y - p.y) * (y - p.y)
        }
        let others = monitors.filter { $0 !== m }
        if let next = others.filter({ inDirection($0.screen.frame, [dir]) }).min(by: { distance($0.screen.frame) < distance($1.screen.frame) }) {
            return next
        }
        let rest: [Direction] = [.left, .right, .up, .down].filter { $0 != dir }
        var farthest: Monitor?, maxDistance: CGFloat = 0
        for o in others where inDirection(o.screen.frame, rest) {
            let d = distance(o.screen.frame)
            if d > maxDistance { maxDistance = d; farthest = o }
        }
        return farthest
    }

    func parseMonitorArg(_ arg: String, relativeTo m: Monitor) -> Monitor? {
        if let dir = Direction(mangoName: arg) { return monitorFromDirection(dir, from: m) }
        guard let i = monitors.firstIndex(where: { $0 === m }) else { return nil }
        switch arg.lowercased() {
        case "next": return monitors[(i + 1) % monitors.count]
        case "prev": return monitors[(i - 1 + monitors.count) % monitors.count]
        default:
            let spec = MonitorSpec(mango: arg)
            return monitors.first { spec.matchMonitorSpec(name: $0.screen.name) }
        }
    }

    func focusMonitor(_ target: Monitor) {
        guard target !== selectedMonitor else { return }
        selectedMonitor = target
        if config.warpcursor { pointerWarpToMonitor(target) }
        if let c = clientFocusTop(target) {
            clientFocus(c)
        } else {
            target.sel = nil
            clientFocus(nil)
        }
    }

    func monitorMoveDirection(_ from: Monitor, _ to: Monitor) -> Direction? {
        guard from !== to else { return nil }
        let dx = to.screen.frame.midX - from.screen.frame.midX
        let dy = to.screen.frame.midY - from.screen.frame.midY
        if dx == 0 && dy == 0 { return nil }
        if abs(dx) >= abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .down : .up
    }

    func clientReassignMonitor(_ c: Client, _ m: Monitor) {
        guard let old = c.mon, old !== m else { return }
        if old.sel == c.id { old.sel = nil }
        if old.prevsel == c.id { old.prevsel = nil }
        old.pertag[TagMask.getTagsFirstTagNum(c.tags) ?? old.getMonCurtag].state.scrollerState.scrollerNodeRemove(c.id)
        c.mon = m
        c.parked = false   // not in mango: the system places it on the new display
        if !c.isVisible(on: m) { clientResetMonTags(c, m, 0) }
        m.sel = c.id
        selectedMonitor = m
    }

    @discardableResult
    func clientJumpToMonitor(_ c: Client, _ m: Monitor, _ dir: Direction) -> Bool {
        guard let old = c.mon, old !== m, config.exchangeCrossMonitor,
              monitorMoveDirection(old, m) == dir else { return false }
        clientReassignMonitor(c, m)
        arrange(old)
        arrange(m)
        return true
    }

    func clientMoveToMonitor(_ c: Client, _ target: Client, _ dir: Direction) {
        guard let src = c.mon, let dst = target.mon, c !== target, src !== dst, config.exchangeCrossMonitor,
              monitorMoveDirection(src, dst) == dir else { return }
        let layout = dst.layout
        if layout == .dwindle {
            dwindleMoveNextTo(c, target, dir)
            return
        }
        let insertBefore = dir == .right || dir == .up
        clientReassignMonitor(c, dst)
        func inOrder(beside t: Client, before: Bool) {
            clients.removeAll { $0 === c }
            guard let i = clients.firstIndex(where: { $0 === t }) else { clients.append(c); return }
            clients.insert(c, at: before ? i : i + 1)
        }
        if layout.isScroller {
            let alongAxis = layout == .verticalScroller ? !dir.isHorizontal : dir.isHorizontal
            let st = dst.current.state.scrollerState
            if !alongAxis {
                st.scrollerDropTile(c.id, onto: target.id, intoStack: true, before: insertBefore)
            } else {
// not in mango: the port's scroller columns
                st.scrollerDropTile(c.id, onto: target.id, intoStack: false, before: insertBefore)
            }
            inOrder(beside: target, before: insertBefore)
        } else {
            inOrder(beside: target, before: insertBefore)
        }
        arrange(src)
        arrange(dst)
    }

    func dwindleMoveNextTo(_ c: Client, _ target: Client, _ dir: Direction) {
        guard let cm = c.mon, c !== target, let tm = target.mon else { return }
        let crossed = cm !== tm
        let origin = c.geom ?? c.frame
        if !clientJumpToMonitor(c, tm, dir) && c.mon !== tm { return }
        guard let m = c.mon else { return }
        m.current.state.dwindleRoot.dwindleMoveNextTo(c.id, nextTo: target.id, direction: dir, crossed: crossed,
                                                      origin: origin, config: config)
        arrange(m)
    }

    func tagMonitor(_ c: Client, to m: Monitor, newtags: UInt32) {
        guard let oldmon = c.mon else { return }
        if oldmon === m {
            clientViewOnMonitor(newtags, on: selectedMonitor, changeFocus: true)
            return
        }
        if oldmon.sel == c.id { oldmon.sel = nil }
        clientSetMonitor(c, m, newtags, focus: true)
        clientUpdateOldmonnameRecord(c, m)
        c.parked = false   // not in mango: the system places it on the new display
        let from = oldmon.screen.workArea, to = m.screen.workArea
        c.floatGeom.size = CGSize(width: (c.floatGeom.width * to.width / max(1, from.width)).rounded(.towardZero),
                                  height: (c.floatGeom.height * to.height / max(1, from.height)).rounded(.towardZero))
        selectedMonitor = m
        c.floatGeom = clientCenterGeometry(c, m, c.floatGeom)
        clientViewOnMonitor(getTagsFirstTag(c.tags), on: selectedMonitor, changeFocus: true)
        clientFocus(c)
        arrange(selectedMonitor)
        if config.warpcursor { pointerWarpToMonitor(m) }
    }

    func toggleScratchpad() {
        if overviewState?.monitor === selectedMonitor { return }
        var hit = false
        for c in clients {
            if !config.scratchpadCrossMonitor && c.mon !== selectedMonitor { continue }
            if config.singleScratchpad && c.isNamedScratchpad && c.scratchpadShown {
                setMinimized(c)
                continue
            }
            if c.isNamedScratchpad || hit { continue }
            hit = switchScratchpadClientState(c)
        }
    }

    func setMinimized(_ c: Client) {
        guard let m = c.mon, grab?.client !== c else { return }
        c.isGlobal = false
        c.oldTags = m.tagset[m.seltags]
        c.tags = 0
        c.isMinimized = true
        c.isInScratchpad = true
        clientFocus(clientFocusTop(selectedMonitor))
        arrange(m)
        clients.removeAll { $0 === c }
        clients.append(c)
    }

    func showHideClient(_ c: Client) {
        guard let m = c.mon else { return }
        if !c.ignoreMinimize { system.unminimize(c) }   // not in mango: macOS's own minimize undone
        setSizePer(m, c)
        let target = getTagsFirstTag(c.oldTags)
        if !c.isInScratchpad {
            tagClient(c, target)
        } else {
            c.tags = m.tagset[m.seltags]
            c.isMinimized = false
            arrange(m)
        }
        c.isMinimized = false
        clientFocus(c)
    }

    func showScratchpad(_ c: Client) {
        guard let m = c.mon else { return }
        if c.isFullscreen || c.isMaximizeScreen {
            c.isFullscreen = false
            c.isMaximizeScreen = false
        }
        if !c.isFloating { clientSetFloating(c, true) }
        if !c.isCustomSize {
            let w = m.screen.workArea
            c.floatGeom.size = CGSize(width: (w.width * CGFloat(config.scratchpadWidthRatio)).rounded(.towardZero),
                                      height: (w.height * CGFloat(config.scratchpadHeightRatio)).rounded(.towardZero))
            c.floatGeom = clientCenterGeometry(c, m, c.floatGeom)
            c.isCustomSize = true
        }
        c.oldTags = m.tagset[m.seltags]
        clients.removeAll { $0 === c }
        clients.insert(c, at: 0)
        showHideClient(c)
    }

    func switchScratchpadClientState(_ c: Client) -> Bool {
        guard let old = c.mon, c.isInScratchpad else { return false }
        let shown = c.scratchpadShown
        if config.scratchpadCrossMonitor && old !== selectedMonitor {
            let from = old.screen.workArea, to = selectedMonitor.screen.workArea
            let w = (c.floatGeom.width * to.width / from.width).rounded(.down)
            let h = (c.floatGeom.height * to.height / from.height).rounded(.down)
            c.floatGeom = clientCenterGeometry(c, CGRect(origin: c.floatGeom.origin, size: CGSize(width: w, height: h)),
                                               in: to).rounded()
            c.mon = selectedMonitor
            clientUpdateOldmonnameRecord(c, selectedMonitor)
            if shown {
                c.tags = getTagsFirstTag(selectedMonitor.tagset[selectedMonitor.seltags])
                arrange(selectedMonitor)
                clientFocus(c)
                return true
            }
        }
        guard let m = c.mon else { return false }
        if shown && m.tagset[m.seltags] & c.tags != 0 {
            setMinimized(c)
            return true
        }
        c.tags = m.tagset[m.seltags]
        c.oldTags = c.tags
        c.scratchpadTagin = true
        if shown {
            arrange(m)
            clientFocus(c)
        } else {
            showScratchpad(c)
        }
        return true
    }

    func toggleNamedScratchpad(appId: String, title: String, command: String) {
        if overviewState?.monitor === selectedMonitor { return }
        let aid: String? = appId == "none" || appId == "0" || appId.isEmpty ? nil : appId
        let tid: String? = title == "none" || title == "0" || title.isEmpty ? nil : title
// mango get_client_by_id_or_title. Not in mango: the app's name matches too (macOS app ids are bundle ids).
        let match = clients.first { c in
            (config.scratchpadCrossMonitor || c.mon === selectedMonitor) &&
            (aid.map { c.appid.range(of: $0, options: .regularExpression) != nil || c.appName.range(of: $0, options: .regularExpression) != nil } ?? true)
                && (tid.map { c.title.range(of: $0, options: .regularExpression) != nil } ?? true)
                && (aid != nil || tid != nil)
        }
        guard let c = match else {
            if !command.isEmpty && command != "0" {
                system.spawnShell(command)
            }
            return
        }
        c.isNamedScratchpad = true
        applyNamedScratchpad(c)
    }

    func applyNamedScratchpad(_ target: Client) {
        for c in clients {
            if !config.scratchpadCrossMonitor && c.mon !== selectedMonitor { continue }
            if config.singleScratchpad && c.scratchpadShown && c !== target { setMinimized(c) }
        }
        if !target.isInScratchpad { setMinimized(target) }
        _ = switchScratchpadClientState(target)
    }
}

private func < (a: (CGFloat, CGFloat), b: (CGFloat, CGFloat)) -> Bool {
    a.0 != b.0 ? a.0 < b.0 : a.1 < b.1
}
