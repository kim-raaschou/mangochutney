import Foundation

package extension MangoServer {
    @discardableResult
    public func dispatch(_ d: Dispatch, target: Client? = nil, rescan: Bool = true) -> String? {
        guard Dispatch.isKnown(d.name) else { return "unknown function" }
        defer { if rescan { system.rescan() } }   // not in mango: the port's side
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
                guard let fc = clientByIdAll(id), !fc.isminimized, !fc.isunglobal,
                      !fc.groupParked else { continue }
                if selID == nil { tc = fc; break }
                if fc.id == selID && !begin { begin = true; continue }
                if begin { tc = fc; break }
            }
            guard let tc, tc.tags != 0, tc.tags & TAG0_MASK == 0 else { return nil }
            clientFocus(tc, true)
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
            guard let c, !c.isfloating, let dir = Direction(mangoName: a0) else { return nil }
            if (c.isfullscreen || c.ismaximizescreen) && !m.layout.isScroller { return nil }
            if let tc = getFocusedStackClient(directionSelect(dir, from: target), target) { clientExchange(c, tc) }
        case "exchange_stack_client":
            guard let c, !c.isfloating, !c.isfullscreen, !c.ismaximizescreen else { return nil }
            if let tc = getNextStackClient(c, reverse: NextPrev(mangoArg: a0) == .prev) { clientExchange(c, tc) }
        case "move_client":
            guard let c, let cm = c.mon, !c.isfloating, let dir = Direction(mangoName: a0) else { return nil }
            if (c.isfullscreen || c.ismaximizescreen) && !cm.layout.isScroller { return nil }
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
            guard var sel: Client? = target ?? clientFocusTop(selectedMonitor), let s0 = sel, !s0.isfloating else { return nil }
            var found: Client?
            for fc in clients where VISIBLEON(fc, selectedMonitor) && !fc.isfloating {
                if fc !== sel { found = fc; break }
                sel = nil
            }
            guard let first = found else { return nil }
            let z = sel ?? first
            clients.removeAll { $0 === z }
            clients.insert(z, at: 0)
            // not in mango: the port keeps the scroller's column order in its state; the
            // column of the window put first goes first, as mango's list order makes it.
            if let zm = z.mon, zm.layout.isScroller { zm.pertag.scrollerState[getMonCurtag(zm)].moveColumnToFront(z.id) }
            clientFocus(z, true)
            arrange(selectedMonitor, false, false)

        case "incnmaster":
            let sm: Monitor = selectedMonitor
            let tag = getMonCurtag(sm)
            sm.pertag.nmasters[tag] = max(sm.pertag.nmasters[tag] + Int32(truncatingIfNeeded: ValueParse.atoi(a0)), 0)
            arrange(sm, false, false)
        case "setmfact":
            let sm: Monitor = selectedMonitor
            let argf = Float(ValueParse.atof(a0))
            let f: Float = argf < 1.0 ? argf + sm.pertag.mfacts[getMonCurtag(sm)] : argf - 1.0
            if f < 0.1 || f > 0.9 { return nil }
            sm.pertag.mfacts[getMonCurtag(sm)] = f
            for t in clients where VISIBLEON(t, sm) && ISTILED(t) { t.masterMfactPer = CGFloat(f) }
            arrange(sm, false, false)
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
                    arrange(sm, false, false)
                    printstatus(.arrangge)
                }
            } else {
                let all = LayoutKind.allCases
                let i = all.firstIndex(of: sm.layout).map { ($0 + 1) % all.count } ?? 0
                setLayout(all[i], on: sm)
            }
        case "set_proportion":
            guard let c, selectedMonitor.layout.isScroller, !selectedMonitor.isoverview,
                  let f = finiteDouble(a0) else { return nil }
            setProportion(c, CGFloat(f))
        case "switch_proportion_preset":
            guard let c, selectedMonitor.layout.isScroller, !selectedMonitor.isoverview,
                  !c.isfloating, !config.scrollerProportionPreset.isEmpty else { return nil }
            let presets = config.scrollerProportionPreset.map { CGFloat($0) }
            let cur = scrollGetStackHeadClient(c).scrollerProportion ?? CGFloat(m.pertag.scrollerDefaultProportion[getMonCurtag(m)])
            let next: CGFloat
            if let i = presets.firstIndex(where: { abs($0 - cur) < 0.001 }) {
                next = presets[(i + 1) % presets.count]
            } else {
                next = presets[0]
            }
            setProportion(c, next)
        case "scroller_stack":
            guard let c, c.mon != nil, !c.isfloating, selectedMonitor.layout.isScroller,
                  let dir = Direction(mangoName: a0) else { return nil }
            let ids = tiledClients(m).map(\.id)
            if m.pertag.scrollerState[getMonCurtag(m)].scrollerApplyStack(c.id, direction: dir, vertical: m.layout == .verticalScroller, clientOrder: ids) {
                arrange(m, false, false)
            }
        case "centerwin":
            guard let c, !c.isfullscreen, !c.ismaximizescreen else { return nil }
            if c.isfloating {
                let w = m.screen.workArea
                c.floatGeom = clientCenterGeometry(c, c.floatGeom, in: w).rounded()
                c.iscustomsize = true
            } else if selectedMonitor.layout.isScroller {
                m.pertag.scrollerState[getMonCurtag(m)].centerWindow(c.id)
            }
            arrange(m, false, false)

        case "view":
            bindToView(TagMask.parseTagMask(a0), allMonitors: ValueParse.atoi(a1) != 0)
        case "comboview":
            let newtags = TagMask.parseTagMask(a0) & TAGMASK
            guard newtags != 0 else { return nil }
            if tagCombo {
                selectedMonitor.tagset[selectedMonitor.seltags] |= newtags
                clientFocus(clientFocusTop(selectedMonitor), true)
                arrange(selectedMonitor, false, false)
            } else {
                tagCombo = true
                clientViewOnMonitor(newtags, on: selectedMonitor)
            }
            printstatus(.arrangge)
        case "toggleview":
            guard !selectedMonitor.isoverview else { return nil }
            let ui = TagMask.parseTagMask(a0)
            let target = ui == 0 ? TagMask.all : ui
            let n = selectedMonitor.tagset[selectedMonitor.seltags] ^ (target & TAGMASK)
            guard n != 0 else { printstatus(.arrangge); return nil }
            selectedMonitor.tagset[selectedMonitor.seltags] = n
            clientFocus(clientFocusTop(selectedMonitor), true)
            for t in tiledClients(selectedMonitor) { setSizePer(selectedMonitor, t, resetProportion: true) }
            arrange(selectedMonitor, false, false)
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
            let ui = TagMask.parseTagMask(a0)
            tagSilent(c, (ui & TAG0_MASK) != 0 ? TAG0_MASK : (ui & TAGMASK), on: m)
        case "tagtoleft", "tagtoright":
            let sm: Monitor = selectedMonitor
            let tagmask = TAGMASK
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
            if sm.isoverview { return nil }
            if sel.tags & TAG0_MASK != 0 { return nil }
            let ui = TagMask.parseTagMask(a0)
            let all = TAGMASK
            var newtags: UInt32
            if ui == TAG0_MASK && sel.tags != all {
                newtags = all
            } else if ui == TAG0_MASK && sel.tags == all {
                var tag = sm.pertag.curtag
                if tag == 0 { tag = getTagsFirstTagNum(sm.tagset[sm.seltags]) }
                if tag == 0 { tag = 1 }
                newtags = 1 << UInt32(tag - 1)
            } else {
                newtags = sel.tags ^ (ui & all)
            }
            if newtags != 0 {
                sel.tags = newtags
                clientFocus(clientFocusTop(selectedMonitor), true)
                arrange(selectedMonitor, false, false)
            }

        case "killclient":
            guard let c else { return nil }
            if a0.lowercased() == "force" { kill(c.pid, SIGKILL) } else { pendingKillClient(c) }
        case "smartkillclient":
            guard let c, let cm = c.mon else { return nil }
            if clientOnlyInOneTag(c) { pendingKillClient(c); return nil }
            let remaining = c.tags & ~(cm.tagset[cm.seltags] & TAGMASK)
            if remaining == 0 { pendingKillClient(c); return nil }
            c.tags = remaining
            clientFocus(clientFocusTop(selectedMonitor), true)
            arrange(cm, false, false)
        case "togglefloating":
            guard grab == nil, !selectedMonitor.isoverview,
                  let c = target ?? clientFocusTop(selectedMonitor) else { return nil }
            let floating = c.isfullscreen || c.ismaximizescreen ? true : !c.isfloating
            clientSetFloating(c, floating)
        case "toggle_all_floating":
            guard let ref = c else { return nil }
            let shouldFloating = !ref.isfloating
            for v in clients where VISIBLEON(v, selectedMonitor) {
                if v.isfloating && !shouldFloating {
                    v.oldMasterInnerPer = 0
                    v.oldStackInnerPer = 0
                    setSizePer(selectedMonitor, v)
                }
                if v.isfloating != shouldFloating { clientSetFloating(v, shouldFloating) }
            }
        case "togglefullscreen":
            guard let c = target ?? clientFocusTop(selectedMonitor) else { return nil }
            c.isInScratchpad = false
            c.isnamedscratchpad = false
            clientSetFullscreen(c, !c.isfullscreen, rearrange: true)
            updateBorders()
        case "togglefakefullscreen":
            guard let c = target ?? clientFocusTop(selectedMonitor) else { return nil }
            clientSetFakeFullscreen(c, !c.isfakefullscreen)
        case "togglemaximizescreen":
            guard let c = target ?? clientFocusTop(selectedMonitor) else { return nil }
            c.isInScratchpad = false
            c.isnamedscratchpad = false
            clientSetMaximizeScreen(c, !c.ismaximizescreen, rearrange: true)
            updateBorders()
        case "toggleglobal":
            guard let c else { return nil }
            if c.isInScratchpad {
                c.isInScratchpad = false
                c.isnamedscratchpad = false
            }
            c.isglobal.toggle()
            updateBorders()
        case "toggleoverlay":
            guard let c, c.mon != nil, !c.isfullscreen else { return nil }
            c.isoverlay.toggle()
            arrange(m, false, false)
        case "toggle_render_border":
            renderBorder.toggle()
            arrange(selectedMonitor, false, false)

        case "minimized":
            guard !selectedMonitor.isoverview, let c, !c.isminimized else { return nil }
            setMinimized(c)
        case "restore_minimized":
            guard !selectedMonitor.isoverview else { return nil }
            let sm: Monitor = selectedMonitor
            let focused = sm.sel.flatMap { clientByIdAll($0) } ?? clientFocusTop(sm)
            var r: Client?
            if let f = focused, SCRATCHPAD_SHOWN(f) {
                r = f
            } else {
                r = clients.first { ($0.mon === sm || config.scratchpadCrossMonitor) && SCRATCHPAD_SHOWN($0) }
            }
            if r == nil { r = clients.first { $0.isminimized && !$0.isnamedscratchpad } }
            guard let r else { return nil }
            if !r.ignoreMinimize { system.clientSetMinimized(r, false) }   // not in mango: macOS's own minimize undone
            let isfloatingBeforeScratchpad = r.isfloatingBeforeScratchpad
            r.isInScratchpad = false
            r.isfloatingBeforeScratchpad = false
            r.isnamedscratchpad = false
            r.isminimized = false
            r.iscustomsize = false
            if let f = focused, f !== r, f.tags != 0 { r.tags = f.tags } else { r.tags = sm.tagset[sm.seltags] }
            r.oldtags = r.tags
            r.mon = sm
            r.isPendingOpenAnimation = true
            clientSetFloating(r, isfloatingBeforeScratchpad)
            clientFocus(r, true)
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
            if c.tags & TAG0_MASK != 0 {
                let back: UInt32 = cm.pertag.prevtag > 0 ? 1 << UInt32(cm.pertag.prevtag - 1) : (cm.pertag.curtag > 0 ? 1 << UInt32(cm.pertag.curtag - 1) : 1)
                if silent { tagSilent(c, back, on: cm) } else { tagClient(c, back) }
            } else if silent {
                specialTagPrepareTarget(cm)
                tagSilent(c, TAG0_MASK, on: cm)
            } else {
                specialTagPrepareTarget(cm)
                tagClient(c, TAG0_MASK)
                if !isSpecialActive(cm) { toggleSpecialTagMon(selectedMonitor) }
            }

        case "movewin":
            guard let c, !c.isfullscreen else { return nil }
            if !c.isfloating { clientSetFloating(c, true) }
            c.floatGeom.origin.x = relOrAbs(a0, c.floatGeom.minX)
            c.floatGeom.origin.y = relOrAbs(a1, c.floatGeom.minY)
            c.iscustomsize = true
            arrange(m, false, false)
        case "resizewin":
            guard let c, !c.isfullscreen, !c.ismaximizescreen else { return nil }
            let animationsBackup = config.animations
            if !c.isfloating { config.animations = false }
            defer { config.animations = animationsBackup }
            if !c.isfloating && !c.isminimized && !c.isunglobal {
                resizeTileClient(c, offsetX: CGFloat(finiteDouble(a0) ?? 0), offsetY: CGFloat(finiteDouble(a1) ?? 0))
            } else {
                c.floatGeom.size.width = max(1, relOrAbs(a0, c.floatGeom.width))
                c.floatGeom.size.height = max(1, relOrAbs(a1, c.floatGeom.height))
                c.iscustomsize = true
                arrange(m, false, false)
            }
        case "smartmovewin":
            guard let c, let dir = Direction(mangoName: a0) else { return nil }
            smartMoveWindow(c, dir)
        case "smartresizewin":
            guard let c, !c.isfullscreen, let dir = Direction(mangoName: a0) else { return nil }
            smartResizeWindow(c, dir)
        case "moveresize":
            let p = system.pointer
            pointerBeginMoveResize(clientAtPoint(p), a0 == "curresize" ? .resize : .move, at: p)
        case "incgaps":
            let sm: Monitor = selectedMonitor
            let i = Int32(truncatingIfNeeded: ValueParse.atoi(a0))
            if isSpecialActive(sm) {
                // not in mango: increase_gaps adds to the normal gaps on the special tag too (a mango bug, docs/afvigelser.md §6)
                setgaps(sm.specialGappoh + i, sm.specialGappov + i, sm.specialGappih + i, sm.specialGappiv + i)
            } else {
                setgaps(sm.gappoh + i, sm.gappov + i, sm.gappih + i, sm.gappiv + i)
            }
        case "togglegaps":
            enableGaps.toggle()
            arrange(selectedMonitor, false, false)

        case "toggleoverview":
            toggleOverview(tc: target, onlyCurrent: a0 == "1")
        case "enteroverview":
            enterOverview(tc: target)
        case "leaveoverview":
            leaveOverview(tc: target)
        case "overcircle":
            overCircle(a0, tc: target)
        case "switcher":
            switcher(a0)
        case "togglejump":
            // not in mango: begin_jump_mode stays on when toggle_overview refuses a grab (a mango bug, docs/afvigelser.md §6)
            guard grab == nil else { return nil }
            toggleJump(tc: target)

        case "dwindle_toggle_split_direction":
            guard let c else { return nil }
            m.pertag.dwindleRoot[getMonCurtag(m)].dwindleSetSplitDirection(c.id, horizontal: nil)
        case "dwindle_toggle_current_split":
            guard let c else { return nil }
            m.pertag.dwindleRoot[getMonCurtag(m)].dwindleToggleCurrentSplit(for: c.id)
            arrange(m, false, false)
        case "dwindle_split_horizontal":
            guard let c else { return nil }
            m.pertag.dwindleRoot[getMonCurtag(m)].dwindleSetSplitDirection(c.id, horizontal: true)
        case "dwindle_split_vertical":
            guard let c else { return nil }
            m.pertag.dwindleRoot[getMonCurtag(m)].dwindleSetSplitDirection(c.id, horizontal: false)

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
            keyMode = String(decoding: a0.utf8.prefix(27), as: UTF8.self)
            printstatus(.keymode); return nil
        case "setoption":
            let value = d.args.dropFirst().joined(separator: ",")
            ConfigParser.parseOption(&config, a0, value, 0, baseDirectory: configURL.deletingLastPathComponent())
            config.overrideConfig()
            updateGlobalVar()   // not in mango: override_config's last step
            resetOption()
        case "groupjoin":
            guard let c, !((c.isfullscreen || c.ismaximizescreen) && (!m.layout.isScroller || c.isfloating)),
                  let dir = Direction(mangoName: a0),
                  let target = directionSelect(dir, from: c) else { return nil }
            clientGroupJoin(c, into: target)
        case "groupleave":
            guard let c else { return nil }
            if clientGroupLeave(c), let cm = c.mon { arrange(cm, false, false) }
        case "groupfocus":
            groupFocus(next: NextPrev(mangoArg: a0) == .next)
        case "togglegroupbar":
            config.alwaysShowGroupBar.toggle()
            arrangeAll(false)
        default:
            // Port extension: not in mango. The port's own dispatchers (chutney_*).
            if let ext = portHooks.extraDispatchers[d.name] {
                if let error = ext(self, d) { return error }
            }
        }
        printstatus(.arrangge)
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
        if c.tags & TAG0_MASK != 0 { return true }
        return (c.tags & TAGMASK).nonzeroBitCount == 1
    }

    func tagClient(_ target: Client?, _ ui: UInt32, allMonitors: Bool = false) {
        let tagmask = TAGMASK
        if let c = target, ui & (tagmask | TAG0_MASK) != 0 {
            c.tags = ui & TAG0_MASK != 0 ? TAG0_MASK : ui & tagmask
            for fc in clients where fc !== c && c.tags & fc.tags != 0 && (fc.isfullscreen || fc.ismaximizescreen)
                && !c.isfloating {
                clearFullscreenFlag(fc)
            }
            if ui & TAG0_MASK != 0, let cm = c.mon { arrange(cm, false, false) }
        }
        clientSwitchView(ui, allMonitors: allMonitors)
        clientFocus(target, true)
        printstatus(.arrangge)
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
        for fc in clients where fc !== c && c.tags & fc.tags != 0 && (fc.isfullscreen || fc.ismaximizescreen) && !c.isfloating {
            clearFullscreenFlag(fc)
        }
        clientFocus(clientFocusTop(selectedMonitor), true)
        arrange(m, false, false)
    }

    func clientActive(_ c: Client) {
        if c.isInScratchpad {
            let visible = c.isInScratchpad && !c.isminimized && c.mon.map { c.tags & $0.tagset[$0.seltags] != 0 } == true
            if visible {
                clientFocus(c, true)
            } else if c.isnamedscratchpad {
                applyNamedScratchpad(c)
            } else {
                _ = switchScratchpadClientState(c)
            }
            return
        }

        if c.isminimized {
            c.isInScratchpad = false
            c.isnamedscratchpad = false
            showHideClient(c)
            if let m = c.mon { arrange(m, false, false) }
            return
        }
        if let cm = c.mon { clientViewOnMonitor(getTagsFirstTag(c.tags), on: cm, changeFocus: true) }
        clientFocus(c, true)
    }

    package func getTagsFirstTag(_ sourceTags: UInt32) -> UInt32 {
        var i: UInt32 = 0, tag: UInt32 = 0

        if sourceTags == 0 {
            return isSpecialActive(selectedMonitor) ? TAG0_MASK
                : (selectedMonitor != nil
                    ? 1 << (selectedMonitor.pertag.curtag != 0 ? selectedMonitor.pertag.curtag - 1 : 0)
                    : 1)
        }

        if sourceTags & TAG0_MASK != 0 { return TAG0_MASK }

        while tag & 1 == 0 && sourceTags != 0 && i < UInt32(config.tagNum) {
            tag = sourceTags >> i
            i += 1
        }

        if i == 1 {
            return 1
        } else if i >= UInt32(config.tagNum) {
            return 1 << (UInt32(config.tagNum) - 1)
        } else {
            return 1 << (i - 1)
        }
    }

    func bindToView(_ mask: UInt32, allMonitors: Bool) {
        let m: Monitor = selectedMonitor
        var target = mask

        if config.viewCurrentToBack && m.pertag.curtag != 0 && (target & TAGMASK) == m.tagset[m.seltags] {
            if m.pertag.prevtag != 0 {
                target = 1 << (m.pertag.prevtag - 1)
            } else {
                // prevtag==0: previous view was the special workspace,
                // decide by the other tagset
                target = (m.tagset[m.seltags ^ 1] & TAG0_MASK) != 0 ? TAG0_MASK : 0
            }
        }

        if !config.viewCurrentToBack && (target & TAGMASK) == m.tagset[m.seltags] { return }

        if Int32(bitPattern: target) == Int32.min && m.pertag.curtag == 0 {
            if config.viewCurrentToBack && m.pertag.prevtag != 0 {
                target = 1 << (m.pertag.prevtag - 1)
            } else {
                target = 0
            }
        }

        // TAG0_MASK is INT_MIN too; handle it before the all-tags branch
        if target == TAG0_MASK {
            clientSwitchView(target, allMonitors: allMonitors)
            return
        }

        if target == 0 || Int32(bitPattern: target) == Int32.min {
            clientSwitchView(~0 & TAGMASK, allMonitors: allMonitors, wantAnimation: false)
        } else {
            clientSwitchView(target, allMonitors: allMonitors)
        }
    }

    package func clientViewOnMonitor(_ ui: UInt32, on m: Monitor, changeFocus: Bool? = nil, wantAnimation: Bool = true) {
        var wantAnimation = wantAnimation
        var tmptag: UInt32

        if ui != (~0 & TAGMASK) && m.isoverview { return }

        if ui == 0 { return }

        if ui == UInt32.max {
            if m.tagset[0] != m.tagset[1] {
                m.pertag.prevtag = getTagsFirstTagNum(m.tagset[m.seltags])
                m.seltags ^= 1 /* toggle sel tagset */
                m.pertag.curtag = getTagsFirstTagNum(m.tagset[m.seltags])
            } else {
                return
            }
        } else {
            if (m.tagset[m.seltags] & ui & (TAGMASK | TAG0_MASK)) != 0 { wantAnimation = false }

            m.seltags ^= 1 /* toggle sel tagset */

            if ui & (TAGMASK | TAG0_MASK) != 0 {
                m.tagset[m.seltags] = ui & (TAGMASK | TAG0_MASK)
                tmptag = m.pertag.curtag

                if ui & TAG0_MASK != 0 {
                    m.pertag.curtag = 0
                } else {
                    var i: UInt32 = 0
                    while ui & (1 << i) == 0 && i < UInt32(config.tagNum) && ui != 0 { i += 1 }
                    m.pertag.curtag = i >= UInt32(config.tagNum) ? UInt32(config.tagNum) : i + 1
                }

                m.pertag.prevtag = tmptag == m.pertag.curtag ? m.pertag.prevtag : tmptag
            } else {
                tmptag = m.pertag.prevtag
                m.pertag.prevtag = m.pertag.curtag
                m.pertag.curtag = tmptag
            }
        }

        // not in mango: arrange's view-change resets (set_size_per), here until arrange is mango's (docs/plan-struktur.md)
        for c in clients where VISIBLEON(c, m) && (c.isglobal || c.isunglobal || (c.tags & ~TAG0_MASK).nonzeroBitCount > 1) {
            setSizePer(m, c, resetProportion: true)
        }
        if changeFocus ?? (m === selectedMonitor) { clientFocus(clientFocusTop(m), true) }
        arrange(m, wantAnimation, true)
        printstatus(.arrangge)
    }

    func getTagStatus(_ tag: UInt32, _ m: Monitor) -> UInt32 {
        var status: UInt32 = 0
        for c in clients {
            if c.mon === m && c.tags & (1 << (tag - 1)) & TAGMASK != 0 {
                if c.isurgent {
                    status = 2
                    break
                }
                status = 1
            }
        }
        return status
    }

    private func tagsLastTagNum(_ tags: UInt32) -> UInt32 {
        var last: UInt32 = 0

        for i in 1...UInt32(config.tagNum) where tags & (1 << (i - 1)) != 0 {
            last = i
        }
        return last
    }

    private func tagGatherLastTagNum(_ m: Monitor) -> UInt32 {
        var last: UInt32 = 0

        for c in clients {
            if c.mon !== m || c.iskilling || (c.tags & TAG0_MASK) != 0 { continue }
            let n = tagsLastTagNum(c.tags & TAGMASK)
            if n > last { last = n }
        }

        last += 1
        if last > UInt32(config.tagNum) { last = UInt32(config.tagNum) }
        return last
    }

    @discardableResult
    func viewShiftTag(_ dir: Int, allMonitors: Bool = false) -> Bool {
        guard let m = selectedMonitor else { return false }
        var wrapped = false

        if m.isoverview || m.pertag.curtag == 0 { return false }

        let cur = getTagsFirstTagNum(m.tagset[m.seltags])
        let last = config.tagGather ? tagGatherLastTagNum(m) : UInt32(config.tagNum)
        var target = m.tagset[m.seltags]

        if dir < 0 {
            target >>= 1

            if target == 0 {
                if !config.tagCarousel { return false }
                target = 1 << (last - 1)
                wrapped = true
            }
        } else {
            target <<= 1

            if config.tagCarousel && cur >= last {
                target = 1
                wrapped = true
            } else if target & TAGMASK == 0 {
                return false
            }
        }

        target &= TAGMASK

        if target == (m.tagset[m.seltags] & TAGMASK) { return false }

        if wrapped { m.carouselAnimDir = dir < 0 ? -1 : 1 }

        clientSwitchView(target, allMonitors: allMonitors)
        m.carouselAnimDir = 0
        return true
    }

    @discardableResult
    func viewShiftTagHaveClient(_ dir: Int, allMonitors: Bool = false) -> Bool {
        guard let sm = selectedMonitor else { return false }

        if sm.isoverview || isSpecialActive(sm) { return false }

        var n: UInt32 = 0
        let current = getTagsFirstTagNum(sm.tagset[sm.seltags])
        var found = false
        var wrapped = false

        if dir < 0 {
            // for (n = current - 1; n >= 1; n--)
            var k = current
            while k > 1 {
                k -= 1
                if getTagStatus(k, sm) != 0 { n = k; found = true; break }
            }

            if !found && config.tagCarousel {
                var k = UInt32(config.tagNum)
                while k > current {
                    if getTagStatus(k, sm) != 0 { n = k; found = true; wrapped = true; break }
                    k -= 1
                }
            }
        } else {
            var k = current + 1
            while k <= UInt32(config.tagNum) {
                if getTagStatus(k, sm) != 0 { n = k; found = true; break }
                k += 1
            }

            if !found && config.tagCarousel {
                var k: UInt32 = 1
                while k < current {
                    if getTagStatus(k, sm) != 0 { n = k; found = true; wrapped = true; break }
                    k += 1
                }
            }
        }

        if found {
            if wrapped { sm.carouselAnimDir = dir < 0 ? -1 : 1 }
            clientSwitchView((1 << (n - 1)) & TAGMASK, allMonitors: allMonitors)
            sm.carouselAnimDir = 0
            return true
        }
        return false
    }

    func viewInsert(next: Bool) {
        guard let sm = selectedMonitor, !sm.isoverview else { return }

        let curmask = sm.tagset[sm.seltags] & TAGMASK
        if curmask == 0 || (curmask & (curmask - 1)) != 0 { return }
        let cur = getTagsFirstTagNum(curmask)
        if cur == 0 { return }

        let target: UInt32
        if next {
            if cur >= UInt32(config.tagNum) { return }
            target = cur + 1
        } else if cur == 1 {
            target = cur
        } else if getTagStatus(cur - 1, sm) == 0 {
            target = cur - 1
        } else {
            target = cur
        }

        if getTagStatus(target, sm) == 0 {
            clientSwitchView((1 << (target - 1)) & TAGMASK)
            return
        }

        if target >= UInt32(config.tagNum) || getTagStatus(UInt32(config.tagNum), sm) != 0 { return }

        viewInsertShiftTags(sm, target)
        let tagGatherBak = config.tagGather
        config.tagGather = false
        clientSwitchView((1 << (target - 1)) & TAGMASK)
        config.tagGather = tagGatherBak
    }

    // remap tags through map; unmapped tags stay as-is.
    func tagRemapMask(_ tags: UInt32, _ map: [UInt32]) -> UInt32 {
        var out = tags & ~TAGMASK

        for i in 1...UInt32(config.tagNum) where tags & (1 << (i - 1)) != 0 {
            out |= map[Int(i)] != 0 ? (1 << (map[Int(i)] - 1)) : (1 << (i - 1))
        }
        return out
    }

    func viewInsertShiftTags(_ m: Monitor, _ target: UInt32) {
        var map = [UInt32](repeating: 0, count: Int(tag_num_MAX) + 1)

        if target < 1 || target >= UInt32(config.tagNum) { return }

        if getTagStatus(UInt32(config.tagNum), m) != 0 { return }

        for i in 1...UInt32(config.tagNum) {
            if i < target {
                map[Int(i)] = i
            } else if i < UInt32(config.tagNum) {
                map[Int(i)] = i + 1
            } else {
                map[Int(i)] = i
            }
        }

        for c in clients {
            if c.mon !== m || c.iskilling { continue }
            c.tags = tagRemapMask(c.tags, map)
        }

        m.tagset[m.seltags] = tagRemapMask(m.tagset[m.seltags], map)
        m.tagset[m.seltags ^ 1] = tagRemapMask(m.tagset[m.seltags ^ 1], map)
        m.ovbkCurrentTagset = tagRemapMask(m.ovbkCurrentTagset, map)
        m.ovbkPrevTagset = tagRemapMask(m.ovbkPrevTagset, map)

        if m.pertag.curtag <= UInt32(config.tagNum) && map[Int(m.pertag.curtag)] != 0 {
            m.pertag.curtag = map[Int(m.pertag.curtag)]
        }
        if m.pertag.prevtag <= UInt32(config.tagNum) && map[Int(m.pertag.prevtag)] != 0 {
            m.pertag.prevtag = map[Int(m.pertag.prevtag)]
        }

        var i = UInt32(config.tagNum) - 1
        while i >= target {
            tagGatherMovePertag(m, i + 1, i)
            i -= 1
        }
    }

    func tagGatherApply(_ m: Monitor) {
        var occupied: UInt32 = 0
        var map = [UInt32](repeating: 0, count: Int(tag_num_MAX) + 1)
        var next: UInt32 = 1
        var changed = false

        // collect occupied tags on this monitor.
        for c in clients where c.mon === m && !c.iskilling && (c.tags & TAG0_MASK) == 0 {
            occupied |= c.tags & tagmask
        }
        // the current view counts as occupied even when empty.
        occupied |= m.tagset[m.seltags] & tagmask

        // old->new mapping and detect gaps.
        for i in 1...UInt32(config.tagNum) {
            if occupied & (1 << (i - 1)) != 0 {
                map[Int(i)] = next
                next += 1
                if map[Int(i)] != i { changed = true }
            } else {
                map[Int(i)] = 0
            }
        }

        if !changed { return }

        // remap client tags.
        for c in clients {
            if c.mon !== m || c.iskilling || (c.tags & TAG0_MASK) != 0 { continue }
            c.tags = tagRemapMask(c.tags, map)
        }

        // remap current/previous views (and overview backups).
        m.tagset[m.seltags] = tagRemapMask(m.tagset[m.seltags], map)
        m.tagset[m.seltags ^ 1] = tagRemapMask(m.tagset[m.seltags ^ 1], map)
        m.ovbkCurrentTagset = tagRemapMask(m.ovbkCurrentTagset, map)
        m.ovbkPrevTagset = tagRemapMask(m.ovbkPrevTagset, map)

        // keep view indices; empty tags stay unchanged.
        if m.pertag.curtag <= UInt32(config.tagNum) && map[Int(m.pertag.curtag)] != 0 {
            m.pertag.curtag = map[Int(m.pertag.curtag)]
        }
        if m.pertag.prevtag <= UInt32(config.tagNum) && map[Int(m.pertag.prevtag)] != 0 {
            m.pertag.prevtag = map[Int(m.pertag.prevtag)]
        }

        // move per-tag state in ascending order so later moves don't clobber
        // earlier sources.
        for i in 1...UInt32(config.tagNum) where map[Int(i)] != 0 && map[Int(i)] != i {
            tagGatherMovePertag(m, map[Int(i)], i)
        }

        // reset trailing empty slots.
        let k = next - 1
        if k + 1 <= UInt32(config.tagNum) {
            for i in (k + 1)...UInt32(config.tagNum) { tagGatherResetSlot(m, i) }
        }
    }

    func setLayout(_ k: LayoutKind, on m: Monitor) {
        m.pertag.ltidxs[getMonCurtag(m)] = k
        clearFullscreenAndMaximizedState(m)
        arrange(m, false, false)
        printstatus(.arrangge)
    }

    func setProportion(_ c: Client, _ p: CGFloat) {
        guard let m = c.mon, !m.isoverview, m.layout.isScroller else { return }
        if tiledClients(m).count == 1 && !config.scrollerIgnoreProportionSingle { return }
        scrollGetStackHeadClient(c).scrollerProportion = p
        arrange(m, false, false)
    }

    func scrollGetStackHeadClient(_ c: Client) -> Client {
        c.mon.map { $0.pertag.scrollerState[getMonCurtag($0)] }?.column(of: c.id).first.flatMap { clientByIdAll($0) } ?? c
    }

    func setgaps(_ oh: Int32, _ ov: Int32, _ ih: Int32, _ iv: Int32) {
        guard let sm = selectedMonitor else { return }
        if isSpecialActive(sm) {
            sm.specialGappoh = max(oh, 0)
            sm.specialGappov = max(ov, 0)
            sm.specialGappih = max(ih, 0)
            sm.specialGappiv = max(iv, 0)
        } else {
            sm.gappoh = max(oh, 0)
            sm.gappov = max(ov, 0)
            sm.gappih = max(ih, 0)
            sm.gappiv = max(iv, 0)
        }
        arrange(sm, false, false)
    }

    func smartResizeWindow(_ c: Client, _ dir: Direction) {
        let sm: Monitor = selectedMonitor
        if !c.isfloating { clientSetFloating(c, true) }
        let w = sm.screen.workArea
        let g = c.floatGeom
        var nw = g.width, nh = g.height
        let others = clients.filter { $0 !== c && $0.isfloating && VISIBLEON($0, sm) }.map(\.floatGeom)
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
        c.iscustomsize = true
        if let cm = c.mon { arrange(cm, false, false) }
    }

    func smartMoveWindow(_ c: Client, _ dir: Direction) {
        guard let m = c.mon, !c.isfullscreen else { return }
        if !c.isfloating { clientSetFloating(c, true) }
        let bw = borderWidth(c, on: m)
        let g = c.floatGeom.insetBy(dx: -bw, dy: -bw)
        let w = m.screen.workArea
        let ih = CGFloat(config.gappih), iv = CGFloat(config.gappiv)
        let others = clients.filter { $0 !== c && $0.isfloating && VISIBLEON($0, selectedMonitor) }.map { o in
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
            ny = max(ny, w.minY + CGFloat(m.gappov))
        case .down:
            ny += (w.height / 4).rounded(.towardZero)
            var tar = CGFloat.infinity
            for t in others where !(g.maxX < t.minX || g.minX > t.maxX) {
                let top = t.minY - iv
                if g.maxY < top && ny + g.height > top { tar = min(tar, top - g.height) }
            }
            if tar != .infinity { ny = tar }
            ny = min(ny, w.maxY - g.height - CGFloat(m.gappov))
        case .left:
            nx -= (w.width / 6).rounded(.towardZero)
            var tar = -CGFloat.infinity
            for t in others where !(g.maxY < t.minY || g.minY > t.maxY) {
                let right = t.maxX + ih
                if g.minX > right && nx < right { tar = max(tar, right) }
            }
            if tar != -.infinity { nx = tar }
            nx = max(nx, w.minX + CGFloat(m.gappoh))
        case .right:
            nx += (w.width / 6).rounded(.towardZero)
            var tar = CGFloat.infinity
            for t in others where !(g.maxY < t.minY || g.minY > t.maxY) {
                let left = t.minX - ih
                if g.maxX < left && nx + g.width > left { tar = min(tar, left - g.width) }
            }
            if tar != .infinity { nx = tar }
            nx = min(nx, w.maxX - g.width - CGFloat(m.gappoh))
        }
        c.floatGeom = CGRect(x: nx, y: ny, width: g.width, height: g.height).insetBy(dx: bw, dy: bw)
        c.iscustomsize = true
        arrange(m, false, false)
    }

    func setSizePer(_ m: Monitor, _ c: Client, resetProportion: Bool = false) {
        let keepOwn = !resetProportion && (c.masterSizeWeight > 0 || c.stackSizeWeight > 0)
        let centered = m.layout == .centerTile
        let tiled = tiledClients(m)
        c.masterMfactPer = CGFloat(m.pertag.mfacts[getMonCurtag(m)])
        for fc in tiled where fc !== c && fc.masterMfactPer > 0 {
            if centered && fc.isleftstack != c.isleftstack { continue }
            c.masterMfactPer = fc.masterMfactPer
            break
        }
        let curtag = getMonCurtag(m)
        if keepOwn {
            if !c.iscustomScrollerProportion && (c.scrollerProportion ?? 0) <= 0 {
                c.scrollerProportion = CGFloat(m.pertag.scrollerDefaultProportion[curtag])
            }
            if !c.iscustomScrollerProportionSingle && (c.scrollerProportionSingle ?? 0) <= 0 {
                c.scrollerProportionSingle = CGFloat(m.pertag.scrollerDefaultProportionSingle[curtag])
            }
            return
        }
        var found = false
        for fc in tiled where fc !== c {
            if centered && fc.isleftstack != c.isleftstack { continue }
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
        if !c.iscustomScrollerProportion { c.scrollerProportion = CGFloat(m.pertag.scrollerDefaultProportion[curtag]) }
        if !c.iscustomScrollerProportionSingle { c.scrollerProportionSingle = CGFloat(m.pertag.scrollerDefaultProportionSingle[curtag]) }
    }

    // not in mango: `fake`, the windows wl_list_for_each with VISIBLEON and ISFAKETILED finds
    func resetSizePerMon(_ m: Monitor, _ fake: [Client], totalLeftStackWeight totalLeft: CGFloat,
                         totalRightStackWeight totalRight: CGFloat, totalStackWeight totalStack: CGFloat,
                         totalMasterWeight totalMaster: CGFloat, masterNum: Int, stackNum: Int) {
        let nmasters = m.pertag.nmasters[getMonCurtag(m)]
        let centered = m.layout == .centerTile
        for (i, c) in fake.enumerated() {
            if totalMaster > 0 && i < nmasters {
                c.ismaster = true
                c.masterInnerPer = c.masterSizeWeight / totalMaster
                let stackSide = centered ? totalLeft + totalRight : totalStack
                c.stackInnerPer = stackSide > 0 ? c.stackSizeWeight / (stackSide + c.stackSizeWeight) : 1
            } else {
                c.ismaster = false
                c.masterInnerPer = totalMaster > 0 ? c.masterSizeWeight / (totalMaster + c.masterSizeWeight)
                    : (masterNum > 0 ? 1 / CGFloat(masterNum) : 1)
                if centered {
                    let side = c.isleftstack ? totalLeft : totalRight
                    c.stackInnerPer = side > 0 ? c.stackSizeWeight / side : 1
                } else {
                    c.stackInnerPer = totalStack > 0 ? c.stackSizeWeight / totalStack
                        : (stackNum > 0 ? 1 / CGFloat(stackNum) : 1)
                }
            }
        }
    }

    func persistTileSizeWeights(_ m: Monitor) {
        for c in clients where VISIBLEON(c, m) && !c.isfloating && !c.isminimized && !c.isunglobal {
            if c.ismaster { c.masterSizeWeight = c.masterInnerPer } else { c.stackSizeWeight = c.stackInnerPer }
        }
    }

    func resizeTileClient(_ gc: Client, isdrag: Bool = false, offsetX: CGFloat, offsetY: CGFloat, cursor: CGPoint = .zero) {
        guard let m = gc.mon, !gc.isfullscreen, !gc.ismaximizescreen, !m.isoverview else { return }
        let layout = m.pertag.ltidxs[getClientTagIdx(gc)]
        switch layout {
        case .tile, .deck, .centerTile, .rightTile:
            resizeTileMaster(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor,
                             type: layout, vertical: false)
        case .verticalTile, .verticalDeck:
            resizeTileMaster(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor,
                             type: layout, vertical: true)
        case .scroller:
            resizeTileScroller(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor, vertical: false)
        case .verticalScroller:
            resizeTileScroller(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor, vertical: true)
        case .dwindle:
            resizeTileDwindle(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor)
        case .grid, .verticalGrid, .fair, .verticalFair:
            resizeTileGridFair(gc, isdrag: isdrag, offsetX: offsetX, offsetY: offsetY, cursor: cursor)
        default:
            break
        }
    }

    // not in mango: resize_tile_master_horizontal and _vertical in one; `vertical` says which
    func resizeTileMaster(_ gc: Client, isdrag: Bool, offsetX: CGFloat, offsetY: CGFloat, cursor: CGPoint,
                          type: LayoutKind, vertical: Bool) {
        guard let m = gc.mon else { return }
        let tiled = tiledClients(m)
        guard let gi = tiled.firstIndex(where: { $0 === gc }) else { return }
        let next = gi + 1 < tiled.count ? tiled[gi + 1] : nil
        let nextnext = gi + 2 < tiled.count ? tiled[gi + 2] : nil
        let prev = gi > 0 ? tiled[gi - 1] : nil
        let prevprev = gi > 1 ? tiled[gi - 2] : nil
        let geom = gc.geom
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
            across = Float(ox) * (gc.ismaster ? oldMfact : 1 - oldMfact) / bw
            along = Float(oy) * (gc.ismaster ? oldMInner : oldSInner) / bh
        } else {
            along = Float(ox) * (gc.ismaster ? oldMInner : oldSInner) / bw
            across = Float(oy) * (gc.ismaster ? oldMfact : 1 - oldMfact) / bh
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
        if gc.ismaster && prev == nil {
            along = back ? -abs(along) : abs(along)
        } else if gc.ismaster, let next, !next.ismaster {
            along = back ? abs(along) : -abs(along)
        } else if !gc.ismaster, let prev, prev.ismaster {
            along = back ? -abs(along) : abs(along)
        } else if !gc.ismaster && next == nil {
            along = back ? abs(along) : -abs(along)
        } else if !vertical && type == .centerTile && !gc.ismaster && nextnext == nil {
            along = back ? abs(along) : -abs(along)
        } else if !vertical && type == .centerTile && !gc.ismaster, let prevprev, prevprev.ismaster {
            along = back ? -abs(along) : abs(along)
        } else if (first && back) || (!first && forth) {
            along = abs(along) * 2
        } else {
            along = -abs(along) * 2
        }
        if !vertical {
            if !gc.ismaster && gc.isleftstack && type == .centerTile { across = -across }
            if gc.ismaster && type == .centerTile && gc.cursorInLeftHalf { across = -across }
            if gc.ismaster && type == .centerTile { across *= 2 }
            if type == .rightTile { across = -across }
        }
        let newMfact = max(0.1, min(0.9, oldMfact + across))
        let newMInner = max(0.1, min(0.9, oldMInner + along))
        let newSInner = max(0.1, min(0.9, oldSInner + along))
        if isdrag {
            if gc.ismaster {
                let cur = 1 - Float(gc.masterInnerPer), new = 1 - newMInner
                if cur > 0.001 {
                    for tc in tiled where tc.ismaster && tc !== gc { tc.masterInnerPer *= CGFloat(new / cur) }
                }
            } else {
                let cur = 1 - Float(gc.stackInnerPer), new = 1 - newSInner
                if cur > 0.001 {
                    for tc in tiled where !tc.ismaster && tc !== gc
                        && (vertical || type != .centerTile || tc.isleftstack == gc.isleftstack) {
                        tc.stackInnerPer *= CGFloat(new / cur)
                    }
                }
            }
        } else {
            for tc in tiled where tc !== gc {
                if !tc.ismaster && newSInner != 1 && oldSInner != 1
                    && (vertical || type != .centerTile || tc.isleftstack == gc.isleftstack) {
                    tc.stackInnerPer = CGFloat((1 - newSInner) / (1 - oldSInner)) * tc.stackInnerPer
                }
                if tc.ismaster && newMInner != 1 && oldMInner != 1 {
                    tc.masterInnerPer = CGFloat((1 - newMInner) / (1 - oldMInner)) * tc.masterInnerPer
                }
            }
        }
        gc.masterInnerPer = CGFloat(newMInner)
        gc.stackInnerPer = CGFloat(newSInner)
        for tc in tiled { tc.masterMfactPer = CGFloat(newMfact) }
        persistTileSizeWeights(m)
        if !isdrag {
            arrange(m, false, false)
            return
        }
        arrange(m, false, false)
    }

    func resizeTileScroller(_ gc: Client, isdrag: Bool, offsetX: CGFloat, offsetY: CGFloat, cursor: CGPoint,
                            vertical: Bool) {
        guard let m = gc.mon else { return }
        let tag = getClientTagIdx(gc)
        let col = m.pertag.scrollerState[tag].column(of: gc.id).compactMap { clientByIdAll($0) }
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
        let headProportion = head.scrollerProportion ?? CGFloat(m.pertag.scrollerDefaultProportion[tag])
        let geom = gc.geom
        if !startDragWindow && isdrag {
            dragBeginCursor = cursor
            startDragWindow = true
            head.oldScrollerPproportion = headProportion
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
            head.oldScrollerPproportion = headProportion
            gc.scrollerOldStackProportion = CGFloat(props[ci])
            gc.cursorInUpperHalf = false
            gc.cursorInLeftHalf = false
        }
        let bw = Float(max(1, gc.dragBeginGeom.width)), bh = Float(max(1, gc.dragBeginGeom.height))
        let oldHead = Float(head.oldScrollerPproportion), oldStack = Float(gc.scrollerOldStackProportion)
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
        let heads = m.pertag.scrollerState[tag].columns(for: tiledClients(m).map(\.id)).count
        if heads > 1 || config.scrollerIgnoreProportionSingle {
            head.scrollerProportion = CGFloat(newScroller)
        }
        for (k, c) in col.enumerated() { c.scrollerStackWeight = CGFloat(props[k]) }
        if !isdrag {
            arrange(m, false, false)
            return
        }
        arrange(m, false, false)
    }

    func resizeTileDwindle(_ gc: Client, isdrag: Bool, offsetX: CGFloat, offsetY: CGFloat, cursor: CGPoint) {
        guard let m = gc.mon else { return }
        let tree = m.pertag.dwindleRoot[getMonCurtag(m)]
        if !isdrag {
            tree.dwindleResizeClientStep(gc.id, dx: offsetX, dy: offsetY, config: config)
            arrange(m, false, false)
            return
        }
        if tree.dwindleResizeClient(gc.id, startDragWindow: &startDragWindow, dragBeginCursor: &dragBeginCursor,
                                    cursor: cursor, smartResize: config.dwindleSmartResize) {
            arrange(m, false, false)
        }
    }

    func resizeTileGridFair(_ gc: Client, isdrag: Bool, offsetX: CGFloat, offsetY: CGFloat, cursor: CGPoint) {
        guard let m = gc.mon, !gc.isfullscreen, !gc.ismaximizescreen, !m.isoverview else { return }
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
        var adjC = gc.gridColIdx, adjR = gc.gridRowIdx
        var signX: Float = 1, signY: Float = 1

        if isdrag {
            if gc.cursorInLeftHalf {
                adjC -= 1
                signX = -1
            } else {
                adjC += 1
                signX = 1
            }

            if gc.cursorInUpperHalf {
                adjR -= 1
                signY = -1
            } else {
                adjR += 1
                signY = 1
            }
        }
        // Keyboard hotkey logic unchanged.
        let maxCol = tiled.map(\.gridColIdx).max() ?? 0, minCol = tiled.map(\.gridColIdx).min() ?? 0
        let maxRow = tiled.map(\.gridRowIdx).max() ?? 0, minRow = tiled.map(\.gridRowIdx).min() ?? 0

        // not in mango: for the keyboard only; mango overwrites the drag's neighbour with it
        // (a mango bug, docs/afvigelser.md §6)
        if !isdrag {
            adjC = gc.gridColIdx + 1
            adjR = gc.gridRowIdx + 1
            signX = 1
            signY = 1

            if gc.gridColIdx == maxCol { adjC = gc.gridColIdx - 1; signX = -1 }
            if gc.gridRowIdx == maxRow { adjR = gc.gridRowIdx - 1; signY = -1 }
            if gc.gridColIdx == minCol { adjC = gc.gridColIdx + 1; signX = 1 }
            if gc.gridRowIdx == minRow { adjR = gc.gridRowIdx + 1; signY = 1 }
        }
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
        arrange(m, false, false)
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
            let s1 = m1.pertag.scrollerState[getMonCurtag(m1)], s2 = m2.pertag.scrollerState[getMonCurtag(m2)]
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
                m1.pertag.dwindleRoot[getMonCurtag(m1)].dwindleSwapClients(c1.id, c2.id)
            } else {
                m1.pertag.dwindleRoot[getMonCurtag(m1)].replace(c1.id, with: c2.id, config: config)
                m2.pertag.dwindleRoot[getMonCurtag(m2)].replace(c2.id, with: c1.id, config: config)
                swapMonitorsAndTags()
            }
            swapList()
        } else {
            swapLayoutProperties()
            swapList()
            if m1 !== m2 { swapMonitorsAndTags() }
        }
        arrange(m1, false, false)
        if m2 !== m1 { arrange(m2, false, false) }
        focusStack.removeAll { $0 == c2.id }
        if let i = focusStack.firstIndex(of: c1.id) { focusStack.insert(c2.id, at: i + 1) }
        if config.warpcursor { pointerWarpToClient(c1) }
    }

    func focusStack(_ dir: NextPrev, from target: Client? = nil) {
        guard let sel = target ?? clientFocusTop(selectedMonitor),
              let tc = getNextStackClient(sel, reverse: dir == .prev) else { return }
        clientFocus(tc, true)
        if config.warpcursor { pointerWarpToClient(tc) }
    }

    func getNextStackClient(_ c: Client, reverse: Bool) -> Client? {
        guard let m = c.mon, let i = clients.firstIndex(where: { $0 === c }) else { return nil }
        let n = clients.count
        for k in 1..<max(n, 1) {
            let x = clients[reverse ? (i - k + n) % n : (i + k) % n]
            if x.isunglobal { continue }
            if x !== c, x.mon != nil, VISIBLEON(x, m) { return x }
        }
        return nil
    }

    func focusDirection(_ dir: Direction) {
        let m = selectedMonitor!
        // not in mango: not in the overview, whose cards are no monocle (a mango bug, docs/afvigelser.md §6)
        if m.layout == .monocle, !m.isoverview, let sel = focused, !sel.isfloating, dir.isHorizontal {
            focusStack(dir == .right ? .next : .prev)
            return
        }
        var c = directionSelect(dir)

        if let sc = c, sc.mon !== selectedMonitor && !config.focusCrossMonitor { return }

        if let sc = c, !m.isoverview {
            if sc.mon !== selectedMonitor {
                guard let tm = sc.mon, let top = clientFocusTop(tm) else { return }
                c = top
                selectedMonitor = tm
            } else {
                c = getFocusedStackClient(sc, nil)
            }
        }
        if let c {
            clientFocus(c, true)
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
        if m.isoverview { return }
        let c = getFocusedStackClient(directionSelect(dir), nil)
        if let c, c.mon === m {
            clientFocus(c, true)
            if config.warpcursor { pointerWarpToClient(c) }
            return
        }
        guard !isSpecialActive(m) else { return }
        let forward = dir == .right || dir == .down
        if !viewShiftTagHaveClient(forward ? 1 : -1) { viewShiftTag(forward ? 1 : -1) }
    }

    func directionSelect(_ dir: Direction, from: Client? = nil) -> Client? {
        guard let tc = from ?? focused else { return nil }
        if (tc.isfullscreen || tc.ismaximizescreen) && (!selectedMonitor.layout.isScroller || tc.isfloating) { return nil }
        return findClientByDirection(tc, dir, findFloating: true)
    }

    /// Not in mango: c->geom, or the card in the overview's pictures.
    func directionGeom(_ c: Client) -> CGRect {
        if let m = c.mon, m.isoverview, let card = m.ovCards[c.id] { return card }
        return c.geom
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
                if !findFloating && c.isfloating { continue }
                if !VISIBLEON(c, cm) || c.isunglobal { continue }
                if !config.focusCrossMonitor && cm !== tc.mon { continue }
                if c.tags & cm.tagset[cm.seltags] == 0 && !c.isglobal { continue }
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
                    if !m.isoverview && !clientIsInSameStack(tc, c, nil) { continue }
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
        if !layout.isScroller && tc.mon !== selectedMonitor && (tc.isfullscreen || tc.ismaximizescreen) { return true }
        switch layout {
        case .monocle:
            return !tc.isTabHidden
        case .scroller, .verticalScroller:
            func head(_ c: Client) -> ClientID? {
                guard let cm = c.mon else { return nil }
                return cm.pertag.scrollerState[getMonCurtag(cm)].column(of: c.id).first ?? c.id
            }
            if let fc, head(fc) == head(sc) { return false }
            return head(sc) == head(tc)
        case .tile, .verticalTile, .deck, .verticalDeck, .rightTile:
            if tabMembers(m).contains(where: { $0 === tc }) { return !tc.isTabHidden }
            if tc.ismaster != sc.ismaster { return false }
            if let fc, fc.ismaster == sc.ismaster { return false }
            return true
        case .centerTile:
            if tc.ismaster != sc.ismaster { return false }
            if let fc, fc.ismaster == sc.ismaster { return false }
            return directionGeom(sc).minX == directionGeom(tc).minX
        default:
            return false
        }
    }

    func getFocusedStackClient(_ sc: Client?, _ customFocusClient: Client?) -> Client? {
        guard let sc, !sc.isfloating, let fc = customFocusClient ?? focused, !fc.isfloating, let m = sc.mon else { return sc }
        let block: Set<ClientID>? = m.layout == .dwindle ? m.pertag.dwindleRoot[getMonCurtag(m)].dwindleFocusBlockRoot(sc.id, fc.id) : nil
        for id in focusStack {
            guard let tc = clientByIdAll(id), !tc.isunglobal, VISIBLEON(tc, m), tc !== fc else { continue }
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
            clientFocus(c, true)
        } else {
            target.sel = nil
            system.keyboardNotifyClearFocus()
            clientFocus(nil, false)
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
        old.pertag.scrollerState[getClientTagIdx(c)].scrollerNodeRemove(c.id)
        c.mon = m
        c.parked = false   // not in mango: the system places it on the new display
        if !VISIBLEON(c, m) { clientResetMonTags(c, m, 0) }
        m.sel = c.id
        selectedMonitor = m
    }

    @discardableResult
    func clientJumpToMonitor(_ c: Client, _ m: Monitor, _ dir: Direction) -> Bool {
        guard let old = c.mon, old !== m, config.exchangeCrossMonitor,
              monitorMoveDirection(old, m) == dir else { return false }
        clientReassignMonitor(c, m)
        arrange(old, false, false)
        arrange(m, false, false)
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
            let st = dst.pertag.scrollerState[getMonCurtag(dst)]
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
        arrange(src, false, false)
        arrange(dst, false, false)
    }

    func dwindleMoveNextTo(_ c: Client, _ target: Client, _ dir: Direction) {
        guard let cm = c.mon, c !== target, let tm = target.mon else { return }
        let crossed = cm !== tm
        let origin = c.geom
        if !clientJumpToMonitor(c, tm, dir) && c.mon !== tm { return }
        guard let m = c.mon else { return }
        m.pertag.dwindleRoot[getMonCurtag(m)].dwindleMoveNextTo(c.id, nextTo: target.id, direction: dir, crossed: crossed,
                                                      origin: origin, config: config)
        arrange(m, false, false)
    }

    func tagMonitor(_ c: Client, to m: Monitor, newtags: UInt32) {
        guard c.mon != nil else { return }
        if c.mon === m {
            clientViewOnMonitor(newtags, on: selectedMonitor, changeFocus: true)
            return
        }

        if !clientSetMonitorAdapted(c, m, newtags, focus: true) { return }

        selectedMonitor = c.mon
        let target = getTagsFirstTag(c.tags)

        clientViewOnMonitor(target, on: selectedMonitor, changeFocus: true)
        clientFocus(c, true)
        arrange(selectedMonitor, false, false)
        if config.warpcursor, let cm = c.mon { pointerWarpToMonitor(cm) }
    }

    private func specialTagMigrateClients(_ target: Monitor) {
        var layoutCopied = false

        for c in clients {
            guard let oldmon = c.mon, oldmon !== target, c.tags & TAG0_MASK != 0 else { continue }

            if !layoutCopied {
                monitorCopyTagLayout(target, oldmon, 0)
                layoutCopied = true
            }
            _ = clientSetMonitorAdapted(c, target, TAG0_MASK, focus: false)
        }
    }

    func specialTagPreviousTagset(_ m: Monitor) -> UInt32 {
        let previous = m.tagset[m.seltags ^ 1] & ~TAG0_MASK
        return previous != 0 ? previous : (m.pertag.prevtag > 0 ? 1 << UInt32(m.pertag.prevtag - 1) : 1)
    }

    func specialTagPrepareTarget(_ target: Monitor) {
        guard config.specialTagCrossMonitor else { return }

        for m in monitors where m !== target && !m.isoverview && isSpecialActive(m) {
            clientViewOnMonitor(specialTagPreviousTagset(m), on: m, changeFocus: false)
        }

        specialTagMigrateClients(target)
    }

    func toggleScratchpad() {
        if selectedMonitor.isoverview { return }
        var shown: Client?
        var hidden: Client?
        for c in clients {
            if !config.scratchpadCrossMonitor && c.mon !== selectedMonitor { continue }
            if config.singleScratchpad && c.isnamedscratchpad && SCRATCHPAD_SHOWN(c) {
                setMinimized(c)
                continue
            }
            if c.isnamedscratchpad { continue }
            if shown == nil && SCRATCHPAD_SHOWN(c) {
                shown = c
            } else if c.isInScratchpad {
                hidden = c   // LIFO insertion puts the oldest scratchpad last.
            }
        }

        if let shown {
            _ = switchScratchpadClientState(shown)
        } else if let hidden {
            _ = switchScratchpadClientState(hidden)
        }
    }

    func setMinimized(_ c: Client) {
        guard let m = c.mon, grab?.client !== c else { return }

        if !c.isInScratchpad {
            c.isfloatingBeforeScratchpad = c.isfloating
        }

        c.isglobal = false
        c.oldtags = m.tagset[m.seltags]
        c.tags = 0
        c.isminimized = true
        c.isInScratchpad = true
        clientFocus(clientFocusTop(selectedMonitor), true)
        arrange(m, false, false)
        clients.removeAll { $0 === c }
        clients.insert(c, at: 0)
    }

    func showHideClient(_ c: Client) {
        guard let m = c.mon else { return }
        if !c.ignoreMinimize { system.clientSetMinimized(c, false) }   // not in mango: macOS's own minimize undone
        setSizePer(m, c)
        let target = getTagsFirstTag(c.oldtags)
        if !c.isInScratchpad {
            tagClient(c, target)
        } else {
            c.tags = m.tagset[m.seltags]
            c.isminimized = false
            arrange(m, false, false)
        }
        c.isminimized = false
        clientFocus(c, true)
    }

    func showScratchpad(_ c: Client) {
        guard let m = c.mon else { return }
        if c.isfullscreen || c.ismaximizescreen {
            c.isfullscreen = false
            c.ismaximizescreen = false
        }
        if !c.isfloating { clientSetFloating(c, true) }
        if !c.iscustomsize {
            let w = m.screen.workArea
            c.floatGeom.size = CGSize(width: (w.width * CGFloat(config.scratchpadWidthRatio)).rounded(.towardZero),
                                      height: (w.height * CGFloat(config.scratchpadHeightRatio)).rounded(.towardZero))
            c.floatGeom = clientCenterGeometry(c, m, c.floatGeom)
            c.iscustomsize = true
        }
        c.oldtags = m.tagset[m.seltags]
        clients.removeAll { $0 === c }
        clients.insert(c, at: 0)
        showHideClient(c)
    }

    func switchScratchpadClientState(_ c: Client) -> Bool {
        guard let old = c.mon, c.isInScratchpad else { return false }
        let shown = SCRATCHPAD_SHOWN(c)
        if config.scratchpadCrossMonitor && old !== selectedMonitor {
            c.mon = selectedMonitor
            clientUpdateOldmonnameRecord(c, selectedMonitor)

            clientAdaptGeometryToMonitor(c, old)

            if shown {
                c.tags = getTagsFirstTag(selectedMonitor.tagset[selectedMonitor.seltags])
                arrange(selectedMonitor, false, false)
                clientFocus(c, true)
                return true
            }
        }
        guard let m = c.mon else { return false }
        if shown && m.tagset[m.seltags] & c.tags != 0 {
            setMinimized(c)
            return true
        }
        c.tags = m.tagset[m.seltags]
        c.oldtags = c.tags
        c.scratchpadTagin = true
        if shown {
            arrange(m, false, false)
            clientFocus(c, true)
        } else {
            showScratchpad(c)
        }
        return true
    }

    func toggleNamedScratchpad(appId: String, title: String, command: String) {
        if selectedMonitor.isoverview { return }
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
        c.isnamedscratchpad = true
        applyNamedScratchpad(c)
    }

    func applyNamedScratchpad(_ target: Client) {
        for c in clients {
            if !config.scratchpadCrossMonitor && c.mon !== selectedMonitor { continue }
            if config.singleScratchpad && SCRATCHPAD_SHOWN(c) && c !== target { setMinimized(c) }
        }
        if !target.isInScratchpad { setMinimized(target) }
        _ = switchScratchpadClientState(target)
    }
}

private func < (a: (CGFloat, CGFloat), b: (CGFloat, CGFloat)) -> Bool {
    a.0 != b.0 ? a.0 < b.0 : a.1 < b.1
}
