---
title: Theming
description: The macOS look, borders and tab bars.
---

mango's own theming keys (`border_px`, the colours, the `*_decorate_*` keys) are described in
mango's [Theming](https://mangowm.github.io/docs/visuals/theming). These are the port's.

## macOS look

| Setting | Default | Description |
| :--- | :--- | :--- |
| `chutney_style` | `0` (the shipped `config.conf`: `1`) | The tab and group bars, jump labels, switcher and palettes in the macOS look, wherever no `*_decorate_*` key sets mango's; mango's colours in macOS's, through `chutney_theme.conf`; the borders' corners as the windows' own ([Borders](#borders)). |

With `chutney_style=1` Mango Chutney writes `chutney_theme.conf` beside `config.conf`, and again
when the accent colour or light/dark mode changes, then reloads the config. It sets mango's colour
keys from the system's colours:

| mango key | macOS colour |
| :--- | :--- |
| `focus_color` | the accent colour |
| `border_color` | system grey |
| `root_color` | the window background |
| `urgent_color` | system red |
| `maximized_screen_color` | system green |
| `scratchpad_color` | system blue |
| `global_color` | system purple |
| `overlay_color` | system teal |
| `drop_color` | the accent colour, at mango's alpha (`0x55`) |
| `split_color` | the accent colour |

`config.conf` reads it with `source_optional=chutney_theme.conf` near its end. A colour of your own
goes after that line, and wins.

```ini
chutney_style=1
source_optional=chutney_theme.conf
focus_color=0xc66b25ff   # mango's orange, over macOS's accent
```

## Borders

macOS draws a window's corners itself and cannot clip a window as mango clips a Wayland
surface, so a border is drawn around the window. With `chutney_style=1` its inner edge follows the
window's own corners: 16 points on macOS 26 and later, 10 points on Sonoma and Sequoia. mango's
`border_radius` and `no_radius_when_single` are then not used. Without `chutney_style`, the corners
are mango's `border_radius`.

| Setting | Default | Description |
| :--- | :--- | :--- |
| `chutney_border_unfocused` | `1` | Borders around unfocused windows too. `0`: only the focused window has one. |
| `chutney_floating_color` | unset | One border colour for floating windows (`0xRRGGBBAA`). Empty or `none`: mango's colours. |
| `chutney_physical_pixels` | `0` | `border_px` and the gaps in the screen's pixels rather than points: `border_px=3` is 1.5 points on a Retina screen, as on mango with scale 2. |

## Tab bars

For mango's `monocle_tab_mode` and `deck_tab_mode`.

| Setting | Default | Description |
| :--- | :--- | :--- |
| `chutney_tab_bar_app_icons` | `0` | The app's icon before each tab's title. |
| `chutney_tab_bar_shortcuts` | `0` | ⌘1–9 picks a tab while a tab bar is shown; the numbers show on the tabs while ⌘ is held. |
