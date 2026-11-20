# B-bind: src/dispatch/bind.c, include/mango/dispatch/bind.h (+ the dispatcher table in src/config/binding_parse.c parse_func_name)

Status 2026-11-20 (trin 10): hvert fund er mærket ✓ (rettet, som mango, listet, væk) eller åben, kontrolleret mod koden efter trin 9.

Paths: mango = `~/sources/mango/src/dispatch/bind.c` unless named; ours = `Sources/Mango/Engine/Dispatch.swift` unless named.
Most mango dispatchers are inlined in ours as `case "<name>":` inside `dispatch(_:target:rescan:)` (Dispatch.swift:5), so they
carry no function with mango's name; those rows are tagged `name` (inlined).

## Functions
| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| bind_to_view (40) | case "view" :151, bindToView :576 | 1:1 | all five branches (view_current_to_back, INT_MIN/curtag 0, TAG0 before all-tags, 0 -> all tags without animation) compared |
| change_vt (92) | none (knownNames, no case) | platform | macOS has no VTs; listed (MangoCompat "chvt"); return 1 listed §3 l.97 |
| create_virtual_output (114) | none | platform | wlroots headless backend; listed MangoCompat |
| destroy_all_virtual_output (149) | none | platform | listed MangoCompat |
| reset_gaps (165) | none | missing ✓ rettet i trin 6 | dead in mango: no dispatcher name in parse_func_name and no caller; trivially portable (setgaps with config/special gaps) |
| exchange_client (175) | case "exchange_client" :46 | 1:1, name | tc/sel, float/fullscreen guard on c->mon, direction_select + get_focused_stack_client(tc, arg->tc) |
| move_client (195) | case "move_client" :53 | differs (minor) ✓ rettet i trin 6 | body 1:1; with an invalid direction (UNDIR) mango still runs client_jump_to_monitor(NULL) and then `pointer_warp_to_client(c)` when warpcursor; ours returns before the warp (`guard ... Direction(mangoName:)`). Scenario: `bind=...,move_client,foo` with warpcursor=1 warps in mango, not in ours |
| exchange_stack_client (225) | case "exchange_stack_client" :50 | 1:1, name | |
| focus_direction (246) | case "focusdir" :15, focusDirection :1417 | differs ✓ rettet i trin 6 | ignores arg->tc: mango uses arg->tc as origin in direction_select and get_focused_stack_client(c, arg->tc); ours always the focused client (`directionSelect(dir)` :1424, `getFocusedStackClient(sc, nil)` :1434). Scenario: `mmsg dispatch client,<id>,focusdir,left` moves from <id> in mango, from the focused window in ours. Monocle-in-overview branch listed §6 |
| focus_window_or_workspace (296) | :18, focusWindowOrWorkspace :1449 | differs ✓ rettet i trin 6 | same arg->tc omission as focus_direction (`directionSelect(dir)`, `getFocusedStackClient(..., nil)` :1452); otherwise 1:1 |
| client_group_join (330) | Groups.swift:17 clientGroupJoin | 1:1 | group_leave's extra arrange covered by the later arranges (same result); client_sync_tiled_hint is xdg tiled state (platform) |
| group_join (378) | case "groupjoin" :452 | 1:1, name | extra fullscreen pre-check (:453) uses c.mon's layout where direction_select uses selmon's; differs only for an IPC target on a non-selected monitor (unsure, negligible) |
| client_group_leave (395) | Groups.swift:33 clientGroupLeave | 1:1 | flink reinsert after rc kept; tag_visible/client_update_visibility are scene (port) |
| group_leave (427) | case "groupleave" :457 | 1:1, name | |
| focus_last (438) | case "focuslast" :21 | 1:1, name | skip of `groupParked` = mango's parked members being unlinked from focus_stack (same result) |
| toggle_trackpad_enable (478) | none | platform | listed MangoCompat ("no API to switch the trackpad off") |
| focus_monitor (483) | case "focusmon" :38, focusMonitor :1615, parseMonitorArg :1603 | differs ✓ rettet i trin 6 (tc) og trin 9 (make/model/serial) | (1) arg->tc ignored: mango focuses `arg->tc ? arg->tc : client_focus_top`, ours always clientFocusTop (:1619); (2) next/prev: mango monitor_from_cycle returns NULL with one enabled monitor, ours returns the same monitor (harmless here, see tag_monitor); (3) monitor spec matched by name only: `matchMonitorSpec(name:)` (:1611) gets no make/model/serial, so `focusmon,make:BNQ` never matches in ours, matches in mango (Screen has make/model/serial) |
| focus_stack (525) | case "focusstack" :13, focusStack :1399 | 1:1 | |
| over_circle (552) | OverviewMode.swift:143 overCircle | 1:1 | |
| group_focus (584) | case "groupfocus" :460, Groups.swift:48 groupFocus | differs ✓ rettet i trin 6 | arg->tc ignored: groupFocus uses `focused` (Groups.swift:49). Scenario: `mmsg dispatch client,<id>,groupfocus,next` cycles <id>'s group in mango, the focused window's in ours |
| inc_nmaster (612) | case "incnmaster" :85 | 1:1, name | atoi vs `Int(a0) ?? 0`: see parse row |
| increase_gaps (622) | case "incgaps" :386, setgaps :804 | 1:1, name | base is m.gaps even when special is active, as mango |
| increase_inner_gap (632) | none | missing ✓ rettet i trin 6 | dead in mango (no dispatcher name, no caller) |
| increase_outer_gap (641) | none | missing ✓ rettet i trin 6 | dead in mango |
| increase_inner_horizontal_gap (650) | none | missing ✓ rettet i trin 6 | dead in mango |
| increase_inner_vertical_gap (659) | none | missing ✓ rettet i trin 6 | dead in mango |
| increase_outer_horizontal_gap (668) | none | missing ✓ rettet i trin 6 | dead in mango |
| increase_outer_vertical_gap (677) | none | missing ✓ rettet i trin 6 | dead in mango |
| set_master_factor (686) | case "setmfact" :89 | 1:1, name | Double vs mango float at the 0.1/0.9 bounds could round differently (unsure); garbage arg: see parse row |
| kill_client (713) | case "killclient" :248 | 1:1, name | client_pending_force_kill inlined as `kill(c.pid, SIGKILL)` (mango does the same) |
| smart_kill_client (728) | case "smartkillclient" :251 | 1:1, name | client_reparent_group is scene (port) |
| move_resize (755) | case "moveresize" :383 | differs ✓ rettet i trin 6 (bar-fallback listet §5) | (1) arg: mango parse_mouse_action lowercases and only "curmove"/"curresize" start a grab (anything else -> mode 0 -> pointer_begin_move_resize refuses); ours `a0 == "curresize" ? .resize : .move`, so `moveresize` with no/other arg starts a move and `CurResize` starts a move; (2) mango falls back to the group bar's client (`bar && !bar->is_tab`), ours only clientAtPoint (bars are port panels; unsure whether reachable) |
| move_window (771) | case "movewin" :357, relOrAbs :491 | differs ✓ rettet i trin 6 | absolute x/y set floatGeom (without border, Client.swift:94) where mango sets geom (with border): `movewin,100,100` puts the border box at (100-bw,100-bw) in ours, (100,100) in mango. Also `arrange(m, .none)` (no animation, Placement.swift:7) where mango's resize animates MOVE (unsure it matters) |
| quit (811) | case "quit" :438 | port | system.quit (wl_display_terminate) |
| resize_window (816) | case "resizewin" :364 | differs ✓ rettet i trin 6 | floating absolute width/height set floatGeom (inner) where mango sets geom (outer): `resizewin,800,600` gives an 800+2bw outer box; `max(1, …)` clamp (:372) is not in mango and unmarked; ISTILED written as !floating && !minimized && !unglobal (same result after the fullscreen guard) |
| restore_minimized (890) | case "restore_minimized" :309 | 1:1, name | system.clientSetMinimized marked; client_update_border_color via port borders |
| set_layout (953) | case "setlayout" :97, setLayout :786 | 1:1 | |
| set_key_mode (972) | case "setkeymode" :440 | 1:1, name | 27-char truncation absent but mango truncates keymode names the same way, so same result; return 1 listed §3 l.97 |
| set_proportion (984) | case "set_proportion" :117, setProportion :793 | 1:1 | single-client check in setProportion; geom.width write is the port's |
| switch_proportion_preset (1024) | case "switch_proportion_preset" :121 | differs ✓ rettet i trin 6 | match by `abs($0 - cur) < 0.001` (:127) where mango compares `==`; scenario: proportion set to 0.5004 by set_proportion, presets 0.5,0.8: mango (no match) -> preset[0]=0.5, ours (match 0.5) -> 0.8. Also current = `?? scrollerDefaultProportion` where mango reads node/tc value directly (unsure) |
| smart_move_window (1088) | case "smartmovewin" :377, smartMoveWindow :850 | differs (minor) ✓ rettet i trin 6 | body 1:1 incl. border conversion; with an invalid direction mango still makes the window floating and resizes it, ours returns before (`guard ... Direction`) |
| smart_resize_window (1195) | case "smartresizewin" :380, smartResizeWindow :810 | differs ✓ rettet i trin 6 | works on floatGeom without the border (no `insetBy(-bw)` as in smartMoveWindow): DOWN/RIGHT clamp leaves the outer box bw past `w - gappov/gappoh`; neighbour snap ends 2bw closer than `gappiv/gappih`; UP/LEFT minimum h/10, w/10 is inner, mango outer. Scenario: borderpx 4, gappiv 5, window above another: mango leaves a 5 px gap, ours overlaps by 3 px. Also `.none` animation (mango animates) and invalid-direction float as smartmovewin |
| center_window (1273) | case "centerwin" :140 | 1:1, name | scroller branch via port centerRequest (listed §5 scroller columns) |
| spawn_shell (1309) | case "spawn_shell" :425 -> Port/macOS Spawn.shell | differs ✓ listet: afvigelser.md §2; login-zsh i Port/macOS/Spawn.swift:9-20, ikke listet | runs `/bin/zsh -lc` (login zsh), mango `sh -c` (fallback bash); stdout/stderr to /dev/null, mango dup2s stdout to its stderr. Scenario: a bash/sh-only construct or a ~/.zprofile side effect behaves differently. Not in afvigelser/compatibility |
| spawn (1334) | case "spawn" :423 -> Spawn.run = Spawn.shell | differs ✓ listet: afvigelser.md §2; Spawn.run = Spawn.shell (Port/macOS/Spawn.swift:5-7), ikke listet | mango `wordexp` + `execvp` (no pipes/`&&`/redirection: wordexp rejects them), ours a login zsh. Scenario: `spawn,foo | bar` runs nothing in mango, a pipeline in ours |
| spawn_on_empty (1365) | case "spawn_on_empty" :427 | 1:1, name | shell as spawn_shell; command-with-commas parse: see parse row |
| switch_keyboard_layout (1385) | none | platform | listed §2 and MangoCompat |
| switch_layout (1444) | case "switch_layout" :100 | 1:1, name | layouts[] order = LayoutKind.allCases (checked) |
| tag (1505) | case "tag" :186, tagClient :503 | 1:1 | client_reparent_group is scene |
| tag_monitor (1513) | case "tagmon" :41, tagMonitor :1702 | differs ✓ rettet i trin 6 | body 1:1; monitor resolution via parseMonitorArg: with one monitor `tagmon,next,1` resolves to the same monitor, so ours runs `clientViewOnMonitor(c.tags)` where mango returns (monitor_from_cycle -> NULL); spec make/model/serial never match (as focus_monitor) |
| tag_silent (1570) | case "tagsilent" :188, tagSilent :527 | differs ✓ rettet i trin 6 | mask normalised by normalizeTagMask (:537, maps 0xFFFFFFFF to all tags) and guarded `mask != 0`; mango: `ui & TAG0_MASK ? TAG0_MASK : ui & TAGMASK`, no guard. Scenarios: `tagsilent,-1` -> mango special tag, ours all tags; `tagsilent,abc` -> mango tags=0 (window hidden), ours nothing |
| tag_to_left (1594) | case "tagtoleft" :194 | 1:1, name | carousel and carousel_anim_dir as mango |
| tag_to_right (1621) | case "tagtoright" :194 | 1:1, name | |
| toggle_named_scratchpad (1648) | case "toggle_named_scratchpad" :337, toggleNamedScratchpad :1861 | 1:1 | skips spawning "0"/"" (mango runs `sh -c 0`, which fails: same result); appName match listed §3 l.85; comma parse: see parse row |
| toggle_render_border (1669) | case "toggle_render_border" :302 | 1:1, name | |
| toggle_scratchpad (1677) | case "toggle_scratchpad" :335, toggleScratchpad :1749 | 1:1 | single_scratchpad test written `isNamedScratchpad && scratchpadShown` (needs is_in_scratchpad) vs mango `isnamedscratchpad && !isminimized`; every mango path that clears is_in_scratchpad also clears isnamedscratchpad, so same result (unsure) |
| special_tag_migrate_clients (1714, static) | specialTagMigrateClients :1720 | 1:1 | iskilling skip absent (killed clients leave `clients` on unmap) |
| special_tag_previous_tagset (1733, static) | specialTagPreviousTagset :1734 | 1:1 | `& ~special` vs `& TAGMASK`: same for normalised tagsets |
| special_tag_prepare_target (1740, static) | specialTagPrepareTarget :1739 | 1:1 | enabled checks are wlroots |
| toggle_special_tag_mon (1760) | MangoServer.swift:605 toggleSpecialTagMon | 1:1 | |
| toggle_special_tag (1776) | case "toggle_special_tag" :339 | 1:1, name | |
| tag_special_tag_internal (1783, static) | case "tag_special_tag", "tag_special_silent" :341 | 1:1, name | |
| tag_special_tag (1818) | :341 | 1:1, name | |
| tag_special_silent (1823) | :341 | 1:1, name | |
| toggle_fake_fullscreen (1828) | case "togglefakefullscreen" :281 | 1:1, name | notify listed §3 l.77 |
| toggle_floating (1837) | case "togglefloating" :259 | 1:1, name | |
| toggle_fullscreen (1861) | case "togglefullscreen" :275 | 1:1, name | |
| toggle_global (1879) | case "toggleglobal" :290 | 1:1, name | |
| toggle_gaps (1896) | case "togglegaps" :390 | 1:1, name | |
| toggle_group_bar (1905) | case "togglegroupbar" :462 | 1:1, name | |
| toggle_maximize_screen (1916) | case "togglemaximizescreen" :284 | 1:1, name | |
| toggle_overlay (1936) | case "toggleoverlay" :298 | 1:1, name | reparent = port restack |
| toggle_tag (1952) | case "toggletag" :225 | 1:1, name | INT_MIN branches checked |
| toggle_view (1990) | case "toggleview" :165 | 1:1, name | |
| tags_last_tag_num (2021, static) | inlined in tagGatherLastTagNum :639 | 1:1, name | |
| tag_gather_last_tag_num (2031, static) | tagGatherLastTagNum :635 | 1:1 | |
| view_shift_tag (2048) | viewShiftTag :645 | 1:1 | |
| view_shift_tag_have_client (2097) | viewShiftTagHaveClient :678 | 1:1 | |
| view_to_left (2158) | case "viewtoleft" :175 | 1:1, name | |
| view_to_right (2163) | :175 | 1:1, name | |
| view_insert (2168) | case "view_insert" :180, viewInsert :704 | 1:1 | |
| view_to_left_have_client (2212) | :177 | 1:1, name | |
| view_to_right_have_client (2217) | :177 | 1:1, name | |
| viewprev_have_client (2222) | :177 | 1:1, name | |
| viewnext_have_client (2227) | :177 | 1:1, name | |
| view_cross_monitor (2232) | case "viewcrossmon" :182 | differs ✓ rettet i trin 6 | mango: `focus_monitor({.v, .i = UNDIR})` (name spec only, no direction/next/prev) and then views the tag on selmon whether or not the monitor matched; ours resolves with parseMonitorArg (also directions, next/prev) and returns "monitor not found" without viewing. Scenario: `viewcrossmon,3,DP-9` (no such monitor) views tag 3 on the current monitor in mango, nothing in ours; spec make/model/serial as focus_monitor |
| tag_cross_monitor (2241) | case "tagcrossmon" :216 | differs ✓ rettet i trin 9 | body 1:1; `matchMonitorSpec(name:)` only (:219, :223), so make:/model:/serial: specs never match |
| combo_view (2259) | case "comboview" :153 | 1:1, name | combo branch arranges with `.none` (no move animation) where mango's arrange animates moves (unsure, visual only) |
| zoom (2279) | case "zoom" :68 | 1:1, name | scroller column reorder marked `not in mango` |
| setoption (2311) | case "setoption" :443 | differs, unlisted ✓ listet: afvigelser.md §6 | from a bind, mango joins arg_value2..5 *including* sscanf's "0" defaults: `setoption,circle_layout,tile,scroller` gives "tile,scroller,0,0"; ours (ConfigParser.parseFuncName stops at the first empty field) gives "tile,scroller". Arguably a mango bug; not agreed/listed |
| minimize_window (2318) | case "minimized" :306 | 1:1, name | |
| fix_mon_tagset_from_overview (2332) | OverviewMode.swift:10 | 1:1 | |
| overview_client_on_current_tags (2342, static) | OverviewMode.swift:21 | 1:1 | |
| set_overview (2348, static) | OverviewMode.swift:26 setOverview | 1:1, listed §5 §6 | anim/cursor/ext-workspace omissions marked and listed §5; empty-monitor fixes §6 |
| toggle_overview (2474) | OverviewMode.swift:122 | 1:1 | arg parse `a0 == "1"` vs `atoi(a0) == 1`: see parse row |
| enter_overview (2482) | OverviewMode.swift:129 | 1:1 | |
| leave_overview (2491) | OverviewMode.swift:136 | 1:1 | |
| toggle_jump (2500) | OverviewMode.swift:358 + Dispatch :404 | 1:1, listed §6 | grab guard is the §6 fix |
| disable_monitor (2517) | none | platform | listed MangoCompat |
| enable_monitor (2532) | none | platform | listed |
| toggle_monitor (2546) | none | platform | listed |
| sleep_monitor (2560) | none | platform | listed |
| wakeup_monitor (2575) | none | platform | listed |
| sleep_toggle_monitor (2589) | none | platform | listed |
| scroller_apply_stack (2603) | Layout/Scroller.swift:72 scrollerApplyStack | 1:1, listed §5 | port's column model (listed §5); target = adjacent visible column instead of find_client_by_direction(findFloating=false), same result for the tiled scroller (unsure with focus_cross_monitor, where mango's target on another monitor makes it return; ours never looks across). Invalid direction: mango (UNDIR) pops c out of its stack, ours nothing (edge) |
| scroller_stack (2674) | case "scroller_stack" :133 | 1:1, name | |
| toggle_all_floating (2688) | case "toggle_all_floating" :264 | 1:1, name | client_raise_group/raise_tab = port restack |
| dwindle_set_split_direction (2722) | Layout/Dwindle.swift:403 dwindleSetSplitDirection | differs ✓ rettet i trin 4 | no `layout->id != DWINDLE` check and uses the monitor's current tag (`m.current.state`) instead of get_client_tag_idx(c). Scenario: tag 1 in dwindle, `setlayout,tile`, `dwindle_split_horizontal`, back to dwindle: ours has changed the leaf's split (the tree persists across layouts), mango has not. client_draw_split_border is the port's |
| dwindle_toggle_split_direction (2748) | case :409 | differs ✓ rettet i trin 4 | as above, and no `c->isfloating` guard (`guard let c` only) |
| dwindle_split_horizontal (2759) | case :416 | differs ✓ rettet i trin 4 | as above |
| dwindle_split_vertical (2770) | case :419 | differs ✓ rettet i trin 4 | as above |
| dwindle_toggle_current_split (2781) | case :412, Dwindle.swift:408 | differs ✓ rettet i trin 4 | no isfloating/DWINDLE check, current tag instead of client's tag; `arrange(m)` even when nothing changed (harmless) |
| focus_by_id (2806) | case "focusid" :35 | 1:1, name | |
| load_config_file (2814) | case "load_config_file" :434 | differs, unmarked ✓ rettet i trin 6 | ours treats "0" (bind with no argument) as the default config and expands `~`; mango copies arg->v verbatim (path "0"; "~/x" stays literal). Scenario: `load_config_file,~/alt.conf` loads in ours, fails in mango |
| bind.h `Arg` struct | Model/Bindings.swift:56 `Dispatch` (name + [String]) | port, name | arguments kept as text and parsed at dispatch time (marked in Bindings/relOrAbs); not mango's structure |
| bind.h enums PREV/NEXT, MON_PREV/NEXT, FORCE/UNFORCE, OVERCIRCLE_* | Geometry.swift:24 NextPrev; string compares in dispatch | 1:1, name | |
| binding_parse.c parse_func_name: names | Bindings.swift:66 knownNames, Dispatch.isKnown :91 | 1:1 | all 94 mango names accepted (diffed); the 12 without a case are all listed in MangoCompat (chvt, *_virtual_output, *_monitor x6, switch_keyboard_layout, toggle_trackpad_enable, togglehdr) |
| parse_func_name: absent IPC argument | Bindings.swift:62 `Dispatch.arg` -> "0"; IPCServer.swift:186 | differs ✓ rettet i trin 6 | mango's IPC passes "" for a missing token, ours "0". parse_tag_mask("") = 0 but ("0") = TAG0. Scenarios: `mmsg dispatch view` views all tags in mango, toggles the special tag in ours; `mmsg dispatch tag` leaves tags in mango, moves the window to the special tag in ours; also toggleview/toggletag/comboview/tagsilent/viewcrossmon/tagcrossmon/spawn_on_empty, `setkeymode` ("" vs "0"), focusmon/tagmon spec ("" regex matches the first monitor in mango) |
| parse_func_name: atoi/atof | :85 `Int(a0) ?? 0`, :388, finiteDouble :476, relOrAbs :491 | differs (minor) ✓ rettet i trin 6 | `incnmaster,1x` -> mango 1, ours 0; `movewin,1.5,…` truncates in mango; garbage `setmfact,abc` -> mango f=0 -> sets mfact to itself and resets every tiled client's master_mfact_per, ours does nothing; `set_proportion,abc` -> mango proportion 0, ours nothing; `movewin,abc,…` -> mango x=0, ours unchanged |
| parse_func_name: toggleoverview | :395 `a0 == "1"` | differs (minor) ✓ rettet i trin 6 | mango `atoi(arg) == 1` ("01", "1x" count) |
| parse_func_name: spawn_on_empty / toggle_named_scratchpad commas | ConfigParser.swift:581-588, IPCServer.swift:169-183 | differs (minor) ✓ rettet i trin 6 og trin 9 | mango takes the command from one field (spawn_on_empty arg_value; scratchpad arg_value3) and drops/uses later fields as given; ours joins the remaining fields into the command. `spawn_on_empty,foo a,b,3`: mango cmd "foo a", tag parse("b")=0; ours cmd "foo a,b", tag 3 |
| parse_direction "alldir" (value_parse.c:222) | Direction(mangoName:) Geometry.swift:9 | differs (minor, unsure) ✓ rettet i trin 6 | ALLDIR has no case; `focusmon,alldir`/`tagmon,alldir` go to monitor_from_direction(ALLDIR) in mango, a name match in ours |

## Not in mango (in the Swift files looked at)
| ours (file:line) | marked? | note |
|---|---|---|
| Dispatch.swift:5 `dispatch(_:target:rescan:)` | no | merges parse_func_name's argument parsing and all dispatcher bodies into one switch; no `/// mango` line; returns error strings mango does not have (IPC discards them); calls `printstatus()` after every dispatcher (harmless: watch sends only on change, §2) |
| Dispatch.swift:7 `defer { system.rescan() }` | yes | port side |
| Dispatch.swift:476 finiteDouble | yes | |
| Dispatch.swift:491 relOrAbs | yes | parse_num_type at dispatch time |
| Dispatch.swift:537 normalizeTagMask | yes | but its 0xFFFFFFFF -> all-tags rule is not mango's inline `& TAGMASK` (see tag_silent) |
| Dispatch.swift:1603 parseMonitorArg(_:relativeTo:) | no | carries mango's name (value_parse.c parse_monitor_arg returns a direction code) but also does monitor_from_cycle and the match_monitor_spec loop, with the differences noted (single monitor, name-only spec, no enabled check) |
| Dispatch.swift:1470 directionGeom | yes | |
| Dispatch.swift:1892 `private func <` on (CGFloat, CGFloat) | no | appears unused in the file (dead code) |
| Dispatch.swift:372 `max(1, …)` in resizewin | no | clamp not in mango |
| Dispatch.swift:435 load_config_file "0"/~ handling | no | see load_config_file |
| Dispatch.swift:465 default -> portHooks.extraDispatchers | yes | port extensions |
| Bindings.swift:62 Dispatch.arg ("0" default) | yes | but also applied to IPC, where mango gives "" (see parse row) |
| Bindings.swift:66 knownNames / :91 isKnown | yes | |
| MangoServer.swift:380 `focused` | no | accessor for selmon->sel; trivial |
| Groups.swift:17,33,48 clientGroupJoin/Leave, groupFocus | n/a | mango names; groupFocus's signature drops arg->tc (see group_focus) |

## Summary
Counts (122 rows in Functions: 116 bind.c/bind.h entries + 6 for the parse table):
- 1:1: 73 (47 rows carry `name`, almost all dispatchers inlined as `case` without a function of mango's name; listed §5/§6: 3)
- differs: 29 (bind.c functions 24, parse table 5)
- missing: 7 (reset_gaps and the six increase_*_gap: dead code in mango, no dispatcher name)
- platform: 11 (all listed in MangoCompat / afvigelser)
- port: 2 (quit, Arg struct)

10 most significant deviations:
1. **Monitor specs match by name only** in focusmon, tagmon, viewcrossmon, tagcrossmon (`matchMonitorSpec(name:)`, Dispatch.swift:219/223/1611): `make:`/`model:`/`serial:` specs never match, though Screen has the fields.
2. **IPC with no argument gets "0", mango gets ""** (Dispatch.arg): `mmsg dispatch view` toggles the special tag instead of viewing all tags; `mmsg dispatch tag` moves the window to the special tag.
3. **spawn/spawn_shell run `/bin/zsh -lc`** (Port Spawn.swift), not wordexp+execvp / `sh -c`; pipes and shell syntax work where mango's spawn refuses them; unlisted.
4. **dwindle_* dispatchers** lack the DWINDLE-layout and isfloating checks and use the monitor's current tag instead of the client's tag; they alter the persisted tree on non-dwindle tags.
5. **smartresizewin ignores the border** (floatGeom is inner): snapping to neighbours and the screen-edge clamp are off by bw/2bw; minimum size is inner.
6. **viewcrossmon**: mango views the tag on the current monitor even when the spec does not match and only matches names; ours also takes directions/next/prev and does nothing when nothing matches.
7. **arg->tc ignored** by focusdir, focus_window_or_workspace, focusmon, groupfocus (IPC `client,<id>,…` acts on the focused window).
8. **tagsilent**: `-1` goes to all tags (mango: special tag); a zero mask is ignored (mango sets tags 0).
9. **movewin/resizewin absolute values** address the inner box (mango the outer box incl. border); unmarked `max(1, …)` clamp.
10. **moveresize**: any argument other than "curresize" (incl. none, "curnormal", "CurResize") starts a move; mango only curmove/curresize, case-insensitive, else nothing. Also: setoption from a bind no longer appends mango's trailing ",0" fields; switch_proportion_preset matches with ±0.001; load_config_file maps "0" to the default and expands `~`.
