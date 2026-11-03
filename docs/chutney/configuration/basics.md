---
title: Basics
description: The port's config files, and apps mango leaves alone.
---

## Files

mango reads `~/.config/mango/config.conf`, and with `source=` and `source_optional=` the files it
names, relative to `config.conf`'s folder (see mango's
[Basics](https://mangowm.github.io/docs/configuration/basics)). The first start writes
one: mango's own default config with its bindings on Hyper (`config-mac.conf`), and then the
port's keys from their marker line to the end. Its last lines read `chutney_theme.conf`, written by Mango Chutney, then
`start.conf`, the first lines to try from the welcome window (yours), then `chutney_menu.conf`,
written by the menu, so the menu's choices win.

Your own lines go in `config.conf`, above those lines. A key set twice takes its last value; a
binding does not (the first one on the same keys runs), so a key of mango's you want elsewhere is
commented out where mango's bindings are. A config from before 0.2 reads a `chutney.conf` of its
own with `source_optional=chutney.conf`; it keeps working.

| Setting | Default | Description |
| :--- | :--- | :--- |
| `chutney_menu_config` | empty | The file the layout panel keeps its changes in, relative to `config.conf`'s folder (or a full path). Read it with `source_optional`, last, so the panel's changes survive a reload. Where they overrule a line read before it, the panel shows the key, its value and your config's line; `mango -p` lists them. Empty: the panel's changes last until the next reload. |

```ini
# config.conf, the port's keys at its end
chutney_menu_config=chutney_menu.conf
# ...
source_optional=chutney_menu.conf
```

## Apps

| Setting | Default | Description |
| :--- | :--- | :--- |
| `chutney_ignore_apps` | empty | Bundle ids of apps whose windows mango never manages, comma separated. Several lines add up; an empty value clears the list. |

```ini
chutney_ignore_apps=com.apple.FaceTime,com.example.app
```

> **Tip:** an app's bundle id: `osascript -e 'id of app "Safari"'`. To float or place an app's
> windows rather than leave them alone, use mango's
> [window rules](https://mangowm.github.io/docs/window-management/rules) (`appid:` is the bundle id).
