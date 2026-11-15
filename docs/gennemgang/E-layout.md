# E-layout: src/layout/{arrange,horizontal,vertical,dwindle,scroll,overview}.c, include/mango/layout/*.h

Paths: mango = `~/sources/mango/src/layout/…`; ours relative to `Sources/`.
"geom" below means mango's `c->geom` (outer box, border included). Ours `c.geom` is the content rect
(border excluded; `Port/macOS/Placement.swift:34` writes the tile inset by `bw`).

## Functions

### arrange.c / layout.h

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| arrange.c:18 `set_size_per` | Mango/Engine/Dispatch.swift:904 `setSizePer` | 1:1 | Both loops over VISIBLEON+ISTILED, center_tile side check, keep_own branch, fallback 1.0, scroller defaults. |
| arrange.c:86 `persist_tile_size_weights` (static) | Dispatch.swift:969 | 1:1 | ISFAKETILED filter written out. |
| arrange.c:99 `resize_tile_master_horizontal` | Dispatch.swift:999 `resizeTileMaster(vertical:false)` | differs | Merge of _horizontal/_vertical is marked. Divisor: mango `offsetx * old_master_mfact_per / drag_begin_geom.width` with geom incl. border; ours `gc.geom ?? gc.frame` (Dispatch.swift:1007) = content, 2*borderpx smaller. Scenario: borderpx 4, master 1000 px wide, drag 100 px: mango Δmfact = 100*0.55/1000 = 0.0550, ours 100*0.55/992 = 0.0554 (keyboard `resizewin` likewise). Also `max(1, width)` guard (mango divides by 0 → inf). Rest (prev/next/nextnext/prevprev, sign table, clamps, group rescale, keyboard rescale, broadcast, persist) matches; arrange(.none) for drag / (.move) for keys = mango's start_drag_window animation rule (same result). |
| arrange.c:327 `resize_tile_master_vertical` | Dispatch.swift:999 `resizeTileMaster(vertical:true)` | differs | Same divisor deviation as above (height/width of content, not geom). Otherwise 1:1 (no center_tile branches in the vertical case, as mango). |
| arrange.c:500 `resize_tile_dwindle` | Dispatch.swift:1204 | 1:1 | Ours calls `arrange` after the tree change where mango calls `dwindle_assign` directly (inside dwindle_resize_client[_step]); same placements. |
| arrange.c:511 `resize_tile_grid_fair` | Dispatch.swift:1218 `resizeTileGridFair` | 1:1, listed §6 | Keyboard-neighbour overwrite fixed for drag only (§6 row 3). Uses `directionGeom` (border incl.) = mango geom. VERTICAL_FAIR/FAIR locked-boundary maths identical. |
| arrange.c:800 `resize_tile_scroller` | Dispatch.swift:1114 `resizeTileScroller` | differs | (a) Divisor is content size (`gc.geom ?? gc.frame`, Dispatch.swift:1132) vs mango geom incl. border (same effect as above). (b) "more than one column" test: mango `m->visible_scroll_tiling_clients > 1`, which scroller_core sets to n_heads counting ISSCROLLTILED (fullscreen/maximized columns included); ours `columns(for: tiledClients(m))` (Dispatch.swift:1188), tiledClients excludes fullscreen/maximized. Scenario: two columns, one maximized, `scroller_ignore_proportion_single` 0 (mango default is 1): resizing the other column changes its width in mango, not in ours. Stack proportions recomputed from weights instead of read from the node (same values). |
| arrange.c:1008 `resize_tile_client` | Dispatch.swift:975 | differs | Missing mango's coalescing `if (gc->mon->last_resize_frame == gc->mon->frame_serial) return;` for tiled resizes (keyboard repeats and pointer motion once per output frame). Ours applies every call (Input.swift:383 for drags). §3 only lists the floating-resize equivalent → unlisted. Layout by `get_client_tag_idx` (special → 0) = ours `getTagsFirstTagNum ?? curtag`. |
| arrange.c:1052 `check_size_per_valid` | — | missing | Debug `assert` only (mango's own comment says it never fires). No behaviour. |
| arrange.c:1060 `special_keep_bg_client` | Mango/Engine/MangoServer.swift:593 | 1:1 | Extra `c.mon === m` guard = the only caller's condition. |
| arrange.c:1066 `reset_size_per_mon` | Dispatch.swift:943 | 1:1 | Takes the ISFAKETILED list as a parameter (marked); assert omitted. |
| arrange.c:1117 `pre_calculate_before_arrange` | inlined: MangoServer.swift:419-447 (weights, isleftstack, reset_size_per_mon), Dispatch.swift:622 (from_view set_size_per), Mango/Layout/Scroller.swift:135 (update_scroller_state) | differs | Marked "pre_calculate_before_arrange's weights, here in arrange". Differences: (1) from_view `set_size_per(m, c, true)` for global/unglobal clients runs in mango for every global client in `server.clients` (any monitor) and for VISIBLEON multi-tag clients via `!client_only_in_one_tag`; ours only for clients visible on m, and with `(tags & ~special).nonzeroBitCount > 1` (a special+2-tag client: mango skips, ours resets). (2) `from_view && m->sel == NULL && c->isglobal && VISIBLEON → client_focus(c,1)` not present (ours focuses `clientFocusTop` only when `changeFocus`) — unsure, probably same result. (3) `set_arrange_hidden` is not skipped for `server.grab_client`. (4) the `special_keep_bg_client` branch's `tag_visible=true`/animation stop is replaced by "do nothing" (same visible result). (5) `m->visible_clients/_tiling/_scroll_tiling/_fake_tiling/hide_clients` are not kept; recomputed per use. (6) whole function skipped in overview (see `arrange`). (7) `only_calculate` path is predict-only (platform). |
| arrange.c:1256 `tag_remap_mask` | Dispatch.swift:733 | 1:1 | |
| arrange.c:1268 `tag_gather_reset_slot` | Mango/Engine/Client.swift:208 (Monitor) | 1:1 | New `Pertag` object = mango's field resets incl. dwindle_root/scroller_state; rule loop same order/condition. |
| arrange.c:1289 `tag_gather_move_pertag` | Client.swift:234 | 1:1 | Moves the whole Pertag object (all fields mango copies). |
| arrange.c:1309 `tag_gather_apply` | Dispatch.swift:758 | 1:1 | No `iscleanuping`/`iskilling` checks (port has no such states; same result). |
| arrange.c:1395 `overviewlayout`, `layouts[]` | Mango/Layout/Layout.swift:4 `LayoutKind` | 1:1 | Same order, names, symbols. |
| arrange.c:1402 `special_handle_empty_view` | inlined MangoServer.swift:407-412 | differs | `from_view` is read as `anim == .tag`. `clientViewOnMonitor` passes `.move` when `want_animation` is false (Dispatch.swift:626), but mango still calls `arrange(m, want_animation, true)`. Scenario: leaving the overview back to an empty special tag (`clientSwitchView(target, wantAnimation:false)`, OverviewMode.swift:104), or `view` of a mask already shown: mango sets `special_empty_view` and stays on the special tag; ours calls `toggleSpecialTagMon` and leaves it. Also not run while in overview (mango resets `special_empty_view=false` there). |
| arrange.c:1421 `arrange` | MangoServer.swift:402 | differs | (1) `if m.isoverview { overview(m); return }` comes first: in overview ours skips `m->sel = client_focus_top`, special_handle_empty_view, pre_calculate (global-client tag rewrite, weights, special_update_dim), tab_sync_monitor, tag_gather_apply and the trailing calls; mango runs all of them and only swaps the layout function. (2) No `printstatus(IPC_WATCH_ARRANGGE)` at the end of arrange (unsure how many callers make up for it). (3) `pointer_process_motion(0,…)`/`check_idle_inhibitor` after arrange: platform (pointer focus, idle inhibit). (4) fullscreen/maximized clients get `m.screen.frame` / `reset_maximizescreen_size` box in every layout, overriding the scroller's own frames (see `horizontal_scroll_adjust_fullandmax`). (5) `!m->wlr_output->enabled` / `iscleanuping` guards: platform. Gaps swap for special (`specialGaps`) and enable_gaps: same. |
| layout.h:17 `layout_predict_box`, `struct LayoutContext` | — | platform | Pre-sizing a new surface before map (xdg configure); macOS windows exist already. Not user-visible. |

### horizontal.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| horizontal.c:17 `tile_core` | Mango/Layout/TileLayouts.swift:89 `tileCore(right:false)` | differs, listed §6 | Pixel maths identical (mfact via `f32`, `(w+ih)*mfact` truncation, double share / float ratio, fallback split). §6: last of each group takes the rest. Unlisted: mango writes `c->master_mfact_per = mfact` (the first fake-tiled client's value) into every tiled client each arrange; ours never writes it back. Scenario: A fullscreen and first in the list, B, C tiled; drag B's edge (broadcast skips A, ISTILED): mango's next arrange resets B, C to A's mfact; ours leaves B, C at the dragged value. Close A: mango keeps the old split, ours jumps to the dragged one. (Fallback `master_inner_per = h / …` write-back unreachable after reset_size_per_mon.) Extra `masterRatio > 0` guard (mango would divide by ≤0; only pathological). |
| horizontal.c:136 `right_tile_core` | TileLayouts.swift:89 `tileCore(right:true)` | differs, listed §6, name | Same as tile_core. Merge of tile_core/right_tile_core into one function is not marked. |
| horizontal.c:256 `center_tile_core` | TileLayouts.swift:146 `centerTile` | differs | All branches (overspread, center_when_single_stack, left/right alternation, `r==1` rest, single-stack `init_single_stack_surplus * stack_inner_per`) match. Same missing `master_mfact_per` write-back as tile_core. |
| horizontal.c:540 `deck_core` | TileLayouts.swift:317 `deck` | differs | Gaps (no iv), `round()` of float mfact, master split, stack box identical. `hidden` is marked (solver only; monocle-like layouts are not parked). Missing `master_mfact_per` write-back. |
| horizontal.c:612 `monocle_core` | TileLayouts.swift:382 `monocle` | 1:1 | monocle_no_gap then smartgaps; `hidden` marked. |
| horizontal.c:645 `grid_core` | Mango/Layout/GridLayouts.swift:55 `gridCore` (+ `grid` :5) | 1:1 | config.gappoh/gappih; n==1 (0.9f), n==2 (0.65 double, y+gappo), cols/rows loop (same result as `cols<=n/2` loop for n≥3), overcols centring, last column/row takes rest, float→int truncation: all match. |
| horizontal.c:845 `fair_core` | GridLayouts.swift:115 `fairCore` (+ `fair` :27) | 1:1 | Two locking passes, fallback 1.0, base/max row sets, last span takes rest. |
| horizontal.c:1046-1082 `tile`, `right_tile`, `center_tile`, `deck`, `monocle`, `grid`, `fair` (7 wrappers) | TileLayouts/GridLayouts public funcs via Layout.swift:218 `LayoutEngine.arrange` | 1:1 | |
| horizontal.c:1048-1084 `tile_predict` … `fair_predict` (7) | — | platform | See layout_predict_box. |

### vertical.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| vertical.c:14 `vertical_tile_core` | TileLayouts.swift:261 `verticalTile` | differs, listed §6 | Including mango's asymmetric fallback `(w - mx - ih - ih*(r-1))/r` and stack y `mh + ov`. Missing `master_mfact_per` write-back (as tile_core). |
| vertical.c:127 `vertical_deck_core` | TileLayouts.swift:349 `verticalDeck` | differs | Gaps (no ih), round, boxes match. Missing write-back. `hidden` here is not marked (deck's is). |
| vertical.c:199 `vertical_grid_core` | GridLayouts.swift:12 `verticalGrid` (transposed gridCore) | differs | Ours = exact transpose of grid (indices `i/rows`, `i%rows`, gappov/gappiv, 0.65 width): matches mango for tiled clients. But mango's loops use `VISIBLEON && !isunglobal && (!client_is_x11_popup(c) \|\| ISFAKETILED(c))` (grid uses `(isoverview && !popup) \|\| ISFAKETILED`), so visible FLOATING clients enter the index count while n is `visible_fake_tiling_clients`. Scenario: one tiled + one floating window earlier in the client list: mango's n==1 loop picks the floating one, `client_tile_resize` does nothing for it, and returns — the tiled window is not placed; with n≥3 the indices shift (and can run past `cols`). Ours places only tiled clients. A mango bug fixed silently: not in §6, no mark, no test. |
| vertical.c:387 `vertical_fair_core` | GridLayouts.swift:33 `verticalFair` (transposed fairCore) | 1:1 | Transpose with `IGaps.transposed` is exact. |
| vertical.c:579-597 4 wrappers | GridLayouts/TileLayouts | 1:1 | |
| vertical.c:581-599 4 `*_predict` | — | platform | |

### dwindle.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| dwindle.c:10 statics `locked_horizontal_node`, `locked_vertical_node` | Mango/Layout/Dwindle.swift:28 (weak) | 1:1 | Mango NULLs them when leaf/parent removed; ours weak refs go nil when the parent is freed. |
| dwindle.c:14 `count_block_items` | Dwindle.swift:126 | 1:1 | |
| dwindle.c:23 `dwindle_find_leaf` | Dwindle.swift:51 | 1:1 | |
| dwindle.c:32 `dwindle_first_leaf` | Dwindle.swift:66 | 1:1 | |
| dwindle.c:40 `dwindle_free_tree` | Dwindle.swift:296 | 1:1 | Only tests call it. |
| dwindle.c:48 `dwindle_remove` | Dwindle.swift:252 | 1:1 | manual_split rollback, p_del clamp, container reset rule identical. |
| dwindle.c:165 `dwindle_assign` | Dwindle.swift:99 | 1:1 | `container == nil` ≡ `container_w==0 && container_h==0`; `(int)(aw*ratio) - gap/2`, max(1). |
| dwindle.c:207 `dwindle_new_leaf` | `Node(client:)` Dwindle.swift:19 | 1:1, name | |
| dwindle.c:215 `get_block_path_and_ratios` | Dwindle.swift:132 | 1:1 | |
| dwindle.c:251 `dwindle_insert` | Dwindle.swift:212 | 1:1 | Takes the target node; the empty-root case lives in dwindleInsertWithConfig (only caller that can see it). |
| dwindle.c:337 `dwindle_move_next_to` | Dispatch.swift `dwindleMoveNextTo` (after clientMoveToMonitor) + Dwindle.swift:315 | differs (minor, unsure) | `tgeom` is `target->geom` in mango (after client_tile_resize took off group/tab bar); ours the leaf's assigned box (`lastFrame`) before the bars. With a group bar on the target, `split_h = w >= h` and the `as_first` y-centre can differ for near-square targets. Sibling-swap, container area, remove+insert(lock) match. |
| dwindle.c:393 `dwindle_swap_clients` | Dwindle.swift:308 + Dispatch.swift:1342 `clientExchange` | 1:1 | Cross-monitor via `replace` on both trees = mango's leaf client swap. |
| dwindle.c:421 `dwindle_resize_client` | Dwindle.swift:361 | 1:1 | smart_resize inversion, 0.05–0.95 clamp. |
| dwindle.c:498 `dwindle_resize_client_step` | Dwindle.swift:341 | 1:1 | |
| dwindle.c:546 `dwindle_remove_client` | MangoServer.swift:1262-1266 (inlined in unmap) | 1:1, name | |
| dwindle.c:556 `dwindle_insert_with_config` | Dwindle.swift:150 `dwindleInsertWithConfig` | differs | mango `fg = &focused->geom` of whatever `focused` dwindle_core passed, also a floating or not-in-tree client; ours `knownFrames[focused]` exists only for tiled clients, else falls back to the first leaf's frame. Scenario: A, B tiled, a wide floating dialog focused, new tiled window: mango picks split direction/side from the dialog's geom (and cursor relative to it), ours from leaf A. |
| dwindle.c:646 `dwindle_core` (static) | Dwindle.swift:72 `dwindleCore` | differs | Removal of vanished leaves (fullscreen/maximized kept) and gaps match. Anchor: mango `client_focus_top(m)` → if not in tree `m->sel` → if NULL `vis[0]`; ours `m.sel ?? first`. Same in the usual case; differs with a floating focus (see above). |
| dwindle.c:741 `cleanup_monitor_dwindle` | — (ARC frees Pertag with the Monitor) | 1:1 | same result |
| dwindle.c:746 `dwindle` | Layout.swift:225 | 1:1 | |
| dwindle.c:748 `dwindle_predict` | — | platform | |

### scroll.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| scroll.c:11 `ensure_scroller_state` | `TagLayoutState.scrollerState` Layout.swift:166 | 1:1, listed §5 | Always allocated. |
| scroll.c:21 `find_scroller_node` | Scroller.swift:11 `contains` (marked), :13 `columnIndex` | 1:1, name | |
| scroll.c:32 `scroller_node_create` | Scroller.swift:37 `insert`, :135 `updateScrollerState` | 1:1, listed §5 | Node proportions live on the Client in ours. |
| scroll.c:47 `scroller_node_remove` | Scroller.swift:46 `scrollerNodeRemove` | 1:1 | |
| scroll.c:74 `clear_scroller_state` | Scroller.swift:66 | 1:1 | Only tests call it. |
| scroll.c:87 `cleanup_monitor_scroller` | — (ARC) | 1:1 | |
| scroll.c:97 `sync_scroller_state_to_clients` | — (values kept on Client) | 1:1, listed §5 | Same result except the exchange case below. |
| scroll.c:109 `vertical_scroll_adjust_fullandmax` | Scroller.swift:229 via transpose | differs | As horizontal below. |
| scroll.c:143 `vertical_check_scroller_root_inside_mon` | Scroller.swift:201 via transpose | 1:1 | |
| scroll.c:152 `horizontal_scroll_adjust_fullandmax` | Scroller.swift:229 | differs | Computed 1:1, but `MangoServer.arrange` throws its frames away for fullscreen (`m.screen.frame`) and maximized (`config.gappoh/ov` box) clients (MangoServer.swift:507-521). Mango: in scroller, `client_tile_resize` does resize them (`\|\| is_scroller_layout`) after `reset_maximizescreen_size`, so the scroller frame wins. Scenarios: (a) maximized column not focused: mango places it beside the focused column at `x = neighbour ± gappih`, ours covers the work area; (b) focused maximized column with `togglegaps` off or smartgaps+single column: mango `w - 2*cur_gappoh` (0 gaps), ours keeps `config.gappoh`; (c) a fullscreen non-head stack member: mango gives it its stack slot, ours the monitor. |
| scroll.c:187 `horizontal_check_scroller_root_inside_mon` | Scroller.swift:201 | 1:1 | |
| scroll.c:198 `scroller_normalize_stack_weights` (static) | inside Scroller.swift:204 and Dispatch.swift:1119 `proportions()` | 1:1 | Mango persists the average into ≤0 weights; ours recomputes it each time. Same result (resize writes all weights of the stack). |
| scroll.c:230 `scroller_arrange_stack_node` | Scroller.swift:204 | 1:1 | |
| scroll.c:267 `scroller_arrange_stack_vertical_node` | Scroller.swift:204 via transpose | 1:1 | |
| scroll.c:305 `scroller_core` (static) | Scroller.swift:179 `scrollerCore`, :149 `arrange` | differs, listed §5 | Gaps (smartgaps w/o iv), single case, root/prevsel/fallback, need_scroller, overspread, need_center (prevsel clause), start_drag, x formulas, neighbour chains: all 1:1. Differences: column order from the port's `cols` (§5, not the client list); fullscreen/maximized frames overridden (above); `centerwin` via `centerRequest` (applied only if the request is in the focused column; mango sets `stack_head->geom.x` of any column, which also feeds the overspread INSIDEMON test) — near same result; next-column x from our column rect, not from the head's post-`resize` geom (differs only when a column is narrower than `1+2*bw`). |
| scroll.c:553 `vertical_scroller_core` (static) | Scroller.swift:149 via `LayoutSupport.transposed` | differs | Besides the above: mango subtracts only `group_bar_height` from the root's/upper neighbour's `geom.y` (`bar_height`), while `client_tile_resize` also shifts by `tab_bar_height`; ours adds back both bars (`topBars`, MangoServer.swift:463). Scenario: vertical_scroller, focused column head in a tab chain, need_scroller false: mango moves the column down by tab_bar_height on every arrange; ours stays put. A mango bug fixed silently (not in §6). |
| scroll.c:806 `scroller_remove_client` | MangoServer.swift:1262-1264 | 1:1 | All monitors, all pertags. |
| scroll.c:821 `scroller_insert_stack` | Scroller.swift:95 `scrollerDropTile(intoStack:true)` / :72 `scrollerApplyStack` | differs | Mango clears fullscreen and maximize of `c` and of the stack head (`client_set_fullscreen(…,0)`, `client_set_maximize_screen(…,0)`) and moves `c` next to the target in the client list (`wl_list_safe_reinsert_prev/next`). Ours does neither on the `scroller_stack` (Dispatch.swift:133) and drag-drop (DragTile.swift:123) paths. Scenario: column head maximized, `scroller_stack` another window into it: mango un-maximizes the head; ours leaves it maximized over the work area. |
| scroll.c:877 `scroller_drop_tile` | DragTile.swift:117-124 + Scroller.swift:95 | differs | Column placement equal, but mango orders the client list (`reinsert_prev(stack_head)`, `reinsert_next(stack_head)`, and via insert_stack), ours leaves `clients` untouched for scroller drops. Scenario: drag a window to the left of a column, then switch to `tile`: mango's order (and master) reflects the drop, ours does not; focusstack order too. |
| scroll.c:927 `scroll_get_stack_head_client` | Dispatch.swift:800 | 1:1 | Uses the monitor's current tag state where mango uses `get_client_tag_idx(c)` (same for visible clients). |
| scroll.c:943 `scroll_get_stack_tail_client` | — (`column(of:).last` where needed) | 1:1, listed §5 | No function; its callers' work is on the column array. |
| scroll.c:959 `update_scroller_state` | Scroller.swift:135 (private) | 1:1, listed §5 | unsure: new columns are placed by client-list index relative to existing heads, equal to mango only while `cols` mirrors the client list (see drop/exchange rows). |
| scroll.c:1005 `scroller_swap_nodes_in_same_stack` | Scroller.swift:117 (same-column `swapAt`) | differs | Mango swaps the nodes' `scroller_proportion/stack_proportion/stack_weight` too, so heights stay with the positions; ours swaps ids while `scrollerStackWeight` stays on each Client. Scenario: a stack split 70/30, `exchange` the two: mango keeps 70 on top, ours moves 70 to the bottom with the window. |
| scroll.c:1056 `scroller_swap_different_stacks` | Scroller.swift:117 (`cols.swapAt`) + Dispatch.swift:1342 | differs | Mango swaps the two stacks' ranges in the client list; ours swaps columns but not `clients` (`clientExchange` only calls `swapList` for the same stack). Scenario: exchange two columns, switch to tile: mango's master changes, ours not. |
| scroll.c:1095 `exchange_two_scroller_clients` | Dispatch.swift:1342 `clientExchange` (scroller branch) + Scroller.swift:117 | differs | Guards match (`!n1 && !n2`, cross-monitor with a stack). Differs through the two rows above. |
| scroll.c:1150,1156 `scroller`, `vertical_scroller` | Layout.swift:230-231 | 1:1 | |
| scroll.c:1152,1158 `scroller_predict`, `vertical_scroller_predict` | — | platform | |

### overview.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| overview.c:10 `compare_layout_items` | sort closure, Mango/Layout/Overview.swift:21 | 1:1 | unsure: equal areas — ours stable by index; glibc `qsort` order for ties is unspecified (introsort since 2.37). Windows of equal size are common. |
| overview.c:20 `begin_jump_mode` | Mango/Engine/OverviewMode.swift:264 | 1:1 | + marked `publishInputState`. |
| overview.c:22 `try_place` | Overview.swift:152 | 1:1 | Same candidate order, dedupe, feasibility, best rule. |
| overview.c:92 `center_placed_rows` (static) | Overview.swift:181 | 1:1 | |
| overview.c:217 `overview_scale` | OverviewMode.swift:214 + Overview.swift:7 | 1:1 | 50-step bisection, rounding `(int)(x+0.5f)`; boxes clamped to ≥1 (mango none). Cards drawn by the port (§5). |
| overview.c:361 `overview_layout_column` | Overview.swift:121 (nested) | 1:1 | |
| overview.c:419 `overview_scale_tab` | OverviewMode.swift:222 + Overview.swift:70 | 1:1 | gap swap/halving, center ratio, title block, rotation. |
| overview.c:548 `create_jump_hints` | OverviewMode.swift:269 | 1:1, listed §5 | |
| overview.c:575 `finish_jump_mode` | OverviewMode.swift:295 | 1:1 | |
| overview.c:594 `overview` | OverviewMode.swift:251 | 1:1 | + marked title-bar geometry call. |

Macros used by these files (defined in manage/client.h / monitor.h): `ISTILED`, `ISFAKETILED`, `ISSCROLLTILED`
written out per use (MangoServer.swift:366-372, 413); `VISIBLEON` = `Client.isVisible(on:)` (Engine/Client.swift:128)
which adds `!groupParked` (group parking, other group's area); `INSIDEMON`/`GEOMINSIDEMON` = Scroller.swift:198 — 1:1.

## Not in mango (in the Swift files looked at)

| ours (file:line) | marked? | note |
|---|---|---|
| Mango/Layout/Layout.swift:54 `LayoutKind.isVertical` | no | helper |
| Layout.swift:58 `isMonocleLike` | yes | port parking |
| Layout.swift:64-120 `Gaps`, `LayoutClient`, `PertagSettings`, `LayoutInput` | no | input structs for the pure layouts (mango reads Monitor/Client directly) |
| Layout.swift:133 `LayoutInput.mfact` | no | is the `fc->master_mfact_per > 0 ? … : mfacts[tag]` line of each core |
| Layout.swift:137 `smartGapped` | no | is the smartgaps lines of each core |
| Layout.swift:149 `fullscreenInView`, :127 `prevFocusedScroll`, `startDragWindow` | no | fields standing for VISIBLEON+fullscreen, `m->prevsel`, `server.start_drag_window` |
| Layout.swift:152-170 `GridPlace`, `LayoutResult` (`hidden` marked), `TagLayoutState` | partly | |
| Layout.swift:185 `sanitized()` | yes | |
| Layout.swift:217 `LayoutEngine.arrange` | no | stands for `ltidxs[tag]->arrange(m)` |
| TileLayouts.swift:4,16 `IRect`, `IGaps` | no | int boxes |
| TileLayouts.swift:27 `finish`, :53 `transposed`, :71 `f32`, :74 `visibleOne` | yes | |
| TileLayouts.swift:89 `tileCore(right:)` | no | merges tile_core + right_tile_core without a mark |
| TileLayouts.swift:349 `verticalDeck` `hidden` | no | same solver-only `hidden` as `deck` (marked there) |
| GridLayouts.swift:20 `shares`, :40 `assign` | yes | |
| GridLayouts.swift:12,33 vertical variants as transposes | partly (`shares` says so) | vertical_grid_core/vertical_fair_core have no own body |
| Dwindle.swift:16,30 `Node.lastFrame`, `knownFrames` | no | stand for `c->geom` reads in insert_with_config / move_next_to (source of the dwindle differs rows) |
| Dwindle.swift:35 `contains` | yes | |
| Dwindle.swift:37 `dwindleFocusBlockRoot` | no | mango `dwindle_focus_block_root` is a static in manage/client.c:1433, not dwindle.c (name fine, location/comment line missing) |
| Dwindle.swift:49 `clientOrder` | no | only used by tests |
| Dwindle.swift:60 `leaves` | yes | |
| Dwindle.swift:204 `drop`, :302 `replace`, :403 `dwindleSetSplitDirection`, :415 `leafSplitHorizontal` | yes | |
| Dwindle.swift:408 `dwindleToggleCurrentSplit` | no | bind.c's dispatcher body on the tree |
| Scroller.swift:4 `ScrollerState` (`cols`, `centerRequest`) | listed §5, `centerRequest` no | |
| Scroller.swift:16,21,29,37,61,111 `column`, `columns`, `position`, `insert`, `moveColumnToFront`, `replace` | yes | `position(of:)` only used by tests |
| Scroller.swift:53 `exitScrollerStack` | no | mango `exit_scroller_stack` (client.c:3683) removes the node; ours moves the window into its own column at `ci+1`, and does nothing for a single-window column (other group's function, but it lives here) |
| Scroller.swift:72 `scrollerApplyStack` | no | bind.c `scroller_apply_stack` on the column array; no fullscreen/maximize clearing, no client-list reorder |
| Scroller.swift:95 `scrollerDropTile` | no | mango name, but does both `scroller_insert_stack` and the column insert of `scroller_drop_tile` |
| Scroller.swift:108 `centerWindow` | no | bind.c `center_window`'s scroller part as a request |
| Scroller.swift:149 `ScrollerState.arrange` | no | stands for scroller()/vertical_scroller() |
| Engine/MangoServer.swift:360,366,374,398 `visibleClients`, `tiledClients`, `specialClients`, `arrangeAll` | yes | |
| Engine/MangoServer.swift:32 `ArrangeAnimation` (.none/.move/.tag) | no | stands for `(want_animation, from_view)`; conflation causes the special_handle_empty_view row |
| Dispatch.swift:999 `resizeTileMaster` | yes | |
| Layout/DropArea.swift, Layout/SwitcherLayout.swift | — | mango's `client_set_drop_area` (pointer.c) and switcher.c; not in my files, not audited |

## Summary

Counts over 111 mango items (functions, static helpers, wrappers, predicts, the layouts table):
- 1:1: 69 (of which listed §5: 6, listed §6: 1 [resize_tile_grid_fair]; name: 3) — the dwindle lock statics row is not counted
- differs: 26 (3 of them — tile, right_tile, vertical_tile — also carry the listed §6 rounding fix)
- missing: 1 (`check_size_per_valid`, assert only)
- platform: 15 (14 `*_predict` + `layout_predict_box`; none user-visible, none unlisted)
- port: 0

Most significant deviations, most significant first:
1. **Scroller `exchange` within a stack** (`scroller_swap_nodes_in_same_stack`): mango keeps the stack heights by position, ours moves them with the windows (70/30 becomes 30/70).
2. **Scroller fullscreen/maximized frames overridden by `arrange`** (`horizontal/vertical_scroll_adjust_fullandmax`): a maximized non-focused column covers the work area instead of standing beside the focused one; focused maximized ignores `togglegaps`/smartgaps; a fullscreen stack member fills the monitor instead of its slot.
3. **`scroller_insert_stack` / `scroller_stack` / drop**: fullscreen/maximize of the moved window and the stack head are not cleared; the client list is not reordered (`scroller_drop_tile`, `scroller_swap_different_stacks`), so tile order, master and focusstack differ after leaving the scroller.
4. **`arrange` in overview returns before `pre_calculate`, special handling, tab sync and tag_gather**; and `arrange` never sends `printstatus(IPC_WATCH_ARRANGGE)`.
5. **`special_handle_empty_view`'s `from_view` read from the animation kind**: returning from the overview to an empty special tag (or any `view` with want_animation false) closes the special tag where mango keeps it.
6. **`vertical_grid_core` mango bug fixed silently**: mango counts visible floating windows in its index (a tiled window can be left unplaced); ours does not. Not in §6, no mark, no test.
7. **`resize_tile_master_*` / `resize_tile_scroller` divide by the content size, not `geom`** (2*borderpx smaller): every drag/keyboard step is slightly larger than mango's.
8. **`master_mfact_per` write-back missing** in tile/right_tile/center_tile/deck/vertical_tile/vertical_deck: after a fullscreen first client, the split can jump when that client goes.
9. **`resize_tile_client` has no per-frame coalescing for tiled resizes** (unlisted; §3 covers floating only); **`resize_tile_scroller`'s "more than one column" ignores fullscreen/maximized columns**.
10. **Dwindle insert anchor** (`dwindle_core`/`dwindle_insert_with_config`): with a floating window focused, mango splits by that window's geom (via `client_focus_top`), ours by the first leaf's frame; plus `vertical_scroller_core`'s tab-bar drift (mango bug) silently fixed.

Also: dead/test-only code in the core: `DwindleTree.clientOrder`, `dwindleFreeTree`, `ScrollerState.clearScrollerState`, `position(of:)`.
