# A-client: src/manage/client.c, include/mango/manage/client.h

Paths: mango = `~/sources/mango`, ours = `~/sources/mangochutney/Sources`. `MS` = `Mango/Engine/MangoServer.swift`,
`D` = `Mango/Engine/Dispatch.swift`, `G` = `Mango/Engine/Groups.swift`, `T` = `Mango/Engine/Tabs.swift`,
`CL` = `Mango/Engine/Client.swift`, `WS` = `Boundary/WindowSystem.swift`.

Convention noted once (it touches many rows, it is marked on the field `CL:94-97`): our `floatGeom`/`geom` exclude
the border, mango's include it. Where only that shifts a number by `bw`, the row is still `1:1`.

## Functions

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| client.h:43 `ISTILED` | Input.swift:494 `isTiled`; `MS:366 tiledClients` | 1:1 | `tiledClients` adds `!scratchpadShown` (a shown scratchpad is always floating: same result) |
| client.h:46 `ISNORMAL` | none (inline) | 1:1 name | only used by `client_check_tab_node_visible`, where ours drops the `!isunglobal` part (see that row) |
| client.h:48 `ISSCROLLTILED` | Input.swift:499 `isScrollTiled` | 1:1 | |
| client.h:51 `ISFAKETILED` | inline filters (`MS:422`, D:942) | 1:1 name | |
| client.h:54 `VISIBLEON` | CL:128 `Client.isVisible(on:)` | 1:1 name | adds `!groupParked`; mango's parked member has `mon == NULL`, so same result |
| client.h:58 `TAGMATCH` | MS:759 nested `tagMatch` | 1:1 name | |
| client.h:61 `SCRATCHPAD_SHOWN` | CL:33 `scratchpadShown` | 1:1 name | |
| client.h:62 `ISFULLSCREEN` | inline `isFullscreen \|\| isMaximizeScreen` (MS:928, MS:1093, D:507) | 1:1 | the two overview `*bak` terms are dropped; every user then calls `clear_fullscreen_flag`, which only acts on `isfullscreen`/`ismaximizescreen`: same result |
| client.h:248-251 `CLIENT_*_OFF` | none | 1:1 name | offset chain helpers not needed; group chain has its own functions, tab chain is computed (listed §5) |
| client.c:61 `client_is_x11` | none | platform | no X11 |
| client.c:67 `client_surface` | none | platform | wl_surface |
| client.c:74 `client_uses_transparent_rendering` | none | platform | buffer alpha / alpha-modifier protocol |
| client.c:89 `toplevel_from_wlr_surface` | none | platform | surface tree lookup |
| client.c:153 `client_activate_surface` | WS:13, MacWindowSystem.swift:137 | port | |
| client.c:168 `client_get_appid` | CL:126 `appid` | port listed §3 | bundle id (or app name); "broken" fallback not needed |
| client.c:178 `get_client_tag_idx` | none; inline `getTagsFirstTagNum(c.tags) ?? m.getMonCurtag` (MS:1053, MS:1180, D:1641) or `m.layout` | differs | (1) for `tags == 0` (a minimized client) mango gives slot 0, ours the current tag (`clear_fullscreen_flag`, `exit_scroller_stack`, `client_reassign_monitor`). (2) Several callers use the monitor's current-tag layout (`m.layout`) where mango uses the client's own tag (`ltidxs[get_client_tag_idx(c)]`): `client_is_in_same_stack`, `get_focused_stack_client`, `client_exchange`, `client_replace`, `handle_client_unmap`'s scroller node. Scenario: view tags 1+2 (curtag 1, tile) with `sc` only on tag 2 (scroller): mango treats `sc` as scroller for focus-stack memory, ours as tile |
| client.c:184 `client_get_pid` | CL:14 `pid` | port | |
| client.c:193 `client_get_clip` | none | platform | xdg geometry clip |
| client.c:210 `client_surface_get_source_box` | none | platform | buffer transform |
| client.c:237 `client_get_geometry` | CL:44 `frame` | port | |
| client.c:255 `client_get_parent` | none | platform listed §3 | AX gives no parent; rule `\|\| parent` and parent's tags/monitor missing (§3 rows "client_is_float_type", "En dialog arver ikke") |
| client.c:270 `client_has_children` | none | platform | no callers in mango outside client.c either |
| client.c:280 `client_get_title` | CL:18 `title` | port | |
| client.c:289 `client_is_float_type` | MS:1044 -> `platform.isFloatType` | port listed §3 §5 | |
| client.c:328 `client_is_rendered_on_mon` | none | platform | surface outputs |
| client.c:341 `client_is_unmanaged` | none | platform | X11 override-redirect |
| client.c:348 `client_notify_enter` | WS:11, MacWindowSystem.swift:130 | port listed §3 | bound keys filtered by the port; §3 "Seatet" row |
| client.c:366 `client_send_close` | WS:77, MacWindowSystem.swift:620 | port | |
| client.c:375 `client_set_border_color` | MS:683 `updateBorders` (port overlay) | port | colours computed by `getBorderColor` per draw |
| client.c:379 `client_set_state_colors` | none | platform | dim colour (compat "Dimming"); border part = `updateBorders` |
| client.c:388 `client_notify_fullscreen` | WS:78, MacWindowSystem.swift:629 | port listed §3 | only with `chutney_fullscreen_tag` (§3 row 77) |
| client.c:401 `client_set_scale` | none | platform | fractional scale protocol |
| client.c:430 `xwayland_device_length` | none | platform | X11 |
| client.c:447 `xwayland_device_source_box` | none | platform | X11 |
| client.c:464 `client_update_xwayland_clip` | none | platform | X11 |
| client.c:571 `client_update_xwayland_dest_size` | none | platform | X11 |
| client.c:610 `client_set_size` | port `setFrame`/`resize` (WS:70-75) | port | identical-repeat skip is X11 |
| client.c:662 `client_set_minimized` | WS:44, MacWindowSystem.swift:598 | port | |
| client.c:674 `client_set_maximized` | none | platform | xdg maximized state (compat `force_fake_maximize`) |
| client.c:689 `client_set_tiled` | none | platform | xdg tiled state (compat `force_tiled_state`) |
| client.c:712 `client_sync_tiled_hint` | none | platform | as above |
| client.c:724 `client_should_ignore_focus` | none | platform | X11 hints |
| client.c:739 `client_is_x11_popup` | none | platform | X11 window types |
| client.c:768 `client_should_global` | none | platform | X11 sticky |
| client.c:781 `client_should_overtop` | none | platform | X11 above (no callers in mango) |
| client.c:793 `client_wants_focus` | none | platform listed §5 | X11 override-redirect |
| client.c:804 `client_wants_fullscreen` | none | platform listed §3 | macOS fullscreen is §3 rows 76-77 |
| client.c:812 `client_move_to_requested_fullscreen_output` | none | platform | xdg fullscreen_output |
| client.c:835 `client_request_minimize` | none | platform | event payload |
| client.c:847 `client_request_maximize` | none | platform | compat `ignore_maximize` |
| client.c:858 `client_set_size_bound` | none | platform listed §3 | app keeps its own min/max (§3 row 65, compat `no_size_hint`) |
| client.c:910 `check_hit_no_border` | MS:658 `checkHitNoBorder` | differs | `monocle_no_border` term: mango `ISFAKETILED(c)` (!floating, !minimized, !killing, !unglobal), ours only `!c.isFloating` (MS:672). Scenario: a `isunglobal` window in monocle with `monocle_no_border=1`: mango draws its border, ours hides it. (Counts are computed live, mango's are cached from the last arrange: same result) |
| client.c:941 `client_find_terminal` | none | platform listed (compat `is_term`, `no_swallow`) | |
| client.c:957 `get_client_by_id_or_title` | D:1866 (inline in `toggleNamedScratchpad`, marked `mango get_client_by_id_or_title`) | differs name | mango's "none" test is `strncmp(arg,"none",4)`: any argument *starting* with "none" means unset; ours only exactly "none" (plus "0"/"" which come from our arg parsing). App-name match is listed §3 row 85 |
| client.c:1001 `client_center_geometry` | MS:564 | 1:1 | mango's `cbw` (only when `check_hit_no_border`) is `c->bw`, which `resize` has just set to 0 in that case, so the clamp is the same; same result |
| client.c:1055 `is_window_rule_matches` | Rules.swift:127 | 1:1 listed §3 | app-name alternative listed §3 row 85, marked |
| client.c:1063 `center_tiled_select` | MS:1218 | 1:1 | takes the candidate list as `among:` (the caller's `scrollTiled`, same filter) |
| client.c:1085 `find_client_by_direction` | D:1478 | 1:1 | geometry via marked `directionGeom` (card in overview, as mango's `geom` there) |
| client.c:1233 `direction_select` | D:1463 | 1:1 | |
| client.c:1251 `client_focus_top` | MS:382 | 1:1 | |
| client.c:1267 `get_next_stack_client` | D:1406 | 1:1 | |
| client.c:1298 `get_border_color` | MS:646 | 1:1 | |
| client.c:1323 `get_dim_color` | none | platform | dimming (compat "Dimming") |
| client.c:1332 `is_single_bit_set` | D:500 inline `nonzeroBitCount == 1` | 1:1 name | |
| client.c:1334 `client_only_in_one_tag` | D:498 | 1:1 | |
| client.c:1345 `client_is_in_same_stack` | D:1532 | differs | layout from `m.layout` (current tag), mango from `sc`'s own tag (see `get_client_tag_idx`); tile-family tab test is `tabMembers(m).contains(tc)` for `tc->tab_prev\|\|tab_next` (tab chain listed §5) |
| client.c:1399 `dwindle_node_depth` | Dwindle.swift:39 nested `depth` | 1:1 name | |
| client.c:1406 `dwindle_node_lca` | Dwindle.swift:40-44 inline | 1:1 name | |
| client.c:1433 `dwindle_focus_block_root` | Dwindle.swift:37 `dwindleFocusBlockRoot` | 1:1 | returns the branch's clients as a Set; root of the current tag (see `get_client_tag_idx`) |
| client.c:1453 `dwindle_focus_block_has_client` | D:1566 `block.contains` | 1:1 name | |
| client.c:1462 `get_focused_stack_client` | D:1560 | differs | dwindle test uses `m.layout`, mango `sc`'s tag layout (see `get_client_tag_idx`); otherwise 1:1 (nil `fc` returns `sc` where mango would crash) |
| client.c:1508 `apply_rule_properties` | MS:944 | differs | all missing fields are listed in compatibility.md (opacity, blur, shadow, swallow, size hints, csd, tearing, …). Two differences: (1) `scroller_proportion`/`_single` are applied when the rule gives any value (MS:960-961); mango's `APPLY_FLOAT_PROP` only when `> 0`. Scenario: `windowrule=scroller_proportion:0,…` sets 0 in ours, mango keeps the default. (2) `no_radius` is listed "impossible", but the port draws mango's border with `border_radius` (`MS:701`), so mango's `no_radius` would apply to it |
| client.c:1552 `set_float_malposition` | MS:1200 | 1:1 | |
| client.c:1597 `client_reset_mon_tags` | MS:1029 | 1:1 | its doc line ("Not in mango: the port's overview leaves the tags in view…") is stale: the code uses `ovbkCurrentTagset` as mango does |
| client.c:1611 `check_match_tag_floating_rule` | MS:1038 | 1:1 | `!c->swallowing` n/a |
| client.c:1618 `client_set_rules` | MS:861 | differs listed §3 | listed: parent (`\|\| parent`, parent tags/monitor), swallow (compat), fake fullscreen's `client_notify_fullscreen` (§3 row 77). Not done, same result: the second `client_set_fullscreen(c, backup, true)` after the view (ours relies on `client_set_monitor`'s call), `old_*_inner_per` saves (refreshed before every use in arrange.c:139-162), fs_mon (xdg). Extra, marked: off-monitor floating window centred (MS:901), `layoutStateInsert`, `mapped:` |
| client.c:1841 `apply_window_snap` | FloatingSnap.swift:31 | differs | mango snaps the outer border edge only when the border is really drawn (`cbw` from `c->bw`, 0 when `check_hit_no_border`); ours uses `config.borderpx` whenever `renderBorder` (FloatingSnap.swift:34). Scenario: `no_border_when_single=1`, one floating window: mango snaps the window to the screen edge, ours leaves a `borderpx` gap |
| client.c:1947 `client_update_geometry` | none | platform | X11 |
| client.c:1962 `client_init_xwayland` | none | platform | X11 |
| client.c:1988 `client_init_unmanaged` | none | platform | X11 |
| client.c:2021 `client_set_xwayland` | none | platform | X11 |
| client.c:2034 `xwayland_scene_buffer_point_accepts_input` | none | platform | X11 |
| client.c:2055 `handle_new_xdg_toplevel` | MacEvents.swift:5 `windowDiscovered` | port | |
| client.c:2086 `init_client_properties` | CL:12-123 (initial values) | 1:1 | defaults match where the field exists (`ignoreMinimize = true`, grid per 1, `isPendingOpenAnimation`); `scroller_proportion` default comes later from `set_size_per`; rendering fields absent (platform) |
| client.c:2226 `client_insert_tiling_order` | MS:1183 | 1:1 | `visible_scroll_tiling_clients > 0` as "any scroll-tiled visible client" (same for the test) |
| client.c:2252 `client_configure_size` | none | platform | xdg initial configure |
| client.c:2260 `client_negotiate_initial_size` | none | platform | xdg initial configure (layout `predict`) |
| client.c:2319 `handle_client_map` | MS:847 | 1:1 | scene/border/shadow nodes are the port's; `overview_backup_surface` for a window mapped in overview is the §6 row; `resize` is the arrange |
| client.c:2464 `client_xdg_size_pending` | none | platform | |
| client.c:2471 `handle_client_commit` | none (port reads frames) | platform | initial-commit rules pass = port's `mapInitial` (MacEvents.swift:32) |
| client.c:2553 `handle_client_unmap` | MS:1227 | 1:1 | fade-out listed §3 row 69; swallow compat; tab detach n/a (§5). Ours arranges before choosing focus, mango after (`client_set_monitor(c,NULL,…)`), then focuses `client_focus_top` again: same result. `pointer_process_motion(0,…)` at the end is not called (unsure: only cursor image / pointer focus, which macOS owns) |
| client.c:2722 `handle_client_destroy` | MS:1280 | 1:1 | `pointer_client_destroyed` not called; `confinePointerLast` holds an id, same result |
| client.c:2758 `handle_client_request_fullscreen` | FullscreenTag.swift:105 (extension) | port listed §3 | §3 rows 76-77 |
| client.c:2769 `handle_client_request_maximize` | none | platform listed (compat `ignore_maximize`) | |
| client.c:2788 `handle_client_request_minimize` | MS:1303 | 1:1 listed §3 | `client_set_minimized` is the port's (§3 row 76) |
| client.c:2806 `handle_client_set_title` | MS:1311 | 1:1 | bar titles via `tabRefreshBars` |
| client.c:2834 `handle_client_activation_request` | MS:1284 | differs | mango returns when `!c->foreign_toplevel`, which is the case for a parked group member (`client_replace` destroys `w`'s handle); ours (guard `clientByIdAll`, which includes parked members) goes on and swaps it in. Scenario: macOS activates a parked member's window (its app brings it forward): mango ignores it, ours shows it in the group's place. Otherwise 1:1 |
| client.c:2862 `pending_kill_client` | Input.swift:125 | 1:1 | |
| client.c:2868 `client_blur_uses_wallpaper` | none | platform | blur (compat) |
| client.c:2875 `client_sync_blur_optimized` | none | platform | blur |
| client.c:2882 `iter_xdg_scene_buffers` | none | platform | blur |
| client.c:2902 `scene_buffer_apply_opacity` | none | platform | opacity (compat) |
| client.c:2907 `client_set_opacity` | none | platform | opacity (compat) |
| client.c:2913 `client_ensure_constraint` | none | platform | pointer-constraints protocol |
| client.c:2927 `client_focus` | MS:725 | 1:1 listed §5 | the omissions are §5's list. Extra (marked, "client_active's step"): a parked group member is swapped in first (MS:734); see `client_active` |
| client.c:3108 `client_active` | D:543 | differs | missing first step `if (!c->mon && !client_group_swap_focus(c)) return;` (moved into `clientFocus`, which runs last). Scenario: group A (shown) + B (parked); A was moved to tag 3. `mmsg dispatch focusid <B>` (mango `focus_by_id`; also our launch_or_focus): mango swaps B in first (B takes A's tags 3) and views tag 3; ours views B's stale tags (tag 1), then swaps B in on tag 3 while tag 1 is shown. Same for the scratchpad/minimized tests, which read B's stale fields |
| client.c:3149 `client_view_on_monitor` | D:592 | 1:1 | also does arrange's `from_view` `set_size_per` for global/multi-tag clients here (D:622, unmarked; arrange.c's part, for group B) |
| client.c:3210 `client_switch_view` | D:518 | 1:1 | |
| client.c:3227 `tag_client` | D:503 | 1:1 | `client_reparent_group` listed §5 |
| client.c:3254 `show_hide_client` | D:1792 | 1:1 | extra marked `clientSetMinimized` (port) |
| client.c:3277 `client_set_monitor` | MS:1011 | 1:1 | `reset_foreign_toplevel` platform; `resize` is the arrange |
| client.c:3316 `client_adapt_geometry_to_monitor` | MS:973 | 1:1 | |
| client.c:3330 `client_set_monitor_adapted` | MS:983 | 1:1 | extra marked `parked = false` |
| client.c:3350 `client_change_mon` | MS:341 | differs | (1) re-centres `floatGeom`; mango centres `c->geom` into both (a floating window in fullscreen/maximize gets that size as its float size in mango). (2) extra `focus:` parameter (unmarked); `rebuildMonitors` passes `false` where mango's `monitor_close` focuses per client |
| client.c:3358 `view_insert_shift_tags` | D:742 | 1:1 | ours also remaps parked members' tags (mango skips them, `mon == NULL`); `client_replace` copies tags on unpark: same result |
| client.c:3400 `client_set_floating` | MS:1065 | 1:1 | `need_float_size_reduce` unused; `old_*_inner_per` same result; `client_set_maximized`/`sync_tiled_hint` platform; extra marked off-monitor centring |
| client.c:3486 `client_set_fullscreen` | MS:1101 | 1:1 | bw/vrr/idle platform; resize is the arrange |
| client.c:3532 `client_set_fake_fullscreen` | MS:1116 | differs listed §3 | no `client_notify_fullscreen(c, fake)` (§3 row 77) |
| client.c:3543 `maximize_screen_gaps` | MS:510-512 inline | 1:1 name | arrange returns early in overview, so the `!isoverview` term holds |
| client.c:3553 `client_set_maximize_screen` | MS:1122 | 1:1 | box computed in arrange (MS:508-518) |
| client.c:3607 `reset_maximizescreen_size` | MS:508-518 inline in `arrange` | 1:1 name | |
| client.c:3626 `set_minimized` | D:1774 | 1:1 | |
| client.c:3653 `unminimize` | none | missing | only caller is `handle_client_request_minimize`'s else branch, which is unreachable (it returns on `isminimized` first): no observable effect |
| client.c:3683 `exit_scroller_stack` | MS:1178 -> Scroller.swift:53 | differs listed §5 | port's columns (marked). Mango removes the node in every case (copying its proportions back to the client); ours only splits a multi-window column and keeps a single column's entry (unsure whether visible: position is then the port's) |
| client.c:3701 `clear_fullscreen_and_maximized_state` | MS:1059 | 1:1 | |
| client.c:3711 `clear_fullscreen_flag` | MS:1051 | 1:1 | tags==0 fallback under `get_client_tag_idx` |
| client.c:3728 `client_pending_fullscreen_state` | field writes | 1:1 name | foreign toplevel platform |
| client.c:3736 `client_pending_maximized_state` | field writes | 1:1 name | |
| client.c:3743 `client_pending_minimized_state` | field writes | 1:1 name | |
| client.c:3750 `show_scratchpad` | D:1808 | 1:1 | |
| client.c:3778 `switch_scratchpad_client_state` | D:1828 | 1:1 | `scratchpad_switching_mon` is an animation flag (port) |
| client.c:3830 `apply_named_scratchpad` | D:1882 | 1:1 | |
| client.c:3852 `client_update_border_color` | MS:683 `updateBorders` | port | |
| client.c:3865 `client_add_dim_node` | none | platform | dimming |
| client.c:3875 `client_exchange` | D:1342 | 1:1 | layouts from `m.layout` (see `get_client_tag_idx`); scroller/dwindle branches re-implement scroll.c/dwindle.c (their groups) |
| client.c:3908 `client_is_parked` | CL:62 `groupParked` | 1:1 name | a flag, unmarked |
| client.c:3910 `client_unlink` | G:141-142, MS:1255-1257 inline | 1:1 name | |
| client.c:3919 `client_park` | G:139 | differs | keeps `c.mon` (mango sets `c->mon = NULL`; `animation.running = false` is the port's). Scenario: a group moved to monitor 2 by its shown member; `mmsg get all-clients` reports the parked members on monitor 1 (IPCJSON.swift:173), mango (`client_output_name` -> `client_group_active`) on monitor 2 |
| client.c:3929 `client_unpark` | G:145 | differs | no focus-stack part and no "parked without anchor -> tail + focus head" branch; `clientReplace` re-inserts c before w in the focus stack itself (same result there); `clientGroupLeave` puts c right after rc (bind.c's own reinsert: its group) |
| client.c:3942 `client_replace` | G:73 | 1:1 | scene/bar/card/foreign parts are the port's; tab chain listed §5; layout from `m.layout` (see `get_client_tag_idx`); always parks `w` (mango unlinks a killing `w`, same result: the unmap removes it) |
| client.c:4060 `monitor_move_direction` | D:1628 | 1:1 | |
| client.c:4078 `client_reassign_monitor` | D:1637 | 1:1 | extra: scroller node removed from the old tag (D:1641, unmarked; port's column state), marked `parked = false` |
| client.c:4096 `client_jump_to_monitor` | D:1650 | 1:1 | |
| client.c:4111 `client_move_to_monitor` | D:1659 | differs | along the scroller axis mango inserts c before the target column's head / after its tail in `clients`; ours beside the target itself (D:1683; marked "the port's scroller columns" on the column part only) |
| client.c:4156 `client_update_oldmonname_record` | MS:1046 | 1:1 listed §5 | display ID; no iskilling/mapped test (marked) |
| client.c:4164 `client_set_bounds` | MS:629 | 1:1 | returns the frame (marked) |
| client.c:4179 `client_swap_layout_properties` | D:1348 nested `swapLayoutProperties` | 1:1 name | |
| client.c:4216 `client_swap_monitors_and_tags` | D:1359 nested `swapMonitorsAndTags` | 1:1 name | |
| client.c:4225 `finish_exchange_arrange_and_focus` | D:1392-1396 inline | 1:1 name | |
| client.c:4240 `client_tile_resize` | MS:489-495, T:40 `reserveTabStrip` (marked) | port | bar strips cut from the layout's frames. Unmarked extra guard `f.height > h` (MS:491, T:45): a tile not taller than the bar is left whole, mango cuts it (then `client_set_bounds`) |
| client.c:4268 `generate_client_id` | CGWindowID | port | |
| client.c:4270 `client_gesture_driven` | Animation.swift:27 | 1:1 | |
| client.c:4277 `client_should_visible` | port `hide`/`parked` | port | scene enable = parking (§3) |
| client.c:4318 `client_update_input_penetration` | none | platform | scene hit flags |
| client.c:4323 `client_update_visibility` | port `hide` | port | |
| client.c:4341 `client_pending_force_kill` | D:250 inline `kill(c.pid, SIGKILL)` | 1:1 name | |
| client.c:4347 `client_add_jump_label_node` | G:118 | 1:1 | node made by the port (marked) |
| client.c:4362 `client_target_layer` | MS:1138 | 1:1 | |
| client.c:4398 `client_sync_layer` | none | port listed §5 | `restack` |
| client.c:4407 `client_wants_group_bar` | G:161 | 1:1 | extra `groupBarHeight > 0`: with height 0 mango makes no bar and cuts 0 px: same result |
| client.c:4415 `client_add_group_bar` | none | port listed §5 | drawn by the port |
| client.c:4434 `client_update_group_bar_title` | `tabRefreshBars` | port listed §5 | |
| client.c:4444 `client_set_group_bar_config` | none | port listed §5 | |
| client.c:4452 `client_remove_group_bar` | none | port listed §5 | `groupBarDrag` is guarded on use (Input.swift:352): same result |
| client.c:4465 `client_group_swap_focus` | G:62 | 1:1 | |
| client.c:4491 `client_focus_group_member` | G:55 | 1:1 | |
| client.c:4500 `client_check_tab_node_visible` | T:65 (returns Bool; the port draws, §5) | differs | `show` needs `TAGMATCH && ISNORMAL` (so not `isunglobal`); ours `isVisible` (VISIBLEON) with no unglobal test. Scenario: `always_show_group_bar=1` and an `isunglobal` window: mango shows no group bar, ours does |
| client.c:4530 `client_raise_group` | MS:810 | 1:1 listed §3 | a parked member is not raised (§3 row 79) |
| client.c:4544 `client_reparent_group` | none | port listed §5 | `restack` |
| client.c:4566 `client_handle_decorate_click` | T:206 | 1:1 | |
| client.c:4580 `client_set_group_mon` | none; `rebuildMonitors` MS:329 loops `clientsAll` | differs | mango moves only unparked members (parked have `mon == NULL`); ours moves parked ones too. Follows from `client_park` keeping `mon`; no visible effect found |
| client.c:4589 `client_set_group_config` | G:109 | 1:1 | drop area / split / bar colours drawn by the port (marked) |
| client.c:4602 `client_chain_head` | G:4 `clientGroupHead` | 1:1 name | |
| client.c:4615 `client_group_head` | G:4 | 1:1 | |
| client.c:4619 `client_is_group_member` | CL:63 `isGroupMember` | 1:1 name | |
| client.c:4623 `client_group_focused` | G:64 inline `first { isGroupFocus }` | 1:1 name | |
| client.c:4630 `client_group_active` | none | differs | used by mango for a parked member's output (ipc.c:574) and bar hit owner (pointer.c:1174); ours reads the parked member's own `mon` (see `client_park`) |
| client.c:4639 `client_chain_unlink` | G:153-156 inline | 1:1 name | |
| client.c:4652 `client_group_mark_dirty` | none | platform | output flush |
| client.c:4657 `client_group_detach` | G:152 | 1:1 | |
| client.c:4668 `client_group_replace` | G:128 | 1:1 | |
| client.c:4689 `mango_surface_frame_done` | none | platform | frame callbacks |
| client.c:4699 `client_send_frame_done` | none | platform | |
| client.c:4706 `client_force_render` | none | platform | compat `force_render` |
| client.c:4722 `xwayland_monitor` | none | platform | X11 |
| client.c:4731 `xwayland_client_scale` | none | platform | X11 |
| client.c:4741 `xwayland_preferred_scale` | none | platform | X11 |
| client.c:4749 `xwayland_apply_scale` | none | platform | X11 |
| client.c:4762 `xwayland_screen_origin` | none | platform | X11 |
| client.c:4768 `xwayland_logical_to_x11` | none | platform | X11 |
| client.c:4780 `xwayland_x11_to_logical` | none | platform | X11 |
| client.c:4794 `client_get_x11_geometry` | none | platform | X11 |
| client.c:4817 `fix_xwayland_coordinate` | none | platform | X11 |
| client.c:4836 `handle_xwayland_surface_request_activate` | none | platform | X11 |
| client.c:4894 `handle_xwayland_surface_request_configure` | none | platform | X11 |
| client.c:4961 `handle_new_xwayland_surface` | none | platform | X11 |
| client.c:4992 `handle_xwayland_surface_commit` | none | platform | X11 |
| client.c:5015 `handle_xwayland_surface_associate` | none | platform | X11 |
| client.c:5032 `handle_xwayland_surface_dissociate` | none | platform | X11 |
| client.c:5041 `handle_xwayland_surface_set_hints` | none | platform | X11 |
| client.c:5056 `handle_xwayland_ready` | none | platform | X11 |
| client.c:5086 `handle_xwayland_surface_set_geometry` | none | platform | X11 |

## Not in mango (in the Swift files looked at)

| ours (file:line) | marked? | note |
|---|---|---|
| MS:49 `clientsAll` | no | `clients` plus parked group members; mango's `server.clients` never holds parked ones |
| G:10 `groupMembers` | no | chain as a list (helper) |
| G:17 `clientGroupJoin`, G:33 `clientGroupLeave`, G:48 `groupFocus` | n/a | mango's bind.c (`client_group_join`, `client_group_leave`, `group_focus`): another group |
| CL:62 `groupParked` | no | stands for `client_is_parked` (empty `link`); keeps `mon` (see `client_park`) |
| CL:128 `isVisible(on:)` `!groupParked` term | no | same result as VISIBLEON |
| MS:734 group swap inside `clientFocus` | yes | `client_active`'s first step moved; causes the `client_active` deviation |
| MS:341 `clientChangeMon(_, to:, focus:)` | no | extra `focus` parameter |
| MS:1218 `centerTiledSelect(_, among:)` | no | candidate list passed in |
| MS:588 second `clientCenterGeometry(_:_:in:)` | yes | centring in a work area, without offsets |
| MS:861 `clientSetRules(_, mapped:)` | yes | |
| MS:901-907, MS:1085-1087 off-monitor floating centring | yes | |
| MS:967 `layoutStateInsert` | yes | |
| MS:1029 doc line on `clientResetMonTags` | yes (stale) | the body is mango's; the comment says otherwise |
| D:622 `setSizePer` loop in `clientViewOnMonitor` | no | arrange's `from_view` part, done in the view |
| D:1641 `scrollerNodeRemove` in `clientReassignMonitor` | no | port's column state |
| D:1470 `directionGeom` | yes | |
| MS:491, T:45 `f.height > h` guard | no | see `client_tile_resize` |
| T:61 `topBars` | no | sum of the bar heights above a window (helper) |
| T:26 `tabMembers`, T:40 `reserveTabStrip`, T:114 `clipBar`, T:130 `barSegments`, T:93 `animationCurrent` | yes | |
| MS:361 `visibleClients`, MS:366 `tiledClients`, MS:373 `specialClients`, MS:398 `arrangeAll`, MS:642 `frameDistance`, MS:683 `updateBorders`, MS:717 `shownFrame`, MS:390 `dragRefreshIntervalMs` | yes | |

## Summary

Counts (202 rows: 193 client.c functions + 9 client.h macro rows; the four `CLIENT_*_OFF` macros are one row, the `broken` constant is not counted):

| status | count | of which |
|---|---|---|
| 1:1 | 86 | 25 `name` (inlined or renamed), 5 already listed |
| differs | 19 | 3 already listed (`client_set_rules`, `client_set_fake_fullscreen` §3; `exit_scroller_stack` §5); 1 also `name` |
| missing | 1 | `unminimize` (unreachable in mango) |
| platform | 71 | 6 listed (compatibility.md / §3 / §5); the rest X11, wlroots, scene, rendering or Wayland protocol glue |
| port | 25 | 11 listed |

No unlisted user-visible platform feature was found: every platform item is X11, wlroots/scene/rendering, or named in compatibility.md/afvigelser.md. `MS:626 sceneGeometry` is mango's `server.scene_geometry` (the bbox for floating windows in animation/client.c:1531).

Most significant deviations, most significant first:

1. `client_active` (D:543): the parked-group-member swap runs last (inside `clientFocus`) instead of first, so `focusid` (or launch_or_focus) on a parked member views its stale tags, then swaps it in on the group's real tag: the wrong tag is shown. Related: `handle_client_activation_request` acts on a parked member, which mango ignores (no foreign toplevel).
2. `get_client_tag_idx` users: layout taken from the monitor's current tag (`m.layout`) instead of the client's own tag in `client_is_in_same_stack`, `get_focused_stack_client`, `client_exchange`, `client_replace`, and the unmap scroller lookup; `tags == 0` falls back to the current tag instead of slot 0. Differs in multi-tag views and for global windows.
3. `client_park` keeps `c.mon` (mango NULL) and `client_group_active` is absent: parked members report a stale monitor in IPC after the group moves monitors; `client_set_group_mon` then also moves parked members.
4. `client_move_to_monitor` along the scroller axis: inserted beside the target, not before the target column's head / after its tail in the client list.
5. `apply_window_snap`: uses `config.borderpx` instead of the client's effective `bw`, so with `no_border_when_single` (or other hidden-border cases) a floating window snaps `borderpx` short of edges.
6. `apply_rule_properties`: `scroller_proportion`/`scroller_proportion_single` applied for values `<= 0` (mango only `> 0`); and `no_radius` is listed impossible though the port draws mango's rounded border.
7. `client_check_tab_node_visible`: no `ISNORMAL` unglobal test, so an `isunglobal` window shows a group bar with `always_show_group_bar`.
8. `check_hit_no_border`: `monocle_no_border` uses `!isFloating` instead of `ISFAKETILED` (unglobal windows lose their border in monocle).
9. `client_change_mon`: centres `floatGeom` rather than `geom` into both, and has an extra unmarked `focus:` parameter.
10. `exit_scroller_stack` (listed §5 structure): a single-window column keeps its entry; mango always removes the node and copies its proportions back (unsure if visible).

Also worth noting: `unminimize` is missing but unreachable in mango; `get_client_by_id_or_title`'s "none" is a prefix test in mango (`strncmp(…, 4)`), exact in ours; `MS:1029`'s doc comment is stale.
