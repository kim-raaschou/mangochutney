import Foundation

extension ParserState {
    // not in mango: wlroots' modifier bits, which a binding's mod is in mango
    private static func wlrModifiers(_ m: Modifiers) -> Int {
        (m.contains(.shift) ? 1 : 0) | (m.contains(.ctrl) ? 4 : 0) | (m.contains(.alt) ? 8 : 0)
            | (m.contains(.hyper) ? 32 : 0) | (m.contains(.superKey) ? 64 : 0) | (m.contains(.fn) ? 256 : 0)
    }

    // not in mango: a binding's first macOS key code stands for its keysym and its keycode1 (docs/afvigelser.md §3)
    static func compareKeybindByKeyOnly(_ ka: KeyBinding, _ kb: KeyBinding) -> Int {
        let amod = wlrModifiers(ka.mods), bmod = wlrModifiers(kb.mods)
        if amod != bmod {
            return amod > bmod ? 1 : -1
        }

        let atype = ka.flags.contains(.keysym) ? KEY_TYPE_SYM : KEY_TYPE_CODE
        let btype = kb.flags.contains(.keysym) ? KEY_TYPE_SYM : KEY_TYPE_CODE
        if atype != btype {
            return atype > btype ? 1 : -1
        }

        let a = ka.keyCodes.first ?? 0, b = kb.keyCodes.first ?? 0
        if a != b {
            return a > b ? 1 : -1
        }
        return 0
    }

    static func sameKey(_ a: KeyBinding, _ b: KeyBinding) -> Bool {
        compareKeybindByKeyOnly(a, b) == 0
    }

    static func sameMousebindKey(_ ma: MouseBinding, _ mb: MouseBinding) -> Bool {
        ma.mods == mb.mods && ma.button == mb.button
    }

    static func sameAxisbindKey(_ aa: AxisBinding, _ ab: AxisBinding) -> Bool {
        aa.mods == ab.mods && (aa.dir == UInt32(ALLDIR) || ab.dir == UInt32(ALLDIR) || aa.dir == ab.dir)
    }

    static func sameSwitchbindKey(_ sa: SwitchBinding, _ sb: SwitchBinding) -> Bool {
        sa.switchAction.type == sb.switchAction.type &&
            sa.switchAction.state == sb.switchAction.state
    }

    static func sameGesturebindKey(_ ga: GestureBinding, _ gb: GestureBinding) -> Bool {
        ga.mods == gb.mods && ga.fingersCount == gb.fingersCount
            && (ga.motion == UInt32(ALLDIR) || gb.motion == UInt32(ALLDIR) || ga.motion == gb.motion)
    }

    // not in mango: get_mousebind_meta, get_axisbind_meta, get_switchbind_meta and get_gesturebind_meta are
    // the binding's mode and its place in keyLocs, mouseLocs, axisLocs, switchLocs and gestureLocs

    @discardableResult
    mutating func checkMouseBindingConflicts() -> Bool {
        checkSimpleBindingConflicts(config.mouseBindings, mouseLocs, Self.sameMousebindKey, \.mode, "mousebind")
    }

    @discardableResult
    mutating func checkAxisBindingConflicts() -> Bool {
        checkSimpleBindingConflicts(config.axisBindings, axisLocs, Self.sameAxisbindKey, \.mode, "axisbind")
    }

    @discardableResult
    mutating func checkSwitchBindingConflicts() -> Bool {
        checkSimpleBindingConflicts(config.switchBindings, switchLocs, Self.sameSwitchbindKey, \.mode, "switchbind")
    }

    @discardableResult
    mutating func checkKeyBindingConflicts() -> Bool {
        let n = config.keyBindings.count
        if n < 2 {
            return false
        }

        /* Copies user-defined bindings (line number > 0). */
        var binds: [(KeyBinding, BindingLocation)] = []
        for i in 0..<n where keyLocs[i].line > 0 {
            binds.append((config.keyBindings[i], keyLocs[i]))
        }
        if binds.count < 2 {
            return false
        }

        /* Sorts only by key so bindings with the same key are grouped together. */
        binds.sort { Self.compareKeybindByKeyOnly($0.0, $1.0) < 0 }

        var conflictFound = false

        var i = 0
        while i < binds.count {
            var j = i
            /* Finds all bindings with the same key (range [i, j)). */
            while j < binds.count && Self.sameKey(binds[i].0, binds[j].0) {
                j += 1
            }

            /* Detects conflicts inside that range. */
            for a in i..<j {
                for b in (a + 1)..<max(a + 1, j) {
                    let sameMode = binds[a].0.mode == binds[b].0.mode
                    let anyCommon = binds[a].0.mode == "common" || binds[b].0.mode == "common"
                    let allowConflict = binds[a].0.flags.contains(.allowConflict) && binds[b].0.flags.contains(.allowConflict)

                    if (sameMode || anyCommon) && !allowConflict {
                        conflictFound = true
                        reportBindingConflict("Key binding", anyCommon ? "common" : binds[a].0.mode, binds[a].1, binds[b].1)
                    }
                }
            }
            i = j /* Moves to the next key group. */
        }

        return conflictFound
    }

    // not in mango: the bindings with their places, and a key path to their mode, where mango
    // takes an array of elem_size and a get_meta function
    mutating func checkSimpleBindingConflicts<T>(_ arr: [T], _ locs: [BindingLocation], _ sameKey: (T, T) -> Bool,
                                                 _ mode: KeyPath<T, String>, _ kind: String) -> Bool {
        var conflictFound = false

        for i in arr.indices {
            for j in arr.indices where j > i {
                if !sameKey(arr[i], arr[j]) {
                    continue
                }

                let ma = arr[i][keyPath: mode], mb = arr[j][keyPath: mode]
                let sameMode = ma == mb
                let anyCommon = ma == "common" || mb == "common"
                if sameMode || anyCommon {
                    conflictFound = true
                    reportBindingConflict(kind, anyCommon ? "common" : ma, locs[i], locs[j])
                }
            }
        }
        return conflictFound
    }

    @discardableResult
    mutating func checkGestureBindingConflicts() -> Bool {
        checkSimpleBindingConflicts(config.gestureBindings, gestureLocs, Self.sameGesturebindKey, \.mode, "gesturebind")
    }

    // not in mango: the conflict's mango_error(false, WLR_INFO, …), kept with the later binding's place
    private mutating func reportBindingConflict(_ kind: String, _ mode: String, _ a: BindingLocation, _ b: BindingLocation) {
        configError("\(kind) conflict in keymode \(mode):\n"
                        + "  File \"\(a.file)\", line \(a.line)\n"
                        + "  File \"\(b.file)\", line \(b.line)",
                    verbosity: .info, file: b.file, line: b.line)
    }
}
