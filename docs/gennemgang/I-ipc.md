# I-ipc: src/ipc/ipc.c, include/mango/ipc/ipc.h, src/ext-protocol/*, include/mango/ext-protocol/*, mmsg/mmsg.c, mangonag/

Status 2026-11-20 (trin 10): hvert fund er mærket ✓ (rettet, som mango, listet, væk) eller åben, kontrolleret mod koden efter trin 9.

Ours: `Sources/Mango/IPC/IPCServer.swift` (IS), `Sources/Mango/IPC/IPCJSON.swift` (IJ), `Sources/Mango/Engine/MangoServer.swift` (MS),
`Sources/Mango/mmsg/main.swift`, `Sources/Mango/mmsg/log.swift`, `Sources/Mango/mangonag/mangonag.swift` (MN),
`Sources/Port/macOS/Nag.swift` (NAG), `Sources/Port/mmsg/*`, `Sources/Port/macOS/MacEvents.swift`.

## Functions

### src/ipc/ipc.c and include/mango/ipc/ipc.h

| mango (file:line) | ours (file:line) | status | note |
|---|---|---|---|
| ipc.h:10 `enum ipc_watch_type`, ipc.h:25 `IPC_WATCH_ARRANGGE` | IS:4 `IPCWatch.Kind` | differs ✓ rettet 15. nov. | The kinds exist; the bit mask that `printstatus(type)` carries does not (see printstatus). |
| ipc.h:30 `struct ipc_client_state`, :38 `struct ipc_watch_client` | IS:221 `IPCClientState`, IS:228 `IPCWatchClient` | 1:1 | Same fields, plus `lastPayload` (marked, §2). Mango's watch targets are `char[64]`, so a monitor name over 63 chars never matches in mango; ours matches it (edge). |
| ipc.c:34 `ipc_device_type_str` | none | platform, unlisted ✓ som mango nu (trin 9: `ipcDeviceTypeStr`, IPC/ipc.swift:261) | libinput device types. |
| ipc.c:63 `monitor_by_name` | IJ:255 `monitorByName` | 1:1 | Names are macOS display names, listed §3. |
| ipc.c:72 `client_by_id` | MS:47 `clientById` | 1:1 | `clients` holds no parked members, as `server.clients`. |
| ipc.c:81 static `client_by_id_all` | MS:48 `clientByIdAll` (`clientsAll`) | 1:1 | Same set: clients plus parked group members. |
| ipc.c:95 `ipc_get_layout_str` | MacWindowSystem.swift:366 `ipcGetLayoutStr` (WindowSystem) | port | xkb layout name becomes the macOS input source name. |
| ipc.c:109 `build_tags_json` | IJ:119 `buildTagsJson` | 1:1 | Fields in the same order: index, is_active, is_urgent, layout, client_count. |
| ipc.c:141 `monitor_active_client` | IJ:134 `monitorActiveClient` | 1:1 | id/title/appid, or three nulls. appid is the bundle id (listed §3). |
| ipc.c:156 `build_all_tags_entry` | inlined in IJ:144 | 1:1, name | Same result. No function of its own. |
| ipc.c:163 `build_all_tags_response` | IJ:144 `buildAllTagsResponse` | 1:1 | `{"all_tags":[{"monitor","tags"}]}`. |
| ipc.c:173 `build_monitor_tags_response` | IJ:150 `buildMonitorTagsResponse` | 1:1 | monitor, tags, active_tags. |
| ipc.c:181 `build_layouts_response` | IJ:158 `buildLayoutsResponse` | 1:1 | `LayoutKind.allCases` has the same order, symbols and names as `layouts[]`. |
| ipc.c:194 static `layer_enum_str` | none | platform | No layer shell (compat `layer_rule`, §3 last_open_surface). |
| ipc.c:209 `build_layers_response` | IJ:113 `IPCJSON.allLayers` (`{"layers":[]}`) | platform | Marked in the code. Mango with no layers gives the same JSON. |
| ipc.c:234 `send_static_json` | IS:411 `sendStaticJson` | 1:1 | Ours adds the `\n` that mango's literals carry. |
| ipc.c:240 `ipc_notify_json_to_fd` | IS:416 `ipcNotifyJsonToFd` | 1:1 | Takes the watch client, not an fd (mango searches the list by fd). Same result. |
| ipc.c:266 `ipc_notify_device_event` | none | platform, unlisted ✓ listet: afvigelser.md §3 | No libinput. `watch all-devices` never gets an event after its first `{"name":null,"type":null}`. |
| ipc.c:282 `ipc_remove_watch_client` | IS:404 `ipcRemoveWatchClient` | 1:1 | No device count (platform). |
| ipc.c:291 `ipc_watch_data_handler` | IS:396 `ipcWatchDataHandler` | 1:1 | Ours also treats EINTR as "keep". |
| ipc.c:308 `ipc_handle_client_data` | IS:357 `ipcHandleClientData` | 1:1 | Same 1 MB cap and same first-line handling. Ours returns on EAGAIN/EINTR where mango cleans up on `n <= 0` (edge, spurious wakeups only). |
| ipc.c:359 `ipc_handle_connection` | IS:331 `ipcHandleConnection` | 1:1, listed §3 | Same O_NONBLOCK/FD_CLOEXEC steps and errors. SO_NOSIGPIPE and 1 MB SO_SNDBUF are listed §3. |
| ipc.c:396 `ipc_notify_client` | IS:429 `handlePrintStatus` + IJ:260 `watchPayload(.client)` | differs, listed §2 (partly) ✓ rettet 15. nov. | Mango iterates only `server.clients` and skips `iskilling`. Ours resolves through `clientByIdAll`, so a watched **parked group member** gets updates in ours and none in mango. It is also sent on any printstatus, not only when the mask has IPC_WATCH_CLIENT. |
| ipc.c:421 `ipc_notify_tags` | same | differs, listed §2 (partly) ✓ rettet 15. nov. | Mango only sends on IPC_WATCH_TAGS, only on enabled outputs. Ours sends on any printstatus when the line changed. |
| ipc.c:447 `ipc_notify_all_tags` | same | differs, listed §2 (partly) ✓ rettet 15. nov. | Same as above (IPC_WATCH_ALL_TAGS). |
| ipc.c:472 `printstatus(enum ipc_watch_type type)` | MS:841 `printstatus()` | differs ✓ rettet 15. nov. (masken; `publishGlobalKeys()` mærket og listet i afvigelser.md §3, ipc.swift:591) | Ours takes no mask: every watcher is re-evaluated and sent if its line changed. Mango sends only to the kinds named in the mask. Scenario: `setkeymode` (`printstatus(IPC_WATCH_KEYMODE)`, bind.c:980) or a keyboard layout change (`IPC_WATCH_KB_LAYOUT`) does not update `watch monitor X` / `watch tags X` in mango, although the monitor JSON carries keymode/keyboardlayout. Ours sends the new monitor line. Ours also calls `publishGlobalKeys()` here (unmarked) and `onStateChange` (marked). |
| ipc.c:476 `handle_print_status` | IS:423 `notifyChanged` + IS:429 `handlePrintStatus` | differs, listed §2 (partly) ✓ listet: afvigelser.md §2 (samlingen pr. tur; masken og rækkefølgen rettet 15. nov.) | §2 lists "sent only when changed". Not listed: (a) the pass is deferred to a `Task` and coalesced, so a state that lasts only between two printstatus calls in one turn is never sent (marked "not in mango", not in afvigelser.md); (b) no type mask (above); (c) mango's order (keymode, kb_layout, focusing, all_tags, all_clients, all_monitors, client, then per monitor: monitor, tags, last_open_surface) is replaced by watcher insertion order. That only changes ordering across separate sockets. `mango_ext_workspace_printstatus` is platform. |
| ipc.c:536 `ipc_cleanup` | IS:319 `ipcCleanup` | 1:1 | Ours unsets `MANGO_INSTANCE_SIGNATURE` only if it is still our path (unmarked, harmless). |
| ipc.c:548 `tags_mask_to_array` | Rules.swift:23 `TagMask.tagsMaskToArray` | 1:1 | Puts 0 first for TAG0_MASK, then 1..tag_num. |
| ipc.c:557 `monitor_active_tags` | IJ:139 `monitorActiveTags` | 1:1 | Overview gives `[0]`. Ours goes through tagsMaskToArray, which would add 0 for the special bit, but `getMonitorActiveTagset` never returns it, so same result. |
| ipc.c:571 static `client_output_name` | inlined IJ:173 (`c.mon?.screen.name ?? ""`) | 1:1 (unsure) | Mango parks with `mon = NULL` and falls back to `client_group_active(c)->mon`. Ours keeps the parked member's own `mon` (Groups.swift `clientPark` does not clear it). Same result unless the member's `mon` is stale after the group moved monitors. Not verified. |
| ipc.c:578 `build_client_json` | IJ:164 `buildClientJson` | differs ✓ rettet 15. nov. | All 31 keys are present in mango's order. Differences: **x/y/width/height** come from `c.geom`, which ours stores **inset by the border** (MS:517/531 `box.insetBy(dx: bw, dy: bw)`; Client.swift:96 says "Not in mango: without the border"). Mango's `c->geom` includes `bw`. Scenario: borderpx=4, tiled client, mango width 1000, ours 992, x off by 4. Falls back to `c.frame` when geom is nil. Not in afvigelser.md for IPC. `foreign_toplevel_id` is `String(c.id)` (platform, unlisted, mango's is the protocol's random identifier). `is_xwayland`/`is_swallowing`/`is_swallowedby` are always false (platform, listed compat). `is_focused` is derived (`c.mon === selmon && selmon.sel == c.id`) for mango's `isfocusing`; same result as far as checked (unsure on edges during unmap). `scroller_proportion` falls back to the pertag default where mango starts at `config.scroller_default_proportion` (same once arranged; unsure before). |
| ipc.c:617 static `build_all_clients_array` | IJ:201 `buildAllClientsArray` | 1:1 | Each client, then its group's parked members. |
| ipc.c:631 static `transform_to_str` | IJ:215 `transformToStr` | 1:1 | Port maps `CGDisplayRotation/90` into the value. |
| ipc.c:654 `build_monitor_json` | IJ:229 `buildMonitorJson` | differs ✓ rettet 15. nov. | 20 keys, same order. **`hide_clients`**: mango gives `m->hide_clients`, the number of minimized clients counted in `arrange` (arrange.c:1134/1162, all clients, any monitor). Ours gives `m.isoverview ? 1 : 0`. Scenario: one minimized window, no overview: mango 1, ours 0. Unlisted and unmarked. `is_hdr`/`is_vrr` are always false (platform, listed compat togglehdr/vrr). `last_open_surface` is "" (listed §3). `x,y,width,height` = `screen.frame` for `m->m` (port). `scale` is a float like mango. |
| ipc.c:684 `handle_command` (frame) | IS:439 `handleCommand` + IS:56 `IPCRequest.parse` | 1:1 (edges) | Comma→space on the command, `dispatch` taken from the raw line, unknown → `{"error":"unknown command"}`: same. Edges: mango copies into `char[1024]` (a longer `get` line is truncated); ours is not. Ours strips a trailing `\r` (IS:59) before matching `get`/`watch`, so `get version\r\n` answers in ours and is "unknown command" in mango (unmarked). Ours answers `{"error":"compositor unavailable"}` if the server is gone (unmarked invention, unreachable in practice). |
| ↳ `get version` | IS:467 | differs, unlisted ✓ rettet 15. nov. | Returns `mangoVersion` = "0.0.4-20261109-beta" (MS:5), the app's version, where mango gives VERSION (0.18.5). A script that checks the mango version sees a different number. |
| ↳ `get cursorpos` | IS:469 | 1:1 | x, y, monitor (or null); port coordinates. |
| ↳ `get keymode` | IS:473 | 1:1 | |
| ↳ `get keyboardlayout` | IS:475 | 1:1 / port | `{"layout": ...}` from the port. |
| ↳ `get last_open_surface [mon]` | IS:477 | 1:1, listed §3 | Same selection and error. Value always "". |
| ↳ `get monitor <name>` | IS:481 | 1:1 | Inherits build_monitor_json's differences. |
| ↳ `get focusing-client` | IS:484, IJ:257 `ipcFocusingClient` | 1:1 | `focused ?? selmon.sel` are the same client. The error text is the same. |
| ↳ `get client <id>` | IS:487 | 1:1 | Same `(uint32_t)atoi`, then client_by_id_all. |
| ↳ `get tag <mon> <idx>` | IS:491 | 1:1, listed §3 | The last field is the tag (names have spaces). Fields: monitor, tag_index, is_active, is_urgent, client_count, focused_client. Same order and errors. |
| ↳ `get all-clients` | IS:521 | 1:1 | |
| ↳ `get all-monitors` | IS:523 | 1:1 | |
| ↳ `get all-devices` | IS:525 `IPCJSON.allDevices` | platform, unlisted (unsure) ✓ listet: afvigelser.md §3 (HID-enheder) | Always `{"devices":[]}`. No libinput. IOHIDManager could list name/vendor/product, but `matched`/`matched_rule` need device_rule (listed compat). Not named in compat/afvigelser. |
| ↳ `get all-layers` | IS:527 | platform | `{"layers":[]}` (no layer shell). |
| ↳ `get all-tags`, `get tags <mon>`, `get layouts` | IS:529-535 | 1:1 | |
| ↳ `dispatch` client-prefix scan | IS:97 `parseDispatch` (marked "apart") | differs ✓ rettet 15. nov. | Mango accepts `client,<id>` only when strtol ends at `\0` or `,` (ipc.c:921). Ours also accepts a space or tab (IS:128). Scenario: `mmsg dispatch client,4 killclient` (raw "client,4 killclient"): mango leaves "client" as the function → `{"error":"unknown function"}`. Ours kills client 4. (Overflowing ids are also handled differently, edge.) |
| ↳ `dispatch` tokenizing | IS:139-188 | differs ✓ rettet i trin 6 | The default (4 tokens plus the rest as the 5th) and `spawn`/`spawn_shell` (combine_args_until_empty, stop at "" or "0") match. **`spawn_on_empty`**: mango uses tokens[1] as the command and tokens[2] as the tag (binding_parse.c:735). Ours splits the whole rest at the *last* comma. **`toggle_named_scratchpad`**: mango uses tokens[1..3] (v, v2, v3). Ours makes the 3rd the whole rest. Scenario: `dispatch toggle_named_scratchpad,app,none,sh -c 'a,b'`: mango runs `sh -c 'a`, ours `sh -c 'a,b'`. Same for `spawn_on_empty,sh -c 'a,b',2`: mango gets cmd `sh -c 'a` and tag mask of `b'`. |
| ↳ `dispatch` target/func | IS:447-461 | 1:1 | "no client found" before "unknown function"; `focusid` falls back to client_by_id_all; `{"success":true}`. |
| ipc.c:1003 `handle_watch_command` | IS:381 `handleWatchCommand` + IS:18 `IPCWatch.parse` | differs (small) ✓ rettet 15. nov. | Same 11 commands, arguments, registration before the first line, and first lines. One difference: the first line of **`watch all-clients`** in mango is built from `server.clients` only (ipc.c:1127-1133, no parked group members). Ours uses `buildAllClientsArray` (with parked members). Scenario: a group of 2 with one parked: mango's first line lists 1 client, ours 2. (Mango's later notifications include them, so ours is self-consistent.) The `\r` strip also applies here. |
| ipc.c:1166 `ipc_notify_monitor` | handlePrintStatus/watchPayload(.monitor) | differs, listed §2 (partly) ✓ rettet 15. nov. | Only on IPC_WATCH_MONITOR in mango (see printstatus). |
| ipc.c:1192 `ipc_notify_last_surface_ws_name` | watchPayload(.lastOpenSurface) | 1:1, listed §3/§2 | An empty target follows the selected monitor in both. Value "". |
| ipc.c:1232 `ipc_notify_focusing_client` | watchPayload(.focusingClient) | differs, listed §2 (partly) ✓ rettet 15. nov. | Only on IPC_WATCH_FOCUSING_CLIENT in mango. |
| ipc.c:1264 `ipc_notify_all_monitors` | watchPayload(.allMonitors) | 1:1, listed §2 | Mango sends this on keymode/kb_layout/focus/tags too, so with the §2 dedupe the results match. |
| ipc.c:1294 `ipc_notify_all_clients` | watchPayload(.allClients) | differs, listed §2 (partly) ✓ rettet 15. nov. | Only on IPC_WATCH_ALL_CLIENTS in mango. |
| ipc.c:1321 `ipc_notify_keymode` | watchPayload(.keymode) | 1:1, listed §2 | |
| ipc.c:1347 `ipc_notify_kb_layout` | watchPayload(.keyboardLayout) | 1:1, listed §2 | Our printstatus on a layout change comes from the port (MacEvents). |
| ipc.c:1375 `ipc_init` | IS:259 `ipcInit` (+ MS:129 caller) | 1:1, listed §3 | Socket path `/tmp/mango-<user>.sock`, a live socket is not taken over, and chmod 0600: all listed §3. Failures are thrown and logged (marked MS:130), where mango returns silently. Same steps otherwise. |

### src/ext-protocol/* (all Wayland protocol glue)

| mango (file:line) | ours | status | note |
|---|---|---|---|
| ext-workspace.c:11 `goto_workspace`, :22 `toggle_workspace` | none | platform | ext-workspace-v1 requests from a Wayland bar. No such clients on macOS. |
| ext-workspace.c:33 `remove_workspace_by_tag`, :42 `get_name_from_tag`, :50 `destroy_workspace`, :56 `cleanup_workspaces_by_monitor`, :65 `add_workspace_by_tag`, :103 `workspaces_init`, :113 `handle_ext_commit`, :208 `sync_workspaces_to_tag_num` | none | platform | Protocol objects. |
| ext-workspace.c:82 `refresh_monitors_workspaces_status` | OverviewMode.swift:114 `printstatus()` in its place | platform, listed §5 | |
| ext-workspace.c:171 `mango_ext_workspace_printstatus` | none | platform | Called from handle_print_status. The menu bar is the port's stand-in. |
| foreign-toplevel.c:11 `handle_foreign_activate_request`, :17 `handle_foreign_maximize_request`, :34 `handle_foreign_minimize_request`, :55 `handle_foreign_fullscreen_request`, :74 `handle_foreign_close_request`, :78 `handle_foreign_destroy`, :88 `add_foreign_toplevel`, :124 `reset_foreign_tolevel` | none | platform | wlr-foreign-toplevel for external taskbars. macOS's Dock/⌘Tab go through activation (below). The Dock's minimize is `handleClientRequestMinimize` (other group). |
| hdr.c:9 `output_set_render_format`, :24 `output_format_in_candidates`, :31 `bit_depth_from_format`, :40 `output_supports_hdr`, :59 `output_enable_hdr`, :104 `output_state_setup_hdr`, :155 `togglehdr_output` | none | platform | Output render formats. |
| hdr.c:210 `toggle_hdr` | none | platform, listed compat (`togglehdr`) | |
| tearing.c:8 `handle_controller_set_hint`, :26 `handle_controller_destroy`, :33 `handle_tearing_new_object`, :53 `check_tearing_frame_allow` | none | platform, listed compat (`allow_tearing`, `force_tearing`) | |
| text-input.c:17 `output_from_wlr_output`, :26 `output_is_usable`, :27 `is_keyboard_emulated_by_input_method`, :41 `get_keyboard_grab`, :55 `mango_im_keyboard_grab_forward_modifiers`, :71 `mango_im_keyboard_grab_forward_key`, :87 `get_active_text_input`, :101 `update_active_text_input`, :115 `update_text_inputs_focused_surface`, :141 `update_popup_position`, :216 `update_popups_position`, :223 `handle_input_method_commit`, :252 `handle_keyboard_grab_destroy`, :265 `handle_input_method_grab_keyboard`, :283 `handle_input_method_destroy`, :296 `handle_popup_surface_destroy`, :305 `handle_popup_surface_commit`, :311 `handle_input_method_new_popup_surface`, :339 `handle_new_input_method`, :375 `send_state_to_input_method`, :396 `handle_text_input_enable`, :408 `handle_text_input_disable`, :415 `handle_text_input_commit`, :425 `handle_text_input_destroy`, :437 `handle_new_text_input`, :465 `handle_focused_surface_destroy`, :473 `mango_im_relay_create`, :492 `mango_im_relay_finish`, :498 `mango_im_relay_set_focus` | none | platform, listed §5 (IM popups) | macOS runs input methods itself. |
| xdg-activation.c:14 `handle_xdg_activation_token_destroy`, :22 `handle_xdg_activation_new_token`, :38 `xdg_activation_token_can_activate`, :78 `handle_xdg_activation_destroy`, :85 `xdg_activation_init`, :104 `xdg_activation_v1_export_token` | none | platform, listed compat (`activation_bypass`) | Tokens. `spawn` exports no XDG_ACTIVATION_TOKEN. |
| xdg-activation.c:50 `handle_xdg_activation_request_activate` | MacEvents.swift:122 `windowFocused` → MS:1284 `handleClientActivationRequest` | port | macOS has already activated the app, so the token check and its urgent-only branch do not apply. Every activation takes the bypass path. |
| xdg-output.c:20 `xdg_output_resource_is_xwayland`, :30 `xdg_output_get_values`, :83 `xdg_output_send_details`, :143 `xdg_output_logical_changed`, :164 `xdg_output_xwayland_changed`, :184 `xdg_output_update`, :194 `handle_xdg_output_resource_destroy`, :201 `handle_xdg_output_destroy`, :206 `handle_xdg_output_manager_destroy`, :212 `handle_xdg_output_description`, :227 `xdg_output_find`, :245 `handle_xdg_output_layout_output_destroy`, :255 `xdg_output_create`, :276 `xdg_output_destroy`, :295 `handle_xdg_output_manager_get_output`, :350 `xdg_output_manager_bind`, :371 `xdg_output_update_all`, :392 `xdg_output_init` | none | platform | |

### mmsg/mmsg.c (+ common/log.c as used by mmsg)

| mango (file:line) | ours | status | note |
|---|---|---|---|
| mmsg.c:12 `usage` | mmsg/main.swift:5 `usage` | 1:1, listed §5 | Same text line for line. The port's lines come in through `mmsgPortUsage()` (marked). |
| mmsg.c:84 `main` | mmsg/main.swift:49-141 | 1:1, listed §2/§3 | Same help/argc checks, sun_path copy, 4096-byte command with the same two "too long" errors, getline echo loop, perror texts. Port commands come in before the env check (marked, §2). The `/tmp/mango-<user>.sock` fallback when MANGO_INSTANCE_SIGNATURE is unset and SO_NOSIGPIPE for MSG_NOSIGNAL are listed §3. |
| common/log.c `mango_error` (log=false, tagged) | mmsg/log.swift:6 `mangoError` | 1:1 | Same colour tags. No error store (inactive in mmsg). Unknown verbosity has no case (only 3 used). |
| mmsg/mmsg.1.in (man page) | none | missing åben (ingen man-sider i repoet eller Makefile; som mangel i afvigelser.md §4) | Not shipped. Neither is `mangonag.1.in`. |

### mangonag/mangonag.c

| mango (file:line) | ours | status | note |
|---|---|---|---|
| :29-67 `NAG_MAX_LINES`, `type_error/_warning/_info`, structs | MN:3-86 | 1:1 | Same colours. State holds no Wayland objects (port). |
| :140 `nag_signal` | MN:95 `nagSignal` | 1:1 | No sigaction; error_nag's nag_kill calls it (marked). |
| :146 `rgba_to_cairo` | NAG:105 `Nag.ns` | port | |
| :154 `nag_run_action` | MN:99 `nagRunAction` + NAG:78 `nagFork` | 1:1 / port, listed §3 | Dismiss and empty-action checks are the same. The fork and the terminal script are the port's. Terminal.app fallback and `.command` are listed §3. Mango double-forks and reaps; ours uses `Process` (port). |
| :202 `handle_buffer_release`, :209-241 `nag_output_*` (name, geometry, mode, done, scale, description), :250 `nag_create_shm_fd`, :272 `nag_buffer_create` | none | platform | wl_shm and wl_output. |
| :318 `nag_layout` | NAG:159 `NagView.size` | port | Pango becomes AppKit with `decorateFont(FontDescription)`. |
| :351 `nag_color` (+ `nag_palette`) | MN:132 `nagColor` | 1:1 | |
| :370 `nag_style_reset` | MN:153 | 1:1 | |
| :383 `nag_style_code` | MN:166 | 1:1 | |
| :416 `nag_style_params` | MN:201 | 1:1 | |
| :462 `nag_attr_emit` | MN:262 `nagAttrEmit` | 1:1 | One record per run, not one pango attribute each (marked). Same ranges and values. |
| :515 `nag_ansi_skip` | MN:294 | 1:1 | |
| :528 `nag_tag_match` | MN:310 | 1:1 | |
| :553 `nag_ansi_attrs` | MN:327 | 1:1 | |
| :636 `nag_layout_markup` | NAG:110 `Nag.attributed` | port | |
| :660 `nag_text_height` | NAG:162 (in computeHeight) | port | Unwrapped height, as width 0. |
| :673 `nag_compute_layout` | NAG:161 `computeHeight` | port | Same constants (padding 8, borders 3, button padding 3). |
| :705 `nag_render` | NAG:172 `NagView.draw` | port | Same layout math (text_avail, char_w from "0000000000", button x walk right-to-left, gap 20, bottom border, outline). The `macOS` variant is the extension `chutney_macos_appearance` (listed §1; the use in Nag.swift is not marked). |
| :839 `nag_layer_configure` | none | platform | |
| :854 `nag_layer_closed` | MN:438 `nagLayerClosed` | 1:1 | Never called by the port (no compositor close). |
| :864 `nag_pointer_button` | MN:402 | 1:1 | |
| :882 `nag_pointer_enter`, :893 `nag_pointer_motion` | MN:419, MN:424 | 1:1 | The port sets motion and then button on a click. |
| :889, :899-916 pointer leave/axis/frame/axis_* (no-ops) | none | platform | Empty in mango. |
| :930 `nag_keyboard_keymap` | none | platform | |
| :944 `nag_keyboard_key` | MN:429 `nagKeyboardKey` | 1:1 | Never called by the port. Mango asks for keyboard interactivity NONE, so it gets no keys either. Same result. |
| :935, :940, :953, :960 other keyboard no-ops | none | platform | |
| :973 `nag_seat_capabilities`, :985 `nag_seat_name`, :993 `nag_registry_global`, :1019 `nag_registry_global_remove` | none | platform | |
| :1028 `nag_setup_surface` | NAG:29 `nagSetupSurface` | port; differs, listed §3 (partly) ✓ listet: afvigelser.md §3 (exclusive zone); fallback til den valgte skærm rettet 15. nov. | `-y` is ignored (listed §3). Two points not listed: (a) mango sets `exclusive_zone = height`, so the layout's work area shrinks and tiled windows move below the bar. Ours is a status-bar-level panel that covers the windows. §3 says only "står over vinduerne". (b) Without `-o`, or with an unknown name, mango's layer surface gets the **selected monitor** (layer.c:515). Ours takes the primary display (`frame.origin == .zero`). error_nag normally passes `-o`, so this is rare. |
| :1064 `nag_expand_long_options` | MN:459 | 1:1 | |
| :1119 `nag_add_button` | MN:495 | 1:1 | |
| :1140 `nag_read_stdin` | MN:499 `nagReadStdin` | 1:1 | stdin is the text the port hands in (marked). Empty becomes nil, as mango's NULL. |
| :1160 `nag_limit_lines` | MN:505 | 1:1 | |
| :1190 `nag_truncate_lines` | MN:531 | 1:1 | |
| :1237 `usage` | MN:571 | 1:1 | |
| :1256 `main` | MN:591 `mangonagMain` (`/// mango main`) | 1:1, listed §3/§5 | Same defaults, getopt string, option handling, details merge, dismiss button, trailing trim, 4-line cap. Not ours: macOS getopt does not permute (listed §3), and signals, connect, the globals check, output scale and the poll loop with `-T` are the port's (timer listed §3). |
| :1474 `nag_destroy` | MN:688 `nagDestroy` + NAG:70 `nagDestroySurface` | port | |

## Not in mango (in the Swift files looked at)

| ours (file:line) | marked? | note |
|---|---|---|
| IS:17 `IPCWatch.parse` | yes | handle_watch_command's parsing as its own function. |
| IS:55 `IPCRequest` / `IPCRequest.parse` | yes | Also strips a trailing `\r` (IS:59), which is not marked on its own. |
| IS:71 `cAtoi`, IS:87 `clientID(atoi:)` | yes | C's atoi. |
| IS:92 `commandTakingDispatchers` | **no** | Dead code: nothing reads it. |
| IS:96 `parseDispatch` | yes ("apart") | The per-dispatcher branches (spawn_on_empty, toggle_named_scratchpad) and the space/tab terminator are deviations that this mark does not name. |
| IS:194 `IPCServerError` | caller marked (MS:130) | ipc_init's silent returns become thrown errors. |
| IS:217 `defaultSocketPath` | yes | §3. |
| IS:233 `IPCWatchClient.lastPayload` | yes | §2. |
| IS:255 `isRunning`, IS:257 `watcherCount` | no | Small accessors. watcherCount is used by tests only. |
| IS:306 `isLive` | yes | §3. |
| IS:423 `notifyChanged` (Task coalescing) | yes | Coalescing is not in afvigelser.md. |
| IS:441 "compositor unavailable" reply | no | Unreachable in practice. |
| IS:536 `portHooks.ipcGets` | yes | `get binds`, §2. |
| IJ:5 `JSONValue` + write/formatNumber/escape/escaped | yes | cJSON's printer. Number and escape rules match cJSON's print_number and print_string. |
| IJ:93 `IPCJSON.error` / constants | yes / n.a. | |
| IJ:110-114 `allDevices`, `allLayers`, `nullDevice` | yes (first two) | |
| IJ:257 `ipcFocusingClient` | no | Helper for `selmon->sel`. Equivalent. |
| IJ:260 `watchPayload` | yes | Replaces the 9 `ipc_notify_*` builders. |
| MS:842 `publishGlobalKeys()` inside `printstatus` | **no** | Not part of mango's printstatus/handle_print_status. |
| MS:844 `onStateChange` | yes | Boundary. |
| mmsg/main.swift:3, :45, :65, :67-69, :111 | yes | Port hooks and §3 items. |
| MN:7 `NagLayer`, MN:67 `display`, MN:92 `nagStdin`, MN:249 `NagAttr` | yes | |
| NAG:6 `macOS` flag / NAG:50-57, :144, :155-157, :209-211, :223 | no (in port) | chutney_macos_appearance look for the nag. Listed §1 but not marked at the use. |

## Summary

Counts, one row per mango function, with handle_command's 16 sub-requests counted separately. ext-protocol and mangonag functions grouped in a row are counted one by one.
- 1:1: 61 (ipc.c 22 including sub-requests; mmsg 3; mangonag 26; the rest are structs/types)
- differs: 15 (ipc.c 14 including sub-requests; mangonag 1, `nag_setup_surface`, which is also port)
- missing: 1 (man pages `mmsg.1`, `mangonag.1`; not a function)
- platform: 101 (ipc.c 4; ext-protocol 95, of which 3 are listed compat/§5 and the rest are pure protocol; mangonag 2 groups ≈ 25 callbacks. `get all-devices` and `ipc_notify_device_event`/`ipc_device_type_str` are **unlisted**)
- port: 12 (ipc_get_layout_str, handle_xdg_activation_request_activate, nag_render/compute_layout/layout/layout_markup/text_height/rgba_to_cairo/run_action fork/setup_surface/destroy)
- Tags: listed §2 on 8 rows, listed §3 on 7, listed §5 on 3. name: build_all_tags_entry and client_output_name inlined.

The 10 most significant deviations, most significant first:
1. **`hide_clients` in the monitor JSON is wrong.** Mango gives the minimized-client count (`m->hide_clients`, set in arrange). Ours gives `isoverview ? 1 : 0` (IJ:246). Unlisted and unmarked. One minimized window: mango 1, ours 0.
2. **Client `x/y/width/height` leave out the border.** Ours reads `c.geom`, which is stored inset by `bw` (MS:517/531). Mango's `c->geom` includes the border. With borderpx=4, every IPC client geometry is 4 px off in x and y and 8 px smaller. Not listed for IPC.
3. **`printstatus` has no watch-type mask.** Every watcher is re-evaluated on every printstatus (IS:429). Example: `setkeymode` or a layout change updates `watch monitor`/`watch tags`/`watch client` in ours but not in mango. The pass is also deferred and coalesced per turn (a `Task`, marked but not in afvigelser.md), so short-lived states are dropped. Only the dedupe is listed (§2).
4. **`dispatch` accepts `client,<id>` followed by a space** (IS:128). `mmsg dispatch client,4 killclient` kills client 4 in ours; mango answers "unknown function".
5. **`dispatch spawn_on_empty` and `toggle_named_scratchpad` keep commas** in the command (IS:170-184). Mango takes tokens[1..3] only, so `sh -c 'a,b'` becomes `sh -c 'a` in mango.
6. **`get version` returns the app version** ("0.0.4-20261109-beta", MS:5), not mango's 0.18.5. Unlisted.
7. **The mangonag bar has no exclusive zone** (the windows are not moved below it). Without `-o` it goes to the primary display, where mango uses the selected monitor (NAG:29-43). §3 only partly covers this.
8. **Parked group members in watches.** The first line of `watch all-clients` includes parked members (mango's does not). `watch client <id>` on a parked member gets updates; mango's `ipc_notify_client` only walks `server.clients`.
9. **`get all-devices` / `watch all-devices` are always empty / silent.** Neither is listed in compat or afvigelser.md. IOHID could at least list the devices.
10. **Request edges.** A trailing `\r` is stripped (IS:59), so `get version\r` works in ours and is "unknown command" in mango. There is no 1024-byte truncation of `get` lines, no 63-char truncation of watch target names, and EAGAIN does not close the connection. Unmarked but minor.

Also worth fixing (housekeeping): `commandTakingDispatchers` (IS:92) is dead and unmarked. `publishGlobalKeys()` inside `printstatus` (MS:842) is unmarked. Nag.swift's `macOS` appearance branch is not marked as an extension. The mmsg and mangonag man pages are not shipped.
