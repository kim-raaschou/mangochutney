---
title: Menu Bar
description: The tags, the layout and the layout panel in the macOS menu bar.
---

Mango Chutney shows mango's tags, layout and key mode in the macOS menu bar.

| Setting | Default | Description |
| :--- | :--- | :--- |
| `chutney_menu_bar` | `0` | The menu bar item: the tags in view, the layout and the key mode, with the layout panel in its menu. |
| `chutney_menu_bar_tag_style` | `square` | The tags: `square`, `circle` or `text` (`[1] 2` with mango's layout symbol, `T`, `DW`, in place of the icon). |
| `chutney_menu_bar_logo` | `color` | The mango logo: `color`, `mono` (its shape in the menu bar's colour, as Apple's own icons) or `0`. |
| `chutney_menu_bar_layout` | `1` | The layout's icon. |
| `chutney_menu_bar_mode` | `1` | The key mode, always: an outlined M for `default`, another mode's first letter filled, so the item keeps its width. `0`: only a mode other than `default`. |

## More than one display

A bar under mango shows each output its own tags. macOS has one menu bar item and draws a copy
of it on every display, so the item shows every monitor: its tags and layout in a group, in the
order the displays stand, with a line between them. The selected monitor's group is drawn in
full and the others dimmed, as AeroSpace and rift do. With one display it looks as before.

## The layout panel

The item's menu holds the layout panel: the 14 layouts as icons, the layout's options, the gaps,
border and master settings, and the menu bar's own. It sends only mango's dispatchers
(`setlayout`, `setmfact`, `incnmaster`, `setoption`), as a bar would over IPC. Its changes are
kept in the file [`chutney_menu_config`](../configuration/basics#files) names.
