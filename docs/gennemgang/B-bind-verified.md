# B-bind verified: src/dispatch/bind.c (+ parse_func_name table)

Paths: mango = `~/sources/mango/src/dispatch/bind.c` unless named; ours = `Sources/Mango/Engine/Dispatch.swift` unless named.
Every `differs`/`missing` row of B-bind.md re-read on both sides (callers, callees, IPC, port, boundary).

## Findings

| finding (short) | mango file:line | ours file:line | verdict | kind | size | note |
|---|---|---|---|---|---|---|
| move_client: invalid direction skips the warp | 195-222 (warp at 219) | :53-67 (`guard ... Direction(mangoName:)` :54) | CONFIRMED | edge | S | mango: parse_direction -> UNDIR, find_client_by_direction finds nothing, client_jump_to_monitor refuses (monitor_move_direction != UNDIR), then `pointer_warp_to_client(c)` when warpcursor. Ours returns before the warp. `move_client,foo` + warpcursor=1: mango warps, ours nothing |
| focus_direction ignores arg->tc | 246-294 (direction_select(arg) :265, get_focused_stack_client(c, arg->tc) :277) | :15-17, focusDirection :1417 (`directionSelect(dir)` :1424, `getFocusedStackClient(sc, nil)` :1434) | CONFIRMED | behaviour | S | arg->tc is set only by IPC `client,<id>` (ipc.c:959). `mmsg dispatch focusdir,left client,<id>`: mango moves from <id>, ours from selmon->sel. The monocle shortcut uses `sel` in both (mango :251 too) |
| focus_window_or_workspace ignores arg->tc | 296-328 (:306-308) | :18-20, focusWindowOrWorkspace :1449 (:1452) | CONFIRMED | behaviour | S | same IPC scenario as focusdir |
| focus_monitor: tc, single monitor, spec fields | 483-523 | :38-40, parseMonitorArg :1603, focusMonitor :1615 | PARTLY | behaviour | S | (1) CONFIRMED: mango `c = arg->tc ? arg->tc : client_focus_top` (:512), ours always clientFocusTop (:1619). (2) REFUTED as a difference: ours returns the same monitor for next/prev with one monitor, but focusMonitor's `guard target !== selectedMonitor` (:1616) makes it a no-op, as mango's NULL is. (3) CONFIRMED: `matchMonitorSpec(name:)` (:1611) passes no make/model/serial (defaults ""), so `focusmon,make:BNQ` never matches; mango match_monitor_spec (monitor.c:297) compares wlr_output make/model/serial. Screen has the fields (Boundary/Screen.swift:11-13). Also MonitorSpec lowercases keys (Rules.swift:51), mango strcmp is case-sensitive (trivial) |
| group_focus ignores arg->tc | 584-610 (:585) | :460-461, Groups.swift:48 (`focused` :49) | CONFIRMED | behaviour | S | `mmsg dispatch groupfocus,next client,<id>`: mango cycles <id>'s group, ours the focused window's |
| moveresize argument | 755-769; binding_parse.c:425 parse_mouse_action; pointer.c:999 | :383-385; Input.swift:195 | CONFIRMED | behaviour | S | mango lowercases; only CurMove/CurResize start a grab (pointer.c:1004 refuses others). Ours `a0 == "curresize" ? .resize : .move`: `CurResize` moves, `curnormal`/typo/no arg moves. Part (2) (bar fallback `bar && !bar->is_tab`): UNSURE, would need a test clicking a group bar panel (Port BarButton) with a moveresize mousebind |
| movewin absolute values address the inner box; no animation | 771-809 | :357-363, Client.swift:94 (`floatGeom` without border) | CONFIRMED | behaviour | S | mango `c->geom.x = i` (outer, incl. border); ours `floatGeom.origin.x = v` (inner): `movewin,100,100` puts the outer box at (100-bw,100-bw). Relative moves are the same. Animation: mango resize() sets action MOVE (animation/client.c:1575) and animates; ours `arrange(m, .none)` -> Animation.swift:72 no animation (visual only) |
| resizewin floating absolute values inner; max(1) clamp | 816-888 | :364-376 | PARTLY | behaviour | S | inner/outer CONFIRMED: `resizewin,800,600` gives an outer box 800+2bw (mango 800). max(1,…) REFUTED as an invention: mango's resize clamps `c->geom.width = MANGO_MAX(1 + 2*bw, …)` (client.c:4166 client_set_bounds, animation/client.c:1538), which is ours inner >= 1. The clamp lacks a mark only |
| switch_proportion_preset matches with ±0.001 | 1024-1086 (`==` :1064) | :121-132 (:127) | CONFIRMED | edge | S | `set_proportion,0.5004`, presets 0.5,0.8: mango no match -> preset[0] 0.5, ours match -> 0.8. The `?? scrollerDefaultProportion` part UNSURE (mango reads node/tc->scroller_proportion; settled by checking where tc->scroller_proportion is initialised at map) |
| smartmovewin with an invalid direction | 1088-1193 | :377-379 | CONFIRMED | edge | S | mango (UNDIR) still floats the window and resizes it to its geom; ours returns before (`guard ... Direction`). Body otherwise 1:1 (smartMoveWindow :850 converts the border) |
| smartresizewin ignores the border; no animation | 1195-1271 | :380-382, smartResizeWindow :810-848 | CONFIRMED | behaviour | M | works on inner floatGeom for c and neighbours: borderpx 4, gappiv 5, floating window above another: mango outer gap 5 px, ours outer boxes overlap by 3 px; DOWN/RIGHT clamp leaves the outer box bw past `w - gappov/gappoh`; UP/LEFT minimum h/10, w/10 is inner. `arrange(cm, .none)` (:847) where mango animates MOVE; smartMoveWindow uses `.move` (:901). Invalid direction as smartmovewin |
| spawn_shell is a login zsh, unlisted | 1309-1332 | :425-426 -> Port/macOS/Spawn.swift:9-20 | CONFIRMED | behaviour | S (list) | `/bin/zsh -lc`, stdout+stderr to /dev/null; mango `sh -c` (bash fallback), stdout dup2'd to stderr, setsid. Not in afvigelser/compatibility/MangoCompat (grep zsh/wordexp: none) |
| spawn is a login zsh, not wordexp+execvp, unlisted | 1334-1363 | :423-424 -> MacWindowSystem.swift:473 -> Spawn.run = Spawn.shell | CONFIRMED | behaviour | S (list) / M (fix) | `spawn,foo | bar`: mango wordexp/execvp runs no pipeline (`|` is WRDE_BADCHAR -> exit), ours a pipeline |
| tagmon with one monitor and next/prev | 1513-1568 | :41-44, tagMonitor :1702 | CONFIRMED | edge | S | mango monitor_from_cycle -> NULL -> return; ours resolves the same monitor and runs `clientViewOnMonitor(newtags)` (:1705): `tagmon,next,1` views the window's tags. Spec make/model/serial as focus_monitor |
| tagsilent mask | 1570-1592 (:1580) | :188-193, normalizeTagMask :537 | CONFIRMED | edge | S | `tagsilent,-1`: parse_tag_mask -> atoi -> 0xFFFFFFFF -> `& TAG0_MASK` -> special tag in mango; ours normalizeTagMask maps 0xFFFFFFFF to all normal tags. `tagsilent,abc`: mango tags=0 (window hidden), ours guard `mask != 0` does nothing |
| viewcrossmon: spec only, views even without a match | 2232-2239 | :182-185 | CONFIRMED | behaviour | S | mango `focus_monitor({.v, .i = UNDIR})` (name spec only) then views on selmon regardless. Ours parseMonitorArg also takes directions/next/prev and returns "monitor not found" without viewing. `viewcrossmon,3,DP-9` (no such monitor): mango views tag 3 here, ours nothing; `viewcrossmon,3,left`: mango regex "left" on names, ours the monitor to the left |
| tagcrossmon: name-only spec | 2241-2257 | :216-224 | CONFIRMED | behaviour | S | body 1:1; `matchMonitorSpec(name:)` (:219, :223) so make:/model:/serial: never match |
| setoption from a bind drops mango's ",0" fields | binding_parse.c:613-650; option_defs.c:1950-1953 (`arg_value* = "0"`) | ConfigParser.swift:589-592; :443-451 | CONFIRMED | mango-bug | S | mango keeps non-empty fields and the unfilled sscanf "0"s: `setoption,circle_layout,tile,scroller` -> "tile,scroller,0,0". Ours "tile,scroller". Not marked, not in §6, not agreed. Only string/array options see it |
| dwindle_set_split_direction checks | 2722-2746 | Dwindle.swift:403 (via :409-421) | CONFIRMED | behaviour | S | no `layout->id != DWINDLE` return; tree is `m.current` (monitor's tag) not get_client_tag_idx(c). Leaves exist on non-dwindle tags (layoutStateInsert, MangoServer.swift:966-970, inserts into the dwindle tree for every layout), so `dwindle_split_horizontal` on a tile tag changes the split seen after `setlayout,dwindle`; mango does not |
| dwindle_toggle_split_direction | 2748-2757 | :409-411 | CONFIRMED | behaviour | S | as above + no `c->isfloating` guard |
| dwindle_split_horizontal | 2759-2768 | :416-418 | CONFIRMED | behaviour | S | as above |
| dwindle_split_vertical | 2770-2779 | :419-421 | CONFIRMED | behaviour | S | as above |
| dwindle_toggle_current_split | 2781-2804 | :412-415, Dwindle.swift:408 | CONFIRMED | behaviour | S | no isfloating/DWINDLE check, monitor tag; arranges always (harmless) |
| load_config_file: "0" and `~` | 2814-2818; load.c:153-184, 386-387 | :434-437 | PARTLY | edge | S | `~` REFUTED: mango's parse_config_file -> resolve_config_path expands `~/` (load.c:171), so `load_config_file,~/alt.conf` loads in mango too. "0" CONFIRMED: from a bind with no argument mango sets cli_config_path "0" and fails to open file "0" (defaults only); ours loads the default config. From IPC with no argument both load the default (mango "", ours "0" -> default). Arguably a mango bug; unmarked |
| IPC: absent argument is "0" in ours, "" in mango | ipc.c:933-955 | Bindings.swift:63 `Dispatch.arg`; IPCServer.swift:160-186 | CONFIRMED | behaviour | S-M | mango passes "" for missing tokens. parse_tag_mask("") = 0, ("0") = TAG0. `mmsg dispatch view`: mango views all tags (bind_to_view target 0), ours toggles/views the special tag; `mmsg dispatch tag`: mango tag_client with ui 0 leaves the tags, ours moves the window to the special tag; also toggleview/toggletag/comboview/tagsilent/viewcrossmon/tagcrossmon/spawn_on_empty. focusmon/tagmon: "" regex matches the first monitor in mango, "0" matches names containing 0 in ours |
| atoi/atof vs Int()/Double() | binding_parse.c:534-537, 711, 841-856 | :85-88, :386-389, finiteDouble :476, relOrAbs :491 | CONFIRMED | edge | S | `incnmaster,1x`/`incgaps,1x`: mango 1, ours 0 (`Int(a0) ?? 0`; ValueParse.atoi exists and is used elsewhere). `movewin,10px`: mango x=10, ours unchanged; `movewin,10.7`: mango 10, ours 10.7; `setmfact,abc`: mango f=0 -> mfact set to itself and every tiled client's master_mfact_per reset, ours returns "invalid argument"; `set_proportion,abc`: mango 0, ours nothing |
| toggleoverview `== "1"` | binding_parse.c:567 | :395 | CONFIRMED | edge | S | mango `atoi(arg) == 1` ("01", "1x" count) |
| spawn_on_empty / toggle_named_scratchpad with commas | binding_parse.c:756-759, 860-864 | ConfigParser.swift:582-588; IPCServer.swift:169-183; :338 | CONFIRMED | edge | S | mango v=field 1 + tags=parse(field 2); scratchpad v3=field 3 only (`%[^,]`). `spawn_on_empty,cmd a,b,3`: mango runs "cmd a" with tags parse("b")=0, ours "cmd a,b" on tag 3. Same on IPC (mango tokens split at commas) |
| "alldir" in focusmon/tagmon | value_parse.c:222-264 | Geometry.swift:9, :1604 | CONFIRMED | edge | S | mango ALLDIR (5) goes to monitor_from_direction, where `1 << 5` is no wlr direction (mango's own result is degenerate); ours treats "alldir" as a monitor name |
| reset_gaps | 165-173 | none | CONFIRMED | name | S | dead in mango: no parse_func_name entry, no caller (grep: only bind.h:107). Missing per rule 1.1, nothing observable |
| increase_inner_gap | 632-639 | none | CONFIRMED | name | S | dead in mango (bind.h:101 only) |
| increase_outer_gap | 641-648 | none | CONFIRMED | name | S | dead |
| increase_inner_horizontal_gap | 650-657 | none | CONFIRMED | name | S | dead |
| increase_inner_vertical_gap | 659-666 | none | CONFIRMED | name | S | dead |
| increase_outer_horizontal_gap | 668-675 | none | CONFIRMED | name | S | dead |
| increase_outer_vertical_gap | 677-684 | none | CONFIRMED | name | S | dead |

## Not in mango

| ours | claim | verdict | note |
|---|---|---|---|
| Dispatch.swift:5 `dispatch(_:target:rescan:)` | invention, no `/// mango` line | CONFIRMED | parse_func_name's argument conversion + all dispatcher bodies in one switch; error strings mango has not |
| Dispatch.swift:7 `defer { system.rescan() }` | marked | CONFIRMED | |
| Dispatch.swift:476 finiteDouble | marked | CONFIRMED | |
| Dispatch.swift:491 relOrAbs | marked | CONFIRMED | |
| Dispatch.swift:537 normalizeTagMask | marked, but its 0xFFFFFFFF rule is not mango's | CONFIRMED | see tagsilent |
| Dispatch.swift:1603 parseMonitorArg | mango's name, does more, no doc | CONFIRMED | also monitor_from_cycle and the spec loop |
| Dispatch.swift:1470 directionGeom | marked | CONFIRMED | |
| Dispatch.swift:1892 `private func <` on (CGFloat, CGFloat) | dead code | CONFIRMED | no tuple comparison in the file (only `min(by:)` on CGFloat at :1591) |
| Dispatch.swift:372 `max(1, …)` | clamp not in mango | REFUTED | mango clamps in resize/client_set_bounds (client.c:4166); unmarked only |
| Dispatch.swift:435 load_config_file "0"/~ | not mango | PARTLY | "0" is ours; `~` expansion mango does too (load.c:171) |
| Dispatch.swift:465 default -> extraDispatchers | marked | CONFIRMED | |
| Bindings.swift:63 Dispatch.arg "0" | marked, also used for IPC | CONFIRMED | see IPC row |
| Bindings.swift:66 knownNames / :91 isKnown | marked | CONFIRMED | |
| MangoServer.swift:380 `focused` | trivial accessor | CONFIRMED | selmon->sel |
| Groups.swift:48 groupFocus | drops arg->tc | CONFIRMED | |
