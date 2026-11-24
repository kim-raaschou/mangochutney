import Foundation
import CoreGraphics

package extension MangoServer {
    func setEnvWithoutDisplay() {
        for (type, value) in config.envVars {
            if type == "DISPLAY" {
                continue // Skip setting DISPLAY
            }
            setenv(type, value, 1)
        }
    }

    func setEnvDisplay() {
        for (type, value) in config.envVars {
            if type == "DISPLAY" {
                setenv("DISPLAY", value, 1)
            }
        }
    }

    func runExec() {
        for cmd in config.exec {
            _ = spawnShell(Arg(v: cmd))
        }
    }

    func runExecOnce() {
        for cmd in config.execOnce {
            _ = spawnShell(Arg(v: cmd))
        }
    }

    // not in mango: apply_explicit_xcursor_env and set_xcursor_env: macOS draws the cursor, and no
    // macOS app reads XCURSOR_SIZE or XCURSOR_THEME (MangoCompat)

    func reapplyProperty() {
        // reset border width when config change
        for c in clients {
            if !c.iskilling {
                if !c.noBorder && !c.isfullscreen {
                    c.bw = CGFloat(config.borderpx)
                }
                clientSetGroupConfig(c)
                // not in mango: no client_set_tab_bar_config, the port draws the tab bar from the config
            }
        }
    }

    func reapplyTagrule() {
        for m in monitors {
            parseTagrule(m)
        }
    }

    func resetOption() {
        initBakedPoints()
        pointerCursorActivity()
        resetKeyboardLayout()
        // not in mango: no reset_blur_params, macOS has no blur (MangoCompat)
        setEnvWithoutDisplay()
        setEnvDisplay()
        runExec()

        reapplyCursorStyle()
        reapplyProperty()
        // not in mango: no reapply_rootbg, the port reads rootcolor where it draws
        // not in mango: no reapply_keyboard, key repeat is macOS's (MangoCompat)
        system.watchGestures(!config.gestureBindings.isEmpty)   // not in mango: the port's side, where reapply_pointer stands
        reapplyMaster()

        reapplyTagrule()
        // not in mango: no reapply_monitor_rules, monitor_rule is macOS's (MangoCompat)

        // Port extension: not in mango. The port takes its own options.
        for loaded in portHooks.configLoaded { loaded(self) }
        publishInputState()   // not in mango: the event tap's snapshot

        /* A global reload must re-apply every monitor, not just the selected one:
         * layout-affecting options such as always_show_group_bar reserve or release
         * space on all outputs. */
        for m in monitors {
            titleMessageBarApplyConfig(m)
            titleMessageBarUpdate(m)
            arrange(m, false, false)
        }
    }

    func reapplyCursorStyle() {
        // not in mango: no xcursor manager and no new timer, macOS draws the cursor (MangoCompat)
        if !cursorHidden {
            hideCursorSource?.timerUpdate(Int32(config.cursorHideTimeout * 1000))
        }
    }

    func reapplyMaster() {
        for i in 0..<PERTAG_SLOTS {
            for m in monitors {
                m.pertag.nmasters[i] = Int32(config.defaultNmaster)
                m.pertag.mfacts[i] = config.defaultMfact
                m.gappih = Int32(config.gappih)
                m.gappiv = Int32(config.gappiv)
                m.gappoh = Int32(config.gappoh)
                m.gappov = Int32(config.gappov)
                m.specialGappih = Int32(config.specialGappih)
                m.specialGappiv = Int32(config.specialGappiv)
                m.specialGappoh = Int32(config.specialGappoh)
                m.specialGappov = Int32(config.specialGappov)
            }
        }
    }

    // Reset a pertag slot to defaults.
    func tagSlotSetDefaults(_ m: Monitor, _ tag: UInt32) {
        m.pertag.nmasters[tag] = Int32(config.defaultNmaster)
        m.pertag.mfacts[tag] = config.defaultMfact
        m.pertag.configLtidxs[tag] = .tile
        m.pertag.scrollerDefaultProportion[tag] = config.scrollerDefaultProportion
        m.pertag.scrollerDefaultProportionSingle[tag] = config.scrollerDefaultProportionSingle
        m.pertag.scrollerIgnoreProportionSingle[tag] = config.scrollerIgnoreProportionSingle
    }

    // Does this tag rule match the monitor?
    func tagRuleMatchesMonitor(_ tr: ConfigTagRule, _ m: Monitor) -> Bool {
        if let monitorName = tr.monitorName, !regexMatch(monitorName, m.screen.name) {
            return false
        }
        if let monitorMake = tr.monitorMake, m.screen.make == nil || monitorMake != m.screen.make {
            return false
        }
        if let monitorModel = tr.monitorModel, m.screen.model == nil || monitorModel != m.screen.model {
            return false
        }
        if let monitorSerial = tr.monitorSerial, m.screen.serial == nil || monitorSerial != m.screen.serial {
            return false
        }
        return true
    }

    // Apply one tag rule to a slot (caller checks coverage).
    func tagRuleApplyToSlot(_ m: Monitor, _ tr: ConfigTagRule, _ tag: UInt32) {
        for layout in LayoutKind.allCases {
            if let layoutName = tr.layoutName, layout.name == layoutName {
                m.pertag.configLtidxs[tag] = layout
            }
        }

        m.pertag.noHide[tag] = tr.noHide
        if let nmaster = tr.nmaster, nmaster >= 1 {
            m.pertag.nmasters[tag] = Int32(nmaster)
        }
        if let mfact = tr.mfact, mfact > 0.0 {
            m.pertag.mfacts[tag] = Float(mfact)
        }
        m.pertag.noRenderBorder[tag] = tr.noRenderBorder
        m.pertag.openAsFloating[tag] = tr.openAsFloating
        if tr.scrollerDefaultProportion > 0.0 {
            m.pertag.scrollerDefaultProportion[tag] = Float(tr.scrollerDefaultProportion)
        }
        if tr.scrollerDefaultProportionSingle > 0.0 {
            m.pertag.scrollerDefaultProportionSingle[tag] = Float(tr.scrollerDefaultProportionSingle)
        }
        if let v = tr.scrollerIgnoreProportionSingle {
            m.pertag.scrollerIgnoreProportionSingle[tag] = v
        }
    }

    func parseTagrule(_ m: Monitor) {
        let prevConfigLtidxs = m.pertag.configLtidxs

        // Set defaults for every tag.
        for i in 0...UInt32(config.tagNum) {
            tagSlotSetDefaults(m, i)
        }

        for tr in config.tagRules {
            if tagRuleMatchesMonitor(tr, m) && (tr.id == nil || tr.id! <= config.tagNum) {
                let tagIdStart = tr.id ?? 0
                let tagIdEnd = tr.id ?? config.tagNum

                for ti in tagIdStart...tagIdEnd {
                    tagRuleApplyToSlot(m, tr, UInt32(ti))
                }
            }
        }

        for i in 0...config.tagNum {
            if prevConfigLtidxs[i] != m.pertag.configLtidxs[i] {
                m.pertag.ltidxs[i] = m.pertag.configLtidxs[i]
            }
        }

        for i in 1...UInt32(config.tagNum) {
            for c in clients {
                if (c.tags & (1 << (i - 1)) & TAGMASK) != 0 && ISTILED(c) {
                    // not in mango: this monitor's windows only; mango's gives every window the last monitor's mfact (a mango bug, docs/afvigelser.md §6).
                    guard c.mon === m else { continue }
                    if m.pertag.mfacts[i] > 0.0 {
                        c.masterMfactPer = CGFloat(m.pertag.mfacts[i])
                    }
                }
            }
        }
    }

    func resetTag(_ oldTagNum: Int) {
        if config.tagNum != oldTagNum {
            let lastTagMask: UInt32 = 1 << UInt32(config.tagNum - 1)

            for c in clients {
                if c.tags & ~tagmask != 0 {
                    c.tags = lastTagMask
                    c.oldtags = lastTagMask
                }
            }

            for m in monitors {
                m.tagset[0] &= tagmask
                m.tagset[1] &= tagmask
                if m.tagset[m.seltags] == 0 {
                    m.tagset[m.seltags] = lastTagMask
                }
                if m.pertag.curtag > UInt32(config.tagNum) {
                    m.pertag.curtag = UInt32(config.tagNum)
                }
                if m.pertag.prevtag > UInt32(config.tagNum) {
                    m.pertag.prevtag = UInt32(config.tagNum)
                }
                // not in mango: no sync_workspaces_to_tag_num, macOS has no ext-workspace
            }
        }
    }

    @discardableResult
    func reloadConfig(_ arg: Arg?) -> Int32 {
        let oldTagNum = config.tagNum
        parseConfig()
        resetTag(oldTagNum)
        resetOption()
        // not in mango: no update_seat_capabilities and apply_primary_selection, the seat is macOS's
        printstatus(.arrangge)
        configWatcherUpdate()
        return 1
    }
}
