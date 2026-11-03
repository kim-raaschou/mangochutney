# Mango Chutney guide

What is particular to the Mac. Everything else is mango's: its layouts, tags, rules,
dispatchers and config keys are described in [mango's documentation](https://mangowm.github.io/),
and they work here as they do there. [Compatibility](compatibility.md) lists what macOS cannot do.

New to tiling? Start with [Coming from macOS](chutney/from-macos.md). Used AeroSpace or yabai? See
[Coming from AeroSpace](chutney/from-aerospace.md) or [Coming from yabai](chutney/from-yabai.md).

- [Installation](#installation)
- [Default keys](#default-keys)
- [The Hyper key](#the-hyper-key)
- [The menu bar and layout panel](#the-menu-bar-and-layout-panel)
- [The hotkeys palette](#the-hotkeys-palette)
- [The layout palette](#the-layout-palette)
- [Configuration](#configuration)
- [Mango Chutney's own options](#mango-chutneys-own-options)
- [How it differs from mango](#how-it-differs-from-mango)
- [Spaces, displays and sleep](#spaces-displays-and-sleep)
- [mmsg](#mmsg)
- [Development](#development)

## Installation

Requires macOS 14 or later on Apple silicon.

**With Homebrew:**

```bash
brew install --cask kim-raaschou/tap/mangochutney
```

This installs `Mango Chutney.app` and puts `mango` and `mmsg` on your `PATH`.

**From a release zip:** unzip `MangoChutney-<version>.zip` into `/Applications`. Mango Chutney is
signed but not notarized, so Gatekeeper stops the first start. Remove the quarantine attribute:

```bash
xattr -dr com.apple.quarantine "/Applications/Mango Chutney.app"
```

or start it once, then allow it in System Settings › Privacy & Security › *Open Anyway*. The
signature is there so the Accessibility grant survives updates.

**From source** (a Swift 5.10+ toolchain; the Command Line Tools are enough, `make test` needs
Xcode):

```bash
make install
```

This builds `Mango Chutney.app` into `/Applications` and links `mango` and `mmsg` into
`~/.local/bin` (put that directory in your `PATH`, or use `PREFIX=/usr/local`). It stops a
running Mango Chutney first. The Makefile signs ad-hoc by default, so macOS forgets the
Accessibility grant on every rebuild; a fixed identity keeps it:

```bash
make install CODESIGN_IDENTITY="Apple Development: you@example.com"
```

(or put `CODESIGN_IDENTITY=…` in a `local.mk` beside the Makefile).

### First start

```bash
open -a "Mango Chutney"
```

A permissions window says what Mango Chutney needs and opens the right page of System Settings:

- **Accessibility** (required): windows are managed as soon as it is allowed.
- **Screen Recording** (optional): pictures of the windows in the overview and the switcher. Without it the overview moves the windows themselves. macOS asks to
  reopen the app once it is on. "Continue without Screen Recording" stops the asking.

The window comes back from the menu bar (Permissions…). If Accessibility is on in the list but
does not take (an old build, or the old `mango` app), remove the row with − and allow it again.

On the first start the default config is written to `~/.config/mango/config.conf`: mango's own
config with mango's keys on the [Hyper](#the-hyper-key) key, so macOS's shortcuts stay as they
are (`config-mac.conf`: mango's bindings commented out, with
[`mac-bindings.conf`](../Resources/mac-bindings.conf) in their place among the port's keys at its
end). The permissions window then shows the two keys to remember, Hyper K and Hyper L, and offers:

- **Your Hyper key**, which must be chosen before Continue: Caps Lock (recommended), the right ⌘
  or the right ⌥ (`chutney_hyper_key`), and whether it is Escape pressed alone
  (`chutney_hyper_tap`). Change it later in the menu bar, Learn › Hyper Key.
- **Start Mango Chutney at login**, off unless ticked: installs the login service on Continue.
  Later it is Start at Login in the menu bar, or:

```bash
mmsg service install
```

Continue opens [Getting Started](chutney/getting-started.md) in your browser and turns the window
into a welcome: the two keys again, and **Open Your Config**, which opens `start.conf`, the first
lines to try. Each is commented out: take away the `#`, save, and the change shows at once.

Stop AeroSpace, yabai, rift or any other tiling window manager first: two managers fight over the
same windows.

## Default keys

mango's keys are on Hyper, the key you chose on the first start (Caps Lock, the right ⌘ or the
right ⌥); macOS's shortcuts stay as they are.
**Hyper K** lists them all.

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
| Hyper + scroll | previous / next tag |

### mango's own keys

The shipped `Resources/config.conf` is mango's default config with mango's own bindings:
`SUPER` is ⌘, `ALT` is ⌥, `CTRL` is ⌃. To use them, replace the `bind`, `mousebind` and
`axisbind` lines of your config with its.

| Keys | Does |
|---|---|
| ⌘ R | reload the config |
| ⌥ Return | a terminal: put your own in its place, e.g. `spawn,open -na Ghostty` (the default names one a Mac does not have) |
| ⌘ M, ⌥ Q | quit mango, close the window |
| ⌘ Tab | next window |
| ⌥ ← ↑ → ↓ | focus the window in that direction |
| ⌘ ⇧ ← ↑ → ↓ | move the window that way |
| ⌥ Tab | jump to a window by its letter |
| ⌃ 1–9, ⌥ 1–9 | view a tag, send the window to a tag |
| ⌘ ← / →, ⌃ ← / → | previous / next tag (⌃: with windows); ⌃⌘: take the window along |
| ⌘ N | next layout |
| ⌥ F, ⌥ ⇧ F, ⌥ A | fullscreen, fake fullscreen, maximize |
| ⌥ \ | floating on/off |
| ⌘ G, ⌘ O | show on all tags, always on top |
| ⌘ I, ⌘ ⇧ I | minimize, restore |
| ⌥ Z | scratchpad |
| ⌥ E, ⌥ X | scroller: full width, next width preset |
| ⌥ ⇧ ← / →, ⌘ ⌥ ← / → | focus the monitor left / right, send the window there |
| ⌃ ⇧ arrows, ⌃ ⌥ arrows | move, resize the window |
| ⌘ + drag, ⌘ + right-drag, middle click | move, resize, maximize a window |
| ⌘ + scroll | previous / next tag |
| 3 and 4 fingers | focus, tags, overview |

On a Mac these keys belong to apps and to macOS too: ⌘M, ⌘N, ⌘R, ⌘Tab, ⌘ with arrows (start and
end of a line), ⌥ with letters and digits (the characters it types, such as @ and { on many
layouts), ⌃ with arrows (Spaces), the middle click (a link in a new tab) and the trackpad's
swipes (Spaces, Mission Control). That is why the default config has them on Hyper
([`mac-bindings.conf`](../Resources/mac-bindings.conf)).

## The Hyper key

A Mac has no Hyper key. In Mango Chutney `HYPER` is `chutney_hyper_modifier`: Control+Option+Command
held together, unless you choose other modifiers in `config.conf`. The palettes are on it
(Hyper K, Hyper L), and so is [`mac-bindings.conf`](../Resources/mac-bindings.conf).

One key for it, chosen on the first start and later in the menu bar (Learn › Hyper Key):
`chutney_hyper_key` is `caps_lock`, `right_command` or `right_option`, done with macOS's own key
mapping, no Karabiner needed. `chutney_hyper_tap=escape` makes the key Escape when it is pressed
alone. mango's own `xkb_rules_options=caps:hyper` makes Caps Lock Hyper too. Only Mango Chutney
sees the key as Hyper; if other apps should get ⌃⌥⌘ too, use the Karabiner-Elements rule in
`Resources/karabiner/mango-hyper.json` instead (and no Hyper key here).

## The menu bar and layout panel

With `chutney_menu_bar=1` (on in the default config) the menu bar shows the tags in view and the
layout's icon. With more than one display it shows every monitor, in the order the displays
stand, the selected one in full and the others dimmed: macOS draws the same item on every
display. Its menu holds the **layout panel**:

- **Layouts:** all 14, each drawn as an icon by mango's own layout code; a click sets it for the
  tag in view. The tick in a layout's corner puts it in or out of mango's `circle_layout` (the
  layouts `switch_layout`, ⌘N, goes round, and the layout palette shows), saved in
  `chutney_menu.conf`; a new one goes last in the round, and the last one stays ticked. Without
  `circle_layout` all are ticked, as mango goes round all of them.
- **The layout's options:** what mango offers for it (new is master, scroller widths and centring,
  dwindle's splits, monocle's and deck's tab mode, …), and the master width and count for the
  layouts that have a master (tile, right_tile, center_tile, deck and their vertical kin).
- **Desktop:** the gaps, inner and outer, horizontal and vertical (linked or apart), for the tags
  or the special tag, with smart gaps and a preview drawn at the screen's scale; border width.
- **Menu bar:** the tags as squares, circles or text, the logo, the layout icon, the key mode; animations on/off.
- Learn: Hyper Key (Caps Lock, right ⌘ or right ⌥; Escape pressed alone; what Super and Hyper are, a click opens the keys' docs), Getting Started, mango Documentation. Then Reload Config (⌘R), Edit Config, Permissions…, Start at Login (`mmsg service install` / `uninstall`, ticked while installed), Restart and Quit Mango Chutney.

The panel only sends mango's own dispatchers (`setlayout`, `setmfact`, `incnmaster`, `setoption`),
as a bar would over IPC. Its changes are kept in `~/.config/mango/chutney_menu.conf`
(`chutney_menu_config`), which the config reads last with mango's `source_optional`, so they
survive a reload. Where they overrule your config (any file it reads before
`chutney_menu.conf`), the panel says so: each key, the menu's value and what your config says on
which line. `mango -p` lists them too. To give a key back to your config, delete its line in
`chutney_menu.conf`. Your own config is never written.

## The hotkeys palette

**Hyper K** (`chutney_toggle_hotkeys_palette`) opens a palette with every binding, open window and
installed app. Type to search; the best match comes first.

- **Search** finds a binding by what it does, its keys, its dispatcher or a word for it ("close",
  "workspace", "float"), and an app by its name ("arc" finds the key that opens Arc). Letters in
  order find a word too ("scrlr" finds scroller).
- **It knows what mango looks like now:** a binding shows its state (floating on, the layout and
  tags in view) and is dimmed when it would do nothing (no window, one monitor, another layout's).
- **The rows you use most** come first on the front page.
- **Windows** are rows too: Return goes to the window, on whatever tag it is.
- **Installed apps** come from Spotlight, ordered by how often you use them, with their icons.
  An app a key opens is one row, its binding's ("focus or open …"). Selected, its footer says what
  Return does now ("start Teams", "go to Arc on tag 2", "the other Code window", "choose among
  3 Ghostty windows"), beside its key. Its windows are rows of their own only when the search is
  in their title beyond the app's name.
- **Without a search** the bindings are grouped by what they do (Windows, Apps, Focus, Move &
  swap, Tags, Layout, Window, …), whatever key mode they are in; a key in a mode shows the key
  that enters it (`Hyper A › A`). Runs on the digits are one row: type the digit.
- **Nothing scrolls:** the palette is as tall as its rows; a long group gets two columns.
- The footer says what Return does, and for a binding its key, to learn it for next time.

Keys: ↑ ↓ (or ⇥, ⌃N/⌃P) move, Return runs, → opens a group, ← or ⌫ goes back, Esc clears the
search, closes the group, then the palette.

With `chutney_style=1` it looks as Spotlight does (the system's material and colours, your accent
colour); otherwise it has the port's own look, after Omarchy's menus, in mango's colours
(`root_color` behind, `border_color` around, `focus_color` for the selection). The menu's panel
and the layout palette mark with the same colour.

## The layout palette

**Hyper L** (`chutney_toggle_layout_palette`, or the menu's Layouts…) opens the layouts of mango's
`circle_layout` as icons, each drawn by mango's own layout code, in its order and five a row (the
menu's ticks set it), in rows as even as five a row allows and centred (six are 3 + 3). Without
`circle_layout` it shows all 14 in a 5×3 grid, the vertical variants under the horizontal ones.
Tab shows all 14 with their ticks; Space or a click on a tick puts the selected layout in or out
of `circle_layout`, as the menu's ticks do, and Tab goes back. A click on a layout sets it. The layout in view is selected when it opens. The arrows move the selection
(`chutney_layout_palette_keys=h,j,k,l` adds vim's keys, or any four), Return sets the layout for
the tag in view with mango's `setlayout`, Esc closes. It only navigates: no search. With
`chutney_style=1` it has the macOS look, as the hotkeys palette. `chutney_layout_palette_width` sets
its size; the icons follow.

## Configuration

The config is mango's: the same file, format and names. You edit `config.conf`, and
`start.conf` if you like; the other two are written by Mango Chutney and read last.

| File | Who writes it | What |
|---|---|---|
| `~/.config/mango/config.conf` | you | Your config. The default is mango's own `assets/config.conf` with its bindings moved to Hyper (`config-mac.conf`), and then Mango Chutney's own keys from their marker line to the end: the menu bar, the palettes on Hyper K and Hyper L, the macOS look (the rest, with their defaults, are in `docs/chutney`). Your own settings and bindings go above the lines at its end that read the files below. Delete the port's keys for plain mango. What does nothing on macOS (blur, shadows, opacity, trackpad, …) is read and ignored; `mango -p` lists it. |
| `~/.config/mango/chutney_theme.conf` | Mango Chutney | With `chutney_style=1`, mango's colours in macOS's: `focus_color` your accent colour, `border_color` and `root_color` the system's grey and window background, the others its red, green, blue, purple and teal. Written at start and again when you change the accent colour or light/dark (then the config is reloaded, as mango's `reload_config`, so `exec` lines run again). Read after mango's example colours; a colour of your own goes after the `source_optional=chutney_theme.conf` line. `mango -p` lists the colours it draws. |
| `~/.config/mango/start.conf` | you | The first lines to try, all commented out: gaps, border width and colour, a tag's layout, a key for an app. Written on the first start and opened from the welcome window; read after `chutney_theme.conf`, so a colour there wins. Delete it if you like; `source_optional` skips a missing file. |
| `~/.config/mango/chutney_menu.conf` | Mango Chutney | The layout panel's changes, read last, so they win. Delete a line to give the key back to `config.conf`. |

A config from before 0.2 has the port's keys in a `chutney.conf` of its own, read by
`source_optional=chutney.conf` at the end of `config.conf`. It keeps working as it is.
| `~/.config/mango/config.toml` | mango's TOML format, read when there is no `config.conf` (ported line for line from mango's reader; `.conf` and `.toml` files can source each other). |

`mango -p` checks a config and lists what has no effect on macOS, which bindings do nothing and
which names are Mango Chutney's own. Like mango it ignores `XDG_CONFIG_HOME`; `mango -c <file>`
reads another file.

- **Modifiers:** `SUPER` is Command, `ALT` is Option, `CTRL` is Control, `HYPER` is
  `chutney_hyper_modifier`.
- **Key names** in `bind=` are mango's (`a`–`z`, `Return`, `Escape`, `Left`, `F1`, …), found on
  the keyboard layout in use; `code:N` is a macOS key code (`code:36` is Return).
- **Order:** a key set twice takes the last value, so `chutney_theme.conf` and
  `chutney_menu.conf`, read last, win over the lines above them. Bindings add up instead: of two on the same keys the first one
  runs, and mango reports the conflict.

## Mango Chutney's own options

Not in mango: mango itself reports each as an unknown keyword and skips it. Unset, mango behaves as
mango does. Each `chutney_` key and dispatcher is described in [Mango Chutney's docs](chutney/index.md),
laid out as mango's own:

- [Basics](chutney/configuration/basics.md): `chutney_menu_config`, `chutney_ignore_apps`.
- [Theming](chutney/visuals/theming.md): `chutney_style` and its colours, borders, tab bars.
- [Menu Bar](chutney/visuals/menu-bar.md): the `chutney_menu_bar*` keys.
- [Key Bindings](chutney/bindings/keys.md): `HYPER` (`chutney_hyper_modifier`), `chutney_focus_app`,
  the dispatchers.
- [Palettes](chutney/bindings/palettes.md): the `chutney_hotkeys_*` and `chutney_layout_palette_*` keys.

mango's own keys and dispatchers are in [mango's documentation](https://mangowm.github.io/docs).

## How it differs from mango

macOS draws and manages other apps' windows, the keyboard, the pointer and the displays itself.
What follows from that:

- **Hidden tags:** windows on tags not in view are parked in a bottom corner with a 1-pixel sliver
  showing, as AeroSpace and rift do.
- **Windows that will not get smaller:** mango gives a tiled window its tile and the compositor
  clips it. A macOS app may refuse a size below its minimum; it then keeps its own size and
  overlaps its neighbour, the focused window on top, as in AeroSpace, yabai and Amethyst.
- **Animations** move real windows through Accessibility, so they are smoother in light apps than
  in heavy ones. There are no close animations: the window is gone when macOS says so.
- **Blur, shadows, dimming, other apps' opacity,** input-device and display settings, the layer
  shell, virtual terminals: accepted so a mango config loads, and listed below.
- **Native fullscreen** windows live in their own Space; Mango Chutney leaves them alone until they
  leave fullscreen.
- **Secure Input:** while an app holds Secure Keyboard Entry (a password field), macOS hides key
  presses from every app that reads the keyboard, Mango Chutney included.
- **Trackpad gestures:** macOS uses 3- and 4-finger swipes for Spaces and Mission Control; turn
  those off in System Settings › Trackpad if you use `gesturebind` (the default config has mango's
  gestures).
- **IPC** goes over a Unix socket, `/tmp/mango-$USER.sock`, with mango's commands and JSON.


[Compatibility](compatibility.md) lists every key macOS cannot do, with the reason;
[afvigelser.md](afvigelser.md) every deviation (in Danish).

## Spaces, displays and sleep

mango's tags do what macOS Spaces do, so use one Space per display and switch tags instead:

- **One Space.** Turn off *Displays have separate Spaces* (System Settings › Desktop & Dock) and
  keep to one Space. A window moved to another Space is reported closed by its app; it is taken
  in again, with its tag and place, while you are on that Space. When one display shows a native
  fullscreen window, the others go black: the price of the setting.
- **Mission Control** draws the parked windows tiny; *Group windows by application* helps:
  `defaults write com.apple.dock expose-group-apps -bool true && killall Dock`.
- **Display arrangement:** each display needs a free bottom corner to park windows in; arrange
  displays so every one has a bottom corner that touches no other.
- **Disconnecting a display** moves its windows, with their tags, to another and back when it
  returns.
- **Sleep and the lock screen** invalidate every window's Accessibility element; the windows are
  picked up again a few seconds after waking.
- **Restarting** keeps every window's tag, display and floating state for the login session
  (`~/.local/state/mango/windows.json`).
- **A window stuck in a corner** (after `kill -9`): drag the sliver into view, or start Mango
  Chutney again.

## mmsg

```bash
mmsg get all-tags
mmsg get focusing-client
mmsg watch tags "Built-in Retina Display"
mmsg dispatch setlayout,scroller
mmsg dispatch togglefloating client,12345
mmsg binds                  # the active bindings, readable
mmsg reload
mmsg service install|uninstall|start|stop|restart|status
```

`mmsg --help` lists every command. `mmsg service install` writes
`~/Library/LaunchAgents/dev.mangochutney.plist` and loads it; the agent restarts Mango Chutney only
after a crash, so `quit` and `mmsg service stop` stay stopped.

## Development

```bash
make test         # the tests (XCTest needs Xcode)
make check        # validate Resources/config.conf with the new parser
make config-diff  # compare Resources/config.conf with mango's assets/config.conf (MANGO=~/sources/mango)
make run          # run in the foreground with -d
make release      # signed with CODESIGN_IDENTITY, zipped: dist/MangoChutney-<version>.zip (+ sha256)
```

Release builds are signed with a fixed certificate (a self-made one is enough, so the
Accessibility grant survives updates) and not notarized. CI runs `make test` and `make check` on
every push.

The code is two modules:

- **`Sources/Mango`** is mango's code in Swift, function by function, with mango's names and no
  macOS framework: `Engine` (the server, clients, monitors, tags, dispatchers, focus, overview,
  switcher), `Layout` (the 14 layouts), `Model`, `Config` (mango's parser) and `IPC`.
- **`Sources/Port`** is macOS, standing where wlroots stands for mango: `macOS` (Accessibility,
  the event tap, gestures, borders and bars, animation, hiding windows, native focus) and
  `Extensions` (Mango Chutney's own, joined to mango only through `PortHooks`).
- **`Sources/MangoApp`** is the app and its menu bar; **`Sources/mmsg`** the command line client.

[plan-kerne-backend.md](plan-kerne-backend.md) describes the split (in Danish).
