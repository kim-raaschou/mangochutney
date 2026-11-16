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
            guard let target = parseMonitorArg(a0) else { return "monitor not found" }
            focusMonitor(target)
        case "tagmon":
            guard let c = target ?? clientFocusTop(selectedMonitor),
                  let tm = parseMonitorArg(a0) else { return nil }
            tagMonitor(c, to: tm, newtags: ValueParse.atoi(a1) != 0 ? c.tags : 0)

        case "exchange_client":
            guard let c, !c.isfloating, let dir = Direction(mangoName: a0) else { return nil }
            if (c.isfullscreen || c.ismaximizescreen) && !isScrollerLayout(m) { return nil }
            if let tc = getFocusedStackClient(directionSelect(dir, from: target), target) { clientExchange(c, tc) }
        case "exchange_stack_client":
            guard let c, !c.isfloating, !c.isfullscreen, !c.ismaximizescreen else { return nil }
            if let tc = getNextStackClient(c, reverse: NextPrev(mangoArg: a0) == .prev) { clientExchange(c, tc) }
        case "move_client":
            guard let c, let cm = c.mon, !c.isfloating, let dir = Direction(mangoName: a0) else { return nil }
            if (c.isfullscreen || c.ismaximizescreen) && !isScrollerLayout(cm) { return nil }
            if let tc = directionSelect(dir, from: target) {
                if tc.mon !== cm {
                    clientMoveToMonitor(c, tc, dir)
                } else if cm.layout == .dwindle {
                    dwindleMoveNextTo(c, tc, Float(config.dwindleSplitRatio), dir)
                } else if let t2 = getFocusedStackClient(tc, c) {
                    clientExchange(c, t2)
                }
            } else if let tm = monitorFromDirection(dir) {
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
            guard isScrollerLayout(selectedMonitor), !selectedMonitor.isoverview,
                  let f = finiteDouble(a0) else { return nil }
            if selectedMonitor.visibleTilingClients == 1 && !config.scrollerIgnoreProportionSingle { return nil }
            guard let c else { return nil }
            setProportion(c, Float(f))
        case "switch_proportion_preset":
            guard !config.scrollerProportionPreset.isEmpty, isScrollerLayout(selectedMonitor),
                  !selectedMonitor.isoverview else { return nil }
            if selectedMonitor.visibleTilingClients == 1 && !config.scrollerIgnoreProportionSingle { return nil }
            guard let c, !c.isfloating else { return nil }
            var targetProportion: Float = 0
            let tc = scrollGetStackHeadClient(c)
            guard let tm = tc.mon else { return nil }
            let node = findScrollerNode(tm.pertag.scrollerState[getMonCurtag(tm)], tc)
            let currentProportion = node?.scrollerProportion ?? tc.scrollerProportion
            let presets = config.scrollerProportionPreset.map { Float($0) }
            for i in presets.indices where presets[i] == currentProportion {
                targetProportion = i == presets.count - 1 ? presets[0] : presets[i + 1]
                break
            }
            if targetProportion == 0.0 { targetProportion = presets[0] }
            setProportion(c, targetProportion)
        case "scroller_stack":
            guard let c, c.mon != nil, !c.isfloating, isScrollerLayout(selectedMonitor),
                  let dir = Direction(mangoName: a0) else { return nil }
            let targetClient = findClientByDirection(c, dir, findFloating: false)
            scrollerApplyStack(c, targetClient, dir)
        case "centerwin":
            guard let c, !c.isfullscreen, !c.ismaximizescreen else { return nil }
            if c.isfloating {
                let w = m.w
                c.floatGeom = clientCenterGeometry(c, c.floatGeom, in: w).rounded()
                c.iscustomsize = true
            } else if isScrollerLayout(selectedMonitor) {
                let stackHead = scrollGetStackHeadClient(c)
                let w = WBox(selectedMonitor.w)
                if selectedMonitor.pertag.ltidxs[getMonCurtag(selectedMonitor)] == .scroller {
                    stackHead.geom.origin.x = CGFloat(w.x + (w.width - Int32(stackHead.geom.width)) / 2)
                } else {
                    stackHead.geom.origin.y = CGFloat(w.y + (w.height - Int32(stackHead.geom.height)) / 2)
                }
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
            guard let target = parseMonitorArg(a1) else { return "monitor not found" }
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
            pointerBeginMoveResize(nodeAtPoint(p), a0 == "curresize" ? .resize : .move, at: p)
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
            guard let c, c.mon != nil, !c.isfloating else { return nil }
            dwindleSetSplitDirection(c, true, false)
        case "dwindle_toggle_current_split":
            guard let c, let cm = c.mon, !c.isfloating else { return nil }
            let tag = getClientTagIdx(c)
            if cm.pertag.ltidxs[tag] != .dwindle { return nil }
            guard let leaf = dwindleFindLeaf(cm.pertag.dwindleRoot[tag], c), let parent = leaf.parent else { return nil }
            parent.splitH = !parent.splitH
            parent.splitLocked = true
            arrange(cm, false, false)
        case "dwindle_split_horizontal":
            guard let c, c.mon != nil, !c.isfloating else { return nil }
            dwindleSetSplitDirection(c, false, true)
        case "dwindle_split_vertical":
            guard let c, c.mon != nil, !c.isfloating else { return nil }
            dwindleSetSplitDirection(c, false, false)

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
            guard let c, !((c.isfullscreen || c.ismaximizescreen) && (!isScrollerLayout(m) || c.isfloating)),
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




    func tagSilent(_ c: Client, _ mask: UInt32, on m: Monitor) {
        c.tags = mask
        for fc in clients where fc !== c && c.tags & fc.tags != 0 && (fc.isfullscreen || fc.ismaximizescreen) && !c.isfloating {
            clearFullscreenFlag(fc)
        }
        clientFocus(clientFocusTop(selectedMonitor), true)
        arrange(m, false, false)
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

    /// not in mango: set_proportion's and switch_proportion_preset's common end (dispatch/bind.c)
    func setProportion(_ c: Client, _ f: Float) {
        let tc = scrollGetStackHeadClient(c)
        guard let m = tc.mon else { return }
        let tag = getMonCurtag(m)
        let st = m.pertag.scrollerState[tag]
        var node: ScrollerStackNode?

        if let st { node = findScrollerNode(st, tc) }

        if let node { node.scrollerProportion = f }
        tc.scrollerProportion = f

        let w = WBox(m.w)
        let maxClientWidth = UInt32(truncatingIfNeeded: w.width - 2 * Int32(config.scrollerStructs) - Int32(config.gappih))
        tc.geom.size.width = CGFloat(i32(Float(maxClientWidth) * f))

        arrange(m, false, false)
    }

    func scrollerApplyStack(_ c: Client, _ targetClient: Client?, _ direction: Direction) {
        guard let m = c.mon, !c.isfloating, isScrollerLayout(m) else { return }

        let tag = getClientTagIdx(c)

        let isHorizontal = m.pertag.ltidxs[tag] == .scroller

        if isHorizontal && (direction == .up || direction == .down) { return }
        if !isHorizontal && (direction == .left || direction == .right) { return }

        let st = ensureScrollerState(m, tag)

        guard let cnode = findScrollerNode(st, c) else { return }

        let tnode = targetClient.flatMap { findScrollerNode(st, $0) }

        // not in mango: no UNDIR here; scroller_stack's direction is one of the four

        if cnode.prevInStack != nil || cnode.nextInStack != nil {
            let moveOutReferNode = cnode.prevInStack ?? cnode.nextInStack!
            scrollerNodeRemove(st, cnode)

            updateScrollerState(m)

            let stackHead = scrollGetStackHeadClient(moveOutReferNode.client)
            let stackTail = scrollGetStackTailClient(moveOutReferNode.client)

            if direction == .left || direction == .up {
                if c !== stackHead { wlListSafeReinsertPrev(stackHead, c) }
            } else if direction == .right || direction == .down {
                if c !== stackTail { wlListSafeReinsertNext(stackHead, c) }
            }
            syncScrollerStateToClients(m, tag)
            arrange(m, false, false)
            return
        }

        guard let tnode, let targetClient, targetClient.mon === c.mon else { return }

        var tail = tnode
        while let n = tail.nextInStack { tail = n }

        scrollerInsertStack(c, tail.client, false)

        if c !== tail.client {
            clients.removeAll { $0 === c }
            if let i = clients.firstIndex(where: { $0 === tail.client }) { clients.insert(c, at: i + 1) }
        }
    }


    func smartResizeWindow(_ c: Client, _ dir: Direction) {
        let sm: Monitor = selectedMonitor
        if !c.isfloating { clientSetFloating(c, true) }
        let w = sm.w
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
        let g = c.floatGeom
        let w = m.w
        let ih = CGFloat(config.gappih), iv = CGFloat(config.gappiv)
        let others = clients.filter { $0 !== c && $0.isfloating && VISIBLEON($0, selectedMonitor) }.map(\.floatGeom)
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
        c.floatGeom = CGRect(x: nx, y: ny, width: g.width, height: g.height)
        c.iscustomsize = true
        arrange(m, false, false)
    }

    func setSizePer(_ m: Monitor, _ c: Client, resetProportion: Bool = false) {
        let keepOwn = !resetProportion && (c.masterSizeWeight > 0 || c.stackSizeWeight > 0)
        let centered = isCentertileLayout(m)
        let tiled = tiledClients(m)
        c.masterMfactPer = CGFloat(m.pertag.mfacts[getMonCurtag(m)])
        for fc in tiled where fc !== c && fc.masterMfactPer > 0 {
            if centered && fc.isleftstack != c.isleftstack { continue }
            c.masterMfactPer = fc.masterMfactPer
            break
        }
        let curtag = getMonCurtag(m)
        if keepOwn {
            if !c.iscustomScrollerProportion && c.scrollerProportion <= 0.0 {
                c.scrollerProportion = m.pertag.scrollerDefaultProportion[curtag]
            }
            if !c.iscustomScrollerProportionSingle && c.scrollerProportionSingle <= 0.0 {
                c.scrollerProportionSingle = m.pertag.scrollerDefaultProportionSingle[curtag]
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
        if !c.iscustomScrollerProportion { c.scrollerProportion = m.pertag.scrollerDefaultProportion[curtag] }
        if !c.iscustomScrollerProportionSingle { c.scrollerProportionSingle = m.pertag.scrollerDefaultProportionSingle[curtag] }
    }

    // not in mango: `fake`, the windows wl_list_for_each with VISIBLEON and ISFAKETILED finds
    func resetSizePerMon(_ m: Monitor, _ fake: [Client], totalLeftStackWeight totalLeft: CGFloat,
                         totalRightStackWeight totalRight: CGFloat, totalStackWeight totalStack: CGFloat,
                         totalMasterWeight totalMaster: CGFloat, masterNum: Int, stackNum: Int) {
        let nmasters = m.pertag.nmasters[getMonCurtag(m)]
        let centered = isCentertileLayout(m)
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
                            vertical isvertical: Bool) {
        if gc.isfullscreen || gc.ismaximizescreen { return }
        guard let m = gc.mon else { return }
        if m.isoverview { return }

        let tag = getClientTagIdx(gc)
        guard let st = m.pertag.scrollerState[tag] else { return }

        guard let curnode = findScrollerNode(st, gc) else { return }

        var headnode = curnode
        while let p = headnode.prevInStack { headnode = p }

        let stackHeadClient = headnode.client

        var deltaX: Float, deltaY: Float
        var newScrollerProportion: Float
        var newStackProportion: Float
        var offsetx = Int32(offsetX), offsety = Int32(offsetY)

        if !startDragWindow && isdrag {
            dragBeginCursor = cursor   // not in mango: the port's cursor
            startDragWindow = true

            headnode.client.oldScrollerPproportion = Double(headnode.scrollerProportion)
            gc.scrollerOldStackProportion = curnode.scrollerStackProportion

            gc.cursorInLeftHalf = cursor.x < gc.geom.minX + (gc.geom.width / 2).rounded(.towardZero)
            gc.cursorInUpperHalf = cursor.y < gc.geom.minY + (gc.geom.height / 2).rounded(.towardZero)
            gc.dragBeginGeom = gc.geom
        } else {
            if isdrag {
                offsetx = Int32(cursor.x - dragBeginCursor.x)
                offsety = Int32(cursor.y - dragBeginCursor.y)
            } else {
                gc.oldMasterMfactPer = gc.masterMfactPer
                gc.oldMasterInnerPer = gc.masterInnerPer
                gc.oldStackInnerPer = gc.stackInnerPer
                gc.dragBeginGeom = gc.geom
                stackHeadClient.oldScrollerPproportion = Double(headnode.scrollerProportion)
                gc.scrollerOldStackProportion = curnode.scrollerStackProportion
                gc.cursorInUpperHalf = false
                gc.cursorInLeftHalf = false
            }

            if isvertical {
                deltaY = Float(Double(offsety) * headnode.client.oldScrollerPproportion / Double(Int32(gc.dragBeginGeom.height)))
                deltaX = Float(offsetx) * gc.scrollerOldStackProportion / Float(Int32(gc.dragBeginGeom.width))
            } else {
                deltaX = Float(Double(offsetx) * headnode.client.oldScrollerPproportion / Double(Int32(gc.dragBeginGeom.width)))
                deltaY = Float(offsety) * gc.scrollerOldStackProportion / Float(Int32(gc.dragBeginGeom.height))
            }

            let movingUp: Bool, movingDown: Bool, movingLeft: Bool, movingRight: Bool
            if !isdrag {
                movingUp = offsety < 0
                movingDown = offsety > 0
                movingLeft = offsetx < 0
                movingRight = offsetx > 0
            } else {
                movingUp = cursor.y < dragBeginCursor.y
                movingDown = cursor.y > dragBeginCursor.y
                movingLeft = cursor.x < dragBeginCursor.x
                movingRight = cursor.x > dragBeginCursor.x
            }

            if (gc.cursorInUpperHalf && movingUp) || (!gc.cursorInUpperHalf && movingDown) {
                deltaY = abs(deltaY)
            } else {
                deltaY = -abs(deltaY)
            }

            if (gc.cursorInLeftHalf && movingLeft) || (!gc.cursorInLeftHalf && movingRight) {
                deltaX = abs(deltaX)
            } else {
                deltaX = -abs(deltaX)
            }

            if isvertical {
                if curnode.nextInStack == nil && curnode.prevInStack != nil && !isdrag {
                    deltaX = deltaX * -1.0
                }
                if curnode.nextInStack == nil && curnode.prevInStack != nil && isdrag {
                    if movingRight { deltaX = -abs(deltaX) } else { deltaX = abs(deltaX) }
                }
                if curnode.prevInStack == nil && curnode.nextInStack != nil && isdrag {
                    if movingLeft { deltaX = -abs(deltaX) } else { deltaX = abs(deltaX) }
                }
                if isdrag {
                    if movingUp { deltaY = -abs(deltaY) } else { deltaY = abs(deltaY) }
                }
            } else {
                if curnode.nextInStack == nil && curnode.prevInStack != nil && !isdrag {
                    deltaY = deltaY * -1.0
                }
                if curnode.nextInStack == nil && curnode.prevInStack != nil && isdrag {
                    if movingDown { deltaY = -abs(deltaY) } else { deltaY = abs(deltaY) }
                }
                if curnode.prevInStack == nil && curnode.nextInStack != nil && isdrag {
                    if movingUp { deltaY = -abs(deltaY) } else { deltaY = abs(deltaY) }
                }
                if isdrag {
                    if movingLeft { deltaX = -abs(deltaX) } else { deltaX = abs(deltaX) }
                }
            }

            if isvertical {
                newScrollerProportion = Float(headnode.client.oldScrollerPproportion + Double(deltaY))
                newStackProportion = gc.scrollerOldStackProportion + deltaX
            } else {
                newScrollerProportion = Float(headnode.client.oldScrollerPproportion + Double(deltaX))
                newStackProportion = gc.scrollerOldStackProportion + deltaY
            }

            newScrollerProportion = max(0.1, min(1.0, newScrollerProportion))
            newStackProportion = max(0.1, min(0.9, newStackProportion))

            // Keeps the sum at 1 so later arrange normalization does not swallow
            // the offset.
            if isdrag {
                let currentOtherSum: Float = 1.0 - curnode.scrollerStackProportion
                let newOtherSum: Float = 1.0 - newStackProportion
                if currentOtherSum > 0.001 {
                    let scale = newOtherSum / currentOtherSum
                    var tc: ScrollerStackNode? = headnode
                    while let n = tc {
                        if n !== curnode { n.scrollerStackProportion *= scale }
                        tc = n.nextInStack
                    }
                }
            } else {
                // Keyboard stepping.
                if gc.scrollerOldStackProportion != 1.0 {
                    var tc: ScrollerStackNode? = headnode
                    while let n = tc {
                        if n !== curnode {
                            n.scrollerStackProportion = (1.0 - newStackProportion)
                                / (1.0 - gc.scrollerOldStackProportion) * n.scrollerStackProportion
                        }
                        tc = n.nextInStack
                    }
                }
            }

            curnode.scrollerStackProportion = newStackProportion

            if m.visibleScrollTilingClients > 1 || config.scrollerIgnoreProportionSingle {
                headnode.scrollerProportion = newScrollerProportion
            }

            var stnode: ScrollerStackNode? = headnode
            while let n = stnode {
                n.scrollerStackWeight = n.scrollerStackProportion
                stnode = n.nextInStack
            }

            /* Syncs back to the global fields. */
            syncScrollerStateToClients(m, tag)

            arrange(m, false, false)
        }
    }

    func resizeTileDwindle(_ gc: Client, isdrag: Bool, offsetX: CGFloat, offsetY: CGFloat, cursor: CGPoint) {
        guard let m = gc.mon else { return }
        if !isdrag {
            dwindleResizeClientStep(m, gc, Int32(offsetX), Int32(offsetY))
            return
        }

        dwindleResizeClient(m, gc)
    }

    func dwindleSetSplitDirection(_ c: Client, _ istoggle: Bool, _ horizontal: Bool) {
        guard let m = c.mon else { return }
        let tag = getClientTagIdx(c)
        if m.pertag.ltidxs[tag] != .dwindle { return }

        guard let leaf = dwindleFindLeaf(m.pertag.dwindleRoot[tag], c) else { return }

        if istoggle {
            leaf.customLeafSplitH = !leaf.customLeafSplitH
        } else if horizontal {
            leaf.customLeafSplitH = true
        } else {
            leaf.customLeafSplitH = false
        }
        updateBorders()   // not in mango: client_draw_split_border; the port draws the split in the border's overlay
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





    func focusStack(_ dir: NextPrev, from target: Client? = nil) {
        guard let sel = target ?? clientFocusTop(selectedMonitor),
              let tc = getNextStackClient(sel, reverse: dir == .prev) else { return }
        clientFocus(tc, true)
        if config.warpcursor { pointerWarpToClient(tc) }
    }


    func focusDirection(_ dir: Direction) {
        let m = selectedMonitor!
        // not in mango: not in the overview, whose cards are no monocle (a mango bug, docs/afvigelser.md §6)
        if isMonocleLayout(m), !m.isoverview, let sel = focused, !sel.isfloating, dir.isHorizontal {
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
            } else if config.focusCrossMonitor, let target = monitorFromDirection(dir) {
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


    /// Not in mango: c->geom, or the card in the overview's pictures.
    func directionGeom(_ c: Client) -> CGRect {
        if let m = c.mon, m.isoverview, let card = m.ovCards[c.id] { return card }
        return c.geom
    }






    func parseMonitorArg(_ arg: String) -> Monitor? {
        if let dir = Direction(mangoName: arg) { return monitorFromDirection(dir) }
        switch arg.lowercased() {
        case "next": return monitorFromCycle(MON_NEXT)
        case "prev": return monitorFromCycle(MON_PREV)
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





    func tagMonitor(_ c: Client, to m: Monitor, newtags: UInt32) {
        guard c.mon != nil else { return }
        if c.mon === m {
            clientViewOnMonitor(newtags, on: selectedMonitor, changeFocus: true)
            return
        }

        if !clientSetMonitorAdapted(c, m, newtags, focus: true) { return }

        setSelectedMonitor(c.mon)
        let target = getTagsFirstTag(c.tags)

        clientViewOnMonitor(target, on: selectedMonitor, changeFocus: true)
        clientFocus(c, true)
        if c.isfloating {
            resize(c, c.geom, ResizeOpts(interact: true))
        } else {
            arrange(selectedMonitor, false, false)
        }
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

}

private func < (a: (CGFloat, CGFloat), b: (CGFloat, CGFloat)) -> Bool {
    a.0 != b.0 ? a.0 < b.0 : a.1 < b.1
}
