# Verificeret mod mango

Hvilke af mangos filer vi har sammenlignet med vores og fundet 1:1. Reference: mango 0.18.5,
commit 21f80a9 (`~/sources/mango`). Én række pr. `.c`-fil i mangos `src/`, `mmsg/` og
`mangonag/`; en header hører til sin `.c`-fil (`client.h` til `client.c`), som dens typer står i
vores tilsvarende fil.

En fil er `1:1`, når hver af mangos funktioner i den findes hos os under mangos navn
(lowerCamelCase), eller står under "Ikke her" med hvor den er, eller hvorfor den mangler.

1:1 gælder funktionerne, givet de typer de bruger. Felterne i mangos structs (`Client`,
`Monitor`, `MangoServer`, config) verificeres med den header, de står i. Bruger en fil et felt i en
anden form end mangos, står det i rækkens note, til typen er rettet. Når en type rettes, ses de
berørte linjer i de verificerede filer igen, og deres fingeraftryk opdateres.

## Status

- **`1:1`**: hver funktion i mangos fil findes i vores med mangos navn og samme trin, i samme
  rækkefølge; hvert `not in mango` i vores fil står i `docs/afvigelser.md`; mangos opførsel er låst
  med tests, hvor det kan lade sig gøre.
- **`porten`**: mangos fil sidder på wlroots (scenen, inputenheder); hos os gør porten det bag
  grænsen (`Sources/Boundary`).
- **`ingen macOS-del`**: intet af filen findes på macOS (layer shell, Xwayland, touch, tablet,
  Wayland-protokoller), eller Swift gør det selv (`cleanup.c`'s frigørelse).
- **`ikke verificeret`**: endnu ikke sammenlignet funktion for funktion efter ombygningen.

**Fingeraftryk** er git's blob-hash (`git hash-object`) af vores fil(er), som de var, da filen blev
verificeret, de første 12 tegn, i samme rækkefølge som "Vores". Passer det ikke længere
(`git hash-object <fil> | cut -c1-12`), er filen ændret siden: verificér igen og skriv det nye
fingeraftryk og commit, eller sæt status tilbage.

**At verificere en fil:** læs mangos fil og vores side om side, funktion for funktion; ret, mærk
eller list hver forskel (CLAUDE.md regel 1); lås opførsel med tests; sæt status, commit (vores,
før verifikationens egen commit), dato og fingeraftryk (`git hash-object <fil> | cut -c1-12`).

## Filerne

| Mango | Vores | Status | Verificeret | Fingeraftryk | Ikke her | Note |
|---|---|---|---|---|---|---|
| `mangonag/mangonag.c` | `mangonag/mangonag.swift` | 1:1 | 30a9ebc, 24. nov. | `8c4d5d599976` | Wayland og tegning er portens (`NagDisplay`, `Port/macOS/Nag.swift`): `nag_output_*`, `nag_registry_*`, `nag_seat_*`, `nag_pointer_*`/`nag_keyboard_*` uden indhold, `nag_buffer_create`, `nag_create_shm_fd`, `handle_buffer_release`, `nag_setup_surface`, `nag_layer_configure`, `nag_layout`, `nag_layout_markup`, `nag_text_height`, `nag_compute_layout`, `nag_render`, `rgba_to_cairo`; `main`'s løkke og signaler | kører i mangos proces: stdin gives med (`nagStdin`), knappens fork er portens (`nagFork`), `getopt` startes forfra (`optreset`); pangos attributter samles i én `NagAttr` pr. stykke; macOS' `getopt` stopper ved første ikke-tilvalg, hvor glibc's flytter dem |
| `mmsg/mmsg.c` | `mmsg/main.swift`, `mmsg/log.swift` | ikke verificeret | | | | portens kommandoer i `Sources/Port/mmsg` |
| `src/animation/client.c` | `animation/animation-client.swift` | ikke verificeret | | | | |
| `src/animation/common.c` | `animation/animation-common.swift` | 1:1 | 3915a6b, 24. nov. | `fa80428b6c2d` | `handle_snapshot_meta_destroy`, `scene_node_snapshot`, `wlr_scene_tree_snapshot`, `snapshot_dest_to_source`, `scene_snapshot_enable_buffers`, `scene_snapshot_clip_buffer`, `scene_snapshot_clip_to_box` (lukke-animationens scene-snapshot, ingen macOS-del, §3) | kurverne bages som mango (rettet 24. nov.); ingen fade-kurver |
| `src/animation/layer.c` | | ingen macOS-del | | | | layer shell |
| `src/animation/tag.c` | `animation/animation-tag.swift` | 1:1 | ae2a891, 24. nov. | `2148fc6236c2` | | `prevtag` 0, `c->mon`-værn, `ov_card_tree`: §5 |
| `src/common/log.c` | `common/Log.swift` | 1:1 | fff28a6, 24. nov. | `38d0f49ac028` | `mango_error_impl` (`mangoError`, makroen `mango_error` og dens impl i én) | ingen buffer på 4096 bytes |
| `src/common/scene_node.c` | | porten | | | | scenen; `surfaceAt`, `sceneNodeSetEnabled` |
| `src/common/server.c` | `common/server.swift` | 1:1 | 529f98e, 24. nov. | `e0a4b7d233d1` | | kun startværdier; lytterne er portens, `child_pid` hører til `-s` (§4), `allow_frame_scheduling` til `main.c`; `server.h`'s struct står her; `struct MangoServer` (`server.h`) gennemgået 24. nov.: `server.h`'s rækkefølge, `focus_stack` er en liste af klienter (§5) |
| `src/common/util.c` | `common/util.swift` | 1:1 | de70e75, 24. nov. | `c73e42e65294` | `die`, `ecalloc`, `utf8_strlcpy`, `wayland_string_set`, `wl_list_append`, `timespec_to_ms`, `join_strings`, `join_strings_with_suffix`, `string_printf` (Swift har dem, §5), `fd_set_nonblock` (med `-s`, §4) | `wl_list`-hjælperne på klientlistens array; `regex_match` med ICU for PCRE2 |
| `src/config/binding_parse.c` | `config/binding_parse.swift` | 1:1 | 7dc0a33, 24. nov. | `fedd3dcef863` | `reference_keymap`, `cleanup_config_keymap`, `create_config_keymap`, `find_keycodes_in_layout`, `find_keycodes_for_keysym` (xkb's keymap er portens, §3) | `parse_func_name`'s 94 dispatchere i mangos rækkefølge; `parse_key` giver macOS-tastekoder (§3); portens modifier-navne gennem `ConfigPort` |
| `src/config/cleanup.c` | | ingen macOS-del | | | | frigørelse: Swift's ARC |
| `src/config/conflict_check.c` | `config/conflict_check.swift` | 1:1 | e8e3384, 24. nov. | `4de6c89f3d2f` | `get_mousebind_meta`, `get_axisbind_meta`, `get_switchbind_meta`, `get_gesturebind_meta` (bindingens `mode` og dens sted i `*Locs`), `mod_to_string` (død i mango, §4) | tasten er den første macOS-tastekode (§3) |
| `src/config/error_nag.c` | `config/error_nag.swift` | 1:1 | a70a15e, 24. nov. | `7067464f7031` | `nag_client_destroyed`, `nag_set_cloexec`, `nag_kill` (mangonag kører i mangos proces, porten står for den: `system.nagSpawn`/`nagKill`, §3), `nag_initial_cb` (ingen timer, §2) | |
| `src/config/error_store.c` | `config/error_store.swift` | 1:1 | ae2a891, 24. nov. | `e04f0ed36e35` | | |
| `src/config/load.c` | `config/load.swift` | 1:1 | a70a15e, 24. nov. | `3fed4484cc7a` | `resolve_keybinding_layout`, `resolve_bindings_to_configured_layouts` (tastekoderne læses med bindingen, §3), `set_default_key_bindings` (CHVT, ingen macOS-del), `config_current_file_index`, `config_file_path_at` (`BindingLocation`) | uden `SYSCONFDIR`; en kilde, der læser sig selv (§6); C's `isspace` i `detect_config_format` (rettet 24. nov.) |
| `src/config/option_defs.c` | `config/option_defs.swift`, `config/parse.swift` | ikke verificeret | | | | `parse.h`'s typer i `parse.swift`; `parse.h`'s structs gennemgået 24. nov.: reglerne med mangos navne og rækkefølge, `Config`'s `float`-felter som `Float` (§5) |
| `src/config/preset.c` | | ingen macOS-del | | | | kun data: `tags` til `ext-workspace.c`, `xkb_fallback_rules` til xkb's keymap |
| `src/config/reapply.c` | `config/reapply.swift` | 1:1 | 529f98e, 24. nov. | `9f01f1a07637` | `apply_explicit_xcursor_env`, `set_xcursor_env`, `reapply_rootbg`, `reapply_pointer`, `reset_blur_params`, `reapply_monitor_rules`, `reapply_keyboard` (ingen macOS-del, §5 reset_option) | `parse_tagrule`'s mfact kun på skærmens vinduer (§6); portens `configLoaded` gennem `PortHooks` |
| `src/config/toml_parse.c` | `config/toml_parse.swift` | 1:1 | e8e3384, 24. nov. | `8bd2aaabb67e` | | to mango-fejl rettet (§6: escaped citationstegn i en liste, keymode efter en sprunget sektion); C's `isspace` og listens grænse på 4096 (rettet 24. nov.); C-buffere §5 |
| `src/config/value_parse.c` | `config/value_parse.swift` | 1:1 | fff28a6, 24. nov. | `9f43771bf126` | `starts_with_ignore_case` (død i mango, §4) | libc's `atoi`/`strtol`/`strtod` står her som `ValueParse`; `remove_comment` med C's `isspace` (rettet 24. nov.) |
| `src/config/variable_expand.c` | `config/variable_expand.swift` | 1:1 | fff28a6, 24. nov. | `6416bc924a82` | `var_buf_append` (Swifts strenge, §5) | `config.vars` er en tabel efter navn |
| `src/config/watcher.c` | `config/watcher.swift` | 1:1 | 529f98e, 24. nov. | `0adc6f519b32` | `clear_dir_watches`, `dir_is_watched`, `add_dir_watch`, `find_dir_watch`, `event_matches`, `on_inotify_event` (mangos inotify-gren; macOS tager mangos kqueue-gren) | `read_symlink_target` med `readlink` (rettet 24. nov.); `chutney_menu_config` gennem `PortHooks` |
| `src/dispatch/bind.c` | `dispatch/bind.swift` | ikke verificeret | | | | |
| `src/draw/dim-node.c` | | porten | | | | `showSpecialDim` |
| `src/draw/text-node.c` | `draw/text-node.swift` | ikke verificeret | | | | noderne er portens (`MangoBarDecoration`, `MangoJumpLabel`) |
| `src/draw/title_message_bar.c` | `draw/title_message_bar.swift` | 1:1 | fff28a6, 24. nov. | `4c149b08b1af` | | baren tegner porten; i overcircle under kortet (§5 Title message bar); `chutney_launch_or_focus` gennem `PortHooks` |
| `src/ext-protocol/ext-workspace.c` | | ingen macOS-del | | | | Wayland-protokol |
| `src/ext-protocol/foreign-toplevel.c` | | ingen macOS-del | | | | Wayland-protokol |
| `src/ext-protocol/hdr.c` | `ext-protocol/hdr.swift` | ikke verificeret | | | | |
| `src/ext-protocol/tearing.c` | | ingen macOS-del | | | | Wayland-protokol |
| `src/ext-protocol/text-input.c` | | ingen macOS-del | | | | Wayland-protokol |
| `src/ext-protocol/xdg-activation.c` | | ingen macOS-del | | | | Wayland-protokol |
| `src/ext-protocol/xdg-output.c` | | ingen macOS-del | | | | Wayland-protokol |
| `src/input/device.c` | | porten | | | | inputenheder (`InputDevice`) |
| `src/input/keyboard.c` | `input/keyboard.swift` | ikke verificeret | | | | |
| `src/input/pointer.c` | `input/pointer.swift` | ikke verificeret | | | | |
| `src/input/switch.c` | | ingen macOS-del | | | | låg- og tablet-kontakter |
| `src/input/tablet.c` | | ingen macOS-del | | | | tablet |
| `src/input/touch.c` | | ingen macOS-del | | | | touch |
| `src/input/trackpad.c` | `input/trackpad.swift` | 1:1 | 3c5950b, 24. nov. | `dec31510a33f` | `pointer_is_trackpad`, `check_trackpad_disabled`, `trackpad_enabled` (`disable_trackpad` kan macOS ikke), `handle_cursor_pinch_*`, `handle_cursor_hold_*` (ingen pinch eller hold fra macOS) | dispatcheren findes efter navn (Swift sammenligner ikke funktioner); intet sendt videre til klienten (`wlr_pointer_gestures_v1`) |
| `src/ipc/ipc.c` | `ipc/ipc.swift` | 1:1 | 1c77ad5, 24. nov. | `8e6a37d354a8` | `layer_enum_str` (ingen layer shell), `ipc_notify_device_event` (§3) | kommandolinjen tolkes for sig (`IPCRequest`, `IPCWatch`); en uændret linje sendes ikke igen, og `printstatus` samles pr. omgang (§2); `get tag` læser det sidste felt som tag (skærmnavne med mellemrum); `cJSON` er `JSONValue` |
| `src/layout/arrange.c` | `layout/arrange.swift`, `layout/Layout.swift` | 1:1 | c3c5f5a, 24. nov. | `f2c76f6f1e1e`, `7089f1a14024` | `*_predict` i `layouts` (§3) | skrevet om efter mango: `resize_tile_master_horizontal`/`_vertical` hver for sig, mangos lister (`VISIBLEON`, `ISTILED`) i stedet for `tiledClients`, `drag_begin_cursor` som `int32_t`, `tag_gather_*` flyttet hertil fra `monitor.swift`; markøren er portens (`system.pointer`); `client_sync_layer` og rammerne er portens (`clientRaiseLayers`, `updateBorders`); gitter-trækkets nabo er §6 |
| `src/layout/dwindle.c` | `layout/dwindle.swift` | 1:1 | de70e75, 24. nov. | `25102b67b28f` | `dwindle_free_tree`, `cleanup_monitor_dwindle` (ARC, §5), `dwindle_predict` (§3) | markøren er portens (`system.pointer`) |
| `src/layout/horizontal.c` | `layout/horizontal.swift` | 1:1 | 1cceefb, 24. nov. | `8b8b24a53eee` | `tile_predict`, `right_tile_predict`, `center_tile_predict`, `deck_predict`, `monocle_predict`, `grid_predict`, `fair_predict` (§3) | `layout.h`'s `LayoutContext` og `util.h`'s `MANGO_MIN`/`MANGO_MAX` står her; `m->w` som `int32_t` (`WBox`); ingen X11-popups |
| `src/layout/overview.c` | `layout/layout-overview.swift` | 1:1 | e8e3384, 24. nov. | `4081f43eccb0` | | kortene er portens (`ovCards`, `overviewLayoutCards`); klienterne tælles her, hvor mango læser `visible_clients`; ingen X11-popups |
| `src/layout/scroll.c` | `layout/scroll.swift` | 1:1 | 35bc19c, 24. nov. | `9de7ac3e2246` | `scroller_predict`, `vertical_scroller_predict` (§3) | stakkenes hoveder samles i én hjælper (`scrollerHeads`); `scroller_swap_different_stacks` bytter klientlistens to løb i arrayet |
| `src/layout/vertical.c` | `layout/vertical.swift` | 1:1 | 1cceefb, 24. nov. | `eb2a7657d081` | `vertical_tile_predict`, `vertical_deck_predict`, `vertical_grid_predict`, `vertical_fair_predict` (§3) | `vertical_grid_core` tæller som `grid_core` (§6); ingen X11-popups |
| `src/main.c` | `common/server.swift` | ikke verificeret | | | | `main` og `run` er appens (`Sources/MangoApp/main.swift`) |
| `src/manage/client.c` | `manage/client.swift` | ikke verificeret | | | | `struct Client` (`client.h`) gennemgået 24. nov.: mangos rækkefølge, `grid_col_per`/`grid_row_per` og de gamle som `Float`, `grid_col_idx`/`grid_row_idx` som `Int32`; typerne og de manglende felter i `docs/afvigelser.md` §5 |
| `src/manage/layer.c` | | ingen macOS-del | | | | layer shell |
| `src/manage/misc.c` | `manage/misc.swift` | 1:1 | 3c5950b, 24. nov. | `1ea7d7915b2b` | alt undtagen `node_at_point`: Wayland-protokollerne (decoration, idle inhibit, session-lås, capture, selection, drm lease, `mango_global_filter`), `layer_ignores_focus` (ingen layer shell), `get_parent_process` og `is_descendant_process` (swallowing), `get_layout_abbr` (død i mango, §4) | `node_at_point` skrevet ud uden scene (§5 Hvad der er under markøren) |
| `src/manage/monitor.c` | `manage/monitor.swift` | 1:1 | aa90f9a, 24. nov. | `642ede87b3ab` | `special_sync_top_layer`, `blur_layer_on_wallpaper` (ingen layer shell eller blur); `device_target_monitor` (`device_rule` virker ikke på macOS); `monitor_matches_rule`, `apply_rule_to_state`, `get_nearest_output_mode`, `enable_adaptive_sync`, `disable_adaptive_sync`, `monitor_load_icc_transform`, `monitor_set_icc`, `handle_output_request_state`, `create_output`, `handle_output_manager_*`, `output_manager_apply_or_test`, `handle_output_power_manager_set_mode`, `check_vrr_enable` (macOS styrer skærmene); `mango_scene_output_commit`, `mango_output_commit`, `monitor_*skip_frame*`, `do_renderer_recreate`, `handle_renderer_lost` (ingen scene eller renderer) | `sel`/`prevsel` er `weak` `Client?`; `monitor_from_direction`, `monitor_at_point` og `get_monitor_nearest_to` regner wlroots' output-layout over skærmenes kasser (mærket); `oldmonname` er skærmens id; `match_monitor_spec` er flyttet hertil fra `parse.swift`; `handle_output_frame` går gennem `server.clients` (ikke de parkerede) |
| `src/manage/tab.c` | `manage/tab.swift` | 1:1 | de70e75, 24. nov. | `132f53027a74` | `tab_update_input_penetration`, `client_reparent_tab`, `client_add_tab_bar`, `client_remove_tab_bar`, `client_update_tab_bar_title`, `client_set_tab_bar_config`, `global_draw_tab_bar` (barens node er portens, §5 Faner) | `client_draw_tabbar` giver stripen til porten; delte `clipBar`/`barSegments` i `animation-client.swift` |
| `src/manage/xwayland_primary.c` | | ingen macOS-del | | | | Xwayland |
| `src/overview/overview.c` | `overview/overview.swift` | ikke verificeret | | | | |
| `src/switcher/switcher.c` | `switcher/switcher.swift` | 1:1 | 3915a6b, 24. nov. | `a3949f237edb` | `switcher_tile_layout`, `switcher_surface_finish`, `switcher_surface_update_buffer`, `handle_switcher_surface_commit`, `handle_switcher_surface_destroy`, `handle_switcher_surface_output_sample`, `handle_switcher_surface_frame_done`, `switcher_tile_add_surface` (flisernes scene-overflader er portens billeder, §3) | intet `client_send_frame_done`; ingen session-lås |
