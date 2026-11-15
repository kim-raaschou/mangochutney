# G-options verified (option_defs.c, parse.h, preset.c/h, assets/config.*)

Verified against mango 0.18.5 (21f80a9) and mangochutney main (da81bb9). Read-only. Every `differs`/`missing` row of
G-options.md was re-read on both sides (mango: option_defs.c, parse.h, value_parse.c, reapply.c, client.c,
arrange.c, load.c, bind.c, animation/client.c; ours: ConfigOptions.swift, ConfigParser.swift, RuleParser.swift,
Config.swift, Rules.swift, Client.swift `parseTagrule`, MangoServer.swift `clientSetRules`/`applyRuleProperties`,
Dispatch.swift `setoption`/`setSizePer`, Geometry.swift `parseDoubleArray`, MangoCompat.swift).
82 grep hits for `| differs |` = 81 table rows + the summary line; 2 `missing` rows.

## Classes (verified once in depth)

| class | mango | ours | verdict | kind | size | note |
|---|---|---|---|---|---|---|
| D1 int-as-bool | parse_option `atoi` (e.g. option_defs.c:58) then `override_config` option_defs.c:2730ff `CLAMP_INT(x,0,1)`; called after every load (load.c:425) and after `setoption` (bind.c:2313) | `ConfigOptions.bool` ConfigOptions.swift:268 → `ValueParse.bool` :390 `atoi(s) != 0`; `Config.overrideConfig` Config.swift:163 has no bool clamps | CONFIRMED | edge | S | `x=-1`: mango 0 (off), ours true (on). Positive values give the same result (2→1 vs true). Checked by script: all 46 assigned keys are bool setters in ours AND have `CLAMP_INT(config.f, 0, 1)` in override_config; every one of them is read somewhere outside the config code (not a stored-only key). The 5 bool setters not in D1 are right to be out: `animation_fade_in/out` (platform, stored only), `tag_carousel`, `monocle_tab_mode`, `deck_tab_mode` (mango does not clamp them; `!= 0` = same truthiness). Fix: a clamped-bool setter `atoi(s) > 0`. Not listed in afvigelser |
| D2 window-rule int fields | option_defs.c:1437-1470 sets 34 int fields to -1; values `atoi` (:1506ff); `apply_rule_properties` client.c:1508 uses `APPLY_INT_PROP` (`>= 0`, parse.h:25) | RuleParser.swift:28-30 `flag` = `n != 0` → `Bool?`; `applyRuleProperties` MangoServer.swift:944 `if let` | CONFIRMED | edge | S | `window_rule=is_floating:-1,app_id:foo`: mango leaves foo as it was, ours floats it; a later matching rule with `-1` also overrides an earlier `1` in ours. Rule fields are read nowhere else in mango (grep), so apply_rule_properties is the only site. Exactly 15 of our fields are applied (MangoServer.swift:945-959) and these are exactly the 15 fields on the 12 D2 rows; the other flag fields (is_term, no_swallow, no_size_hint, allow_csd, force_tiled_state, ignore_maximize, no_shadow/radius/blur, no_fade_*) are parsed but never applied (platform rows), so D2 cannot show there |
| D3 animation curves | `parse_double_array` value_parse.c:80: `memset(output,0,…)` first, fills tokens until an error; option_defs.c:94/104/114 then errors with `num != 4` but the array is already changed; config is used despite errors (load.c:420-433) and re-baked by `reset_option` → `init_baked_points` | `curve` ConfigOptions.swift:333 + `parseDoubleArray` Geometry.swift:126: returns nil, curve untouched | CONFIRMED | edge | S | `animation_curve_move=0.46,1.0,0.29` → mango curve (0.46,1.0,0.29,0), ours default; `animation_curve_move=x` → mango (0,0,0,0) (linear), ours default. Also mango prints "Invalid number in array" only for a bad/negative token (not for too few values). The 3 assigned rows (move/open/tag) belong here; close/focus have the same parse but are stored-only/missing rows |
| D4 tag-rule int fields | option_defs.c:1271-1273 default `no_render_border/open_as_floating/no_hide = 0`, parse clamps 0..1 (:1308-1313) so always ≥ 0; `tag_rule_apply_to_slot` reapply.c:443 applies `if (>= 0)` for every matching rule | `TagRule` Rules.swift:143 `Bool?` nil; `parseTagrule` Client.swift:256-258 `if let` | CONFIRMED | behaviour | S | `tag_rule=id:2,no_render_border:1` then `tag_rule=id:2,layout_name:scroller` (or `id:*,no_hide:1` then any `id:3,…` rule): mango ends 0 (the later rule's default resets it), ours keeps 1. The `>= 0` guards in mango are dead code for these three (only `scroller_ignore_proportion_single` gets -1), so this may be a mango bug; it is not in §6 and ours is not marked; decide with the user before changing either way |

## Per-row verdicts

| finding (short) | mango file:line | ours file:line | verdict | kind | size | note |
|---|---|---|---|---|---|---|
| `parse_option` composite: `setoption` path lacks `var`/`source`/`source_optional`, drops a window_rule/tag_rule with an unknown field | bind.c:2311 `setoption` → `parse_option` (has `var` :1867, `source*` :2354-2357; unknown rule field → `parse_error` but `count++`, :1638/:1341) + `reset_option` (reapply.c:155, incl. `reapply_tagrule`) | Dispatch.swift:443 → `ConfigOptions.parseOption` ConfigOptions.swift:12 (no var/source cases → `.unknown`); strict `RuleParser.parseWindowRule/parseTagRule` RuleParser.swift:5,11 drop on any error | CONFIRMED | edge | S | `setoption,source,~/x.conf`: mango parses the file into the live config (binds, rules) and reset_option applies it; ours "Unknown keyword". `setoption,tag_rule,id:2,layout_name:scroller,foo:1`: mango applies the rule at once (reapply_tagrule), ours drops it. The other items folded into this row (D1, D3, key_mode, env, preset/circle_layout, prefix keywords) are verified on their own rows |
| `override_config`: no 0..1 clamps for bools | option_defs.c:2730 | Config.swift:163 | CONFIRMED | edge | S | = D1 (all numeric clamps present; checked) |
| `APPLY_INT_PROP` | parse.h:25, client.c:1508 | MangoServer.swift:944, RuleParser.swift:29 | CONFIRMED | edge | S | = D2 |
| `APPLY_FLOAT_PROP`: rule `scroller_proportion(_single)` ≤ 0 assigned in ours | parse.h:29, client.c:1544-1545, custom flag :1685-1691; `set_size_per` arrange.c:18 overwrites a non-custom proportion | MangoServer.swift:960-961; `setSizePer` Dispatch.swift:904 (called after the rules, MangoServer.swift:896, as mango client.c:1737) | PARTLY | edge | S | The audit's scenario is REFUTED: one rule `scroller_proportion:0` sets 0 but leaves `isCustomScrollerProportion` false, so `setSizePer` (both the new-client branch :938 and the keep-own branch :916) replaces it with the tag default, as mango. Real only after an earlier custom value: rule A `app_id:foo,scroller_proportion:0.5` + rule B `app_id:foo,scroller_proportion:0` (or `-0.5`) → mango 0.5, ours 0 with the custom flag still set → a zero-width scroller column |
| `ConfigTagRule` | parse.h:194, option_defs.c:1247 | Rules.swift:143 | CONFIRMED | behaviour | S | = D4 (name `TagRule` is a name-only note) |
| `key_mode` empty / 27-char truncation | option_defs.c:56-57 `snprintf "%.27s"`; parse_config_line load.c:88 rejects `key_mode=` (sscanf needs ≥1 char) but `key_mode= ` / `key_mode=""` reach it as "" | ConfigParser.swift:361-362, ConfigOptions.swift:64-65 `value.isEmpty ? "default"` | PARTLY | edge | S | Empty part CONFIRMED: `key_mode=""` then `bind=…` → mango puts the bind in mode "" (active only after `setkeymode` with an empty arg), ours in "default" (active at once). Truncation: mango truncates both the bind's mode and `setkeymode` (bind.c:973) to 27, so matching is the same; differs only for two names sharing 27 chars and in what `mmsg`/IPC prints |
| `animation_duration_focus` missing | option_defs.c:92; used by `client_start_focus_animation` animation/client.c:1682-1726: cross-fades opacity AND border colour (and dim) over the duration with `animation_curve_focus` | stored Config.swift:21, read nowhere; MangoCompat.swift:100 lists it as `fade` ("opacity … SIP off") | CONFIRMED | behaviour | M | With `animation_duration_focus=300` mango fades the border from bordercolor to focuscolor over 300 ms; ours switches at once. The port draws the borders, so the colour half is possible; MangoCompat/compatibility.md:40 name only the opacity half. Default 0 = same result |
| `animation_curve_focus` missing | option_defs.c:133; `find_animation_curve_at(…, FOCUS)` animation/common.c:24 | stored only; MangoCompat.swift:101 | CONFIRMED | behaviour | M | goes with the row above (the row's note "Default 0" means the duration's default) |
| `animation_curve_move` (D3) | option_defs.c:94 | ConfigOptions.swift:120 | CONFIRMED | edge | S | D3 |
| `animation_curve_open` (D3) | option_defs.c:104 | ConfigOptions.swift:121 | CONFIRMED | edge | S | D3 |
| `animation_curve_tag` (D3) | option_defs.c:114 | ConfigOptions.swift:122 | CONFIRMED | edge | S | D3 |
| `scroller_proportion_preset` error path | option_defs.c:306-380: frees the old list first; any bad token or count mismatch → list NULL, count 0 | ConfigOptions.swift:135-148: `.invalid`, previous list kept | CONFIRMED | edge | S | `scroller_proportion_preset=0.5,0.8,1.0` then `scroller_proportion_preset=0.5,x` → mango no preset, ours 0.5,0.8,1.0. `0.5,,0.8` (count 3, 2 tokens) same. `sscanf %f` also takes `inf`/`nan`/hex where `scanDouble` (:383) does not (minor) |
| `circle_layout` empty token | option_defs.c:381-460: `string_count` = commas+1, strtok skips empties → `i != string_count` → error, list emptied | ConfigOptions.swift:160-165: `split` drops empties, no error | CONFIRMED | edge | S | `circle_layout=tile,,scroller` or `tile,` → mango error + empty list, ours [tile, scroller] / [tile] silently. Trimming: `sanitize_string` (value_parse.c:119) keeps spaces (isprint), ours trims only control chars → same for ASCII, as the audit says |
| `tag_rule` keyword | option_defs.c:1247 | ConfigParser.swift:430, ConfigOptions.swift:43 | CONFIRMED | behaviour | S | D4 fields + setoption drop (see parse_option row) |
| `window_rule` keyword | option_defs.c:1412 | ConfigParser.swift:421, ConfigOptions.swift:38 | CONFIRMED | edge | S | D2, empty app_id/title, setoption drop. File path: kept with unknown fields, dropped on a bad global_key_binding, both 1:1 |
| `env` prefix / blank name | option_defs.c:1787 `strncmp(key,"env",3)`, sscanf `%255[^,],%255[^\n]` then trim | ConfigOptions.swift:19-32 exact `"env"`, rejects an empty name | CONFIRMED | edge | S | `envfoo=A,b` → mango sets env A, ours "Unknown keyword". Blank name sharpened: from a plain line the value is already trimmed (load.c:104), so `env= ,x` reaches mango as `,x` and both reject it; mango accepts a blank name only when a variable expands to empty before the comma (`env=$E ,x`, the value is not re-trimmed after expansion), ours re-trims (ConfigOptions.swift:14) and rejects. HOME unset is marked port |
| `is_floating` (D2) | option_defs.c:1506 | RuleParser.swift:46 | CONFIRMED | edge | S | D2 |
| `title` empty | option_defs.c:1508 `strdup("")`; `is_window_rule_matches` client.c:1057 + `regex_match` util.c:71 (empty pattern matches everything) | RuleParser.swift:45 `nil if empty`; Rules.swift:127 (no criterion → never matches) | CONFIRMED | edge | S | `window_rule=is_floating:1,title:` floats every window in mango, none in ours. With the other criterion set (`app_id:foo,title:`) both match foo: same |
| `app_id` empty | option_defs.c:1510 | RuleParser.swift:44 | CONFIRMED | edge | S | as title |
| `no_focus` (D2) | :1525 | RuleParser.swift:81 | CONFIRMED | edge | S | D2 |
| `no_force_center` (D2) | :1531 | :65 | CONFIRMED | edge | S | D2 |
| `no_border` (D2) | :1537 | :67 | CONFIRMED | edge | S | D2 |
| `no_animation` (D2) | :1543 | :71 | CONFIRMED | edge | S | D2 |
| `is_open_silent` / `is_tag_silent` (D2) | :1545/1547 | :51/52 | CONFIRMED | edge | S | D2 |
| `is_named_scratchpad` (D2) | :1549 | :53 | CONFIRMED | edge | S | D2 (-1 → ours also forces floating via client.c:1677 equivalent MangoServer.swift:880) |
| `is_unmanaged_global` / `is_global` (D2) | :1551/1553 | :54/49 | CONFIRMED | edge | S | D2 |
| `scroller_proportion_single` ≤ 0 | :1555 | RuleParser.swift:80, MangoServer.swift:961 | PARTLY | edge | S | see APPLY_FLOAT_PROP: only after an earlier custom value |
| `is_overlay` (D2) | :1561 | :50 | CONFIRMED | edge | S | D2 |
| `ignore_minimize` (D2) | :1569 | :84 | CONFIRMED | edge | S | D2 |
| `confine_pointer` (D2) | :1593 | :82 | CONFIRMED | edge | S | D2 |
| `scroller_proportion` ≤ 0 | :1597 | RuleParser.swift:79, MangoServer.swift:960 | PARTLY | edge | S | see APPLY_FLOAT_PROP |
| `is_fullscreen` / `is_fake_fullscreen` (D2) | :1599/1601 | :47/48 | CONFIRMED | edge | S | D2 |
| tag `no_render_border` (D4 + D1) | option_defs.c:1308, reapply.c:457 | RuleParser.swift:133, Client.swift:256 | CONFIRMED | behaviour | S | D4; also `no_render_border:-1` → mango 0 (clamped at parse), ours true |
| tag `open_as_floating` (D4) | :1310, reapply.c:459 | :135, Client.swift:257 | CONFIRMED | behaviour | S | D4 (+ same negative case) |
| tag `no_hide` (D4) | :1312, reapply.c:451 | :137, Client.swift:258 | CONFIRMED | behaviour | S | D4 (+ same negative case) |
| tag `scroller_default_proportion(_single):0` | :1318/1321 clamp 0..1; reapply.c:461-466 apply only `> 0` | RuleParser.swift:143/145 clamp 0..1; Client.swift:253-254 `if let` | CONFIRMED | edge | S | `tag_rule=id:1,scroller_default_proportion:0` → mango keeps the config default; ours sets the tag default to 0, so `setSizePer` (Dispatch.swift:938) gives new windows there proportion 0 (zero-width column). Negative values clamp to 0, same |
| tag `scroller_ignore_proportion_single` (D1 only) | :1325 default -1, `CLAMP_INT(atoi,0,1)`; reapply.c:467 | RuleParser.swift:147 `n != 0`; Client.swift:255 | CONFIRMED | edge | S | `:-1` → mango 0 (off), ours true. Belongs with D1, not D2/D4 (default is -1 = unset in both) |
| `animations=-1` (D1) | option_defs.c:58 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:105 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `scroller_ignore_proportion_single=-1` (D1) | option_defs.c:170 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:129 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `scroller_focus_center=-1` (D1) | option_defs.c:172 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:130 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `scroller_prefer_center=-1` (D1) | option_defs.c:174 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:131 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `scroller_prefer_overspread=-1` (D1) | option_defs.c:176 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:132 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `edge_scroller_pointer_focus=-1` (D1) | option_defs.c:178 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:133 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `focus_cross_monitor=-1` (D1) | option_defs.c:182 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:239 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `focus_direction_only_zone_overlap=-1` (D1) | option_defs.c:184 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:240 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `exchange_cross_monitor=-1` (D1) | option_defs.c:186 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:242 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `scratchpad_cross_monitor=-1` (D1) | option_defs.c:188 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:243 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `special_tag_cross_monitor=-1` (D1) | option_defs.c:190 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:178 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `focus_cross_tag=-1` (D1) | option_defs.c:192 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:241 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `view_current_to_back=-1` (D1) | option_defs.c:194 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:159 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `single_scratchpad=-1` (D1) | option_defs.c:230 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:244 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `auto_reload_config=-1` (D1) | option_defs.c:250 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:257 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `no_border_when_single=-1` (D1) | option_defs.c:252 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:202 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `no_radius_when_single=-1` (D1) | option_defs.c:254 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:203 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `monocle_no_border=-1` (D1) | option_defs.c:256 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:175 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `monocle_no_gap=-1` (D1) | option_defs.c:258 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:176 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `monocle_no_radius=-1` (D1) | option_defs.c:260 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:177 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `enable_floating_snap=-1` (D1) | option_defs.c:264 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:251 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `float_full_to_top=-1` (D1) | option_defs.c:266 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:253 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `drag_tile_to_tile=-1` (D1) | option_defs.c:268 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:254 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `drag_tile_small=-1` (D1) | option_defs.c:270 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:255 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `gesture_live=-1` (D1) | option_defs.c:274 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:259 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `new_is_master=-1` (D1) | option_defs.c:461 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:151 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `tag_gather=-1` (D1) | option_defs.c:469 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:157 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `center_master_overspread=-1` (D1) | option_defs.c:471 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:154 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `center_when_single_stack=-1` (D1) | option_defs.c:473 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:155 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `dwindle_preserve_split=-1` (D1) | option_defs.c:479 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:168 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `dwindle_smart_split=-1` (D1) | option_defs.c:481 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:169 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `dwindle_smart_resize=-1` (D1) | option_defs.c:483 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:170 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `dwindle_drop_simple_split=-1` (D1) | option_defs.c:485 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:172 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `dwindle_manual_split=-1` (D1) | option_defs.c:487 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:171 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `enable_hotarea=-1` (D1) | option_defs.c:495 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:226 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `hotarea_disable_on_fullscreen=-1` (D1) | option_defs.c:497 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:227 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `cursor_hide_on_keypress=-1` (D1) | option_defs.c:511 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:246 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `focus_on_activate=-1` (D1) | option_defs.c:515 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:236 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `sloppy_focus=-1` (D1) | option_defs.c:523 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:237 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `warp_cursor=-1` (D1) | option_defs.c:525 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:238 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `drag_warp_cursor=-1` (D1) | option_defs.c:529 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:248 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `enable_border_resize=-1` (D1) | option_defs.c:531 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:249 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `smart_gaps=-1` (D1) | option_defs.c:535 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:199 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `monocle_right_button_close=-1` (D1) | option_defs.c:539 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:187 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `always_show_group_bar=-1` (D1) | option_defs.c:938 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:182 `bool` | CONFIRMED | edge | S | mango off, ours on |
| `group_bar_close_button_enable=-1` (D1) | option_defs.c:940 + override_config CLAMP_INT 0..1 | ConfigOptions.swift:183 `bool` | CONFIRMED | edge | S | mango off, ours on |

## Not in mango (verdicts on the audit's table)

| ours | audit says | verdict | note |
|---|---|---|---|
| `OptionResult` ConfigOptions.swift:3 | partly marked | CONFIRMED | the only mark is a doc line placed on `case ignored` (:5) |
| `ConfigOptions.knownKeys` :86 | no mark | CONFIRMED | used only by MangoCoverageTests.swift:140 |
| `isIgnored`/`hasSetter`/`setterKeys` :88-94 | marked | CONFIRMED | |
| `Setter`/`setters`/`mangoSetters` :96-100 | via §5 | CONFIRMED | no local mark; covered by the table mark at :267 and §5 |
| `bool`/`int`/…/`animation` :268-348 | marked once (:267) | CONFIRMED | |
| `homeDirectory` :351 | marked | CONFIRMED | |
| `ValueParse` :357-391 | no mark | CONFIRMED | libc stand-ins; `bool` (:390) is where D1 comes from |
| `RuleParser.parseWindowRule`/`parseTagRule` :5,11 | marked (:4) | CONFIRMED | strict variants; the setoption drop comes from here |
| `parseWindowRuleLenient`/`Checked`/`parseTagRuleLenient`/`tokens` | not marked | CONFIRMED | |
| `ConfigError` :6, `mangoHighlight` :38 | marked | CONFIRMED | |
| `ParsedConfig` :48 | partly | CONFIRMED | |
| `ConfigParser.parse(text:)` :88 | marked | CONFIRMED | |
| `note`/`noteDispatch` :255/260 | marked | CONFIRMED | |
| `recordConfigLineError` :265 | not marked | CONFIRMED | |
| dangling `/// Not in mango: file:line text for conflict messages.` ConfigParser.swift:463 | stale | CONFIRMED | followed directly by the closing `}` of `ParserState` |
| `BindingParser` :466, `splitFields` :603 | marked | CONFIRMED | |
| `Config.port` :149, `xkbRulesOptions` :145 | marked | CONFIRMED | |
| `DecorateStyle` optional fields Decorate.swift:3-13 | not marked | CONFIRMED | |
| `DecorateStyle.mango*` Decorate.swift:31-47 | not marked | CONFIRMED | values equal mango's set_value_default |
| `DecorateStyle.setValueDefault(from:)` Decorate.swift:49 | borrows mango's name | CONFIRMED | a nil-merge, not mango's set_value_default (name clash) |
| `MangoCompat` `let corners` MangoCompat.swift:93 | declared, never used | CONFIRMED | `t` never gets it; the `no_radius` rule note at :154 is a separate literal |

## Counts

81 `differs` rows + 2 `missing` rows = 83 checked.
- CONFIRMED: 79 (46 D1 keys, 12 D2 field rows, 3 D3 rows, 3 D4 field rows, and override_config, APPLY_INT_PROP,
  ConfigTagRule, parse_option, tag_rule, window_rule, env, title, app_id, scroller_proportion_preset, circle_layout,
  tag scroller_default_proportion, tag scroller_ignore_proportion_single, and the 2 missing focus-animation rows)
- PARTLY: 4 (APPLY_FLOAT_PROP, window-rule scroller_proportion, window-rule scroller_proportion_single, key_mode)
- REFUTED: 0 rows; refuted sub-claim: a single `window_rule=…,scroller_proportion:0` does NOT give the window a 0
  proportion in ours (`setSizePer` replaces the non-custom value with the default, as mango); only a second rule
  after a custom value differs.
- UNSURE: 0
Not in mango table: 21 rows, all CONFIRMED.
