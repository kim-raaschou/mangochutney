# Afvigelser fra mango

Hvor Mango Chutney gør andet end mango 0.18.5 (`~/sources/mango`, commit `21f80a9`), og hvorfor. Kun det, der
gælder nu; det rettede og hvordan vi kom hertil står i [afvigelser-historik.md](afvigelser-historik.md).
Hver mango-nøgle, macOS ikke kan, står med grunden i [compatibility.md](compatibility.md) og
i `mango -p`.

Uden nogen `chutney_`-nøgle (portens blok sidst i `config.conf` slettet) opfører porten sig
som mango, så langt macOS tillader (afsnit 3), og med de fejl i mango rettet, der står i
afsnit 6.

## 1. Til og fra: portens udvidelser

Hver er fra, når nøglen mangler, og ændrer da intet af mangos opførsel. Standardconfigen er
mangos egen `assets/config.conf` med mangos taster på Hyper (afsnit 2), og derefter portens
nøgler fra deres markeringslinje til slutningen: dem, en Mac vil have; resten står i
`docs/guide.md`. Blokken sætter ingen af mangos nøgler. Slettes den, opfører porten sig som
mango med filens taster, hvor `HYPER` da er ⌃⌥⌘ holdt (`chutney_hyper_modifier`s standard);
mango selv melder "Unknown keyword" for hver `chutney_`-linje og læser resten.

| Nøgle / dispatcher | Gør | I standardconfigen | Uden den (mango) |
|---|---|---|---|
| `chutney_menu_bar` (+ `_tag_style`, `_logo`, `_layout`, `_mode`) | Menulinjen med tags, layout og layout-panelet | til | Ingen menulinje; tags i en bar via `mmsg watch` |
| `chutney_menu_config` | Panelets ændringer gemmes i `chutney_menu.conf`, som configen læser sidst; `config.conf` skrives aldrig | `chutney_menu.conf` | `setoption` gemmer intet |
| `chutney_style` | Fanebjælke, gruppebjælke, jump-mærker, switcher, titelbjælke, config-banner og overview i macOS' udseende, hvor ingen `*_decorate_*`-nøgle er sat; mangos farver i macOS' (`chutney_theme.conf`, følger accentfarve og lys/mørk); rammen følger vinduets runde hjørner | til | Mangos udseende og farver |
| `chutney_tab_bar_decorate_icon`, `chutney_group_bar_decorate_icon` | Appens ikon før titlen i fanebjælken og i gruppebjælken, én nøgle pr. bjælke som mangos `*_decorate_*` | til | Kun titler |
| `chutney_tab_bar_shortcuts` | ⌘1–9 vælger en fane | til | Ingen |
| `chutney_keybindings` (+ `chutney_keybindings_spotlight_launch`) | Keybindings-paletten: søg i bindinger, vinduer og programmer | Hyper K | Ingen |
| `chutney_layout_switcher` (+ `chutney_layout_switcher_*`) | Layout-switcheren; viser `circle_layout`, Tab og Space sætter den | Hyper L | Ingen |
| `chutney_focus_app` | Én tast pr. app: start den eller gå til dens vindue (med tre eller flere: det, der blev brugt før) | nej | Ingen |
| `chutney_overlap_warning` | Et flisebelagt vindue, der er større end sit felt (og går ind over naboen), tegner sit tag orange i menulinjen; menuen siger hvor meget og giver forslag med ét klik (til et tomt tag, eller flydende), hver en af mangos kommandoer | nej | Intet mærke |
| `chutney_hyper_modifier` | Hvad `HYPER` betyder i en binding | `super+ctrl+alt` | Mangos Mod3 |
| `chutney_hyper_tap` | Hyper-tasten trykket alene (Caps Lock eller en funktionstast): `none`, `original` eller `escape` | nej (standard `none`) | Ingen |
| `chutney_set_proportion_all` (dispatcher) | `set_proportion` for alle vinduer på tagget i visning | nej | `set_proportion` på ét vindue |

`Resources/config.conf` er mangos `assets/config.conf`, men med mangos bindinger på Hyper
(`var=mod,HYPER`, `var=mods,HYPER+SHIFT`), fordi ⌘, ⌥ og ⌃ er macOS' og appernes. Resten følger
mangos fil linje for linje, og mangos ændringer merges ind (`make config-diff`).

## 2. Valgt anderledes, uden nøgle

Gælder for alle. Står i koden mærket "not in mango".

| Hvad | mango | Hvorfor | Mangos opførsel |
|---|---|---|---|
| `watch` sender kun, når svaret har ændret sig | Ved hver statusbegivenhed | Færre linjer til en bar | Ingen |
| `chutney_restart`, `mmsg service`/`logs`/`reload`/`binds`, `get binds` | Findes ikke | Genstart og login-tjeneste på macOS | Brug dem ikke |
| Modifiernavnene `cmd`, `option`, `control`, `fn` m.fl. i bindinger | Ukendte navne springes over | macOS' egne navne | Brug mangos navne |
| `switch_keyboard_layout` virker ikke | Skifter xkb-layout | macOS skifter inputkilde selv (menuen og ⌃Space); kunne bygges med `TISSelectInputSource`, men er fravalgt | Brug macOS' genvej |
| Dækkede vinduer animeres ikke | Alle animeres | Hver frame er en Accessibility-skrivning; usynligt | Ingen |
| Layout-paletten viser alle 14 layouts i et 5×3-gitter, når `circle_layout` mangler | `layouts[]`-rækkefølgen | Palettens opstilling | `switch_layout` følger mangos rækkefølge |
| Den medfølgende config (`Resources/config.conf`) er mangos `assets/config.conf` med mangos værdier; hvert sted, den ikke er det, står i en region mærket `# not mango default` (til `# end not mango default` eller filens slutning) med mangos linje nævnt: tasterne på Hyper, rofi og mangos midterklik udeladt, portens `chutney_*`-blok og Escape, der lukker overview (`bindp=NONE,Escape,leaveoverview`). | `assets/config.conf` | Tasterne må ikke tage macOS' og apps' genveje; portens nøgler | Brug mangos linjer i stedet for regionerne |
| `error_nag` tjekker for fejl, når `setup` er færdig, ikke på en timer på 1 ms | `config_error_nag_init`s timer | Porten er klar, når `setup` er færdig | Ingen |
| Efter et greb kører kun den del af `pointer_process_motion(0, …)`, der sætter kantgrebets markør, ikke resten (sloppy focus, hot area) | Hele `pointer_process_motion` | Den var aldrig med; markøren skulle med for kantgrebet | Ingen synlig: næste bevægelse gør resten |

## 3. Tvunget af macOS

| Hvad | Hvorfor |
|---|---|
| Vinduer på skjulte tags parkeres i et hjørne med en pixel synlig | Uden compositor kan et vindue ikke skjules |
| Menulinjens punkt viser alle skærme, hver med sine tags og sit layout, den valgte fuldt optrukket og de andre dæmpet (som AeroSpace og rift) | macOS tegner ét menulinjepunkt som kopi på hver skærm; en bar som waybar viser hver skærm sine egne |
| Et flydende vindue holdes inden for sin skærms arbejdsområde (`keepOnDisplay` efter mangos `client_set_bounds`); mango lader det stå halvt uden for skærmene | Med separate Spaces (macOS' standard) står et vindue på én skærm: et vindue lagt hen over to flytter macOS, væk fra den ramme, mango tegner |
| Et vindue åbner flydende, når det er en dialog (`client_is_float_type`); mangos andet led, `|| parent` (et vindue med en forælder), mangler | macOS' Accessibility siger ikke, hvilket vindue der er et andets forælder |
| Hvilke vinduer der styres (popups aldrig), og hvilke der åbner flydende (dialoger), afgøres med AeroSpaces heuristik 1:1, med dens app-lister, og én ændring: AeroSpaces regel om vinduesniveau gælder alle apps, ikke kun dem på dens liste, så et vindue over normalt niveau (en notifikation, et flydende panel) aldrig styres; en `window_rule` med `is_floating` vinder. Som i AeroSpace flyder et vindue, der er minimeret, eller hvis app er skjult, når det findes | Wayland siger det med xdg-roller; macOS siger det ikke pålideligt, og AeroSpaces heuristik er afprøvet mod rigtige apps |
| Et vindue, der ikke kan blive mindre end sit felt, går ind over naboen og vokser indad fra en skærmkant, det ellers ville krydse; mango klipper det (`chutney_overlap_warning`: tagget bliver orange i menulinjen) | Appen afviser størrelsen, og andre apps' vinduer kan ikke klippes |
| Efter mangos kantgreb (`enable_border_resize`) eller et træk vises en pil, til appen selv sætter sin markør igen, når markøren går ind over en ny del af den; i mango giver wlroots straks appen sin markør tilbage. På macOS 14 er de skrå markører på et flydende vindues hjørner et sigtekors | En app i baggrunden kan sætte markøren (`SetsCursorInBackground`), men ikke bede en anden app om at sætte sin igen; macOS 14 har ingen offentlige skrå markører |
| Mangos lag (`client_target_layer`) holdes, når mango giver fokus, men et klik med musen løfter altid vinduet; en app, der selv lægger sit vindue frem, når den bliver aktiv eller får sit nøglevindue (fx Arc, IntelliJ), kommer øverst alligevel; og et vindue, der får fokus under et højere lag, løftes heller ikke over sine naboer i sit eget lag | Klikket når macOS, før mango ser det; tastaturfokus kræver, at appen er aktiv, og en aktiv app ordner selv sine vinduer; porten kan lade være med at løfte et vindue, men ikke lægge et andet programs vindue over det aktive |
| Layoutet holder menulinjen og Dock'en fri | De svarer til mangos bjælker med eksklusiv zone |
| Ingen skygge, blur, dæmpning, gennemsigtighed eller runde hjørner fra mango; ingen luk- og fade-animationer | macOS tegner andre apps' vinduer; gennemsigtighed kræver SIP slået fra |
| Animationer skrives via Accessibility (højst 60 Hz) | Ingen compositor |
| En flydende resize med musen sker højst én gang pr. skærmens opdateringsinterval; mango én gang pr. tegnet billede (`frame_serial`, 09828ec) | Kernen får ingen billedbegivenheder fra macOS |
| Overview og switcher viser billeder (Skærmoptagelse), stillbilleder taget ved åbning; de rigtige vinduer bliver under dem, så `warp_cursor` sætter markøren på kortet (mangos `geom` i overview) | Andre apps' vinduer kan ikke skaleres; en strøm pr. vindue koster meget |
| Kantgrebet (`enable_border_resize`) tager kun et klik, som event tap'en har taget fra appen; den afgør det ud fra mangos `hover_resize_edge` ved forrige bevægelse. Er markøren lige kommet på eller af striben, kan det ene klik gå til appen, eller gå tabt | Tap'en skal afgøre klikket med det samme, før appen får det, og kan ikke vente på mango |
| `mangonag` er ikke et eget program: dens kode (`Sources/Mango/mangonag`, 1:1) kører i mangos proces, og porten står for dens Wayland-side (`NagDisplay`): bjælken tegnes med AppKit (mangonags farver, skrift, fire linjer, ANSI-farver og knapper) og står under menulinjen (eller over Dock'en); `-y` (lag) gør intet, bjælken står over vinduerne; tilvalgene læses med macOS' `getopt`, som ikke flytter tilvalg efter et løst argument frem, som glibc's gør | mangonag er en Wayland-klient på en layer surface, tegnet med cairo og pango; et program at kalde selv har en Mac ikke brug for (macOS' notifikationer) |
| En terminalknap i bjælken (Edit) åbner macOS' Terminal, når hverken `$TERMINAL` eller en af mangos terminaler (foot, alacritty, kitty, wezterm, st, xterm) findes; scriptet hedder `.command` | mango kører den så i `sh` uden terminal, og `vi` kan ikke køre uden en |
| Et vindue i macOS' egen fuldskærm (den grønne knap), i Dock'en (med `ignore_minimize`, mangos standard), i en skjult app (⌘H) eller i en app, der ikke svarer, mens det er parkeret, unmappes med mangos `handle_client_unmap` og mappes tilbage på sin plads, når det kommer igen. Mango ser det ikke imens, heller ikke i `mmsg get all-clients` | macOS har allerede taget vinduet væk; mango ville have det unmappet |
| En holdt tasts gentagelser: højst én venter på hovedtråden ad gangen | macOS sender gentagelserne selv; mangos egen gentagelsestimer stabler dem aldrig |
| Fokus sendes til macOS én gang pr. tur, for det sidst fokuserede vindue | Fokus på macOS er en synkron forespørgsel til WindowServer og appen; mangos `client_focus` sætter kun tilstand |
| Kant-, fane- og gruppevinduer lægges kun om, når de ligger forkert | Hver omlægning venter på WindowServer; én forespørgsel på rækkefølgen er billigere |
| En dialog arver ikke sit hovedvindues tags og skærm | Accessibility siger ikke pålideligt, hvem der ejer en dialog |
| Vinduer, der er der ved start eller kommer igen efter dvale, beholder deres plads; layout, tags og grupper gemmes og kommer igen efter en genstart og dvale | En genstart af mango lukker ikke vinduerne, og macOS melder vinduer væk og tilbage omkring dvale |
| Titelbjælkens anden linje er appens bundle id | macOS' nærmeste svar på `app_id` |
| `app_id` i en vinduesregel og i `toggle_named_scratchpad` matcher også appens navn (`Safari`), ikke kun bundle id'et (`com.apple.Safari`) | macOS har intet `app_id`; bundle id'et er det nærmeste, navnet det, man kender |
| `monitor_name` i regler og skærmnavnene i IPC er macOS' navn for skærmen (`BenQ RD280U`), ikke udgangen (`DP-1`) | macOS navngiver ikke udgange |
| `tag_rule`s `monitor_make` er skærmens PNP-id (`BNQ`), ikke fabrikantens navn (wlroots: `BenQ Corporation`); `monitor_model` og `monitor_serial` er EDID'ens som hos wlroots. En skærm, macOS ikke har dem for, matcher ikke (som en skærm uden EDID hos mango), og to ens skærme uden serienummer får intet | macOS har EDID'ens felter i IORegistry (Apple silicon), men ingen PNP-navnetabel |
| Et klik fokuserer ikke det vindue, der allerede har fokus, og intet i overview; mangos `buttonpress` kalder `focusclient` hver gang | macOS har fokuseret vinduet med klikket; i overview er kortene billeder |
| `last_open_surface` (i `get` og `watch`) er altid tom | Den sættes, når en layer-shell-flade åbner; macOS har ingen layer shell |
| `confine_pointer` sætter markøren tilbage, når den er nået over kanten | macOS flytter markøren, før mango ser bevægelsen |
| `xkb_rules_options`: kun de muligheder, der flytter taster, med macOS' egen omlægning | macOS har ingen xkb |
| Systemets trackpad-gestures konkurrerer med `gesturebind` | macOS ejer dem |
| IPC: Unix-socket `/tmp/mango-<bruger>.sock`, kun brugerens (0600), og en anden kørende mangos socket overtages ikke; `mmsg` bruger den, når `MANGO_INSTANCE_SIGNATURE` mangler (mango: fejl), og `SO_NOSIGPIPE` for `MSG_NOSIGNAL`; `get tag` tager tallet som sidste felt; sende-bufferen er 1 MB | Ingen `XDG_RUNTIME_DIR`; et program, Dock'en eller Terminal starter, er ikke mangos barn; skærmnavne har mellemrum; macOS' buffer er 8 KB, og et svar sendes uden at vente |
| `source=` med relativ sti læses fra config-mappen; ingen `/etc/mango`-fallback | Under launchd er arbejdsmappen `/`; macOS har ingen `/etc`-config |
| Første start skriver `Resources/config.conf` som `config.conf`: mangos config med mangos taster på Hyper (en tast, brugeren vælger som i Raycasts Hyper Key: Caps Lock, en venstre/højre modifier eller F1–F12; `chutney_hyper_key`), ikke mangos egne taster, og de første linjer at prøve nær slutningen. Også et velkomstvindue, der åbner Getting Started | mango læser `/etc/mango/config.conf`, når brugeren ingen har; en Mac-app har ingen `/etc`-config. mangos taster (⌘M, ⌘N, ⌥+bogstav, ⌃+pile) er macOS' og appernes genveje |
| Input besluttes på event tappets tråd; `setkeymode` og `chvt` stopper søgningen efter bindinger | macOS vil have svaret med det samme; dispatcherens svar kendes først på hovedtråden |
| Timere: cursor-skjul (som mangos), animationernes reserve-timer, 0,4 s ekstra genstabling efter fokus, sen genlæsning af vinduets ramme, ét forsøg pr. sekund på at sætte et vindue tilbage, samling af skærm- (0,3 s) og config-ændringer (0,15 s, som mangos), appens egne rapporter lige efter et træk (0,4 s), 0,05 s efter menuen, ventetid ved genstart og `mmsg service`, hovedtrådens vagt, mangonags `-T` (kun når den er sat; config-fejlenes bjælke har ingen) | macOS melder ikke alt som en begivenhed |

## 4. Mangler endnu

Intet: alt af mango 0.18.5, som macOS tillader, er bygget (`switch_keyboard_layout` er fravalgt,
afsnit 2). Af de 31 commits fra 0.18.2 rammer disse ikke macOS: lag- og låseflader (`a3990ec`,
`9c44c66`), VRR (`4a430d8`; dens sloppy focus under et træk holder vi allerede, mens en knap er
nede), billedudsnit til overview og switcher (`b7551be`), xdg- og Xwayland-tilstand (`499a164`,
`61fa048`), popups (`283246a`) og touch (`7812939`).

## 5. Struktur

Hvor koden står, når den ikke står som i mango.

- **mmsg (`Sources/Mango/mmsg`)** er mangos `mmsg/mmsg.c` 1:1 med `mango_error` fra
  `common/log.c`. Portens kommandoer (`service`, `logs`, `reload`, `binds`) og deres linjer i
  hjælpen står i `Sources/Port/mmsg` og kobles på med én mærket linje hver.
- **Kernen (`Sources/Mango`)** har mangos funktioner med mangos navne og kun mangos egne
  kommentarer eller mærker om, hvor vi afviger (CLAUDE.md regel 8). En funktion med andet navn
  end mangos har én linje `/// mango <funktion> (<fil>)`; der er 14 tilbage: tastaturets tråd,
  cursor-timeren, `Log` og nogle få, der allerede har mangos navn.
- **Bevidst i kernen, mærket:** parkeringen (`c.parked`, mango klipper i scenen), scrollerens
  kolonner i tag-tilstanden (mango bruger `ScrollerStackNode` i klientlisten), overview med
  billeder (`thumbnails`), drag-tile delt med appens eget træk, `parse_option` som en tabel,
  og `resize_tile_master` i begge retninger i én funktion.
- **Mærket i kernen, som at skrive mangos C i Swift:** `f32` (en værdi, mango har i et
  float-felt, afrundet som C) og `LayoutInput.sanitized()` (C laver et tal, der ikke er
  endeligt, om til et heltal uden videre; Swift stopper programmet). `oldmonname` holder
  skærmens display-ID, ikke navnet, for to skærme kan have samme navn.
- **Faner:** fanekæden holdes for de tags, der er i visning, som `tab_member_kept` holder den;
  mango kæder den pr. vindue (`Tabs.swift`).
- **Lag:** `client_target_layer` er i kernen 1:1, og porten bruger den, når mango giver fokus: ligger
  et synligt vindue i et højere lag over det, får vinduet fokus uden at blive løftet (`lifts`), så
  det højere lag bliver øverst. `client_sync_layer` og `client_reparent_group` (et vindue og dets
  gruppebjælke flyttes til et andet lag i scenen) har ingen funktion i kernen; porten ordner
  vinduerne i `restack`.
- **Kald over grænsen, mærket:** `client_is_float_type` er `platform.isFloatType` (en dialogs
  subrole); appens egne flyt under et træk tager porten ud (`grabBegan`, `grabEnded`).
- **Logning:** mangos `common/log.c` i kernen (`mangoError`, `mangoLogInit`) og wlroots'
  `wlr_log` på grænsen (`WlrLog.swift`), med wlroots' format og niveau. Porten logger med
  `wlrLog`, som wlroots gør, og udvidelserne med `mangoError`, som mangos kode gør. Uden `-d`
  kun fejl (`WLR_ERROR`, mangos standard), med `-d` alt (`WLR_DEBUG`).
- **Config-fejl:** mangos `error_store.c` og `error_nag.c` i kernen, og mangonag
  (`mangonag/mangonag.c`) i `Sources/Mango/mangonag`; `nag_spawn` og `nag_kill` er kald over
  grænsen, hvor porten kører mangonags `main` i mangos proces. mangonags Wayland-side
  (`NagDisplay`: bjælken placeret og tegnet, knappernes fork, løkken med `-T`) er portens
  (`Nag.swift`).
- **Grænsen (`Sources/Boundary`):** `WindowSystem` (wlroots' plads), `NagDisplay` (mangonags Wayland-side), `EventLoop`
  (`wl_event_loop_add_fd` til IPC), `Screen`, `PortHooks`, `ConfigPort` (portens nøgler,
  modifiernavne, tastkoder) og `InputState`.
- **Porten (`Sources/Port`):** macOS-laget (`Port/macOS`: Accessibility, parkering, fokus,
  appens egne træk, vinduer ved start og tilbage, vinduer væk i `AwayWindows`, `KeySyms`,
  IPC's event loop) og udvidelserne (`Port/Extensions`), som kobler sig på gennem `PortHooks`.

## 6. Fejl i mango, rettet hos os

Hvor mangos egen kode er forkert, og vi gør det rigtige (CLAUDE.md, "Mango's bugs"). Hver er
aftalt, rettet så lidt som muligt, mærket `a mango bug` i koden og låst med en test.

| Fejl i mango | mango | Hos os | Rettelse |
|---|---|---|---|
| `tile`, `right_tile` og `vertical_tile` giver gruppens sidste vindue sin andel afrundet ned, så kolonnen kan mangle en pixel nederst (eller til højre). Andelen er `double`, forholdet `float`, og de to går ikke op. Det sker i omkring halvdelen af skærmhøjderne med lige store vinduer | 600 px på tre vinduer: 200, 199, 200 | 200, 200, 200 | Det sidste vindue får resten, som mangos egen `center_tile` gør (`if (r == 1) h = m->w.height - my - cur_gappov`). `TileLayouts.swift`, `LayoutGoldenTests` |
| Værnet mod en `source`, der læser sig selv (direkte eller gennem en anden fil): mango læser den igen og igen, til stakken løber tør | går ned | filen læses én gang, og det meldes | `includeStack` i `ConfigParser.swift`; `testASourceCycleIsReadOnce` |
| Et træk i `fair`, `vertical_fair`, `grid` og `vertical_grid` vælger naboen på den side af vinduet, man trækker i (`cursor_in_left_half`), og overskriver straks valget med tastaturets (*"Keyboard hotkey logic unchanged"*): naboen til højre, og kun for den yderste kolonne til højre den til venstre | tre kolonner, træk i midterste vindues venstre kant: dens højre kant flytter sig | venstre kant flytter sig | Tastaturets valg bruges kun ved tastaturet (`!isdrag`), og trækkets valg, som mango selv udregner, står. `resizeTileGridFair` i `Dispatch.swift`; `testAGridDragMovesTheEdgeItGrabs` |
| `focus_direction` sender venstre og højre gennem `focus_stack`, når tagget er monocle, også i overview, hvor kortene ligger i et gitter; samme funktion springer stakken over i overview tre linjer længere nede (`if (!isoverview)`) | overview fra et monocle-tag: venstre/højre følger vinduernes rækkefølge, ikke kortene | venstre/højre går til kortet ved siden af | Monocle-grenen gælder ikke i overview, som mangos egen `!isoverview`. `focusDirection` i `Dispatch.swift`; `testMonocleInTheOverviewGoesByTheCards` |
| Ved reload giver `parse_tagrule` alle vinduer master-bredden fra den sidste skærms tag, også vinduer på andre skærme, så en `tag_rule` med `monitor_name` kun virker på den sidste skærm | to skærme, 0,3 og 0,7: begge får 0,7 | hver skærms vinduer får deres egen | `c.mon === self` i `parseTagrule`; `testAReloadKeepsEachMonitorsOwnMfact` |
