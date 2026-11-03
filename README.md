<div align="center">
  <img src="Resources/mango.svg" alt="Mango logo" width="120"/>

  <h1>Mango Chutney</h1>

  <p>A tiling window manager for macOS, ported from <a href="https://github.com/mangowm/mango">mango</a></p>

<img src="https://img.shields.io/badge/mango-0.18.2-orange?style=flat" alt="mango 0.18.2"/>
<img src="https://img.shields.io/badge/macOS-14%2B-blue?style=flat" alt="macOS 14+"/>
<img src="https://img.shields.io/badge/status-beta-yellow?style=flat" alt="Beta"/>

</div>

---

Mango Chutney arranges your windows in a layout and lets you work with them from the keyboard.
Open a window and it takes its place next to the others; close it and the rest fill the space.

It is a port of [mango](https://github.com/mangowm/mango), a tiling window manager for Linux.
The layouts, tags and config are mango's. On top of that it adds a few things for the Mac: a
menu bar item, a searchable list of keys, and colours that follow your system settings.

You can see the layouts at [mangowm.github.io](https://mangowm.github.io/).

> **Remember two keys.** **Hyper K** lists every key, searched by what you want to do. **Hyper L**
> picks a layout. Everything else is found from them; [Getting Started](docs/chutney/getting-started.md)
> has the rest.

## Features

- 14 layouts: tile, scroller, monocle, deck, dwindle, grid and more
- 9 tags per screen instead of desktops, each with its own layout (no macOS Spaces needed)
- floating windows, fullscreen, scratchpads, an overview and a window switcher
- a menu bar panel for layouts, gaps and borders
- Hyper K: all keys in a list you can search

## Install

```bash
brew install --cask kim-raaschou/tap/mangochutney
open -a "Mango Chutney"
```

Needs macOS 14 or later on Apple silicon. Quit any other tiling window manager first.

On first start it asks for Accessibility. Screen Recording is optional and gives the overview and
switcher pictures of the windows. Start at login is a choice on the first start, and later in the
menu bar or with `mmsg service install`.

## Keys

mango's keys are on **Hyper**: one key you choose on the first start, Caps Lock, the right ⌘ or
the right ⌥, held. It acts as ⌃⌥⌘, and macOS's own shortcuts stay as they are.

| Keys | Does |
|---|---|
| Hyper K | list all keys |
| Hyper L | pick a layout |
| Hyper ← ↑ → ↓ | focus left, up, right, down |
| Hyper 1–9 | go to tag 1–9 (Hyper ⇧ 1–9 moves the window there) |
| Hyper N | next layout |
| Hyper \ | toggle floating |
| Hyper F | fullscreen |
| Hyper Q | close window |
| Hyper drag | move window (right-drag resizes) |

mango's own keys (⌥ arrows, ⌃ 1–9, ⌘ N …) clash with Mac shortcuts; the
[guide](docs/guide.md#default-keys) says how to use them anyway.

## Config

The config is `~/.config/mango/config.conf`, mango's own format. It reloads when you save it.
Changes made from the menu bar are saved in a separate file and never touch your config.

- Coming [from macOS](docs/chutney/from-macos.md), [from AeroSpace](docs/chutney/from-aerospace.md) or
  [from yabai](docs/chutney/from-yabai.md): where to start, and what to try
- [Guide](docs/guide.md): Hyper key, menu bar, palettes, Spaces and displays
- [mango's docs](https://mangowm.github.io/): layouts, keys, window rules, all options
- [Mango Chutney's options](docs/chutney/index.md): the `chutney_` keys

## Coming from mango

Your mango config should load as it is, and `mmsg` works the same. Not everything is possible on
macOS:

<!-- mango-glance:start -->
|  | In mango | Works on macOS | Not implemented yet | Cannot work on macOS |
| --- | --- | --- | --- | --- |
| Options | 239 | 151 | 0 | 88 |
| Keywords | 18 | 14 | 0 | 4 |
| Window-rule fields | 49 | 27 | 0 | 22 |
| Dispatchers | 94 | 82 | 0 | 12 |
| Layouts | 14 | 14 | 0 | 0 |
<!-- mango-glance:end -->

Blur, shadows, other apps' opacity, input devices, display modes and the layer shell are out of
reach. Windows on hidden tags are moved to a corner of the screen.
[Compatibility](docs/compatibility.md) has the full list, and `mango -p` checks your config.

The Mac additions are all named `chutney_` and are off unless set. They stand together at the
end of `config.conf`; delete them to run plain mango.

## Status

Beta (0.0.1-20261103-beta). I use it every day, but there are rough edges. Bugs go in this repo's issues;
questions about mango itself go to [mango](https://github.com/mangowm/mango) or its
[Discord](https://discord.gg/CPjbDxesh5).

## Development

```bash
make test
make install
```

`Sources/Mango` is mango ported to Swift, without any macOS code. `Sources/Port` is the macOS
part. More in the [guide](docs/guide.md#development).

## Acknowledgements

- [mango](https://github.com/mangowm/mango) by DreamMaoMao and contributors, which this is a port
  of. The logo (`Resources/mango.svg`) is mango's (`assets/mango.svg`, see
  [mangowm.github.io/brand](https://mangowm.github.io/brand)), under mango's GPL-3.0 license.
- [dwl](https://codeberg.org/dwl/dwl), which mango is built on.
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) and [rift](https://github.com/acsandmann/rift)
  for showing how to do this on macOS. The rules for which windows are tiled and which float are
  AeroSpace's (MIT, `docs/licenses/AeroSpace-LICENSE.txt`).
- [mangobutter](https://justaguy.dev/drew/mangobutter), whose quickshell panel the layout panel is
  based on.
- [Omarchy](https://omarchy.org/) for the hotkeys palette, and AeroControl for `chutney_focus_app`.
