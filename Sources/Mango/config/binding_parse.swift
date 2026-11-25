import Foundation

// not in mango: parse_option's keyword parsers (option_defs.c) and binding_parse.c's, as one namespace
public enum BindingParser {}

// not in mango: reference_keymap, cleanup_config_keymap and create_config_keymap: xkb's keymap is the
// port's (ConfigPort.keyCodes)

extension BindingParser {
    // Parses the bind combination string.
    // not in mango: `error`, mango_error's message given to the caller; the flags as one set
    static func parseBindFlags(_ str: String, error: (String) -> Void = { _ in }) -> KeyBindingFlags {
        var kb: KeyBindingFlags = []
        // Checks whether it starts with "bind".
        if !str.hasPrefix("bind") {
            return kb
        }

        let suffix = str.dropFirst(4) // Skips "bind".

        // Walks the remaining suffix characters.
        for c in suffix {
            switch c {
            case "s":
                kb.insert(.keysym)
            case "l":
                kb.insert(.locked)
            case "r":
                kb.insert(.release)
            case "p":
                kb.insert(.passthrough)
            case "c":
                kb.insert(.allowConflict)
            case "n":
                kb.insert(.norepeat)
            default:
                error("Unknown bind flag: \(mangoHighlight(String(c)))")
            }
        }
        return kb
    }

    // not in mango: the mode alone; iscommonmode and isdefaultmode are the mode's "common" and "default"
    static func setBindingKeymode(_ config: Config) -> String {
        config.keymode
    }

    // not in mango: nil where mango returns UINT32_MAX; `error`, mango_error's message given to the caller
    package static func parseMod(_ modStr: String, error: (String) -> Void = { _ in }) -> Modifiers? {
        if modStr.isEmpty {
            return nil
        }

        var mod: Modifiers = []
        var matchSuccess = false

        // Copies and converts to lowercase.
        let inputCopy = String(decoding: modStr.utf8.prefix(255), as: UTF8.self).lowercased()

        // Splits and processes each part.
        for raw in inputCopy.split(separator: "+") {
            // Strips leading/trailing whitespace.
            let token = ValueParse.trimWhitespace(raw)

            // Skips tokens that became empty.
            if token.isEmpty {
                continue
            }

            if token.hasPrefix("code:") {
                // Handles the code: form.
                if let (keycode, rest) = ValueParse.strtol(token.dropFirst(5)), rest.isEmpty || rest.first == " " {
                    switch keycode {
                    case 133, 134:
                        mod.insert(.superKey)
                        matchSuccess = true
                    case 37, 105:
                        mod.insert(.ctrl)
                        matchSuccess = true
                    case 50, 62:
                        mod.insert(.shift)
                        matchSuccess = true
                    case 64, 108:
                        mod.insert(.alt)
                        matchSuccess = true
                    default:
                        error("unknown modifier keycode: \(mangoHighlight(token))")
                    }
                }
            } else {
                if token == "super" || token == "super_l" || token == "super_r" {
                    mod.insert(.superKey)
                    matchSuccess = true
                }
                if token == "ctrl" || token == "ctrl_l" || token == "ctrl_r" {
                    mod.insert(.ctrl)
                    matchSuccess = true
                }
                if token == "shift" || token == "shift_l" || token == "shift_r" {
                    mod.insert(.shift)
                    matchSuccess = true
                }
                if token == "alt" || token == "alt_l" || token == "alt_r" {
                    mod.insert(.alt)
                    matchSuccess = true
                }
                if token == "hyper" || token == "hyper_l" || token == "hyper_r" {
                    mod.insert(.hyper)
                    matchSuccess = true
                }
                if token == "none" {
                    matchSuccess = true
                }
                if let m = ConfigParser.port?.modifier(token) {   // the port's names: not in mango
                    mod.formUnion(m)
                    matchSuccess = true
                }
            }
        }

        if !matchSuccess {
            error("Unknown modifier: \(mangoHighlight(modStr))")
            return nil
        }

        return mod
    }
}

// not in mango: find_keycodes_in_layout and find_keycodes_for_keysym: xkb's keymap is the port's
// (ConfigPort.keyCodes, WindowSystem.findKeycodesForKeysym)

package extension MangoServer {
    func findKeycodesForChar(_ cChar: Character?, _ multiKc: inout MultiKeycode) {
        multiKc = MultiKeycode()

        guard let cChar else { return }

        multiKc = system.findKeycodesForKeysym(cChar)   // not in mango: the port's side (xkb's keymap)
    }
}

extension BindingParser {
    // not in mango: the key's macOS key codes from the port (xkb's keymap in mango), [] for a key
    // with no code (matched by keysym in mango, dropped here), nil for XKB_KEY_NoSymbol; `error`,
    // mango_error's message given to the caller (docs/afvigelser.md §3)
    static func parseKey(_ keyStr: String, _ isbindsym: Bool, error: (String) -> Void = { _ in }) -> [UInt16]? {
        let codes = ConfigParser.port?.keyCodes(keyStr) ?? []   // the boundary: xkb's keymap is the port's

        // Handles the code: prefix case.
        if keyStr.hasPrefix("code:") {
            return codes
        }

        if !codes.isEmpty || keyStr.lowercased().hasPrefix("xf86") {
            return codes
        }

        if !isbindsym {
            // Unparseable key name.
            error("Unknown key: \(mangoHighlight(keyStr))")
        }
        return nil
    }

    // not in mango: the button as MouseButton, nil where mango returns UINT32_MAX; `error`,
    // mango_error's message given to the caller
    static func parseButton(_ str: String, error: (String) -> Void = { _ in }) -> MouseButton? {
        // Converts the input string to lowercase.
        let lowerStr = String(decoding: str.utf8.prefix(19), as: UTF8.self).lowercased()

        // Parses the "code:number" format.
        if lowerStr.hasPrefix("code:") {
            // Checks that the conversion succeeded with no leftover characters and
            // no overflow (within uint32_t).
            guard let (val, rest) = ValueParse.strtoul(lowerStr.dropFirst(5)), rest.isEmpty,
                  val <= UInt64(UInt32.max) else {
                error("Invalid code format: \(mangoHighlight(str))")
                return nil
            }
            switch val {
            case 272: return .left
            case 273: return .right
            case 274: return .middle
            case 275: return .side
            case 276: return .extra
            case 277: return .forward
            case 278: return .back
            case 279: return .task
            default: return .code(Int(val))
            }
        }

        // Returns the matching button number from the lowercased string.
        if lowerStr == "btn_left" {
            return .left
        } else if lowerStr == "btn_right" {
            return .right
        } else if lowerStr == "btn_middle" {
            return .middle
        } else if lowerStr == "btn_side" {
            return .side
        } else if lowerStr == "btn_extra" {
            return .extra
        } else if lowerStr == "btn_forward" {
            return .forward
        } else if lowerStr == "btn_back" {
            return .back
        } else if lowerStr == "btn_task" {
            return .task
        } else {
            error("Unknown button: \(mangoHighlight(str))")
            return nil
        }
    }

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
        } else if funcName == "toggleworkspaceoverview" {
            `func` = MangoServer.toggleWorkspaceOverview(_:)
            arg.i2 = WORKSPACE_OVERVIEW_GRID
            if argValue == "scroll_occupied" {
                arg.i = OCCUPIED_WORKSPACE
                arg.i2 = WORKSPACE_OVERVIEW_SCROLL
            } else if argValue == "scroll_all" {
                arg.i = ALL_WORKSPACE
                arg.i2 = WORKSPACE_OVERVIEW_SCROLL
            } else {
                arg.i = argValue == "occupied" ? OCCUPIED_WORKSPACE : ALL_WORKSPACE
            }
        } else if funcName == "enterworkspaceoverview" {
            `func` = MangoServer.enterWorkspaceOverview(_:)
            arg.i2 = WORKSPACE_OVERVIEW_GRID
            if argValue == "scroll_occupied" {
                arg.i = OCCUPIED_WORKSPACE
                arg.i2 = WORKSPACE_OVERVIEW_SCROLL
            } else if argValue == "scroll_all" {
                arg.i = ALL_WORKSPACE
                arg.i2 = WORKSPACE_OVERVIEW_SCROLL
            } else {
                arg.i = argValue == "occupied" ? OCCUPIED_WORKSPACE : ALL_WORKSPACE
            }
        } else if funcName == "leaveworkspaceoverview" {
            `func` = MangoServer.leaveWorkspaceOverview(_:)
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
            arg.ui = ValueParse.parseTagMask(argValue)
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

            if !argValue2.isEmpty { nonEmptyParams.append(argValue2) }
            if !argValue3.isEmpty { nonEmptyParams.append(argValue3) }
            if !argValue4.isEmpty { nonEmptyParams.append(argValue4) }
            if !argValue5.isEmpty { nonEmptyParams.append(argValue5) }

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
            arg.ui = ValueParse.parseTagMask(argValue2)
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
            arg.ui = ValueParse.parseTagMask(argValue)
            arg.i = Int32(truncatingIfNeeded: ValueParse.atoi(argValue2))
        } else if funcName == "view" {
            `func` = MangoServer.bindToView(_:)
            arg.ui = ValueParse.parseTagMask(argValue)
            arg.i = Int32(truncatingIfNeeded: ValueParse.atoi(argValue2))
        } else if funcName == "viewcrossmon" {
            `func` = MangoServer.viewCrossMonitor(_:)
            arg.ui = ValueParse.parseTagMask(argValue)
            arg.v = argValue2
        } else if funcName == "tagcrossmon" {
            `func` = MangoServer.tagCrossMonitor(_:)
            arg.ui = ValueParse.parseTagMask(argValue)
            arg.v = argValue2
        } else if funcName == "toggletag" {
            `func` = MangoServer.toggleTag(_:)
            arg.ui = ValueParse.parseTagMask(argValue)
        } else if funcName == "toggleview" {
            `func` = MangoServer.toggleView(_:)
            arg.ui = ValueParse.parseTagMask(argValue)
        } else if funcName == "comboview" {
            `func` = MangoServer.comboView(_:)
            arg.ui = ValueParse.parseTagMask(argValue)
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
