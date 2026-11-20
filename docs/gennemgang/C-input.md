# C-input: src/input/{pointer,keyboard,trackpad,device,touch,tablet,switch}.c, include/mango/input/*.h

Status 2026-11-20 (trin 10): hvert fund er mærket ✓ (rettet, som mango, listet, væk) eller åben, kontrolleret mod koden efter trin 9.

Paths: mango = `~/sources/mango/src/input/`; ours relative to `Sources/`. "Input" = `Mango/Engine/Input.swift`,
"DragTile" = `Mango/Engine/DragTile.swift`, "LG" = `Mango/Engine/LiveGestures.swift`, "KB" = `Mango/Engine/Keyboard.swift`,
"PT" = `Mango/Engine/Pointer.swift`, "CH" = `Mango/Engine/CursorHide.swift`, "MS" = `Mango/Engine/MangoServer.swift`,
"IR" = `Port/macOS/InputRouter.swift`, "MWS" = `Port/macOS/MacWindowSystem.swift`.

## Functions

### pointer.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| pointer_surface_scale :44 | - | platform | Xwayland scale |
| pointer_constraint_sync_region :55 | - | platform | pointer-constraints protocol (listed §5 under client_focus) |
| pointer_region_closest_point :69 | - | platform | pointer constraints |
| pointer_client_warp_box :89 | (inline `c.frame`) Input:312-341 | 1:1 | same result: our frame is geom minus border, and the confine maths add `bw` back |
| pointer_constraint_hint_position :100 | - | platform | pointer constraints |
| pointer_locked_constraint_applies :121 | - | platform | pointer constraints |
| pointer_follow_constraint_hint :141 | - | platform | pointer constraints |
| pointer_cursor_outside_client :158 | Input:319 (`!c.frame.contains`) | differs ✓ rettet i trin 7 | minor: mango's box includes the border (`geom`), ours is `c.frame` without it. Pointer resting on the confined window's border when it gains focus: mango leaves it, ours warps it to the centre |
| pointer_node_enabled :165 | - (in pointerConfineRuleClient Input:311) | missing ✓ rettet i trin 7 | `c->scene->node.enabled` (ours `!c.parked`) not checked in the confine rule client; same result in practice (a parked window is not VISIBLEON) |
| pointer_client_visible :174 | - | platform | used only by constraints |
| pointer_confine_rule_client :183 | pointerConfineRuleClient Input:311 | 1:1 | seat's keyboard surface falls back to `selmon->sel` (`focused`); port |
| pointer_check_confine_client :202 | pointerCheckConfineClient Input:317 | 1:1 | border nuance via pointer_cursor_outside_client |
| pointer_client_destroyed :213 | - | missing ✓ rettet i trin 5 | `confinePointerLast` (MS:75) is never cleared on destroy; same result (window IDs are not reused) |
| pointer_constraint_surface_visible :219 | - | platform | constraints |
| pointer_warp_into_constraint :235 | - | platform | constraints |
| pointer_confine_client :268 | - | platform | constraints |
| toggle_hotarea :312 | toggleHotarea Input:287 | 1:1 | corners/conditions identical; mango truncates the cursor to int and uses `unsigned` hx/hy (sub-pixel / straddling-0 edge only) |
| handle_cursor_axis :405 | IR.scroll :281 + PT.handleCursorAxis :29 | port | binding match, timeout and dir 1:1; forward with scroll factor is listed. Differs: no `pointer_cursor_activity()` (CH:4) on scroll, and no `ipc_notify_device_event` (see Summary 2, 4) |
| handle_cursor_button :476 | IR.mouseButton :177 → pointerProcessButtonPress | port | no `ipc_notify_device_event` |
| handle_last_cursor_surface_destroy :486 | - | platform | client cursor surfaces |
| handle_request_set_cursor_shape :492 | - | platform | apps set their own cursor (listed §3) |
| pointer_set_accel :516 | - | platform | listed (mouse_*/trackpad_*) |
| configure_pointer :532 | - | platform | listed (libinput keys, device_rule) |
| pointer_create :626 | - | platform | |
| handle_pointer_constraint_commit :647 | - | platform | |
| handle_new_pointer_constraint :667 | - | platform | |
| pointer_constrain_cursor :697 | - | platform | |
| handle_cursor_frame :733 | - | platform | |
| pointer_warp_to_constraint_hint :743 | - | platform | |
| handle_drag_icon_destroy :757 | - | platform | Wayland DnD |
| handle_pointer_constraint_destroy :765 | - | platform | |
| handle_cursor_motion_absolute :786 | - | platform | macOS only gives absolute positions; all go to handleCursorMotion |
| client_resize_grab :814 | clientResizeGrab Input:454 | 1:1 | |
| tiled_shared_edges :825 | tiledSharedEdges Input:464 | 1:1 | uses `clientGeom` (frame+bw) for `geom` |
| client_resize_edge_at :857 | clientResizeEdgeAt Input:503 | 1:1 | scene enabled = `!parked` (marked) |
| resize_cursor_name :900 | resizeCursorName Input:534 | 1:1 | |
| pointer_update_resize_cursor :907 | pointerUpdateResizeCursor Input:539 | 1:1 | CurNormal = no grab and no button (marked); `seat->drag` covered by the button test |
| pointer_resize_floating_window :946 | pointerResizeFloatingWindow Input:408 | 1:1 | maths identical; `resize(.drag_edge = edge)` becomes `setFrame` without the edge, so the anchoring of an app-clamped size is the port's (unsure if visible) |
| client_begin_drag_float :989 | clientBeginDragFloat DragTile:9 | differs ✓ rettet i trin 7 | ours lacks `exit_scroller_stack(c)` and `old_stack_inner_per = old_master_inner_per = 0`, sets `isFloating`/`floatGeom = frame` directly instead of `client_set_floating(c,1,false)` (grab branch: no recentre, `arrange(m, false)`; ours `arrange(m, .move)`), and calls `set_size_per` before the float instead of after. Scenario: drag a window out of a scroller stack with drag_tile_to_tile=0; mango has taken it out of the stack, ours still lists it there (unsure what becomes visible on re-tile) |
| pointer_begin_move_resize :999 | pointerBeginMoveResize Input:195 | 1:1 | extra `|| c.scratchpadShown` beside `isfloating` (same result if a shown scratchpad is always floating); cancelAnimation marked |
| pointer_end_grab_client :1086 | pointerEndGrabClient Input:250 | 1:1 | partial `pointer_process_motion(0)` (listed §2); ours adds `arrange(target, …)` mango does not call on the same monitor (client_set_monitor returns early) — same result for a floating move, unsure for others |
| group_bar_target_at :1147 | groupBarTargetAt DragTile:46 | differs åben: stadig en strip over vinduer med gruppebjælke, ingen fanebjælker eller stabling (input/pointer.swift:457-471) | unsure: mango hit-tests any bar node (group, tab, title bar) under the pointer and returns `client_group_active(owner)`; ours tests only a strip `group_bar_height` above each visible client with a group bar and returns that client |
| pointer_process_motion :1178 | pointerProcessMotion Input:332 | differs åben: kun gruppebjælkens lukkeknap-hover mangler (input/pointer.swift:524); resten rettet i trin 7 | **sloppy focus is not focus-on-enter** (see pointer_focus). Also: rule-confine clamp skipped during a grab (`grab == nil`; mango clamps regardless of cursor_mode); group-bar close-button hover (`mango_bar_decoration_set_close_hover`) missing; scroller lock: no `!c->animation.running` when clearing it, `ISSCROLLTILED` instead of `ISTILED` when setting it; "default" cursor platform; relative motion, constraints, drag icon platform |
| handle_cursor_motion :1425 | handleCursorMotion Input:325 (from IR.mouseMoved :258 / dragged :236) | port | 1:1 order (motion then toggle_hotarea); no ipc_notify_device_event |
| pointer_focus :1445 | (inlined) Input:388-404 | differs ✓ rettet i trin 7 | mango focuses only when the pointer *enters* a different surface (`surface != pointer_state.focused_surface`), and every arrange / client_focus / warp re-enters the surface under the pointer via `pointer_process_motion(0)` without focusing. Ours focuses whenever the pointer moves over a window that is not `sel` (Input:403). Scenario: sloppyfocus=1 (default), pointer resting on A, a floating dialog opens elsewhere and takes focus; a 1-px nudge: mango keeps the dialog, ours focuses A. Also missing `!c->animation.tagining`. Listed §2/§5 only as "Ingen synlig" for the motion(0) part, which is wrong here |
| handle_request_start_drag :1514 | - | platform | DnD |
| handle_request_set_cursor :1524 | - | platform | listed §3 |
| handle_start_drag :1566 | - | platform | DnD |
| pointer_cursor_activity :1576 | pointerCursorActivity CH:4 | 1:1 | timer as asyncAfter (listed §3); the `/// mango pointer_cursor_activity` line sits on armCursorHideTimer (CH:14), not here |
| pointer_hide_cursor :1593 | pointerHideCursor CH:33 | 1:1 | |
| pointer_warp_to_client :1599 | pointerWarpToClient MS:830 | differs ✓ rettet i trin 7 | no `pointer_process_motion(0)` after the warp (feeds the pointer_focus deviation); overview card marked |
| pointer_warp_to_monitor :1608 | pointerWarpToMonitor MS:837 | differs ✓ rettet i trin 7 | no `pointer_cursor_activity()` (and "default" cursor). Scenario: cursor_hide_on_keypress=1, `focusmon` with warpcursor: mango shows the cursor on the new monitor, ours leaves it hidden until the mouse moves |
| handle_new_virtual_pointer :1615 | - | platform | protocol, unlisted (not user-visible) |
| find_closest_tiled_client :1627 | findClosestTiledClient DragTile:30 | 1:1 | same result (hypot vs squared int distance, same order; first wins) |
| pointer_place_drag_tile :1658 | pointerPlaceDragTile DragTile:89 | 1:1 | UNDIR/rightTile/default/dwindle branches 1:1; scroller branch maps to `scrollerDropTile` (body is the layout group's, unsure); group join folded in (mango does it in the release path) |
| pointer_process_button_press :1717 | pointerProcessButtonPress Input:128 (+ PT:14 on the tap thread) | 1:1 | order and branches match; click-focus skips listed §3; border-resize tap listed §3. Minor: the tap decides mouse bindings before bars, so a modifier+click on a group/tab bar runs the binding where mango handles the bar first (and for a tab bar also `client_handle_decorate_click`) |

### keyboard.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| handle_keyboard_key_watch :28 | - | missing ✓ listet: afvigelser.md §3 | `ipc_notify_device_event`; `mmsg watch all-devices` never streams (IPCJSON nullDevice); unlisted |
| find_device_rule :34 | - | platform | device_rule listed |
| keyboard_create :106 | - | platform | |
| device_rule_has_keyboard_settings :146 | - | platform | |
| compile_rule_keymap :157 | - | platform | xkb |
| keyboard_repeat :182 | - | platform | listed (repeat_rate/delay; macOS repeats) — same result for pass-only binds (mango does not repeat unhandled keys either) |
| is_keyboard_shortcut_inhibitor :199 | - | platform | listed (allow_shortcuts_inhibit) |
| keyboard_process_global_keypress :210 | publishGlobalKeys Input:48 + KB.handleUnboundKey :97 + IR | differs ✓ listet: afvigelser.md §3; NONE rettet i trin 7, pid-reglen mærket (input/keyboard.swift:27) | name (publishGlobalKeys, marked). Port forwards to a pid. Differs: mango skips a rule whose `globalkeybinding.mod` is 0; ours accepts `NONE-key` (Modifiers.parse "none" → []), so F5 with no modifier is taken from every app. Ours also drops the rule when the first matching window shares the focused window's pid (Input:60, unmarked); mango sends to that window |
| handle_keyboard_shortcuts_inhibitor_destroy :271 | - | platform | |
| handle_keyboard_shortcuts_inhibit_new_inhibitor :283 | - | platform | listed |
| keyboard_sync_keymap :321 | - | platform | Xwayland |
| standalone_keyboard_apply_config :330 | - | platform | device_rule |
| create_standalone_keyboard :374 | - | platform | |
| invalidate_saved_seat_keyboard :400 | - | platform | |
| restore_seat_keyboard :415 | - | platform | |
| keyboard_hard_modifiers :431 | MWS.keyboardHardModifiers :606 | port | |
| handle_standalone_keyboard_destroy :444 | - | platform | |
| keyboard_group_create :462 | - | platform | numlock_on listed; `capslock` is a field with no key |
| keyboard_group_destroy :535 | - | platform | |
| keyboard_bound_key_index :555 | KeyboardState.boundKeys KB:37 | 1:1 | name (a Set); same result (mango caps at 32 keys) |
| keyboard_is_bound_key :563 | KB.handleKeyboardKey | 1:1 | name |
| keyboard_mark_bound_key :568 | KB.handleKeyboardKey | 1:1 | name; marked after the dispatch is decided, not before it runs (same result) |
| keyboard_unmark_bound_key :577 | KB.handleKeyboardKey | 1:1 | name |
| keyboard_check_keybinding :585 | KB.keyboardCheckKeybinding :5 | differs ✓ listet: afvigelser.md §3 (keysym); handled rettet i trin 7 | matches keycodes only, never `KEY_TYPE_SYM` with `xkb_keysym_to_lower` (keysym model deferred by the user 2026-11-14, but not in docs/afvigelser.md). `handled` is a sticky OR in ours; mango overwrites it per match, so an allow-conflict non-pass bind followed by a `bindp` match passes the key in mango and swallows it in ours. Break after setkeymode/chvt/reload_config/load_config_file = mango's nonzero returns (1:1). Modifier-key mods translation (keyModifier) reproduces wlroots' pre-update mods (1:1) |
| keyboard_cancel_pending_release_bind :656 | IR.cancelPendingReleaseBind :171 (WindowSystem) | port | |
| keyboard_find_jump_client :663 | keyboardFindJumpClient OverviewMode:373 | 1:1 | |
| handle_keyboard_key :680 | KB.handleKeyboardKey :67 + handleUnboundKey :97 + MangoServer.handleKeyboardKey Input:68 + IR.key :81 | differs ✓ rettet i trin 7 | minor: `ISMODEKEYCODE` is the 8 Shift/Ctrl/Alt/Super keycodes; ours is any flagsChanged key, so releasing Caps Lock or Fn commits the switcher / leaves overcircle. Jump mode decided on the tap (listed §5). Order of hide-cursor/tag_combo/overcircle differs, same result |
| handle_keyboard_modifiers :837 | MWS :548 (TIS notification → printstatus) | port | layout change → printstatus; seat part platform |
| reset_keyboard_layout :874 | resetKeyboardLayout MS:251 | port | listed §3 (xkb_rules_options) |
| handle_new_virtual_keyboard :968 | - | platform | protocol |

### trackpad.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| pointer_is_trackpad :36 | - | platform | listed (trackpad_scroll_factor) |
| check_trackpad_disabled :49 | - | platform | listed (disable_trackpad) |
| trackpad_enabled :56 | - | platform | listed |
| fire_gesture_motion :58 | fireGestureMotion Input:573 | 1:1 | |
| swipe_opposite_motion :80 | LG:9 | 1:1 | |
| trackpad_gesture_drag_active :122 | LG:5 | 1:1 | the tap does not know it, so a click during a gesture drag still reaches the app (minor) |
| view_opposite_func :126 | LG:16 | 1:1 | |
| swipe_func_is_view :142 | LG:28 | 1:1 | |
| swipe_func_is_overview :146 | LG:30 | 1:1 | |
| swipe_layout_is_scroller :151 | LG:34 | 1:1 | |
| swipe_func_drivable :170 | LG:47 | 1:1 | |
| swipe_find_binding :208 | LG:79 | 1:1 | `!isUndir` = UNDIR never equals a motion |
| swipe_has_running_transition :228 | LG:87 | 1:1 | tagining = running `.tag` action; need_output_flush is the port's |
| swipe_drive_log_state :241 | LG:95 | 1:1 | |
| swipe_drive_freeze :275 | LG:119 | 1:1 | |
| swipe_drive_unfreeze :280 | LG:124 | 1:1 | |
| swipe_drive_axis :285 | LG:129 | 1:1 | |
| swipe_drive_apply :289 | LG:133 | 1:1 | |
| swipe_drive_pan_target :305 | LG:142 | 1:1 | |
| swipe_drive_apply_pan :344 | LG:175 | 1:1 | scene/clip as setFrame (marked) |
| swipe_drive_pan_offset :370 | LG:197 | 1:1 | |
| swipe_drive_pan_flick_target :407 | LG:229 | 1:1 | |
| swipe_drive_begin :450 | LG:261 | 1:1 | |
| swipe_drive_fire_opposite :542 | LG:337 | 1:1 | |
| swipe_drive_apply_drag :581 | LG:376 | 1:1 | wlr_cursor_move as warp (marked) |
| swipe_drive_update :606 | LG:401 | 1:1 | |
| swipe_drive_end :672 | LG:458 | 1:1 | |
| handle_cursor_swipe_begin :803 | LG:560 | 1:1 | listed §3 |
| handle_cursor_swipe_update :826 | LG:573 | 1:1 | listed §3 |
| handle_cursor_swipe_end :846 | LG:582 | 1:1 | never cancelled, listed §3 |
| handle_cursor_pinch_begin :871 | - | missing ✓ listet: afvigelser.md §5 | its one mango step, `keyboard_cancel_pending_release_bind()`, is not done (the port tracks only 3+ finger swipes). Scenario: `bindr=SUPER,Super_L`, hold Super and pinch-zoom: mango cancels the release bind, ours fires it |
| handle_cursor_pinch_update :885 | - | platform | forward to client |
| handle_cursor_pinch_end :898 | - | platform | forward to client |
| handle_cursor_hold_begin :910 | - | missing ✓ listet: afvigelser.md §5 | as pinch_begin |
| handle_cursor_hold_end :924 | - | platform | |
| pointer_process_swipe_end :937 | LG:598 | 1:1 | |

### device.c, switch.c, touch.c, tablet.c

| mango (file:line) | ours | status | note |
|---|---|---|---|
| device.c: handle_input_device_destroy :18, seat_device_provides_capability :50, seat_has_capability :68, update_seat_capabilities :78, handle_seat_device_destroy :97, seat_device_add :107, handle_new_input_device :118 (7) | - | platform | wlr seat/devices |
| switch.c: handle_switch_toggle :10, switch_create :33 (2) | - | platform | listed (switchbind) |
| touch.c: touch_apply_monitor_mapping :46, touch_create :60, handle_touch_point_surface_destroy :73, touch_get_coords :85, touch_emulate_move_absolute :108, touch_emulate_button :120, touch_apply_xwayland_scale :136, handle_cursor_touch_down :149, _motion :224, _up :263, _cancel :302, _frame :345, touch_finish_all :356 (13) | - | platform | listed (touch_enable, touch_enable_mouse_emulation) |
| tablet.c: tablet_create :19, handle_tablet_destroy :75, handle_tablet_pad_tablet_destroy :83, attach_tablet_pad :94, handle_tablet_pad_attach :102, tablet_pad_create :115, handle_tablet_pad_destroy :169, handle_tablet_tool_surface_destroy :180, handle_tablet_tool_destroy :187, handle_tablet_tool_set_cursor :197, tablet_tool_motion :215, handle_tablet_tool_proximity :313, _axis :361, _button :396, _tip :406 (15) | - | platform | unlisted; macOS delivers tablets as mouse events, which take the pointer path |

### Macros and constants (headers / statics)

| mango | ours | status | note |
|---|---|---|---|
| CLEANMASK keyboard.h | `mods.subtracting(.fn)` | 1:1 | caps is not in our Modifiers; fn is the port's |
| ISMODEKEYCODE keyboard.h | `ev.isModifierKey` (EventTap flagsChanged) | differs ✓ rettet i trin 7 | includes Caps Lock (57) and Fn (63); see handle_keyboard_key |
| KEYBOARD_MAX_KEYSYMS | - | platform | xkb |
| KEYBOARD_MAX_BOUND_KEYS (32) | Set | 1:1 | same result |
| CONFINE_POINTER_MARGIN (5) | literal 5 Input:338 | 1:1 | |
| SWIPE_LOCK_DISTANCE, SWIPE_FLICK_MAX_MS | SwipeDrive.swift:3-4 | 1:1 | |

Config keys read in these files (hotarea_*, axis_bind_apply_timeout, cursor_hide_*, enable_border_resize, border_resize_size, drag_corner, drag_warp_cursor, drag_tile_*, sloppyfocus, edge_scroller_*, gesture_*, swipe_min_threshold, monocle_right_button_close): defaults and clamps checked against `option_defs.c`, all match (`Model/Config.swift`, `Config/ConfigOptions.swift`).

## Not in mango (in the Swift files looked at)

| ours (file:line) | marked? | note |
|---|---|---|
| `Grab` struct Input:3 | partly | fields carry mango names in doc lines; the struct (mango: `server.grab_client`, `cursor_mode`, `grab_offset_*`) is unmarked |
| publishInputState Input:19 | yes | tap snapshot |
| `xkbOptions` Input:43 | no | splits xkb options for the port; port helper in the core |
| handleKeyboardKey(_ actions:) Input:68 | yes | |
| clientAtPoint Input:101, surfaceAt Input:114, clientGeom Input:120 | yes | node_at_point stand-ins |
| `pointerProcessMotion` return value Input:331 | yes | |
| `enum Keyboard` KB:4, `enum Pointer` PT:4 | yes | tap-thread decisions |
| `KeyboardState` KB:37, `KeyAction` KB:44, `KeyInput` KB:54, `Pointer.ButtonPress` PT:5 | no | types for the tap split; unmarked |
| `handleUnboundKey` KB:97 | yes (`/// mango handle_keyboard_key`) | tail of handle_keyboard_key |
| `armCursorHideTimer` CH:15 | wrongly | carries `/// mango pointer_cursor_activity (pointer.c)` but is the hide timer (wl_event_source); pointerCursorActivity itself (CH:4) has mango's name |
| `DragTile` struct DragTile:3 | no | stands for `c->drag_to_tile` + `drag_tile_float_backup_geom` |
| tileBox DragTile:41, dropTarget :55, updateDragTile :67, dropDraggedTile :79 | yes | |

## Summary

Counts (166 mango items: 159 functions + 7 macros/constants):
- 1:1: 55
- differs: 11
- missing: 5
- platform: 88 (unlisted: tablet (15), virtual pointer/keyboard, device-event IPC is counted under missing)
- port: 7
- name tag: publishGlobalKeys, boundKeys helpers (4)

Most significant deviations, most significant first:
1. **Sloppy focus is focus-on-motion, not focus-on-enter** (pointer_focus / pointer_process_motion, Input:403; pointer_warp_to_client MS:830). Mango focuses only when the pointer enters a different surface, and re-enters the surface under the pointer without focusing after every arrange, client_focus and warp. Ours refocuses the window under the pointer on any motion when it is not `sel`. A dialog or new window that takes focus loses it to the window under the pointer at the next nudge. Docs §2 calls the dropped `pointer_process_motion(0)` "no visible effect", which is not true here.
2. **Scrolling is not pointer activity** (handle_cursor_axis): with cursor_hide_timeout set, the cursor hides while you scroll and a scroll does not show a hidden cursor.
3. **pointer_warp_to_monitor without pointer_cursor_activity** (MS:837): after a keypress hid the cursor, `focusmon` leaves it hidden.
4. **ipc_notify_device_event never sent** (axis, button, motion, key_watch): `mmsg watch all-devices` streams nothing. Unlisted.
5. **client_begin_drag_float** (DragTile:9): no `exit_scroller_stack`, no reset of `old_*_inner_per`, a different arrange, and the set_size_per order differs. Unsure what becomes visible.
6. **keyboard_check_keybinding matches keycodes only, never keysyms.** The user deferred this on 2026-11-14, but docs/afvigelser.md does not list it.
7. **globalkeybinding**: `NONE-key` is accepted (mango requires a modifier), and the rule is dropped when the matching window shares the focused app's pid (unmarked).
8. **group_bar_target_at**: a geometric strip above the group bar instead of mango's hit test of any bar plus `client_group_active` (unsure).
9. **Group-bar close-button hover highlight** (pointer_process_motion → set_close_hover) is missing.
10. Smaller items:
   - pinch/hold begin do not cancel a pending release bind.
   - `handled` is a sticky OR with bindp plus allow-conflict.
   - Caps Lock/Fn count as mode keys (ISMODEKEYCODE).
   - The rule-confine clamp is skipped during a grab.
   - pointer_focus lacks `!tagining`.
   - The scroller lock uses ISSCROLLTILED where mango uses ISTILED and lacks `!animation.running`.
   - A modifier mouse binding beats a bar click.
