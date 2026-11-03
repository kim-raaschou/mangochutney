---
title: Coming from AeroSpace
description: What AeroSpace's commands are called here, and what there is to find beyond them.
---

Mango Chutney works the way AeroSpace does underneath: it moves windows through the Accessibility
API, hides windows on other tags in a corner of the screen, and needs no change to SIP. Which
windows are tiled and which float is decided by AeroSpace's own rules, ported as they are.

The rest is mango. There is no tree of containers. A layout is a fixed arrangement that the
windows fill in order, and you switch layouts instead of building one.

## The same thing, another name

| AeroSpace | Mango Chutney |
|---|---|
| `~/.aerospace.toml` | `~/.config/mango/config.conf` (or `config.toml`), reloaded on save |
| workspaces | tags: 1–9 on every monitor |
| `workspace 2` | `view,2` |
| `move-node-to-workspace 2` | `tag,2` (`tagsilent,2` stays where you are) |
| `focus left` | `focusdir,left` |
| `move left` | `move_client,left` |
| `join-with left` | `scroller_stack,left`, in the scroller layout |
| `layout tiles` | `setlayout,tile` |
| `layout accordion` | `setlayout,monocle` or `deck`, with a tab bar |
| `layout floating tiling` | `togglefloating` |
| `fullscreen` | `togglefullscreen`, or `togglemaximizescreen` |
| `resize smart` | `resizewin`, or `setmfact` for the main area |
| `[mode.window.binding]` | `key_mode=window` and `setkeymode,window` |
| `[[on-window-detected]]` | `window_rule=`, with the bundle id as `app_id` |
| `aerospace` | `mmsg` |

A mode looks like this:

```ini
bind=HYPER,w,setkeymode,window
key_mode=window
bind=none,Left,move_client,left
bind=super,Left,focusdir,left
bind=none,Escape,setkeymode,default
key_mode=default
```

## What AeroSpace does not have

Things to try. Keys are mango's defaults; **Hyper K** finds the rest by name.

- **14 layouts**, each tag with its own. ⌘ N goes round them, Hyper L shows them all. Try
  scroller: windows in a row you scroll through, ⌥ X for the next width, ⌥ E for full width.
- **Overview.** Four fingers up shows every window from every tag. Bind `toggleoverview` for a
  key, or set `enable_hotarea=1` to open it from a screen corner.
- **Jump labels.** ⌥ Tab puts a letter on each window.
- **Scratchpad.** ⌘ I puts a window away, ⌥ Z brings it back. A named scratchpad
  (`toggle_named_scratchpad`) is one key for one app that starts it if needed.
- **A window on every tag** (⌘ G), or **always on top** (⌘ O).
- **Two tags at once.** `toggleview,3` adds tag 3's windows to the ones in view, and
  `toggletag,3` puts a window on tag 3 as well.
- **Groups.** `groupjoin,left` joins the window to the one on its left, with a tab bar.
- **A switcher** with pictures of the windows: `switcher,all_tag_next`.
- **Borders and animations**, with colours that follow your accent colour.
- **Trackpad gestures**: three fingers move focus, four switch tags and open the overview. Turn off
  macOS's own swipes in System Settings → Trackpad if they get in the way.
- **`tag_carousel=1`**: going right from tag 9 comes round to tag 1.

The [layout palette](bindings/palettes#layout-palette) has a second view as well: press Tab to see
all 14 layouts and choose which ones ⌘ N goes round.

## Moving your config over

There is no converter. Start from the default config, add your app rules as `window_rule` lines
and your modes as `key_mode` blocks, then put your keys where you want them. mango's own keys use
⌘ and ⌥, which macOS apps also use; with `xkb_rules_options=caps:hyper` Caps Lock is a Hyper key,
much like the Hyper setups many AeroSpace users have. The [guide](../guide.md#the-hyper-key) has a
ready set of mango's keys on Hyper.

`mango -p` checks the config and tells you what does not work on macOS.
