---
title: Coming from yabai
description: What yabai's commands are called here, and what there is to find beyond them.
---

Mango Chutney needs no change to SIP and no scripting addition. It does not use macOS Spaces:
each screen has nine tags of its own, and windows on the tags you are not looking at are moved
to a corner of the screen. Switching tags is instant, with no Spaces animation.

There is no skhd either. Keys, rules and options are all in one file,
`~/.config/mango/config.conf`, which reloads when you save it.

## The same thing, another name

| yabai / skhd | Mango Chutney |
|---|---|
| `~/.yabairc` and `~/.skhdrc` | `~/.config/mango/config.conf` |
| `alt - h : yabai -m window --focus west` | `bind=ALT,h,focusdir,left` |
| `space --layout bsp` | `setlayout,dwindle` |
| `space --layout stack` | `setlayout,monocle` or `deck`, with a tab bar |
| `space --layout float` | `toggle_all_floating` |
| `window --swap west` | `exchange_client,left` |
| `window --warp west` | `move_client,left` (in dwindle it moves the window in beside the other) |
| `window --insert east` | `dwindle_split_horizontal`, `dwindle_split_vertical` |
| `window --toggle split` | `dwindle_toggle_split_direction` |
| `window --ratio`, `--resize` | `setmfact`, `resizewin` |
| `window --toggle float` | `togglefloating` |
| `window --toggle zoom-fullscreen` | `togglemaximizescreen` |
| `window --toggle native-fullscreen` | `togglefullscreen` |
| `window --toggle sticky` | `toggleglobal` |
| `window --sub-layer above` | `toggleoverlay` |
| `window --space 2` | `tag,2` (`tagsilent,2` stays where you are) |
| `space --focus 2` | `view,2` |
| `window --display east` | `tagmon,right` |
| `rule --add app="^Calculator$" manage=off` | `window_rule=is_floating:1,app_id:com.apple.calculator` |
| `window_gap`, `top_padding` … | `gappih`, `gappiv`, `gappoh`, `gappov` |
| `mouse_modifier`, `mouse_action1 move` | `mousebind=SUPER,btn_left,moveresize,curmove` |
| `focus_follows_mouse autofocus` | `sloppy_focus=1` |
| `mouse_follows_focus on` | `warp_cursor=1` |
| skhd modes | `key_mode=` blocks and `setkeymode` |
| `yabai -m query` | `mmsg get all-clients`, `mmsg get focusing-client` |
| `yabai -m signal` | `mmsg watch all-clients`, `mmsg watch all-tags` |

`mmsg dispatch` runs any of these from a script, like `yabai -m`.

## What yabai does not have

Things to try. Keys are mango's defaults; **Hyper K** finds the rest by name.

- **14 layouts**, each tag with its own. ⌘ N goes round them, Hyper L shows them all. dwindle is
  the one closest to bsp. Try scroller: windows in a row you scroll through, ⌥ X for the next
  width, ⌥ E for full width.
- **Overview.** Four fingers up shows every window from every tag. Bind `toggleoverview` for a
  key, or set `enable_hotarea=1` to open it from a screen corner.
- **Jump labels.** ⌥ Tab puts a letter on each window.
- **Scratchpad.** ⌘ I puts a window away, ⌥ Z brings it back. A named scratchpad
  (`toggle_named_scratchpad`) is one key for one app that starts it if needed.
- **Two tags at once.** `toggleview,3` adds tag 3's windows to the ones in view, and
  `toggletag,3` puts a window on tag 3 as well.
- **Groups.** `groupjoin,left` joins the window to the one on its left, with a tab bar.
- **A switcher** with pictures of the windows: `switcher,all_tag_next`.
- **Borders and animations** built in, with colours that follow your accent colour.
- **Trackpad gestures**: three fingers move focus, four switch tags and open the overview. Turn off
  macOS's own swipes in System Settings → Trackpad if they get in the way.

## What yabai does that this does not

yabai's scripting addition reaches into the Dock, which Mango Chutney does not. It cannot set
other apps' opacity or shadows, and it does not create, destroy or move macOS Spaces. Tags take
the place of Spaces. [Compatibility](../compatibility.md) has the full list.

## Moving your config over

There is no converter. Start from the default config, turn each skhd line into a `bind=` line and
each `yabai -m rule` into a `window_rule` line. mango's own keys use ⌘ and ⌥, which macOS apps
also use; with `xkb_rules_options=caps:hyper` Caps Lock is a Hyper key, which takes the place of
skhd's `hyper` modifier. The [guide](../guide.md#the-hyper-key) has a ready set of mango's keys
on Hyper.

`mango -p` checks the config and tells you what does not work on macOS.
