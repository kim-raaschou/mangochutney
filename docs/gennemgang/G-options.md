# G-options: src/config/option_defs.c, include/mango/config/parse.h, src/config/preset.c, include/mango/config/preset.h, assets/config.conf, assets/config.toml

Mango 0.18.5 (21f80a9) against this repo (main, da81bb9). Read-only.
Ours: Sources/Mango/Config/ConfigOptions.swift (setters, `parseOption`), Sources/Mango/Config/ConfigParser.swift
(`ParserState.parseOption`, `BindingParser`), Sources/Mango/Config/RuleParser.swift, Sources/Mango/Model/Config.swift
(defaults, `overrideConfig`), Sources/Mango/Model/Decorate.swift, Sources/Mango/Model/Rules.swift; port side
Sources/Port/macOS/MangoCompat.swift, Sources/Port/Extensions/PortOptions.swift.

Every one of mango's 257 parse_option keys (plus `window_rule_once` and the `bind*` regex) is accepted by us: none is
an "Unknown keyword" in ours. 77 are ignored by the port and 12 stored without effect, all listed in MangoCompat.

Systemic deviations used in the tables:
- **D1** int-as-bool keys: mango stores `atoi` and `override_config` clamps 0..1, so a negative value is OFF; ours stores
  `atoi(s) != 0` (`ValueParse.bool`, ConfigOptions.swift:390), so it is ON. Example: `animations=-1` → mango no
  animations, ours animations. Only for keys mango clamps (46 keys); `monocle_tab_mode`, `deck_tab_mode`,
  `tag_carousel` are unclamped in mango and are 1:1.
- **D2** window-rule int fields: mango's -1 sentinel and `APPLY_INT_PROP` (`>= 0`) make any negative value "unset";
  ours `flag` (RuleParser.swift:29) makes it `true`.
- **D3** animation curves: mango's `parse_double_array` zeroes the target array first and fills what parsed, so a bad
  value changes the curve even though the line errors; ours leaves the curve untouched.
- **D4** tag-rule int fields: mango defaults them to 0 and `tag_rule_apply_to_slot` applies them when `>= 0`, so every
  matching rule without the field resets it to 0; ours nil skips.

## Functions
| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| `is_title_message_bar_decorate_key` option_defs.c:46 | folded into `ConfigOptions.decorate` ConfigOptions.swift:190,300 | 1:1 | same key set (`title_message_bar_decorate_*` ×10); no separate function, same result |
| `parse_option` option_defs.c:55 | `ParserState.parseOption` ConfigParser.swift:359 + `ConfigOptions.parseOption` ConfigOptions.swift:12 (+ `RuleParser`, `BindingParser`) | differs | strcmp chain as a table (listed §5). Key-level differences in the key table: D1 (negative int-as-bool), D3 (curves), key_mode "", env prefix, scroller_proportion_preset/circle_layout error paths. Two callers differ: `setoption` (Dispatch.swift:443) reaches only `ConfigOptions.parseOption`, which has no `var`, `source`, `source_optional` ("Unknown keyword" where mango's setoption runs them) and drops a window_rule/tag_rule with any unknown field (mango keeps it). Prefix keywords (`env*`, `exec_once*`, `mousebind*`, `axisbind*`, `switchbind*`, `gesturebind*`, `source*`) and the `\|` in mango's `^bind[s\|l\|r\|p\|c]*$` regex are exact names in ours (trivial) |
| `apply_option_expanded` option_defs.c:2369 | `ParserState.applyOptionExpanded` ConfigParser.swift:354 | 1:1 | expand then parse; setoption skips expansion in both |
| `set_value_default` option_defs.c:2378 | property initialisers Config.swift:7-161; bar/label defaults `DecorateStyle.mango*` Decorate.swift:31-47 merged at draw (Tabs.swift:57) | 1:1 | every default checked equal (table below). name: no function of that name; `DecorateStyle.setValueDefault(from:)` (Decorate.swift:49) borrows mango's name for a nil-merge. `title_message_bardata = groupbardata` copy of the defaults (not of user settings) matches `mangoTitleMessageBar` |
| `override_config` option_defs.c:2730 | `Config.overrideConfig` Config.swift:163 | differs | every numeric clamp present (some at parse time in the setter, same result). The CLAMP_INT(…,0,1) of the ~48 int-as-bool keys has no counterpart: Swift stores `atoi != 0`, so `x=-1` is on in ours and off in mango (D1) |
| `update_global_var` option_defs.c:3011 | `TagMask.mask(forTagNum:)` at use, Rules.swift:7-9 | 1:1 | marked "not in mango: TAGMASK … worked out where it is used"; same result |
| `CLAMP_INT` parse.h:15 | `min(max())` Config.swift:164, ConfigOptions.swift:276 | 1:1 | (int32_t) cast only matters on overflow |
| `CLAMP_FLOAT` parse.h:21 | same | 1:1 | |
| `APPLY_INT_PROP` parse.h:25 (`if (rule->prop >= 0)`) | `if let` in `applyRuleProperties` MangoServer.swift:943 | differs | D2: RuleParser turns any non-zero (also negative) into `true`; mango's -1/negative means "not set". `window_rule=is_floating:-1,app_id:foo` floats foo in ours, leaves it in mango. Apply site is the client group's |
| `APPLY_FLOAT_PROP` parse.h:29 (`if (rule->prop > 0.0f)`) | MangoServer.swift:960-961 | differs | ours assigns `scroller_proportion`/`scroller_proportion_single` also when ≤0 (only `isCustom…` checks >0): `window_rule=scroller_proportion:0,app_id:foo` gives foo proportion 0 (Scroller.swift:191 uses it) where mango keeps the default. Opacity fields: platform |
| `enum animation_type` parse.h:38 (UNSET=-1 … UNKNOWN) | `AnimationType` Config.swift:205, `animationTypeFromString` :209 | 1:1 | UNSET/UNKNOWN folded into `.slide`/nil; both reach the slide branch in mango (animation/client.c:175-195), same result |
| `enum { VERTICAL, HORIZONTAL }` parse.h:34 | literal `1` (Animation.swift:187) | 1:1 | name: no constants |
| `enum { UNFOLD, FOLD, INVALIDFOLD }`, `tearing_mode`, `seat_config_shortcuts_inhibit`, `render_bit_depth` parse.h | – | platform | switchbind / tearing / shortcuts-inhibit / HDR, all listed MangoCompat |
| `default_jump_labels` parse.h:62 (def. load.c:52) | default of `Config.jumpLabels` Config.swift:114 | 1:1 | |
| `Config` struct parse.h:308 | `Config` Config.swift:4 | 1:1 | fields Double where mango has float (rounded at use, e.g. `f32` in TileLayouts.swift:71); `envVars` for `env` (name); `port` dict and `xkbRulesOptions` marked |
| `ConfigWinRule` parse.h:108 | `WindowRule` Rules.swift:75 | 1:1 | name (`WindowRule`); sentinels -1/0/NULL as Optionals (see D2, APPLY_FLOAT_PROP, app_id/title) |
| `ConfigTagRule` parse.h:194 | `TagRule` Rules.swift:143 | differs | name (`TagRule`); D4: mango's int fields default 0 and `tag_rule_apply_to_slot` applies them when ≥0, ours nil (see tag-rule fields) |
| `ConfigEnv` / `ConfigVar` | `(String,String)` tuples Config.swift:151 / `ParserState.vars` ConfigParser.swift:182 | 1:1 | name |
| `ConfigMonitorRule`, `ConfigLayerRule`, `ConfigDeviceRule`, `SwitchBinding` | – | platform | listed MangoCompat.ignoredKeywords |
| `tags[tag_num_MAX]` preset.c:4 | – | platform | tag names for ext-workspace only (src/ext-protocol/ext-workspace.c:46) |
| `xkb_fallback_rules` preset.c:10 | – | platform | xkb keymap fallback; no xkb on macOS |
| `tag_num_MAX` preset.h:11 | literal 31 (Config.swift:175, Rules.swift:9,17,26, RuleParser.swift:125) | 1:1 | name: no named constant |
| `MODKEY` preset.h:5 | – | 1:1 | unused in mango too |
| assets/config.conf (shipped) | Resources/config.conf | port | lines 1-176 (every option, rule, comment) identical; bindings rebound to HYPER in a region marked `# not mango default` (listed §1, §2). Inside the region, besides the stated omissions (rofi, middle click), mango's `SUPER,Left/Right,viewtoleft/viewtoright,0` are not carried over (only the `_have_client` pair, on comma/period), and scroller_stack/movewin/resizewin moved into a `window` key mode; the region comments name mango's keys but not the two dropped binds |
| assets/config.toml (shipped) | not shipped; `~/.config/mango/config.toml` read when no config.conf (ConfigParser.swift:64) | platform | same 126 options as config.conf (checked); mango installs it to /etc/mango and reads it only without a config.conf; no /etc on macOS (listed §3) |

## Config keys (parse_option, one row per key)
Columns: key | mango line | mango default (set_value_default) | ours (setter) | our default (Config.swift) |
parsing/clamp mango → ours | status | note. Clamp ranges of the form `int(lo...hi)` are applied by our setter at
parse time and again in `overrideConfig`; mango applies them once in `override_config`; same result.

| key | mango | mango default | ours | our default | parse/clamp | status | note |
|---|---|---|---|---|---|---|---|
| `key_mode` | option_defs.c:56 | - | Sources/Mango/Config/ConfigParser.swift:361, Sources/Mango/Config/ConfigOptions.swift:64 | "default" (mango: keymode "default", load.c) | snprintf → `%.27s` copy | differs | empty value (`key_mode= ` or `key_mode=""`): mango sets mode "" so later binds sit in an unreachable mode "", ours resets to "default"; mango truncates to 27 chars, ours keeps the whole name |
| `animations` | option_defs.c:58 | 1 | Sources/Mango/Config/ConfigOptions.swift:105 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `layer_animations` | option_defs.c:60 | 0 | Port/macOS/MangoCompat.swift:40 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Layer surfaces" |
| `animation_type_open` | option_defs.c:62 | ANIM_TYPE_UNSET | Sources/Mango/Config/ConfigOptions.swift:106 | .slide (mango ANIM_TYPE_UNSET) | animation_type_from_string → animation_type_from_string | 1:1 | same result: UNSET and UNKNOWN both fall to the slide branch of set_client_open_animation; ours stores .slide |
| `animation_type_close` | option_defs.c:64 | ANIM_TYPE_UNSET | Sources/Mango/Config/ConfigOptions.swift:107 | .slide | animation_type_from_string → animation | platform | stored, no effect: listed MangoCompat.optionsWithoutEffect (close animation: window already gone) |
| `layer_animation_type_open` | option_defs.c:66 | ANIM_TYPE_UNSET | Port/macOS/MangoCompat.swift:40 | - | animation_type_from_string → ignored | platform | listed MangoCompat "Layer surfaces" |
| `layer_animation_type_close` | option_defs.c:68 | ANIM_TYPE_UNSET | Port/macOS/MangoCompat.swift:40 | - | animation_type_from_string → ignored | platform | listed MangoCompat "Layer surfaces" |
| `animation_fade_in` | option_defs.c:70 | 1 | Sources/Mango/Config/ConfigOptions.swift:108 | true | atoi; override 0..1 → bool | platform | stored, no effect: listed MangoCompat.optionsWithoutEffect (opacity needs SIP off) |
| `animation_fade_out` | option_defs.c:72 | 1 | Sources/Mango/Config/ConfigOptions.swift:109 | true | atoi; override 0..1 → bool | platform | stored, no effect: listed MangoCompat.optionsWithoutEffect (opacity needs SIP off) |
| `tag_animation_direction` | option_defs.c:74 | HORIZONTAL | Sources/Mango/Config/ConfigOptions.swift:110 | 1 (HORIZONTAL) | atoi; override CLAMP 0..1 → int(0...1) | 1:1 | ours clamps at parse; same result |
| `zoom_initial_ratio` | option_defs.c:76 | 0.4f | Sources/Mango/Config/ConfigOptions.swift:111 | 0.4 | atof; override 0.1f..1.0f → double | 1:1 |  |
| `zoom_end_ratio` | option_defs.c:78 | 0.8f | Sources/Mango/Config/ConfigOptions.swift:112 | 0.8 | atof; override 0.1f..1.0f → double | platform | stored, no effect: listed MangoCompat.optionsWithoutEffect (close animation: window already gone) |
| `fade_in_begin_opacity` | option_defs.c:80 | 0.5f | Sources/Mango/Config/ConfigOptions.swift:113 | 0.5 | atof; override 0.0f..1.0f → double | platform | stored, no effect: listed MangoCompat.optionsWithoutEffect (opacity needs SIP off) |
| `fade_out_begin_opacity` | option_defs.c:82 | 0.5f | Sources/Mango/Config/ConfigOptions.swift:114 | 0.5 | atof; override 0.0f..1.0f → double | platform | stored, no effect: listed MangoCompat.optionsWithoutEffect (opacity needs SIP off) |
| `animation_duration_move` | option_defs.c:84 | 500 | Sources/Mango/Config/ConfigOptions.swift:115 | 500 | atoi; override 0..50000 → int | 1:1 |  |
| `animation_duration_open` | option_defs.c:86 | 400 | Sources/Mango/Config/ConfigOptions.swift:116 | 400 | atoi; override 0..50000 → int | 1:1 |  |
| `animation_duration_tag` | option_defs.c:88 | 300 | Sources/Mango/Config/ConfigOptions.swift:117 | 300 | atoi; override 0..50000 → int | 1:1 |  |
| `animation_duration_close` | option_defs.c:90 | 300 | Sources/Mango/Config/ConfigOptions.swift:118 | 300 | atoi; override 0..50000 → int | platform | stored, no effect: listed MangoCompat.optionsWithoutEffect (close animation: window already gone) |
| `animation_duration_focus` | option_defs.c:92 | 0 | Sources/Mango/Config/ConfigOptions.swift:119 | 0 | atoi; override 0..50000 → int | missing | mango's focus animation also fades the border colour (client_start_focus_animation, animation/client.c:1682); the port draws the borders and could. Stored, read nowhere; MangoCompat lists it only as opacity ("SIP off"), which covers half of it. Default 0 = same result |
| `animation_curve_move` | option_defs.c:94 | (0.46,1.0,0.29,0.99) | Sources/Mango/Config/ConfigOptions.swift:120 | (0.46,1.0,0.29,0.99) | parse_double_array → parse_double_array(…,4) ==4 else error | differs | D3: a bad value (`0.46,1.0,0.29`) leaves our curve unchanged; mango memsets the array to 0 and fills what parsed, so the curve becomes (0.46,1.0,0.29,0). Mango also prints "Invalid number in array" before "Failed to parse" |
| `animation_curve_open` | option_defs.c:104 | (0.46,1.0,0.29,0.99) | Sources/Mango/Config/ConfigOptions.swift:121 | (0.46,1.0,0.29,0.99) | parse_double_array → as move | differs | D3 |
| `animation_curve_tag` | option_defs.c:114 | (0.46,1.0,0.29,0.99) | Sources/Mango/Config/ConfigOptions.swift:122 | (0.46,1.0,0.29,0.99) | parse_double_array → as move | differs | D3 |
| `animation_curve_close` | option_defs.c:123 | (0.46,1.0,0.29,0.99) | Sources/Mango/Config/ConfigOptions.swift:123 | BezierCurve.mangoDefault | parse_double_array → curve("animation_curve_close") | platform | stored, no effect: listed MangoCompat.optionsWithoutEffect (close animation: window already gone) |
| `animation_curve_focus` | option_defs.c:133 | (0.46,1.0,0.29,0.99) | Sources/Mango/Config/ConfigOptions.swift:124 | BezierCurve.mangoDefault | parse_double_array → curve | missing | mango's focus animation also fades the border colour (client_start_focus_animation, animation/client.c:1682); the port draws the borders and could. Stored, read nowhere; MangoCompat lists it only as opacity ("SIP off"), which covers half of it. Default 0 = same result |
| `animation_curve_opacity_fade_in` | option_defs.c:143 | (0.46,1.0,0.29,0.99) | Port/macOS/MangoCompat.swift:37 | - | parse_double_array → ignored | platform | listed MangoCompat "Opacity animation" |
| `animation_curve_opacity_fade_out` | option_defs.c:153 | (0.5,0.5,0.5,0.5) | Port/macOS/MangoCompat.swift:37 | - | parse_double_array → ignored | platform | listed MangoCompat "Opacity animation" |
| `scroller_structs` | option_defs.c:164 | 20 | Sources/Mango/Config/ConfigOptions.swift:126 | 20 | atoi; override 0..1000 → int | 1:1 |  |
| `scroller_default_proportion` | option_defs.c:166 | 0.9f | Sources/Mango/Config/ConfigOptions.swift:127 | 0.9 | atof; override 0.1f..1.0f → double | 1:1 |  |
| `scroller_default_proportion_single` | option_defs.c:168 | 1.0f | Sources/Mango/Config/ConfigOptions.swift:128 | 1.0 | atof; override 0.1f..1.0f → double | 1:1 |  |
| `scroller_ignore_proportion_single` | option_defs.c:170 | 1 | Sources/Mango/Config/ConfigOptions.swift:129 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `scroller_focus_center` | option_defs.c:172 | 0 | Sources/Mango/Config/ConfigOptions.swift:130 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `scroller_prefer_center` | option_defs.c:174 | 0 | Sources/Mango/Config/ConfigOptions.swift:131 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `scroller_prefer_overspread` | option_defs.c:176 | 1 | Sources/Mango/Config/ConfigOptions.swift:132 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `edge_scroller_pointer_focus` | option_defs.c:178 | 1 | Sources/Mango/Config/ConfigOptions.swift:133 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `edge_scroller_focus_allow_speed` | option_defs.c:180 | 0.0f | Sources/Mango/Config/ConfigOptions.swift:134 | 0.0 | atof; override 0.0f..1000.0f → double | 1:1 |  |
| `focus_cross_monitor` | option_defs.c:182 | 0 | Sources/Mango/Config/ConfigOptions.swift:239 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `focus_direction_only_zone_overlap` | option_defs.c:184 | 1 | Sources/Mango/Config/ConfigOptions.swift:240 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `exchange_cross_monitor` | option_defs.c:186 | 0 | Sources/Mango/Config/ConfigOptions.swift:242 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `scratchpad_cross_monitor` | option_defs.c:188 | 0 | Sources/Mango/Config/ConfigOptions.swift:243 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `special_tag_cross_monitor` | option_defs.c:190 | 0 | Sources/Mango/Config/ConfigOptions.swift:178 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `focus_cross_tag` | option_defs.c:192 | 0 | Sources/Mango/Config/ConfigOptions.swift:241 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `view_current_to_back` | option_defs.c:194 | 0 | Sources/Mango/Config/ConfigOptions.swift:159 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `blur` | option_defs.c:196 | 0 | Port/macOS/MangoCompat.swift:26 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Blur" |
| `blur_layer` | option_defs.c:198 | 0 | Port/macOS/MangoCompat.swift:26 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Blur" |
| `blur_optimized` | option_defs.c:200 | 1 | Port/macOS/MangoCompat.swift:26 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Blur" |
| `border_radius` | option_defs.c:202 | 0 | Sources/Mango/Config/ConfigOptions.swift:201 | 0 | atoi → int; overrideConfig 0..100 | 1:1 | parse 1:1; the port rounds only its own border frame (window corners: listed §3) |
| `blur_params_num_passes` | option_defs.c:204 | 1 | Port/macOS/MangoCompat.swift:27 | - | atoi; override 0..10 → ignored | platform | listed MangoCompat "Blur" |
| `blur_params_radius` | option_defs.c:206 | 5 | Port/macOS/MangoCompat.swift:27 | - | atoi; override 0..100 → ignored | platform | listed MangoCompat "Blur" |
| `blur_params_noise` | option_defs.c:208 | 0.02f | Port/macOS/MangoCompat.swift:27 | - | atof; override 0..1 → ignored | platform | listed MangoCompat "Blur" |
| `blur_params_brightness` | option_defs.c:210 | 0.9f | Port/macOS/MangoCompat.swift:26 | - | atof; override 0..2 → ignored | platform | listed MangoCompat "Blur" |
| `blur_params_contrast` | option_defs.c:212 | 0.9f | Port/macOS/MangoCompat.swift:26 | - | atof; override 0..2 → ignored | platform | listed MangoCompat "Blur" |
| `blur_params_saturation` | option_defs.c:214 | 1.2f | Port/macOS/MangoCompat.swift:27 | - | atof; override 0..2 → ignored | platform | listed MangoCompat "Blur" |
| `shadows` | option_defs.c:216 | 0 | Port/macOS/MangoCompat.swift:30 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Shadows" |
| `shadow_only_floating` | option_defs.c:218 | 1 | Port/macOS/MangoCompat.swift:31 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Shadows" |
| `layer_shadows` | option_defs.c:220 | 0 | Port/macOS/MangoCompat.swift:31 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Shadows" |
| `shadows_size` | option_defs.c:222 | 10 | Port/macOS/MangoCompat.swift:30 | - | atoi; override 0..100 → ignored | platform | listed MangoCompat "Shadows" |
| `shadows_blur` | option_defs.c:224 | 15.0f | Port/macOS/MangoCompat.swift:30 | - | atof; override 0..100 → ignored | platform | listed MangoCompat "Shadows" |
| `shadows_position_x` | option_defs.c:226 | 0 | Port/macOS/MangoCompat.swift:30 | - | atoi; override -1000..1000 → ignored | platform | listed MangoCompat "Shadows" |
| `shadows_position_y` | option_defs.c:228 | 0 | Port/macOS/MangoCompat.swift:31 | - | atoi; override -1000..1000 → ignored | platform | listed MangoCompat "Shadows" |
| `single_scratchpad` | option_defs.c:230 | 1 | Sources/Mango/Config/ConfigOptions.swift:244 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `xwayland_persistence` | option_defs.c:232 | 1 | Port/macOS/MangoCompat.swift:74 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Xwayland" |
| `xwayland_ignore_scale` | option_defs.c:234 | 0 | Port/macOS/MangoCompat.swift:74 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Xwayland" |
| `sync_obj_enable` | option_defs.c:236 | 1 | Port/macOS/MangoCompat.swift:43 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Display" |
| `tag_carousel` | option_defs.c:238 | 0 | Sources/Mango/Config/ConfigOptions.swift:158 | false | atoi → bool | 1:1 | not clamped in mango; atoi!=0 same result |
| `allow_tearing` | option_defs.c:240 | TEARING_DISABLED | Port/macOS/MangoCompat.swift:43 | - | atoi; override 0..2 → ignored | platform | listed MangoCompat "Display" |
| `hdr_depth` | option_defs.c:242 | MANGO_RENDER_BIT_DEPTH_10 | Port/macOS/MangoCompat.swift:43 | - | atoi; override 0..2 → ignored | platform | listed MangoCompat "Display" |
| `allow_shortcuts_inhibit` | option_defs.c:244 | SHORTCUTS_INHIBIT_ENABLE | Port/macOS/MangoCompat.swift:71 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Wayland protocols" |
| `disable_middle_paste` | option_defs.c:246 | 0 | Port/macOS/MangoCompat.swift:62 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Other input" |
| `allow_lock_transparent` | option_defs.c:248 | 0 | Port/macOS/MangoCompat.swift:71 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Wayland protocols" |
| `auto_reload_config` | option_defs.c:250 | 1 | Sources/Mango/Config/ConfigOptions.swift:257 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `no_border_when_single` | option_defs.c:252 | 0 | Sources/Mango/Config/ConfigOptions.swift:202 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `no_radius_when_single` | option_defs.c:254 | 0 | Sources/Mango/Config/ConfigOptions.swift:203 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `monocle_no_border` | option_defs.c:256 | 0 | Sources/Mango/Config/ConfigOptions.swift:175 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `monocle_no_gap` | option_defs.c:258 | 0 | Sources/Mango/Config/ConfigOptions.swift:176 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `monocle_no_radius` | option_defs.c:260 | 0 | Sources/Mango/Config/ConfigOptions.swift:177 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `snap_distance` | option_defs.c:262 | 30 | Sources/Mango/Config/ConfigOptions.swift:252 | 30 | atoi; override 0..99999 → int(0...99999) | 1:1 |  |
| `enable_floating_snap` | option_defs.c:264 | 0 | Sources/Mango/Config/ConfigOptions.swift:251 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `float_full_to_top` | option_defs.c:266 | 0 | Sources/Mango/Config/ConfigOptions.swift:253 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `drag_tile_to_tile` | option_defs.c:268 | 1 | Sources/Mango/Config/ConfigOptions.swift:254 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `drag_tile_small` | option_defs.c:270 | 1 | Sources/Mango/Config/ConfigOptions.swift:255 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `swipe_min_threshold` | option_defs.c:272 | 1 | Sources/Mango/Config/ConfigOptions.swift:258 | 1 | atoi; override 1..1000 → int(1...1000) | 1:1 |  |
| `gesture_live` | option_defs.c:274 | 1 | Sources/Mango/Config/ConfigOptions.swift:259 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `gesture_swipe_distance` | option_defs.c:276 | 300 | Sources/Mango/Config/ConfigOptions.swift:260 | 300 | atoi; override 32..4096 → int(32...4096) | 1:1 |  |
| `gesture_swipe_cancel_ratio` | option_defs.c:278 | 0.5 | Sources/Mango/Config/ConfigOptions.swift:261 | 0.5 | atof; override 0.05..0.95 → double(0.05...0.95) | 1:1 |  |
| `gesture_swipe_min_speed_to_force` | option_defs.c:280 | 10 | Sources/Mango/Config/ConfigOptions.swift:262 | 10.0 | atof; override >=0 → double(0...Double.greatestFiniteMagnitude) | 1:1 |  |
| `focused_opacity` | option_defs.c:282 | 1.0f | Sources/Mango/Config/ConfigOptions.swift:204 | 1.0 | atof; override 0.0f..1.0f → double | platform | stored, no effect: listed MangoCompat.optionsWithoutEffect (opacity needs SIP off) |
| `unfocused_opacity` | option_defs.c:284 | 1.0f | Sources/Mango/Config/ConfigOptions.swift:205 | 1.0 | atof; override 0.0f..1.0f → double | platform | stored, no effect: listed MangoCompat.optionsWithoutEffect (opacity needs SIP off) |
| `xkb_rules_rules` | option_defs.c:286 | - | Port/macOS/MangoCompat.swift:46 | - | strncpy → ignored | platform | listed MangoCompat "Keyboard" |
| `xkb_rules_model` | option_defs.c:290 | - | Port/macOS/MangoCompat.swift:46 | - | strncpy → ignored | platform | listed MangoCompat "Keyboard" |
| `xkb_rules_layout` | option_defs.c:294 | - | Port/macOS/MangoCompat.swift:46 | - | strncpy → ignored | platform | listed MangoCompat "Keyboard" |
| `xkb_rules_variant` | option_defs.c:298 | - | Port/macOS/MangoCompat.swift:46 | - | strncpy → ignored | platform | listed MangoCompat "Keyboard" |
| `xkb_rules_options` | option_defs.c:302 | - | Sources/Mango/Config/ConfigOptions.swift:103 | "" | strncpy → strncpy 127 | port | only key-moving options, done by the port (listed §3); other xkb_rules_* ignored |
| `scroller_proportion_preset` | option_defs.c:306 | - | Sources/Mango/Config/ConfigOptions.swift:135 | [] (mango NULL) | strdup → count commas+1, strtok tokens, sscanf %f, CLAMP 0.1..1, count must match | differs | on a bad value (`0.5,x` or `0.5,,0.8`) mango frees the list (preset becomes empty), ours returns invalid and keeps the previous list; sscanf %f also takes inf/nan/hex, our scanDouble does not |
| `circle_layout` | option_defs.c:381 | - | Sources/Mango/Config/ConfigOptions.swift:160 | [] (mango NULL) | strdup → count commas+1, strtok tokens, sanitize_string, count must match else error and list emptied | differs | `circle_layout=tile,,scroller` or a trailing comma: mango errors "Invalid circle_layout format" and empties the list; ours silently keeps [tile, scroller]. Ours trims Cc/Cf chars where mango strips !isprint bytes (same for ASCII) |
| `new_is_master` | option_defs.c:461 | 1 | Sources/Mango/Config/ConfigOptions.swift:151 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `default_master_factor` | option_defs.c:463 | 0.55f | Sources/Mango/Config/ConfigOptions.swift:152 | 0.55 | atof; override 0.1f..0.9f → double | 1:1 |  |
| `default_master_count` | option_defs.c:465 | 1 | Sources/Mango/Config/ConfigOptions.swift:153 | 1 | atoi; override 1..1000 → int | 1:1 |  |
| `tag_num` | option_defs.c:467 | 9 | Sources/Mango/Config/ConfigOptions.swift:156 | 9 | atoi → int; overrideConfig 1..31 | 1:1 | tagmask derived at use (Rules.swift:7, marked) |
| `tag_gather` | option_defs.c:469 | 0 | Sources/Mango/Config/ConfigOptions.swift:157 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `center_master_overspread` | option_defs.c:471 | 0 | Sources/Mango/Config/ConfigOptions.swift:154 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `center_when_single_stack` | option_defs.c:473 | 1 | Sources/Mango/Config/ConfigOptions.swift:155 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `dwindle_vertical_split` | option_defs.c:475 | 1 | Sources/Mango/Config/ConfigOptions.swift:166 | 1 | atoi; override 0..2 → int | 1:1 |  |
| `dwindle_horizontal_split` | option_defs.c:477 | 1 | Sources/Mango/Config/ConfigOptions.swift:167 | 1 | atoi; override 0..2 → int | 1:1 |  |
| `dwindle_preserve_split` | option_defs.c:479 | 0 | Sources/Mango/Config/ConfigOptions.swift:168 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `dwindle_smart_split` | option_defs.c:481 | 0 | Sources/Mango/Config/ConfigOptions.swift:169 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `dwindle_smart_resize` | option_defs.c:483 | 0 | Sources/Mango/Config/ConfigOptions.swift:170 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `dwindle_drop_simple_split` | option_defs.c:485 | 1 | Sources/Mango/Config/ConfigOptions.swift:172 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `dwindle_manual_split` | option_defs.c:487 | 0 | Sources/Mango/Config/ConfigOptions.swift:171 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `dwindle_split_ratio` | option_defs.c:489 | 0.5f | Sources/Mango/Config/ConfigOptions.swift:173 | 0.5 | atof; override 0.05f..0.95f → double | 1:1 |  |
| `hotarea_size` | option_defs.c:491 | 10 | Sources/Mango/Config/ConfigOptions.swift:224 | 10 | atoi; override 1..1000 → int(1...1000) | 1:1 |  |
| `hotarea_corner` | option_defs.c:493 | BOTTOM_LEFT | Sources/Mango/Config/ConfigOptions.swift:225 | 2 | atoi; override 0..3 → int | 1:1 |  |
| `enable_hotarea` | option_defs.c:495 | 0 | Sources/Mango/Config/ConfigOptions.swift:226 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `hotarea_disable_on_fullscreen` | option_defs.c:497 | 1 | Sources/Mango/Config/ConfigOptions.swift:227 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `overview_gap_inner` | option_defs.c:499 | 5 | Sources/Mango/Config/ConfigOptions.swift:228 | 5 | atoi; override 0..1000 → int(0...1000) | 1:1 |  |
| `overview_gap_outer` | option_defs.c:501 | 30 | Sources/Mango/Config/ConfigOptions.swift:229 | 30 | atoi; override 0..1000 → int(0...1000) | 1:1 |  |
| `overcircle_center_ratio` | option_defs.c:503 | 0.5f | Sources/Mango/Config/ConfigOptions.swift:230 | 0.5 | atof; override 0.1f..0.9f → double(0.1...0.9) | 1:1 |  |
| `jump_labels` | option_defs.c:505 | - | Sources/Mango/Config/ConfigOptions.swift:231 | "HJKLASDFGQWERTYUIOPZXCVBNM" (mango NULL→default_jump_labels, load.c:52) | strdup → strdup | 1:1 | labels indexed by Character in ours, by byte in mango (only non-ASCII labels differ) |
| `cursor_hide_timeout` | option_defs.c:509 | 0 | Sources/Mango/Config/ConfigOptions.swift:245 | 0 | atoi; override 0..36000 → int(0...36000) | 1:1 |  |
| `cursor_hide_on_keypress` | option_defs.c:511 | 0 | Sources/Mango/Config/ConfigOptions.swift:246 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `axis_bind_apply_timeout` | option_defs.c:513 | 100 | Sources/Mango/Config/ConfigOptions.swift:256 | 100 | atoi; override 0..1000 → int(0...1000) | 1:1 |  |
| `focus_on_activate` | option_defs.c:515 | 1 | Sources/Mango/Config/ConfigOptions.swift:236 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `numlock_on` | option_defs.c:517 | 0 | Port/macOS/MangoCompat.swift:47 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Keyboard" |
| `idle_inhibit_ignore_visible` | option_defs.c:519 | 0 | Port/macOS/MangoCompat.swift:68 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Idle" |
| `idle_inhibit_when_fullscreen` | option_defs.c:521 | 0 | Port/macOS/MangoCompat.swift:68 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Idle" |
| `sloppy_focus` | option_defs.c:523 | 1 | Sources/Mango/Config/ConfigOptions.swift:237 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `warp_cursor` | option_defs.c:525 | 1 | Sources/Mango/Config/ConfigOptions.swift:238 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `drag_corner` | option_defs.c:527 | 3 | Sources/Mango/Config/ConfigOptions.swift:247 | 3 | atoi; override 0..4 → int(0...4) | 1:1 |  |
| `drag_warp_cursor` | option_defs.c:529 | 1 | Sources/Mango/Config/ConfigOptions.swift:248 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `enable_border_resize` | option_defs.c:531 | 1 | Sources/Mango/Config/ConfigOptions.swift:249 | true | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `border_resize_size` | option_defs.c:533 | 10 | Sources/Mango/Config/ConfigOptions.swift:250 | 10 | atoi; override 0..50 → int(0...50) | 1:1 |  |
| `smart_gaps` | option_defs.c:535 | 0 | Sources/Mango/Config/ConfigOptions.swift:199 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `monocle_tab_mode` | option_defs.c:537 | 1 | Sources/Mango/Config/ConfigOptions.swift:174 | true | atoi → bool | 1:1 | not clamped in mango; atoi!=0 same result |
| `monocle_right_button_close` | option_defs.c:539 | 0 | Sources/Mango/Config/ConfigOptions.swift:187 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `deck_tab_mode` | option_defs.c:541 | 1 | Sources/Mango/Config/ConfigOptions.swift:179 | true | atoi → bool | 1:1 | not clamped in mango; atoi!=0 same result |
| `repeat_rate` | option_defs.c:543 | 25 | Port/macOS/MangoCompat.swift:47 | - | atoi; override 1..1000 → ignored | platform | listed MangoCompat "Keyboard" |
| `repeat_delay` | option_defs.c:545 | 600 | Port/macOS/MangoCompat.swift:47 | - | atoi; override 1..20000 → ignored | platform | listed MangoCompat "Keyboard" |
| `disable_trackpad` | option_defs.c:547 | 0 | Port/macOS/MangoCompat.swift:58 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Trackpad and touch" |
| `touch_enable` | option_defs.c:549 | 1 | Port/macOS/MangoCompat.swift:59 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Trackpad and touch" |
| `touch_enable_mouse_emulation` | option_defs.c:551 | 0 | Port/macOS/MangoCompat.swift:59 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Trackpad and touch" |
| `tap_to_click` | option_defs.c:553 | 1 | Port/macOS/MangoCompat.swift:59 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Trackpad and touch" |
| `tap_and_drag` | option_defs.c:555 | 1 | Port/macOS/MangoCompat.swift:59 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Trackpad and touch" |
| `drag_lock` | option_defs.c:557 | 1 | Port/macOS/MangoCompat.swift:59 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Trackpad and touch" |
| `mouse_natural_scrolling` | option_defs.c:559 | 0 | Port/macOS/MangoCompat.swift:51 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Mouse" |
| `trackpad_natural_scrolling` | option_defs.c:561 | 0 | Port/macOS/MangoCompat.swift:57 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Trackpad and touch" |
| `cursor_size` | option_defs.c:563 | 24 | Port/macOS/MangoCompat.swift:65 | - | atoi; override 4..512 → ignored | platform | listed MangoCompat "Cursor" |
| `cursor_theme` | option_defs.c:565 | - | Port/macOS/MangoCompat.swift:65 | - | strdup → ignored | platform | listed MangoCompat "Cursor" |
| `group_bar_decorate_font_desc` | option_defs.c:569 | NULL → "monospace Bold 13" (draw/text-node.c) | Sources/Mango/Config/ConfigOptions.swift:192 | nil → DecorateStyle.mango* (Decorate.swift) | strdup → decorate | 1:1 | strdup |
| `group_bar_decorate_fg_color` | option_defs.c:573 | (c0,ca,f5,1.0f) | Sources/Mango/Config/ConfigOptions.swift:192 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `group_bar_decorate_bg_color` | option_defs.c:585 | (1d,20,21,1.0f) | Sources/Mango/Config/ConfigOptions.swift:192 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `group_bar_decorate_focus_fg_color` | option_defs.c:597 | (9e,ce,6a,1.0f) | Sources/Mango/Config/ConfigOptions.swift:192 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `group_bar_decorate_focus_bg_color` | option_defs.c:609 | (3c,38,36,1.0f) | Sources/Mango/Config/ConfigOptions.swift:192 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `group_bar_decorate_border_color` | option_defs.c:621 | (3b,42,61,1.0f) | Sources/Mango/Config/ConfigOptions.swift:192 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `group_bar_decorate_border_width` | option_defs.c:633 | 4 | Sources/Mango/Config/ConfigOptions.swift:192 | nil → DecorateStyle.mango* (Decorate.swift) | atoi, CLAMP 0..100; override 0..100 → decorate(0...100) | 1:1 | CLAMP 0..100 at parse (mango too) |
| `group_bar_decorate_corner_radius` | option_defs.c:635 | 5 | Sources/Mango/Config/ConfigOptions.swift:192 | nil → DecorateStyle.mango* (Decorate.swift) | atoi, CLAMP 0..100; override 0..100 → decorate(0...100) | 1:1 | CLAMP 0..100 at parse (mango too) |
| `group_bar_decorate_padding_x` | option_defs.c:637 | 0 | Sources/Mango/Config/ConfigOptions.swift:192 | nil → DecorateStyle.mango* (Decorate.swift) | atoi, CLAMP 0..100; override 0..100 → decorate(0...100) | 1:1 | CLAMP 0..100 at parse (mango too) |
| `group_bar_decorate_padding_y` | option_defs.c:639 | 0 | Sources/Mango/Config/ConfigOptions.swift:192 | nil → DecorateStyle.mango* (Decorate.swift) | atoi, CLAMP 0..100; override 0..100 → decorate(0...100) | 1:1 | CLAMP 0..100 at parse (mango too) |
| `title_message_bar_decorate_font_desc` | option_defs.c:641 | NULL → "monospace Bold 13" (draw/text-node.c) | Sources/Mango/Config/ConfigOptions.swift:190 | nil → DecorateStyle.mango* (Decorate.swift) | strdup → decorate | 1:1 | strdup |
| `title_message_bar_decorate_fg_color` | option_defs.c:645 | (c0,ca,f5,1.0f) (copy of groupbardata) | Sources/Mango/Config/ConfigOptions.swift:190 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `title_message_bar_decorate_bg_color` | option_defs.c:657 | (1d,20,21,1.0f) (copy of groupbardata) | Sources/Mango/Config/ConfigOptions.swift:190 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `title_message_bar_decorate_focus_fg_color` | option_defs.c:669 | (9e,ce,6a,1.0f) (copy of groupbardata) | Sources/Mango/Config/ConfigOptions.swift:190 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `title_message_bar_decorate_focus_bg_color` | option_defs.c:682 | (3c,38,36,1.0f) (copy of groupbardata) | Sources/Mango/Config/ConfigOptions.swift:190 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `title_message_bar_decorate_border_color` | option_defs.c:695 | (3b,42,61,1.0f) (copy of groupbardata) | Sources/Mango/Config/ConfigOptions.swift:190 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `title_message_bar_decorate_border_width` | option_defs.c:708 | 0 | Sources/Mango/Config/ConfigOptions.swift:190 | nil → DecorateStyle.mango* (Decorate.swift) | atoi, CLAMP 0..100; override 0..100 → decorate(0...100) | 1:1 | CLAMP 0..100 at parse (mango too) |
| `title_message_bar_decorate_corner_radius` | option_defs.c:711 | 15 | Sources/Mango/Config/ConfigOptions.swift:190 | nil → DecorateStyle.mango* (Decorate.swift) | atoi, CLAMP 0..100; override 0..100 → decorate(0...100) | 1:1 | CLAMP 0..100 at parse (mango too) |
| `title_message_bar_decorate_padding_x` | option_defs.c:714 | 0 (copy of groupbardata) | Sources/Mango/Config/ConfigOptions.swift:190 | nil → DecorateStyle.mango* (Decorate.swift) | atoi, CLAMP 0..100; override 0..100 → decorate(0...100) | 1:1 | CLAMP 0..100 at parse (mango too) |
| `title_message_bar_decorate_padding_y` | option_defs.c:717 | 0 (copy of groupbardata) | Sources/Mango/Config/ConfigOptions.swift:190 | nil → DecorateStyle.mango* (Decorate.swift) | atoi, CLAMP 0..100; override 0..100 → decorate(0...100) | 1:1 | CLAMP 0..100 at parse (mango too) |
| `tab_bar_decorate_font_desc` | option_defs.c:720 | NULL → "monospace Bold 13" (draw/text-node.c) | Sources/Mango/Config/ConfigOptions.swift:191 | nil → DecorateStyle.mango* (Decorate.swift) | strdup → decorate | 1:1 | strdup |
| `tab_bar_decorate_fg_color` | option_defs.c:724 | (c0,ca,f5,1.0f) | Sources/Mango/Config/ConfigOptions.swift:191 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `tab_bar_decorate_bg_color` | option_defs.c:736 | (1d,20,21,1.0f) | Sources/Mango/Config/ConfigOptions.swift:191 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `tab_bar_decorate_focus_fg_color` | option_defs.c:748 | (7a,a2,f7,1.0f) | Sources/Mango/Config/ConfigOptions.swift:191 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `tab_bar_decorate_focus_bg_color` | option_defs.c:760 | (3c,38,36,1.0f) | Sources/Mango/Config/ConfigOptions.swift:191 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `tab_bar_decorate_border_color` | option_defs.c:772 | (3b,42,61,1.0f) | Sources/Mango/Config/ConfigOptions.swift:191 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `tab_bar_decorate_border_width` | option_defs.c:784 | 4 | Sources/Mango/Config/ConfigOptions.swift:191 | nil → DecorateStyle.mango* (Decorate.swift) | atoi, CLAMP 0..100; override 0..100 → decorate(0...100) | 1:1 | CLAMP 0..100 at parse (mango too) |
| `tab_bar_decorate_corner_radius` | option_defs.c:786 | 5 | Sources/Mango/Config/ConfigOptions.swift:191 | nil → DecorateStyle.mango* (Decorate.swift) | atoi, CLAMP 0..100; override 0..100 → decorate(0...100) | 1:1 | CLAMP 0..100 at parse (mango too) |
| `tab_bar_decorate_padding_x` | option_defs.c:788 | 0 | Sources/Mango/Config/ConfigOptions.swift:191 | nil → DecorateStyle.mango* (Decorate.swift) | atoi, CLAMP 0..100; override 0..100 → decorate(0...100) | 1:1 | CLAMP 0..100 at parse (mango too) |
| `tab_bar_decorate_padding_y` | option_defs.c:790 | 0 | Sources/Mango/Config/ConfigOptions.swift:191 | nil → DecorateStyle.mango* (Decorate.swift) | atoi, CLAMP 0..100; override 0..100 → decorate(0...100) | 1:1 | CLAMP 0..100 at parse (mango too) |
| `jump_label_decorate_font_desc` | option_defs.c:792 | NULL → "monospace Bold 16" (draw/text-node.c) | Sources/Mango/Config/ConfigOptions.swift:193 | nil → DecorateStyle.mango* (Decorate.swift) | strdup → decorate | 1:1 | strdup |
| `jump_label_decorate_fg_color` | option_defs.c:796 | (c4,93,9d,1.0f) | Sources/Mango/Config/ConfigOptions.swift:193 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `jump_label_decorate_bg_color` | option_defs.c:808 | (32,32,32,1.0f) | Sources/Mango/Config/ConfigOptions.swift:193 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `jump_label_decorate_focus_fg_color` | option_defs.c:820 | (ed,a6,b4,1.0f) | Sources/Mango/Config/ConfigOptions.swift:193 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `jump_label_decorate_focus_bg_color` | option_defs.c:832 | (4e,45,3c,1.0f) | Sources/Mango/Config/ConfigOptions.swift:193 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `jump_label_decorate_border_color` | option_defs.c:844 | (8b,aa,9b,1.0f) | Sources/Mango/Config/ConfigOptions.swift:193 | nil → DecorateStyle.mango* (Decorate.swift) | parse_color → decorate | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `jump_label_decorate_border_width` | option_defs.c:856 | 4 | Sources/Mango/Config/ConfigOptions.swift:193 | nil → DecorateStyle.mango* (Decorate.swift) | atoi, CLAMP 0..100; override 0..100 → decorate(0...100) | 1:1 | CLAMP 0..100 at parse (mango too) |
| `jump_label_decorate_corner_radius` | option_defs.c:858 | 5 | Sources/Mango/Config/ConfigOptions.swift:193 | nil → DecorateStyle.mango* (Decorate.swift) | atoi, CLAMP 0..100; override 0..100 → decorate(0...100) | 1:1 | CLAMP 0..100 at parse (mango too) |
| `jump_label_decorate_padding_x` | option_defs.c:860 | 10 | Sources/Mango/Config/ConfigOptions.swift:193 | nil → DecorateStyle.mango* (Decorate.swift) | atoi, CLAMP 0..100; override 0..100 → decorate(0...100) | 1:1 | CLAMP 0..100 at parse (mango too) |
| `jump_label_decorate_padding_y` | option_defs.c:862 | 10 | Sources/Mango/Config/ConfigOptions.swift:193 | nil → DecorateStyle.mango* (Decorate.swift) | atoi, CLAMP 0..100; override 0..100 → decorate(0...100) | 1:1 | CLAMP 0..100 at parse (mango too) |
| `mouse_accel_profile` | option_defs.c:864 | LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE | Port/macOS/MangoCompat.swift:50 | - | atoi; override 0..2 → ignored | platform | listed MangoCompat "Mouse" |
| `mouse_accel_speed` | option_defs.c:866 | 0.0 | Port/macOS/MangoCompat.swift:50 | - | atof; override -1.0f..1.0f → ignored | platform | listed MangoCompat "Mouse" |
| `trackpad_accel_profile` | option_defs.c:868 | LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE | Port/macOS/MangoCompat.swift:55 | - | atoi; override 0..2 → ignored | platform | listed MangoCompat "Trackpad and touch" |
| `trackpad_accel_speed` | option_defs.c:870 | 0.0 | Port/macOS/MangoCompat.swift:55 | - | atof; override -1.0f..1.0f → ignored | platform | listed MangoCompat "Trackpad and touch" |
| `mouse_left_handed` | option_defs.c:872 | 0 | Port/macOS/MangoCompat.swift:50 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Mouse" |
| `mouse_middle_button_emulation` | option_defs.c:874 | 0 | Port/macOS/MangoCompat.swift:51 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Mouse" |
| `mouse_scroll_method` | option_defs.c:876 | LIBINPUT_CONFIG_SCROLL_2FG | Port/macOS/MangoCompat.swift:52 | - | atoi; override 0..4 → ignored | platform | listed MangoCompat "Mouse" |
| `mouse_scroll_button` | option_defs.c:878 | 274 | Port/macOS/MangoCompat.swift:51 | - | atoi; override 272..279 → ignored | platform | listed MangoCompat "Mouse" |
| `mouse_click_method` | option_defs.c:880 | LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS | Port/macOS/MangoCompat.swift:50 | - | atoi; override 0..2 → ignored | platform | listed MangoCompat "Mouse" |
| `mouse_send_events_mode` | option_defs.c:882 | LIBINPUT_CONFIG_SEND_EVENTS_ENABLED | Port/macOS/MangoCompat.swift:52 | - | atoi; override 0..2 → ignored | platform | listed MangoCompat "Mouse" |
| `trackpad_left_handed` | option_defs.c:884 | 0 | Port/macOS/MangoCompat.swift:56 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Trackpad and touch" |
| `trackpad_middle_button_emulation` | option_defs.c:886 | 0 | Port/macOS/MangoCompat.swift:56 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Trackpad and touch" |
| `trackpad_disable_while_typing` | option_defs.c:888 | 1 | Port/macOS/MangoCompat.swift:56 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Trackpad and touch" |
| `trackpad_scroll_method` | option_defs.c:890 | LIBINPUT_CONFIG_SCROLL_2FG | Port/macOS/MangoCompat.swift:58 | - | atoi; override 0..4 → ignored | platform | listed MangoCompat "Trackpad and touch" |
| `trackpad_scroll_button` | option_defs.c:892 | 274 | Port/macOS/MangoCompat.swift:57 | - | atoi; override 272..279 → ignored | platform | listed MangoCompat "Trackpad and touch" |
| `trackpad_click_method` | option_defs.c:894 | LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS | Port/macOS/MangoCompat.swift:55 | - | atoi; override 0..2 → ignored | platform | listed MangoCompat "Trackpad and touch" |
| `trackpad_send_events_mode` | option_defs.c:896 | LIBINPUT_CONFIG_SEND_EVENTS_ENABLED | Port/macOS/MangoCompat.swift:58 | - | atoi; override 0..2 → ignored | platform | listed MangoCompat "Trackpad and touch" |
| `send_events_mode` | option_defs.c:898 | LIBINPUT_CONFIG_SEND_EVENTS_ENABLED | Port/macOS/MangoCompat.swift:62 | - | atoi; override 0..2 → ignored | platform | listed MangoCompat "Other input" |
| `button_map` | option_defs.c:900 | LIBINPUT_CONFIG_TAP_MAP_LRM | Port/macOS/MangoCompat.swift:62 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Other input" |
| `axis_scroll_factor` | option_defs.c:902 | 1.0 | Port/macOS/MangoCompat.swift:62 | - | atof; override 0.1f..10.0f → ignored | platform | listed MangoCompat "Other input" |
| `trackpad_scroll_factor` | option_defs.c:904 | 1.0 | Port/macOS/MangoCompat.swift:57 | - | atof; override 0.1f..10.0f → ignored | platform | listed MangoCompat "Trackpad and touch" |
| `gap_inner_horizontal` | option_defs.c:906 | 5 | Sources/Mango/Config/ConfigOptions.swift:195 | 5 | atoi; override 0..1000 → int | 1:1 |  |
| `gap_inner_vertical` | option_defs.c:908 | 5 | Sources/Mango/Config/ConfigOptions.swift:196 | 5 | atoi; override 0..1000 → int | 1:1 |  |
| `gap_outer_horizontal` | option_defs.c:910 | 10 | Sources/Mango/Config/ConfigOptions.swift:197 | 10 | atoi; override 0..1000 → int | 1:1 |  |
| `gap_outer_vertical` | option_defs.c:912 | 10 | Sources/Mango/Config/ConfigOptions.swift:198 | 10 | atoi; override 0..1000 → int | 1:1 |  |
| `scratchpad_width_ratio` | option_defs.c:914 | 0.8f | Sources/Mango/Config/ConfigOptions.swift:216 | 0.8 | atof; override 0.1f..1.0f → double(0.1...1) | 1:1 |  |
| `scratchpad_height_ratio` | option_defs.c:916 | 0.9f | Sources/Mango/Config/ConfigOptions.swift:217 | 0.9 | atof; override 0.1f..1.0f → double(0.1...1) | 1:1 |  |
| `special_dim` | option_defs.c:918 | 0.5f | Sources/Mango/Config/ConfigOptions.swift:218 | 0.5 | atof; override 0.0f..1.0f → double(0...1) | 1:1 |  |
| `special_gap_inner_horizontal` | option_defs.c:920 | 10 | Sources/Mango/Config/ConfigOptions.swift:219 | 10 | atoi; override 0..1000 → int(0...1000) | 1:1 |  |
| `special_gap_inner_vertical` | option_defs.c:922 | 10 | Sources/Mango/Config/ConfigOptions.swift:220 | 10 | atoi; override 0..1000 → int(0...1000) | 1:1 |  |
| `special_gap_outer_horizontal` | option_defs.c:924 | 20 | Sources/Mango/Config/ConfigOptions.swift:221 | 20 | atoi; override 0..1000 → int(0...1000) | 1:1 |  |
| `special_gap_outer_vertical` | option_defs.c:926 | 20 | Sources/Mango/Config/ConfigOptions.swift:222 | 20 | atoi; override 0..1000 → int(0...1000) | 1:1 |  |
| `border_px` | option_defs.c:928 | 4 | Sources/Mango/Config/ConfigOptions.swift:200 | 4 | atoi; override 0..200 → int | 1:1 |  |
| `group_bar_height` | option_defs.c:930 | 33 | Sources/Mango/Config/ConfigOptions.swift:181 | 33 | atoi; override 0..500 → int(0...500) | 1:1 |  |
| `tab_bar_height` | option_defs.c:932 | 33 | Sources/Mango/Config/ConfigOptions.swift:180 | 33 | atoi; override 0..500 → int(0...500) | 1:1 |  |
| `title_message_bar_height` | option_defs.c:934 | 52 | Sources/Mango/Config/ConfigOptions.swift:188 | 52 | atoi; override 0..500 → int(0...500) | 1:1 |  |
| `title_message_bar_gap` | option_defs.c:936 | 20 | Sources/Mango/Config/ConfigOptions.swift:189 | 20 | atoi; override 0..500 → int(0...500) | 1:1 |  |
| `always_show_group_bar` | option_defs.c:938 | 0 | Sources/Mango/Config/ConfigOptions.swift:182 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `group_bar_close_button_enable` | option_defs.c:940 | 0 | Sources/Mango/Config/ConfigOptions.swift:183 | false | atoi; override 0..1 → bool | differs | D1: negative value → mango 0 (CLAMP_INT 0..1), ours on (atoi != 0) |
| `group_bar_button_size` | option_defs.c:942 | 16 | Sources/Mango/Config/ConfigOptions.swift:184 | 16 | atoi; override 4..64 → int(4...64) | 1:1 |  |
| `group_bar_button_margin` | option_defs.c:944 | 4 | Sources/Mango/Config/ConfigOptions.swift:185 | 4 | atoi; override 0..50 → int(0...50) | 1:1 |  |
| `group_bar_button_color` | option_defs.c:946 | (ad,40,1f,1.0f) | Sources/Mango/Config/ConfigOptions.swift:186 | parseColor("0xad401fff")! | parse_color → color("group_bar_button_color") | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `root_color` | option_defs.c:957 | (32,32,32,1.0f) | Sources/Mango/Config/ConfigOptions.swift:206 | parseColor("0x323232ff")! | parse_color → color("rootcolor") | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `shadows_color` | option_defs.c:970 | (0.0f,0.0f,0.0f,1.0f) | Port/macOS/MangoCompat.swift:30 | - | parse_color → ignored | platform | listed MangoCompat "Shadows" |
| `dim_enable` | option_defs.c:981 | 0 | Port/macOS/MangoCompat.swift:34 | - | atoi; override 0..1 → ignored | platform | listed MangoCompat "Dimming" |
| `dim_focused_color` | option_defs.c:983 | (0.0f,0.0f,0.0f,0.0f) | Port/macOS/MangoCompat.swift:34 | - | parse_color → ignored | platform | listed MangoCompat "Dimming" |
| `dim_unfocused_color` | option_defs.c:994 | (0.0f,0.0f,0.0f,55) | Port/macOS/MangoCompat.swift:34 | - | parse_color → ignored | platform | listed MangoCompat "Dimming" |
| `border_color` | option_defs.c:1005 | (44,44,44,1.0f) | Sources/Mango/Config/ConfigOptions.swift:207 | parseColor("0x444444ff")! | parse_color → color("bordercolor") | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `drop_color` | option_defs.c:1016 | (d5,89,9d,0.5f) | Sources/Mango/Config/ConfigOptions.swift:214 | RGBA(r: 0xd5 / 255.0, g: 0x89 / 255.0, b: 0x9d / 255.0, a: 0.5) | parse_color → color("dropcolor") | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `split_color` | option_defs.c:1027 | (eb,44,1e,1.0f) | Sources/Mango/Config/ConfigOptions.swift:215 | parseColor("0xeb441eff")! | parse_color → color("splitcolor") | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `focus_color` | option_defs.c:1038 | (c6,6b,25,1.0f) | Sources/Mango/Config/ConfigOptions.swift:208 | parseColor("0xc66b25ff")! | parse_color → color("focuscolor") | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `maximized_screen_color` | option_defs.c:1049 | (89,aa,61,1.0f) | Sources/Mango/Config/ConfigOptions.swift:210 | parseColor("0x89aa61ff")! | parse_color → color("maximizescreencolor") | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `urgent_color` | option_defs.c:1061 | (ad,40,1f,1.0f) | Sources/Mango/Config/ConfigOptions.swift:209 | parseColor("0xad401fff")! | parse_color → color("urgentcolor") | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `scratchpad_color` | option_defs.c:1072 | (51,6c,93,1.0f) | Sources/Mango/Config/ConfigOptions.swift:211 | parseColor("0x516c93ff")! | parse_color → color("scratchpadcolor") | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `global_color` | option_defs.c:1084 | (b1,53,a7,1.0f) | Sources/Mango/Config/ConfigOptions.swift:212 | parseColor("0xb153a7ff")! | parse_color → color("globalcolor") | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `overlay_color` | option_defs.c:1095 | (14,a5,7c,1.0f) | Sources/Mango/Config/ConfigOptions.swift:213 | parseColor("0x14a57cff")! | parse_color → color("overlaycolor") | 1:1 | parse_color assumed 1:1 (value_parse.c, other group) |
| `monitor_rule` | option_defs.c:1106 | - | Sources/Mango/Config/ConfigOptions.swift:67 | - |  → see rule-field table | platform | listed (MangoCompat.ignoredKeywords); also mango's validation errors (no name/make/model/serial; width/height/refresh together; x/y together) are not reported |
| `tag_rule` | option_defs.c:1247 | - | Sources/Mango/Config/ConfigParser.swift:430 → RuleParser.swift:112 | - |  → see rule-field table | differs | field differences (no_hide/no_render_border/open_as_floating defaults). Via setoption (ConfigOptions.swift:44) ours drops a rule with any unknown field; mango keeps it |
| `layer_rule` | option_defs.c:1343 | - | Sources/Mango/Config/ConfigOptions.swift:67 | - |  → see rule-field table | platform | listed (MangoCompat.ignoredKeywords) |
| `window_rule` | option_defs.c:1412 | - | Sources/Mango/Config/ConfigParser.swift:421 → RuleParser.swift:22 | - |  → see rule-field table | differs | rule-level: kept with unknown fields (1:1), dropped on a bad global_key_binding (1:1); field differences D2, app_id/title empty. Via setoption (ConfigOptions.swift:39) ours drops a rule that has any unknown field; mango keeps it |
| `device_rule` | option_defs.c:1640 | - | Sources/Mango/Config/ConfigOptions.swift:67 | - |  → see rule-field table | platform | listed (MangoCompat.ignoredKeywords) |
| `env` | option_defs.c:1787 | - | Sources/Mango/Config/ConfigOptions.swift:19 | - |  → sscanf "%255[^,],%255[^\n]", trim, "~/"→$HOME/ | differs | mango matches any key starting "env" (strncmp 3): `envfoo=A,b` is an env in mango, unknown keyword in ours; ` ,x` (blank name) is accepted by mango (sscanf before trim) and rejected by ours. HOME unset: mango error, ours NSHomeDirectory (marked) |
| `var` | option_defs.c:1867 | - | Sources/Mango/Config/ConfigParser.swift:365 | - | strdup → strchr comma, trim, is_valid_var_name, set_config_var | 1:1 | only reachable from a file line in ours: `setoption,var,...` is "Unknown keyword" in ours (ConfigOptions.parseOption has no var), mango sets the variable |
| `exec` | option_defs.c:1891 | - | Sources/Mango/Config/ConfigOptions.swift:33 | - |  → append | 1:1 |  |
| `exec_once` | option_defs.c:1912 | - | Sources/Mango/Config/ConfigOptions.swift:36 | - |  → append; strncmp 9 prefix | 1:1 | `exec_onceX` is exec_once in mango (trivial) |
| `mousebind` | option_defs.c:2030 | - | Sources/Mango/Config/ConfigParser.swift:387 | - |  → sscanf ≥3 fields, parse_mod/parse_button/parse_func_name | 1:1 | keyword level only; field parsing (parse_mod, parse_button, parse_func_name) belongs to binding_parse.c's group. strncmp 9 prefix (`mousebindX`) not matched by ours (trivial) |
| `axisbind` | option_defs.c:2116 | - | Sources/Mango/Config/ConfigParser.swift:397 | - |  → sscanf ≥3 fields, parse_direction | 1:1 | keyword level only (see mousebind); strncmp 8 prefix |
| `switchbind` | option_defs.c:2195 | - | Sources/Mango/Config/ConfigParser.swift:417 | - |  → lid switch binding | platform | listed (MangoCompat.ignoredKeywords) |
| `gesturebind` | option_defs.c:2267 | - | Sources/Mango/Config/ConfigParser.swift:407 | - |  → sscanf ≥4 fields, fingers atoi | 1:1 | keyword level only; mango's "Unknown dispatch in axisbind" for gesturebind kept (1:1) |
| `source_optional` | option_defs.c:2354 | - | Sources/Mango/Config/ConfigParser.swift:379 | - |  → parse_config_file(value,false); strncmp 15 prefix | 1:1 | prefix: `source_optionalX` is source_optional in mango, unknown in ours (trivial). Not reachable via setoption in ours (mango: it is). Empty value: ours "Missing path for" (own message) |
| `source` | option_defs.c:2356 | - | Sources/Mango/Config/ConfigParser.swift:379 | - |  → parse_config_file(value,true); strncmp 6 prefix | 1:1 | as source_optional; recursion guard is §6 (listed §6) |
| `window_rule_once` | option_defs.c:1412 | - | Sources/Mango/Config/ConfigParser.swift:421 | - | same branch, `is_once=1` | 1:1 | see window-rule fields |
| `bind`, `binds`, `bindl`, `bindr`, `bindp`, `bindc`, combinations | option_defs.c:1933 (`regex_match("^bind[s\|l\|r\|p\|c]*$")`) | - | `BindingParser.isKeyBindKeyword` ConfigParser.swift:468 | - | sscanf ≥3 fields, parse_bind_flags/parse_key/parse_mod/parse_func_name | 1:1 | keyword level; field parsing belongs to binding_parse.c's group. Mango's character class also takes a literal `\|` (trivial). Ours drops a bind whose key has no macOS keycode silently (ConfigParser.swift:445; platform) |

## Window-rule fields (window_rule / window_rule_once)
| field (option_defs.c) | mango default / parse | ours (RuleParser.swift) | status | note |
|---|---|---|---|---|
| `is_floating` :1506 | -1 / atoi | :46 flag→Bool? | differs | D2 (negative = unset in mango, true in ours) |
| `title` :1508 | NULL / strdup | :45 nil if empty | differs | empty value: mango pattern "" matches every title (regex_match, client.c:1057); ours nil, and a rule with neither app_id nor title never matches (Rules.swift:139). `window_rule=is_floating:1,title:` floats every window in mango, none in ours |
| `app_id` :1510 | NULL / strdup | :44 nil if empty | differs | as title; also matches the app's name (listed §3) |
| `animation_type_open` :1512 | UNSET / animation_type_from_string | :77 | 1:1 | empty → unset both; unknown → slide (same result) |
| `animation_type_close` :1514 | UNSET | :78 | platform | listed MangoCompat.windowRuleFieldsWithoutEffect |
| `tags` :1517 | 0 / parse_tag_mask | :57 nil if 0 | 1:1 | mango applies only `if (r->tags)` |
| `monitor` :1519 | NULL / strdup | :60 MonitorSpec(mango:) | 1:1 | empty → nil; matching is another group's (unsure for `monitor:` empty) |
| `offset_x` / `offset_y` :1521/1523 | 0 / atoi | :63/64 | 1:1 | |
| `no_focus` :1525 | -1 / atoi | :81 | differs | D2 |
| `no_fade_in` / `no_fade_out` :1527/1529 | -1 | :72/73 | platform | listed |
| `no_force_center` :1531 | -1 | :65 | differs | D2 |
| `width` / `height` :1533/1535 | 0 / atof | :61/62 | 1:1 | |
| `no_border` :1537 | -1 | :67 | differs | D2 |
| `no_shadow` / `no_radius` :1539/1541 | -1 | :68/69 | platform | listed |
| `no_animation` :1543 | -1 | :71 | differs | D2 |
| `is_open_silent` / `is_tag_silent` :1545/1547 | -1 | :51/52 | differs | D2 |
| `is_named_scratchpad` :1549 | -1 | :53 | differs | D2 |
| `is_unmanaged_global` / `is_global` :1551/1553 | -1 | :54/49 | differs | D2 |
| `scroller_proportion_single` :1555 | 0 / atof | :80 | differs | ≤0 applied in ours (see APPLY_FLOAT_PROP) |
| `unfocused_opacity` / `focused_opacity` :1557/1559 | 0 | :75/74 | platform | listed |
| `is_overlay` :1561 | -1 | :50 | differs | D2 |
| `shield_when_capture`, `allow_shortcuts_inhibit`, `idle_inhibit_when_focus`, `vrr_only_fullscreen`, `force_render`, `activation_bypass`, `force_fake_maximize`, `force_tearing` :1563-1589 | -1 | accepted by port (MangoCompat.ignoredWindowRuleFields) | platform | listed, 8 fields |
| `ignore_maximize` :1567 | -1 | :83 | platform | listed |
| `ignore_minimize` :1569 | -1 | :84 | differs | D2 |
| `no_size_hint` :1571 | -1 | :66 | platform | listed |
| `is_term` / `allow_csd` / `no_swallow` / `force_tiled_state` :1581/1583/1591/1587 | -1 | :55/76/56/85 | platform | listed |
| `confine_pointer` :1593 | -1 | :82 | differs | D2 |
| `no_blur` :1595 | -1 | :70 | platform | listed |
| `scroller_proportion` :1597 | 0 / atof | :79 | differs | ≤0 applied in ours (APPLY_FLOAT_PROP row) |
| `is_fullscreen` / `is_fake_fullscreen` :1599/1601 | -1 | :47/48 | differs | D2 |
| `global_key_binding` :1603 | {0} / sscanf "%255[^-]-%255s", parse_mod, parse_key; error → rule dropped | :86 | 1:1 | dropped on error (keep=false) as mango; mango stops at that token, ours goes on and also reports later unknown fields (message only); `%255s` stops at a space, ours takes the rest (edge) |
| unknown field | error, rule kept (count++) | :103 | 1:1 | kept in file parsing (ConfigParser.swift:423); dropped via setoption (ConfigOptions.swift:40) |
| token without ':' | skipped | `tokens` :156 | 1:1 | |
| `window_rule_once` | `is_once=1` | :25 `once` | 1:1 | |

## Tag-rule fields (tag_rule)
| field (option_defs.c) | mango default / parse | ours (RuleParser.swift) | status | note |
|---|---|---|---|---|
| `id` :1290 | 0 / `*`→wildcard, CLAMP 0..31 | :123 (nil = wildcard) | 1:1 | |
| `layout_name` :1298 | NULL / strdup | :127 | 1:1 | |
| `monitor_name` / `monitor_make` / `monitor_model` / `monitor_serial` :1300-1306 | NULL / strdup | :129-132 | 1:1 | make is PNP id (listed §3) |
| `no_render_border` :1308 | 0 / CLAMP 0..1 | :133 Bool? | differs | D4: mango's default 0 is applied by every matching rule (`>= 0`, reapply.c:457), ours nil skips: `tag_rule=id:2,no_render_border:1` then `tag_rule=id:2,layout_name:scroller` → mango 0, ours 1. Also D1 (negative → 0 vs true) |
| `open_as_floating` :1310 | 0 / CLAMP 0..1 | :135 | differs | D4 |
| `no_hide` :1312 | 0 / CLAMP 0..1 | :137 | differs | D4 |
| `master_count` :1314 | 0 / CLAMP 1..99 | :139 | 1:1 | applied if ≥1 (always after clamp) |
| `master_factor` :1316 | 0 / CLAMP 0.1..0.9 | :141 | 1:1 | |
| `scroller_default_proportion` / `_single` :1318/1321 | 0 / CLAMP 0..1, applied only if >0 | :143/145, applied always | differs | `…proportion:0` is "unset" in mango (reapply.c:461), ours sets 0 |
| `scroller_ignore_proportion_single` :1325 | -1 / CLAMP 0..1 | :147 | differs | D1 only (negative → 0 vs true) |
| unknown field | error, rule kept | :150, kept (ConfigParser.swift:432) | 1:1 | dropped via setoption (ConfigOptions.swift:45) |

## Monitor, layer and device rules
| rule | fields (option_defs.c) | ours | status | note |
|---|---|---|---|---|
| `monitor_rule` :1106 | name, make, model, serial, rr, scale, x, y, width, height, refresh, vrr, hdr, hdr_min_lum, hdr_max_lum, hdr_max_avg_lum, hdr_force, icc, disable, primary, custom (21) | ignored (ConfigOptions.swift:67) | platform | listed MangoCompat.ignoredKeywords; `primary` only picks the Xwayland primary output (xwayland_primary.c:280) |
| `layer_rule` :1343 | layer_name, animation_type_open, animation_type_close, shield_when_capture, no_blur, no_animation, no_shadow (7) | ignored | platform | listed |
| `device_rule` :1640 | name, type, repeat_rate, repeat_delay, kb_rules, kb_model, kb_layout, kb_variant, kb_options, natural_scrolling, accel_profile, accel_speed, left_handed, middle_button_emulation, scroll_method, scroll_button, click_method, send_events_mode, tap_to_click, tap_and_drag, drag_lock, button_map, disable_while_typing, monitor, map_focus_monitor (25) | ignored | platform | listed |

## Not in mango (in the Swift files looked at)
| ours (file:line) | marked? | note |
|---|---|---|
| `OptionResult` Sources/Mango/Config/ConfigOptions.swift:3 | partly (`.ignored` :5) | replaces parse_option's bool; `.ignored`/`.unknown`/`.invalid` |
| `ConfigOptions.knownKeys` ConfigOptions.swift:86 | no | helper |
| `ConfigOptions.isIgnored` :88, `hasSetter` :93, `setterKeys` :94 | yes | port's side |
| `Setter`, `setters`, `mangoSetters` :96-100 | via §5 ("parse_option som en tabel") | the strcmp chain as a table |
| `bool`/`int`/`double`/`color`/`decorate`/`optionalColor`/`optionalInt`/`curve`/`animation` :268-348 | yes (:267, one mark) | table entries; `bool` is where D1 comes from |
| `homeDirectory` :351 | yes | HOME with NSHomeDirectory fallback |
| `ValueParse` (`int`, `atoi`, `double`, `atof`, `scanDouble`, `bool`) :357-391 | no | libc stand-ins (atoi, atof, sscanf %f). `atof` has no hex/inf/nan and gives 0 for overflow (C: HUGE_VAL) |
| `RuleParser.parseWindowRule`/`parseTagRule` RuleParser.swift:5,11 | yes (:4) | strict variants used by setoption; they drop the rule on any error (mango keeps it) |
| `parseWindowRuleLenient`/`parseWindowRuleChecked`/`parseTagRuleLenient`/`tokens` RuleParser.swift:17,22,112,156 | no (under :4's mark at best) | branches of parse_option; `tokens` is strtok+strchr+trim |
| `ConfigError` ConfigParser.swift:6, `mangoHighlight` :38 | yes | |
| `ParsedConfig` :48 | partly (`notes`) | return value of the parse for `mango -p` and tests |
| `ConfigParser.parse(text:…)` :88 | yes | |
| `ParserState.note`/`noteDispatch` :256/261 | yes | port notes |
| `ParserState.recordConfigLineError` :265 | no | stands for mango_error + report_config_line_error |
| doc comment `/// Not in mango: file:line text for conflict messages.` ConfigParser.swift:463 | – | dangling, no declaration follows (stale) |
| `BindingParser` :466, `splitFields` :603 | yes | |
| `Config.port` Config.swift:149, `xkbRulesOptions` :145 | yes | |
| `DecorateStyle` optional fields Decorate.swift:3-13 | no | mango's DecorateDrawData has concrete values; nil = "not set by the user" exists for `chutney_macos_appearance` (a port extension's need shaping a core type); same result with the extension off |
| `DecorateStyle.mangoGroupBar/mangoTabBar/mangoTitleMessageBar/mangoJumpLabel` Decorate.swift:31-47 | no | mango's set_value_default values (+ text-node.c font fallbacks) |
| `DecorateStyle.setValueDefault(from:)` Decorate.swift:49 | no | uses mango's name `set_value_default` for a nil-merge (name clash with the mango function it is not) |
| `MangoCompat` `let corners` MangoCompat.swift:93 | – | port; declared, never used |

## Summary

Counts (keys 259 + window-rule fields 49 + tag-rule fields 14 + monitor/layer/device fields 53 + functions/types/shipped 25 = 400):

| status | keys | window-rule | tag-rule | other rules | functions/types | total |
|---|---|---|---|---|---|---|
| 1:1 | 114 | 8 | 8 | 0 | 14 | 144 |
| differs | 55 (46 only D1) | 19 (15 only D2) | 6 | 0 | 5 | 85 |
| missing | 2 | 0 | 0 | 0 | 0 | 2 |
| platform | 87 (all listed MangoCompat) | 22 (listed) | 0 | 53 (listed) | 5 | 167 |
| port | 1 | 0 | 0 | 0 | 1 | 2 |

No key is unknown to us; no default value differs from mango's (every set_value_default value checked, the decorate
defaults via DecorateStyle.mango*). `name` tags: set_value_default (no function; its name reused by
DecorateStyle.setValueDefault), ConfigWinRule→WindowRule, ConfigTagRule→TagRule, ConfigEnv/ConfigVar, VERTICAL/HORIZONTAL
and tag_num_MAX as literals.

Most significant deviations, most significant first:
1. **animation_duration_focus / animation_curve_focus: missing.** Mango's focus animation also cross-fades the border
   colour (animation/client.c:1682-1724); the port draws the borders and could. Both keys are stored and read nowhere;
   MangoCompat lists them as opacity ("SIP off"), which is only half true. Default 0, so plain mango matches.
2. **D4 tag-rule no_hide / no_render_border / open_as_floating.** Mango's 0 default is applied by every matching
   rule; ours nil. Two rules on the same tag (or `id:*` plus a specific one) give different no_hide/no_render_border/
   open_as_floating. Also `scroller_default_proportion(_single):0` is "unset" in mango, applied as 0 in ours.
3. **window_rule app_id/title empty.** `app_id:` or `title:` with no value is a match-everything pattern in mango and
   "no criterion" in ours: `window_rule=is_floating:1,app_id:` floats every window in mango, none in ours.
4. **APPLY_FLOAT_PROP: window-rule scroller_proportion(_single) ≤ 0** are applied in ours (MangoServer.swift:960-961),
   skipped in mango: `scroller_proportion:0` gives a 0 proportion instead of the default.
5. **setoption path** (Dispatch.swift:443 → ConfigOptions.parseOption): no `var`, `source`, `source_optional`
   ("Unknown keyword" in ours, executed by mango's setoption), and a window_rule/tag_rule with an unknown field is
   dropped where mango keeps it.
6. **D1 int-as-bool keys (46 keys)**: a negative value is OFF in mango (CLAMP 0..1), ON in ours. Edge input, but every
   bool key of the core is affected; one fix in `ValueParse.bool`/`ConfigOptions.bool` would cover them (clamped keys
   only; monocle_tab_mode, deck_tab_mode, tag_carousel stay `!= 0`).
7. **D2 window-rule int fields (15 fields)**: negative = unset in mango, `true` in ours (`is_floating:-1` floats).
8. **scroller_proportion_preset / circle_layout error paths**: mango empties the list on a bad value (`0.5,x`, empty
   token, trailing comma); ours keeps the previous preset, and for circle_layout accepts the non-empty tokens without
   error. With mango's shipped `scroller_proportion_preset=0.5,0.8,1.0` followed by a bad user line, mango ends with no
   preset, ours with mango's.
9. **key_mode empty**: `key_mode=""`/`key_mode= ` puts later binds in mode "" in mango (unreachable), in "default" in
   ours; mango also truncates mode names to 27 characters.
10. **D3 curves** (animation_curve_move/open/tag): a bad value partly overwrites (zeroes) the curve in mango, leaves it
    in ours. Plus minor: `env*` prefix keys and other strncmp-prefix keywords (`sourceX`, `mousebindX`, …) are exact
    names in ours; the shipped config.conf drops mango's `viewtoleft`/`viewtoright` binds without saying so in its
    marked region.

Notes for other groups: our `parseTagrule` (Client.swift:238) never resets no_hide/no_render_border/open_as_floating
(neither does mango's tag_slot_set_defaults; D4 is the only difference); parse_color/parse_double_array/
animation_type_from_string/sanitize_string (value_parse.c) and parse_mod/parse_key/parse_func_name (binding_parse.c)
were assumed 1:1 here.
