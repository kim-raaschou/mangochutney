# Kernen og porten

Status 3. november 2026. Hvordan koden er delt, hvad der er gjort, og hvad der er tilbage.
Den oprindelige plan (28. oktober) og dens trin står i git-historikken for denne fil og i
taggene `plan/*`.

## Reglen

CLAUDE.md er bindende. Kort fortalt:

- **`Sources/Mango`, kernen,** indeholder kun det, der findes i mangoWm 0.18.5, med mangos navne,
  opbygning, rækkefølge og standarder. Kommentarer er mangos egne eller et kort mærke om, hvor vi
  afviger (`not in mango: …`). En funktion med andet navn end mangos har én linje
  `/// mango <funktion> (<fil>)`.
- **`Sources/Port`, porten,** er alt andet: macOS-laget (`Port/macOS`), der står hvor wlroots og
  libwayland står hos mango, og udvidelserne (`Port/Extensions`), der er slået fra uden deres
  `chutney_`-nøgle.
- **`Sources/Boundary`, grænsen,** er protokollerne og typerne mellem de to. Den bygges i samme
  modul som kernen, fordi dens typer bruger mangos.
- Det eneste ikke-mango i kernen er kaldet over grænsen: én mærket linje, hvor mango kalder
  wlroots (`system.…`), eller hvor en udvidelse kobler sig på (`portHooks.…`).

## Moduler

| Modul | Linjer (uden tomme) | Indhold |
|---|---|---|
| `Mango` (`Sources/Mango` + `Sources/Boundary`) | 9.144 + 492 | Kernen og grænsen |
| `Port` (`Port/macOS` + `Port/Extensions`) | 6.780 + 2.524 | macOS-laget og udvidelserne |
| `MangoApp` | 968 | Appen: menulinjen, layoutpanelet, `mango -p` |
| `mmsg` (`Sources/Mango/mmsg`) + `MmsgPort` (`Sources/Port/mmsg`) | 137 + 407 | Mangos `mmsg.c` 1:1; portens `service`, `logs`, `reload`, `binds` (6. november 2026) |
| Tests | 8.846 | 551 tests; de tegner aldrig, flytter ikke markøren og tager ikke fokus (`FakeWindowSystem`) |

Den 2. november var kernen 13.272 linjer.

## Grænsen

| Fil | Hvad | Mangos tilsvarende |
|---|---|---|
| `WindowSystem.swift` | Det, mango beder systemet om: flyt, skjul, fokus, hæv, tegn rammer, faner, overview, skifter | wlroots' scene, seat og output |
| `EventLoop.swift` | `addFd`: kald mig, når der kan læses | `wl_event_loop_add_fd` (IPC) |
| `Screen.swift` | En skærm: ramme, arbejdsområde, skala, opdateringsfrekvens | `wlr_output` |
| `InputState.swift` | Det, event-tap-tråden skal vide for at afgøre en tast eller et klik | – |
| `Swipe.swift` | Et swipe, som libinput melder det | libinputs gesture-hændelser |
| `Decorations.swift` | Kant-, fane- og overview-beskrivelser, som porten tegner | mangos scene-noder |
| `PortHooks.swift` | Udvidelsernes kroge, alle `nil` eller tomme uden udvidelser | – |
| `ConfigPort.swift` | Portens nøgler, noter til `mango -p`, modifiernavne, tastkoder (xkb's keymap) | xkb og mangos egne tabeller |

Porten kalder mangos handlere, som wlroots gør: `handleClientMap`, `handleClientUnmap`,
`handleClientDestroy`, `handleClientActivationRequest`, `handleClientRequestMinimize`,
`handleClientSetTitle`, `handleCursorMotion`, `pointerProcessButtonPress`,
`handleKeyboardKey`, `handleCursorSwipeUpdate`/`End`, `handleOutputLayoutChange`.

## Porten

**macOS-laget (`Port/macOS`)** gør det, compositoren gør hos mango:

- **Vinduer:** Accessibility (`AX`, `AppWatcher`, `WindowClassifier` med AeroSpaces heuristik),
  skrivning og animation (`Placement`, `Animator`), parkering på skjulte tags (`Hider`), fokus
  (`Focus`, sendt én gang pr. tur), appens egne træk (`UserDrag`).
- **Vinduer, mango ikke har:** vinduer ved start og tilbage efter dvale eller genstart
  (`MacEvents.mapInitial`/`mapBack`, `WindowMemory`, `SavedLayout`), og vinduer macOS har væk
  (`AwayWindows`: Dock med `ignore_minimize`, fuld skærm, ⌘H, en app der ikke svarer), som
  unmappes og mappes tilbage.
- **Input:** event tap og tastaturets og musens beslutninger på dens tråd (`InputRouter`,
  `EventTap`), tastnavne (`KeySyms`, `KeyNames`), gestures (`Gestures`, `SwipeTracker`).
- **Tegning:** kanter, faner, overview, skifter, jump-mærker, drop-område, nag (`Borders`,
  `TabBars`, `OverviewOverlay`, `SwitcherPanel`, …).
- **System:** skærme, config-overvågning, IPC's event loop (`MainEventLoop`), tilladelser,
  hovedtrådens vagt (`MainThreadWatchdog`, kun med `-d`).
- **Tabeller:** `MangoCompat` (hvad macOS ikke kan, til `mango -p` og docs).

**Udvidelserne (`Port/Extensions`)**, slået fra uden deres nøgle: `chutney_focus_app`,
hotkeys- og layout-paletterne, menulinjen, `chutney_style` og temaet, ⌘1–9 i fanebjælken,
`chutney_floating_color`, `chutney_physical_pixels`, `chutney_ignore_apps`,
`chutney_hyper_modifier`. Nøglerne står i `PortOptions` og `PortConfig`.

## Gjort

| Tag | Hvad |
|---|---|
| `plan/1-grundlag` … `plan/8-k6-graensen` | Reglen og planen; tastetekst, swipe-tæller, config-model B, første start, vinduer der kommer igen, portens tabeller og grænsen i `Sources/Boundary` |
| `plan/9-k7-*` | Mærkerne i mangos filer gennemgået fil for fil; picker, klik-aktivering og Dock-minimering ud |
| `plan/10-kommentarer`, `plan/11-navne` | Kun mangos kommentarer og afvigelsesmærker; 52 funktioner med mangos navne |
| `plan/12-input` … `plan/16-foldet` | Input, config, IPC og 47 hjælpere foldet ind i mangos funktioner |
| `plan/17-ipc-mango`, `plan/20-ipc-uden-snapshot` | IPC 1:1 efter `ipc.c` på hovedtråden, JSON fra den levende tilstand |
| `plan/18-hovedtraad` | Tastegentagelser stables ikke; overlays lægges kun om, når de ligger forkert |
| `plan/19-start-tilbage`, `plan/21-macos-tilstande` | Start-, tilbage- og væk-vinduer i porten; `handleClientMap` er mangos |
| `plan/22-keysyms`, `plan/23-docs` | Tastkoderne i porten; docs opdateret |

Prøvet og fravalgt: macOS' fuld skærm som mangos fuldskærmstilstand
(`chutney_native_fullscreen`). Afprøvet live og fjernet igen; vinduer i fuld skærm unmappes.

## Det, der står tilbage i kernen

Mærket og bevidst. Kandidater til senere, når hverdagen har vist, at det, der er gjort, holder:

| Hvad | Hvor | Størrelse |
|---|---|---|
| Overview med billeder | `thumbnails`-grenene i `OverviewMode`, `arrange`, input (9 steder) | Middel |
| Parkering | `c.parked` (13 steder); mango skjuler i scenen | Middel |
| Scrollerens kolonnemodel | Kolonner i tag-tilstanden, hvor mango bruger `ScrollerStackNode` i klientlisten | Stor, en omskrivning |
| Rene layouts | Fanebjælken lagt oven på layoutets rammer (`reserveTabStrip`), `finish`/`transposed` | Hører til de rene layouts; bliver |
| 13 henvisningslinjer | Tastaturets tråd, cursor-timeren, `Log`, `f32`, fem mærker på mango-navne | Kræves af Swift og macOS; bliver |

## Hvordan det kontrolleres

- `make test` efter hvert trin; alle tests grønne.
- Et trin pr. commit, tagget `plan/<n>-<navn>`.
- Live: `make install`, genstart med `-d`, og tjek med `mmsg` og loggen (`/tmp/mango_krn.debug.log`).
- En ændring i kernen læses mod mangos kilde først (`~/sources/mango`), og mangos opførsel låses
  med en test, hvor det kan lade sig gøre.

## Kun på opfordring

Samle commits til ét og pushe taggene.
