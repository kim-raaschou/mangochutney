# H-config verified: src/config/*.c (binding_parse, toml_parse, reapply, load, value_parse, conflict_check, …)

Paths: mango = `~/sources/mango/src/config/…`; ours relative to `Sources/`.
Every `differs`, `missing` and `port (unlisted)` row of H-config.md re-read on both sides.

## Findings

| finding (short) | mango file:line | ours file:line | verdict | kind | size | note |
|---|---|---|---|---|---|---|
| parse_mod: no "unknown modifier keycode" error; renamed | binding_parse.c:110-217 (:166-170) | Mango/Model/Bindings.swift:13-41 (:33 `default: break`) | CONFIRMED | edge + name | S | `bind=code:999+SUPER,…`: mango logs "unknown modifier keycode: code:999", ours silent; binding the same. `Modifiers.parse` has no `/// mango parse_mod` line |
| parse_key: key model (port, unlisted) | binding_parse.c:314-368; load.c:228-258 | Port/macOS/KeySyms.swift:7-35; Mango/Config/ConfigParser.swift:497-500, :443-450 | PARTLY | behaviour | M | (1) CONFIRMED: `.keysym` (binds) is only read by the conflict check (ConfigParser.swift:217-220); matching is by key code. (2) CONFIRMED: a valid keysym with no key in the layout is "Unknown key" (non-XF86) or dropped, where mango keeps it `unresolved` and matches by keysym. (3) PARTLY: common XF86 names are mapped (KeySyms.swift:74-90: volume, brightness, mute, media, eject, …); only XF86 names outside that table give success with no codes and are dropped silently (ConfigParser.swift:498-500 lets an `xf86` name through with no codes, :445 `guard !b.keyCodes.isEmpty else { return }` drops it), mango binds them. (4) CONFIRMED: `code:N` is a macOS key code; said only in docs/guide.md:125. None of it in afvigelser/compatibility (memory: keysym model on hold) |
| parse_button: code: forms | binding_parse.c:370-423 | Bindings.swift:185-209; Engine/Pointer.swift:20; Engine/Input.swift:161 | CONFIRMED | edge | S | `code:abc` -> ours "Unknown button", mango "Invalid code format"; `code:-1` accepted by ours (`.code(-1)`), mango strtoul wraps > UINT32_MAX -> error; `code:280` -> `.code(280)` compared with CG button numbers (`cgButtonNumber`) never fires, mango matches evdev 280 |
| parse_mouse_action / moveresize | binding_parse.c:425-447; pointer.c:1004 | Engine/Dispatch.swift:383-385 | CONFIRMED | behaviour | S | `mousebind=SUPER,btn_right,moveresize,CurResize`: mango resizes, ours moves; any non-mode argument moves in ours, nothing in mango |
| parse_func_name argument conversion | binding_parse.c:496-893; option_defs.c:1950-1953 | ConfigParser.swift:563-600; Dispatch.swift | CONFIRMED | edge (c: mango-bug) | S each | (a) toggle_named_scratchpad: mango v3 = field 3 only; ours joins the rest. (b) spawn_on_empty: mango cmd = field 1, tags = parse(field 2); ours joins all but the last. (c) setoption from a bind: mango "tile,0,0,0", ours "tile" (unmarked, not §6). (d) atoi/atof vs Int()/Double(). (e) view_insert: mango `strcmp(arg,"next")` case-sensitive, ours NextPrev lowercases (`view_insert,Next`: mango PREV, ours next). (f) `spawn,a,b,c,d,e,0,f`: mango arg_value5 = "e,0,f" (`%[^\n]`), no lone "0" -> runs `a,b,c,d,e,0,f`; ours stops at the "0" (`prefix { $0 != "0" }`, :580) |
| toml_foreach_array_element: escaped quote; stop on failure | toml_parse.c:132-186 | Mango/Config/TOMLReader.swift:227-259, 139-160 | CONFIRMED | mango-bug + behaviour | S | (1) mango appends `\` and the escaped char, then `if (*p == quote)` closes the string on the escaped `"` (its remove_toml_comment/toml_statement_complete skip escapes properly). `exec = ["notify-send \"a, b\""]`: mango splits at the comma, ours one command. Our fix is unmarked, not in §6, no test. (2) mango returns at the first callback that fails (`if (!fn(ctx, elem)) return false`, :172); ours applies every element: `"SUPER+a" = ["spawn,x", "nosuchdispatch", "spawn,y"]` binds spawn,y in ours, not in mango |
| toml_section_flush after a rejected bind section | toml_parse.c:315-445 (memset :320, skip returns :410-427), :562-586 (:574-577) | TOMLReader.swift:164-171 (`!section.skip` :169) | CONFIRMED | mango-bug | S | an unknown flag or missing keymode leaves kind BIND with a zeroed saved_keymode; flush sets `config->keymode = ""`, so every later binding outside a bind section (rest of the file, later sourced files) has mode "" and never fires. Ours keeps the keymode: unmarked fix, not in §6. Rule-section report text: mango prints `section->name`, ours re-reads the header line (text only) |
| parse_config_line: value length, empty key | load.c:80-108 | ConfigParser.swift:333-351 | CONFIRMED | edge | S | mango checks `strcspn(equals+1)` on the raw text (`key = <254 chars>␠␠` is an error), ours after trimming; ` =x`: mango key " " -> "Unknown keyword: ", ours "Invalid line format" |
| parse_conf_stream / error output | load.c:110-128; option_defs.c:2019-2024 | ConfigParser.swift:265-269, 321-331, 486-499 | CONFIRMED | edge | M | mango prints parse_mod's, parse_key's and the "Unknown dispatch" error of one line and then one [Index]; ours stops at the first error of a binding line and every error gets its own [Index] (re-reading the line). 511-byte fgets split not reproduced (trivial) |
| resolve_config_path | load.c:153-184 | ConfigParser.swift:271-281 | CONFIRMED (listed §3) | behaviour | — | bare relative path from the config dir: afvigelser §3 l.96; HOME fallback marked |
| parse_config_file: missing source, directory | load.c:186-226; option_defs.c:2354-2357 (return ignored) | ConfigParser.swift:284-319 (:306) | CONFIRMED | edge | S | (1) a missing `source=` file: mango only "Failed to open config file: X" (parse_option returns true, no [Index]); ours also an [Index] report for the source line, so the nag's first target is that line. (2) a directory: mango's fopen succeeds and reads nothing (no error), ours "Failed to open". (3) standardised/deduplicated paths: text only |
| resolve_keybinding_layout (port, unlisted) | load.c:228-258 | KeySyms.parseKey at parse time | PARTLY | edge | S (list) | the layout being macOS's is listed (compatibility.md:28, `xkb_rules_layout` "layout … are macOS keyboard settings"); the unlisted part is the missing unresolved-keysym path and its "has no keycode … matched by keysym" message (see parse_key 2) |
| resolve_bindings_to_configured_layouts (port, unlisted) | load.c:261-294 | — | PARTLY | edge | S (list) | as above, incl. window rules' globalkeybinding; the "Invalid xkb_rules_* layout" fallback has no place on macOS (listed key) |
| tag_rule_apply_to_slot | reapply.c:443-470; option_defs.c:1262-1276 (defaults) | Engine/Client.swift:239-262 (parseTagrule), :208-230 (tagGatherResetSlot); Config/RuleParser.swift:112-151; Model/Rules.swift:143-157 | CONFIRMED (sharpened) | behaviour | S | (1) `scroller_default_proportion(_single):0`: mango `> 0.0f` ignores it, ours sets 0. (2) new: mango's rule defaults `no_render_border = open_as_floating = no_hide = 0` and applies them with `>= 0`, so every matching rule writes 0 for those it does not name; ours applies them only when set (`Bool?`). `tag_rule=id:3,no_hide:1` then `tag_rule=id:*,layout_name:tile`: mango tag 3 no_hide 0, ours 1 (looks like a mango bug: scroller_ignore_proportion_single defaults to -1 for exactly this). (3) a rule with `id > tag_num`: ours applies it to the slot, mango skips; unobservable (a tag_num change reloads and re-runs parse_tagrule) |
| nag_initial_cb: no 1 ms timer | error_nag.c:364-371 | Config/ErrorNag.swift:139 | CONFIRMED (listed §2) | edge | — | afvigelser §2 l.54 |
| config_error_nag_init | error_nag.c:373-380 | ErrorNag.swift:139 | CONFIRMED (listed §2) | edge | — | same |
| trim_whitespace | value_parse.c:17-39 | `trimmingCharacters(in: .whitespaces)` | CONFIRMED | edge | S | C isspace also trims \r \v \f \n; ours trims Unicode spaces C keeps. CRLF is normalised first, so practically invisible |
| parse_double_array: invalid curve | value_parse.c:80-115; option_defs.c:94-120 | Model/Geometry.swift:127-136; Config/ConfigOptions.swift:331-338 | CONFIRMED | behaviour | S | mango memsets and fills the config array in place: `animation_curve_open=0.46,1.0,0.29` leaves (0.46,1.0,0.29,0); ours keeps the default curve. Mango also prints "Invalid number in array[ (must be non-negative)]" before "Failed to parse"; strtod accepts nan/inf/hex, ours rejects |
| parse_color | value_parse.c:267-274 | Geometry.swift:116-124 | CONFIRMED | edge | S | `0x`: strtol leaves endptr at "x" -> -1 error; ours transparent black. `+ff` -> mango 0xff, ours error; `-2` -> mango 0xfffffffe (only -1 is the error value), ours error |
| check_key_binding_conflicts: report order | conflict_check.c:140-204 (qsort :159) | ConfigParser.swift:200-224 | CONFIRMED | edge | S | same pairs/mode/text; mango sorted by (mod, type, key) and grouped, ours by the later binding in file order. Log order only |
| check_simple_binding_conflicts: report order | conflict_check.c:206-245 | ConfigParser.swift:226-252 | CONFIRMED | edge | S | mango outer loop on the first binding, ours on the second: A1,B1,B2,A2 -> mango A then B, ours B then A |
| starts_with_ignore_case | value_parse.c:133 | — | CONFIRMED | name | S | dead in mango (whole tree grep: definition only, not in a header) |
| mod_to_string | conflict_check.c:119 | — | CONFIRMED | name | S | dead in mango (definition only); Modifiers.mangoDescription is not it |

## Not in mango

| ours | claim | verdict | note |
|---|---|---|---|
| ConfigParser.swift:3 `extension String: Error` | unmarked | CONFIRMED | |
| ConfigParser.swift:6 ConfigError | marked | CONFIRMED | |
| ConfigParser.swift:38 mangoHighlight | marked | CONFIRMED | |
| ConfigParser.swift:48 ParsedConfig | partly marked | CONFIRMED | only `notes` |
| ConfigParser.swift:64 defaultConfigURL | unmarked | CONFIRMED | |
| ConfigParser.swift:88 parse(text:…) | marked | CONFIRMED | |
| ConfigParser.swift:171 BindingLocation | unmarked | CONFIRMED | |
| ConfigParser.swift:176 ParserState | unmarked | CONFIRMED | |
| ConfigParser.swift:256/261 note, noteDispatch | marked | CONFIRMED | |
| ConfigParser.swift:265 recordConfigLineError | unmarked | CONFIRMED | source of the error-output difference |
| ConfigParser.swift:359 parseOption, "Missing path for source" | message unmarked | CONFIRMED | mango `source=␠␠` -> "Failed to open config file: " with an empty path |
| ConfigParser.swift:463 orphan `/// Not in mango: file:line text…` | dead doc comment | CONFIRMED | followed by `}` |
| ConfigParser.swift:466-560 BindingParser | one mark on isKeyBindKeyword | CONFIRMED | |
| ConfigParser.swift:603 splitFields | marked | CONFIRMED | |
| Bindings.swift:44 Modifiers.mangoDescription | unmarked, port-only use | CONFIRMED | KeyboardOptions.swift:77-80 |
| Bindings.swift:138 MouseButton.cgButtonNumber | unmarked macOS numbering in core | CONFIRMED | |
| Bindings.swift:109 KeyBindingFlags | unmarked structure | CONFIRMED | |
| Geometry.swift:9/26 Direction(mangoName:), NextPrev(mangoArg:) | no `/// mango` lines | CONFIRMED | parse_direction / parse_circle_direction |
| ConfigOptions.swift:357 ValueParse; dead `else` in RuleParser | unmarked; int/double never nil | CONFIRMED | `static func int(_:) -> Int? { atoi(s) }` (:358), `double` (:375) |
| Engine/Client.swift:208 tagGatherResetSlot | "not in mango" | REFUTED | it is mango's tag_gather_reset_slot (layout/arrange.c:1268); the only point is that it repeats parseTagrule's per-slot body where mango calls tag_slot_set_defaults |
| Dispatch.swift:476/491 finiteDouble, relOrAbs | marked | CONFIRMED | |
| MangoServer.swift:166 parseConfig | marked | CONFIRMED | |
