# Fidelity audit: every mango function against `Sources/Mango`

Date: 2026-11-15. Reference: mango 0.18.5, commit 21f80a9. Our side: commit da81bb9.

Every function, macro and config key in mango's tree (`src/`, `include/`, `mmsg/`, `mangonag/`,
`assets/config.conf`) was compared with ours, one at a time. Nine readers each took one area
and classified every item. Five other readers then tried to refute each `differs` or `missing`
row, reading both sides again. A finding is on this list only if it survived that. Nothing in
either repo was changed.

**How to use it.** This file is the work list, by theme. Each area has two files: the full
inventory (`<area>.md`, one row per mango function, including all `1:1` rows), and its
verification (`<area>-verified.md`), with mango and our file:line for each finding and a
scenario. Where the two disagree, the verified file wins. Once a deviation is fixed, its
row is struck here. One that is kept is moved to `docs/afvigelser.md`.

## Status 20. november (trin 10)

Hvert fund nedenfor og i områdefilerne er mærket mod koden efter trin 9: `✓ rettet i trin N`,
`✓ rettet 15. nov.`, `✓ som mango nu`, `✓ listet: afvigelser.md §N`, `✓ væk` eller `åben`. Næsten
alt er rettet i ombygningen (trin 1–9). Tilbage er:

**Lukket 20. november (efter trin 10)**
- ✓ `node_at_point` går lagene igennem oppefra (`client_target_layer`); i laget vinduesserverens
  øverste, ellers fokus-stakken (`manage/misc.swift`).
- ✓ `group_bar_target_at` går gennem samme lag: en bjælke ligger nederst i sin klients lag, så et
  vindue i samme eller et højere lag skjuler den (`input/pointer.swift`).
- ✓ `iskilling` springes over i `get_focused_stack_client` og `client_focus`, som i mango.
- ✓ `resize_tile_client`s `frame_serial`: én resize pr. billede, som mango; portens Fit tager sine
  skridt i ét billede og nulstiller `last_resize_frame` før hvert.
- ✓ §6: `client_group_leave` (lige bag `rc`), `monitor_from_cycle` (listehovedet springes over),
  `vertical_grid_core` (`grid_core`s betingelse).
- ✓ som mango: `vertical_scroller_core`s fanebjælke-drift kan ikke ske i mango: `arrange` kalder
  `tab_sync_monitor` før layoutet, og den opløser kæderne uden for monocle og deck.
- ✓ mærker på portens ting i kernen; død kode (`LayoutKind.isVertical`, `BezierCurve.extremes`)
  væk; de forkerte mærker rettet. `mangoBarDecorationApplyConfig` er mærket som portens fletning.

**Mangler (står i `docs/afvigelser.md` §4)**
- Fokus-animationens kantfarve; hover på gruppebjælkens lukkeknap; runde hjørner ved skærmkanten
  under `border_radius`; `check_size_per_valid`.
- `-s`, `-r`, `XDG_CURRENT_DESKTOP`, `increase_nofile_limit` (med `fd_set_nonblock`, `child_pid`);
  man-siderne `mmsg.1` og `mangonag.1`; `unminimize`, `get_layout_abbr`, `starts_with_ignore_case`
  og `mod_to_string` (døde i mango).

**Til din beslutning**
- Idle inhibit og swallowing står som umulige, men IOPMAssertion og sysctl kunne gøre dem.

## Totals

| area | mango files | items | 1:1 | differs | missing | platform | port |
|---|---|---|---|---|---|---|---|
| A-client | manage/client.c, client.h | 202 | 86 | 19 | 1 | 71 | 25 |
| B-bind | dispatch/bind.c, bind.h, dispatcher table | 122 | 73 | 29 | 7 | 11 | 2 |
| C-input | input/* | 166 | 55 | 11 | 5 | 88 | 7 |
| D-monitor-main | monitor.c, misc.c, layer.c, tab.c, xwayland_primary.c, main.c, common/* | 192 | 34 | 16 | 5 | 117 | 20 |
| E-layout | layout/* | 111 | 69 | 26 | 1 | 15 | 0 |
| F-anim-draw | animation/*, draw/*, overview/overview.c, switcher/switcher.c | 182 | 41 | 8 | 6 | 75 | 52 |
| G-options | option_defs.c, parse.h, preset.c, assets/config.* (per key and rule field) | 400 | 144 | 85 | 2 | 167 | 2 |
| H-config | the rest of config/* | 161 | 100 | 18 | 2 | 32 | 9 |
| I-ipc | ipc/ipc.c, ext-protocol/*, mmsg, mangonag | ~190 | 61 | 15 | 1 | 101 | 12 |

Counts are the first pass's. Verification refuted 3 whole rows (A: `client_unpark`; C:
`pointer_node_enabled`, `pointer_client_destroyed`) and parts of about 30 others. It found a
few new ones, which are included below. About 250 findings hold: 75 a user can see, about 150
edge cases (61 of them come from two causes in config parsing), 14 names or marks, and the
silent mango-bug fixes in §8.

All 94 dispatcher names and all 257 config keys are accepted, and every default value is
mango's. The deviations are in behaviour, not in what exists.

## 1. Visible behaviour, by cause

### 1.1 Layout read from the monitor's tag, not the client's (A, M) — ✓ rettet i trin 5
Mango's `get_client_tag_idx` is absent. `client_is_in_same_stack`, `get_focused_stack_client`,
`client_exchange`, `client_replace` and the scroller lookup in unmap use `m.layout` (the current
tag) where mango uses the client's own tag. A client with `tags == 0` falls back to the current
tag, where mango uses slot 0. Visible with two tags in view that have different layouts.

### 1.2 Sloppy focus (C, M) — ✓ rettet i trin 7
Mango focuses only when the pointer *enters* a different surface. After every arrange, focus
and warp it re-enters the surface under the pointer with `pointer_process_motion(0)`, which never
focuses. Ours focuses any window the pointer moves over. A dialog that takes focus, or a
`focusstack` without a warp, loses focus to the window under the pointer at the next 1-px nudge.
`!tagining` is missing too. `docs/afvigelser.md` §2 says that dropping motion(0) has no visible
effect. That is wrong, and the line must go when this is fixed. Related: `pointer_warp_to_client`
has no motion(0), so the hover resize cursor goes stale.

### 1.3 Scroller (E, A; M)
- ✓ rettet i trin 4: `*_scroll_adjust_fullandmax`: `MangoServer.arrange` replaces the scroller's frames for
  fullscreen and maximized windows. A maximized column that is not focused covers the work area
  (mango: beside the focused column). The gap is wrong when gaps are off or with smartgaps. A
  fullscreen window in a stack fills the monitor (mango: its slot in the stack).
- ✓ rettet i trin 4: `scroller_insert_stack`, `scroller_stack`, `scroller_drop_tile`, `scroller_swap_different_stacks`
  and `exchange_two_scroller_clients` do not reorder `clients`. After leaving the scroller, master,
  tile order and the focus stack differ from mango. `scroller_insert_stack` does not clear
  fullscreen or maximize on the window or the column head.
- ✓ rettet i trin 4: `scroller_swap_nodes_in_same_stack`: the heights move with the windows (a 70/30 stack becomes
  30/70). Mango keeps each position's height.
- ✓ rettet i trin 4: `client_move_to_monitor` along the scroller axis inserts the window next to the target. Mango
  inserts it before the column head or after its tail.
- ✓ rettet i trin 7: `client_begin_drag_float` lacks `exit_scroller_stack`. Drag a window out of a stack with
  `drag_tile_to_tile=0`, then `togglefloating`, and ours puts it back into the old stack.

### 1.4 Monitors (D, B; S–M)
- ✓ rettet i trin 9: `match_monitor_spec` is called with the name only, so `make:`, `model:` and `serial:` never
  match in focusmon, tagmon, viewcrossmon, tagcrossmon or window_rule `monitor:`. `Screen` has
  the fields. (S)
- ✓ rettet i trin 5: Mango's monitor list has the newest monitor first; ours is sorted left to right. This changes
  `focusmon` and `tagmon` with next/prev (`monitor_from_cycle`), which monitor replaces a removed
  selected one (`monitor_close`), and IPC order. (M)
- **åben:** `node_at_point`: overlapping floats give the first in tiling order, not the topmost. A float
  under a fullscreen window is hit instead of the fullscreen window. Affects sloppy focus, click
  focus and moveresize. (M)
- ✓ rettet i trin 5: `monitor_close` does not reset `gesture_drive_*`. `handle_output_layout_change` lacks the
  refocus on a geometry-only change and the float shift for hidden tags.
- **åben, listet:** ukendte argumenter i afvigelser.md §2; `-s`, `-r` og `XDG_CURRENT_DESKTOP` som mangel i §4. `main`/`setup`: `-s <cmd>` and `-r <fd>` are missing, and `XDG_CURRENT_DESKTOP=mango` is not set.
  Unknown arguments are ignored, which macOS needs (`-psn_…`, `-NS…`): list it.
- ✓ rettet i trin 5: `monitor_at_point` returns the nearest monitor, where mango returns NULL.

### 1.5 Dispatchers (B; mostly S)
- ✓ rettet i trin 6: `arg->tc` is ignored by focusdir, focus_window_or_workspace, focusmon and groupfocus.
- ✓ rettet i trin 6: A missing IPC argument is `"0"` here and `""` in mango: `mmsg dispatch view` shows the special
  tag (mango: all tags), and `mmsg dispatch tag` moves the window to it.
- ✓ rettet i trin 6: `moveresize`: any argument other than exactly `curresize` starts a move. Mango accepts
  `curmove`/`curresize` regardless of case, and does nothing otherwise.
- ✓ rettet i trin 6: `movewin`, `resizewin` and `smartresizewin` give absolute values for the box without the border
  (mango: with it), and do not animate (`arrange(.none)`; mango animates MOVE). `smartresizewin`'s
  snap and clamp are off by the border. (S–M)
- ✓ rettet i trin 4: `dwindle_*` (5): no DWINDLE-layout or floating check, and they use the monitor's tag instead of
  the client's. They change the dwindle tree on tags that are not in dwindle.
- ✓ rettet i trin 6: `viewcrossmon` also takes directions and next/prev, and does nothing without a match. Mango
  matches the name only and views the tag on the current monitor anyway.
- ✓ rettet i trin 6: `tagsilent`: `-1` sends the window to all tags (mango: the special tag), and a zero mask is
  ignored (mango: tags = 0).
- **✓ listet: afvigelser.md §2** (trin 10; kernens mærker i `dispatch/bind.swift` siger stadig mangos `fork`/`execvp`). `spawn` and `spawn_shell` both run `/bin/zsh -lc`. Mango uses wordexp+execvp for `spawn` (a pipe
  does not work) and `sh -c` for `spawn_shell`. This is unlisted.
- ✓ rettet i trin 6: `get_client_by_id_or_title`: mango treats any argument that starts with `none` as unset, keeps
  `"0"` and `""` as regexes, and always spawns when nothing matches.
- ✓ rettet i trin 6: Number parsing: `Int()`/`Double()` stand in for atoi/atof, so `movewin,10px` and
  `incnmaster,1x` give different results.

### 1.6 Animation and drawing (F, G; M)
- ✓ rettet i trin 2: `set_arrange_visible`: a parked client slides in on any `.tag` arrange. Mango slides only when
  `prevtag && curtag`, so `view N` from the special tag slides here and not in mango. A reversed
  tagout gets the move duration and curve.
- ✓ rettet i trin 2 og 6: `resize`: OVERVIEW uses `animation_curve_tag` (mango: move). `scratchpad_switching_mon` is not
  honoured, so a scratchpad moved across monitors slides. The core's `.none` arrange has no mango
  counterpart: movewin, resizewin, toggleoverlay, comboview, tab-bar focus and floating snap do not
  animate.
- **åben, som mangel i afvigelser.md §4:** The focus animation is missing (`client_start_focus_animation` and four helpers;
  `animation_duration_focus`/`animation_curve_focus` are stored and never read). Mango also fades
  the border colour, and the port could do that. MangoCompat names only the opacity half.
- **åben, som mangel i afvigelser.md §4** (mærket i `input/pointer.swift:524` siger forkert, at porten gør det): `mango_bar_decoration_set_close_hover`: the group bar's close button has no hover colour.
- **åben (lille), som mangel i afvigelser.md §4:** kanten klippes nu ved skærmkanten; en rest under `border_radius` står. `set_client_corner_location`: mango squares a corner only where a window stands past the
  monitor edge by at least `border_radius`. Here that is only visible on scroller columns
  off-screen.

### 1.7 Switcher (F; S) — ✓ rettet i trin 8
- `switcher_remove_client` re-runs the whole layout. Mango keeps `tile_h` and each tile's width.
- `switcher_commit_client` does not pass changefocus=true to `client_view_on_monitor`.
- `switcher()` checks for overview before it cycles. Mango checks only in `switcher_open`.

### 1.8 Groups and tabs (A, C, D; S)
- ✓ rettet i trin 5 (portens bytte i `Port/macOS/MacEvents.swift:144` er listet i afvigelser.md §3, men umærket i koden): `client_active`: mango swaps a parked member in first. Here it happens last, inside
  `clientFocus`, so `focusid` on a parked member first shows its old tag. The port's
  `MacEvents.swift:132` swaps a member in on macOS focus, and is not marked.
- ✓ rettet i trin 5 og 9: `client_park` keeps `c.mon` (mango: NULL), and `client_group_active` is absent. IPC reports
  parked members on their old monitor.
- ✓ rettet i trin 5: `client_check_tab_node_visible` does not exclude global or unglobal windows.
- ✓ rettet i trin 5: `check_hit_no_border`: `monocle_no_border` tests `!isFloating` instead of fake-tiled.
- ✓ rettet i trin 5: The tab chain needs `tab_bar_height > 0`. At 0 (legal), mango still forms the chain and hides
  the other members.
- ✓ rettet i trin 5: `clientReplace` does not carry `isTabFocus` over.
- **åben** (`input/pointer.swift:457`): `group_bar_target_at` tests a strip above each window, ignores tab bars and stacking. Dropping
  onto a tab bar does nothing, and a group under a float can still be joined. (M)
- ✓ rettet i trin 7: A modifier mouse binding beats a click on a bar. Mango handles bar clicks first.

### 1.9 Input (C; S–M)
- ✓ rettet i trin 7: Scrolling does not count as pointer activity (`handle_cursor_axis`), and `focusmon`'s warp does
  not call `pointer_cursor_activity`. A hidden cursor stays hidden.
- ✓ rettet i trin 7: Caps Lock and Fn count as mode keys. Releasing them commits the switcher or leaves overcircle.
- **✓ listet: afvigelser.md §5** (Input: pinch og hold uden macOS-del; tvivlsomt, se C-input): Pinch and hold begin do not cancel a pending release bind.
- ✓ rettet i trin 7: `keyboard_check_keybinding`: `handled` is a sticky OR, so an allow-conflict bind followed by a
  `bindp` swallows a key that mango passes on.
- ✓ rettet i trin 7 (`NONE-`); pid-reglen ✓ listet: afvigelser.md §3. Global keys: a `NONE-` rule is accepted (mango skips it). Dropping the rule when the target has
  the focused pid is forced by macOS. Mark it and list it.
- ✓ rettet i trin 7: The rule-confine clamp is skipped during a grab. The scroller lock is cleared without
  `!animation.running`.
- ✓ rettet i trin 7: `pointer_cursor_outside_client` tests the box without the border.

### 1.10 IPC (I; S–M)
- ✓ rettet 15. nov.: `printstatus` ignores mango's watch-type mask, so every watcher is re-evaluated each time.
  `setkeymode` or a layout change updates `watch monitor`/`watch tags` here and not in mango. (M)
- ✓ rettet 15. nov.: `hide_clients` is `isoverview ? 1 : 0`. Mango gives the number of minimized clients.
- ✓ rettet 15. nov. og i trin 2: Client `x/y/width/height` leave out the border: off by bw in x and y, and 2·bw smaller.
- ✓ rettet 15. nov.: `get version` gives the app version, not `0.18.5(…)`.
- ✓ rettet 15. nov. og i trin 6: `client,<id>` followed by a space is accepted. `spawn_on_empty` and `toggle_named_scratchpad`
  keep commas in the command (mango takes one field). A trailing `\r` is stripped.
- ✓ rettet 15. nov.: The first line of `watch all-clients`, and `watch client <id>` on a parked member, include
  parked members.
- **✓ listet: afvigelser.md §3** (`get` lister nu macOS' enheder): `get/watch all-devices` are always empty, and `ipc_notify_device_event` is never sent. Unlisted.

## 2. Config parsing (G, H)

- ✓ rettet 15. nov.: **D1, 46 int-as-bool keys.** Mango clamps to 0..1 in `override_config`, so a negative value is
  off. Here `atoi != 0` makes it on (`animations=-1`). One fix in `ValueParse.bool`. (S)
- ✓ rettet 15. nov.: **D2, 15 window-rule fields.** A negative value means "unset" in mango and `true` here
  (`is_floating:-1` floats). (S)
- ✓ rettet 15. nov.: **D3, animation curves.** A bad value zeroes the curve in mango; here the old curve stays. (S)
- ✓ som mango nu (rettet 15. nov.; mangos opførsel valgt): **D4, tag rules.** `no_hide`, `no_render_border` and `open_as_floating` default to 0 in mango and
  every matching rule writes them. Here only a rule that sets them does. So a later `id:*` rule
  resets them in mango and not here. This may be a mango bug: **your decision**.
- ✓ rettet 15. nov.: An empty `app_id:` or `title:` in a window rule matches every window in mango and none here.
- ✓ rettet 15. nov. og i trin 1: `scroller_default_proportion:0` in a tag rule is applied here and skipped in mango. A window
  rule with `scroller_proportion ≤ 0` overrides an earlier rule's value here.
- ✓ rettet 15. nov.: `setoption` has no `var`, `source` or `source_optional`, and drops a rule with an unknown field.
  Mango keeps the rule.
- ✓ rettet 15. nov.: `scroller_proportion_preset`/`circle_layout` with a bad value: mango empties the list, ours keeps
  the old one (or the tokens that parsed).
- ✓ rettet 15. nov.: An empty `key_mode` makes later binds unreachable in mango, and puts them in "default" here.
- ✓ rettet 15. nov.: Keywords by prefix (`env*`, `source*`, `mousebind*`, …) are exact here. TOML
  `[mousebind.<mode>.<flag>]` is "Unknown keyword".
- ✓ rettet 15. nov. og i trin 9: Error output: mango reports every error on a line, ours stops at the first. A missing `source=`
  file gets an extra report here.
- ✓ listet: afvigelser.md §3. The key model (`binds` by keysym, XF86 names outside our table, `code:N` as a macOS keycode)
  is on hold since 2026-11-14 but is not listed in `docs/afvigelser.md`. List it.

## 3. Mango bugs we already differ from, without a mark, §6 row or test

Each needs a `not in mango: … (a mango bug, docs/afvigelser.md §6)` mark, a §6 row and a test:
- ✓ listet: afvigelser.md §6, mærke og test. `toml_foreach_array_element`: an escaped `\"` ends the string in mango.
- ✓ listet: afvigelser.md §6, mærke og test. `toml_section_flush`: after a rejected `[bind.…]` section, mango sets the keymode to `""`, so
  every later bind is dead.
- ✓ som mango nu (trin 4): vi følger mangos fejl igen; kandidat til §6. `vertical_grid_core`: visible floats count in mango's index, so a tiled window can be left
  unplaced.
- ✓ som mango nu (trin 4): vi følger mangos fejl igen; kandidat til §6. `vertical_scroller_core`: a tab chain at the head drifts down by `tab_bar_height` on every
  arrange.

Possible mango bugs where we still follow mango or differ without having decided:
- ✓ listet: afvigelser.md §6 (trin 9). `setoption` from a bind appends sscanf's `,0,0,0` to the value in mango; ours does not.
- ✓ som mango nu: D4 above.
- **åben, din beslutning** (`dispatch/bind.swift:299`): `client_group_leave` (bind.c:415) puts the leaving client two places behind `rc` in the focus
  stack, against its own comment. Ours puts it right behind.
- **åben, din beslutning** (vores løkke springer listehovedet over uden mærke, `manage/monitor.swift:76`): `monitor_from_cycle` reads a bogus Monitor when the selected one is last in mango's list
  (undefined behaviour).

## 4. Platform and port items that are not listed

Status trin 10: spawn via zsh ✓ listet §2; `get/watch all-devices` ✓ listet §3; the key model ✓
listet §3; global keys and the focused pid ✓ listet §3; unknown command-line arguments ✓ listet §2;
`-s`/`-r` som mangel i §4; mangonag without an exclusive zone ✓ listet §3 (the selected monitor
✓ rettet 15. nov.); tablet and the virtual input protocols ✓ listet §5 (Input). **Åben, din
beslutning:** idle inhibit and swallowing are listed as impossible, but IOPMAssertion and sysctl
could do them.

## 5. Names, marks and dead code (S)

- **Mango's name on something else:**
  - ✓ rettet i trin 2: `setArrangeVisible` returns only a start rect; the logic is in `clientAnimation`.
  - **åben** (mærket, ikke omdøbt; `draw/text-node.swift:7`): `mangoBarDecorationApplyConfig` is a merge.
  - ✓ rettet i trin 2: `clientDrawFrame` only redraws borders and bars.
  - ✓ væk (nu `filled(from:)`, mærket): `DecorateStyle.setValueDefault(from:)` is a merge.
  - ✓ rettet i trin 6: `parseMonitorArg` does more than mango's.
  - ✓ væk (nu mangos `hide_cursor_source`): `armCursorHideTimer` carries `/// mango pointer_cursor_activity`.
- **Not mango's name:**
  - ✓ rettet i trin 1: `prevTag` should be `prevtag`.
  - ✓ rettet 15. nov.: `ConfigWinRule` is `WindowRule`, and `ConfigTagRule` is `TagRule`.
  - ✓ rettet i trin 1: The gap and Pertag fields.
  - ✓ rettet i trin 6: Most dispatchers are a `case` in `dispatch()`, without mango's function or a `/// mango` line.
  - ✓ væk (trin 4): `tileCore(right:)` merges `tile_core` and `right_tile_core`.
  - ✓ rettet i trin 8: `SwitcherLayout.switcherLayout` merges three functions.
  - ✓ rettet i trin 5: `dwindleFocusBlockRoot`.
- **Unmarked inventions:**
  - Types: `Grab`, `DragTile`, `ArrangeAnimation`, `AnimationAction`/`TagoutAnimation`/`ClientAnimation` ✓ væk; **åben:** `KeyboardState`/`KeyAction`/`KeyInput` (`input/keyboard.swift:88`, umærket).
  - Functions and members: `topBars`, `recordConfigLineError` ✓ væk; `Modifiers.mangoDescription` ✓ flyttet til porten; `ValueParse`, `MouseButton.cgButtonNumber` ✓ mærket; **åben (umærket):** `clientsAll`, `groupMembers`, `focused`, `MangoServer.xkbOptions` (se `docs/analyse-udenfor-kernen.md` §0).
  - Flags and parameters: `centerTiledSelect(among:)`, `clientChangeMon(focus:)` ✓ væk; **åben:** `groupParked` (mærket, hvor det sættes, ikke på feltet).
  - ✓ væk: Calls in the wrong place: the `setSizePer` loop in `clientViewOnMonitor`, and `scrollerNodeRemove` in `clientReassignMonitor`.
  - ✓ som mango nu eller væk (trin 4–6): Scroller: `exitScrollerStack`, `scrollerApplyStack`, `centerWindow`/`centerRequest`, `ScrollerState.arrange`.
  - Others: the `hidden` in `verticalDeck`, `knownFrames`/`lastFrame` ✓ væk; `publishGlobalKeys()` in `printstatus` ✓ mærket og listet §3; **åben:** `BezierCurve.extremes` (`Model/Geometry.swift:76`, umærket og nu uden kalder).
  - ✓ væk: Strings and comments: the message "Missing path for source", and the out-of-date comment on `clientResetMonTags`.
- **Dead code:** ✓ væk alle: `IPCRequest.commandTakingDispatchers`, the private tuple `<` in
  Dispatch.swift, the orphan doc comment at ConfigParser.swift:463, `let corners` in MangoCompat, the
  error branches in RuleParser, and the test-only helpers. **Ny død kode:** `LayoutKind.isVertical`
  (`Layout/Layout.swift:52`) og `BezierCurve.extremes`.
- **Missing, but dead in mango:** `reset_gaps` and the six `increase_*_gap` ✓ rettet i trin 6;
  `is_centertile_layout` ✓ rettet i trin 5; **åben, som mangel i afvigelser.md §4:** `unminimize`,
  `get_layout_abbr`, `starts_with_ignore_case` and `mod_to_string`.
