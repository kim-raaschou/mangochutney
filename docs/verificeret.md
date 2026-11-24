# Verificeret mod mango

Hvilke af mangos filer vi har sammenlignet med vores og fundet 1:1. Reference: mango 0.18.5,
commit 21f80a9 (`~/sources/mango`). Én række pr. `.c`-fil i mangos `src/`, `mmsg/` og
`mangonag/`; en header hører til sin `.c`-fil (`client.h` til `client.c`), som dens typer står i
vores tilsvarende fil.

En fil er `1:1`, når hver af mangos funktioner i den findes hos os under mangos navn
(lowerCamelCase), eller står under "Ikke her" med hvor den er, eller hvorfor den mangler.

## Status

- **`1:1`**: hver funktion i mangos fil findes i vores med mangos navn og samme trin, i samme
  rækkefølge; hvert `not in mango` i vores fil står i `docs/afvigelser.md`; mangos opførsel er låst
  med tests, hvor det kan lade sig gøre.
- **`porten`**: mangos fil sidder på wlroots (scenen, inputenheder); hos os gør porten det bag
  grænsen (`Sources/Boundary`).
- **`ingen macOS-del`**: intet af filen findes på macOS (layer shell, Xwayland, touch, tablet,
  Wayland-protokoller), eller Swift gør det selv (`cleanup.c`'s frigørelse).
- **`ikke verificeret`**: endnu ikke sammenlignet funktion for funktion efter ombygningen.

**Fingeraftryk** er git's blob-hash (`git hash-object`) af vores fil(er), som de var, da filen blev
verificeret, de første 12 tegn, i samme rækkefølge som "Vores". Passer det ikke længere
(`git hash-object <fil> | cut -c1-12`), er filen ændret siden: verificér igen og skriv det nye
fingeraftryk og commit, eller sæt status tilbage.

**At verificere en fil:** læs mangos fil og vores side om side, funktion for funktion; ret, mærk
eller list hver forskel (CLAUDE.md regel 1); lås opførsel med tests; sæt status, commit (vores,
før verifikationens egen commit), dato og fingeraftryk (`git hash-object <fil> | cut -c1-12`).

## Filerne

| Mango | Vores | Status | Verificeret | Fingeraftryk | Ikke her | Note |
|---|---|---|---|---|---|---|
| `mangonag/mangonag.c` | `mangonag/mangonag.swift` | ikke verificeret | | | | |
| `mmsg/mmsg.c` | `mmsg/main.swift`, `mmsg/log.swift` | ikke verificeret | | | | portens kommandoer i `Sources/Port/mmsg` |
| `src/animation/client.c` | `animation/animation-client.swift` | ikke verificeret | | | | |
| `src/animation/common.c` | `animation/animation-common.swift` | ikke verificeret | | | | |
| `src/animation/layer.c` | | ingen macOS-del | | | | layer shell |
| `src/animation/tag.c` | `animation/animation-tag.swift` | 1:1 | ae2a891, 24. nov. | `2148fc6236c2` | | `prevtag` 0, `c->mon`-værn, `ov_card_tree`: §5 |
| `src/common/log.c` | `common/Log.swift` | ikke verificeret | | | | |
| `src/common/scene_node.c` | | porten | | | | scenen; `surfaceAt`, `sceneNodeSetEnabled` |
| `src/common/server.c` | `common/server.swift` | ikke verificeret | | | | |
| `src/common/util.c` | `common/util.swift` | ikke verificeret | | | | |
| `src/config/binding_parse.c` | `config/binding_parse.swift` | ikke verificeret | | | | |
| `src/config/cleanup.c` | | ingen macOS-del | | | | frigørelse: Swift's ARC |
| `src/config/conflict_check.c` | `config/conflict_check.swift` | ikke verificeret | | | | |
| `src/config/error_nag.c` | `config/error_nag.swift` | ikke verificeret | | | | |
| `src/config/error_store.c` | `config/error_store.swift` | 1:1 | ae2a891, 24. nov. | `e04f0ed36e35` | | |
| `src/config/load.c` | `config/load.swift` | ikke verificeret | | | | |
| `src/config/option_defs.c` | `config/option_defs.swift`, `config/parse.swift` | ikke verificeret | | | | `parse.h`'s typer i `parse.swift` |
| `src/config/preset.c` | `config/parse.swift` | ikke verificeret | | | | kun data |
| `src/config/reapply.c` | `config/reapply.swift` | ikke verificeret | | | | |
| `src/config/toml_parse.c` | `config/toml_parse.swift` | ikke verificeret | | | | |
| `src/config/value_parse.c` | `config/value_parse.swift` | ikke verificeret | | | | |
| `src/config/variable_expand.c` | `config/variable_expand.swift` | ikke verificeret | | | | |
| `src/config/watcher.c` | `config/watcher.swift` | ikke verificeret | | | | |
| `src/dispatch/bind.c` | `dispatch/bind.swift` | ikke verificeret | | | | |
| `src/draw/dim-node.c` | | porten | | | | `showSpecialDim` |
| `src/draw/text-node.c` | `draw/text-node.swift` | ikke verificeret | | | | noderne er portens (`MangoBarDecoration`, `MangoJumpLabel`) |
| `src/draw/title_message_bar.c` | `draw/title_message_bar.swift` | ikke verificeret | | | | |
| `src/ext-protocol/ext-workspace.c` | | ingen macOS-del | | | | Wayland-protokol |
| `src/ext-protocol/foreign-toplevel.c` | | ingen macOS-del | | | | Wayland-protokol |
| `src/ext-protocol/hdr.c` | `ext-protocol/hdr.swift` | ikke verificeret | | | | |
| `src/ext-protocol/tearing.c` | | ingen macOS-del | | | | Wayland-protokol |
| `src/ext-protocol/text-input.c` | | ingen macOS-del | | | | Wayland-protokol |
| `src/ext-protocol/xdg-activation.c` | | ingen macOS-del | | | | Wayland-protokol |
| `src/ext-protocol/xdg-output.c` | | ingen macOS-del | | | | Wayland-protokol |
| `src/input/device.c` | | porten | | | | inputenheder (`InputDevice`) |
| `src/input/keyboard.c` | `input/keyboard.swift` | ikke verificeret | | | | |
| `src/input/pointer.c` | `input/pointer.swift` | ikke verificeret | | | | |
| `src/input/switch.c` | | ingen macOS-del | | | | låg- og tablet-kontakter |
| `src/input/tablet.c` | | ingen macOS-del | | | | tablet |
| `src/input/touch.c` | | ingen macOS-del | | | | touch |
| `src/input/trackpad.c` | `input/trackpad.swift` | ikke verificeret | | | | |
| `src/ipc/ipc.c` | `ipc/ipc.swift` | ikke verificeret | | | | |
| `src/layout/arrange.c` | `layout/arrange.swift`, `layout/Layout.swift` | ikke verificeret | | | | |
| `src/layout/dwindle.c` | `layout/dwindle.swift` | ikke verificeret | | | | |
| `src/layout/horizontal.c` | `layout/horizontal.swift` | ikke verificeret | | | | |
| `src/layout/overview.c` | `layout/layout-overview.swift` | ikke verificeret | | | | |
| `src/layout/scroll.c` | `layout/scroll.swift` | ikke verificeret | | | | |
| `src/layout/vertical.c` | `layout/vertical.swift` | ikke verificeret | | | | |
| `src/main.c` | `common/server.swift` | ikke verificeret | | | | `main` og `run` er appens (`Sources/MangoApp/main.swift`) |
| `src/manage/client.c` | `manage/client.swift` | ikke verificeret | | | | |
| `src/manage/layer.c` | | ingen macOS-del | | | | layer shell |
| `src/manage/misc.c` | `manage/misc.swift` | ikke verificeret | | | | |
| `src/manage/monitor.c` | `manage/monitor.swift` | ikke verificeret | | | | |
| `src/manage/tab.c` | `manage/tab.swift` | ikke verificeret | | | | |
| `src/manage/xwayland_primary.c` | | ingen macOS-del | | | | Xwayland |
| `src/overview/overview.c` | `overview/overview.swift` | ikke verificeret | | | | |
| `src/switcher/switcher.c` | `switcher/switcher.swift` | ikke verificeret | | | | |
