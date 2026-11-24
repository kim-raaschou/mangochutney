# Afvigelser fra mango

Hvor Mango Chutney gør andet end mango 0.18.5 (`~/sources/mango`, commit `21f80a9`), og hvorfor. Kun det, der
gælder nu; det rettede og hvordan vi kom hertil står i [afvigelser-historik.md](afvigelser-historik.md).
Hver mango-nøgle, macOS ikke kan, står med grunden i [compatibility.md](compatibility.md) og
i `mango -p`.

Uden nogen `chutney_`-nøgle (portens blok sidst i `config.conf` slettet) opfører porten sig
som mango, så langt macOS tillader (afsnit 3) og bortset fra det, der ikke er bygget endnu (afsnit 4), og med de fejl i mango rettet, der står i
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
| `chutney_menu_config` | Panelets ændringer gemmes i `chutney_menu.conf`, som configen læser sidst; `config.conf` skrives aldrig. Mangos config-watcher læser ikke panelets egen skrivning igen (`configWriteIsOwn`) | `chutney_menu.conf` | `setoption` gemmer intet |
| `chutney_macos_appearance` | Fanebjælke, gruppebjælke, jump-mærker, switcher, titelbjælke, config-banner og overview i macOS' udseende, hvor ingen `*_decorate_*`-nøgle er sat; mangos farver i macOS' (`chutney_theme.conf`, følger accentfarve og lys/mørk); rammen følger vinduets runde hjørner | til | Mangos udseende og farver |
| `chutney_tab_bar_decorate_icon`, `chutney_group_bar_decorate_icon` | Appens ikon før titlen i fanebjælken og i gruppebjælken, én nøgle pr. bjælke som mangos `*_decorate_*` | til | Kun titler |
| `chutney_keybindings` (+ `chutney_keybindings_spotlight_launch`) | Keybindings-paletten: søg i bindinger, vinduer og programmer | Hyper K | Ingen |
| `chutney_layout_switcher` (+ `chutney_layout_switcher_*`) | Layout-switcheren; viser `circle_layout`, Tab og Space sætter den | Hyper L | Ingen |
| `chutney_launch_or_focus` | Én tast pr. app: start den eller gå til dens vindue; hvor valget ikke er givet (to set udefra, tre eller flere), vises vinduerne i switcherens panel | fra | Ingen |
| `chutney_fullscreen_tag` (+ `chutney_view_fullscreen`, `chutney_toggle_fullscreen`) | Et vindue i macOS-fullscreen får sin egen tag F1–F12 efter mangos tags (over `tag_num`), som det får sit eget Space; i menulinjen tegnes den som appens ikon. Taggen vises, når man er i dets Space; den har kun sit eget vindue, og mangos `tag`/`toggletag` brugt derfra ændrer vinduets egne tags. Ud af fullscreen er vinduet tilbage på sin tag og plads. Mangos fullscreen er macOS': `togglefullscreen` sætter appen i macOS-fullscreen (mangos `client_notify_fullscreen`), og macOS-fullscreen fra appen (den grønne knap, ⌃⌘F) er mangos. Tager macOS ikke imod beskeden om at gå i fullscreen (den taber den, mens den flytter et vindue mellem Spaces), er vinduet ude af mangos fullscreen igen efter skiftet; en besked om at gå ud venter porten på, for macOS kan stadig være på vej ud efter skiftet, og står vinduet stadig i fullscreen, sender tasten den igen. Et vindue, der kommer ud af fullscreen på en tag, der ikke vises, parkeres, også når macOS først lægger det tilbage, efter at porten har parkeret det | fra | Vinduet er ude af layoutet, til det er tilbage |
| `chutney_overlap_warning` | Et flisebelagt vindue, der er større end sit felt (og går ind over naboen), tegner sit tag orange i menulinjen | til | Intet mærke |
| `chutney_fit_layout` | Hvor en app holder sit vindue større end feltet: mangos `resizewin` på vinduet med det, det mangler, hvor layoutet har plads til det i bredden eller højden, også til den mindste størrelse, naboerne tidligere har holdt; intet, hvor der ikke er plads. dispatcheren altid, 1: menulinjens menu, 2: også en macOS-notifikation med en Fit-knap, eller en der siger, at der ikke er plads, 3: af sig selv | fra | Vinduet går ind over naboen, som i mango |
| `chutney_hyper_modifier` | Hvilke taster holdt sammen der er mangos `HYPER` (Mod3); porten oversætter dem, når de kommer ind. En binding på netop de taster uden `HYPER` kan ikke nås, og loggen siger det | `super+ctrl+alt` | Mangos Mod3 |

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
| `spawn` og `spawn_shell` kører kommandoen med `/bin/zsh -lc`, uden stdout og stderr (`Port/macOS/Spawn.swift`) | `spawn`: `wordexp` og `execvp`; `spawn_shell`: `sh -c`; stdout til stderr, `setsid` | En app, launchd starter, har ikke login-shellens `PATH` | `spawn,a \| b` kører en pipe hos os, intet hos mango |
| Kommandolinjen: `-v` skriver appens version, `-h` portens tekst, `--list-ignored` og `--list-glance` er portens, og ukendte argumenter ignoreres | `-v` skriver `VERSION`; et ukendt argument er en fejl | macOS giver en app egne argumenter (`-psn_…`, `-NS…`) | `-s` og `-r` mangler (afsnit 4) |
| Layout-paletten viser alle 14 layouts i et 5×3-gitter, når `circle_layout` mangler | `layouts[]`-rækkefølgen | Palettens opstilling | `switch_layout` følger mangos rækkefølge |
| Den medfølgende config (`Resources/config.conf`) er mangos `assets/config.conf` med mangos værdier; hvert sted, den ikke er det, står i en region mærket `# not mango default` (til `# end not mango default` eller filens slutning) med mangos linje nævnt: tasterne på Hyper, rofi og mangos midterklik udeladt, portens `chutney_*`-blok og Escape, der lukker overview (`bindp=NONE,Escape,leaveoverview`). | `assets/config.conf` | Tasterne må ikke tage macOS' og apps' genveje; portens nøgler | Brug mangos linjer i stedet for regionerne |
| `error_nag` tjekker for fejl, når `setup` er færdig, ikke på en timer på 1 ms | `config_error_nag_init`s timer | Porten er klar, når `setup` er færdig | Ingen |
| `watch`-linjerne sendes én gang pr. tur, efter de ventende begivenheder, med typerne fra turens `printstatus`-kald samlet (`notifyChanged` i `IPC/ipc.swift`) | `handle_print_status` med det samme | Én handling kalder `printstatus` mange gange; samlet pr. tur bygges hvert svar én gang, og en watcher får turens sidste tilstand | En tilstand, der kun findes mellem to `printstatus` i samme tur, sendes ikke |

## 3. Tvunget af macOS

| Hvad | Hvorfor |
|---|---|
| Vinduer på skjulte tags parkeres i et hjørne med en pixel synlig | Uden compositor kan et vindue ikke skjules |
| Menulinjens punkt viser alle skærme, hver med sine tags og sit layout, den valgte fuldt optrukket og de andre dæmpet (som AeroSpace og rift) | macOS tegner ét menulinjepunkt som kopi på hver skærm; en bar som waybar viser hver skærm sine egne |
| `client_get_parent`: en dialogs forælder er dens apps vindue, der sidst havde fokus; dialogen åbner flydende på forælderens skærm og med dens tags, som i mango. Andre vinduer har ingen forælder | macOS' Accessibility siger ikke, hvilket vindue der er et andets forælder |
| Hvilke vinduer der styres (popups aldrig), og hvilke der åbner flydende (dialoger), afgøres med AeroSpaces heuristik 1:1, med dens app-lister, og én ændring: AeroSpaces regel om vinduesniveau gælder alle apps, ikke kun dem på dens liste, så et vindue over normalt niveau (en notifikation, et flydende panel) aldrig styres; en `window_rule` med `is_floating` vinder. Som i AeroSpace flyder et vindue, der er minimeret, eller hvis app er skjult, når det findes | Wayland siger det med xdg-roller; macOS siger det ikke pålideligt, og AeroSpaces heuristik er afprøvet mod rigtige apps |
| Et vindue, der ikke kan blive mindre end sit felt, går ind over naboen og vokser indad fra en skærmkant, det ellers ville krydse; mango klipper det (`chutney_overlap_warning`: tagget bliver orange i menulinjen; `chutney_fit_layout` kan give det plads). Kernen tegner kant og bjælker om `c->animation.current` som mango; porten viser dem om vinduet, hvor det står, når ingen animation kører (`shownBorders`, `lag`) | Appen afviser størrelsen, og andre apps' vinduer kan ikke klippes |
| Efter mangos kantgreb (`enable_border_resize`) eller et træk vises en pil, til appen selv sætter sin markør igen, når markøren går ind over en ny del af den; i mango giver wlroots straks appen sin markør tilbage. På macOS 14 er de skrå markører på et flydende vindues hjørner et sigtekors | En app i baggrunden kan sætte markøren (`SetsCursorInBackground`), men ikke bede en anden app om at sætte sin igen; macOS 14 har ingen offentlige skrå markører |
| Mangos lag (`client_target_layer`) holdes, når mango giver fokus, men et klik med musen løfter altid vinduet; en app, der selv lægger sit vindue frem, når den bliver aktiv eller får sit nøglevindue (fx Arc, IntelliJ), kommer øverst alligevel; og et vindue, der får fokus under et højere lag, løftes heller ikke over sine naboer i sit eget lag | Klikket når macOS, før mango ser det; tastaturfokus kræver, at appen er aktiv, og en aktiv app ordner selv sine vinduer; porten kan lade være med at løfte et vindue, men ikke lægge et andet programs vindue over det aktive |
| Layoutet holder menulinjen og Dock'en fri | De svarer til mangos bjælker med eksklusiv zone |
| Ingen skygge, blur, dæmpning, gennemsigtighed eller runde hjørner fra mango; ingen luk- og fade-animationer | macOS tegner andre apps' vinduer; gennemsigtighed kræver SIP slået fra |
| Et vindue, som mango klipper ved sin skærms kant (scroller, tag-skift), tegnes helt; ligger der en anden skærm ud over kanten, parkeres det i stedet, så intet af det når nabo-skærmen, og hvor mango viser den klippede del, viser porten en plade: et stillbillede af vinduet taget ved parkeringen, klippet ved kanten (appens ikon uden Skærmoptagelse); pladen har vinduets kant, klippet ved kanten med den, og et klik fokuserer vinduet. Det parkeres også, når mango slukker det. Under en animation skifter vinduet størrelse billede for billede, hvor mango skalerer sin buffer | Andre apps' vinduer kan ikke klippes eller skaleres |
| Animationer skrives via Accessibility (højst 60 Hz) | Ingen compositor |
| Intet `client_negotiate_initial_size`, og derfor ingen af layouternes `*_predict` (`layout_predict_box`): mango giver et nyt vindue dets felts størrelse, før det vises; porten giver det sin plads, når mango mapper det. `LayoutContext` står i layouterne som i mango, uden kalder med `probe` | Et macOS-vindue findes med sin størrelse, før porten ser det; der er ingen første configure at svare på |
| Overview og switcher viser billeder (Skærmoptagelse), stillbilleder taget ved åbning; de rigtige vinduer bliver under dem, så `warp_cursor` sætter markøren på kortet (mangos `geom` i overview) | Andre apps' vinduer kan ikke skaleres; en strøm pr. vindue koster meget |
| Kantgrebet (`enable_border_resize`) tager kun et klik, som event tap'en har taget fra appen; den afgør det ud fra mangos `hover_resize_edge` ved forrige bevægelse. Er markøren lige kommet på eller af striben, kan det ene klik gå til appen, eller gå tabt | Tap'en skal afgøre klikket med det samme, før appen får det, og kan ikke vente på mango |
| `mangonag` er ikke et eget program: dens kode (`Sources/Mango/mangonag`, 1:1) kører i mangos proces, og porten står for dens Wayland-side (`NagDisplay`): bjælken tegnes med AppKit (mangonags farver, skrift, fire linjer, ANSI-farver og knapper) og står under menulinjen (eller over Dock'en); `-y` (lag) gør intet, bjælken står over vinduerne; tilvalgene læses med macOS' `getopt`, som ikke flytter tilvalg efter et løst argument frem, som glibc's gør | mangonag er en Wayland-klient på en layer surface, tegnet med cairo og pango; et program at kalde selv har en Mac ikke brug for (macOS' notifikationer) |
| En terminalknap i bjælken (Edit) åbner macOS' Terminal, når hverken `$TERMINAL` eller en af mangos terminaler (foot, alacritty, kitty, wezterm, st, xterm) findes; scriptet hedder `.command` | mango kører den så i `sh` uden terminal, og `vi` kan ikke køre uden en |
| Et vindue i macOS' egen fuldskærm (den grønne knap), i Dock'en (med `ignore_minimize`, mangos standard), i en skjult app (⌘H) unmappes med mangos `handle_client_unmap` og mappes tilbage på sin plads, når det kommer igen; pladsen huskes, så længe det er væk. Fra fuldskærm siger appen, hvilket vindue der har tasterne, og flisen skrives, når macOS har flyttet det færdigt. Mango ser det ikke imens, heller ikke i `mmsg get all-clients` | macOS har allerede taget vinduet væk; mango ville have det unmappet |
| Mangos `client_notify_fullscreen` siger kun appen besked med `chutney_fullscreen_tag`; uden nøglen fylder mangos fullscreen skærmen, uden at appen ved det. `togglefakefullscreen` siger aldrig appen besked. En app, der ikke kan gå i macOS-fullscreen, bliver i mangos. macOS-fullscreen fra appen går gennem mangos `togglefullscreen`, som også tager vinduet ud af en scratchpad; mangos `handle_client_request_fullscreen` gør ikke | macOS kan kun sige en app, at den er i fullscreen, med sin egen fullscreen, som giver vinduet sit eget Space; fake fullscreen findes ikke på macOS |
| Et parkeret vindue i en app, der ikke svarer, bliver mappet, som i mango, men kan ikke flyttes frem: dets flise står tom, til appen svarer | Et vindue flyttes gennem appen (Accessibility); en Wayland-klient, der hænger, vises med sit sidste billede |
| Rammen (og fane- og gruppebjælken) står, hvor appen sidst har sat vinduet, så længe en skrivning til det ikke er udført; et vindue, der hentes fra parkering, får først sin ramme, når appen har flyttet det | Et vindue flyttes gennem appen (Accessibility), som svarer efter 5–400 ms; wlroots viser rammen og vinduet i samme billede |
| En holdt tasts gentagelser: højst én venter på hovedtråden ad gangen | macOS sender gentagelserne selv; mangos egen gentagelsestimer stabler dem aldrig |
| Fokus sendes til macOS én gang pr. tur, for det sidst fokuserede vindue, og mangos løft (`client_raise_group`, `client_raise_tab`) af det vindue går med i samme kald; et parkeret gruppemedlem løftes ikke. Mens portens panel eller overviewets billeder er fremme, holdes fokus tilbage og gives, når de lukker | Fokus på macOS er en synkron forespørgsel til WindowServer og appen; et løft og et fokus hver for sig går i to køer og flimrer |
| Seatet (`keyboardFocusedSurface`, mangos `client_focus` vender tidligt om på det) er det vindue, mango sidst gav tasterne; det ryddes, når macOS giver tasterne til en anden app eller et vindue, mango ikke styrer. Har macOS selv givet et vindue tasterne (et klik, ⌘Tab), sender `client_notify_enter` intet | macOS flytter tasterne uden mango; wlroots' seat ved altid, hvor de er |
| Kant-, fane- og gruppevinduer lægges kun om, når de ligger forkert | Hver omlægning venter på WindowServer; én forespørgsel på rækkefølgen er billigere |
| Giver macOS et parkeret gruppemedlems vindue fokus (et klik i Dock'en, ⌘\`), byttes det ind i gruppen (`clientFocusGroupMember` i `Port/macOS/MacEvents.swift`); mango ignorerer en aktivering af et parkeret medlem (`handle_client_activation_request`, intet foreign toplevel) | macOS har allerede givet vinduet fokus og lagt det frem |
| En global tast (`globalkeybinding` i en vinduesregel) sendes ikke, når målvinduets app er den, der har fokus (`input/keyboard.swift`) | En tast sendes til en app, ikke til et vindue; appen med fokus får den alligevel |
| Vinduer, der er der ved start eller kommer igen efter dvale, beholder deres plads; layout, tags og grupper gemmes og kommer igen efter en genstart og dvale | En genstart af mango lukker ikke vinduerne, og macOS melder vinduer væk og tilbage omkring dvale |
| Titelbjælkens anden linje er appens bundle id | macOS' nærmeste svar på `app_id` |
| `app_id` i en vinduesregel og i `toggle_named_scratchpad` matcher også appens navn (`Safari`), ikke kun bundle id'et (`com.apple.Safari`) | macOS har intet `app_id`; bundle id'et er det nærmeste, navnet det, man kender |
| `monitor_name` i regler og skærmnavnene i IPC er macOS' navn for skærmen (`BenQ RD280U`), ikke udgangen (`DP-1`) | macOS navngiver ikke udgange |
| `tag_rule`s `monitor_make` er skærmens PNP-id (`BNQ`), ikke fabrikantens navn (wlroots: `BenQ Corporation`); `monitor_model` og `monitor_serial` er EDID'ens som hos wlroots. En skærm, macOS ikke har dem for, matcher ikke (som en skærm uden EDID hos mango), og to ens skærme uden serienummer får intet | macOS har EDID'ens felter i IORegistry (Apple silicon), men ingen PNP-navnetabel |
| `last_open_surface` (i `get` og `watch`) er altid tom | Den sættes, når en layer-shell-flade åbner; macOS har ingen layer shell |
| `confine_pointer` sætter markøren tilbage, når den er nået over kanten | macOS flytter markøren, før mango ser bevægelsen |
| `xkb_rules_options`: kun de muligheder, der flytter taster, med macOS' egen omlægning | macOS har ingen xkb |
| Systemets trackpad-gestures konkurrerer med `gesturebind` | macOS ejer dem |
| Swipe: porten giver mangos `handle_cursor_swipe_begin` og hvert trin ud fra den samlede afstand, macOS' multitouch melder; kommer en finger til, er swipet `cancelled`, løftes en, slutter det, som libinput gør. Et klik under et træk med en gestus når appen | macOS' private multitouch-ramme har ingen begin-, trin- eller annulleringshændelser, kun fingrenes positioner, og event tappet kender ikke gestussens træk |
| IPC: Unix-socket `/tmp/mango-<bruger>.sock`, kun brugerens (0600), og en anden kørende mangos socket overtages ikke; `mmsg` bruger den, når `MANGO_INSTANCE_SIGNATURE` mangler (mango: fejl), og `SO_NOSIGPIPE` for `MSG_NOSIGNAL`; `get tag` tager tallet som sidste felt; sende-bufferen er 1 MB; fejler `ipc_init`, logges det (mango vender tavst om) | Ingen `XDG_RUNTIME_DIR`; et program, Dock'en eller Terminal starter, er ikke mangos barn; skærmnavne har mellemrum; macOS' buffer er 8 KB, og et svar sendes uden at vente |
| `source=` med relativ sti læses fra config-mappen; ingen `/etc/mango`-fallback. En tom `source=` er derfor mappen, som læses som tom uden fejl (mango: `Failed to open config file`) | Under launchd er arbejdsmappen `/`; macOS har ingen `/etc`-config |
| Første start skriver `Resources/config.conf` som `config.conf`: mangos config med mangos taster på Hyper (en tast, brugeren vælger som i Raycasts Hyper Key: Caps Lock, en venstre/højre modifier eller F1–F12; `chutney_hyper_key`), ikke mangos egne taster, og de første linjer at prøve nær slutningen. Også et velkomstvindue, der åbner Getting Started | mango læser `/etc/mango/config.conf`, når brugeren ingen har; en Mac-app har ingen `/etc`-config. mangos taster (⌘M, ⌘N, ⌥+bogstav, ⌃+pile) er macOS' og appernes genveje |
| Input besluttes på event tappets tråd; `setkeymode`, `chvt`, `reload_config` og `load_config_file` stopper søgningen efter bindinger. Tappet får bindingerne og de globale taster, når de ændres, også fra `printstatus` (`publishGlobalKeys`) | macOS vil have svaret med det samme; dispatcherens svar kendes først på hovedtråden |
| Timere: cursor-skjul (som mangos), billedurets reserve-timer (kun uden skærm), 0,4 s ekstra genstabling efter fokus, sen genlæsning af vinduets ramme, ét forsøg pr. sekund på at sætte et vindue tilbage, samling af skærm- (0,3 s) og config-ændringer (0,15 s, som mangos), appens egne rapporter lige efter et træk (0,4 s), 0,05 s efter menuen, ventetid ved genstart og `mmsg service`, hovedtrådens vagt, mangonags `-T` (kun når den er sat; config-fejlenes bjælke har ingen) | macOS melder ikke alt som en begivenhed |
| `get all-devices` lister macOS' HID-enheder (IOKit): tastaturer, mus, trackpads, touchskærme og tablets; grænseflader på samme sted (USB-port, Bluetooth-enhed) er én enhed. `vendor`/`product` er IOKits (0 for Macens indbyggede), og `matched` er altid `false` | macOS har ingen libinput; `device_rule` virker ikke på macOS |
| `watch all-devices` sender kun sin første linje (`{"name":null,"type":null}`); `ipc_notify_device_event` sendes aldrig | macOS' tastatur- og musehændelser (CGEvent) siger ikke, hvilken enhed de kom fra |
| mangonag reserverer ikke plads (`set_exclusive_zone`): flisede vinduer flyttes ikke ned under bjælken, den står over dem | Ikke bygget: porten skulle trække bjælkens højde fra skærmens arbejdsområde, mens bjælken står, og lægge skærmene om ved åbning og lukning. Kan bygges |
| Bindinger matches på macOS-tastkode, ikke på keysym: `binds` (`KEY_TYPE_SYM`) læses af konflikttjekket og af `parse_key`. En keysym uden tast i det aktuelle layout er `Unknown key`, og i en `binds` droppes den uden besked (mango beholder den og matcher på keysym, `resolve_keybinding_layout`); et `XF86`-navn uden for portens tabel giver hverken fejl eller binding. `code:N` er en macOS-tastkode, ikke en xkb-kode. En museknap `code:N` uden for 272–279 sammenlignes med macOS' knapnummer, så `code:280` virker aldrig, og `btn_side`/`btn_back` (og `btn_extra`/`btn_forward`) er samme knap | macOS har ingen xkb-keymap og ingen evdev-knapkoder. Modellen med keysym-bindinger er sat på hold af brugeren 2026-11-14 |

## 4. Mangler endnu

Det af mango 0.18.5, macOS tillader, og som ikke er bygget endnu (`switch_keyboard_layout` er
fravalgt, afsnit 2):

- Fokus-animationen (`client_start_focus_animation` og dens fire hjælpere): kantens farve glider
  ikke fra `bordercolor` til `focuscolor`; `animation_duration_focus` og `animation_curve_focus`
  læses ikke (`MangoCompat`: ikke bygget). Gennemsigtigheds-halvdelen kan macOS ikke (afsnit 3).
- Hover-farven på gruppebjælkens lukkeknap (`mango_bar_decoration_set_close_hover`).
- Runde hjørner ved skærmkanten (`set_client_corner_location`): porten har én radius for hele
  rammen, så et vindue, der står mindre end `border_radius` ud over kanten, får et skåret hjørne.
- `check_size_per_valid` (kun en kontrol, ingen opførsel).
- Kommandolinjens `-s <cmd>` og `-r <fd>` (med `fd_set_nonblock` og `child_pid`), `XDG_CURRENT_DESKTOP=mango`
  og `increase_nofile_limit`/`restore_nofile_limit`.
- Man-siderne `mmsg.1` og `mangonag.1`.
- Funktioner, mango selv ikke kalder: `unminimize`, `get_layout_abbr`, `starts_with_ignore_case`
  og `mod_to_string`.

Af de 31 commits fra 0.18.2 rammer disse ikke macOS: lag- og låseflader (`a3990ec`,
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
  end mangos har én linje `/// mango <funktion> (<fil>)` (52 i alt, mest typer og hjælpere fra
  mangos headere og funktioner delt i to, fordi portens tråde kalder dem hver for sig).
- **Portens vindue i kernen:** kernen læser ikke `c.parked` eller `c.frame` (felterne er portens).
  Hvor mango spørger wlroots, spørger kernen porten: `c->scene->node.enabled`
  (`c.platform.sceneNodeEnabled`) for pointerens tjek og `node_at_point`, `client_get_geometry`
  (`clientGetGeometry`) for switcherens størrelse og `wlr_scene_node_coords`
  (`sceneSurfaceCoords`) for hvor et vindue rammes. Et skjult vindue, mango flytter til en anden
  skærm, parkerer porten selv i den nye skærms hjørne (`Placement.commitFrame`).
- **Bevidst i kernen, mærket:** overview med
  billeder (`Monitor.ovThumbnails`, `ovCards`) og `parse_option` som en tabel. Hvad der ellers står i kernen uden at
  være mangos, står i `docs/analyse-udenfor-kernen.md`.
- **Mærket i kernen, som at skrive mangos C i Swift:** `f32` (en værdi, mango har i et
  float-felt, afrundet som C), `i32` (C's omregning af et kommatal til `int32_t`), `wl_list`-hjælperne
  i `common/util.swift` på klientlistens array, og `1 << (prevtag - 1)` med
  `prevtag` 0 i tag-animationerne regnes som intet tag (C's skift er udefineret; Swift stopper
  programmet). En klippeboks' bredde læses som `size.width`, for `CGRect.width` er aldrig
  negativ, og `wlr_box`'s kan være det (`clip_to_hide`). `oldmonname` holder
  skærmens display-ID, ikke navnet, for to skærme kan have samme navn.
  Hvor mango læser en pointer, der altid er sat (`c->mon` i et arrange), stopper en `guard` i
  Swift ved nil (`not in mango: c->mon is always set here`).
- **`struct Client` (`client.h`):** felterne står i mangos rækkefølge med mangos navne. Typerne er
  mangos, med fire faste omskrivninger: `struct wlr_box` er `CGRect` med hele tal, og `bw` er
  `CGFloat` som dem; `int32_t`-flag (`isfloating`, `no_border`, …) er `Bool`; `animation_type_open`
  er `AnimationType?` (nil er mangos -1); `jump_char` er `Character?`. `oldmonname` er skærmens id
  (ovenfor), `sel`/`prevsel` og `tab_prev` er `weak`. Uden macOS-del, så felterne mangler: scenen
  (`scene`, `border`, `droparea`, `splitindicator`, `shadow`, `shield`, `blur`, `scene_surface`,
  `image_capture_*`, `overview_scene_surface`, `dim_node`, `ov_card_tree`, `ov_card_surfaces`;
  porten tegner), `surface` og lytterne (wlroots), XWayland-felterne, `xdg_geo_x/y`,
  `foreign_toplevel`, `ext_foreign_toplevel`, `decoration`, `opacity_animation`,
  `focused_opacity`, `unfocused_opacity`, `no_blur`, `blur_opacity`, `no_shadow`, `no_radius`,
  `shield_when_capture`, `swallowdby`/`swallowing`, `isterm`, `no_swallow`, `allow_csd`,
  `tearing_hint`, `force_tearing`, `idleinhibit_when_focus`, `vrr_only_fullscreen`,
  `allow_shortcuts_inhibit`, `force_render`, `group_bar` og `tab_bar` (bjælkerne tegnes af porten;
  `tabBarEnabled`). Afgøres med `client.c`, hvor de bruges: `need_float_size_reduce`,
  `ignore_maximize`, `activation_bypass`, `fullscreen_backup_*`, `animation_type_close`,
  `no_fade_in`, `no_fade_out`, `force_fakemaximize`, `force_tiled_state`, `old_ismaster`,
  `snapshot_temp_visible`. Portens egne felter står øverst og er mærket (`platform`, `bundleId`,
  `appName`, `title`).
- **Faner:** mangos `manage/tab.c` står i kernen (`manage/tab.swift`) med fanekæden på klienten
  (`tab_prev`, `tab_next`, `is_tab_focus`, `is_tab_hidden`) og `tab_member_count` på serveren.
  `client_chain_head` og `client_chain_unlink` tager felterne som key paths, ikke offsets. Barens
  scene-node er portens: `tab_bar_set_enabled` sætter `tabBarEnabled`, og porten tegner bjælken ud
  fra den. Uden macOS-del: `tab_update_input_penetration`, `client_reparent_tab` og barens
  oprettelse, titel og config (porten tegner bjælken med titlen ud fra stripen).
- **Fane- og gruppebjælker:** mangos `client_draw_tabbar` (`manage/tab.swift`) og
  `client_draw_group_bar` (`animation/animation-client.swift`) står i kernen med anker (`c->geom` under
  åbne-animationen), kantklipning (`compute_edge_offsets`, `client_is_ignore_output_clip`) og
  bredde-deling. De kaldes for alle vinduer på én gang (`drawBars`), ikke fra `client_set_clip` pr.
  vindue, og giver porten en strip at tegne som ét panel med en boks pr. medlem, hvor mango
  placerer en bar-node pr. medlem. Klippes en fanebjælke helt væk, tegner porten ingen; mango
  lader barerne stå, hvor de var.
- **Skærme:** mangos `manage/monitor.c` står i kernen (`manage/monitor.swift`) i mangos rækkefølge.
  Porten melder skærmene, som wlroots melder outputs (`rebuildMonitors` i
  `Sources/Boundary/Outputs.swift`): en ny skærm er `handle_new_output`, en skærm, der er væk, er
  `handle_output_destroy`, og hver ændring ender i `handle_output_layout_change`. `m` og `w` er
  mangos felter: `m` er skærmens ramme og `w` macOS' arbejdsområde, der står for `arrange_layers`.
  `monitor_at_point`, `get_monitor_nearest_to` og `monitor_from_direction` regner på skærmenes
  bokse, hvor mango spørger `wlr_output_layout`. Uden macOS-del: tilstande, regler, skala,
  transform, VRR, HDR, ICC, blur, lag, låseskærm, frame-skip-timeren, output-manageren,
  xdg-output og XWayland; macOS melder kun de skærme, der er tændt, så der er ingen slukkede
  outputs at springe over. Før porten har sine vinduer, giver `handle_output_layout_change` ikke
  fokus, og `arrange` gør intet (`started`). Ved start vælges skærmen under markøren med mangos
  linje fra `run`; hos mango står wlroots' markør da endnu i (0,0), så mango får skærmen ved
  layoutets origo, porten den under macOS' markør. Er markøren uden for alle, beholdes den,
  `handle_output_layout_change` valgte.
- **Dispatchere:** mangos `dispatch/bind.c` står i kernen (`dispatch/bind.swift`) i mangos
  rækkefølge, hver med `Arg`, og `parse_func_name` (`Config/binding_parse.swift`) vælger dem.
  Konfigurationen gemmer bindingens felter; `parse_func_name` kører, når bindingen kører, hvor mango
  kører den, når konfigurationen læses. Et felt, bindingen ikke giver, er `0` fra en nøglebinding og
  tomt fra IPC, som i mango. Ingen macOS-del (markerede funktioner, der ingen ting gør): `chvt`,
  virtuelle outputs, `togglehdr`, `toggle_trackpad_enable`, `switch_keyboard_layout` og
  `*_monitor`. Retningerne er mangos tal (`UP`…`ALLDIR`, `SWIPE_*`), også i akse- og
  gestus-bindingerne.
- **Input:** mangos `input/pointer.c`, `keyboard.c` og `trackpad.c` står i kernen
  (`input/pointer.swift`, `keyboard.swift`, `trackpad.swift`) i mangos rækkefølge, med mangos greb
  (`cursor_mode`, `grab_client`), træk-til-tile (`client_begin_drag_float`, `pointer_place_drag_tile`,
  `client_set_drop_area`) og `pointer_focus`: fokus ved markøren kun med en tid og kun når markøren
  går ind i en ny flade. Grænsen har seatets pointerfokus (`pointerFocusedSurface`,
  `seatPointerNotifyEnter`, `seatPointerClearFocus`); fladen under markøren er vinduet under
  punktet, og portens egne vinduer (kanter, bjælker, overview) giver ingen. macOS flytter markøren,
  før mango ser bevægelsen, så der er ingen `wlr_cursor_move`; `dx`/`dy` er forskellen fra portens
  forrige hændelse. Når appen selv trækker et vindue i titelbjælken, gør porten mangos træk
  (`Port/macOS/UserDrag.swift`). Tastaturets bindinger matcher på portens taster, ikke keysyms (ingen
  tabel). Ingen macOS-del: constraints, cursorbilleder, libinput, drag-and-drop, virtuelle enheder,
  keymaps, `keyboard_repeat`, shortcut-inhibitor, pinch og hold, `device.c`, `switch.c`, `tablet.c`,
  `touch.c`.
- **Config og IPC:** mangos `config/*.c` og `ipc/ipc.c` står i kernen i filer med mangos navne
  (`Config/load.swift`, `option_defs.swift`, `value_parse.swift`, `binding_parse.swift`,
  `variable_expand.swift`, `conflict_check.swift`, `reapply.swift`, `watcher.swift`, `error_store.swift`,
  `error_nag.swift`, `toml_parse.swift`, `parse.swift`; `IPC/ipc.swift`). Mærket i koden: `parse_option`
  er en tabel; regex er ICU's (`NSRegularExpression`) for PCRE2, med ICU's fejltekst uden offset og
  den tomme pattern som `(?:)`; `nan`, som `strtod` læser, bliver 0, og `inf` også, undtagen hvor mango
  klemmer værdien, før den bruges (der bliver den grænsen, som i mango), for Swift går ned ved omregning
  til heltal, hvor mangos C giver skrald; `monitor_rule`, `layer_rule` og `device_rule`
  tjekkes som i mango, men gemmes ikke (macOS har ingen del); `parse_tag_mask`'s `TAGMASK` er alle tags
  undtagen tag0 (ingen server ved parsning). Uden macOS-del: xkb/keymap, `cleanup.c`, `preset.c`,
  inotify. Uden `HOME` læser mango ingen config; porten vælger `/.config/mango/config.conf`.
  `nan` bliver også 0 i kommatal-nøgler, hvor mango klemmer værdien (`CLAMP_FLOAT`).
- **Klienter:** mangos `manage/client.c` står i kernen (`manage/client.swift`) i mangos
  rækkefølge. `client_park` giver medlemmet `mon` nil, som mango, og `client_is_parked` er
  listemedlemskab; `groupParked` er portens mærke (`clientsAll`), og porten parkerer et parkeret
  medlems vindue på gruppens skærm (`client_group_active`). En klient, der har været
  væk (macOS-fuldskærm, minimeret, skjult), genbruges af porten, så af `init_client_properties` i
  unmap nulstilles kun `iskilling` og `drag_to_tile`. Ingen macOS-del: swallowing, foreign toplevel,
  scene-noderne ved map, `client_reparent_group`, regel-felterne MangoCompat lister.
- **C's egne hjælpere:** hvad Swift selv har, findes ikke: `die`, `ecalloc`, `utf8_strlcpy`,
  `wayland_string_set`, `string_printf`, `join_strings`, `join_strings_with_suffix` (Swifts strenge),
  `wl_list_append` (listen er et array) og `timespec_to_ms` (`get_now_in_ms` regner selv i ms, og
  tests kan stille dens ur, `nowInMsOverride`).
- **Faste C-buffere:** hvor mango skærer en streng af ved en buffers størrelse uden at sige det
  (`snprintf` med `%.255s`, `fgets` på 4096 tegn, `vsnprintf` i loggen), beholder Swift den hel;
  hvor mango melder en fejl eller stopper ved grænsen (en for lang toml-sektion, -linje eller
  -liste), gør kernen det samme.
- **Frigørelse:** Swift frigør selv, hvad ingen holder (ARC): `cleanup.c`, `dwindle_free_tree`,
  `cleanup_monitor_dwindle` og mangos andre rene `free`-funktioner findes ikke. Et dwindle-blad,
  hvis klient er væk (klienten holdes svagt), tages ud af træet i `dwindleCore` (`removeDeadLeaf`).
- **Mangos filtre som lister:** hvor mango går `server.clients` igennem med `VISIBLEON`,
  `ISTILED` eller special-tagget, har kernen `visibleClients`, `tiledClients` og `specialClients`
  (`common/server.swift`), og `arrangeAll` for mangos løkke over skærmene; alle mærket.
- **Layer shell (`layer.c`):** macOS har ingen layer shell; filen har ingen macOS-del.
- **Hvad der er under markøren:** mangos `node_at_point` går scenen igennem fra øverste lag; porten
  har ingen scene, så `nodeAtPoint` (`manage/misc.swift`) skriver rækkefølgen ud: overview-kortene
  (et flydende kort over gitteret), ellers det øverste lag under punktet (`client_target_layer`) og i
  laget vinduesserverens øverste vindue, ellers fokus-stakkens første; med special-tagget fremme kun
  dets vinduer, som mangos dæmpning ingen vinduer under sig giver. `group_bar_target_at` går samme
  lag igennem, med bjælken nederst i sin klients lag. Bjælkerne svarer portens paneler for
  (`BarButton`), og fladen giver `surfaceAt`. Lag-flader og IM-popups har macOS ikke.
- **Lag:** `client_target_layer` er i kernen 1:1, og porten bruger den, når mango giver fokus: ligger
  et synligt vindue i et højere lag over det, får vinduet fokus uden at blive løftet (`lifts`), så
  det højere lag bliver øverst. `client_sync_layer` og `client_reparent_group` (et vindue og dets
  gruppebjælke flyttes til et andet lag i scenen) har ingen funktion i kernen; porten ordner
  vinduerne i `restack`.
- **Animationer:** mangos `animation/client.c`, `animation/tag.c` og `animation/common.c` står i
  kernen (`Sources/Mango/animation/animation-*.swift`; SwiftPM tillader ikke to filer med samme navn
  i ét modul) med `c->animation`, `geom` (med kanten), `pending`, `current`, `animainit_geom` og
  `bw`, og `handle_output_frame` i `manage/monitor.swift`. Porten står for wlroots: et billedur
  (display link) kalder `handleOutputFrame` for hver skærm med et planlagt billede
  (`wlr_output_schedule_frame`), og `wlr_scene_node_set_position` og
  `wlr_scene_subsurface_tree_set_clip` skriver vinduets ramme. macOS kan ikke klippe et andet
  programs vindue: det tegnes helt og parkeres, hvor den klippede del ville nå en anden skærm, og når mangos
  synlighed (`client_should_visible`, også `clip_to_hide`) slukker det. Rammerne skrives og de
  slukkede vinduer parkeres, når billedet afleveres (wlroots' output commit): et `arrange`s
  `resize` af ét vindue (`set_arrange_visible`s og layoutets) når appen som én skrivning, og et
  vindue parkeres først, når billedets synlige vinduer er skrevet, så intet hul viser skrivebordet,
  når et vindue afløser et andet (monocle, faner). Det er mangos frame-skip (`handle_output_frame`,
  `monitor_check_skip_frame_timeout`): uden animationer og uden træk venter vinduerne, der skal væk,
  på dem, der kommer frem på samme skærm, højst mangos 100 ms (`skip_frame_timeout`, en timer som
  mangos); mango holder hele billedet, porten kun de vinduer, der skal væk. Uden macOS-del, mærket i
  koden: buffer-effekter, fokus-opacitet (`client_set_focus_opacity` giver false), pointer-enter ved
  animationens slut, `force_render`, swallowing, størrelses-hints (`client_set_size_bound` får ingen fra
  macOS) og kortene i overviewet (`ov_card_tree`). Kanter og bjælker tegnes for alle vinduer på
  én gang efter billedet (`bordersDirty`), hvor mango tegner dem pr. vindue i `client_set_clip`.
  Kurverne bages som i mango (`init_baked_points`, 256 punkter) og slås op med
  `find_animation_curve_at`; fade-kurverne (`opafadein`, `opafadeout`) har ingen macOS-del, og
  FOCUS-kurven bruges ikke, før fokus-animationen er bygget (afsnit 4).
- **`arrange` (`Layout/arrange.swift`):** mangos `arrange`, `pre_calculate_before_arrange`,
  `special_handle_empty_view` og tabellen `layouts[]`, der kalder mangos layouts
  (`horizontal.swift`, `vertical.swift`, `dwindle.swift`, `scroll.swift`) og i overview
  `overviewlayout`. Mærket i koden: `client_sync_layer` er portens løft til sidst
  (`clientRaiseLayers`, med det valgte vindue øverst i monocle og deck, hvor porten parkerer
  resten); `special_sync_top_layer` og `check_idle_inhibitor` har ingen macOS-del; `ltidxs` holder
  layoutets id; et `isunglobal`-vindue får ingen `set_arrange_visible`, så porten skriver aldrig dets
  ramme (mango lader det stå, hvor det står).
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
- **`client_focus`:** 1:1 med mangos trin og rækkefølge, `lift` skrevet ud ved hvert kald. Uden
  macOS-del: `session_locked`, opacity,
  `client_check_tab_node_visible` (porten tegner bjælkerne ud fra `sel`), idle inhibit, vrr, foreign
  toplevel, `exclusive_focus` (layer shell), `client_wants_focus` (X11) og
  pointer constraints. Uden klient
  kommer `printstatus` efter, at `sel` er ryddet, for portens status læser den med det samme.
- **Title message bar:** mangos `draw/title_message_bar.c` står i kernen (`draw/title_message_bar.swift`),
  én bar pr. skærm (`Monitor.titleMessageBar`); baren selv (`MangoBarDecoration`, mangos `text-node.c`
  og scene-node) tegner porten. I overcircle ligger den under klientens kort, ikke under `c->geom`
  eller `c->animation.current`, og den sættes én gang, når kortet er sat (ved start og ved hvert
  skift), hvor mangos `client_draw_frame` flytter den med hvert billede. `chutney_launch_or_focus` lægger den under sit eget panel gennem
  `PortHooks.titleMessageBarGeometry`.
- **Overview:** mangos `set_overview`, `toggle_overview`, `enter_overview`, `leave_overview`,
  `over_circle`, `overview`, `overview_backup`, `overview_restore` og `want_restore_fullscreen` står i
  kernen (`dispatch/bind.swift`, `overview/overview.swift` og `Layout/layout-overview.swift`; SwiftPM
  tillader ikke to `overview.swift` i ét modul) med skærmens `isoverview`, `ovTabLayout` og `ovNormalMode`, så hver
  skærm har sit eget overview. Kortene er portens billeder, ét panel pr. skærm, hvor mangos kort-træer
  er (`overview_backup_surface`, `overview_destroy_card`); `overview_scale` og `overview_scale_tab`
  lægger dem gennem `client_tile_resize` i `Monitor.ovCards`, hvor mango flytter klienterne, og
  `overview` lægger kortene ud én gang pr. arrange, hvor mangos `client_draw_frame` gør det pr.
  klient; et vindue, layoutet ikke gav et kort (flydende, fullscreen, maksimeret), får sit kort,
  hvor det står, som mangos kort-træ; uden Skærmoptagelse flyttes de rigtige vinduer. Uden macOS-del, mærket i koden:
  `client_set_tiled` i `overview_backup` og `overview_restore` og `refresh_monitors_workspaces_status`
  (ext-workspace; `printstatus`). Switcheren (`switcher/switcher.swift`) har mangos felter og tegnes
  af porten; `chutney_launch_or_focus` har en kopi af dens layout-regning i porten
  (`SwitcherPanelLayout`), for udvidelsen lægger sin egen vindusliste ud.
- **Jump-tilstand:** mangos `toggle_jump`, `begin_jump_mode`, `create_jump_hints`, `finish_jump_mode`,
  `overview_update_jump_label` og `keyboard_find_jump_client` står i kernen med `Monitor.isJumpMode` og
  klientens `jumpChar`, `jumpKeycodes` og `jumpLabelNode`; mærket selv (`MangoJumpLabel`, mangos
  `text-node.c` og scene-node) tegner porten som et lille panel over overview, og
  `find_keycodes_for_keysym` (xkb's keymap) er portens tastaturtabel. Mærket sættes én gang ved kortets
  mål, hvor mangos `overview_layout_card` flytter det med hvert billede, og dets sted er skærmens,
  da porten ikke har klientens scene-træ. Event-tap-tråden får `is_jump_mode` og klienternes taster i
  `InputState`, så den kan sluge dem; hovedtråden spørger på `is_jump_mode`, efter at bindingerne har
  kørt, som mango. Har en gennemslupnings-binding (`bindp`) forladt overview, er tasten dog slugt, hvor
  mango sender den videre.
- **`reset_option` og opstarten:** `reset_option` har mangos trin i mangos rækkefølge
  (`resetOption` i `config/reapply.swift`), og opstarten følger `setup` og `run`: `exec` og `exec_once` kører
  til sidst, når skærmene er sat op, og et reload kører kun `exec`. Uden macOS-del, mærket i koden:
  `reset_blur_params`,
  `reapply_rootbg` (porten læser `rootcolor`, hvor den tegner), `reapply_keyboard`,
  `reapply_monitor_rules`, xcursor-delen af `reapply_cursor_style` og `bw` og
  `client_set_tab_bar_config` i `reapply_property` (kanten og bjælken tegnes ud fra config).
  `reapply_pointer`s plads har portens gestus-overvågning. `run`s del ligger sidst i `setup`.
- **Config-watcheren:** mangos `config/watcher.c` med dens kqueue-del (mangos egen på macOS) står i
  kernen (`Config/watcher.swift`); dens filer og debounce-timer er wayland's event loop på grænsen.
- **Grænsen (`Sources/Boundary`):** `WindowSystem` (wlroots' plads), `Outputs` (wlroots'
  output-events), `MangoBarDecoration` og `MangoJumpLabel` (mangos tekstnoder), `Decorations`,
  `NagDisplay` (mangonags Wayland-side), `EventLoop` (`wl_event_loop_add_fd` og `_add_timer`, til
  IPC og config-watcheren), `Screen`, `InputDevice`, `Swipe`, `WlrLog`, `PortHooks`, `ConfigPort`
  (portens nøgler, modifiernavne, tastkoder) og `InputState`.
- **Porten (`Sources/Port`):** macOS-laget (`Port/macOS`: Accessibility, parkering, fokus,
  appens egne træk, vinduer ved start og tilbage, vinduer væk i `AwayWindows`, `KeySyms`,
  IPC's event loop) og udvidelserne (`Port/Extensions`), som kobler sig på gennem `PortHooks`.

## 6. Fejl i mango, rettet hos os

Hvor mangos egen kode er forkert, og vi gør det rigtige (CLAUDE.md, "Mango's bugs"). Hver er
aftalt, rettet så lidt som muligt, mærket `a mango bug` i koden og låst med en test (en Swift-test
eller en facit-scenarios `ours`-linje). Det er det eneste sted, en enkelt detalje i mangos kode får
sin egen test; at resten er 1:1, kontrolleres fil for fil i `docs/verificeret.md`.

| Fejl i mango | mango | Hos os | Rettelse |
|---|---|---|---|
| Værnet mod en `source`, der læser sig selv (direkte eller gennem en anden fil): mango læser den igen og igen, til stakken løber tør | går ned | filen læses én gang, og det meldes (én linje uden `[Index]`) | `includeStack` i `Config/load.swift`; `testASourceCycleIsReadOnce` |
| Et træk i `fair`, `vertical_fair`, `grid` og `vertical_grid` vælger naboen på den side af vinduet, man trækker i (`cursor_in_left_half`), og overskriver straks valget med tastaturets (*"Keyboard hotkey logic unchanged"*): naboen til højre, og kun for den yderste kolonne til højre den til venstre | tre kolonner, træk i midterste vindues venstre kant: dens højre kant flytter sig | venstre kant flytter sig | Tastaturets valg bruges kun ved tastaturet (`!isdrag`), og trækkets valg, som mango selv udregner, står. `resizeTileGridFair` i `Layout/arrange.swift`; `testAGridDragMovesTheEdgeItGrabs` |
| `focus_direction` sender venstre og højre gennem `focus_stack`, når tagget er monocle, også i overview, hvor kortene ligger i et gitter; samme funktion springer stakken over i overview tre linjer længere nede (`if (!isoverview)`) | overview fra et monocle-tag: venstre/højre følger vinduernes rækkefølge, ikke kortene | venstre/højre går til kortet ved siden af | Monocle-grenen gælder ikke i overview, som mangos egen `!isoverview`. `focusDirection` i `dispatch/bind.swift`; `testMonocleInTheOverviewGoesByTheCards` |
| `togglejump` på en skærm uden vinduer sætter `is_jump_mode` (`begin_jump_mode`), men `set_overview` vender om uden at gå i overview, så flaget bliver stående: kun at forlade overview rydder det | indtil næste overview er switcheren afvist, og Escape sluges i alle apps (`toggle_jump`) | jump-tilstanden slutter igen | Den tomme vej kalder `finish_jump_mode`, som mangos egen vej ud af overview gør. `setOverview` i `dispatch/bind.swift`; `testToggleJumpOnAnEmptyMonitorLeavesNoJumpMode` |
| `togglejump` under et træk med musen (`grab_client`): `toggle_jump` har intet værn, så `begin_jump_mode` sætter `is_jump_mode`, og `toggle_overview` afviser bagefter | som rækken over: jump-tilstanden bliver stående uden overview | intet sker | Værnet mod `grab_client`, som `toggle_overview` selv har, står før `toggle_jump`. `toggleJump` i `dispatch/bind.swift`; `testNoOverviewWhileGrabbed` |
| Hot area på en skærm uden vinduer: `toggle_hotarea` sætter `ov_normal_mode`, og `set_overview`s tomme vej rydder den ikke | næste `overcircle` viser gitteret, og i overview går den ud i stedet for at skifte | `ov_normal_mode` ryddes | Den tomme vej rydder den, som mangos vej ud af overview gør. `setOverview` i `dispatch/bind.swift`; `testTheHotAreaOnAnEmptyMonitorLeavesNoNormalMode` |
| `monitor_close` på en skærm i overview kalder `toggle_overview`, som virker på den valgte skærm | fjernes en anden skærm end den valgte, går den valgte ind i (eller ud af) overview, og den fjernede bliver i det | den fjernede skærm går ud af overview | `toggle_overview` kører med den fjernede skærm som den valgte og sætter den valgte tilbage. `monitor_close` i `manage/monitor.swift`; `testRemovingAMonitorInOverviewLeavesTheSelectedOneAlone` |
| Et vindue, der åbner i overview, får kun `overview_backup_surface`, ikke `overview_backup`, så `overview_restore` giver det de nulstillede kopier tilbage | en dialog, der åbner i overview, mister sin flydende tilstand og lægges i layoutet, når overview lukker | vinduet beholder sin tilstand (fx flydende) | `overview_restore` springer et vindue over, som `overview_backup` ikke har kørt for (`overviewBackedUp`); `overview_backup_geom` sættes ved map, som i mango. `overviewRestore` i `overview/overview.swift`; `testAClientMappedInTheOverviewKeepsItsState` |
| Ved reload giver `parse_tagrule` alle vinduer master-bredden fra den sidste skærms tag, også vinduer på andre skærme, så en `tag_rule` med `monitor_name` kun virker på den sidste skærm | to skærme, 0,3 og 0,7: begge får 0,7 | hver skærms vinduer får deres egen | `c.mon === self` i `parseTagrule` i `Config/reapply.swift`; `testAReloadKeepsEachMonitorsOwnMfact` |
| `toml_foreach_array_element` kopierer `\` og det escapede tegn, men tester bagefter, om tegnet er citattegnet, så et escapet `"` afslutter strengen; mangos egne `remove_toml_comment` og `toml_statement_complete` springer det escapede tegn over | `exec = ["notify-send \"a, b\""]` deles ved kommaet i to `exec` | én `exec`: `notify-send "a, b"` | Det escapede tegn afslutter ikke strengen, som i mangos to andre TOML-læsere. `tomlForeachArrayElement` i `Config/toml_parse.swift`; `testAnEscapedQuoteStaysInsideATomlString` |
| `toml_section_begin` sætter `kind = BIND`, før den læser keymode og flag; afvises sektionen, sætter `toml_section_flush` `config->keymode` til `""` | efter `[bind.default.bogus]` får alle senere bindinger keymode `""` og virker aldrig | keymode er uændret | Kun en sektion, der ikke er afvist, sætter keymode tilbage. `tomlSectionFlush` i `Config/toml_parse.swift`; `testARejectedTomlBindSectionKeepsTheKeymode` |
| `increase_gaps` lægger tallet til de normale mellemrum, også på special-tagget, og `setgaps` skriver dem så som special-tagets | `incgaps,5` på special-tagget giver special-mellemrummene de normales + 5 | special-tagets egne + 5 | `increase_gaps` regner fra special-mellemrummene, når special-tagget er aktivt. `increaseGaps` i `dispatch/bind.swift`; facit `bind-special-incgaps.mango` (`ours`) |
| `parse_func_name` samler `setoption`'s felt 2–5 med komma og springer kun tomme felter over, men nøglebindingens parser giver de manglende felter `0` | `bind=…,setoption,circle_layout,tile,scroller` sætter `circle_layout` til `tile,scroller,0,0` | `tile,scroller` | felter, bindingen ikke giver, når `setoption` som `""` (som IPC's), ikke `"0"`; `parse_func_name` er mangos, så et givet `0` står (`setoption,animation_curve_move,0,0,1,1` virker). `dispatch(_:)` i `Engine/Dispatch.swift` og `swipeBindingFunc` i `input/trackpad.swift`; `testSetoptionSkipsTheBindingsUngivenFields`, `testSetoptionKeepsGivenZeros` |
| En tom linje i en fil med CRLF-linjeskift er `"\r\n"`, og `parse_conf_stream` springer kun `'\n'` over | hver tom linje giver `Invalid line format` | linjen springes over | en linje på præcis `"\r\n"` springes over som en tom; værdilinjer er mangos (`\r` trimmes). `parseConfStream` i `Config/load.swift`; `testCRLFLineEndings` |
| `handle_client_unmap` rydder `drop_client`, men ikke `group_bar_drag_client` | lukkes et vindue, mens et træk fra dets gruppebjælke venter, peger mango videre på det lukkede vindue | trækket slippes | unmap rydder `group_bar_drag_client` og `group_bar_drag_pending`, som `drop_client`. `handleClientUnmap` i `manage/client.swift`; `testAGroupBarPressOnAWindowThatClosesIsLetGo` |
| `client_group_leave` lægger det vindue, der forlader gruppen, med `wl_list_insert(rc->flink.next, …)`, altså to pladser bag `rc` i fokus-stakken, hvor mangos egen kommentar siger *"put tc right behind it"*; er `rc` sidst, er `rc->flink.next` listens hoved, og vinduet kommer forrest | `groupleave`: vinduet står to pladser bag `rc` (eller forrest, når `rc` er sidst) | lige bag `rc` | indsat efter `rc`, som kommentaren siger. `clientGroupLeave` i `dispatch/bind.swift`; `testGroupLeavePutsTheWindowRightBehindTheGroup` |
| `monitor_from_cycle` går med `m->link.next`/`prev` rundt i den cirkulære liste uden at springe hovedet over, så `wl_container_of` på `&server.monitors` giver en skærm, der ikke findes, og dens `wlr_output->enabled` læses | `focusmon,next` fra listens sidste skærm (eller `prev` fra den første): udefineret, går ned eller vælger intet | den næste skærm rundt om | rundt med modulo, uden hovedet. `monitorFromCycle` i `manage/monitor.swift`; `testTheCycleWrapsAround` |
| `set_float_malposition` læser og skriver `geom`, også når `client_set_rules` lige har gjort klienten fullscreen eller maksimeret, så `float_geom` får skærmens øverste venstre hjørne | et vindue med reglen `isfloating:1,isfullscreen:1` (eller maksimeret), der forlader fullscreen: står i skærmens hjørne | midt på skærmen, hvor `client_set_floating` satte det | springes over for `ISFULLSCREEN`. `setFloatMalposition` i `manage/client.swift`; facit `rule-float-fullscreen.mango` (`ours`) |
| `vertical_grid_core` tæller med `(!client_is_x11_popup(c) \|\| ISFAKETILED(c))`, som er sand for alle synlige flydende vinduer, hvor `grid_core` skriver `(m->isoverview && …) \|\| ISFAKETILED(c)`; `n` er kun de flisede | et flydende vindue tager en plads i gitteret og flyttes ind i det, og et fliset vindue kan blive uden plads | de flydende står, hvor de står | `grid_core`s betingelse. `verticalGridCounts` i `Layout/vertical.swift`; facit `arrange-floating-in-layout.mango` (`ours`) |

## 7. Fejl i mango, vi følger

Hvor mangos kode er forkert, men fejlen er så lille, at vi gør som mango (aftalt med brugeren). De
står her, så de kan meldes til mango; facit viser mangos svar uden `ours`.

| Fejl i mango | mango | En rettelse ville være |
|---|---|---|
| `tile`, `right_tile` og `vertical_tile` giver gruppens sidste vindue sin andel afrundet ned, så kolonnen kan mangle en pixel nederst (eller til højre). Andelen er `double`, forholdet `float`, og de to går ikke op. Det sker i omkring halvdelen af skærmhøjderne med lige store vinduer | 600 px på tre vinduer: 200, 199, 200 (vi svarer det samme) | Det sidste vindue får resten, som mangos egen `center_tile` gør (`if (r == 1) h = m->w.height - my - cur_gappov`). Fulgt fra 2026-11-23; før det rettede vi den (600 px på tre vinduer: 200, 200, 200) |

