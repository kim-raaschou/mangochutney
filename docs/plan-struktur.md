# Kernen som mangos kode: plan for ombygningen

Besluttet 15. november 2026: kernen skal være 1:1 med mango, også i opbygning, ikke kun i
adfærd. Gennemgangen (`docs/gennemgang/`) viste, at mange afvigelser kommer af, at vores kerne er
bygget anderledes end mangos. Denne plan bygger kernen om, så den læses som mangos kildekode.

## Princippet

- **Fil for fil.** Hver af mangos filer i `src/` får sin egen fil i `Sources/Mango`, i samme træ og
  med samme navn: `src/layout/arrange.c` → `Sources/Mango/layout/arrange.swift`,
  `src/manage/client.c` → `Sources/Mango/manage/client.swift`. Funktionerne står i samme
  rækkefølge, med mangos navne i lowerCamelCase og mangos trin.
- **Mangos typer.** `Arg`, `Client`, `Monitor`, `Pertag`, `MangoServer`, `ResizeOpts`,
  `TagScrollerState`, `ScrollerStackNode`, `DwindleNode` med mangos felter og betydning. Bl.a.:
  `geom` er boksen med kanten, `bw` er kantens bredde, og animationen er mangos
  `c->animation` (`current`, `pending`, `animainit_geom`, `action`, `duration`, `running`).
- **wlroots er porten.** Hvor mango kalder wlroots (scene-noder, `client_set_size`, seat, cursor),
  kalder kernen `system.…` (`WindowSystem`). Én mærket linje pr. sted.
- **Animationen i kernen.** Mangos `resize` sætter animationens tilstand, og `rendermon` →
  `client_draw_frame` → `client_animation_next_tick` flytter vinduet billede for billede. Porten
  kalder kernens `rendermon(m)` for hvert skærmbillede (display link) og flytter vinduet, når
  kernen beder om det. Portens `Animator` forsvinder.
- **Testene følger med.** Tests, der låser vores gamle adfærd, skrives om til mangos. `make test`
  er grøn ved slutningen af hvert trin. Live-test efter trin 2, 4 og 6.

## Trinene

| # | Mango | Vores nu | Hvad |
|---|---|---|---|
| 1 | `common/types.h`, `server.h`, `manage/client.h`, `manage/monitor.h` | `Engine/Client.swift`, `MangoServer.swift` | Typerne og felterne med mangos navne og betydning; `geom` med kant |
| 2 | `animation/client.c` (resize, pending state, next tick, draw frame), `animation/common.c`, `animation/tag.c` | `Engine/Animation.swift`, `Port/macOS/Animator.swift` | `resize` og animationen i kernen; porten kalder `rendermon` |
| 3 | `layout/arrange.c`, `layout/layout.h` (`layouts[]`) | `MangoServer.arrange`, `Layout/Layout.swift` | `arrange` som mangos; layouts kaldes via tabellen |
| 4 | `layout/horizontal.c`, `vertical.c`, `scroll.c`, `dwindle.c`, `overview.c` | `Layout/*` | Layouts, der kalder `resize` pr. klient; scroller- og dwindle-tilstand som mangos |
| 5 | `manage/client.c`, `monitor.c`, `misc.c`, `tab.c`, `layer.c` | `MangoServer.swift`, `Groups.swift`, `Tabs.swift` m.fl. | Klient- og skærmhåndtering |
| 6 | `dispatch/bind.c`, `config/binding_parse.c` (`parse_func_name`) | `Engine/Dispatch.swift` | Dispatcherne som mangos funktioner med `Arg` |
| 7 | `input/pointer.c`, `keyboard.c`, `trackpad.c` | `Engine/Input.swift`, `Keyboard.swift`, `Pointer.swift`, `LiveGestures.swift`, `DragTile.swift` | Input, inkl. mangos fokus ved indgang i en flade |
| 8 | `overview/overview.c`, `switcher/switcher.c`, `draw/*` | `OverviewMode.swift`, `SwitcherMode.swift`, `TitleMessageBar.swift`, `Tabs.swift` | Overview, switcher, bjælker |
| 9 | `config/*`, `ipc/ipc.c` | `Config/*`, `IPC/*` | Allerede tæt på; flyttes til mangos træ og rettes efter gennemgangen |
| 10 | – | `docs/afvigelser.md`, `docs/gennemgang/` | Afvigelserne opdateres; fundne afvigelser strøges |

Rækkefølgen er nedefra: typerne først, fordi alt andet bruger dem. Trin 2–4 hænger sammen
(resize, arrange og layouts kalder hinanden) og live-testes samlet.

## Trin 2 i detaljer: animationen

Mangos model (`animation/client.c`):
- `resize(c, geo, opts)` sætter `c->geom` (med kant), `bw`, animationens `action`/`duration`,
  `animainit_geom`, kalder `client_set_size` (configure til den endelige størrelse uden kant) og
  `client_set_pending_state` → `client_commit` (`current = pending`, start animationen:
  `initial = animainit_geom`, `time_started`, `running`).
- Hvert skærmbillede: `rendermon(m)` → `client_draw_frame(c)` → `client_animation_next_tick(c)`:
  interpolerer `initial` → `current` med kurven, `wlr_scene_node_set_position` og
  `client_set_clip` (den synlige størrelse). Ved slut: `client_set_finish_geometry`.

Hos os:
- `client_set_size` → `system.clientSetSize(c, w, h)` (porten gemmer størrelsen, AX skriver den).
- `wlr_scene_node_set_position` + `client_set_clip` → `system.sceneNodeSetPosition(c, x, y)` og
  `system.clientSetClip(c, box)`: macOS kan ikke klippe et vindue, så porten sætter vinduets
  størrelse til den synlige boks (mærket i `docs/afvigelser.md`).
- `wlr_output_schedule_frame` → `system.scheduleFrame(m)`; portens display link kalder
  `server.rendermon(m)` og stopper, når `rendermon` ikke beder om flere billeder.
- Portens `Animator` (job-listen, kurverne) forsvinder; dens AX-kø (`WindowWriter`) bliver.

## Det, der ikke ændres

- Porten (`Port/macOS`) bliver ved med at gøre det, wlroots gør: AX, parkering af skjulte vinduer,
  rammer, faner og billeder tegnes stadig af porten. Den får nye kald over grænsen, hvor kernen nu
  gør mere selv (animationen).
- Udvidelserne (`Port/Extensions`) kobler sig stadig kun på via `PortHooks`.
- Det, macOS ikke kan, står stadig i `MangoCompat` og `docs/afvigelser.md`.

## Status

- 15. november: gennemgangen er færdig. Rettelserne til IPC (gennemgangens I) og config-parsing
  (G og H) er lavet af to agenter og flettet ind; 826 tests grønne.
- Trin 1, første del: klientens felter har mangos navne (`isfloating`, `isfullscreen`,
  `ismaximizescreen`, `isglobal`, `isunglobal`, `isminimized`, `isoverlay`, `oldtags`,
  `isnamedscratchpad`, `iscustomsize`, `iscustompos`, `isopensilent`, `istagsilent`, `isurgent`,
  `ismaster`, `isleftstack`, `oldScrollerPproportion` …).
- Trin 1, anden del: `Pertag` har mangos arrays (`curtag`, `prevtag`, `nmasters`, `mfacts`, `ltidxs`,
  `configLtidxs`, `noHide`, `noRenderBorder`, `openAsFloating`, `scrollerDefaultProportion…`,
  `dwindleRoot`, `scrollerState`) med mangos typer (`UInt32`, `Int32`, `Float`); `Monitor` har
  `gappih`…`specialGappov`; `get_mon_curtag`, `is_special_active`, `get_tags_first_tag(_num)`,
  `get_client_tag_idx`, `parse_tagrule`, `tag_slot_set_defaults`, `tag_rule_apply_to_slot`,
  `tag_gather_*`, `view_insert_shift_tags`, `client_view_on_monitor`, `get_tag_status`, `setgaps`,
  `reapply_master`, `monitor_copy_tag_layout` og `client_reset_mon_tags` er mangos; `TAGMASK`
  (`server.tagmask`, `update_global_var`), `TAG0_MASK` og makroerne `ISTILED`, `ISNORMAL`,
  `ISSCROLLTILED`, `ISFAKETILED`, `VISIBLEON`, `TAGMATCH`, `SCRATCHPAD_SHOWN`, `ISFULLSCREEN`.
- Tilbage af trin 1: mangos retningskonstanter (`UP`…`ALLDIR`) i stedet for `Direction`, `m`/`w`
  på `Monitor`. Tages med trin 3–4, hvor layoutet skrives om.
- Trin 2 (16. november): mangos `resize`, `client_set_pending_state`, `client_commit`,
  `client_animation_next_tick`, `client_set_finish_geometry`, `client_set_clip`, `clip_to_hide`,
  `client_animation_set_progress`, `client_animation_resume`, `client_draw_frame`,
  `set_client_open_animation`, `set_overview_enter_animation`, `is_special_animation_rule`,
  `set_tagin_animation`, `set_arrange_visible`, `set_tagout_animation`, `set_arrange_hidden`,
  `client_should_visible`, `client_update_visibility`, `client_set_bounds`, `client_get_clip` og
  `handle_output_frame` står i kernen (`animation/animation-client.swift`, `animation-tag.swift`,
  `animation-common.swift`, `manage/client.swift`, `manage/monitor.swift`; SwiftPM vil ikke have to
  `client.swift` i ét modul). `Client` har `geom` (med kanten), `pending`, `current`,
  `animainitGeom`, `bw` og `animation` (`MangoAnimation`). Grænsen har `clientSetSize`,
  `sceneNodeSetPosition`, `sceneSubsurfaceTreeSetClip`, `sceneNodeSetEnabled`,
  `sceneSurfaceSetEnabled` og `outputScheduleFrame`; portens `Animator` er væk, dens plads har
  `FrameClock` (display link → `handleOutputFrame`). `arrange(m, wantAnimation, fromView)` har
  mangos parametre og kalder `set_arrange_visible`/`set_arrange_hidden` og `resize` pr. klient;
  resten af `arrange` (pre_calculate, layouts via tabellen) er trin 3. `LayoutResult.hidden`
  bruges ikke længere af kernen (mangos `clip_to_hide` skjuler scrollerens kolonner) og går med
  trin 4. `floatGeom` er stadig uden kanten.
- (Oprindelig note) `Pertag` med mangos arrays (`curtag`, `prevtag`, `nmasters`, `mfacts`, `ltidxs`,
  `configLtidxs`, `noHide`, `noRenderBorder`, `openAsFloating`, `scrollerDefaultProportion…`,
  `dwindleRoot`, `scrollerState`), `Monitor` med `gappih`…`gappov`, `m`/`w`, og mangos konstanter
  (`UP`…`ALLDIR`, `TAGMASK`, `TAG0_MASK`) og makroer (`VISIBLEON`, `ISTILED`, …).
- Kladde til trin 6: `bind.c` oversat til Swift med `Arg` ligger i sessionens scratchpad
  (`draft/bind.swift`); den bygges ind, når funktionerne den kalder har mangos form.
