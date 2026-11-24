# Verificeret mod mango

Hvilke af mangos filer vi har sammenlignet med vores og fundet 1:1. Reference: mango 0.18.5,
commit 21f80a9 (`~/sources/mango`). Én række pr. `.c`-fil i mangos `src/`, `mmsg/` og
`mangonag/`; en header hører til sin `.c`-fil (`client.h` til `client.c`), som dens typer står i
vores tilsvarende fil.

En fil er `1:1`, når hver af mangos funktioner i den findes hos os under mangos navn
(lowerCamelCase), eller står under "Ikke her" med hvor den er, eller hvorfor den mangler.

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
| `mangonag/mangonag.c` | `mangonag/mangonag.swift` | ikke verificeret | | | | |
| `mmsg/mmsg.c` | `mmsg/main.swift`, `mmsg/log.swift` | ikke verificeret | | | | portens kommandoer i `Sources/Port/mmsg` |
| `src/animation/client.c` | `animation/animation-client.swift` | ikke verificeret | | | | |
| `src/animation/common.c` | `animation/animation-common.swift` | 1:1 | 3915a6b, 24. nov. | `fa80428b6c2d` | `handle_snapshot_meta_destroy`, `scene_node_snapshot`, `wlr_scene_tree_snapshot`, `snapshot_dest_to_source`, `scene_snapshot_enable_buffers`, `scene_snapshot_clip_buffer`, `scene_snapshot_clip_to_box` (lukke-animationens scene-snapshot, ingen macOS-del, §3) | kurverne bages som mango (rettet 24. nov.); ingen fade-kurver |
| `src/animation/layer.c` | | ingen macOS-del | | | | layer shell |
| `src/animation/tag.c` | `animation/animation-tag.swift` | 1:1 | ae2a891, 24. nov. | `2148fc6236c2` | | `prevtag` 0, `c->mon`-værn, `ov_card_tree`: §5 |
| `src/common/log.c` | `common/Log.swift` | 1:1 | fff28a6, 24. nov. | `38d0f49ac028` | `mango_error_impl` (`mangoError`, makroen `mango_error` og dens impl i én) | ingen buffer på 4096 bytes |
| `src/common/scene_node.c` | | porten | | | | scenen; `surfaceAt`, `sceneNodeSetEnabled` |
| `src/common/server.c` | `common/server.swift` | 1:1 | fff28a6, 24. nov. | `68e4580f4d32` | | kun startværdier; lytterne er portens, `child_pid` hører til `-s` (§4), `allow_frame_scheduling` til `main.c`; `server.h`'s struct står her |
| `src/common/util.c` | `common/util.swift` | 1:1 | de70e75, 24. nov. | `c73e42e65294` | `die`, `ecalloc`, `utf8_strlcpy`, `wayland_string_set`, `wl_list_append`, `timespec_to_ms`, `join_strings`, `join_strings_with_suffix`, `string_printf` (Swift har dem, §5), `fd_set_nonblock` (med `-s`, §4) | `wl_list`-hjælperne på klientlistens array; `regex_match` med ICU for PCRE2 |
| `src/config/binding_parse.c` | `config/binding_parse.swift` | ikke verificeret | | | | |
| `src/config/cleanup.c` | | ingen macOS-del | | | | frigørelse: Swift's ARC |
| `src/config/conflict_check.c` | `config/conflict_check.swift` | 1:1 | e8e3384, 24. nov. | `4de6c89f3d2f` | `get_mousebind_meta`, `get_axisbind_meta`, `get_switchbind_meta`, `get_gesturebind_meta` (bindingens `mode` og dens sted i `*Locs`), `mod_to_string` (død i mango, §4) | tasten er den første macOS-tastekode (§3) |
| `src/config/error_nag.c` | `config/error_nag.swift` | 1:1 | a70a15e, 24. nov. | `7067464f7031` | `nag_client_destroyed`, `nag_set_cloexec`, `nag_kill` (mangonag kører i mangos proces, porten står for den: `system.nagSpawn`/`nagKill`, §3), `nag_initial_cb` (ingen timer, §2) | |
| `src/config/error_store.c` | `config/error_store.swift` | 1:1 | ae2a891, 24. nov. | `e04f0ed36e35` | | |
| `src/config/load.c` | `config/load.swift` | 1:1 | a70a15e, 24. nov. | `3fed4484cc7a` | `resolve_keybinding_layout`, `resolve_bindings_to_configured_layouts` (tastekoderne læses med bindingen, §3), `set_default_key_bindings` (CHVT, ingen macOS-del), `config_current_file_index`, `config_file_path_at` (`BindingLocation`) | uden `SYSCONFDIR`; en kilde, der læser sig selv (§6); C's `isspace` i `detect_config_format` (rettet 24. nov.) |
| `src/config/option_defs.c` | `config/option_defs.swift`, `config/parse.swift` | ikke verificeret | | | | `parse.h`'s typer i `parse.swift` |
| `src/config/preset.c` | | ingen macOS-del | | | | kun data: `tags` til `ext-workspace.c`, `xkb_fallback_rules` til xkb's keymap |
| `src/config/reapply.c` | `config/reapply.swift` | ikke verificeret | | | | |
| `src/config/toml_parse.c` | `config/toml_parse.swift` | 1:1 | e8e3384, 24. nov. | `8bd2aaabb67e` | | to mango-fejl rettet (§6: escaped citationstegn i en liste, keymode efter en sprunget sektion); C's `isspace` og listens grænse på 4096 (rettet 24. nov.); C-buffere §5 |
| `src/config/value_parse.c` | `config/value_parse.swift` | 1:1 | fff28a6, 24. nov. | `9f43771bf126` | `starts_with_ignore_case` (død i mango, §4) | libc's `atoi`/`strtol`/`strtod` står her som `ValueParse`; `remove_comment` med C's `isspace` (rettet 24. nov.) |
| `src/config/variable_expand.c` | `config/variable_expand.swift` | 1:1 | fff28a6, 24. nov. | `6416bc924a82` | `var_buf_append` (Swifts strenge, §5) | `config.vars` er en tabel efter navn |
| `src/config/watcher.c` | `config/watcher.swift` | ikke verificeret | | | | |
| `src/dispatch/bind.c` | `dispatch/bind.swift` | ikke verificeret | | | | |
| `src/draw/dim-node.c` | | porten | | | | `showSpecialDim` |
| `src/draw/text-node.c` | `draw/text-node.swift` | ikke verificeret | | | | noderne er portens (`MangoBarDecoration`, `MangoJumpLabel`) |
| `src/draw/title_message_bar.c` | `draw/title_message_bar.swift` | 1:1 | fff28a6, 24. nov. | `3cd2bedc6f08` | | baren tegner porten; i overcircle under kortet (§5 Title message bar); `chutney_launch_or_focus` gennem `PortHooks` |
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
| `src/input/trackpad.c` | `input/trackpad.swift` | ikke verificeret | | | | |
| `src/ipc/ipc.c` | `ipc/ipc.swift` | ikke verificeret | | | | |
| `src/layout/arrange.c` | `layout/arrange.swift`, `layout/Layout.swift` | ikke verificeret | | | | |
| `src/layout/dwindle.c` | `layout/dwindle.swift` | 1:1 | de70e75, 24. nov. | `7c1bf821750a` | `dwindle_free_tree`, `cleanup_monitor_dwindle` (ARC, §5), `dwindle_predict` (§3) | markøren er portens (`system.pointer`) |
| `src/layout/horizontal.c` | `layout/horizontal.swift` | 1:1 | 1cceefb, 24. nov. | `08b9f6dfd68b` | `tile_predict`, `right_tile_predict`, `center_tile_predict`, `deck_predict`, `monocle_predict`, `grid_predict`, `fair_predict` (§3) | `layout.h`'s `LayoutContext` og `util.h`'s `MANGO_MIN`/`MANGO_MAX` står her; `m->w` som `int32_t` (`WBox`); ingen X11-popups |
| `src/layout/overview.c` | `layout/layout-overview.swift` | 1:1 | e8e3384, 24. nov. | `4782e020d705` | | kortene er portens (`ovCards`, `overviewLayoutCards`); klienterne tælles her, hvor mango læser `visible_clients`; ingen X11-popups |
| `src/layout/scroll.c` | `layout/scroll.swift` | ikke verificeret | | | | |
| `src/layout/vertical.c` | `layout/vertical.swift` | 1:1 | 1cceefb, 24. nov. | `87f2c8d9708c` | `vertical_tile_predict`, `vertical_deck_predict`, `vertical_grid_predict`, `vertical_fair_predict` (§3) | `vertical_grid_core` tæller som `grid_core` (§6); ingen X11-popups |
| `src/main.c` | `common/server.swift` | ikke verificeret | | | | `main` og `run` er appens (`Sources/MangoApp/main.swift`) |
| `src/manage/client.c` | `manage/client.swift` | ikke verificeret | | | | |
| `src/manage/layer.c` | | ingen macOS-del | | | | layer shell |
| `src/manage/misc.c` | `manage/misc.swift` | ikke verificeret | | | | |
| `src/manage/monitor.c` | `manage/monitor.swift` | ikke verificeret | | | | |
| `src/manage/tab.c` | `manage/tab.swift` | 1:1 | de70e75, 24. nov. | `7775e180ad64` | `tab_update_input_penetration`, `client_reparent_tab`, `client_add_tab_bar`, `client_remove_tab_bar`, `client_update_tab_bar_title`, `client_set_tab_bar_config`, `global_draw_tab_bar` (barens node er portens, §5 Faner) | `client_draw_tabbar` giver stripen til porten; delte `clipBar`/`barSegments` i `animation-client.swift` |
| `src/manage/xwayland_primary.c` | | ingen macOS-del | | | | Xwayland |
| `src/overview/overview.c` | `overview/overview.swift` | ikke verificeret | | | | |
| `src/switcher/switcher.c` | `switcher/switcher.swift` | 1:1 | 3915a6b, 24. nov. | `fc057d52e523` | `switcher_tile_layout`, `switcher_surface_finish`, `switcher_surface_update_buffer`, `handle_switcher_surface_commit`, `handle_switcher_surface_destroy`, `handle_switcher_surface_output_sample`, `handle_switcher_surface_frame_done`, `switcher_tile_add_surface` (flisernes scene-overflader er portens billeder, §3) | intet `client_send_frame_done`; ingen session-lås |
