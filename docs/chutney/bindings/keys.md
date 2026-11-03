---
title: Key Bindings
description: HYPER, one key per app, and the port's dispatchers.
---

Bindings are mango's: `bind[flags]=MODIFIERS,KEY,COMMAND,PARAMETERS`, with mango's flags and key
modes. See mango's [Key Bindings](https://mangowm.github.io/docs/bindings/keys) for the syntax and
mango's dispatchers. This page has what the port adds.

## Modifiers

On a Mac mango's modifiers are these keys:

| mango | Mac |
| :--- | :--- |
| `SUPER` | ⌘ Command |
| `ALT` | ⌥ Option |
| `CTRL` | ⌃ Control |
| `SHIFT` | ⇧ Shift |
| `HYPER` | `chutney_hyper_modifier` |

A Mac has no Hyper key. In Mango Chutney `HYPER` in a binding means the modifiers
`chutney_hyper_modifier` names, held together.

| Setting | Default | Description |
| :--- | :--- | :--- |
| `chutney_hyper_modifier` | `super+ctrl+alt` | What `HYPER` means in a binding, in mango's modifier names: ⌃⌥⌘ unless you choose otherwise. Leave `shift` out if you use `HYPER+SHIFT` bindings (as `mac-bindings.conf` does). |

```ini
# your choice: ⌃⌥⌘⇧
chutney_hyper_modifier=super+ctrl+alt+shift
bind=HYPER,k,chutney_toggle_hotkeys_palette
```

> **Tip:** one key for Hyper: mango's own `xkb_rules_options=caps:hyper` makes Caps Lock held
> Hyper, for Mango Chutney only. For other apps to get ⌃⌥⌘ too, use the Karabiner-Elements rule in
> `Resources/karabiner/mango-hyper.json` instead (not both).

## One Key per App

`chutney_focus_app` gives an app a key of its own, after AeroControl. The app's windows are looked
for on every tag and monitor (not minimized, hidden or on the special tag).

| The app has | The key |
| :--- | :--- |
| no window | starts it (`open -b <bundle id>`, or the command given) |
| one window | focuses it, viewing its tag |
| two, one of them focused | focuses the other |
| two or more, none focused | focuses the one used last, as ⌘Tab does |
| three or more, one focused | focuses the one used before it (none: the next one) |

To choose among many windows use mango's own `toggleoverview` or `togglejump`.

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

Hyper A, then S: Safari.

## Tabs

With `chutney_tab_bar_shortcuts=1` ⌘1–9 picks a tab while a tab bar is shown (see
[Theming](../visuals/theming#tab-bars)).

## Dispatchers List

| Command | Param | Description |
| :--- | :--- | :--- |
| `chutney_focus_app` | `bundle id or app name`[, `command`] | One key per app: start it or go to its window (above). The command, when given, starts it. |
| `chutney_restart` | - | mango's `quit`, with hidden windows left hidden: the next mango restores them from the saved layout (`make install` and `mmsg service restart` use it). |
| `chutney_set_proportion_all` | [`proportion`] | `set_proportion` for every window of the tag in view, in the scroller. Without a value, back to `scroller_default_proportion`. |
| `chutney_toggle_hotkeys_palette` | - | The hotkeys palette: every binding, window and app, searched as you type (see [Palettes](palettes#hotkeys-palette)). |
| `chutney_toggle_layout_palette` | - | The layout palette: `circle_layout`'s layouts as icons (see [Palettes](palettes#layout-palette)). |
