# D-monitor-main: manage/monitor.c, manage/misc.c, manage/layer.c, manage/tab.c, manage/xwayland_primary.c, main.c, common/{log,scene_node,server,util}.c, include/mango/manage/{monitor,misc,layer,tab,xwayland_primary}.h, include/mango/common/{server,types,util,log,scene_node}.h

Status 2026-11-20 (trin 10): hvert fund er mærket ✓ (rettet, som mango, listet, væk) eller åben, kontrolleret mod koden efter trin 9.

Paths: mango = `~/sources/mango/src/...`; ours = `Sources/...` (abbreviated `MS` = `Mango/Engine/MangoServer.swift`, `CL` = `Mango/Engine/Client.swift`, `DI` = `Mango/Engine/Dispatch.swift`, `IN` = `Mango/Engine/Input.swift`, `TB` = `Mango/Engine/Tabs.swift`, `RU` = `Mango/Model/Rules.swift`).

## Functions

### manage/monitor.c (+ monitor.h macros)

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| is_special_active monitor.c:46 | MS:616 `isSpecialActive` | 1:1 | |
| get_mon_curtag monitor.c:50 | CL:180 `getMonCurtag` (var) | 1:1 | Marked: no isoverview test. Verified set_overview's target is `current_tags & TAGMASK` or `~0 & TAGMASK`, never TAG0, so same result. curtag lives on Monitor, not Pertag. |
| special_has_clients monitor.c:61 | MS:373 `specialClients(m).isEmpty` (used MS:409) | 1:1 name | Helper is marked; mango's server.clients excludes parked members, as our `clients` does. |
| get_monitor_active_tagset monitor.c:74 | MS:599 | 1:1 | `& ~special` where mango has `& TAGMASK`; same result unless the other tagset holds bits above tag_num (only with `chutney_fullscreen_tag`'s F tags). |
| monitor_from_direction monitor.c:86 | DI:1574 `monitorFromDirection(_:from:)` | 1:1 | wlroots' adjacent/farthest output written out with ref point (m.x,m.y). Returns nil where mango returns selmon; callers treat both as "nothing". |
| monitor_from_cycle monitor.c:106 | DI:1607-1608 (inline in `parseMonitorArg`) | differs, name ✓ rettet i trin 5 | Same algorithm, but over a differently ordered list: mango's `server.monitors` is newest-first (`wl_list_insert(&server.monitors, …)` in handle_new_output), ours is sorted left-to-right (`Port/macOS/Screens.swift:33`). Displays A,B,C plugged in that order and also placed left-to-right, selected B: `focusmon next` → mango A, ours C. (Mango's loop also steps onto the list head sentinel when selmon is last; unsure what it does there.) |
| is_scroller_layout monitor.c:124 | inline `m.layout.isScroller` (Mango/Layout/Layout.swift:51) | 1:1 name | |
| is_monocle_layout monitor.c:134 | inline `m.layout == .monocle` | 1:1 name | |
| is_centertile_layout monitor.c:141 | none | missing ✓ rettet i trin 5 | Has no caller in mango, so nothing is lost. |
| is_overcircle_mode monitor.c:148 | Mango/Engine/OverviewMode.swift:5 | 1:1 | |
| special_sync_top_layer monitor.c:153 | none | platform | Moves the layer-shell top layer in the scene. |
| special_update_dim monitor.c:164 | MS:620 → `system.showSpecialDim` | port | |
| get_tag_status monitor.c:179 | DI:630 `getTagStatus(_:on:)` → Bool | 1:1 | Mango's urgent level (2) is read only by ext-workspace. The `!isMinimized` filter changes nothing because minimized clients have tags 0 (DI:1783). |
| get_tags_first_tag_num monitor.c:194 | RU:30 `TagMask.getTagsFirstTagNum` | differs ✓ rettet i trin 1 | Mango clamps the result to `config.tag_num` (`i >= tag_num → tag_num`); ours returns lowest bit + 1 with no clamp, and nil for 0. Example: tags = only bit 9 (tag 10) with tag_num 9 (a rule tag or an F tag above tag_num): mango → 9, ours → 10, which picks a different pertag slot in checkMatchTagFloatingRule, clearFullscreenFlag and checkHitNoBorder. Unsure how reachable this is without the port extension. |
| monitor_copy_tag_layout monitor.c:220 | MS:995 | 1:1 | |
| get_tags_first_tag monitor.c:248 | DI:567 | 1:1 | |
| monitor_at_point monitor.c:282 | MS:355 `monitorAtPoint` | differs ✓ rettet i trin 5 | Mango returns NULL for a point outside every output. Ours falls back to the monitor with the nearest centre. Example: a window centre off-screen (`Port/macOS/MacEvents.swift:40`, DragTile, IPC): mango → none, ours → a monitor. |
| get_monitor_nearest_to monitor.c:288 | none (monitorAtPoint's fallback is similar) | platform | Used only for text-input/IM popups. |
| match_monitor_spec monitor.c:297 | RU:47 `MonitorSpec(mango:)` + RU:65 `matchMonitorSpec`; callers MS:877, DI:219, DI:223, DI:1611 | differs ✓ rettet i trin 9 | Every caller passes only `name:`; make/model/serial default to "". `Screen` has make/model/serial (Boundary/Screen.swift:11). So a spec with `make:`, `model:` or `serial:` (focusmon, tagmon, tagcrossmon, window_rule `monitor:`, …) never matches on any display, where mango matches it. Smaller points: keys are lowercased and trimmed (mango: `Name:` is ignored, so it matches all), and we split on "&&" where strtok splits on any '&'. |
| device_target_monitor monitor.c:366 | none | platform listed | device_rule (MangoCompat.ignoredKeywords). |
| blur_layer_on_wallpaper monitor.c:379 | none | platform listed | Blur. |
| mango_scene_output_commit monitor.c:390 | none | platform | Output commit, tearing. |
| mango_output_commit monitor.c:459 | none | platform | |
| get_nearest_output_mode monitor.c:470 | none | platform listed | monitor_rule. |
| enable_adaptive_sync monitor.c:491 | none | platform listed | vrr (monitor_rule, vrr_only_fullscreen). |
| disable_adaptive_sync monitor.c:512 | none | platform listed | |
| monitor_matches_rule monitor.c:518 | none | platform listed | monitor_rule (also xwayland_primary, reapply_monitor_rules §5). |
| monitor_load_icc_transform monitor.c:534 | none | platform listed | monitor_rule icc. |
| monitor_set_icc monitor.c:578 | none | platform listed | |
| apply_rule_to_state monitor.c:601 | none | platform listed | monitor_rule. |
| handle_new_output monitor.c:645 | MS:303 `rebuildMonitors` (marked) + CL:191 `Monitor.init` | differs ✓ rettet i trin 5 | Pertag defaults, `parse_tagrule`, tagset/curtag/prevtag = 1, gaps from config: same. Monitor rules, chvt backup, blur and ext-workspace are platform (listed). The difference is list position: mango inserts the new monitor at the head of `server.monitors`; ours rebuilds the list in left-to-right order. That order drives monitor_from_cycle, monitor_close's fallback, the `!selected_monitor` choice in handle_output_layout_change, and the order of IPC outputs. |
| handle_output_destroy monitor.c:899 | MS:315-324 (removed branch of rebuildMonitors) | port | Fadeouts, layer surfaces, ext-workspace, scene, skip-frame timer and ICC are platform. `title_message_bar_finish` is kept (MS:324, before monitor_close rather than after; same result). |
| set_selected_monitor monitor.c:973 | inline `selectedMonitor = …` | 1:1 name | |
| monitor_close monitor.c:975 | MS:315-338 | differs, listed §6 (the overview part only) ✓ rettet i trin 5 | (a) When the selected monitor goes, mango picks the first enabled monitor in its list (the most recently added); ours picks the macOS main display (`isMain`, MS:327). Example: three displays, the selected secondary one is unplugged: mango → newest remaining, ours → menu-bar display. Not listed. (b) `gesture_drive_mon/active` is not reset (ours MS:94-95 keep pointing at the removed monitor until the gesture ends). (c) Clients move with `focus:false`, then one `clientFocus(top,true)`; same end state as mango's per-client `client_change_mon` plus the final client_focus. The oldmonname record matches. |
| handle_output_request_state monitor.c:1032 | none | platform | Nested backend. |
| create_output monitor.c:1061 | none | platform listed | Virtual outputs. |
| handle_output_layout_change monitor.c:1082 | MS:349 + rebuildMonitors | differs ✓ rettet i trin 5 | (a) A floating client on a monitor whose origin moved gets `geom += (Δx, Δy)` in mango; ours leaves `floatGeom` alone, and `keepOnDisplay` then clamps it. Example: move a display in System Settings → mango keeps the float in the same place on that display; ours puts it back at its old global coordinates, clamped. Unsure whether the port's move report updates floatGeom first. (b) Mango calls `client_focus(client_focus_top(selmon), 1)` on every layout change; ours only when monitors were added or removed (MS:338), so a resolution or scale change does not refocus or lift. (c) The fix-up for clients with `tags == 0 && !is_in_scratchpad` (tags = selmon's tagset + set_size_per) is missing. (d) Restoring by oldmonname runs only for added monitors; same result in practice. The fullscreen resize and per-monitor arrange are covered by `arrangeAll(.none)`. |
| handle_output_manager_apply monitor.c:1256 | none | platform | wlr-output-management; macOS arranges displays. |
| output_manager_apply_or_test monitor.c:1261 | none | platform | |
| handle_output_manager_test monitor.c:1328 | none | platform | |
| handle_output_power_manager_set_mode monitor.c:1333 | none | platform listed | DPMS (sleep_monitor etc. in unsupportedDispatchers). |
| monitor_stop_skip_frame_timer monitor.c:1347 | none | platform | |
| monitor_skip_frame_timeout_callback monitor.c:1355 | none | platform | |
| monitor_check_skip_frame_timeout monitor.c:1369 | none | platform | |
| handle_output_frame monitor.c:1382 | none (`frame_serial` → `Monitor.lastResizeTime`, CL:159) | platform listed §3 | Frames/animations through Accessibility. |
| check_vrr_enable monitor.c:1448 | none | platform listed | vrr_only_fullscreen. |
| do_renderer_recreate monitor.c:1486 (static) | none | platform | |
| handle_renderer_lost monitor.c:1514 | none | platform | |
| setgaps monitor.c:1524 | DI:804 `setgaps(_:_:)` | 1:1 | Takes the monitor; its only caller passes selmon (DI:389). Only `incgaps` is bound in mango too. |
| INSIDEMON monitor.h:15 | inline IN:397 `m.screen.frame.contains(c.frame)`; MS:834 | differs ✓ rettet i trin 4 | Mango tests `c->geom` (with the border) against `c->mon->m`. Ours tests the frame without the border, against the monitor under the pointer. A scroller column whose border alone crosses the monitor edge: mango says not inside (scroller_focus_lock path), ours says inside. Minor. |
| GEOMINSIDEMON monitor.h:19 | Mango/Layout/Scroller.swift:198 `insideMon` | 1:1 name | |

### manage/misc.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| get_parent_process misc.c:123 | none | platform listed | Swallowing (`is_term`/`no_swallow` in MangoCompat). Unsure: macOS can read a process's ppid with sysctl `KERN_PROC_PID`; the listing says it cannot. |
| is_descendant_process misc.c:144 | none | platform listed | Same as above. |
| get_layout_abbr misc.c:151 (+ layout_mappings table) | none | missing åben: ikke der, mærket udeladt i manage/misc.swift:3; som mangel i afvigelser.md §4 | Has no caller in mango. |
| client_at_point misc.c:202 | IN:104 (overview branch: `ovCards.first { contains }`) | port listed §5 | Mango walks server.clients in order; ours walks a dictionary in no fixed order. Same result while overview cards do not overlap. |
| layer_ignores_focus misc.c:214 | none | platform listed | Layer shell. |
| node_at_point misc.c:223 | IN:101 `clientAtPoint`, IN:114 `surfaceAt`, bars via `BarButton` | differs, listed §5 åben: manage/misc.swift:19 giver første flydende i `clients`-rækkefølge, før fullscreen/overlay | §5 lists the written-out order. Two consequences not stated there: (1) among overlapping floating windows ours returns the first in the `clients` (tiling) order; mango returns the topmost in the scene. Example: float B opened after float A and over it; pointer on the overlap: mango B, ours A (sloppy focus, click focus and `moveresize` pick A). (2) Mango's layer order puts LyrFullscreen and LyrOverlay above LyrFloat; ours checks floats and scratchpads first. Example: a fullscreen client covering a float: mango returns the fullscreen client, ours the hidden float. |
| check_idle_inhibitor misc.c:330 | none | platform listed | Idle. |
| handle_xdg_decoration_destroy misc.c:361 | none | platform listed | allow_csd. |
| handle_new_xdg_decoration misc.c:369 | none | platform listed | |
| handle_new_idle_inhibitor misc.c:382 | none | platform listed | |
| session_lock_focus_target misc.c:390 (static) | none | platform listed | Session lock (allow_lock_transparent). |
| session_lock_focus_restore misc.c:409 | none | platform listed | |
| session_lock_focus_missing misc.c:422 | none | platform listed | |
| handle_session_lock_new_surface misc.c:433 | none | platform listed | |
| handle_idle_inhibitor_destroy misc.c:453 | none | platform listed | |
| session_lock_cleanup misc.c:462 | none | platform listed | |
| handle_session_lock_surface_destroy misc.c:487 | none | platform listed | |
| handle_session_lock_surface_commit misc.c:510 | none | platform listed | |
| handle_session_lock_destroy misc.c:527 | none | platform listed | |
| handle_new_session_lock misc.c:532 | none | platform listed | |
| handle_new_foreign_toplevel_capture_request misc.c:558 | none | platform listed | shield_when_capture. |
| handle_session_destroy misc.c:582 | none | platform listed | |
| capture_source_format_supported misc.c:605 (static) | none | platform | |
| capture_source_add_shm_format misc.c:622 (static) | none | platform | |
| capture_session_announce_bgr_shm_formats misc.c:644 (static) | none | platform | |
| handle_ext_image_copy_capture_new_session misc.c:678 | none | platform listed | |
| handle_xdg_decoration_mode_request misc.c:710 | none | platform listed | allow_csd. |
| handle_drm_lease_request misc.c:729 | none | platform | DRM lease (VR). |
| handle_request_set_primary_selection misc.c:739 | none | platform listed | disable_middle_paste. |
| apply_primary_selection misc.c:752 | none | platform listed | |
| handle_primary_selection_policy_destroy misc.c:766 (static) | none | platform | |
| primary_selection_policy misc.c:775 (static) | none | platform | |
| mango_global_filter misc.c:792 | none | platform | |
| handle_request_set_selection misc.c:811 | none | platform | macOS pasteboard. |
| client_keep_idle_inhibit misc.c:821 (static) | none | platform listed | idle_inhibit_when_focus / idle_inhibit_when_fullscreen. Unsure "cannot": an IOPMAssertion could keep the display awake. |
| check_keep_idle_inhibit misc.c:836 | none | platform listed | |
| idle_keep_inhibit misc.c:842 | none | platform listed | |
| handle_session_lock_unlock misc.c:866 | none | platform listed | |

### manage/layer.c (layer shell and xdg popups: MangoCompat "Layer surfaces", `layer_rule`; §3 "popups aldrig"; §5 "Lag-flader og IM-popups har macOS ikke")

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| arrange_layer layer.c:22 | none | platform listed | |
| layer_focus layer.c:44 | none | platform listed | |
| reset_exclusive_layers_focus layer.c:55 | none | platform listed | |
| arrange_layers layer.c:112 | `Screen.workArea` (macOS visibleFrame, Port/macOS/Screens.swift:27) | port listed §3 | `m->w` (the usable area) is macOS's, with the menu bar and Dock as exclusive zones. |
| iter_layer_scene_buffers layer.c:159 | none | platform listed | Blur. |
| layer_blur_uses_wallpaper layer.c:176 | none | platform listed | |
| layer_flush_blur_background layer.c:183 | none | platform listed | |
| handle_layer_surface_map layer.c:197 | none | platform listed | `last_open_surface` is always empty (§3). |
| handle_layer_surface_commit layer.c:276 | none | platform listed | |
| popup_unconstrain layer.c:389 | none | platform listed | |
| handle_popup_destroy layer.c:435 | none | platform listed | |
| handle_popup_commit layer.c:448 | none | platform listed | |
| handle_popup_reposition layer.c:483 | none | platform listed | |
| handle_new_xdg_popup layer.c:488 | none | platform listed | |
| handle_new_layer_surface layer.c:507 | none | platform listed | |
| handle_layer_node_destroy layer.c:554 | none | platform listed | |
| handle_layer_surface_unmap layer.c:566 | none | platform listed | |

### manage/tab.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| tab_member_count tab.c:13 (static var) | none | 1:1 | Only lets mango skip work early; same result. |
| tab_head tab.c:15 (static) | `tabMembers(m).first` | port listed §5 | The chain is derived on each arrange (§5 "Faner"). |
| tab_is_member tab.c:19 (static) | `tabMembers(m).contains` | port listed §5 | |
| tab_bar_set_enabled tab.c:23 (static) | port draws or omits the strip (`system.drawTabBars`) | port | |
| tab_chain_focus tab.c:29 (static) | TB:32 | 1:1 | |
| tab_leave tab.c:46 (static) | none | port listed §5 | Derived chain. |
| tab_layout_id_supported tab.c:54 (static) | TB:4 | 1:1 | |
| tab_layout_enabled tab.c:62 (static) | TB:10 | 1:1 | |
| tab_layout_active tab.c:68 | TB:12 | 1:1 | |
| tab_state_ok tab.c:72 (static) | TB:14 | 1:1 | `iskilling` has no counterpart here. |
| tab_is_stack_candidate tab.c:80 (static) | TB:19 | 1:1 | |
| tab_member_kept tab.c:89 (static) | TB:26 `tabMembers` (marked) | differs ✓ rettet i trin 5 | `tabMembers` returns [] when `config.tabBarHeight <= 0`. Mango's chain does not depend on tab_bar_height (only `client_add_tab_bar` and the tile reservation do; the option is clamped 0..500, so 0 is legal). With `tab_bar_height=0` and monocle_tab_mode/deck_tab_mode (default 1), mango still chains the stack, hides the non-focused members (`is_tab_hidden`) and uses tab semantics in client_is_in_same_stack; ours forms no chain. Example: deck, tab_bar_height=0: mango shows only the focused stack window; ours leaves all of them stacked and visible. |
| tab_member_in_view tab.c:94 (static) | via `visibleClients` in tabMembers | 1:1 name | |
| tab_focus_can_render tab.c:98 (static) | inline TB:145 | 1:1 name | |
| tab_refresh_bars tab.c:102 (static) | MS:450-454 (`isTabHidden`) + TB:70 `tabRefreshBars` | port listed §5 | Reparenting the bar to the focus layer is the port's restack. |
| tab_update_input_penetration tab.c:138 | none (no strip, no panel) | port | |
| tab_sync_focus tab.c:164 | `tabChainFocus` from `sel` on each draw | port listed §5 | §5 client_focus row. |
| tab_detach_client tab.c:175 | none (derived) | port listed §5 | |
| tab_replace_client tab.c:197 | none; `clientReplace` (Mango/Engine/Groups.swift:73) does not move `isTabFocus` | differs ✓ rettet i trin 5 | Mango gives the replacing group member the old member's `is_tab_focus`/`is_tab_hidden`. Ours falls back to sel, then an existing `isTabFocus`, then the first member. Example: monocle tab chain [A, G1(tab focus)] on a monitor that is not selected; G1 closes and its parked group member G2 replaces it: mango shows G2, ours shows A. Unsure: an edge case. |
| tab_sync_monitor tab.c:231 | MS:450-454 + `tabMembers` | differs ✓ rettet i trin 5 | The tab_bar_height gate described under tab_member_kept. Otherwise same membership (current tagset, tab_state_ok, stack candidate, ≥2 members) and the same `is_tab_hidden` clearing. |
| tab_focus_member tab.c:291 | TB:216 | 1:1 | Mango's member guard is not needed, since callers pass only members. `arrange(m, .none)` gives the same result as mango's arrange(false,false) here: only hidden/shown members change. |
| client_raise_tab tab.c:299 | MS:821 | 1:1 | Placing the bar on top is the port's restack (§3 row 79). |
| client_reparent_tab tab.c:313 | none (restack) | port listed §5 | "Lag". |
| client_add_tab_bar tab.c:333 | Port/macOS/TabBars.swift | port | |
| client_remove_tab_bar tab.c:347 | port | port | |
| client_update_tab_bar_title tab.c:354 | MS:1313 → `tabRefreshBars` | port | |
| client_set_tab_bar_config tab.c:364 | none (drawn from config) | port listed §5 | reset_option row. |
| global_draw_tab_bar tab.c:370 | TB:130 `barSegments` (marked) | port listed §5 | |
| client_draw_tabbar tab.c:379 | TB:142 | 1:1, listed §5 | When the strip is clipped away entirely, ours draws none; mango leaves its bars where they were (listed). |

### manage/xwayland_primary.c (Xwayland: MangoCompat "Xwayland" group; monitor_rule)

| mango (file:line) | ours | status | note |
|---|---|---|---|
| xwayland_server_running :37 (static) | none | platform listed | X11 |
| xwayland_primary_unwatch :44 (static) | none | platform listed | |
| xwayland_primary_watch :51 (static) | none | platform listed | |
| xwayland_primary_close :61 (static) | none | platform listed | |
| xwayland_primary_connect :82 (static) | none | platform listed | |
| xwayland_primary_build_cache :108 (static) | none | platform listed | |
| xwayland_primary_apply :119 (static) | none | platform listed | |
| xwayland_primary_start :161 (static) | none | platform listed | |
| xwayland_primary_ready :181 (static) | none | platform listed | |
| xwayland_primary_rule_monitor :255 (static) | none | platform listed | |
| xwayland_primary_set :299 (static) | none | platform listed | |
| xwayland_primary_init :324 | none | platform listed | |
| xwayland_primary_update :341 | none | platform listed | |

### main.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| restore_nofile_limit main.c:136 (static) | none | missing åben: mangler, ikke listet | Not user-visible. |
| increase_nofile_limit main.c:145 (static) | none | missing åben: mangler; som mangel i afvigelser.md §4 | Raises the soft RLIMIT_NOFILE to the hard limit; macOS could do this. Not user-visible. |
| handle_signal main.c:167 | MangoApp/main.swift:557 (SIGTERM/SIGINT/SIGHUP → terminate); Foundation's Process reaps children | port | |
| restore_child_signals main.c:175 (static) | none | platform | Spawning goes through Foundation's Process. |
| cleanup_listeners main.c:185 | none | platform | |
| cleanup main.c:241 | MS:144 | 1:1 | Mango's own steps (ipc_cleanup → config_watcher_destroy → config_error_nag_destroy) run in mango's order. The rest is wlroots, except killing `child_pid`, which ours lacks because there is no `-s`. |
| handle_quit_signal main.c:278 | signal sources, MangoApp/main.swift:557 | port | |
| set_activation_env main.c:292 (+ env_vars) | none | platform | dbus/systemd session. |
| unset_activation_env main.c:336 | none | platform | |
| run main.c:389 | MS:134-141 ("run's part of the start, in setup") | differs, partly listed §5 åben: startskærmen er mangos linje (Engine/MangoServer.swift:150, §5); `-s`, stdout ikke-blokerende og readiness-fd mangler | §5 lists the order. Not listed: mango picks the initial `selected_monitor` with `monitor_at_point(cursor)`; ours uses the macOS main display (MS:327). Example: start with the pointer on a secondary display: mango selects it; ours selects the menu-bar display, and new windows and focus go there. Also missing: `-s startup_cmd` (fork/setsid/sh -c with a stdin pipe), making stdout non-blocking, and the readiness fd write. |
| setup main.c:468 | MS:110 | differs åben: `XDG_CURRENT_DESKTOP` sættes ikke (Engine/MangoServer.swift:120); som mangel i afvigelser.md §4 | Missing: `setenv("XDG_CURRENT_DESKTOP","mango")`, so children of mango do not see it. `_JAVA_AWT_WM_NONREPARENTING` is X11 (platform). init_baked_points is listed §5. Mango runs ipc_init and config_watcher_init before outputs exist; ours runs them after rebuildMonitors (same result). Everything else is wlroots. |
| main main.c:943 | MangoApp/main.swift:464 | differs åben: `-s`/`-r` mangler (afvigelser.md §4); ukendte argumenter ignoreres, listet i §2 (MangoApp/main.swift:463-494) | `-s <command>` and `-r <fdnum>` are missing. Unknown options or stray arguments are silently ignored, where mango prints usage. `-p` prints extra port lists (accepted per CLAUDE.md). The `XDG_RUNTIME_DIR` check is platform (listed §3 IPC). Extra port options (`--list-ignored`, `--list-glance`, the already-running check) are outside the core. |

### common/log.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| mango_log_init log.c:9 | Mango/common/Log.swift:6 `mangoLogInit` | 1:1 | No callback parameter (wlroots). |
| mango_tag_color log.c:14 (static) | Log.swift:10 | 1:1 | |
| mango_tag_plain log.c:27 (static) | Log.swift:19 | 1:1 | |
| mango_emit log.c:40 (static) | Log.swift:28 | 1:1 | Text captured for the error store is not cut at 4096 bytes, as mango's vsnprintf buffer cuts it. |
| mango_error_impl log.c:85 (+ `mango_error` macro) | Log.swift:52 `mangoError` | 1:1 name | The macro and the impl are one Swift function (#fileID/#line). |
| mango_error_untagged log.c:94 | Log.swift:57 | 1:1 | |

### common/scene_node.c (all scene graph: platform, listed §5 "porten har ingen scene")

| mango (file:line) | ours | status | note |
|---|---|---|---|
| handle_scene_node_destroy :7 (static) | none | platform listed | |
| mango_scene_node_set :14 | none | platform listed | |
| mango_scene_node_find :41 | none | platform listed | |
| mango_scene_node_set_ignore_hit :50 | none | platform listed | |
| mango_scene_node_get_ignore_hit :58 | none | platform listed | |
| scene_node_size :67 (static) | none | platform listed | |
| scene_node_accepts_input :98 (static) | none | platform listed | |
| scene_node_contains_point :123 (static) | none | platform listed | |
| scene_node_search :140 (static) | none | platform listed | |
| mango_scene_node_at :186 | none (IN:101 writes out the order) | platform listed | |

### common/server.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| `struct MangoServer server = {…}` server.c:17 | MS:39 + fields | 1:1 | enable_gaps 1 → `enableGaps = true`; render_border → `renderBorder = true`; key_mode "default" → `keyMode = "default"`; tagmask is computed (marked, RU:7); child_pid has no counterpart (no `-s`). The listener table is platform. |

### common/util.c (+ util.h)

| mango (file:line) | ours | status | note |
|---|---|---|---|
| die util.c:17 | none | platform | C/wlroots fatal-error helper. |
| ecalloc util.c:34 | none | platform | C allocation. |
| utf8_strlcpy util.c:43 (static) | none | platform | Wayland string limit. |
| wayland_string_set util.c:52 | none | platform | foreign-toplevel/xdg strings. |
| fd_set_nonblock util.c:57 | none (IPC does its own fcntl, Mango/IPC/IPCServer.swift:281) | missing åben: mangler, ikke listet | Its only mango caller is `run` (stdout non-blocking, for `-s` scripts). Belongs with `-s`. |
| regex_match util.c:71 | inline `String.range(of:options:.regularExpression)` (RU:66, RU:130, RU:162, DI:1868) | differs, name ✓ listet: afvigelser.md §5 (fejlen logges nu, common/util.swift:44) | ICU instead of PCRE2 (UTF). An invalid pattern returns no match in both, but mango logs "PCRE2 error: … at offset N" and ours logs nothing. Syntax that only one of the two engines supports matches differently. |
| wl_list_append util.c:100 | Swift arrays | platform | libwayland list helper. |
| get_now_in_ms util.c:104 | inline clocks (CACurrentMediaTime, event times) | platform | C clock helper. |
| timespec_to_ms util.c:111 | none | platform | |
| join_strings util.c:115 | none | platform | Used only by activation env. |
| join_strings_with_suffix util.c:146 | none | platform | |
| string_printf util.c:179 | Swift interpolation | platform | |
| wl_list_swap util.c:197 | `Array.swapAt` | platform | |
| wl_list_safe_reinsert_prev util.c:229 | Array insert | platform | |
| wl_list_safe_reinsert_next util.c:242 | Array insert | platform | |

(util.h macros MANGO_MAX/MIN/GEZERO/LENGTH/END/LISTEN: helpers; Swift `max`/`min` inline.)

### Headers: types and struct fields (server.h, types.h, monitor.h)

| mango | ours | status | note |
|---|---|---|---|
| enum Lyr* (server.h:15) | MS:8 `enum Lyr` (`.bg` … `.block`, same order) | 1:1 name | |
| TAG0_MASK / TAGMASK (server.h:11-12) | RU:4 `TagMask.special`; RU:8 `TagMask.mask(forTagNum:)` (marked) | 1:1 name | |
| KeyMode {char mode[28]; bool isdefault} | MS:58 `keyMode: String` | 1:1 name | No 27-character cut-off. `isdefault` is derived from `== "default"`. |
| PERTAG_SLOTS (monitor.h:25) | CL:156 `Monitor.pertagSlots = 32` | 1:1 | |
| MangoServer.clients / focus_stack | MS:46 `clients`, MS:56 `focusStack` | 1:1 | Like mango, parked group members are not in `clients`; `clientsAll` (unmarked) adds them. |
| MangoServer.monitors | MS:45 | differs ✓ rettet i trin 5 | Order: newest-first in mango, left-to-right in ours (see handle_new_output). |
| MangoServer.selected_monitor / scene_geometry | `selectedMonitor` MS:57, `sceneGeometry` MS:626 (computed) | 1:1 | |
| grab_client, cursor_mode, resize_edge, grab_is_border_resize, grab_pointer_x/y | `grab: Grab?` (IN:3: `client`, `mode`, `resizeEdge`, `isBorderResize`, `grabPointer`) | 1:1 name | The fields are gathered in one struct. `grab_offset_x/y` has no field; Grab keeps `startMouse`/`startFrame` instead (pointer.c group to check). |
| drop_client, group_bar_hover, drop_to_group, group_bar_drag_* | `dragTile` MS:77, `groupBarDrag` tuple MS:81; hover and drop_to_group not found in the core | name / unsure | For the pointer.c group. |
| hover_resize_edge, hover_resize_floating, drag_begin_cursor_x/y, start_drag_window | MS:83, MS:84, MS:76, MS:74 | 1:1 name | |
| enable_gaps, render_border, scroller_focus_lock, cursor_hidden, tag_combo, cli_debug_log | MS:62, 63, 101, 82, 68, 66 | 1:1 | Bool for int32. |
| gesture_drive_mon/active, swipe_fingers/dx/dy | MS:94-95, MS:93, MS:91-92 | 1:1 | |
| axis_apply_time/dir | port's InputState (`axisTimeout`, IN:27) | port | |
| last_hold_keycode | Mango/Engine/Keyboard.swift:38 `KeyboardState.lastHoldKeycode` | 1:1 name | On the event-tap thread's state. |
| cli_config_path | MS:41 `configURL` | name | |
| tagmask | computed `TagMask.mask(forTagNum:)` | 1:1 (marked) | |
| hide_cursor_source | MS:85 `cursorHideTimerArmed` | name | |
| print_status_signal | `ipc?.notifyChanged()` + `onStateChange` (MS:841) | port | |
| child_pid | none | missing åben: mangler (hører til `-s`) | Goes with `-s`. |
| chvt_backup_tag/_monitor_name, allow_frame_scheduling, session_locked, locked_modifiers, exclusive_focus, active_capture_count, next_client_id, keep_idle_inhibit_source, all wlroots pointers and listeners | none | platform (chvt, session lock and capture are listed) | |
| baked_points_* | port animator | port listed §5 | |
| Monitor.m / Monitor.w | `screen.frame` / `screen.workArea` (Boundary/Screen.swift) | name | Boundary type. |
| Monitor.seltags, tagset, pertag, ovbk_current_tagset, ovbk_prev_tagset, sel, prevsel, isoverview, is_jump_mode, is_in_hotarea, ov_normal_mode, ov_tab_layout, special_empty_view, title_message_bar, carousel_anim_dir | CL:153-174 | 1:1 | sel/prevsel are ClientIDs. |
| Monitor.gappih/iv/oh/ov, special_gapp* | CL:161-162 `gaps`, `specialGaps` (Gaps ih/iv/oh/ov) | name | |
| Monitor.visible_clients, visible_tiling_clients, visible_scroll_tiling_clients, visible_fake_tiling_clients, hide_clients | none; counted on demand (`visibleClients(m).count`, `tiledClients(m).count`) | name | Computed in pre_calculate_before_arrange in mango (arrange group). |
| Monitor.frame_serial / last_resize_frame | CL:159 `lastResizeTime` (marked) | port listed §3 | |
| Monitor.last_open_surface | none (IPC empty) | platform listed §3 | |
| Monitor.only_sleep, blur, special_dim_rect, ext_group, iscleanuping, vrr/hdr/icc fields, lock surface, skip-frame fields, layers[4] | none | platform (vrr/hdr/icc listed under monitor_rule) | |
| Pertag.curtag / prevtag | CL:163-164 `Monitor.curtag` / `Monitor.prevTag` | name | Moved to Monitor. `prevTag` should be `prevtag` in mango's lowerCamelCase. |
| Pertag.nmasters, mfacts, scroller_default_proportion(_single), scroller_ignore_proportion_single | `pertag[i].settings.{nmaster, mfact, …}` (Mango/Layout/Layout.swift:105 PertagSettings) | name | One object per slot instead of mango's arrays per field. |
| Pertag.no_hide, no_render_border, open_as_floating | CL:140-142 | 1:1 | |
| Pertag.ltidxs / config_ltidxs | CL:137 `layout` / CL:143 `configLayout` (LayoutKind) | name | |
| Pertag.dwindle_root / scroller_state | `state.dwindleRoot` (DwindleTree) / `state.scrollerState` (ScrollerState), Layout.swift:177 | name | |
| types.h: Arg, Layout, DwindleNode, TagScrollerState, LayoutContext | `Dispatch`, `LayoutKind`, `DwindleTree`, `ScrollerState`, `LayoutInput` (unsure that this is the counterpart) | name | |
| types.h: ScrollerStackNode | none | listed §5 | Scroller columns kept in tag state. |
| types.h: MangoJumpLabel, MangoBarDecoration, Client, Monitor, Pertag, MangoServer | Boundary/MangoJumpLabel.swift, Boundary/MangoBarDecoration.swift, CL, MS | 1:1 | |
| types.h: InputDevice, Switch, KeyboardGroup, KeyboardShortcutsInhibitor, LayerSurface, Popup, SessionLock, PointerConstraint, SnapshotMetadata, LastCursor | none | platform | |

## Not in mango (in the Swift files looked at)

| ours (file:line) | marked? | note |
|---|---|---|
| MS:32 `enum ArrangeAnimation` (.none/.move/.tag) | no | Stands for mango's `want_animation`/`from_view` booleans plus resize's choice. One mango call, arrange(m,false,false), maps to `.move` in some places and `.none` in others (Tabs.swift:219, MangoServer). |
| MS:49 `clientsAll` | no | clients plus parked group members. |
| MS:62 `drawsOverlays`, MS:65 `started` | no | Gates for tests and start-up. |
| MS:303 `rebuildMonitors` | yes | Stands for handle_new_output, handle_output_destroy and monitor_close. |
| MS:361/366/373 `visibleClients` / `tiledClients` / `specialClients` | yes | |
| MS:380 `focused` | no | `selectedMonitor.sel` as a Client. |
| MS:390 `dragRefreshIntervalMs` | yes | mango 0.18.2. |
| MS:398 `arrangeAll` | yes | |
| MS:588 `clientCenterGeometry(_:_:in:)` (second variant) | yes | |
| MS:642 `frameDistance` | yes | |
| MS:677 `borderWidth` | yes | |
| MS:683 `updateBorders` | yes | |
| MS:717 `shownFrame` | yes | |
| MS:721 `clientDrawFrame` | no | Has mango's name but only calls updateBorders; mango's client_draw_frame steps animations. |
| MS:967 `layoutStateInsert` | yes | |
| MS:1177 `exitScrollerStack` | yes | |
| CL:5 `protocol PlatformWindow`, CL:44/48 `Client.frame` / `parked` | partly (isFloatType marked; parked listed §5) | |
| CL:126 `Client.appid`, CL:128 `isVisible(on:)` (VISIBLEON), CL:33 `scratchpadShown` (SCRATCHPAD_SHOWN), CL:63 `isGroupMember` (client_is_group_member) | no | Mango has these as a macro or helper under another name. |
| CL:153 `Monitor.screen`, CL:188-189 `Monitor.current` / `layout` | no | |
| TB:26 `tabMembers`, TB:40 `reserveTabStrip`, TB:52 `barsInsideBorder`, TB:93 `animationCurrent`, TB:114 `clipBar`, TB:130 `barSegments` | yes | |
| TB:61 `topBars` | no | |
| TB:57 `mangoBarDecorationApplyConfig` | no | Mango's name, but here it only merges DecorateStyle defaults; mango applies config to the bar node. |
| RU:47 `MonitorSpec.init(mango:)` | no (struct marked) | Parses match_monitor_spec's tokens once; lowercases and trims keys, unlike mango. |
| DI:1603 `parseMonitorArg` | no | Mango parses at config time into arg->i/arg->v. Holds monitor_from_cycle inline. |
| IN:101 `clientAtPoint`, IN:114 `surfaceAt`, IN:120 `clientGeom` | yes | |

## Summary

Counts (192 rows for functions and logic macros; struct fields are in their own table):
- 1:1: 34 (of these, 8 also carry `name`)
- differs: 16
- missing: 5 (2 have no caller in mango: is_centertile_layout and get_layout_abbr; plus the nofile pair and fd_set_nonblock)
- platform: 117 (most are listed; the unlisted ones are not user-visible: output management, DRM lease, renderer, scene, C helpers)
- port: 20

The 10 most significant deviations, most significant first:
1. **match_monitor_spec** (monitor.c:297): every caller (MS:877, DI:219/223/1611) passes only the display name. Specs with `make:`, `model:` or `serial:` never match in focusmon, tagmon, tagcrossmon or window_rule `monitor:`, although `Screen` has those values.
2. **node_at_point → clientAtPoint** (IN:101): overlapping floats return the first in tiling order, not the topmost. A float hidden under a fullscreen client (LyrFullscreen > LyrFloat in mango) is returned instead of the fullscreen client. This affects sloppy focus, click focus and moveresize. §5 lists the written-out order, but not these consequences.
3. **Tab chain gated on tab_bar_height > 0** (TB:27; tab_member_kept/tab_sync_monitor): with `tab_bar_height=0`, mango still chains, hides the non-focused monocle/deck members and applies tab rules in client_is_in_same_stack; ours forms no chain.
4. **Monitor list order** (handle_new_output): mango is newest-first, ours left-to-right. This changes `focusmon`/`tagmon next|prev` (monitor_from_cycle), the replacement for a removed selected monitor, and the IPC output order.
5. **Initial selected monitor** (run main.c:389): mango uses the monitor under the cursor; ours uses the macOS main display (MS:327). Not listed.
6. **monitor_close fallback** (monitor.c:975): a removed selected monitor is replaced by the macOS main display, not mango's first monitor in the list. gesture_drive_* is not reset.
7. **handle_output_layout_change** (monitor.c:1082): floats are not shifted when a display's origin moves; no `client_focus(top,1)` on geometry-only changes; the tags==0 client fix-up is missing.
8. **main/run CLI**: `-s <startup command>` (with child_pid kill in cleanup and non-blocking stdout) and `-r <readiness fd>` are missing; unknown options are ignored instead of printing usage; `XDG_CURRENT_DESKTOP=mango` is not set.
9. **monitor_at_point** (MS:355): returns the nearest monitor instead of NULL for points outside every display.
10. **get_tags_first_tag_num** (RU:30): no clamp to tag_num (a different pertag slot for tags beyond tag_num). Edge cases close behind: tab_replace_client does not carry `isTabFocus` (Groups.swift:73), and regex_match uses ICU with no "PCRE2 error" log.
