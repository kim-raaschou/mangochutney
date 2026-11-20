# F-anim-draw: src/animation/{client,common,layer,tag}.c, src/draw/{text-node,dim-node,title_message_bar}.c, src/overview/overview.c, src/switcher/switcher.c

Status 2026-11-20 (trin 10): hvert fund er mærket ✓ (rettet, som mango, listet, væk) eller åben, kontrolleret mod koden efter trin 9.

Paths: mango = `~/sources/mango/src/...`; ours relative to `Sources/`.
Abbreviations: `Anim` = Mango/Engine/Animation.swift, `MS` = Mango/Engine/MangoServer.swift, `Tabs` = Mango/Engine/Tabs.swift,
`OvM` = Mango/Engine/OverviewMode.swift, `SwM` = Mango/Engine/SwitcherMode.swift, `SwL` = Mango/Layout/SwitcherLayout.swift,
`TMB` = Mango/Engine/TitleMessageBar.swift, `Pl` = Port/macOS/Placement.swift, `Ani` = Port/macOS/Animator.swift,
`MWS` = Port/macOS/MacWindowSystem.swift.

## Functions

### animation/client.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| client_open_animation_type client.c:26 | Anim:83 (inline `c.animationTypeOpen ?? config.animationTypeOpen`) | 1:1 | name: inlined, no function |
| client_close_animation_type client.c:32 | — | platform | close animations; listed (MangoCompat `animation_type_close`, afvigelser §3) |
| client_no_radius_active client.c:38 | MS:154 `clientNoRadiusActive` | 1:1 | `visible_tiling_clients` = `tiledClients(m).count`; ISFAKETILED written out; same result |
| client_animations_enabled client.c:50 | Anim:21 | 1:1 | |
| client_is_ignore_output_clip client.c:58 | Tabs:98 | 1:1 | `tagining` derived as "running && action == .tag && !tagouting" (marked); same result |
| compute_edge_offsets client.c:64 | Tabs:106 | 1:1 | uses port's `animationCurrent` for `c->animation.current` (marked) |
| client_actual_size client.c:79 | Tabs:93 (inset by bw) | port | |
| set_rect_size client.c:83 | — | platform | scene rect |
| set_client_corner_location client.c:86 | MS:701 (`radius = clientNoRadiusActive ? 0 : borderRadius`) | differs åben (som mangel i afvigelser.md §4) (lille: klippet ved kanten nu, MangoServer.swift:265; ingen radius pr. hjørne) | mango zeroes each corner that touches the monitor edge (`target_geom.x + border_radius <= m.x` …) and keeps all four for `client_is_ignore_output_clip`; ours is one uniform radius for the border. Scenario: `border_radius=10`, mango look (no `chutney_macos_appearance`), a tiled window flush with the screen's left edge: mango draws square left corners, ours round. Unlisted (afvigelser §3 only says mango's window corners are not drawn) |
| is_horizontal_stack_layout client.c:119 | Anim:117 inline | 1:1 | name: inlined |
| is_horizontal_right_stack_layout client.c:125 | Anim:118 inline | 1:1 | name: inlined |
| is_special_animation_rule client.c:130 | Anim:113 | 1:1 | returns nil for UNDIR; `!isfloating` hoisted into the guard, same result |
| set_overview_enter_animation client.c:153 | Anim:129 | 1:1 | box is our content box (geom without border) where mango's is with border; same shape |
| set_client_open_animation client.c:169 | Anim:82 | 1:1 | listed §3: fade starts in place (opacity impossible); slide/zoom same formulas |
| scene_buffer_apply_effect client.c:245 | — | platform | buffer scale/corner radii; listed §3 |
| buffer_set_effect client.c:310 | — | platform | listed §3 |
| client_draw_shadow client.c:337 | — | platform | listed (MangoCompat "Shadows") |
| client_draw_group_bar client.c:425 | Tabs:175 | 1:1 | listed §5 (called for all clients at once, one panel per bar) |
| client_draw_shield client.c:501 | — | platform | listed (`shield_when_capture`) |
| client_draw_dim client.c:544 | — | platform | listed (MangoCompat "Dimming") |
| client_draw_blur client.c:591 | — | platform | listed (MangoCompat "Blur") |
| global_draw_group_bar client.c:632 | Tabs:130 `barSegments` | port | name; listed §5 |
| client_draw_split_border client.c:640 | MS:709 `clientDrawSplitBorder` + Port/macOS/Borders.swift:37 | port | same conditions and side (`custom_leaf_split_h` → right); port insets the indicator by the outer radius (radius+bw) where mango uses `border_radius`, and does not clip it at the monitor edge |
| client_draw_border client.c:708 | MS:683 `updateBorders` + Borders.swift | port | marked; no monitor-edge clipping (`offsets`) of the border rect; per-corner radii see set_client_corner_location |
| clip_to_hide client.c:768 | — (parking in arrange, MS:~535) | port | listed §3/§5 (parking stands for scene clip/hide) |
| client_set_drop_area client.c:810 | Mango/Layout/DropArea.swift:7 + Mango/Engine/DragTile.swift:61 | 1:1 | all layout branches, ratios and halves match; `drop_to_group` = group-bar target with whole area; scene caching (`first_draw`, `drop_direction`) is the port's |
| client_set_clip client.c:1008 | — | platform | scene clip/scale; tab/group bars drawn by `tabRefreshBars` (listed §5) |
| fadeout_client_animation_next_tick client.c:1175 | — | platform | close animation; listed §3 |
| client_animation_next_tick client.c:1231 | Ani:198 `tick` | port | listed §3/§5; end-of-animation `wlr_seat_pointer_notify_enter` is platform |
| init_fadeout_client client.c:1297 | — | platform | listed §3, MangoCompat |
| client_set_finish_geometry client.c:1389 | Ani:57 `finish`, Pl:66 | port | |
| client_animation_set_progress client.c:1399 | MWS:483 → Ani:40 | port | listed §5 |
| client_animation_resume client.c:1429 | MWS:488 → Ani:50/57 | port | listed §5; same 0.05 threshold and whole-duration restart |
| client_commit client.c:1458 | Ani:100 `animate` | port | |
| client_set_pending_state client.c:1483 | Pl:43-68, Anim:76 | port | grab → 0 ms, equal box → no write, `no_animation` via `clientAnimationsEnabled`; `start_drag_window` is achieved by callers passing `.none` |
| resize client.c:1520 | Anim:32 `clientAnimation` (marked) + Pl:31 + MS arrange (bounds) | differs ✓ rettet i trin 2 | (a) OVERVIEW action: mango's `find_animation_curve_at` has no OVERVIEW branch, so it uses `animation_curve_move`; ours uses `animationCurveTag` (Anim:42). Scenario: no Screen Recording permission (real windows move), `animation_curve_tag` ≠ `_move`: overview zoom eases differently. (b) `scratchpad_switching_mon && isfloating → animainit_geom = geom` not honoured: a shown scratchpad pulled to the selected monitor (`scratchpad_cross_monitor`) slides across from the old monitor in ours, appears in place in mango. (c) `.none` arrange (no animation at all, Dispatch/Tabs/FloatingSnap/port callers) has no counterpart: mango always animates a move. (d) size hints (`client_set_size_bound`) and swallow absent — listed (MangoCompat `no_size_hint`, `no_swallow`). listed §5 for the structure only |
| client_draw_fadeout_frame client.c:1674 | — | platform | listed §3 |
| client_start_focus_animation client.c:1682 | — | missing åben (som mangel i afvigelser.md §4) | opacity part is platform, but the same animation fades the **border colour** (`target_border_color`) over `animation_duration_focus` with `animation_curve_focus`; the port draws borders and could. MangoCompat lists both keys only as "opacity needs SIP off" (reason incomplete). Scenario: `animation_duration_focus=300`: mango fades border focus→unfocus colour, ours switches at once |
| client_interpolate_focus_animation client.c:1704 | — | missing åben (som mangel i afvigelser.md §4) | as above (border/dim colour interpolation) |
| client_step_focus_animation client.c:1728 | — | missing åben (som mangel i afvigelser.md §4) | as above |
| client_set_unfocused_opacity_animation client.c:1739 | — | missing åben (som mangel i afvigelser.md §4) | border-colour fade start; border raise is scene |
| client_set_focused_opacity_animation client.c:1748 | — | missing åben (som mangel i afvigelser.md §4) | as above |
| client_set_focus_opacity client.c:1759 | — | platform | opacity/fade-in/blur; listed (MangoCompat fade keys) |
| client_draw_frame client.c:1865 | MS:721 `clientDrawFrame` + Ani:202 `frozen` | port | listed §5; our `clientDrawFrame` only redraws borders/bars for the animator's frames (see table 2) |

### animation/tag.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| set_tagin_animation tag.c:10 | Anim:196 `setTaginAnimation` | differs ✓ rettet i trin 2 | mango: forward start x = `MAX(m.x+m.width, geom.x+m.width)`, back `MIN(m.x-geom.width, geom.x-m.width)` (y likewise vertical), and keeps the other axis at `animation.current`; ours is `target ± screen width/height` with the other axis from the target. Scenario: scroller window extending past the right screen edge, view back: mango starts at `m.x - w`, ours at `x - m.width` (different start). Also a client whose geom changed while hidden starts from its old y in mango (diagonal), straight in ours. The "running" and "on both tags / global" branches are covered elsewhere (move) |
| set_arrange_visible tag.c:55 | Anim:38-75 (inside `clientAnimation`), Anim:179 | differs ✓ rettet i trin 2 | (1) `tag_switch` needs `prevtag != 0 && curtag != 0`; ours slides in any parked client on a `.tag` arrange. Scenario: special tag shown, `view 3`: prevtag becomes 0, mango shows tag 3's windows in place, ours slides them in. (2) In-flight tagout reversed: mango sets `tagining` → TAG duration/curve; ours falls to `.move` (move duration 500 ms / move curve instead of 300 ms / tag curve). (3) Special (TAG0) clients: mango slides from above on every `want_animation` arrange even when shown; ours only when parked. `tag_from_rule`: same result (new client takes OPEN in both). Unlisted |
| set_tagout_animation tag.c:129 | Anim:184 | 1:1 | same MIN/MAX positions; port runs it (Pl:180) |
| set_arrange_hidden tag.c:168 | Anim:141 | 1:1 | scratchpad, special (`want_animation && !isoverview`), prev-tag tagout with mango's conditions; `ov_card_tree` branch is port; `!parked` stands for `!tagouted`; same result |

### animation/common.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| calculate_animation_curve_at common.c:12 | Mango/Model/Geometry.swift:85 | 1:1 | per component; curve picked per action by the caller |
| handle_snapshot_meta_destroy common.c:41 | — | platform | snapshot |
| init_baked_points common.c:46 | — | port | listed §5 |
| find_animation_curve_at common.c:91 | Geometry.swift:89 | 1:1 | bisection on t instead of baked-table lookup; same result within the table's step |
| scene_node_snapshot common.c:125 | — | platform | close-animation snapshot; listed §3 |
| wlr_scene_tree_snapshot common.c:280 | — | platform | listed §3 |
| snapshot_dest_to_source common.c:301 | — | platform | |
| scene_snapshot_enable_buffers common.c:347 | — | platform | |
| scene_snapshot_clip_buffer common.c:365 | — | platform | |
| scene_snapshot_clip_to_box common.c:463 | — | platform | |
| request_fresh_all_monitors common.c:481 | Ani:179 `ensureTimer` (display link) | port | frame scheduling; listed §3 (≤60 Hz) |

### animation/layer.c (all layer-shell; listed: MangoCompat "Layer surfaces", afvigelser §4)

| mango (file:line) | ours | status | note |
|---|---|---|---|
| layer_open_animation_type layer.c:12 | — | platform | no layer shell |
| layer_close_animation_type layer.c:18 | — | platform | |
| layer_actual_size layer.c:24 | — | platform | |
| layer_consume_exclusive layer.c:34 | — | platform | exclusive zones ≈ menu bar/Dock (§3) |
| layer_bound_area layer.c:65 | — | platform | |
| get_layer_area_bound layer.c:94 | — | platform | |
| get_layer_target_geometry layer.c:97 | — | platform | |
| set_layer_dir_animaiton layer.c:174 | — | platform | |
| layer_draw_shield layer.c:224 | — | platform | |
| layer_draw_shadow layer.c:251 | — | platform | |
| layer_scene_buffer_apply_effect layer.c:294 | — | platform | |
| fadeout_layer_animation_next_tick layer.c:314 | — | platform | |
| layer_surface_tree layer.c:374 | — | platform | |
| layer_apply_output_clip layer.c:394 | — | platform | |
| layer_animation_next_tick layer.c:426 | — | platform | |
| init_fadeout_layers layer.c:510 | — | platform | |
| layer_set_pending_state layer.c:609 | — | platform | |
| layer_commit layer.c:660 | — | platform | |
| layer_draw_frame layer.c:682 | — | platform | |
| layer_draw_fadeout_frame layer.c:706 | — | platform | |

### draw/dim-node.c (per-client dim; listed MangoCompat "Dimming")

| mango (file:line) | ours | status | note |
|---|---|---|---|
| dim_buffer_destroy dim-node.c:15 | — | platform | wlr_buffer impl |
| dim_buffer_begin_data_ptr_access dim-node.c:23 | — | platform | |
| dim_buffer_end_data_ptr_access dim-node.c:40 | — | platform | |
| dim_node_build_pixel dim-node.c:48 | — | platform | |
| dim_node_point_accepts_input dim-node.c:80 | — | platform | |
| mango_dim_node_create dim-node.c:85 | — | platform | listed |
| mango_dim_node_destroy dim-node.c:119 | — | platform | |
| mango_dim_node_set_color dim-node.c:136 | — | platform | |
| mango_dim_node_set_radius dim-node.c:150 | — | platform | |
| mango_dim_node_set_box dim-node.c:164 | — | platform | |
| mango_dim_node_set_enabled dim-node.c:183 | — | platform | |

### draw/text-node.c (MangoBarDecoration / MangoJumpLabel; boundary protocols Boundary/MangoBarDecoration.swift, Boundary/MangoJumpLabel.swift; drawn by Port/macOS/TabBars.swift, SwitcherPanel.swift, JumpLabel.swift; listed §5)

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| get_cached_font_desc text-node.c:22 | Mango/Model/Decorate.swift:65 `FontDescription` | platform | pango font cache; port parses the desc |
| mango_text_global_finish text-node.c:38 | — | platform | |
| text_buffer_destroy text-node.c:46 | — | platform | |
| text_buffer_begin_data_ptr_access text-node.c:54 | — | platform | |
| text_buffer_end_data_ptr_access text-node.c:71 | — | platform | |
| rect_apply text-node.c:79 | — | platform | |
| rect_apply_border text-node.c:111 | — | platform | |
| layout_configure text-node.c:135 | — | platform | |
| measure_init text-node.c:141 | — | platform | |
| measure_finish text-node.c:149 | — | platform | |
| measure_text text-node.c:168 | — | platform | |
| text_ellipsize_line text-node.c:183 | TabBars.swift:199 (`truncationMode = .end`) | port | same "…" at the end |
| text_ellipsize text-node.c:210 | as above | port | per line |
| text_surface_create text-node.c:246 | — | platform | cairo |
| text_surface_create_two_lines text-node.c:292 | — | platform | |
| text_node_install text-node.c:342 | — | platform | |
| text_node_apply_size text-node.c:369 | — | platform | |
| text_node_clear text-node.c:418 | — | platform | |
| mango_jump_label_node_create text-node.c:~431 | JumpLabel.swift:17 | port | listed §5 |
| mango_jump_label_node_destroy text-node.c:473 | JumpLabel.swift:47 | port | |
| jump_label_apply_geometry text-node.c:495 | JumpLabel.swift:62 `measure` | port | logical size from the port's look |
| mango_jump_label_node_update text-node.c:528 | JumpLabel.swift:36 | port | |
| mango_jump_label_node_set_focus text-node.c:565 | — | port | never called in mango; nothing to port |
| mango_jump_label_node_set_background text-node.c:576 | — | port | never called in mango |
| mango_jump_label_node_set_border text-node.c:591 | — | port | never called in mango |
| mango_jump_label_node_set_padding text-node.c:609 | — | port | never called in mango |
| mango_bar_decoration_create text-node.c:~628 | `system.mangoBarDecorationCreate` (TMB:14), TabBars panels | port | |
| mango_bar_decoration_destroy text-node.c:690 | boundary `destroy` | port | |
| bar_decoration_avail_width text-node.c:716 | — | port | |
| bar_decoration_apply_geometry text-node.c:722 | — | port | |
| mango_bar_decoration_set_size text-node.c:770 | boundary `setSize` | port | |
| close_button_box text-node.c:793 | TabBars.swift:296-299 | port | same size/margin clamp and centring |
| close_button_render text-node.c:814 | TabBars.swift:300-314 | port | stroke `size/10` vs mango `pixel*0.12` (min 1) |
| close_button_sync text-node.c:862 | TabBars.swift:291 | port | |
| mango_bar_decoration_update text-node.c:892 | boundary `update` | port | |
| mango_bar_decoration_set_focus text-node.c:982 | boundary `setFocus`; Port/macOS/SwitcherPanel.swift:232 no-op | port | title bar always focused (as mango sets it) |
| mango_bar_decoration_set_center_secondary_line text-node.c:992 | boundary | port | |
| mango_bar_decoration_set_colors text-node.c:1004 | — | port | never called in mango |
| mango_bar_decoration_set_close text-node.c:1018 | Tabs:199 `TabStrip.closeButton` | port | |
| mango_bar_decoration_set_close_color text-node.c:1033 | Tabs:201 | port | hover colour derivation (`c + (1-c)*0.4`) unused, see next |
| mango_bar_decoration_set_close_hover text-node.c:1047 | — | missing åben (som mangel i afvigelser.md §4) (pointer.swift:524) | group-bar close button does not change colour under the pointer (mango: pointer.c:1286). Unlisted |
| mango_bar_decoration_close_contains text-node.c:1055 | TabBars.swift:321 | port | |
| mango_jump_label_node_apply_config text-node.c:1067 | JumpLabel.swift:41 | port | |
| mango_bar_decoration_apply_config text-node.c:1095 | boundary `applyConfig`; Tabs:57 | port | see table 2 for Tabs:57's name |

### draw/title_message_bar.c (listed §5)

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| title_message_bar_text tmb.c:12 | TMB:6 | 1:1 | appid = bundle id (listed §3) |
| title_message_bar_init tmb.c:16 | TMB:10 | 1:1 | layer/ignore-hit are port |
| title_message_bar_set_text tmb.c:32 | TMB:23 | 1:1 | string compare instead of strncmp pieces; same result |
| overcircle_title_bar_geometry tmb.c:48 | TMB:30 | differs ✓ listet: afvigelser.md §5 | listed §5: under the client's card (`ovCards`), not `geom`/`animation.current`, and no fallback between them |
| title_message_bar_geometry tmb.c:75 | TMB:41 | 1:1 | plus one marked `PortHooks` call (launch_or_focus) |
| title_message_bar_finish tmb.c:82 | TMB:47 | 1:1 | |
| title_message_bar_apply_config tmb.c:90 | TMB:54 | 1:1 | |
| title_message_bar_hide tmb.c:99 | TMB:61 | 1:1 | |
| title_message_bar_update_title tmb.c:106 | TMB:66 | 1:1 | plus marked PortHooks |
| title_message_bar_refresh tmb.c:127 | TMB:81 | 1:1 | |
| title_message_bar_update tmb.c:156 | TMB:100 | 1:1 | |
| title_message_bar_update_geometry tmb.c:160 | TMB:104 | 1:1 | called once at the card (OvM:261, marked; listed §5) instead of every frame |

### overview/overview.c (listed §5)

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| want_restore_fullscreen overview.c:32 | OvM:407 | 1:1 | |
| handle_overview_card_surface_commit overview.c:50 | — | port | cards are stills (listed §3) |
| handle_overview_card_surface_destroy overview.c:58 | — | platform | |
| overview_card_surface_add overview.c:68 | OvM:202 + Port/macOS/OverviewOverlay.swift:138 | port | name reused per monitor (marked inline) |
| overview_layout_card overview.c:97 | OvM:234 `overviewTileResize` + OverviewOverlay | port | listed §5 |
| overview_update_jump_label overview.c:207 | OvM:316 | 1:1 | listed §5 (screen coords, once at the card) |
| overview_destroy_card overview.c:241 | OvM:196 `overviewCardsClose` | port | listed §5 |
| overview_card_set_corner_radii overview.c:257 | `OverviewLook.mango.cornerRadius` (OvM:188) | port | |
| overview_backup_surface overview.c:265 | OvM:183 `overviewCardsShow`; new clients captured in OverviewOverlay.swift:93 | port | listed §5 |
| overview_backup overview.c:301 | OvM:390 | 1:1 | listed §5 (bw, client_set_tiled, client_sync_layer marked out; floating backup = floatGeom, marked) |
| overview_restore overview.c:329 | OvM:420 | 1:1 | listed §5, §6 (no-backup guard); floating/`is_restoring_from_ov` resize left to arrange, marked; same result |

### switcher/switcher.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| switcher_tile_layout switcher.c:22 | Port/macOS/SwitcherPanel.swift | port | stills (listed §3) |
| switcher_surface_finish switcher.c:73 | — | platform | |
| switcher_surface_update_buffer switcher.c:82 | — | platform | |
| handle_switcher_surface_commit switcher.c:144 | — | platform | stills |
| handle_switcher_surface_destroy switcher.c:150 | — | platform | |
| handle_switcher_surface_output_sample switcher.c:157 | — | platform | |
| handle_switcher_surface_frame_done switcher.c:180 | — | platform | |
| switcher_tile_add_surface switcher.c:189 | — | platform | |
| switcher_tile_create switcher.c:219 | SwL:31-35 (cw), SwitcherPanel | port | cw formula 1:1 (content size = `c.frame.size`) |
| switcher_layout switcher.c:237 | SwL:15 `switcherLayout` | 1:1 | rows, centring, panel position match; also holds switcher_open's tile_h loop (table 2) |
| switcher_apply_highlight switcher.c:294 | SwM:102/113 → port | port | focuscolor/bordercolor passed |
| switcher_close switcher.c:301 | SwM:68 | 1:1 | |
| switcher_remove_client switcher.c:321 | SwM:88 | differs ✓ rettet i trin 8 | mango's `switcher_layout` keeps `tile_h` and each `tile->cw` from open; ours re-runs `switcherLayout` from scratch, recomputing tile height for the new count and widths from current frames. Scenario: 2 tiles open, one window closes: mango keeps the remaining tile its size, ours can grow it (rows=1 gives larger `h_by_h`). Unlisted |
| switcher_client_eligible switcher.c:355 | SwM:36 | 1:1 | mapped/unmanaged/x11 checks need no macOS part |
| switcher_commit_client switcher.c:361 | SwM:76 | differs ✓ rettet i trin 8 | mango calls `client_view_on_monitor(..., true, tc->mon, true)` (changefocus true); ours passes no `changeFocus`, so false when `tc` is on another monitor than the selected one (all_next scope): mango first focuses that monitor's top client then `tc` (prevsel = that top client), ours focuses `tc` directly (prevsel unchanged). Unlisted |
| switcher_commit switcher.c:371 | SwM:83 | 1:1 | |
| switcher_client_at switcher.c:375 | Mango/Engine/Input.swift:135 inline | 1:1 | name: inlined; same box (cw+2·pad × tile_h+2·pad) |
| switcher_title_message_bar_geometry switcher.c:394 | SwM:117 | 1:1 | |
| switcher_open switcher.c:415 | SwM:42 (+SwL tile_h loop) | 1:1 | index rule, focus-stack order match; mango's "any monitor in overview → return" moved to `switcher` (see next) |
| switcher_cycle switcher.c:486 | SwM:60 | 1:1 | |
| switcher switcher.c:493 | SwM:14 | differs ✓ rettet i trin 8 | ours returns when any monitor is in overview before the active/cycle test (mango checks overview only inside `switcher_open`). Scenario: switcher open, a binding enters overview, mod+Tab again: mango cycles (or closes on scope change), ours does nothing and the switcher stays. `session_locked` n/a. Unlisted |
| switcher_is_active switcher.c:511 | `switcherState != nil` | 1:1 | name: no function |
| switcher_candidate switcher.c:513 | SwM:44-51 inline | 1:1 | name: inlined |
| switcher_content_size switcher.c:524 | `c.frame.size` (SwM:55) | port | |
| switcher_panel_color switcher.c:537 | Port/macOS/SwitcherPanel.swift:25 `mangoPanelColor` | port | same value |

## Not in mango (in the Swift files looked at)

| ours (file:line) | marked? | note |
|---|---|---|
| Anim:3 `AnimationAction`, Anim:7 `TagoutAnimation`, Anim:13 `ClientAnimation` | no | value types carrying mango's `animation.action`/duration/curve across the boundary; unmarked |
| Anim:32 `clientAnimation` | yes | resize's action/start choice plus set_arrange_visible and set_tagin_animation logic in one function (listed §5) |
| Anim:179 `setArrangeVisible` | no | carries mango's `set_arrange_visible` name but is only the "start above the monitor" rect; the real set_arrange_visible logic is inside `clientAnimation`. Misleading name, unmarked |
| Tabs:57 `mangoBarDecorationApplyConfig` | no | mango's name, but merges set keys over mango's defaults (`setValueDefault`), it does not apply config to a node; unmarked |
| Tabs:61 `topBars` | no | bar heights above a client; unmarked helper |
| Tabs:70 `tabRefreshBars`, Tabs:93 `animationCurrent`, Tabs:114 `clipBar`, Tabs:130 `barSegments` | yes | |
| MS:677 `borderWidth`, MS:683 `updateBorders`, MS:717 `shownFrame` | yes | |
| MS:721 `clientDrawFrame` | no | mango's name; here a batch border/bar redraw for the animator's frames, not per-client tick (listed §5 only in spirit) |
| Mango/Model/Geometry.swift:101 `BezierCurve.extremes` | no | only used by the port (Ani:88 `covered`); port helper in the core, unmarked |
| OvM:174 `overlayCards`, OvM:183 `overviewCardsShow`, OvM:196 `overviewCardsClose`, OvM:207 `overviewItems`, OvM:234 `overviewTileResize` | yes | |
| OvM:202 `overviewCardSurfaceAdd` | body marked | mango's per-surface callback name used for a per-monitor capture call |
| SwM:40 `switcherOrder` | no | focus_stack as clients; trivial |
| SwM:102 `drawSwitcher` | yes | |
| SwL:15 `switcherLayout` | no | merges switcher_open's tile_h loop, switcher_tile_create's cw and switcher_layout into one pure function; no `/// mango` line. This merge is what makes switcher_remove_client differ |

## Summary

Counts (182 functions): 1:1 41 · differs 8 · missing 6 · platform 75 · port 52.
(platform: layer.c 20, dim-node 11, text-node rendering 16, client.c effects/fade 13, snapshots 7, switcher surfaces 7, overview 1; none user-visible and unlisted.)

Most significant deviations, most significant first:
1. **set_arrange_visible** (Anim:38-75): a parked client slides in on any `.tag` arrange; mango requires `prevtag != 0 && curtag != 0`. From the special tag, `view N` slides tag N's windows in where mango shows them in place. An in-flight tagout that is reversed runs with move duration/curve, not tag's.
2. **resize: scratchpad_switching_mon** not honoured: a shown scratchpad pulled to another monitor (`scratchpad_cross_monitor`) slides across the screens; mango puts it in place.
3. **Focus animation (client_start_focus_animation & co.) missing for the border colour**: with `animation_duration_focus > 0`, mango fades the border colour; ours switches at once. MangoCompat lists the keys only as "opacity needs SIP off", so the reason is incomplete.
4. **resize: overview animation curve**: mango's OVERVIEW action falls back to `animation_curve_move`; ours uses `animation_curve_tag` (seen without Screen Recording).
5. **switcher_remove_client**: tile height and widths are recomputed when a window closes under the open switcher; mango keeps them.
6. **switcher()**: the overview guard is moved ahead of the cycle, so an open switcher cannot cycle or change scope while any monitor is in overview.
7. **switcher_commit_client**: `client_view_on_monitor` called without mango's `changefocus = true` for a client on another monitor; the intermediate focus and `prevsel` differ.
8. **mango_bar_decoration_set_close_hover** missing: the group bar's close button has no hover colour. Unlisted.
9. **set_client_corner_location**: the border radius is uniform; mango squares the corners that touch the monitor edge (with `border_radius > 0`, mango look).
10. **set_tagin_animation**: the start position has no MAX/MIN clamp and takes the cross axis from the target, not `animation.current`, so the start differs for windows past the screen edge (scroller) or whose geom changed while hidden. Related: the core's `.none` arrange (no animation at all) has no counterpart in mango's resize.

Naming issues worth fixing with the above: `setArrangeVisible` (Anim:179) and `mangoBarDecorationApplyConfig` (Tabs:57) carry mango names for other jobs; `BezierCurve.extremes` is a port-only helper in the core, unmarked.
