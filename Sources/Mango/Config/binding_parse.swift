let NUM_TYPE_MINUS: UInt32 = 0, NUM_TYPE_PLUS: UInt32 = 1, NUM_TYPE_DEFAULT: UInt32 = 2

package extension MangoServer {
    func findKeycodesForChar(_ cChar: Character?, _ multiKc: inout MultiKeycode) {
        multiKc = MultiKeycode()

        guard let cChar else { return }

        multiKc = system.findKeycodesForKeysym(cChar)   // not in mango: the port's side (xkb's keymap)
    }
}

extension BindingParser {
    static func parseMouseAction(_ str: String) -> UInt32 {
        // Converts the input string to lowercase.
        let lowerStr = String(decoding: str.utf8.prefix(19), as: UTF8.self).lowercased()

        // Returns the matching button number from the lowercased string.
        if lowerStr == "curmove" {
            return CurMove
        } else if lowerStr == "curresize" {
            return CurResize
        } else if lowerStr == "curnormal" {
            return CurNormal
        } else if lowerStr == "curpressed" {
            return CurPressed
        } else {
            return 0
        }
    }

    // Helper: checks whether a string starts with the given prefix
    // (case-insensitive).
    static func combineArgsUntilEmpty(_ values: [String]) -> String {
        if values.isEmpty {
            return ""
        }

        // find the first empty string
        var firstEmpty = values.count
        for i in values.indices {
            // check if it's empty: empty string or only contains "0" (initialized)
            if values[i].isEmpty || values[i] == "0" {
                firstEmpty = i
                break
            }
        }

        // 	if there are no valid parameters, return an empty string
        if firstEmpty == 0 {
            return ""
        }

        return values[0..<firstEmpty].joined(separator: ",")
    }

    @MainActor
    static func parseFuncName(_ funcName: String, _ arg: inout Arg, _ argValue: String, _ argValue2: String,
                              _ argValue3: String, _ argValue4: String, _ argValue5: String) -> FuncType? {
        var `func`: FuncType?
        arg.i = 0
        arg.i2 = 0
        arg.f = 0.0
        arg.f2 = 0.0
        arg.ui = 0
        arg.ui2 = 0
        arg.v = nil
        arg.v2 = nil
        arg.v3 = nil

        if funcName == "focusstack" {
            `func` = MangoServer.focusStack(_:)
            arg.i = ValueParse.parseCircleDirection(argValue)
        } else if funcName == "overcircle" {
            `func` = MangoServer.overCircle(_:)
            arg.i = ValueParse.parseOvercircleDirection(argValue)
        } else if funcName == "groupfocus" {
            `func` = MangoServer.groupFocus(_:)
            arg.i = ValueParse.parseCircleDirection(argValue)
        } else if funcName == "focusdir" {
            `func` = MangoServer.focusDirection(_:)
            arg.i = ValueParse.parseDirection(argValue)
        } else if funcName == "focus_window_or_workspace" {
            `func` = MangoServer.focusWindowOrWorkspace(_:)
            arg.i = ValueParse.parseDirection(argValue)
        } else if funcName == "groupjoin" {
            `func` = MangoServer.groupJoin(_:)
            arg.i = ValueParse.parseDirection(argValue)
        } else if funcName == "groupleave" {
            `func` = MangoServer.groupLeave(_:)
        } else if funcName == "focusid" {
            `func` = MangoServer.focusById(_:)
        } else if funcName == "incnmaster" {
            `func` = MangoServer.incNmaster(_:)
            arg.i = Int32(truncatingIfNeeded: ValueParse.atoi(argValue))
        } else if funcName == "setmfact" {
            `func` = MangoServer.setMasterFactor(_:)
            arg.f = Float(ValueParse.atof(argValue))
        } else if funcName == "zoom" {
            `func` = MangoServer.zoom(_:)
        } else if funcName == "exchange_client" {
            `func` = MangoServer.exchangeClient(_:)
            arg.i = ValueParse.parseDirection(argValue)
        } else if funcName == "move_client" {
            `func` = MangoServer.moveClient(_:)
            arg.i = ValueParse.parseDirection(argValue)
        } else if funcName == "exchange_stack_client" {
            `func` = MangoServer.exchangeStackClient(_:)
            arg.i = ValueParse.parseCircleDirection(argValue)
        } else if funcName == "toggleglobal" {
            `func` = MangoServer.toggleGlobal(_:)
        } else if funcName == "togglehdr" {
            /* togglehdr[,on|off|toggle][,<monitor name>|all] */
            `func` = MangoServer.toggleHdr(_:)
            if argValue == "on" {
                arg.i = 1
            } else if argValue == "off" {
                arg.i = 0
            } else {
                arg.i = -1 // toggle, and the default for an empty argument
            }
            // "not given" is "" from the IPC path and "0" from the keybinding
            // parser -- same rule as combine_args_until_empty().
            let hasName = !argValue2.isEmpty && argValue2 != "0"
            arg.v = hasName ? argValue2 : nil
        } else if funcName == "toggleoverview" {
            `func` = MangoServer.toggleOverview(_:)
            arg.i = ValueParse.atoi(argValue) == 1 ? 1 : 0
        } else if funcName == "enteroverview" {
            `func` = MangoServer.enterOverview(_:)
        } else if funcName == "leaveoverview" {
            `func` = MangoServer.leaveOverview(_:)
        } else if funcName == "togglejump" {
            `func` = MangoServer.toggleJump(_:)
        } else if funcName == "set_proportion" {
            `func` = MangoServer.setProportion(_:)
            arg.f = Float(ValueParse.atof(argValue))
        } else if funcName == "switch_proportion_preset" {
            `func` = MangoServer.switchProportionPreset(_:)
            arg.i = ValueParse.parseCircleDirection(argValue)
        } else if funcName == "viewtoleft" {
            `func` = MangoServer.viewToLeft(_:)
            arg.i = Int32(truncatingIfNeeded: ValueParse.atoi(argValue))
        } else if funcName == "viewtoright" {
            `func` = MangoServer.viewToRight(_:)
            arg.i = Int32(truncatingIfNeeded: ValueParse.atoi(argValue))
        } else if funcName == "view_insert" {
            `func` = MangoServer.viewInsert(_:)
            arg.i = argValue == "next" ? NEXT : PREV
        } else if funcName == "tagsilent" {
            `func` = MangoServer.tagSilent(_:)
            arg.ui = TagMask.parseTagMask(argValue)
        } else if funcName == "tagtoleft" {
            `func` = MangoServer.tagToLeft(_:)
            arg.i = Int32(truncatingIfNeeded: ValueParse.atoi(argValue))
        } else if funcName == "tagtoright" {
            `func` = MangoServer.tagToRight(_:)
            arg.i = Int32(truncatingIfNeeded: ValueParse.atoi(argValue))
        } else if funcName == "killclient" {
            `func` = MangoServer.killClient(_:)
            arg.i = ValueParse.parseForce(argValue)
        } else if funcName == "smartkillclient" {
            `func` = MangoServer.smartKillClient(_:)
        } else if funcName == "centerwin" {
            `func` = MangoServer.centerWindow(_:)
        } else if funcName == "focuslast" {
            `func` = MangoServer.focusLast(_:)
        } else if funcName == "switcher" {
            `func` = MangoServer.switcher(_:)
            if argValue == "all_next" {
                arg.i = NEXT
                arg.i2 = SW_ALL_MON
            } else if argValue == "all_prev" {
                arg.i = PREV
                arg.i2 = SW_ALL_MON
            } else if argValue == "all_tag_next" {
                arg.i = NEXT
                arg.i2 = SW_ALL_TAG
            } else if argValue == "all_tag_prev" {
                arg.i = PREV
                arg.i2 = SW_ALL_TAG
            } else if argValue == "prev" {
                arg.i = PREV
                arg.i2 = SW_CURRENT_TAG
            } else {
                arg.i = NEXT
                arg.i2 = SW_CURRENT_TAG
            }
        } else if funcName == "toggle_trackpad_enable" {
            `func` = MangoServer.toggleTrackpadEnable(_:)
        } else if funcName == "setoption" {
            `func` = MangoServer.setoption(_:)

            arg.v = argValue

            // Collects the parameters to concatenate.
            var nonEmptyParams: [String] = []

            // not in mango: a binding's "0" (not given) after the value is skipped too, as in
            // combine_args_until_empty (a mango bug, docs/afvigelser.md §6)
            if !argValue2.isEmpty { nonEmptyParams.append(argValue2) }
            if !argValue3.isEmpty && argValue3 != "0" { nonEmptyParams.append(argValue3) }
            if !argValue4.isEmpty && argValue4 != "0" { nonEmptyParams.append(argValue4) }
            if !argValue5.isEmpty && argValue5 != "0" { nonEmptyParams.append(argValue5) }

            // Handles concatenation.
            arg.v2 = nonEmptyParams.joined(separator: ",")
        } else if funcName == "setkeymode" {
            `func` = MangoServer.setKeyMode(_:)
            arg.v = argValue
        } else if funcName == "switch_keyboard_layout" {
            `func` = MangoServer.switchKeyboardLayout(_:)
            arg.i = Int32(min(max(ValueParse.atoi(argValue), 0), 100))
        } else if funcName == "setlayout" {
            `func` = MangoServer.setLayout(_:)
            arg.v = argValue
        } else if funcName == "switch_layout" {
            `func` = MangoServer.switchLayout(_:)
        } else if funcName == "togglefloating" {
            `func` = MangoServer.toggleFloating(_:)
        } else if funcName == "togglefullscreen" {
            `func` = MangoServer.toggleFullscreen(_:)
        } else if funcName == "togglefakefullscreen" {
            `func` = MangoServer.toggleFakeFullscreen(_:)
        } else if funcName == "toggleoverlay" {
            `func` = MangoServer.toggleOverlay(_:)
        } else if funcName == "minimized" {
            `func` = MangoServer.minimizeWindow(_:)
        } else if funcName == "restore_minimized" {
            `func` = MangoServer.restoreMinimized(_:)
        } else if funcName == "toggle_scratchpad" {
            `func` = MangoServer.toggleScratchpad(_:)
        } else if funcName == "toggle_render_border" {
            `func` = MangoServer.toggleRenderBorder(_:)
        } else if funcName == "focusmon" {
            `func` = MangoServer.focusMonitor(_:)
            arg.i = ValueParse.parseMonitorArg(argValue)
            if arg.i == UNDIR {
                arg.v = argValue
            }
        } else if funcName == "tagmon" {
            `func` = MangoServer.tagMonitor(_:)
            arg.i = ValueParse.parseMonitorArg(argValue)
            arg.i2 = Int32(truncatingIfNeeded: ValueParse.atoi(argValue2))
            if arg.i == UNDIR {
                arg.v = argValue
            }
        } else if funcName == "incgaps" {
            `func` = MangoServer.increaseGaps(_:)
            arg.i = Int32(truncatingIfNeeded: ValueParse.atoi(argValue))
        } else if funcName == "togglegaps" {
            `func` = MangoServer.toggleGaps(_:)
        } else if funcName == "togglegroupbar" {
            `func` = MangoServer.toggleGroupBar(_:)
        } else if funcName == "chvt" {
            `func` = MangoServer.changeVt(_:)
            arg.ui = UInt32(truncatingIfNeeded: ValueParse.atoi(argValue))
        } else if funcName == "spawn" {
            `func` = MangoServer.spawn(_:)
            let values = [argValue, argValue2, argValue3, argValue4, argValue5]
            arg.v = combineArgsUntilEmpty(values)
        } else if funcName == "spawn_shell" {
            `func` = MangoServer.spawnShell(_:)
            let values = [argValue, argValue2, argValue3, argValue4, argValue5]
            arg.v = combineArgsUntilEmpty(values)
        } else if funcName == "spawn_on_empty" {
            `func` = MangoServer.spawnOnEmpty(_:)
            arg.v = argValue
            arg.ui = TagMask.parseTagMask(argValue2)
        } else if funcName == "quit" {
            `func` = MangoServer.quit(_:)
        } else if funcName == "create_virtual_output" {
            `func` = MangoServer.createVirtualOutput(_:)
            if !argValue.isEmpty {
                arg.v = argValue
            }
        } else if funcName == "destroy_all_virtual_output" {
            `func` = MangoServer.destroyAllVirtualOutput(_:)
        } else if funcName == "moveresize" {
            `func` = MangoServer.moveResize(_:)
            arg.ui = parseMouseAction(argValue)
        } else if funcName == "togglemaximizescreen" {
            `func` = MangoServer.toggleMaximizeScreen(_:)
        } else if funcName == "viewprev_have_client" {
            `func` = MangoServer.viewprevHaveClient(_:)
            arg.i = Int32(truncatingIfNeeded: ValueParse.atoi(argValue))
        } else if funcName == "viewnext_have_client" {
            `func` = MangoServer.viewnextHaveClient(_:)
            arg.i = Int32(truncatingIfNeeded: ValueParse.atoi(argValue))
        } else if funcName == "viewtoleft_have_client" {
            `func` = MangoServer.viewToLeftHaveClient(_:)
            arg.i = Int32(truncatingIfNeeded: ValueParse.atoi(argValue))
        } else if funcName == "viewtoright_have_client" {
            `func` = MangoServer.viewToRightHaveClient(_:)
            arg.i = Int32(truncatingIfNeeded: ValueParse.atoi(argValue))
        } else if funcName == "reload_config" {
            `func` = MangoServer.reloadConfig(_:)
        } else if funcName == "load_config_file" {
            `func` = MangoServer.loadConfigFile(_:)
            arg.v = argValue
        } else if funcName == "tag" {
            `func` = MangoServer.tag(_:)
            arg.ui = TagMask.parseTagMask(argValue)
            arg.i = Int32(truncatingIfNeeded: ValueParse.atoi(argValue2))
        } else if funcName == "view" {
            `func` = MangoServer.bindToView(_:)
            arg.ui = TagMask.parseTagMask(argValue)
            arg.i = Int32(truncatingIfNeeded: ValueParse.atoi(argValue2))
        } else if funcName == "viewcrossmon" {
            `func` = MangoServer.viewCrossMonitor(_:)
            arg.ui = TagMask.parseTagMask(argValue)
            arg.v = argValue2
        } else if funcName == "tagcrossmon" {
            `func` = MangoServer.tagCrossMonitor(_:)
            arg.ui = TagMask.parseTagMask(argValue)
            arg.v = argValue2
        } else if funcName == "toggletag" {
            `func` = MangoServer.toggleTag(_:)
            arg.ui = TagMask.parseTagMask(argValue)
        } else if funcName == "toggleview" {
            `func` = MangoServer.toggleView(_:)
            arg.ui = TagMask.parseTagMask(argValue)
        } else if funcName == "comboview" {
            `func` = MangoServer.comboView(_:)
            arg.ui = TagMask.parseTagMask(argValue)
        } else if funcName == "smartmovewin" {
            `func` = MangoServer.smartMoveWindow(_:)
            arg.i = ValueParse.parseDirection(argValue)
        } else if funcName == "smartresizewin" {
            `func` = MangoServer.smartResizeWindow(_:)
            arg.i = ValueParse.parseDirection(argValue)
        } else if funcName == "resizewin" {
            `func` = MangoServer.resizeWindow(_:)
            arg.ui = ValueParse.parseNumType(argValue)
            arg.ui2 = ValueParse.parseNumType(argValue2)
            arg.i = Int32(truncatingIfNeeded: arg.ui == NUM_TYPE_DEFAULT ? ValueParse.atoi(argValue)
                                                                         : ValueParse.atoi(String(argValue.dropFirst())))
            arg.i2 = Int32(truncatingIfNeeded: arg.ui2 == NUM_TYPE_DEFAULT ? ValueParse.atoi(argValue2)
                                                                           : ValueParse.atoi(String(argValue2.dropFirst())))
        } else if funcName == "movewin" {
            `func` = MangoServer.moveWindow(_:)
            arg.ui = ValueParse.parseNumType(argValue)
            arg.ui2 = ValueParse.parseNumType(argValue2)
            arg.i = Int32(truncatingIfNeeded: arg.ui == NUM_TYPE_DEFAULT ? ValueParse.atoi(argValue)
                                                                         : ValueParse.atoi(String(argValue.dropFirst())))
            arg.i2 = Int32(truncatingIfNeeded: arg.ui2 == NUM_TYPE_DEFAULT ? ValueParse.atoi(argValue2)
                                                                           : ValueParse.atoi(String(argValue2.dropFirst())))
        } else if funcName == "toggle_named_scratchpad" {
            `func` = MangoServer.toggleNamedScratchpad(_:)
            arg.v = argValue
            arg.v2 = argValue2
            arg.v3 = argValue3
        } else if funcName == "toggle_special_tag" {
            `func` = MangoServer.toggleSpecialTag(_:)
        } else if funcName == "tag_special_tag" {
            `func` = MangoServer.tagSpecialTag(_:)
        } else if funcName == "tag_special_silent" {
            `func` = MangoServer.tagSpecialSilent(_:)
        } else if funcName == "disable_monitor" {
            `func` = MangoServer.disableMonitor(_:)
            arg.v = argValue
        } else if funcName == "enable_monitor" {
            `func` = MangoServer.enableMonitor(_:)
            arg.v = argValue
        } else if funcName == "toggle_monitor" {
            `func` = MangoServer.toggleMonitor(_:)
            arg.v = argValue
        } else if funcName == "sleep_monitor" {
            `func` = MangoServer.sleepMonitor(_:)
            arg.v = argValue
        } else if funcName == "wakeup_monitor" {
            `func` = MangoServer.wakeupMonitor(_:)
            arg.v = argValue
        } else if funcName == "sleep_toggle_monitor" {
            `func` = MangoServer.sleepToggleMonitor(_:)
            arg.v = argValue
        } else if funcName == "scroller_stack" {
            `func` = MangoServer.scrollerStack(_:)
            arg.i = ValueParse.parseDirection(argValue)
        } else if funcName == "toggle_all_floating" {
            `func` = MangoServer.toggleAllFloating(_:)
        } else if funcName == "dwindle_toggle_split_direction" {
            `func` = MangoServer.dwindleToggleSplitDirection(_:)
        } else if funcName == "dwindle_split_horizontal" {
            `func` = MangoServer.dwindleSplitHorizontal(_:)
        } else if funcName == "dwindle_split_vertical" {
            `func` = MangoServer.dwindleSplitVertical(_:)
        } else if funcName == "dwindle_toggle_current_split" {
            `func` = MangoServer.dwindleToggleCurrentSplit(_:)
        } else {
            return nil
        }
        return `func`
    }
}
