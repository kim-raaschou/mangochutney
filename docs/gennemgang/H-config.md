# H-config: src/config/{binding_parse,toml_parse,reapply,watcher,load,error_nag,error_store,value_parse,cleanup,conflict_check,variable_expand}.c + include/mango/config/{error_nag,error_store,internal,watcher}.h

Conventions used below:
- C buffer limits (255-byte keys, 2 KB/4 KB/8 KB TOML buffers, 511-byte `fgets` lines, 27-char keymodes) are
  not reproduced in Swift. They are not counted as deviations; they only matter for absurd input.
- **Error-output convention (applies to every parse path):** mango prints all `mango_error`s of a failing
  line (e.g. bad modifier *and* bad key *and* unknown dispatcher) and then one `report_config_line_error`
  per failing line/statement. Ours stops at the first error of a binding line, and every recorded error
  (`recordConfigLineError`, ConfigParser.swift:265) prints its own `[Index]` report, re-reading the
  physical file line (mango prints the joined TOML statement or, for rule sections, the section name).
  Counted once, under `parse_conf_stream`.
- Paths: mango = `~/sources/mango/src/config/…`; ours relative to `Sources/`.

## Functions

### binding_parse.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| reference_keymap (binding_parse.c:22) | — | platform | xkb fallback keymap; the port's KeySyms table stands for it |
| cleanup_config_keymap (:31) | — | platform | xkb context/keymap freeing |
| create_config_keymap (:46) | — | platform | xkb context/keymap |
| parse_bind_flags (:60) | Mango/Config/ConfigParser.swift:473 `BindingParser.parseBindFlags(forKeyword:)` | 1:1 | Trivial edge: mango's keyword regex is `^bind[s\|l\|r\|p\|c]*$`, so `bind\|=` is a binding with "Unknown bind flag: \|"; ours "Unknown keyword" (`isKeyBindKeyword`, :468) |
| set_binding_keymode (:95) | ConfigParser.swift:388-412 (mode passed as `keyMode`) | 1:1 | iscommonmode/isdefaultmode derived from the mode string where used; same result |
| parse_mod (:110) | Mango/Model/Bindings.swift:13 `Modifiers.parse` | differs, name | Same tokens, `none`, code:133/134/37/105/50/62/64/108, unknown tokens ignored when one matched. Missing: mango's "unknown modifier keycode: code:N" error for a code that is not a modifier (Bindings.swift:33 silently ignores). Port names (`cmd`, `option`, …) marked, listed §2. Renamed without a `/// mango parse_mod` line |
| find_keycodes_in_layout (:219) | Port/macOS/MacWindowSystem.swift:319 | port | xkb keymap walk; the port's layout table |
| find_keycodes_for_keysym (:266) | Boundary/WindowSystem.swift:35, Port/macOS/MacWindowSystem.swift:319 | port | listed §5 (jump mode) |
| find_keycodes_for_char (:301) | Mango/Engine/OverviewMode.swift:349 | 1:1 | `/// mango find_keycodes_for_char` present |
| parse_key (:314) | Port/macOS/KeySyms.swift:7 via `ConfigParser.port?.keyCodes` (ConfigParser.swift:498) | port (differs, **unlisted**) | Key model on hold (memory "Keysym model on hold"), but not in afvigelser/compatibility: (1) `binds` (KEY_TYPE_SYM) has no effect besides the conflict check, every binding matches by keycode; (2) a keysym with no keycode in the layout (`unresolved`, matched by keysym in mango) — ours drops it; (3) `XF86*` names: ours returns success with no codes and the binding is silently dropped (ConfigParser.swift:445), mango binds them; (4) `code:N` is a macOS virtual key code (only docs/guide.md:125 says so), mango's is an xkb keycode — `bind=SUPER,code:38,…` is `a` in mango, `j` on macOS |
| parse_button (:370) | Mango/Model/Bindings.swift:185 `parseButton` | differs (minor) | Marked (`nil` for UINT32_MAX). `code:abc` → ours "Unknown button: …", mango "Invalid code format: …"; `code:-1` accepted by ours (`.code(-1)`), mango rejects. Evdev codes other than 272–279 become `.code(n)` and are compared with CG button numbers (`cgButtonNumber`), so `code:280` never fires; mango matches evdev 280 |
| parse_mouse_action (:425) | Mango/Engine/Dispatch.swift:383-385 (`a0 == "curresize" ? .resize : .move`) | differs | Mango lowercases and maps curmove/curresize/curnormal/curpressed, else 0; `pointer_begin_move_resize` refuses anything but CurMove/CurResize. Ours: case-sensitive, and any other argument (`CurResize`, `curnormal`, a typo, none) starts a **move**. Scenario: `mousebind=SUPER,btn_right,moveresize,CurResize` resizes in mango, moves in ours |
| combine_args_until_empty (:451) | Mango/Engine/Dispatch.swift:481 | 1:1 | |
| parse_func_name (:496) | ConfigParser.swift:563 `BindingParser.parseFuncName` (names) + Dispatch.swift (argument conversion at dispatch) | differs | Name set identical to mango's 94 (checked by diff; Bindings.swift:67). Arguments are kept as text and converted in `dispatch`; where that changes results: (a) `toggle_named_scratchpad`: mango `v3 = arg_value3`, a `%[^,]` field, so the command stops at its first comma; ours joins the rest (ConfigParser.swift:586, Dispatch.swift:337). (b) `spawn_on_empty`: mango `v = arg1`, `ui = parse_tag_mask(arg2)`; ours joins all but the last field as the command and takes the last as tags (ConfigParser.swift:582) — `spawn_on_empty,cmd a,b,3`: mango runs `cmd a` with tags of `b` (0), ours `cmd a,b` on tag 3. (c) `setoption` via a key binding: mango appends unfilled sscanf defaults, value = `"tile,0,0,0"`; ours `"tile"` (ConfigParser.swift:590, Dispatch.swift:443) — visible for string options, e.g. `setoption,circle_layout,tile` gives mango a circle of tile,0,0,0 (likely a mango bug; not agreed/listed). (d) numbers: mango `atoi`/`atof`, ours `Int()`/`Double()` (`incnmaster`/`incgaps` "1x" → mango 1, ours 0; `movewin`,`10px` → mango x=10, ours unchanged; `movewin,10.7` → mango 10, ours 10.7) (Dispatch.swift:85, 386, 357, 491). (e) `view_insert`: mango `strcmp(arg,"next")` case-sensitive, ours `NextPrev(mangoArg:)` lowercases. (f) `spawn` rest field: `spawn,a,b,c,d,e,0,f` → mango `a,b,c,d,e,0,f` (the 5th field holds the rest), ours stops at the `0` |

### toml_parse.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| remove_toml_comment (toml_parse.c:35) | Mango/Config/TOMLReader.swift:183 | 1:1 | |
| toml_scalar (:57) | TOMLReader.swift:202 `tomlScalar(_:mapBool:)` | 1:1 | |
| toml_value_to_string (:124) | TOMLReader.swift:202 (`mapBool: true`) | 1:1 | folded into tomlScalar |
| toml_value_as_string (:128) | TOMLReader.swift:202 (`mapBool: false`) | 1:1 | folded |
| toml_foreach_array_element (:132) | TOMLReader.swift:227 | differs | (1) Inside a `"…"` element mango copies `\` and the escaped char and then tests `*p == quote`, so `\"` **ends** the string (a mango bug; its own remove_toml_comment/toml_statement_complete skip escapes correctly). Ours keeps the quote open. `exec = ["notify-send \"a, b\""]`: mango splits at the comma and runs two broken commands, ours runs one correct one. Unmarked, not in §6. (2) Mango stops at the first element whose callback fails (`if (!fn(ctx, elem)) return false`); ours returns all elements and the callers apply every one (TOMLReader.swift:139-144, 156-160): `"SUPER+a" = ["spawn,x", "nosuchdispatch", "spawn,y"]` binds `spawn,y` in ours, not in mango |
| toml_apply_element (:195) | TOMLReader.swift:160 | 1:1 | (stop-on-failure is the foreach's, above) |
| toml_join_element (:205) | TOMLReader.swift:156-158 | 1:1 | |
| toml_key_joins_array (:222) | TOMLReader.swift:179 | 1:1 | |
| toml_apply_value (:228) | TOMLReader.swift:150 | 1:1 | |
| toml_is_rule_type (:258) | TOMLReader.swift:173 `tomlRuleTypes` | 1:1 | |
| toml_section_add (:266) | TOMLReader.swift:129-132 | 1:1 | |
| toml_bind_flag_char (:301) | TOMLReader.swift:177 `tomlBindFlags` | 1:1 | |
| toml_section_begin (:315) | TOMLReader.swift:64 | 1:1 | Cross-group note (parse_option, option_defs.c): mango matches `mousebind`/`axisbind`/`gesturebind`/`switchbind` with `strncmp`, so `[mousebind.default.lock]` (keyword `mousebindl`) works with the flag ignored; ours reports "Unknown keyword: mousebindl" (ConfigParser.swift:387 exact `case`) |
| toml_bind_element (:453) | TOMLReader.swift:139-144 | 1:1 | |
| toml_bind_prefix (:465) | TOMLReader.swift:285 | 1:1 | |
| toml_section_leaf (:510) | TOMLReader.swift:121 | 1:1 | |
| toml_section_flush (:562) | TOMLReader.swift:164 | differs | A bind section rejected in toml_section_begin (unknown flag, or no keymode) keeps `kind = BIND` with a zeroed `saved_keymode`; mango's flush then sets `config->keymode = ""`, so every binding parsed afterwards outside a bind section (rest of the file, later `source`d .conf files) gets mode `""` and never fires (a mango bug). Ours guards with `!section.skip` (:169) and keeps the keymode — an unmarked, unlisted fix. Report text for a failing rule section: mango prints the section name, ours the header line |
| toml_statement_complete (:588) | TOMLReader.swift:265 | 1:1 | |
| toml_process_statement (:623) | TOMLReader.swift:38 | 1:1 | report text: see error-output convention |
| parse_toml_stream (:693) | TOMLReader.swift:18 | 1:1 | |

### reapply.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| set_env_without_display (reapply.c:47) | Mango/Engine/MangoServer.swift:180 | 1:1 | |
| set_env_display (:56) | MangoServer.swift:189 | 1:1 | |
| run_exec (:64) | MangoServer.swift:195 | 1:1 | spawn_shell over the boundary |
| run_exec_once (:73) | MangoServer.swift:199 | 1:1 | |
| apply_explicit_xcursor_env (:82) | — | platform | xcursor env; cursor_theme/cursor_size in MangoCompat. Not marked where reapply_cursor_style omits it |
| set_xcursor_env (:92) | — | platform | same |
| reapply_rootbg (:110) | — | platform | listed §5; marked in resetOption |
| reapply_property (:114) | MangoServer.swift:203 | 1:1 | `bw` and `client_set_tab_bar_config` omitted, marked, listed §5. Iterates `clients` (group heads) where mango iterates all; `clientSetGroupConfig` walks the group from its head, same result. No `iskilling` skip (trivial) |
| reapply_pointer (:129) | MangoServer.swift:231 (`system.watchGestures`) | port | libinput; marked, listed §5 |
| reapply_tagrule (:145) | MangoServer.swift:212 | 1:1 | |
| reset_option (:155) | MangoServer.swift:218 | 1:1 | Steps in mango's order; omissions marked, listed §5; port hooks marked |
| reset_blur_params (:187) | — | platform | listed (MangoCompat), marked |
| reapply_monitor_rules (:217) | — | platform | listed, marked |
| reapply_cursor_style (:291) | MangoServer.swift:255 | port | xcursor manager omitted (marked); hide timer re-armed as mango does |
| reapply_keyboard (:330) | — | platform | listed §5, marked |
| reapply_master (:386) | MangoServer.swift:263 | 1:1 | |
| tag_slot_set_defaults (:410) | Mango/Engine/Client.swift:240-246 (inlined in parseTagrule) | 1:1 | Ours resets all 32 slots, mango 0…tag_num; unobservable (slots above tag_num cannot be viewed and are recomputed when tag_num grows). No own function |
| tag_rule_matches_monitor (:423) | Mango/Model/Rules.swift:161 | 1:1 | listed §3 (macOS names/PNP make) |
| tag_rule_apply_to_slot (:443) | Client.swift:247-258 (inlined) | differs (minor) | Mango applies scroller_default_proportion(_single) only if `> 0.0f`; the parser clamps to 0…1 in both, so `tag_rule=id:1,scroller_default_proportion:0` is ignored by mango and sets 0 in ours (Client.swift:253-254). A rule with `id` > tag_num is applied to its slot by ours, ignored by mango (unobservable until tag_num grows) |
| parse_tagrule (:472) | Client.swift:239 `Monitor.parseTagrule` | 1:1 | listed §6 (`c.mon === self`). ISTILED's `!iskilling` not checked (trivial) |
| reset_tag (:513) | MangoServer.swift:285 | 1:1 | `sync_workspaces_to_tag_num` (ext-workspace) omitted without a mark |
| reload_config (:542) | MangoServer.swift:276 | 1:1 | `update_seat_capabilities` and `apply_primary_selection` (Wayland seat/selection) omitted without a mark |

### watcher.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| schedule_check (watcher.c:50) | Mango/Config/Watcher.swift:85 | 1:1 | |
| refresh_file_state (:56) | Watcher.swift:17 | 1:1 | `st_mtimespec` |
| clear_watched_files (:83) | Watcher.swift:89 | 1:1 | |
| file_is_tracked (:94) | Watcher.swift:94 | 1:1 | (compares the unresolved path with resolved ones, as mango) |
| path_dirname (:102) | Watcher.swift:45 | 1:1 | |
| path_join (:119) | Watcher.swift:51 | 1:1 | |
| read_symlink_target (:136) | Watcher.swift:55 | 1:1 | Foundation's `destinationOfSymbolicLink`; on failure `errno` for the message may be stale (trivial) |
| resolve_watch_path (:165) | Watcher.swift:59 | 1:1 | |
| track_path (:218) | Watcher.swift:98 | 1:1 | |
| clear_dir_watches (:256) | — | platform | inotify (Linux); mango itself builds kqueue on Apple |
| dir_is_watched (:267) | — | platform | inotify |
| add_dir_watch (:275) | — | platform | inotify |
| find_dir_watch (:294) | — | platform | inotify |
| event_matches (:302) | — | platform | inotify |
| on_inotify_event (:329) | — | platform | inotify |
| backend_init, inotify (:358) | — | platform | inotify |
| backend_destroy, inotify (:374) | — | platform | inotify |
| backend_sync, inotify (:386) | — | platform | inotify |
| add_file_watch (:405) | Watcher.swift:107 | 1:1 | |
| on_kqueue_event (:422) | Watcher.swift:120 | 1:1 | |
| backend_init, kqueue (:444) | Watcher.swift:138 | 1:1 | `addFd` cannot fail (boundary EventLoop) |
| backend_destroy, kqueue (:460) | Watcher.swift:148 | 1:1 | |
| backend_sync, kqueue (:471) | Watcher.swift:159 | 1:1 | |
| backend_init/destroy/sync stubs (:481, :483, :485) | — | platform (×3) | no-backend build, not compiled on Apple |
| on_watch_timer (:489) | Watcher.swift:165 | 1:1 | `configWriteIsOwn` port hook marked, listed §1 |
| config_watcher_init (:503) | Watcher.swift:178 | 1:1 | timer creation cannot fail |
| config_watcher_update (:526) | Watcher.swift:192 | 1:1 | |
| config_watcher_destroy (:542) | Watcher.swift:202 | 1:1 | |

### load.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| parse_config_line (load.c:80) | ConfigParser.swift:333 `ParserState.parseConfigLine` | differs (minor) | Value length checked after trimming (mango: the raw text after `=`, so `key = <254 chars>␠␠` is an error in mango, accepted in ours). A key of only spaces (`␠=x`): mango "Unknown keyword: " , ours "Invalid line format". Otherwise same (remove_comment, sscanf requirements, trim, strip_quotes, expand) |
| parse_conf_stream (:110) | ConfigParser.swift:321 | differs (minor, error output) | See error-output convention (one `[Index]` per error, first error only per binding line). CRLF normalised (marked). Mango's 511-byte `fgets` splits a longer line into two numbered lines |
| detect_config_format (:130) | ConfigParser.swift:95 | 1:1 | `ConfigFileFormat` (internal.h) = `ConfigParser.Format` |
| resolve_config_path (:153) | ConfigParser.swift:271 | differs, listed §3 | Bare relative path read from the config dir (listed §3 "source= med relativ sti"); missing HOME falls back to NSHomeDirectory (marked, ConfigOptions.swift:351) |
| parse_config_file (:186) | ConfigParser.swift:284 | differs | (1) A missing `source=` file: mango prints "Failed to open config file: X" only (parse_option ignores the return), ours also prints an `[Index]` report for the `source=` line (`recordConfigLineError`, :306) — and the nag's Edit button then opens that line, where mango's opens the next reported error. (2) A directory is "Failed to open" in ours; mango's `fopen` of a directory succeeds and reads nothing. (3) Paths are `standardizedFileURL` and deduplicated in the file list (watcher/conflict text only). Recursion guard listed §6 |
| resolve_keybinding_layout (:228) | KeySyms.parseKey at parse time | port (unlisted) | Key names resolved with the current macOS input layout, not `xkb_rules_layout`; no "has no keycode … matched by keysym" message (see parse_key) |
| resolve_bindings_to_configured_layouts (:261) | — | port (unlisted) | same; also window rules' `globalkeybinding` |
| set_default_key_bindings (:296) | — | platform | the twelve ctrl+alt XF86Switch_VT_n → chvt bindings; `chvt` listed (MangoCompat) |
| parse_config (:327) | Engine/MangoServer.swift:166 + Config/ConfigParser.swift:76 | 1:1 | Split server side / parse (marked). Same steps and order (store_begin, reset, filename, defaults, parse_config_file, override_config, conflict checks, store_end, nag_update); no `/etc` fallback listed §3; no bool result (mango's is used by `mango -p`, ours counts `errors`) |
| config_get_file_paths (:439) | MangoServer.swift:176 | 1:1 | list deduplicated |
| config_current_file_index (:446) | ConfigParser.swift:171 `BindingLocation.file` | 1:1 | structure: the file string is kept per binding instead of an index |
| config_file_path_at (:448) | ConfigParser.swift:171 | 1:1 | same |

### error_nag.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| nag_client_destroyed (error_nag.c:22) | — | platform | wl_client listener |
| nag_set_cloexec (:31) | — | platform | socketpair for WAYLAND_SOCKET |
| nag_strip_ansi (:39) | Mango/Config/ErrorNag.swift:3 | 1:1 | Edge: a lone ESC not followed by `[` — mango keeps ESC and the next char, ours drops both; the store never contains one |
| nag_kill (:58) | WindowSystem.nagKill, Port/macOS/MacWindowSystem.swift:343 | port | listed §5 |
| nag_first_target (:68) | ErrorNag.swift:19 | 1:1 | |
| nag_shell_quote (:118) | ErrorNag.swift:50 | 1:1 | |
| nag_edit_command (:142) | ErrorNag.swift:54 | 1:1 | |
| nag_pipe_text (:211) | ErrorNag.swift:88 | 1:1 | (mango counts 1 KB fgets chunks; same for real lines) |
| nag_spawn (:248) | ErrorNag.swift:110 + MacWindowSystem.swift:339 | port | argv 1:1; fork/socket/exec is the port's (listed §3/§5); `started` for `server.display` marked |
| config_error_nag_update (:346) | ErrorNag.swift:126 | 1:1 | |
| nag_initial_cb (:364) | ErrorNag.swift:139 | differs, listed §2 | no 1 ms timer |
| config_error_nag_init (:373) | ErrorNag.swift:139 | differs, listed §2 | runs at once after setup |
| config_error_nag_destroy (:382) | ErrorNag.swift:143 | 1:1 | |

### error_store.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| store_dir_ok (error_store.c:17) | Mango/Config/ErrorStore.swift:7 | 1:1 | |
| store_dir_prepare (:31) | ErrorStore.swift:16 | 1:1 | |
| config_error_store_path (:39) | ErrorStore.swift:22 | 1:1 | |
| config_error_store_begin (:62) | ErrorStore.swift:40 | 1:1 | |
| config_error_store_end (:81) | ErrorStore.swift:56 | 1:1 | |
| config_error_store_active (:89) | ErrorStore.swift:64 | 1:1 | |
| config_error_store_record (:91) | ErrorStore.swift:66 | 1:1 | |

### value_parse.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| trim_whitespace (value_parse.c:17) | `trimmingCharacters(in: .whitespaces)` throughout | differs (trivial), name | C `isspace` trims `\r \v \f \n`, ours does not; ours trims Unicode spaces (NBSP) that C keeps. No own function |
| strip_quotes (:42) | ConfigParser.swift:128 | 1:1 | |
| remove_comment (:57) | ConfigParser.swift:109 | 1:1 | |
| parse_double_array (:80) | Mango/Model/Geometry.swift:126 (marked) | differs | Mango writes straight into the config array: it `memset`s it and fills it as it goes, so an invalid `animation_curve_*` (3 numbers, or a bad one) leaves a zeroed/partial curve, e.g. `animation_curve_open=0.46,1.0,0.29` → mango curve (0.46,1.0,0.29,0); ours keeps the previous curve (ConfigOptions.swift:333). Mango also prints "Invalid number in array: X" / "(must be non-negative)" before "Failed to parse …"; ours prints only the latter. `strtod` accepts `nan`, `inf`, hex floats; ours rejects them |
| sanitize_string (:119) | ConfigOptions.swift:160-163 (inlined, circle_layout) | 1:1 | layout names are ASCII; mango also strips non-ASCII bytes, ours only control chars |
| starts_with_ignore_case (:133) | — | missing | dead code in mango (no caller); nothing observable |
| report_config_line_error (:144) | ConfigParser.swift:41 | 1:1 | `/// mango` line present |
| convert_hex_to_rgba (:153) | Geometry.swift:116 (folded into parseColor) | 1:1 | |
| parse_num_type (:160) | Dispatch.swift:491 `relOrAbs` | 1:1 | marked; the number itself see parse_func_name (d) |
| animation_type_from_string (:171) | Mango/Model/Config.swift:209 | 1:1 | UNSET/UNKNOWN fold to `.slide`; empty handled by callers (RuleParser.swift:39); open animation treats UNSET/UNKNOWN as slide; close animations are not drawn (§3) — same result |
| parse_circle_direction (:185) | Mango/Model/Geometry.swift:26 `NextPrev(mangoArg:)` | 1:1, name | no `/// mango parse_circle_direction` line |
| parse_overcircle_direction (:204) | Mango/Engine/OverviewMode.swift:148-150 (inlined) | 1:1 | |
| parse_direction (:222) | Geometry.swift:9 `Direction(mangoName:)` + `isUndir` (ConfigParser.swift:535-536) | 1:1, name | ALLDIR = nil & !isUndir, marked; no `/// mango parse_direction` line |
| parse_monitor_arg (:248) | Dispatch.swift:1603 `parseMonitorArg` | 1:1 | also resolves the monitor (focus_monitor's lookup). Trivial: `alldir` is a direction in mango, a monitor name in ours |
| parse_color (:267) | Geometry.swift:116 `parseColor` (marked) | differs (minor) | `strtol` accepts a sign and rejects a bare `0x`: `0x` → mango error, ours transparent black; `+ff`/`-2` → mango 0xff / 0xfffffffe, ours error. Overflow clamping reproduced |
| parse_force (:276) | Dispatch.swift:250 (inlined) | 1:1 | |
| parse_fold_state (:296) | — | platform | switchbind (lid switch) listed |
| parse_tag_mask (:316) | Mango/Model/Rules.swift:12 `TagMask.parseTagMask` | 1:1 | |

### cleanup.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| free_circle_layout (cleanup.c:9) | — | platform | C memory; the Config value is replaced |
| free_baked_points (:25) | — | platform | C memory; baked points are the port animator's (§5) |
| free_config (:56) | — | platform | C memory; `ParserState` starts from `Config()` |

### conflict_check.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| compare_keybind_by_key_only (conflict_check.c:13) | ConfigParser.swift:220 (inlined) | 1:1 | mods, keysym flag, first keycode |
| same_key (:36) | ConfigParser.swift:220 | 1:1 | |
| same_mousebind_key (:40) | ConfigParser.swift:229 | 1:1 | |
| same_axisbind_key (:46) | ConfigParser.swift:234-241 `sameDir` | 1:1 | marked |
| same_switchbind_key (:53) | — | platform | switchbind listed |
| same_gesturebind_key (:59) | ConfigParser.swift:248 | 1:1 | |
| get_mousebind_meta (:67) | ConfigParser.swift:191 `mouseLocs` | 1:1 | |
| get_axisbind_meta (:75) | ConfigParser.swift:192 | 1:1 | |
| get_switchbind_meta (:83) | — | platform | switchbind |
| get_gesturebind_meta (:91) | ConfigParser.swift:193 | 1:1 | |
| check_mouse_binding_conflicts (:99) | ConfigParser.swift:226 | 1:1 | merged into checkKeyBindingConflicts (marked) |
| check_axis_binding_conflicts (:106) | ConfigParser.swift:237 | 1:1 | |
| check_switch_binding_conflicts (:112) | — | platform | switchbind |
| mod_to_string (:119) | — | missing | dead code in mango (no caller). `Modifiers.mangoDescription` (Bindings.swift:44) is not it (other format, port's use) |
| check_key_binding_conflicts (:140) | ConfigParser.swift:200 | differs (log order only) | Same pairs, mode and text. Mango sorts by (mod, type, keycode) and reports group by group; ours reports in file order of the later binding. Only the order of the INFO lines differs |
| check_simple_binding_conflicts (:206) | ConfigParser.swift:226-252 | differs (log order only) | mango orders by first binding, ours by second (`A1,B1,B2,A2` → mango A then B, ours B then A) |
| check_gesture_binding_conflicts (:247) | ConfigParser.swift:245 | 1:1 | |

### variable_expand.c

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| find_config_var (variable_expand.c:10) | `vars[name]` (ConfigParser.swift:182) | 1:1 | dictionary |
| is_valid_var_name (:20) | ConfigParser.swift:133 | 1:1 | |
| set_config_var (:32) | ConfigParser.swift:376 | 1:1 | |
| var_buf_append (:67) | — | platform | C buffer growth |
| expand_config_variables (:83) | ConfigParser.swift:140 | 1:1 | Trivial: mango does not expand names of 128+ chars |

Headers: error_nag.h, error_store.h, watcher.h declare the functions above; internal.h's `ConfigFileFormat`
is `ConfigParser.Format` (ConfigParser.swift:93), its prototypes are rows above or option_defs.c's.
load.c's `default_jump_labels` = Config.swift:114 `jumpLabels` (same string).

## Not in mango (in the Swift files looked at)

| ours (file:line) | marked? | note |
|---|---|---|
| ConfigParser.swift:3 `extension String: Error` | no | Swift glue for `Result<_, String>` |
| ConfigParser.swift:6 `ConfigError` (+ `emit`) | yes | errors kept for `mango -p` and tests; `emit` re-reads the file line for the report |
| ConfigParser.swift:38 `mangoHighlight` | yes | |
| ConfigParser.swift:48 `ParsedConfig` | partly (only `notes`) | parse result struct |
| ConfigParser.swift:64 `ConfigParser.defaultConfigURL` | no | parse_config's filename choice pulled out; no `/etc` (listed §3) |
| ConfigParser.swift:88 `ConfigParser.parse(text:…)` | yes | |
| ConfigParser.swift:171 `BindingLocation` | no | stands for `file_index` + `line_number` |
| ConfigParser.swift:176 `ParserState` | no | stands for the parse's globals (config, file_paths, current_file_index, config.vars) |
| ConfigParser.swift:256 `note`, :261 `noteDispatch` | yes | port notes for `mango -p` |
| ConfigParser.swift:265 `recordConfigLineError` | no | mango_error + report_config_line_error per error (source of the error-output difference) |
| ConfigParser.swift:359 `parseOption` (file variant) | yes | parse_option for a file line; its `"Missing path for source"` message (:381) is not mango's (mango: "Failed to open config file: " with an empty path) and is unmarked |
| ConfigParser.swift:463 `/// Not in mango: file:line text for conflict messages.` | — | orphan doc comment with no declaration after it (dead) |
| ConfigParser.swift:466-560 `BindingParser.isKeyBindKeyword`, `parseKeyBinding`, `parseMouseBinding`, `parseAxisBinding`, `parseGestureBinding` | yes (one line, :467, placed on `isKeyBindKeyword`) | parse_option's binding branches (option_defs.c group) |
| ConfigParser.swift:603 `splitFields` | yes | sscanf stand-in |
| Model/Bindings.swift:44 `Modifiers.mangoDescription` | no | in the core, used only by the port (Port/macOS/KeyboardOptions.swift:77-80) |
| Model/Bindings.swift:138 `MouseButton.cgButtonNumber` | no | macOS CG button numbering in the core (Pointer.swift:20, Input.swift:161) |
| Model/Bindings.swift:64 `Dispatch.arg`, :67 `knownNames` | yes | |
| Model/Bindings.swift:109 `KeyBindingFlags` | no | mango's five bools as an OptionSet (structure only) |
| Model/Geometry.swift:9 `Direction(mangoName:)`, :26 `NextPrev(mangoArg:)` | no | renamed parse_direction / parse_circle_direction without `/// mango` lines (rule 8) |
| Config/ConfigOptions.swift:357 `ValueParse` (`atoi`, `atof`, `scanDouble`, `int`, `double`, `bool`) | no | C library stand-ins. `int`/`double` never return nil, so every `else { errors.append(bad) }` in RuleParser (e.g. :30-36, :125-147) is dead |
| Engine/Dispatch.swift:476 `finiteDouble`, :491 `relOrAbs` | yes | |
| Engine/Client.swift:208 `Monitor.tagGatherResetSlot` | no | duplicates parseTagrule's per-slot body (tag_gather group) |
| Engine/MangoServer.swift:166 `parseConfig` (server side) | yes | |

## Summary

161 mango functions/variants: **1:1 100**, **differs 18** (3 of them listed: resolve_config_path §3,
nag_initial_cb §2, config_error_nag_init §2), **missing 2** (both dead code in mango: starts_with_ignore_case,
mod_to_string), **port 9**, **platform 32**.

Most significant deviations, most significant first:
1. **parse_key / resolve_bindings_to_configured_layouts (port, unlisted):** `binds` has no effect (no keysym
   matching), unresolved keysyms and `XF86*` keys are silently dropped (no error), `code:N` is a macOS key
   code not an xkb one, names resolve with the current macOS layout not `xkb_rules_layout`. Paused by the
   user, but none of it is in afvigelser/compatibility.
2. **toml_foreach_array_element:** mango ends a quoted array element at an escaped `\"` (a mango bug); ours
   parses it correctly — an unmarked fix, not in §6, no test. Also mango stops an array at the first failing
   element; ours applies the rest.
3. **parse_mouse_action (moveresize):** ours starts a move for any argument other than exact `curresize`
   (`CurResize`, `curnormal`, typos); mango is case-insensitive and does nothing for non-modes.
4. **parse_func_name, toggle_named_scratchpad / spawn_on_empty:** commands with commas — mango truncates at
   the first comma (spawn_on_empty: tags from the 2nd field); ours keeps the whole command.
5. **parse_func_name, setoption from a key binding:** mango passes `value,0,0,0` (unfilled sscanf defaults,
   likely a mango bug); ours passes `value`. Visible for string options (`circle_layout`).
6. **parse_double_array:** an invalid `animation_curve_*` leaves mango with a zeroed/partial curve and an
   extra "Invalid number in array" message; ours keeps the previous curve.
7. **toml_section_flush:** after a rejected `[bind.…]` section mango sets the parse keymode to `""` (later
   bindings dead); ours keeps it — an unmarked fix of a mango bug.
8. **parse_config_file:** a missing `source=` file gets an extra `[Index]` report in ours (and the nag's Edit
   button points at the `source=` line); mango prints only "Failed to open config file".
9. **Error output in general (parse_conf_stream & co.):** mango prints every error of a line and one report
   per line/statement; ours the first error of a binding line and one report per error.
10. **parse_func_name numbers / tag_rule_apply_to_slot:** `atoi`/`atof` vs `Int()`/`Double()` (`movewin,10px`,
    `incnmaster,1x`, `movewin,10.7`); `tag_rule … scroller_default_proportion:0` applied by ours, ignored by
    mango.

Also unmarked omissions (platform, but no `not in mango` line): `update_seat_capabilities` and
`apply_primary_selection` in reload_config, `sync_workspaces_to_tag_num` in reset_tag,
`apply_explicit_xcursor_env`/`set_xcursor_env`. Cross-group (option_defs.c): `[mousebind.<mode>.<flag>]`
in TOML (and any `mousebindX=` key) is "Unknown keyword" in ours, accepted by mango's `strncmp`.
