---
title: Mango Chutney
description: mango for macOS, and what the port adds to it.
---

Mango Chutney is [mango](https://mangowm.github.io/docs) 0.18.2 on macOS: the same dispatchers,
config keys, layouts and defaults. **Everything of mango's is described in
[mango's documentation](https://mangowm.github.io/docs).** These pages describe only what the port
adds: keys and dispatchers whose names begin with `chutney_`.

- Each `chutney_` key is off, or mango's behaviour, when it is absent. Delete them all and Mango
  Chutney behaves as plain mango.
- mango itself reports each as an unknown keyword and skips the line.
- `mango -p` checks the whole config, the port's keys too.
- What macOS cannot do of mango's is listed by `mango -p` and in
  [compatibility.md](../compatibility.md).

## The files

All in `~/.config/mango`.

| File | Written by | What it holds |
| :--- | :--- | :--- |
| `config.conf` | you | mango's own `assets/config.conf`, unchanged, then the port's keys from their marker line to the end: the palettes' bindings, the macOS look, and the two files below, read last. Your own settings go above those two lines. |
| `chutney_theme.conf` | Mango Chutney | macOS's colours for mango's colour keys, with [`chutney_style`](visuals/theming#macos-look). Not for editing. |
| `chutney_menu.conf` | Mango Chutney | What the menu bar's layout panel changes ([`chutney_menu_config`](configuration/basics#files)). Not for editing; delete a line to give the key back to `config.conf`. |

You edit one file, `config.conf`. Read in that order. A key set twice takes its last value; bindings add up instead, and of two on
the same keys the first one runs (mango reports the conflict). See
[Basics](configuration/basics) for how they are read.

## Pages

- [Coming from macOS](from-macos): a first week with tiling, one step at a time.
- [Coming from AeroSpace](from-aerospace): its commands under mango's names, and what to try next.
- [Coming from yabai](from-yabai): the same for yabai and skhd.
- [Basics](configuration/basics): the files, apps mango leaves alone.
- [Theming](visuals/theming): the macOS look, borders, tab bars.
- [Menu Bar](visuals/menu-bar): the tags, the layout and the layout panel in the menu bar.
- [Keys](bindings/keys): `HYPER`, one key per app, ⌘1–9 for tabs, the port's dispatchers.
- [Palettes](bindings/palettes): the hotkeys palette and the layout palette.
