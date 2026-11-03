# Afvigelser fra mango

Hvor Mango Chutney gør andet end mango 0.18.2 (`~/sources/mango`), og hvorfor. Kun det, der
gælder nu; det rettede og hvordan vi kom hertil står i [afvigelser-historik.md](afvigelser-historik.md).
Hver mango-nøgle, macOS ikke kan, står med grunden i [compatibility.md](compatibility.md) og
i `mango -p`.

Uden nogen `chutney_`-nøgle (portens blok sidst i `config.conf` slettet) opfører porten sig
som mango, så langt macOS tillader (afsnit 3).

## 1. Til og fra: portens udvidelser

Hver er fra, når nøglen mangler, og ændrer da intet af mangos opførsel. Standardconfigen er
mangos egen `assets/config.conf` uændret, og derefter portens nøgler fra deres markeringslinje
til slutningen: dem, en Mac vil have; resten står i `docs/chutney`. Blokken sætter ingen af
mangos nøgler. Slet den for ren mango (mango selv melder "Unknown keyword" for hver
`chutney_`-linje og læser resten).

| Nøgle / dispatcher | Gør | I standardconfigen | Uden den (mango) |
|---|---|---|---|
| `chutney_menu_bar` (+ `_tag_style`, `_logo`, `_layout`, `_mode`) | Menulinjen med tags, layout og layout-panelet | til | Ingen menulinje; tags i en bar via `mmsg watch` |
| `chutney_menu_config` | Panelets ændringer gemmes i `chutney_menu.conf`, som configen læser sidst; `config.conf` skrives aldrig | `chutney_menu.conf` | `setoption` gemmer intet |
| `chutney_style` | Fanebjælke, gruppebjælke, jump-mærker, switcher, titelbjælke, config-banner og overview i macOS' udseende, hvor ingen `*_decorate_*`-nøgle er sat; mangos farver i macOS' (`chutney_theme.conf`, følger accentfarve og lys/mørk); rammen følger vinduets runde hjørner | til | Mangos udseende og farver |
| `chutney_tab_bar_app_icons` | Appens ikon før fanens titel | til | Kun titler |
| `chutney_tab_bar_shortcuts` | ⌘1–9 vælger en fane | til | Ingen |
| `chutney_toggle_hotkeys_palette` (+ `chutney_hotkeys_*`) | Hotkeys-paletten: søg i bindinger, vinduer og apps | Hyper K | Ingen |
| `chutney_toggle_layout_palette` (+ `chutney_layout_palette_*`) | Layout-paletten; viser `circle_layout`, Tab og Space sætter den | Hyper L | Ingen |
| `chutney_focus_app` | Én tast pr. app: start den eller gå til dens vindue (med tre eller flere: det, der blev brugt før) | nej | Ingen |
| `chutney_floating_color` | Fast rammefarve for flydende vinduer | nej | Mangos farver |
| `chutney_border_unfocused` | `0`: ramme kun om det fokuserede vindue | nej (standard `1`) | Ramme om alle |
| `chutney_physical_pixels` | `border_px` og gaps i skærmens pixels, ikke punkter | nej | Punkter |
| `chutney_ignore_apps` | Apps, der aldrig styres | nej | Alle styres |
| `chutney_hyper_modifier` | Hvad `HYPER` betyder i en binding | `super+ctrl+alt` | Mangos Mod3 |

Mangos bindinger er standard, også dem på ⌘ og ⌥, som apps og macOS også bruger (⌘M lukker
mango). `Resources/mac-bindings.conf` har de samme på Hyper til at sætte i deres sted.

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

## 3. Tvunget af macOS

| Hvad | Hvorfor |
|---|---|
| Vinduer på skjulte tags parkeres i et hjørne med en pixel synlig | Uden compositor kan et vindue ikke skjules |
| Menulinjens punkt viser alle skærme, hver med sine tags og sit layout, den valgte fuldt optrukket og de andre dæmpet (som AeroSpace og rift) | macOS tegner ét menulinjepunkt som kopi på hver skærm; en bar som waybar viser hver skærm sine egne |
| Hvilke vinduer der styres (popups aldrig), og hvilke der åbner flydende (dialoger), afgøres med AeroSpaces heuristik 1:1, med dens app-lister, og én ændring: AeroSpaces regel om vinduesniveau gælder alle apps, ikke kun dem på dens liste, så et vindue over normalt niveau (en notifikation, et flydende panel) aldrig styres; en `window_rule` med `is_floating` vinder. Som i AeroSpace flyder et vindue, der er minimeret, eller hvis app er skjult, når det findes | Wayland siger det med xdg-roller; macOS siger det ikke pålideligt, og AeroSpaces heuristik er afprøvet mod rigtige apps |
| Et vindue, der ikke kan blive mindre end sit felt, går ind over naboen og vokser indad fra en skærmkant, det ellers ville krydse; mango klipper det | Appen afviser størrelsen, og andre apps' vinduer kan ikke klippes |
| Layoutet holder menulinjen og Dock'en fri | De svarer til mangos bjælker med eksklusiv zone |
| Ingen skygge, blur, dæmpning, gennemsigtighed eller runde hjørner fra mango; ingen luk- og fade-animationer | macOS tegner andre apps' vinduer; gennemsigtighed kræver SIP slået fra |
| Animationer skrives via Accessibility (højst 60 Hz) | Ingen compositor |
| Overview og switcher viser billeder (Skærmoptagelse), stillbilleder taget ved åbning | Andre apps' vinduer kan ikke skaleres; en strøm pr. vindue koster meget |
| Config-fejl i portens banner, ikke `mangonag` | `mangonag` er en Wayland-klient |
| Et vindue i macOS' egen fuldskærm (den grønne knap), i Dock'en (med `ignore_minimize`, mangos standard), i en skjult app (⌘H) eller i en app, der ikke svarer, mens det er parkeret, unmappes med mangos `handle_client_unmap` og mappes tilbage på sin plads, når det kommer igen. Mango ser det ikke imens, heller ikke i `mmsg get all-clients` | macOS har allerede taget vinduet væk; mango ville have det unmappet |
| En holdt tasts gentagelser: højst én venter på hovedtråden ad gangen | macOS sender gentagelserne selv; mangos egen gentagelsestimer stabler dem aldrig |
| Fokus sendes til macOS én gang pr. tur, for det sidst fokuserede vindue | Fokus på macOS er en synkron forespørgsel til WindowServer og appen; mangos `client_focus` sætter kun tilstand |
| Kant-, fane- og gruppevinduer lægges kun om, når de ligger forkert | Hver omlægning venter på WindowServer; én forespørgsel på rækkefølgen er billigere |
| En dialog arver ikke sit hovedvindues tags og skærm | Accessibility siger ikke pålideligt, hvem der ejer en dialog |
| Vinduer, der er der ved start eller kommer igen efter dvale, beholder deres plads; layout, tags og grupper gemmes og kommer igen efter en genstart og dvale | En genstart af mango lukker ikke vinduerne, og macOS melder vinduer væk og tilbage omkring dvale |
| Titelbjælkens anden linje er appens bundle id | macOS' nærmeste svar på `app_id` |
| `confine_pointer` sætter markøren tilbage, når den er nået over kanten | macOS flytter markøren, før mango ser bevægelsen |
| `xkb_rules_options`: kun de muligheder, der flytter taster, med macOS' egen omlægning | macOS har ingen xkb |
| Systemets trackpad-gestures konkurrerer med `gesturebind` | macOS ejer dem |
| IPC: Unix-socket `/tmp/mango-<bruger>.sock`, kun brugerens (0600), og en anden kørende mangos socket overtages ikke; `get tag` tager tallet som sidste felt; sende-bufferen er 1 MB | Ingen `XDG_RUNTIME_DIR`; skærmnavne har mellemrum; macOS' buffer er 8 KB, og et svar sendes uden at vente |
| `source=` med relativ sti læses fra config-mappen; ingen `/etc/mango`-fallback | Under launchd er arbejdsmappen `/`; macOS har ingen `/etc`-config |
| Første start skriver `config-mac.conf` som `config.conf`: mangos config med mangos taster på Hyper (Caps Lock, medmindre brugeren fravælger det), ikke mangos egne taster. Også `start.conf`, og et velkomstvindue, der åbner Getting Started | mango læser `/etc/mango/config.conf`, når brugeren ingen har; en Mac-app har ingen `/etc`-config. mangos taster (⌘M, ⌘N, ⌥+bogstav, ⌃+pile) er macOS' og appernes genveje |
| Input besluttes på event tappets tråd; `setkeymode` og `chvt` stopper søgningen efter bindinger | macOS vil have svaret med det samme; dispatcherens svar kendes først på hovedtråden |
| Timere: cursor-skjul (som mangos), animationernes reserve-timer, 0,4 s ekstra genstabling efter fokus, sen genlæsning af vinduets ramme, ét forsøg pr. sekund på at sætte et vindue tilbage, samling af skærm- (0,3 s) og config-ændringer (0,2 s), 0,05 s efter menuen, ventetid ved genstart og `mmsg service`, hovedtrådens vagt | macOS melder ikke alt som en begivenhed |

## 4. Mangler endnu

Intet: alt af mango, som macOS tillader, er bygget (`switch_keyboard_layout` er fravalgt, afsnit 2).

## 5. Struktur

Hvor koden står, når den ikke står som i mango.

- **Kernen (`Sources/Mango`)** har mangos funktioner med mangos navne og kun mangos egne
  kommentarer eller mærker om, hvor vi afviger (CLAUDE.md regel 8). En funktion med andet navn
  end mangos har én linje `/// mango <funktion> (<fil>)`; der er 13 tilbage: tastaturets tråd,
  cursor-timeren, `Log`, `f32` og nogle få, der allerede har mangos navn.
- **Bevidst i kernen, mærket:** parkeringen (`c.parked`, mango klipper i scenen), scrollerens
  kolonner i tag-tilstanden (mango bruger `ScrollerStackNode` i klientlisten), overview med
  billeder (`thumbnails`), drag-tile delt med appens eget træk, `parse_option` som en tabel,
  og `resize_tile_master` i begge retninger i én funktion.
- **Grænsen (`Sources/Boundary`):** `WindowSystem` (wlroots' plads), `EventLoop`
  (`wl_event_loop_add_fd` til IPC), `Screen`, `PortHooks`, `ConfigPort` (portens nøgler,
  modifiernavne, tastkoder) og `InputState`.
- **Porten (`Sources/Port`):** macOS-laget (`Port/macOS`: Accessibility, parkering, fokus,
  appens egne træk, vinduer ved start og tilbage, vinduer væk i `AwayWindows`, `KeySyms`,
  IPC's event loop) og udvidelserne (`Port/Extensions`), som kobler sig på gennem `PortHooks`.
