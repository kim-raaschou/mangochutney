# POC: mango selv som facit

*Natten til 22. nov. 2026. Bygget og målt sammen med Fable.*

## Kort fortalt

**Det virker.** Rigtig mango 0.18.5 kører nu headless i en container. Den spiller 91 scenarier og
optager sine egne svar på `mmsg get`. Vores kerne spiller de samme scenarier og skal svare det samme.

- **Status:** alle 91 er grønne.
- **Tid:** de kører på 0,46 sekunder uden container (`make test` ser aldrig en container).

**Det fandt fejl med det samme:**
- To ægte fejl hos os, nu rettet.
- Én kendt afvigelse, der kan ses udefra.
- Alle de §6-rettelser, scenarierne rammer: mango selv bekræfter, at mangos svar er det, vi
  skrev i afvigelser.md.

**Men tallet 85 % holder ikke.**
- Facit dækker **58 % af kernen**.
- I det, mmsg kan se (Layout, dispatch, manage), ligger dækningen på **78–87 %**.
- Resten (input, mangonag, switcher, animation, meget af config-parseren) kan mmsg ikke nå. Det
  vil heller ikke ske med flere scenarier.

**Besparelse:**
- **109 af 854 tests** kan erstattes (ca. 1.240 linjer, 13 %).
- **Ingen tid** spares. 300 af suitens 328 sekunder går til porttests med rigtig ventetid
  (FullscreenTag, FitLayout, FullscreenNotify). Mango-testene var allerede hurtige.

**Den egentlige gevinst er tillid.** I dag skriver vi både koden og det forventede svar ud fra vores
egen læsning af mango. Facit fjerner den selvbekræftelse.

## Hvad der blev bygget

```
scenarie (.mango)  ──►  rigtig mango 0.18.5 i container  ──►  facit (.json)
       │                (headless, mmsg dispatch/get)              │
       └──────────►  vores kerne (TestMango, samme mmsg-linjer) ◄──┘  FacitTests sammenligner
```

Et scenarie er en lille tekstfil, som en senior kan læse uden at kende koden:

```
# tile with 1, 2, 3 and 5 windows, then nmaster, mfact and gaps.
# ours: tile gives the last window of a column the rest of it (a mango bug, docs/afvigelser.md §6).
config new_is_master=0
dispatch setlayout,tile
open a
check
open b
check
...
dispatch incnmaster,1
check
ours e.height 351
```

Trinene er `config`, `monitors 2`, `open a [dialog]`, `close a`, `dispatch …`, `check` og
`ours …`. Formatet står i `Tests/README.md`.

| Del | Fil | Linjer |
|---|---|---|
| Optager (kører inde i mango, styrer mmsg) | `Tests/MangoFacit/recorder/record.py` | ~150 |
| Testklient (xdg-vindue med titel) | `Tests/MangoFacit/recorder/facit-client.c` | ~110 |
| Container (Fedora 45: wlroots 0.20.2, scenefx 0.5) | `Tests/MangoFacit/recorder/Dockerfile`, `build.sh` | ~35 |
| DRM-shim, så scenefx kan tegne i software | `Tests/MangoFacit/recorder/drm-shim.c` | 8 |
| Kørsel | `Tests/MangoFacit/record` | ~20 |
| Afspiller og sammenligning | `Tests/MangoTestKit/Facit.swift`, `Tests/MangoTests/FacitTests.swift` | ~170 |
| Scenarier og facit | `Tests/MangoFacit/scenarios/` (91), `facit/` (2,1 MB) | |

Svarene sendes gennem den samme kode på begge sider. `TestMango.mmsg("get", "all-clients")` sender
linjen gennem vores `IPCServer.handleCommand`, præcis som mmsg ville. Der sammenlignes på:

- **Pr. vindue:** titel, skærm, tags, geometri, fokus, synlig, floating, fullscreen, maximized,
  minimized, global, overlay, scratchpad, gruppe og scroller_proportion. Rækkefølgen i klientlisten
  tæller også.
- **Pr. skærm:** layout, tags (pr. tag: aktiv, antal vinduer, layout), aktive tags, aktivt
  vindue, skjulte vinduer og keymode.
- **Markørens plads.**

## Hvad facit fandt

| Fund | Hvad | Status |
|---|---|---|
| **Fejl hos os** | `dwindleSwapClients` byttede kun bladene i træet. Mangos `dwindle_swap_clients` bytter også layout-egenskaber, plads i listen og skærm, og fokuserer og arrangerer. `exchange_client` i dwindle gjorde derfor intet synligt | Rettet 1:1 med mango (`Layout/dwindle.swift`), **ikke committet** |
| **Fejl hos os** | IPC skrev float-tal med 16–17 cifre. Mango (cJSON) skriver 15, når de rammer inden for `DBL_EPSILON` (`compare_double`). Eksempel: `scroller_proportion` 0.8999999761581421 mod mangos 0.899999976158142 | Rettet (`IPC/ipc.swift`, én linje), **ikke committet** |
| Kendt afvigelse, nu synlig | `is_focused`: mango bruger flaget `c->isfocusing`, vi bruger "selmon.sel". Et vindue med `no_focus:1` alene på skærmen er `false` i mango og `true` hos os. I afvigelser.md står `isfocusing` som udeladt | Indført 2026-11-22 efter din beslutning: `isfocusing` på `Client`, sat og ryddet i `client_focus` som hos mango, og IPC svarer med det. `ours`-linjerne i `rule-nofocus` er væk, og scenariet er grønt |
| §6 bekræftet | tile-afrunding, incgaps på special-tagget, `vertical_grid` med flydende vindue, `set_float_malposition` ved fullscreen-regel | Mangos svar er præcis det, §6 beskriver. Markeret med `ours` (8 scenarier) |
| Platformen, ikke mango | wlroots' headless-backend melder skærme i omvendt rækkefølge, og markøren starter i (100,100) eller på nærmeste skærm | Optageren gemmer begge dele, og afspilleren starter som mango startede |

To mutationer viser, at testen bider:
- dwindle-fejlen genindført giver 12 fejl i præcis `dwindle-move`.
- `default_mfact` ændret fra 0.55 til 0.56 giver 1.166 fejl i 60+ scenarier.

## Dækning

Linjer i `Sources/Mango`, målt med `swift test --enable-code-coverage`:

| Område | Facit alene | Hele suiten i dag |
|---|---|---|
| Layout | 84,8 % | 90,8 % |
| dispatch | 87,1 % | 75,9 % |
| manage | 78,3 % | 85,2 % |
| overview | 69,5 % | 95,4 % |
| Engine | 76,5 % | 90,1 % |
| Config | 41,1 % | 94,5 % |
| IPC | 34,9 % | 87,9 % |
| animation | 47,8 % | 92,3 % |
| input | 12,1 % | 88,5 % |
| switcher | 6,8 % | 90,6 % |
| mangonag | 0 % | 95,6 % |
| **I alt** | **57,8 %** | **89,0 %** |

- Facit rammer **62,5 %** af de linjer, suiten rammer.
- Facit rammer desuden **294 linjer, som ingen eksisterende test rører** (141 i dispatch, 90 i
  Layout, 57 i manage). I dispatch er facit allerede bedre end hele suiten.
- **Loftet:** de områder mmsg kan nå, er ca. 79 % af kernen, og facit dækker 68 % af dem i dag.
  Det, der mangler i Layout, dispatch og manage, er mest træk med musen, klientens egne ønsker
  (activation, minimize-request, titel) og skærme, der forsvinder. Fables liste over, hvad der ikke
  kan nås, er i bilaget.

## Hvad kan spares

Fable gennemgik alle 854 tests:

| | Tests | Hvad |
|---|---|---|
| **Kan erstattes (F)** | **109** (ca. 1.240 linjer) | 69 i FidelityTests, 15 LayoutTests, 8 EngineTagNavigationTests, 6 OverviewTests, 5 GroupTests, 3 IPCTests, 3 andre |
| Delvist (P) | 84 | et assert, mmsg ikke kan se: fokusstakken, interne felter, mål-klient, reload, klientens ønsker |
| Ikke (N) | 661 | port, extensions, macOS-fullscreen, input, config-parser, animation, tegning |

Forbehold:
- Fable læste FidelityTests i sin helhed og bedømte mange andre ud fra navne og asserts.
- Hver F-test skal holdes op mod sit scenarie, før den slettes. Ofte mangler et lille trin i et
  scenarie, fx at `viewtoright` stopper ved tag 9.

**Prøvet i praksis:** EngineTagNavigationTests' 8 mango-tests er omskrevet til fire scenarier
(`bind-viewtoleft-right*.mango`), optaget fra mango og grønne.

| | Linjer |
|---|---|
| Swift-testene | 63 |
| De fire scenarier | 60 |

Linjer spares der næsten ikke. Gevinsten er, at svaret nu er mangos eget, og at scenariet kan læses
uden Swift. De gamle tests er **ikke slettet**: det er din beslutning.

**Med små udvidelser af formatet** (kun hvad rigtig mango tilbyder) kan 20–35 P blive til F:
1. `dispatch @b focusstack,next`: mål-klient via mangos `client,<id>`. Det giver mest for mindst
   arbejde.
   **Bygget 2026-11-22:** `dispatch @b <func>` sendes som mangos `<func> client,<id>` (mango tager
   kun målet med mellemrum til sidst). 17 nye scenarier (`target-*.mango`) over 30 dispatchere med
   mål; alle grønne. Dækningen steg kun fra 57,8 % til 58,4 %: målet er få linjer, gevinsten er, at
   ca. 30 tests, Fable fandt, nu kan holdes op mod mangos eget svar.
2. Fokusstakken afsløret ved at lukke vinduer til sidst i et scenarie.
3. `reload` med nye config-linjer.
4. Skærme, der slås fra og til, og skærme med andre størrelser.
5. `open a 1920x500` og klientens egne ønsker (activation, minimize).

## Tastatur og mus (2026-11-22)

Mango har `virtual-keyboard` og `virtual-pointer`, så optageren trykker taster og flytter musen i rigtig
mango (`recorder/facit-input.c`). Afspilleren giver vores kerne de samme hændelser, som porten giver
dem. Trin: `key`, `keydown`/`keyup`, `pointer`, `move`, `click`/`button` og `scroll`.

- 11 scenarier (`input-*.mango`): key binds, keymodes, release-binds, sloppy og klik-fokus, axis-binds,
  flyt og resize med en musebinding, resize ved rammen, hot area, switcheren og jump mode. Alle grønne.
- Én rettelse i testlaget: den falske wlroots lod ikke vinduet følge mangos størrelse og plads, så
  punktet under musen ramte forkert. Nu tager overfladen den størrelse, mango konfigurerer, og står,
  hvor mango sætter noden, som wlroots og testklienten gør.
- Grænser, som mango selv sætter: et virtuelt tastaturs modifiers tæller ikke for muse- og
  axis-binds (`keyboard_hard_modifiers`), og dets mode-tast afslutter hverken overcircle eller
  switcheren. Swipe-gester kan et virtuelt device ikke sende.

| Område | Før | Efter |
|---|---|---|
| input | 12,1 % | 48,1 % (74 % uden trackpad, som ingen virtuel enhed når) |
| switcher | 6,8 % | 78,0 % |
| Config | 41,2 % | 49,6 % |
| **I alt** | **58,4 %** | **65,6 %** |

## Config (2026-11-22)

`mango -c <fil> -p` tjekker en config og skriver hver fejl med linje. Optageren gemmer exitkoden og
fejlene for hver fil i `configs/` (`.conf` og `.toml`), og `ConfigFacitTests` læser samme fil med
vores parser og portens side af config'en, som vores `mango -p` gør, og sammenligner fejl for fejl.

- 10 filer: mangos egen `config.conf` og `config.toml` (begge fejlfri hos mango og os), farver,
  bindinger af alle slags, regler, tal, lister, variabler, `source`, konflikter i alle fem slags
  bindinger, TOML med fejl og CRLF. Ca. 90 fejl og advarsler giver præcis mangos tekst og linje.
- Tre steder svarer vi anderledes med vilje, og de er markeret i filen (`# ours: drop …`):
  - CRLF: mango afviser hver tom linje med `\r` (en mango-fejl, allerede i §6). Mango bekræfter
    nu selv §6's beskrivelse.
  - `F13`: mango advarer om en tast uden keycode i layoutet; vores bindinger følger portens taster
    (§3).
  - `dim_unfocused_color`: macOS kan ikke dæmpe vinduer, så porten ignorerer nøglen og læser ikke
    værdien; mango afviser en ugyldig farve.

| Område | Før | Efter |
|---|---|---|
| Config | 49,6 % | 73,6 % (resten er mest filovervågning, fejl-nag og reload) |
| **I alt** | **65,6 %** | **70,4 %** |

## Flere mmsg-svar (2026-11-22)

Trinnet `get <emne>` gemmer mangos hele svar på `mmsg get <emne>` (uden id'er, pid'er og
foreign-toplevel-id'et, som er tilfældigt), og testen sammenligner felt for felt. To scenarier
(`ipc-get*.mango`) spørger på `all-tags`, `tag`, `keymode`, `focusing-client`, `monitor`, `client`,
`last_open_surface`, `layouts` og `cursorpos`, også fejlsvarene og en gruppe, scratchpad, fullscreen,
global og overview. Alle svar er mangos, felt for felt; testlagets xkb-navn for layoutet er rettet
til `English (US)`.

`watch` er ikke med: vores `watch` sender med vilje én linje pr. tur og kun ved ændring (§2), mens
mango sender ved hvert `printstatus`, så strømmene kan ikke sammenlignes linje for linje.
Sluttilstanden dækkes af `get`.

| Område | Før | Efter |
|---|---|---|
| IPC | 38,6 % | 49,0 % (resten er `watch`, socket og enheder) |
| **I alt** | **70,4 %** | **71,0 %** |

## Reload, skærme og appens egne ønsker (2026-11-22)

Nye trin: `open a 1900x500` (en egen størrelse), `monitors 2560x1440 1280x1024`, `output add EXTRA`
(en skærm sat til), `reload <linje>` og `request a minimize | title x | activate by c`. Testklienten
tager nu ønsker på stdin og sender dem til mango, som en app gør.

- 7 scenarier: egne størrelser og store dialoger, appens ønsker, aktivering med `focus_on_activate`
  til og fra, reload af mellemrum, rammer, layout, `tag_num` og en ny bind, skærme af forskellig
  størrelse, en skærm, der sættes til, og et vindue flyttet ind over en anden skærm. Alle 127 scenarier er optaget igen med den nye klient;
  mangos svar er uændrede.
- **Fundet og rettet i kernen:** mangos `node_at_point` går hele scenen igennem, så et flydende
  vindue, der er flyttet ind over en anden skærm, er under musen dér. Vores `nodeAtPoint` så kun
  vinduerne på skærmen under punktet og fokuserede vinduet bag ved. Nu ser den alle vinduer med en
  synlig node, hvor de står (`manage/misc.swift`); låst af `monitor-span.mango`.
- **Rettet i testlaget:** den falske wlroots gav et vindue den nye størrelse straks; i wlroots (og i
  porten) tager vinduet den først, når appen har svaret. Nu sker det ved næste frame.
- **Ikke med:** mangos aktivering uden et gyldigt token (kun urgent) ligger i dens protokol-lag,
  som porten erstatter; `disable_monitor` og søskende kan macOS ikke (MangoCompat); og at fjerne en
  skærm kan headless-mango kun for alle på én gang, hvor vores grænse med vilje ignorerer en tom
  skærmliste. Mangos ønske om fullscreen fra appen har ingen modpart i kernen (native fullscreen er
  fravalgt).

| Område | Før | Efter |
|---|---|---|
| Config | 73,6 % | 76,3 % |
| manage | 80,0 % | 81,5 % |
| **I alt** | **71,0 %** | **71,8 %** |

## Flytningen af testene (2026-11-22)

Fable delte alle mango-tests op i dækket (COVERED), kan skrives (WRITABLE) og skal blive (KEEP). Scenarier
og config-filer blev skrevet til de skrivbare, optaget fra mango, og hver Swift-test blev holdt op mod
sit facit, før den blev slettet. En test, der også påstår noget, facit ikke ser (fokus-stakken, interne
felter, porten, tegning, læste værdier), er blevet.

| | Før facit | Nu |
|---|---|---|
| Swift-testlinjer (PortTests og MangoTests) | 14.084 | 11.703 |
| Testfunktioner | 867 | 683 |
| Scenarier | 0 | 292 (4.138 linjer) |
| Config-filer | 0 | 56 |
| Dækning, hele suiten | 89,0 % | 92,7 % |
| Dækning, facit alene | 0 | 75,1 % |

Mango var enig med alle de Swift-tests, der blev flyttet. Undervejs fandt facit to fejl mere i kernen,
begge rettet: `handle_client_map` sluttede med `arrange`, hvor mango slutter med `resize`, og `focused`
gik ned ved en `global_key_binding`-regel, før der var en skærm.

## Hvad det koster

- **Opsætningen** (én gang): en colima-profil `mangofacit` (4 CPU, 4 GB), som `record` selv
  forklarer.
  - Ubuntu-kernen i colima mangler en DRM-enhed, så `linux-modules-extra` er installeret i den VM,
    og `vkms` indlæses ved start.
  - mango tegner med scenefx (GLES). Mesa tegner derfor i software på vkms, og en lille LD_PRELOAD
    (`drm-shim.c`) lader scenefx bruge vkms' primære node. Den rører ikke mangos logik.
  - Din standardprofil i colima er ikke rørt.
- **En optagelse:** knap 6 minutter for alle 91 scenarier. Det er kun nødvendigt ved nye scenarier
  eller en ny mango-version.
- **Timer:** optageren venter, til tre svar i træk, med 40 ms mellemrum, er ens. Det er en poll og
  ligger kun i optageren. Testene venter ikke på noget.
- **Et valg i testklienten:** den tager sin egen første størrelse (800x600) i stedet for mangos
  forudsagte (`client_negotiate_initial_size`). Det er det samme som en macOS-app og det samme som
  vores `TestMango.map`. Uden det valg ville et vindue født fliset og gjort flydende få en anden
  størrelse end hos os.
- **Facit er bundet til mango 0.18.5.** Ved en ny mango-version optages der igen, og forskellen
  i facit viser præcis, hvad mango har ændret. Det er i sig selv nyttigt for porten.

## Anbefaling

1. **Behold facit.** Det er den eneste kilde til "mangos svar", der ikke er vores egen læsning. Det
   fandt en ægte fejl, som 854 tests ikke fandt.
2. **Commit POC'en og de to rettelser** (efter dit review): `Layout/dwindle.swift` og
   `IPC/ipc.swift` i kernen, resten i `Tests/`.
3. **Flyt de 109 F-tests** fil for fil til scenarier og slet de gamle, når scenariet er grønt og
   dækker samme påstand. Start med EngineTagNavigationTests (gjort) og LayoutTests.
4. **`isfocusing`:** indført 2026-11-22 (se "Hvad facit fandt").
5. **Byg formatudvidelse 1** (`@titel` som mål) før migrationen af FidelityTests. Den gør mange
   scenarier kortere.
6. **Testtiden er et andet emne.** Hvis de 5 minutter skal ned, ligger de i porttestenes ventetid
   (FullscreenTag 123 s, FitLayout 77 s, FullscreenNotify 62 s), ikke i mango-testene.

## Bilag

**Ændret, ikke committet:**
- Kerne: `Sources/Mango/Layout/dwindle.swift`, `Sources/Mango/IPC/ipc.swift`.
- Test: `Tests/MangoTestKit/{TestMango,FakeWlroots,Facit}.swift`, `Tests/MangoTests/FacitTests.swift`,
  `Tests/README.md`, `Tests/MangoFacit/`.

**Committet:** `dc59366` (MangoTestKit, MangoTests, ExtensionsOffTests).

**Kan ikke nås med mmsg** (fra Fables gennemgang):
- **Input:** pointer og tastatur (træk, resize med musen, sloppy focus, hot area, switcherens valg
  ved tastslip, jump-tilstandens bogstaver).
- **Overflader og klienter:** layer shell, X11, klientens egne ønsker.
- **Udseende og intern tilstand:** animationer og udseende, fokusstakkens rækkefølge og z-orden.
- **Uden for mangos proces:** `spawn`/`exec`, reload uden formatudvidelse, og MangoCompat-skærmkommandoer.

**Miljø efter natten:**
- colima-profilen `mangofacit` er stoppet. Den startes med `colima start -p mangofacit`.
- Docker-konteksten hedder `colima-mangofacit`. En `colima start` af standardprofilen sætter den
  tilbage.
