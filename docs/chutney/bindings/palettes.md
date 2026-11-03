---
title: Palettes
description: The hotkeys palette and the layout palette.
---

Two palettes, each opened by a dispatcher on a key of your own.

## Hotkeys Palette

`chutney_toggle_hotkeys_palette` (Hyper K in the default config), after Omarchy's Super+K: every
binding, open window and installed app, searched as you type.

- A binding shows its state (floating on, the layout in view) and is dimmed when it would do
  nothing now. Return runs it, as its key would; the footer shows its key, to learn it.
- An app with a key is one row, its binding's ("focus or open …"), with where its windows are
  ("tag 1, 3"). Selected, the footer says what Return does now ("go to Arc on tag 2").
- Open windows are rows too: Return goes to the window, on whatever tag it is. A window of an
  app whose row is found shows only when the search is in its title beyond the app's
  name.
- Without a search the bindings are grouped by what they do, whatever key mode they are in; the
  rows used most come first.
- A number after a colon is a value for the row, not a search word: `every col :60` sets every
  column to 60 % with `chutney_set_proportion_all`, `width :0.5` the focused one with
  `set_proportion`. Over 1 is a percentage; the share is held to mango's 10 to 100 %. The footer shows what Return runs. These two are
  found by a search even without a key.

Keys: ↑ ↓ (or ⇥, ⌃N/⌃P) move, Return runs, → opens a group, ← or ⌫ goes back, Esc clears the
search, closes the group, then the palette.

| Setting | Default | Description |
| :--- | :--- | :--- |
| `chutney_hotkeys_max_rows` | `14` | The most rows shown (3–60); a long group gets two columns, nothing scrolls. |
| `chutney_hotkeys_recent` | `4` | The rows used most, on the front page (0–20; `0`: none). |
| `chutney_hotkeys_width` | `680` | The palette's width in points (360–3000). |
| `chutney_hotkeys_apps` | `1` | Installed apps (from Spotlight) in the search. |

With [`chutney_style`](../visuals/theming#macos-look) it looks as Spotlight does; otherwise it has
the port's own look in mango's colours (`root_color` behind, `border_color` around, `focus_color`
for the selection).

## Layout Palette

`chutney_toggle_layout_palette` (Hyper L in the default config, or the menu bar's Layouts…): the
layouts of mango's `circle_layout` as icons, drawn by mango's own layout code, in its order. Without
`circle_layout` all 14.

The arrows move, Return sets the layout for the tag in view (`setlayout`), Esc closes. Tab shows all
14 with their ticks; Space or a click on a tick puts a layout in or out of `circle_layout`.

| Setting | Default | Description |
| :--- | :--- | :--- |
| `chutney_layout_palette_keys` | `left,down,up,right` | Four keys that move the selection, in the order left, down, up, right (`h,j,k,l` for vim's); the arrows always work. |
| `chutney_layout_palette_width` | `560` | The palette's width in points (300–2000); its cells and icons follow. |
