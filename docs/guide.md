# Mango Chutney guide

Mango Chutney is [mango](https://mangowm.github.io/docs) 0.18.5 on macOS: mango's layouts, tags,
rules, dispatchers and config keys work here as they do there, and
[mango's documentation](https://mangowm.github.io/docs) describes them. This guide has what is
particular to the Mac: the first start, the keys, the menu bar and palettes, and the port's own
`chutney_` options. [Compatibility](compatibility.md) lists what macOS cannot do.

- [Getting started](#getting-started)
- [A first week](#a-first-week)
- [Keys](#keys)
- [The Hyper key](#the-hyper-key)
- [The menu bar](#the-menu-bar)
- [The palettes](#the-palettes)
- [One key per app](#one-key-per-app)
- [Configuration](#configuration)
- [Theming](#theming)
- [Coming from AeroSpace or yabai](#coming-from-aerospace-or-yabai)
- [On macOS](#on-macos)
- [mmsg](#mmsg)
- [Installing from a zip or from source](#installing-from-a-zip-or-from-source)

## Getting started

```bash
brew install --cask kim-raaschou/tap/mangochutney
open -a "Mango Chutney"
```

Requires macOS 14 or later on Apple silicon. Quit AeroSpace, yabai or any other tiling window
manager first: two managers fight over the same windows.

### Remember two keys

| Keys | Does |
| :--- | :--- |
| **Hyper K** | Every key binding, in a list you search by what you want to do: "float", "tag", "layout". When you do not know how, press Hyper K. |
| **Hyper L** | The layouts, as pictures: pick how the windows are arranged with the arrows and Return. |

**Hyper** is one key you choose on the first start, held. It acts as Control, Option and Command
(⌃⌥⌘), which no app uses, so mango's keys never take an app's shortcut. Everything else is found
from these two keys.

### The first start

A window says what Mango Chutney needs and opens the right page of System Settings:

- **Accessibility** (required): windows are managed as soon as it is allowed.
- **Screen Recording** (optional): pictures of the windows in the overview and the switcher.
  Without it the overview moves the windows themselves. macOS asks to reopen the app once it is
  on; "Continue without Screen Recording" stops the asking.
- **Your Hyper key**, which must be chosen before Continue, as Raycast's Hyper Key: Caps Lock
  (recommended), a left or right ⌃ ⇧ ⌥ ⌘, or F1–F12. For Caps Lock and the function keys,
  **Quick Press**: what the key does pressed alone (nothing, the key itself, or Escape).
- **Start Mango Chutney at login**, off unless ticked (later: Settings, or `mmsg service install`).

Nothing is written and no key is moved before Continue: Mango Chutney waits for your choice
(the menu bar says so), and quitting before it just means the next start is a first start
again. Continue writes your config, starts tiling, opens this guide in your browser and turns
the window into a welcome with the two keys and **Open Your Config**. The window comes back
from the menu bar as Settings… (⌘,). If Accessibility
is on in the list but does not take (an old build), remove the row with − and allow it again.

The first start writes your config, `~/.config/mango/config.conf`: mango's own default config with
mango's keys on Hyper, so macOS's shortcuts stay as they are. Near its end are a few lines to
try, all commented out: take away a `#`, save, and the change shows at once.

## A first week

On a normal Mac you place every window yourself. A tiling window manager does it for you: each new
window takes a place next to the others, and when one closes the rest fill the space. It takes a
few days to get used to, and the mouse keeps working the whole time.

1. **Let it place your windows.** Open three or four. The default layout, tile, puts one large
   window on the left and stacks the others on the right. **Hyper N** goes to the next layout,
   **Hyper L** shows them all, and the menu bar item has them too, with the gaps and borders.
2. **Move around with the keys.** Hyper ← ↑ → ↓ focuses the window in that direction, Hyper ⇧ with
   an arrow moves it, Hyper Q closes it. Hyper and drag moves a window with the mouse; right-drag
   resizes it.
3. **Tags.** Tags are desktops that are always there: nine on every screen, each with its own
   layout. Hyper 1–9 goes to a tag, Hyper ⇧ 1–9 sends the window there, Hyper , and . go to the
   previous or next tag with windows. They do not use macOS Spaces.
4. **When a window should not be tiled.** Hyper \ floats it (or tiles it again), Hyper A maximizes,
   Hyper F is fullscreen, Hyper O keeps it on top, Hyper G shows it on every tag. Dialogs float by
   themselves.
5. **Put things away.** Hyper I sends a window to the scratchpad, Hyper Z shows or hides it,
   Hyper ⇧ I takes it back.
6. **Find a window.** Hyper ⇧ Tab puts a letter on every window; press the letter. Four fingers up
   on the trackpad shows the overview. Hyper K lists your open windows too: type part of a title.
7. **Give your apps keys** once the rest feels normal: [One key per app](#one-key-per-app).

## Keys

The default keys, all on Hyper. **Hyper K** lists them, and every other binding of your config.

| Keys | Does |
|---|---|
| Hyper K, Hyper L | every key, the layouts |
| Hyper R | reload the config |
| Hyper Return | a terminal (Ghostty, else Terminal) |
| Hyper M, Hyper Q | quit mango, close the window |
| Hyper Tab, Hyper ⇧ Tab | next window, jump to a window by its letter |
| Hyper ← ↑ → ↓ | focus the window in that direction |
| Hyper ⇧ ← ↑ → ↓ | move the window that way |
| Hyper 1–9, Hyper ⇧ 1–9 | view a tag, send the window to a tag |
| Hyper , / . | previous / next tag with windows; with ⇧ the window goes along |
| Hyper N | next layout |
| Hyper F, Hyper ⇧ F, Hyper A | fullscreen, fake fullscreen, maximize |
| Hyper \ | floating on/off |
| Hyper G, Hyper O | show on all tags, always on top |
| Hyper I, Hyper ⇧ I | minimize, restore |
| Hyper Z | scratchpad |
| Hyper E, Hyper X | scroller: full width, next width preset |
| Hyper [ / ] | focus the monitor left / right; with ⇧ the window goes there |
| Hyper W, then arrows | resize the window (⇧: move it); Escape or Return leaves |
| Hyper + drag, Hyper + right-drag | move, resize a window |
| drag a window's edge | resize it (mango's border resize: a 10-point strip inside the edge; a tiled window's edges that face another window, every edge of a floating one) |
| Escape, in the overview | leave it; Hyper + arrows move between the cards, a click picks one |
| Hyper + scroll | previous / next tag |
| 3 and 4 fingers | focus, tags, overview |

Bindings are mango's: `bind[flags]=MODIFIERS,KEY,COMMAND,PARAMETERS`, with mango's flags and key
modes ([mango's Key Bindings](https://mangowm.github.io/docs/bindings/keys)). On a Mac `SUPER` is
⌘, `ALT` is ⌥, `CTRL` is ⌃, `SHIFT` is ⇧, and `HYPER` is
[`chutney_hyper_modifier`](#the-hyper-key). Key names are mango's (`a`–`z`, `Return`, `Escape`,
`Left`, `F1`, …), found on the keyboard layout in use; `code:N` is a macOS key code.

**mango's own keys.** mango's default config has its bindings on ⌥, ⌃ and ⌘ (⌥ arrows, ⌃ 1–9,
⌘ N, ⌘ M …). On a Mac those belong to apps and to macOS too: ⌘M, ⌘N, ⌘R, ⌘Tab, ⌘ with arrows (start
and end of a line), ⌥ with letters and digits (the characters it types, such as @ and {), ⌃ with
arrows (Spaces). That is why your config has them on Hyper: `var=mod,HYPER` and
`var=mods,HYPER+SHIFT` at the top of its key bindings, and two lines move them all elsewhere.

## The Hyper key

A Mac has no Hyper key. In a binding `HYPER` means the modifiers `chutney_hyper_modifier` names,
held together, and `chutney_hyper_key` makes one key hold them: chosen on the first start, and
later in Settings (⌘, in the menu bar), the same window. It is done with macOS's own key mapping (`hidutil`),
no Karabiner needed, and only Mango Chutney sees the key as Hyper. Key moves of your own in that
mapping stay as they are, and are all that is left when Mango Chutney quits.

The first start writes your key in `config.conf`; a key chosen later in Settings is kept in
`chutney_menu.conf`, which is read last and wins. To go back to the one in `config.conf`, delete
the `chutney_hyper_key` line in `chutney_menu.conf`. Settings can keep a key only with
`chutney_menu_config` set, as in the default config.

| Setting | Default | Description |
| :--- | :--- | :--- |
| `chutney_hyper_modifier` | `super+ctrl+alt` | What `HYPER` means in a binding, in mango's modifier names: ⌃⌥⌘. Leave `shift` out if you use `HYPER+SHIFT` bindings, as the default config does. |
| `chutney_hyper_key` | unset (the first start: your choice) | One key held as `HYPER`, as Raycast's Hyper Key: `caps_lock`; `left_` or `right_` `control`, `shift`, `option` or `command`; `f1` … `f12`. That key no longer does what it did (Caps Lock types no capitals). Unset: hold the modifiers together. |
| `chutney_hyper_tap` | `none` | Raycast's Quick Press: Caps Lock or a function key that is Hyper, pressed and let go alone: `none`, `original` (Caps Lock's lock, or the function key) or `escape`. A modifier has none. |

```ini
# Caps Lock held is Hyper; tapped alone it is Escape
chutney_hyper_key=caps_lock
chutney_hyper_tap=escape
```

mango's own `xkb_rules_options=caps:hyper` makes Caps Lock Hyper too.

## The menu bar

The mango in the menu bar shows the tags in view, the layout and the key mode. With more than one
display it shows every monitor, in the order the displays stand, the selected one in full and the
others dimmed: macOS draws the same item on every display. Its menu holds:

- **The layout panel.** The 14 layouts, each drawn as an icon by mango's own layout code; a click
  sets it for the tag in view. The tick in a layout's corner puts it in or out of mango's
  `circle_layout` (the layouts Hyper N goes round and Hyper L shows). Below: the master width and
  count and the layout's own options (new is master, scroller widths, dwindle's splits, the tab
  modes, …), by mango's names.
- Reload Config (⌘R). Your config opens from Settings (**Open Your Config**).
- At the bottom, the version running (as `mango -v` and `mmsg get version`).
- **Settings… (⌘,)**, the first start's window, in two tabs. **General**: the permissions, your
  Hyper key and Quick Press, the two keys to remember and Start at Login, then **Your config**:
  open it, mango's documentation (every key the config has) and this guide. **Look**: the gaps
  (inner and outer, with a preview at the screen's scale; on a grid tag only the direction
  mango's grid reads, its horizontal gaps all round, or vertical_grid's vertical ones;
  `smart_gaps` and the special tag's `special_gap_…` are the config's), `border_px`,
  animations on or off with `animation_type_open` (slide, zoom or none) and
  `tag_animation_direction`, and the menu bar's own look. Durations and curves are the config's. Each choice is kept as you make it.
- Restart and Quit.

The panel sends only mango's own dispatchers (`setlayout`, `setmfact`, `incnmaster`, `setoption`),
as a bar would over IPC. Its changes are kept in `chutney_menu.conf`, which the config reads last,
so they survive a reload and win over your own lines. Delete a line in `chutney_menu.conf` to give
the key back to your config. Your own config is never written.

| Setting | Default | Description |
| :--- | :--- | :--- |
| `chutney_menu_bar` | `0` | The menu bar item: the tags in view, the layout and the key mode, with the layout panel in its menu. |
| `chutney_menu_bar_tag_style` | `square` | The tags: `square`, `circle` or `text` (`[1] 2` with mango's layout symbol in place of the icon). |
| `chutney_menu_bar_logo` | `color` | The mango logo: `color`, `mono` (its shape in the menu bar's colour) or `0`. |
| `chutney_menu_bar_layout` | `1` | The layout's icon. |
| `chutney_menu_bar_mode` | `1` | The key mode, always: an outlined M for `default`, another mode's first letter filled. `0`: only a mode other than `default`. |
| `chutney_menu_config` | empty | The file the panel keeps its changes in, relative to `config.conf`'s folder (or a full path). Read it with `source_optional`, last. Empty: the panel's changes last until the next reload. |

## The palettes

### Hotkeys palette

**Hyper K** (`chutney_toggle_hotkeys_palette`), after Omarchy's Super K: every binding, open window
and installed app, searched as you type.

- **Search** finds a binding by what it does, its keys, its dispatcher or a word for it ("close",
  "workspace", "float"), and an app by its name. Letters in order find a word too ("scrlr" finds
  scroller).
- **It knows what mango looks like now:** a binding shows its state (floating on, the layout in
  view) and is dimmed when it would do nothing.
- **Windows** are rows: Return goes to the window, on whatever tag it is.
- **Installed apps** come from Spotlight, ordered by how often you use them. An app a key opens is
  one row, and the footer says what Return does now ("go to Arc on tag 2").
- **Without a search** the bindings are grouped by what they do; the rows used most come first.
  Nothing scrolls: a long group gets two columns.
- **A number after a colon** is a value: `every col :60` sets every column to 60 % with
  `chutney_set_proportion_all`, `width :0.5` the focused one with `set_proportion`.
- The footer shows the binding's key, to learn it for next time.

Keys: ↑ ↓ (or ⇥, ⌃N/⌃P) move, Return runs, → opens a group, ← or ⌫ goes back, Esc clears the
search, closes the group, then the palette.

| Setting | Default | Description |
| :--- | :--- | :--- |
| `chutney_hotkeys_apps` | `1` | Installed apps (from Spotlight) in the search. |

### Layout palette

**Hyper L** (`chutney_toggle_layout_palette`): the layouts of mango's `circle_layout` as icons,
drawn by mango's own layout code, in its order (all 14 without it). The arrows move, Return sets the
layout for the tag in view (`setlayout`), Esc closes. Tab shows all 14 with their ticks; Space or a
click on a tick puts a layout in or out of `circle_layout`.

| Setting | Default | Description |
| :--- | :--- | :--- |
| `chutney_layout_palette_keys` | `left,down,up,right` | Four keys that move the selection, in the order left, down, up, right (`h,j,k,l` for vim's); the arrows always work. |

Both palettes look as Spotlight does: mango has no palette whose look they could take.

## One key per app

`chutney_focus_app` gives an app a key of its own, after AeroControl. The app's windows are looked
for on every tag and monitor (not minimized, hidden or on the special tag).

| The app has | The key |
| :--- | :--- |
| no window | starts it (`open -b <bundle id>`, or the command given) |
| one window | focuses it, viewing its tag |
| two, one of them focused | focuses the other |
| two or more, none focused | focuses the one used last, as ⌘Tab does |
| three or more, one focused | focuses the one used before it (none: the next one) |

The apps' keys are best in a key mode of their own, entered with one key. `bindc` (mango's `c`
flag) lets the app's key and the mode's exit share the key:

```ini
bind=HYPER,a,setkeymode,apps
key_mode=apps
bindc=none,s,chutney_focus_app,com.apple.Safari
bindc=none,s,setkeymode,default
bindc=none,v,chutney_focus_app,com.microsoft.VSCode
bindc=none,v,setkeymode,default
bind=none,Escape,setkeymode,default
key_mode=default
```

Hyper A, then S: Safari. An app's bundle id: `osascript -e 'id of app "Safari"'`.

### The port's dispatchers

| Command | Param | Description |
| :--- | :--- | :--- |
| `chutney_focus_app` | `bundle id or app name`[, `command`] | One key per app: start it or go to its window. The command, when given, starts it. |
| `chutney_restart` | - | mango's `quit`, with hidden windows left hidden: the next mango restores them (`make install` and `mmsg service restart` use it). |
| `chutney_set_proportion_all` | [`proportion`] | `set_proportion` for every window of the tag in view, in the scroller. Without a value, back to `scroller_default_proportion`. |
| `chutney_toggle_hotkeys_palette` | - | The hotkeys palette. |
| `chutney_toggle_layout_palette` | - | The layout palette. |

## Configuration

The config is mango's: the same file, format and names, read again each time you save it. All the
files are in `~/.config/mango`, read in this order:

| File | Written by | What |
| :--- | :--- | :--- |
| `config.conf` | you | Your config. The first start writes mango's own `assets/config.conf` with its bindings on Hyper, then Mango Chutney's own keys from their marker line to the end, then the first lines to try. Your own settings go there, between the line that reads `chutney_theme.conf` (so a colour of yours wins) and the one that reads `chutney_menu.conf`. |
| `chutney_theme.conf` | Mango Chutney | With `chutney_style=1`, macOS's colours for mango's colour keys. Not for editing. |
| `chutney_menu.conf` | Mango Chutney | The menu's choices, read last, so they win. Delete a line to give the key back to `config.conf`. |

A key set twice takes its last value. Bindings add up instead: of two on the same keys the first one
runs, and mango reports the conflict. mango's TOML format, `config.toml`, is read when there is no
`config.conf`. `mango -c <file>` reads another file.

`mango -p` checks a config: what has no effect on macOS (blur, shadows, opacity, …), which bindings
do nothing, and which names are Mango Chutney's own.

**Mango Chutney's own options** are all named `chutney_`, and each is off, or mango's behaviour,
when it is absent: delete them and Mango Chutney behaves as mango, with the config's keys still on
`HYPER` (then ⌃⌥⌘ held). mango itself reports each as an unknown keyword and skips the line.

| Setting | Default | Description |
| :--- | :--- | :--- |
| `chutney_ignore_apps` | empty | Bundle ids of apps whose windows mango never manages, comma separated. Several lines add up; an empty value clears the list. To float or place an app's windows instead, use mango's [window rules](https://mangowm.github.io/docs/window-management/rules) (`appid:` is the bundle id). |

## Theming

mango's own theming keys (`border_px`, the colours, the `*_decorate_*` keys) are described in
mango's [Theming](https://mangowm.github.io/docs/visuals/theming). These are the port's.

| Setting | Default | Description |
| :--- | :--- | :--- |
| `chutney_style` | `0` (the default config: `1`) | The tab and group bars, jump labels and switcher in the macOS look, wherever no `*_decorate_*` key sets mango's; mango's colours in macOS's; the borders' corners as the windows' own. The bars, the switcher and the palettes (always) stand on Liquid Glass on macOS 26 and later, on the system's blur before it. |
| `chutney_border_unfocused` | `1` | Borders around unfocused windows too. `0`: only the focused window has one. |
| `chutney_floating_color` | unset | One border colour for floating windows (`0xRRGGBBAA`). Empty or `none`: mango's colours. |
| `chutney_physical_pixels` | `0` | `border_px` and the gaps in the screen's pixels rather than points: `border_px=3` is 1.5 points on a Retina screen, as on mango with scale 2. |
| `chutney_overlap_warning` | `0` | A tiled window its app keeps larger than its tile (Claude, VS Code and other apps with a minimum size) goes over its neighbour, as always; with this key the menu bar draws its tag in orange. The menu says which windows go over by how much, and offers to move the one that goes over most to the first empty tag (`tagsilent`) or float it (`togglefloating`), each one of mango's commands run when picked. |
| `chutney_tab_bar_app_icons` | `0` | In mango's `monocle_tab_mode` and `deck_tab_mode`: the app's icon before each tab's title. |
| `chutney_tab_bar_shortcuts` | `0` | ⌘1–9 picks a tab while a tab bar is shown; the numbers show while ⌘ is held. |

**Colours.** With `chutney_style=1` Mango Chutney writes `chutney_theme.conf`, and again when the
accent colour or light/dark mode changes, then reloads the config: `focus_color` and `split_color`
are your accent colour, `drop_color` too at mango's alpha, `border_color` the system grey,
`root_color` the window background, and `urgent_color`, `maximized_screen_color`,
`scratchpad_color`, `global_color` and `overlay_color` the system red, green, blue, purple and
teal. A colour of your own goes after the `source_optional=chutney_theme.conf` line, and wins.

**Corners.** macOS cannot clip a window as mango clips a Wayland surface, so a border is drawn
around the window. With `chutney_style=1` its inner edge follows the window's own corners: 16
points on macOS 27 and 10 on Sonoma and Sequoia (on macOS 26 the corners vary from window to window,
so some will not match). Without it the corners are mango's `border_radius`.

## Coming from AeroSpace or yabai

Mango Chutney works as AeroSpace does underneath: it moves windows through the Accessibility API,
hides windows on other tags in a corner of the screen, and needs no change to SIP and no scripting
addition. Which windows are tiled and which float is decided by AeroSpace's own rules, ported as
they are. The rest is mango: no tree of containers, but layouts that the windows fill in order, and
no macOS Spaces, but nine tags on every screen.

| AeroSpace | yabai / skhd | Mango Chutney |
|---|---|---|
| `~/.aerospace.toml` | `~/.yabairc`, `~/.skhdrc` | `~/.config/mango/config.conf`, reloaded on save |
| `workspace 2` | `space --focus 2` | `view,2` |
| `move-node-to-workspace 2` | `window --space 2` | `tag,2` (`tagsilent,2` stays where you are) |
| `focus left` | `window --focus west` | `focusdir,left` |
| `move left` | `window --warp west` | `move_client,left` |
| | `window --swap west` | `exchange_client,left` |
| `layout tiles` | `space --layout bsp` | `setlayout,tile` or `dwindle` |
| `layout accordion` | `space --layout stack` | `setlayout,monocle` or `deck`, with a tab bar |
| `layout floating tiling` | `window --toggle float` | `togglefloating` |
| `fullscreen` | `window --toggle zoom-fullscreen` | `togglemaximizescreen` (`togglefullscreen` for fullscreen) |
| `resize smart` | `window --ratio`, `--resize` | `setmfact`, `resizewin` |
| | `window --toggle sticky` | `toggleglobal` |
| | `window --display east` | `tagmon,right` |
| `[mode.window.binding]` | skhd modes | `key_mode=window` and `setkeymode,window` |
| `[[on-window-detected]]` | `rule --add app=…` | `window_rule=`, with the bundle id as `app_id` |
| `aerospace` | `yabai -m query`, `signal` | `mmsg get`, `mmsg watch`, `mmsg dispatch` |

**What they do not have:** 14 layouts, each tag with its own (try scroller: windows in a row you
scroll through); the overview (four fingers up, or `enable_hotarea=1` for a screen corner); jump
labels; scratchpads, and named ones that start their app; two tags at once (`toggleview`,
`toggletag`); groups with a tab bar (`groupjoin,left`); a switcher with pictures
(`switcher,all_tag_next`); borders and animations; trackpad gestures; `tag_carousel=1`.

**What yabai does that this does not:** its scripting addition reaches into the Dock. Mango
Chutney cannot set other apps' opacity or shadows, and does not create or move macOS Spaces.

There is no converter: start from the default config, turn your rules into `window_rule` lines and
your modes into `key_mode` blocks. `mango -p` tells you what does not work on macOS.

## On macOS

macOS draws and manages other apps' windows, the keyboard, the pointer and the displays itself.
What follows from that:

- **Hidden tags:** windows on tags not in view are parked in a bottom corner with a 1-pixel sliver
  showing, as AeroSpace and rift do. Each display needs a free bottom corner, so arrange displays
  with every one having a bottom corner that touches no other.
- **Windows that will not get smaller** keep their own size and overlap their neighbour, the
  focused one on top, as in AeroSpace, yabai and Amethyst.
- **Animations** move real windows, smoother in light apps than in heavy ones. There are no close
  animations.
- **Blur, shadows, dimming, other apps' opacity,** input and display settings, the layer shell:
  accepted so a mango config loads; [Compatibility](compatibility.md) lists them.
- **Spaces:** use one Space per display and switch tags instead. Turn off *Displays have separate
  Spaces* (System Settings › Desktop & Dock). A window in native fullscreen lives in its own Space
  and is left alone until it comes back.
- **Mission Control** draws the parked windows tiny; *Group windows by application* helps:
  `defaults write com.apple.dock expose-group-apps -bool true && killall Dock`.
- **Trackpad gestures:** macOS uses 3- and 4-finger swipes for Spaces and Mission Control; turn
  them off in System Settings › Trackpad to use mango's.
- **Secure Input:** while an app holds Secure Keyboard Entry (a password field), macOS hides key
  presses from Mango Chutney too.
- **Displays and sleep:** a disconnected display's windows move to another and back when it
  returns; after sleep the windows are picked up again within a few seconds. A restart keeps every
  window's tag, display and floating state for the login session.
- **A window stuck in a corner** (after `kill -9` or a crash, when Mango Chutney could not put
  it back): start Mango Chutney again and quit it from the menu bar, which brings every window
  it hid back into view. Without it (uninstalled), click the app and choose Window › Center
  (macOS 15 and later), or drag the sliver into view.
- **The Hyper key still Hyper** (after `kill -9` or a crash): the key keeps its move until Mango
  Chutney starts again, which clears it, or until macOS restarts.
- **Arc and other Chromium browsers:** Chromium stops drawing a window macOS calls hidden, and a
  window parked for a hidden tag is hidden to macOS. Given a new size there, an Arc window keeps its
  old, smaller picture until it is shown, so its card in the overview is small. Quit Arc and start
  it with Chromium's switch, and it keeps drawing:
  `open -a Arc --args --disable-backgrounding-occluded-windows`. A start from the Dock or at login
  does not carry the switch. Hidden Arc windows then use a little more power.

## mmsg

mango's IPC client, over the socket `/tmp/mango-$USER.sock`, with mango's commands and JSON.

```bash
mmsg get all-tags
mmsg get focusing-client
mmsg watch tags "Built-in Retina Display"
mmsg dispatch setlayout,scroller
mmsg binds                  # the active bindings, readable
mmsg reload
mmsg service install|uninstall|start|stop|restart|status
```

`mmsg --help` lists every command. `mmsg service install` writes
`~/Library/LaunchAgents/dev.mangochutney.plist` and loads it; it restarts Mango Chutney only after a
crash, so Quit and `mmsg service stop` stay stopped.

## Installing from a zip or from source

**From a release zip:** unzip `MangoChutney-<version>.zip` into `/Applications`. It is signed but
not notarized, so remove the quarantine attribute first:

```bash
xattr -dr com.apple.quarantine "/Applications/Mango Chutney.app"
```

**From source**, with a Swift 5.10+ toolchain (`make test` needs Xcode):

```bash
make install
```

This builds `Mango Chutney.app` into `/Applications` and links `mango` and `mmsg` into
`~/.local/bin`. The Makefile signs ad-hoc, so macOS forgets the Accessibility grant on every
rebuild; a fixed identity keeps it: `CODESIGN_IDENTITY=…` in a `local.mk` beside the Makefile.
