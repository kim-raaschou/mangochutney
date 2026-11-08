# Compatibility with mango

Mango Chutney tracks [mango](https://github.com/mangowm/mango) 0.18.5. Every option, keyword,
window-rule field and dispatcher of mango works, or is listed here with the reason macOS cannot
do it. A test (`MangoCoverageTests`) checks this against the names taken from mango's source
(`Tests/mango-keys`, `script/mango-keys.sh`). A misspelt key is an error, as in mango, and
`mango -p` says which keys of your config do nothing on macOS.

Generated from the code with `make readme-tables`.

<!-- mango-compat:start -->
### Not implemented yet

Nothing: everything of mango that macOS allows is implemented.

### Cannot work on macOS

macOS draws and manages other apps' windows, the keyboard, the pointer and the displays itself; a window manager cannot change these.

| What | Names | Why |
| --- | --- | --- |
| Blur | `blur`, `blur_layer`, `blur_optimized`, `blur_params_brightness`, `blur_params_contrast`, `blur_params_noise`, `blur_params_num_passes`, `blur_params_radius`, `blur_params_saturation` | scenefx effect; macOS draws other apps' windows |
| Shadows | `layer_shadows`, `shadow_only_floating`, `shadows`, `shadows_blur`, `shadows_color`, `shadows_position_x`, `shadows_position_y`, `shadows_size` | macOS draws window shadows |
| Dimming | `dim_enable`, `dim_focused_color`, `dim_unfocused_color` | darkening other apps' windows needs a compositor |
| Opacity animation | `animation_curve_opacity_fade_in`, `animation_curve_opacity_fade_out` | another app's window opacity can only be changed with SIP off |
| Layer surfaces | `layer_animation_type_close`, `layer_animation_type_open`, `layer_animations` | macOS has no layer shell; bars and launchers are ordinary apps |
| Display | `allow_tearing`, `hdr_depth`, `sync_obj_enable` | colour depth and tearing are display settings of macOS |
| Keyboard | `numlock_on`, `repeat_delay`, `repeat_rate`, `xkb_rules_layout`, `xkb_rules_model`, `xkb_rules_rules`, `xkb_rules_variant` | layout, repeat and Num Lock are macOS keyboard settings (mango repeats a binding with its own timer; the port leaves key repeat to macOS, and a passthrough binding does not repeat) |
| Mouse | `mouse_accel_profile`, `mouse_accel_speed`, `mouse_click_method`, `mouse_left_handed`, `mouse_middle_button_emulation`, `mouse_natural_scrolling`, `mouse_scroll_button`, `mouse_scroll_method`, `mouse_send_events_mode` | pointer settings are macOS settings |
| Trackpad and touch | `disable_trackpad`, `drag_lock`, `tap_and_drag`, `tap_to_click`, `touch_enable`, `touch_enable_mouse_emulation`, `trackpad_accel_profile`, `trackpad_accel_speed`, `trackpad_click_method`, `trackpad_disable_while_typing`, `trackpad_left_handed`, `trackpad_middle_button_emulation`, `trackpad_natural_scrolling`, `trackpad_scroll_button`, `trackpad_scroll_factor`, `trackpad_scroll_method`, `trackpad_send_events_mode` | trackpad settings are macOS settings |
| Other input | `axis_scroll_factor`, `button_map`, `disable_middle_paste`, `send_events_mode` | libinput settings and Wayland's middle-click paste |
| Cursor | `cursor_size`, `cursor_theme` | macOS draws the cursor (System Settings, Accessibility, Display) |
| Idle | `idle_inhibit_ignore_visible`, `idle_inhibit_when_fullscreen` | macOS handles sleep and the screen saver |
| Wayland protocols | `allow_lock_transparent`, `allow_shortcuts_inhibit` | protocols without a macOS counterpart |
| Xwayland | `xwayland_ignore_scale`, `xwayland_persistence` | there is no X11 on macOS |
| Keyword | `device_rule=` | input devices are configured in macOS settings |
| Keyword | `layer_rule=` | macOS has no layer shell |
| Keyword | `monitor_rule=` | display mode, scale, position and HDR are macOS display settings |
| Keyword | `switchbind=` | lid switch events are not available to apps on macOS |
| Options | `animation_curve_focus`, `animation_duration_focus`, `animation_fade_in`, `animation_fade_out`, `fade_in_begin_opacity`, `fade_out_begin_opacity`, `focused_opacity`, `unfocused_opacity` | another app's window opacity can only be changed with SIP off |
| Options | `float_full_to_top` | macOS has no layers for other apps' windows: the window focused last is on top |
| Options | `animation_curve_close`, `animation_duration_close`, `animation_type_close`, `zoom_end_ratio` | the window is already gone when macOS reports it closed |
| Window-rule fields | `allow_shortcuts_inhibit` | Wayland protocol without a macOS counterpart |
| Window-rule fields | `focused_opacity`, `no_fade_in`, `no_fade_out`, `unfocused_opacity` | another app's window opacity can only be changed with SIP off |
| Window-rule fields | `allow_csd` | macOS apps always draw their own title bars |
| Window-rule fields | `no_size_hint` | macOS apps keep their own minimum and maximum size |
| Window-rule fields | `ignore_maximize` | macOS apps zoom their own windows; no maximize request reaches mango (the default, 1, is what happens) |
| Window-rule fields | `is_term`, `no_swallow` | macOS does not say which app started another, so nothing can swallow it |
| Window-rule fields | `no_blur` | macOS draws other apps' windows |
| Window-rule fields | `no_radius` | macOS draws window corners |
| Window-rule fields | `no_shadow` | macOS draws window shadows |
| Window-rule fields | `idle_inhibit_when_focus` | macOS handles sleep and the screen saver |
| Window-rule fields | `force_tiled_state` | macOS has no tiled state to tell an app |
| Window-rule fields | `shield_when_capture` | screen-capture protocol; macOS decides what captures show |
| Window-rule fields | `force_tearing` | tearing is a display setting |
| Window-rule fields | `animation_type_close` | the window is already gone when macOS reports it closed |
| Window-rule fields | `force_render` | the window server decides what is rendered |
| Window-rule fields | `vrr_only_fullscreen` | variable refresh rate is a macOS display setting |
| Window-rule fields | `force_fake_maximize` | xdg maximize state; macOS has no such request |
| Window-rule fields | `activation_bypass` | xdg-activation; macOS apps activate themselves |
| Dispatchers | `togglehdr` | HDR is a macOS display setting |
| Dispatchers | `disable_monitor`, `enable_monitor`, `sleep_monitor`, `sleep_toggle_monitor`, `toggle_monitor`, `wakeup_monitor` | displays are managed by macOS |
| Dispatchers | `switch_keyboard_layout` | keyboard layouts are switched by macOS's input menu and its own shortcut (not built: chosen) |
| Dispatchers | `toggle_trackpad_enable` | macOS has no API to switch the trackpad off |
| Dispatchers | `chvt` | macOS has no virtual terminals |
| Dispatchers | `create_virtual_output`, `destroy_all_virtual_output` | virtual outputs are a wlroots feature |

### Port extensions (not in mango)

Unset, mango behaves as mango does. In mango itself each is an unknown keyword, reported and skipped.

| Name | Does |
| --- | --- |
| `chutney_border_unfocused` | draw borders around unfocused windows too |
| `chutney_floating_color` | fixed border colour of floating windows, focused or not |
| `chutney_hotkeys_apps` | the installed apps (from Spotlight) in the hotkeys palette's search |
| `chutney_hyper_key` | the key held as HYPER, as Raycast's Hyper Key: caps_lock, a left_ or right_ control, shift, option or command, f1 … f12 (macOS's own key mapping) |
| `chutney_hyper_modifier` | what HYPER means in a bind |
| `chutney_hyper_tap` | Caps Lock or a function key that is Hyper, pressed alone: none, original (the key itself) or escape |
| `chutney_ignore_apps` | bundle ids that are never managed |
| `chutney_layout_palette_keys` | the keys that move the layout palette's selection: left,down,up,right (or h,j,k,l); the arrows always work |
| `chutney_menu_bar` | menu-bar item with the current tags and layout |
| `chutney_menu_bar_layout` | the layout's icon in the menu bar |
| `chutney_menu_bar_logo` | the mango logo in the menu bar: color, mono (the menu bar's colour) or 0 |
| `chutney_menu_bar_mode` | the key mode in the menu bar, the default one too (0: only another mode) |
| `chutney_menu_bar_tag_style` | the menu bar's tags: square, circle (SF Symbols numbers) or text |
| `chutney_menu_config` | the file the menu's panel saves its settings in; the config reads it with source_optional, last |
| `chutney_physical_pixels` | border_px and the gaps in the screen's pixels, not points (3 is 1.5 points on Retina) |
| `chutney_style` | bars, switcher and jump labels in the macOS style where no decorate key is set |
| `chutney_tab_bar_app_icons` | the app's icon before each tab's title |
| `chutney_tab_bar_shortcuts` | ⌘1-9 picks a tab while a tab bar is shown |
| `chutney_focus_app` (dispatcher) | one key per app: start it, or go to its window |
| `chutney_restart` (dispatcher) | quit, with hidden windows left hidden for the next mango (make install, mmsg service restart) |
| `chutney_set_proportion_all` (dispatcher) | set_proportion for every window of the tag in view; without a value, scroller_default_proportion |
| `chutney_toggle_hotkeys_palette` (dispatcher) | the hotkeys palette: search the bindings, move with the keys, Return runs one |
| `chutney_toggle_layout_palette` (dispatcher) | the layout palette: circle_layout's layouts (or all 14) as icons, move with the keys, Return sets one |
<!-- mango-compat:end -->
