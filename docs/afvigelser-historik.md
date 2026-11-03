# Afvigelser fra mango: historik

Den fulde log fra 2026-10-26 til 2026-10-31, med det, der er rettet. Det, der gælder nu,
står i [afvigelser.md](afvigelser.md).

Lavet 2026-10-26 efter beslutningen "tro mod huset er første prioritet".
Sammenlignet med mango 0.18.2 (`~/sources/mango`, koden, ikke docs) og
kontrolleret af Fable mod mangos kildekode.

Hver afvigelse har én mærkat:

- **T — tvunget**: macOS tillader det ikke anderledes. Bliver, og README siger
  hvorfor.
- **V — valgt**: porten har valgt noget andet, end mango gør (somme tider med
  en macOS-grund, der står i "Hvorfor"). Fjernes eller erstattes af mangos
  egen måde, medmindre du beslutter andet.
- **M — mangler**: en mango-funktion, porten ikke har endnu. Kan bygges.

Kolonnen "Forslag" er mit bud; "Din beslutning" er din.

**Besluttet 2026-10-26:** tro mod huset betyder, at porten kan alt det, mango
kan, på mangos måde. Udvidelser i §1 bliver, men er slået fra som standard og
tydeligt mærket (`mango -p`, README), så porten opfører sig som mango, indtil man
selv slår en udvidelse til. Arbejdet er herefter §2–§5.

**Fra i koden, til i `macos.conf`.** "Fra som standard" nedenfor gælder koden: en nøgle, der
ikke står i configen, ændrer intet af mangos opførsel. Den medfølgende `macos.conf`, som
`config.conf` læser til sidst med `source_optional=macos.conf`, slår nogle til for en Mac:
`macos_menu_bar`, `macos_style`, `macos_tab_bar_app_icons`, `macos_tab_bar_shortcuts`,
`macos_menu_config`, paletterne på Hyper K og Hyper L, kortere animationer (200 ms) og
`sloppy_focus=0`. Slet den linje i `config.conf` for ren mango.

## 1. Udvidelser, mango ikke har

| Navn | Mærkat | Hvorfor | Mangos måde | Forslag | Din beslutning |
|---|---|---|---|---|---|
| Prefikset `macos_` (nøgler, dispatchers, `macos.conf`, `macos_theme.conf`, `macos_menu.conf`) | V | **Omdøbt** 2026-11-01 til `chutney_` (`chutney.conf`, `chutney_theme.conf`, `chutney_menu.conf`): appens navn, kan ikke støde sammen med mango. De gamle navne (også dem fra før `macos_`) er ikke længere aliaser; appen var ikke udgivet | — | — | **Omdøbt** |
| `border_corner_radius` | T | macOS tegner runde vindueshjørner, som rammen skal følge | `border_radius` (virker ikke på macOS) | Bliver | **Ingen indstilling:** rammen følger altid macOS' hjørner (fjernet 2026-10-26) |
| `macos_ignore_apps` | T | Nogle macOS-apps (systemets) kan ikke styres via Accessibility | — (`is_unmanaged_global` er noget andet) | Bliver | **Bliver**, tom som standard |
| `macos_hyper_modifier` | V | Mangos ⌘-, ⌥- og Ctrl-bindinger virker i porten, men tager appenes genveje; Hyper er et lag for sig | Bindinger direkte på SUPER/ALT/CTRL | Bliver (macOS-grund), men nævnes som valg | **Bliver** |
| `macos_auto_float_oversized` | V | **Fjernet** 2026-10-30: efter at mangos felter bruges præcist (et vindue, der ikke kan blive mindre, går ind over naboen), løste den kun det, mangos `window_rule=is_floating:1,app_id:…` allerede løser pr. app | — | — | **Fjernet** |
| `macos_border_unfocused` | V | Mango tegner altid rammer om alle vinduer (undtagen `no_border`, `no_border_when_single`, `monocle_no_border`) | Altid rammer | Fjern nøglen; rammer om alle vinduer som i mango | **Bliver**; til som standard, fordi det er mangos adfærd |
| `macos_floating_color` | V | Mango har ingen farve for flydende vinduer | `focus_color`/`border_color` | Fjern | **Bliver**, fra som standard |
| `macos_menu_bar` (tidl. `menu_bar_icon`), `macos_menu_bar_tag_style`, `macos_menu_bar_logo`, `macos_menu_bar_layout` | V | Mango viser tags og layout i en ekstern bar via IPC | Ekstern bar via `mmsg watch` (sketchybar på macOS) | Fjern; vis tags i sketchybar via `mmsg` | **Bliver**, fra som standard Tags som SF Symbols-tal (firkant/cirkel) eller tekst; tomme tags vises efter mangos `tag_rule` `no_hide`; logo og layoutikon kan slås fra; alt kan ændres fra panelet (2026-10-30) |
| `macos_tab_bar_app_icons` | V | Mangos fanebjælke viser kun titler | Titler | Fjern | **Bliver**, fra som standard |
| `macos_tab_bar_shortcuts` (⌘1–9) | V | Mango har ingen dispatcher til fane nr. n | `focusstack` | Fjern | **Bliver**, fra som standard |
| `macos_physical_pixels` | V | Mangos `border_px` og gaps er logiske pixels (punkter); på Retina er 1 punkt 2 pixels, så den tyndeste ramme over 1 punkt er 2 punkter. Med nøglen er `border_px` og gaps skærmens pixels (3 = 1,5 punkt), og værdierne forbliver heltal | `border_px` og gaps i logiske pixels | Bliver | **Bliver**, fra som standard (2026-10-30; afløser `border_px_physical`). Gælder rammen, snap, layoutets gaps og et maksimeret vindues ydre gap; ikke de få sammenligninger med gaps (tolerancer, scratchpad-størrelse). Menuens panel viser punkter i pixeltrin, når den er sat |
| Layout-panelet i menulinjemenuen | V | Efter mangobutters quickshell-panel; sender kun mangos dispatchers (`setlayout`, `incgaps`, `setoption,border_px`, `setmfact`, `incnmaster`) | Ekstern bar via IPC | Bliver | **Bliver** (2026-10-30), en del af `menu_bar_icon` |
| `macos_toggle_hotkeys_palette` (dispatcher), `macos_hotkeys_*` | V | Mango har ingen visning af bindingerne; mangobutter har den i sin bjælke (KeybindsPane). Paletten efter Omarchys Super+K: søg i bindinger, vinduer og apps (Spotlight), kør med Return; tilstand og hvad der kan bruges nu, senest brugte først, ingen scroll. Afløser genvejsvinduet `macos_toggle_shortcuts` (det gamle navn åbner paletten; `macos_shortcuts_*_ratio` er fjernet) | Ekstern bjælke | Bliver | **Bliver** (2026-10-30) |
| `macos_toggle_layout_palette` (dispatcher), `macos_layout_palette_keys`, `macos_layout_palette_width` | V | Mango har ingen layoutvælger; man skifter med setlayout/switch_layout. Paletten viser layoutene i mangos `circle_layout` (dem `switch_layout` går rundt i) som ikoner, tegnet af mangos egen layoutkode, i dens rækkefølge; uden `circle_layout` alle 14 i et 5×3-gitter (portens opstilling, ikke mangos `layouts[]`-rækkefølge). Pile eller egne taster (h,j,k,l), Return kører setlayout; Tab viser alle 14 med flueben, og Space sætter `circle_layout` med mangos `setoption`, som menuens flueben | Ekstern bjælke | Bliver | **Bliver** (2026-10-30; `circle_layout` 2026-10-31) |
| `macos_menu_config` | V | Mangos `setoption` gemmer intet; menuens ændringer forsvandt ved genindlæsning. Med nøglen gemmer panelet dem i en egen fil (almindelig mango-config, én linje pr. nøgle og pr. `tag_rule`-felt), som configen læser sidst med mangos egen `source_optional` og derfor vinder. Brugerens config skrives aldrig; hvor filen overstyrer den, advarer panelet ("Overrides config", med Clear) og `mango -p` | Intet gemmes | Bliver | **Bliver** (2026-10-30), fra uden nøglen |
| `macos_focus_app` (dispatcher) | V | Fra AeroControl; mango har ingen "fokusér app" | `spawn`, `focusstack`, `toggle_named_scratchpad` | Fjern, eller behold som eneste bevidste udvidelse | **Bliver** (virker kun, hvis man binder den) |

## 2. Udseende

| Afvigelse | Mærkat | Hvorfor | Forslag | Din beslutning |
|---|---|---|---|---|
| Rammen tegnes uden om vinduet, ind i mellemrummet; mango lægger rammen inden for vinduets felt (indholdet er 2 × `border_px` mindre end feltet). Følger: vinduerne er større end i mango, og rammer kan overlappe naboens, når mellemrummet er mindre end rammen | V | Intet på macOS forhindrer, at vinduet gøres `border_px` mindre hele vejen rundt | Gør som mango: ramme inden for feltet | **Rettet** 2026-10-26 (mangos `bw`; også `no_border_when_single` tæller nu alle synlige vinduer som i mango) |
| Fanebjælken tegnes i macOS-stil og ignorerer `tab_bar_decorate_*` (farver, skrift, kant, hjørner, luft) | V | Valgt for at ligne macOS | Tegn den som mango med `tab_bar_decorate_*` | **Rettet** 2026-10-28: mangos look er grundlaget; portens macOS-look er en override (`macos_style`, til som standard), og hver `*_decorate_*`-nøgle, der sættes, vinder |
| Fanebjælken ligger inden for rammen (rammen går om bjælke og vindue); mango lægger den oven på den indrammede boks | T/V | Vinduets hjørner er runde (tvunget); hvor bjælken ligger, er valgt | Tag op sammen med rammen inden for feltet | **Rettet** 2026-10-28: som mango uden `macos_style`; med den inden for rammen |
| Jump-mærker tegnes i macOS-stil og ignorerer `jump_label_decorate_*` | V | Valgt for at ligne macOS | Tegn dem som mango | **Rettet** 2026-10-28, som fanebjælken (`macos_style`) |
| Switcherens panel og felter tegnes i macOS-stil (sløret panel, mørke kort, ring i fokusfarven); billederne beholder vinduets proportioner, og et meget mindre vindue tegnes mindre (mindst 60 %). Mango tegner et fladt panel, felter i `border_color`/`focus_color` og strækker vinduet ud i feltet | V | Valgt som fanebjælken; mangos ens felthøjder fik små vinduer til at se store ud | Bliver | **Besluttet** 2026-10-28 |
| Titelbjælken er i macOS-stil som standard; hver `title_message_bar_decorate_*`-nøgle, der sættes, giver den del mangos look | V | Valgt ("begge") | Bliver | **Besluttet** 2026-10-28 |
| Config-fejl vises i portens eget banner; mango starter sit program `mangonag` (med Luk og Rediger) | T | `mangonag` er en Wayland-klient | Bliver; banneret kunne få mangonags knapper | Banneret har mangonags Rediger og Luk og, uden `macos_style`, mangonags look |
| Titel/app-id-bjælken (`title_message_bar_*`), som mangos switcher og overview viser, findes ikke | M | — | Kan bygges sammen med switcheren (§3) | **Rettet** 2026-10-28: under switcheren og overcircles kort, i macOS-stil; hver `title_message_bar_decorate_*`-nøgle, der sættes, giver den del mangos look. Switcherens felter ligger som mangos, men panelet er macOS-stil, og hvert billede fylder sit felt i vinduets egne proportioner (mango strækker det ud til hele feltet) |
| Overview viser billeder af vinduerne (kræver Skærmoptagelse), ikke skalerede vinduer | T | Man kan ikke skalere en anden apps vindue på macOS | Bliver | Uden `macos_style` tegnet som mangos: `root_color` bag kortene, vinduet strakt ud i kortet med sin ramme |
| Ingen skygge, blur, dæmpning, gennemsigtighed eller runde hjørner fra mango | T | macOS tegner andre apps' vinduer | Bliver | |

Fejl fundet undervejs: README og `MangoCompat.swift` kaldte `title_message_bar_*`
"mango's config error bar". Rettet 2026-10-26: de står nu som "ikke lavet endnu".

## 3. Adfærd

| Afvigelse | Mærkat | Hvorfor | Forslag | Din beslutning |
|---|---|---|---|---|
| Vinduer på skjulte tags parkeres i et hjørne med en pixel synlig | T | Uden compositor kan et vindue ikke skjules | Bliver | |
| Layoutet bruger macOS' arbejdsområde: menulinjen og Dock'en holdes fri | T | Dock og menulinje svarer til mangos bjælker med eksklusiv zone | Bliver | |
| Skjulte fanemedlemmer (monocle/deck med faner) ligger bag det viste; mango skjuler dem (`is_tab_hidden`) | V | Valgt; de kunne parkeres som skjulte tags | Parkér dem, som mango skjuler dem | **Rettet** 2026-10-28 (parkeres som vinduer på skjulte tags) |
| `switcher` åbner overview og går gennem fokuslisten; mango har sin egen switcher med titel/app-id-bjælke | V/M | Forenklet | Byg mangos switcher | **Rettet** 2026-10-28 (mangos panel, rækkefølge, omfang, valg ved slip af modifier, klik); billederne kræver Skærmoptagelse, ellers app-ikon og titel |
| Et scratchpad centreres igen ved hver arrange; mango centrerer kun første gang og beholder et flyttet scratchpads plads | V | Fejl, ikke et valg | Ret: behold pladsen som mango | **Rettet** 2026-10-26 (mangos `iscustomsize`) |
| Et tiled vindue, der trækkes og slippes på et andet, bytter plads med det; mango viser et felt i `drop_color`, hvor det lander, og sætter det ind på den side (venstre/højre/op/ned, i dwindle efter `dwindle_drop_simple_split`) | V/M | Forenklet | Byg mangos træk-og-slip med retning og felt | **Rettet** 2026-10-28: vinduet flyder under trækket, feltet i `drop_color` viser siden, og det sættes ind der (rækkefølgen, scrollerens stak/kolonne, dwindle-træet); også ved appens eget træk i titellinjen |
| Switcherens billeder tages, når den åbner, og står stille; mango viser vinduerne levende. Uden Skærmoptagelse står appens ikon i stedet | T | macOS giver kun billeder af andre apps' vinduer gennem ScreenCaptureKit; en strøm pr. vindue koster meget | Kan gøres levende med en strøm pr. vindue | |
| Titelbjælkens anden linje er appens bundle id | T | macOS' nærmeste svar på mangos app_id | Bliver | |
| Et nyt vindue kom først i fokuslisten, når det fik fokus; mango sætter det øverst, når det åbner (switcherens rækkefølge, `focuslast`, fokus efter et lukket vindue) | V | Fejl | Som mango | **Rettet** 2026-10-28 |
| Switcheren lukkede ikke, når skærmen blev låst | V | Fejl | Som mango | **Rettet** 2026-10-28 |
| Dækkede vinduer animeres ikke; mango animerer alle | V | Hver frame er en Accessibility-skrivning; usynligt for brugeren | Bliver (ses ikke) | |
| Animationer skrives via Accessibility (højst 60 Hz) | T | Ingen compositor | Bliver | |
| Ingen luk- og fade-animationer | T | Vinduet er væk, når macOS melder det lukket; gennemsigtighed kræver SIP slået fra | Bliver | |
| Et vindue, der ikke kan blive mindre end sit felt, går ind over naboen; mango klipper det | T | macOS-apps afviser størrelsen, og andre apps' vinduer kan ikke klippes. Mangos felter bruges præcist; det fokuserede vindue ligger øverst. Som AeroSpace, yabai og Amethyst. Afløser `MinSizeSolver` og læring af minimumsstørrelser (langsomt, huller i dwindle) | Bliver | 2026-10-30 |
| Layout og tags gemmes på disk og kommer igen efter en genstart | T | En genstart af mango lukker ikke vinduerne, som en compositor-genstart gør | Bliver | |
| Fuldskærm med den grønne knap lever i sit eget macOS-Space | T | macOS' egen fuldskærm | Bliver | |
| IPC: mangos JSON over en Unix-socket; `mmsg service`, `mmsg logs`, `mmsg reload`, `mmsg binds` og `get binds` er portens, og `watch` har en anden form | T/V | Ingen Wayland-protokol (T); de ekstra kommandoer er valgt | Bliver; nævn de ekstra kommandoer | |
| `watch` sender kun en linje, når svaret har ændret sig; mango sender ved hver statusbegivenhed (`printstatus`, `ipc_notify_*`) | V | Færre linjer til en bar, der alligevel tegner det samme | Bliver, eller send hver gang som mango | Listet 2026-10-31 |
| `get tag <skærm> <n>`: tallet er det sidste felt, så skærmnavne med mellemrum virker; mango læser `%63s %d` (navnet stopper ved første mellemrum) | T | macOS' skærmnavne har mellemrum ("Built-in Retina Display") | Bliver | Listet 2026-10-31 |
| `quit,restart`: en ny mango tager over med det samme, og skjulte vinduer bliver skjult; mangos `quit` tager intet argument | V | `make install` og `mmsg service restart` genstarter appen | Bliver | Listet 2026-10-31 |
| Modifiernavnene `cmd`, `command`, `logo`, `meta`, `control`, `option`, `opt`, `fn`, `function` accepteres i bindinger; mangos `parse_mod` springer ukendte navne over | V | macOS' egne navne; `fn` har intet mango-navn | Bliver | Listet 2026-10-31 |
| `ignore_minimize` (mangos standard 1): mango afviser en minimering, og vinduet bliver i layoutet; på macOS minimerer Dock'en, før mango hører om det, så vinduet tages ud af layoutet og kommer igen, når det gendannes | T | macOS minimerer selv | Bliver | Listet 2026-10-31 |
| Vinduesklassificeringen har faste app-lister: apps hvis normale vinduer mangler fuldskærmsknap (Chrome, Safari, Arc, Ghostty, VS Code, terminaler m.fl.), Ghosttys quick terminal og Xcodes Open Quickly som popups, Finders Quick Look som vindue, qutebrowser og Ghostty i dialogvalget, og Electron-apps kendt på deres framework | V | Mango får vinduets rolle fra xdg-shell; macOS siger det ikke pålideligt. Listerne er særtilfælde | Erstattet af AeroSpaces heuristik 1:1 (vores tilføjelser fjernet: Electron, Safari/Arc/Brave, 60 %-reglen, IntelliJ-reglen, lag ≠ 0 for alle, den udskudte dialogafgørelse `dialogPending`) | Rettet 2026-10-31 |
| Timere (hver har en kommentar i koden): cursor-skjul (`cursor_hide_timeout`, som mangos), animationernes frame-timer uden skærm, 0,4 s ekstra genstabling efter fokus (apps, der ændrer rækkefølge bagefter), en sen genlæsning af vinduets ramme (≥ 0,6 s, apps der aldrig melder deres flytning), højst ét forsøg pr. sekund på at sætte et vindue tilbage, 0,3 s samling af skærmændringer, 0,2 s samling af config-gemninger, 0,05 s efter menuen lukker, 0,1 s ventetid ved genstart, `mmsg service`s ventetid på launchctl, og hovedtrådens vagt (logger kun) | T/V | macOS melder ikke alt som en begivenhed | Bliver; fjern 0,4 s-genstablingen, hvis `-d` viser, at den aldrig gør noget | Listet 2026-10-31 |
| IPC-socketten er `/tmp/mango-<bruger>.sock`; mango bruger `$XDG_RUNTIME_DIR/mango-<pid>.sock` | T | macOS har ingen `XDG_RUNTIME_DIR` | Bliver | Listet 2026-10-30 |
| `source=` med en relativ sti læses fra config-mappen; mango fra processens arbejdsmappe | T | Under launchd er arbejdsmappen `/` | Bliver | Listet 2026-10-30 |
| Ingen `/etc/mango/config.conf`-fallback; uden brugerens config kopieres portens standardconfig | T | macOS-apps har ingen `/etc`-config | Bliver | Listet 2026-10-30 |
| `confine_pointer`: mango klemmer musens bevægelse, før markøren flytter sig; på macOS har systemet flyttet den, så den sættes straks tilbage på samme grænse (5 px inden for vinduet). Den kan nå én frame ud over kanten | T | macOS flytter markøren før mango ser bevægelsen | Bliver (nær ækvivalent) | Bygget 2026-10-30; før listet som umulig med forkert grund (pointer constraints, som mango ikke bruger) |
| Escape i en almindelig overview går til appen; kun jump-tilstanden tager den | – | Som mango | – | **Rettet** 2026-10-30 |
| Systemets trackpad-gestures (Spaces, Mission Control) konkurrerer med `gesturebind` | T | macOS ejer dem | Bliver | |
| Et vindue, der allerede er der, når mango starter, beholder sin plads (centreres ikke, får ikke fokus, dets tag vises ikke); et vindue, der kommer igen efter dvale, får sin gamle plads, tag og skærm | T | En compositor-genstart lukker vinduerne; på macOS lever de videre | Bliver | |
| `toggle_named_scratchpad` gør det vindue, den starter, til et navngivet scratchpad; mango kræver en `window_rule` med `is_named_scratchpad:1` | V | Bekvemt; ændrer intet, når reglen findes | Bliver, eller som mango | |
| En dialog arver ikke sit hovedvindues tags og skærm (mangos `parent`); den åbner på det valgte tag | T | Accessibility siger ikke pålideligt, hvilket vindue en dialog hører til | Bliver | |
| `xkb_rules_options`: kun de muligheder, der flytter taster (`caps:hyper`, `caps:escape`, `caps:swapescape`, `caps:ctrl_modifier`, `ctrl:nocaps`, `ctrl:swapcaps`, `caps:super`, `altwin:swap_alt_win`); `caps:hyper` gælder kun mangos bindinger (andre apps får ingen Hyper-modifier); omlægningen er macOS' egen (hidutil) og gælder, til mango ændrer den, mango lukker eller macOS genstarter | T | macOS har ingen xkb; layout og compose er systemets | Bliver | Implementeret 2026-10-29 |

## 4. Standardconfig (`Resources/config.conf`)

| Afvigelse | Mærkat | Hvorfor | Forslag | Din beslutning |
|---|---|---|---|---|
| Bindinger på Hyper-laget (`$mod`) i stedet for Super/Alt | V | Mangos bindinger virker, men tager appenes genveje | Bliver (macOS-grund), men nævnes som valg | |
| `movewin`, `resizewin` og `scroller_stack` ligger i en `key_mode=window` (`$mod+w`) med tre `setkeymode`-bindinger | V | Valgt: tasterne kolliderede på Hyper-laget | Bliver eller som mango | |
| Udkommenteret: `viewtoleft`/`viewtoright`, én `spawn`, fire `scroller_stack` og `mousebind` til `togglemaximizescreen` | V | Valgt | Gennemgås én for én | |
| Alle otte `gesturebind`-linjer er udkommenteret | V | Konkurrerer med systemets gestures (§3) | Bliver udkommenteret, med grunden | |
| Animationsvarigheder 200/300/150 ms mod mangos config-fil 500/400/350 (mangos kode: 500/400/300) | V | Valgt, fordi Accessibility-animationer halter i tunge apps | Brug mangos værdier; din egen config kan sætte kortere | **Rettet** 2026-10-28: mangos værdier |
| `sloppy_focus=0` mod mangos 1 | V | Valgt | Brug mangos værdi | **Rettet** 2026-10-28: mangos værdi |
| `macos.conf` sætter 200 ms animationer og `sloppy_focus=0` oven på mangos værdier i `config.conf` | V | En Mac-standard; Accessibility-animationer halter i tunge apps | Bliver i `macos.conf`; slet `source_optional=macos.conf` for ren mango | Listet 2026-10-31 |
| Terminal: Ghostty i stedet for foot | T | foot findes ikke på macOS | Bliver | |
| `layer_rule` for rofi er udkommenteret | T | macOS har ingen layer shell | Bliver | |
| Alt ovenfor | V/T | | `config.conf` er mangos egen fil uændret, med `source_optional=macos.conf` til sidst; `macos.conf` har kun portens nøgler og paletternes bindinger; Hyper-sættet ligger i `docs/mac-bindings.conf` | **Rettet** 2026-10-31: mangos fil og bindinger |

## 5. Mango-funktioner, porten mangler (M)

| Område | Navne | Forslag | Din beslutning |
|---|---|---|---|
| Vinduesgrupper | `groupfocus`, `groupjoin`, `groupleave`, `togglegroupbar`, `group_bar_*` | Kan bygges (gruppebjælke som fanebjælken) | **Rettet** 2026-10-28: grupper som mangos (én plads, medlemmer uden for synet parkeret, `client_replace`, slip på en gruppebjælke), gruppebjælken i fanebjælkens macOS-stil med `group_bar_height` og `always_show_group_bar`. Lukkeknappen (`group_bar_close_button_enable`, `group_bar_button_*`) og `monocle_right_button_close` virker. Mangler: grupper huskes ikke efter en genstart |
| Switcher | `switcher` med titel/app-id-bjælke (`title_message_bar_*`) | Kan bygges (se §3) | **Rettet** 2026-10-28 |
| Regelfelter | `ignore_maximize`, `no_force_center`, `no_size_hint`, `force_tiled_state`, `global_key_binding` | Kan bygges; `is_term`/`no_swallow` er umulige (macOS siger ikke, hvilken app der startede en anden) | **Rettet** 2026-10-28: `no_force_center` og `global_key_binding` virker (tasten sendes til appen med `postToPid`); `ignore_maximize`, `no_size_hint` og `force_tiled_state` kan ikke virke (macOS-apps sender ingen maksimeringsanmodning, holder selv deres min./maks.-størrelse og har ingen tiled-tilstand). Undervejs rettet: `tagmon` skalerer og centrerer et flydende vindue som mango |
| Træk og ændring af størrelse | `enable_border_resize`, `border_resize_size`, `drag_corner`, `drag_warp_cursor`, `float_full_to_top` | Kan bygges | **Rettet** 2026-10-28: `drag_corner` og `drag_warp_cursor` virker. Kan ikke virke: `float_full_to_top` (macOS har ingen lag for andre apps' vinduer; det sidst fokuserede ligger øverst) og `enable_border_resize`/`border_resize_size` (kun appen under markøren kan ændre dens form; macOS giver hvert vindue sine egne kanter, og et træk i en tiled kant flytter delelinjen) |
| Dwindle | `dwindle_drop_simple_split`, `dwindle_smart_resize`, `drop_color`, `split_color` | Kan bygges | **Rettet** 2026-10-28 (`drop_color` og `dwindle_drop_simple_split` med mangos træk-og-slip, se §3) |
| Scroller-kanter | `edge_scroller_pointer_focus`, `edge_scroller_focus_allow_speed` | Kan bygges | **Rettet** 2026-10-28 (med mangos fokuslås) |
| Gestures | `gesture_live`, `gesture_swipe_cancel_ratio`, `gesture_swipe_distance`, `gesture_swipe_min_speed_to_force`, `swipe_min_threshold` | Kan bygges | Trin 1 **rettet** 2026-10-28: et swipe udløses, når en finger løftes, målt i libinputs enheder, og `swipe_min_threshold` virker. Levende gestures **rettet** samme dag: tag-skift og overview følger fingrene og fuldføres eller rulles tilbage (`gesture_swipe_distance`, `_cancel_ratio`, `_min_speed_to_force`), `focusdir` i scroller panorerer båndet, `moveresize` trækker vinduet. Ikke prøvet på en trackpad |
| Andet | `animation_curve_focus`, `animation_duration_focus`, `cursor_hide_on_keypress`, `cursor_hide_timeout`, `hotarea_disable_on_fullscreen`, `special_dim`, `zoom_end_ratio` | Gennemgås én for én; dæmpning er umulig | **Rettet** 2026-10-28: `hotarea_disable_on_fullscreen`, `special_dim` (et sort panel under special-vinduerne, der tager markøren som mangos), `cursor_hide_*` (macOS' "SetsCursorInBackground"; timeouten er en timer som mangos). Kan ikke virke: `animation_*_focus` (gennemsigtighed kræver SIP slået fra) og `zoom_end_ratio` (lukke-animation) |

## 6. Fundet ved navnegennemgangen 2026-10-28

Fundet, da hver Swift-funktion blev parret med mangos (`~/sources/mango/src`), og derefter
læst mod mangos kode én for én. alle 29 er rettet med en test hver (`Tests/MangoCoreTests/FidelityTests.swift`). Undervejs fundet og rettet:
`comboview` var en almindelig `view` (nu mangos `combo_view` med `tag_combo`).

| # | Vores | mango | Afvigelse |
|---|---|---|---|
| 1 | `handleClientMap` | `client_insert_tiling_order` (client.c) | Et nyt vindue sættes efter det valgte; mango sætter det sidst (i scrolleren efter det valgtes stak) **Rettet** (test i `FidelityTests`). |
| 2 | `handleClientUnmap` | `handle_client_unmap` | Fokus flyttes kun, hvis det lukkede var `sel`; mango flytter, når det var på den valgte skærm, og prøver først scrollerens stak-naboer **Rettet** (test i `FidelityTests`). |
| 3 | `findClientByDirection` | `find_client_by_direction` (client.c) | Midtpunktsafstand; mango bruger kant- og tværafstand, ser først i samme stak, og `focusdir_only_zone_overlap` virker ikke hos os **Rettet** (test i `FidelityTests`). |
| 4 | `focusDirection` | `focus_direction`, `focus_window_or_workspace` (bind.c) | Skifter kun tag til venstre/højre; springer ikke over, når special-tagget er aktivt; ingen `view_shift_tag` uden vindue **Rettet** (test i `FidelityTests`). |
| 5 | `clientFocus` | `client_focus` (client.c) | Tjekker ikke `no_focus`; warper selv (mango lader kalderen); arrangerer i flere tilfælde (mango: `prevsel` og vinduet på tagget, ikke flydende, scroller/monocle/faner) **Rettet** (test i `FidelityTests`). |
| 6 | `clientFocusTop` | `client_focus_top` (client.c) | Falder tilbage på første synlige og springer `no_focus` over; mango giver NULL og springer kun `isunglobal` over **Rettet** (test i `FidelityTests`). |
| 7 | `monitorFromDirection` | `monitor_from_direction` (monitor.c) | Giver nil ved kanten; mango går rundt til den fjerneste skærm **Rettet** (test i `FidelityTests`). |
| 8 | `setLayout` | `clear_fullscreen_flag` (client.c) | Rydder fuldskærm/maks. på alle; mango skåner tiled scroller- og monocle-fanevinduer **Rettet** (test i `FidelityTests`). |
| 9 | `setProportion` | `set_proportion` (bind.c) | Sætter hele kolonnen og har ingen vagt for ét vindue; mango sætter stakkens hoved og nægter ved ét vindue uden `scroller_ignore_proportion_single` **Rettet** (test i `FidelityTests`). |
| 10 | `toggleScratchpad` | `toggle_scratchpad` (bind.c) | Viser hele puljen på én gang; mango ét vindue pr. kald **Rettet** (test i `FidelityTests`). |
| 11 | `Client.isScratchpad` | `is_in_scratchpad`, `SCRATCHPAD_SHOWN` (client.h) | Tilstanden er vendt: hos os betyder `isScratchpad` vist og `isMinimized` i puljen **Rettet** (test i `FidelityTests`). |
| 12 | `smartMoveWindow` | `smart_move_window` (bind.c) | Snapper ikke til andre flydende vinduers kanter og kræver et flydende vindue; mango gør det flydende først **Rettet** (test i `FidelityTests`). |
| 13 | `DwindleTree.dwindleCore` | `dwindle_core` (dwindle.c) | Fjerner bladet for vinduer, der ikke er med (fuldskærm, maks.); mango beholder deres plads i træet **Rettet** (test i `FidelityTests`). |
| 14 | `tabMembers` | `tab_state_ok` (tab.c) | Udelader fuldskærm og maks.; mango gør ikke **Rettet** (test i `FidelityTests`). |
| 15 | `tabChainFocus` | `tab_chain_focus` (tab.c) | Vælger fra `focusHistory`; mango bruger `is_tab_focus` pr. vindue **Rettet** (test i `FidelityTests`). |
| 16 | hotarea, sloppy focus | `toggle_hotarea`, `pointer_process_motion` (pointer.c) | Vi har 0,8 s og 50 ms tærskler (timere i tid), hotarea på alle skærme; mango har ingen tærskler, kun den valgte skærm og `is_in_hotarea` **Rettet** (test i `FidelityTests`). |
| 17 | `fireGestureMotion` | `fire_gesture_motion` (trackpad.c) | Fyrer kun første binding; mango alle, springer `move_resize` over og kender `ALLDIR` **Rettet** (test i `FidelityTests`). |
| 18 | `clientGroupJoin` | `client_group_join` (bind.c) | Går gennem `clientChangeMon` (centrerer, rydder `sel`); mango sætter skærmen direkte og arrangerer også den gamle **Rettet** (test i `FidelityTests`). |
| 19 | `clientGroupDetach` | `client_group_detach` (client.c) | Rydder også `isGroupFocus` på en efterladt nabo; mango overlader det til kalderen **Rettet** (test i `FidelityTests`). |
| 20 | `clientReplace` | `client_replace` (client.c) | Kopierer mindre (`bw`, `overview_backup_geom`, `scroller_stack_proportion` mangler) og retter dwindle og scroller for alle layouts **Rettet** (test i `FidelityTests`). |
| 21 | `pointerEndGrabClient` | `pointer_end_grab_client` (pointer.c) | Flytter kun flydende vinduer til en anden skærm; mango alle, husker `oldmonname`, snapper ikke efter et klik på kanten **Rettet** (test i `FidelityTests`). |
| 22 | `clientViewOnMonitor` | `bind_to_view` (bind.c) | `view_current_to_back` skifter `seltags`; mango går til `1 << (prevtag-1)` **Rettet** (test i `FidelityTests`). |
| 23 | `getTagsFirstTag` | `get_tags_first_tag` (monitor.c) | Giver 1 for 0; mango det aktuelle tag, eller TAG0 med special-tagget **Rettet** (test i `FidelityTests`). |
| 24 | `toggle_special_tag`, `Monitor.curtag` | `toggle_special_tag_mon`, `get_mon_curtag` (bind.c, monitor.c) | Vi XOR'er special-bitten og beholder de normale; mango viser TAG0 alene, og `curtag` er 0 **Rettet** (test i `FidelityTests`). |
| 25 | `parseTagrule` | `tag_slot_set_defaults` (reapply.c) | Nulstiller `no_render_border`, `open_as_floating`, `no_hide` ved hver genindlæsning; mango gør ikke **Rettet** (test i `FidelityTests`). |
| 26 | `clientExchange` | `client_exchange` (client.c) | Bytter i både scroller og dwindle på alle skærme; mango kun i det aktive layouts, og arrangerer og warper selv **Rettet** (test i `FidelityTests`). |
| 27 | tile, grid | `tile_core`, `grid_core` (horizontal.c) | Ser bort fra `master_mfact_per`, `grid_col_per`, `grid_row_per` pr. vindue **Rettet** (test i `FidelityTests`). |
| 28 | `cycleOvercircle` | `over_circle` (bind.c) | Flytter ikke fokus ved hvert skridt; mango kalder `client_focus` **Rettet** (test i `FidelityTests`). |
| 29 | `lastAxisFire` | `axis_apply_time` (server.h) | Feltet bruges ikke **Rettet** (test i `FidelityTests`). |

## 7. Fundet ved gennemgangen af `client_apply_rules` 2026-10-30

Fundet, da `handleClientMap`/`clientApplyRules` blev lagt linje for linje ved siden af mangos
`handle_client_map` og `client_apply_rules` (manage/client.c). Navnegennemgangen (§6) parrede
navne og fangede dem ikke. Alle er rettet med en test hver (`Tests/MangoCoreTests/FidelityTests.swift`).

| # | Afvigelse | mango |
|---|---|---|
| 1 | Et nyt vindue uden plads fra en regel blev ikke centreret **Rettet** | `client_center_geometry` |
| 2 | Et nyt flydende vindue lagde sig oven på et andet **Rettet** | `set_float_malposition` |
| 3 | En regels tags uden for synet åbnede stille; mango viser dem, medmindre vinduet er silent **Rettet** | `client_view_on_monitor` |
| 4 | `is_tag_silent` gav aldrig fokus; mango giver fokus, når tagget er i synet (`is_open_silent` aldrig) **Rettet** | `should_init_get_focus` |
| 5 | Et vindue uden fokus lå forrest i fokusstakken; mango lægger det bagerst **Rettet** | `wl_list_safe_reinsert_prev` |
| 6 | `open_as_floating` blev læst fra tagget i synet før reglerne; mango læser vinduets eget tag **Rettet** | `check_match_tag_floating_rule` |
| 7 | Et nyt tiled vindue tog ikke et fuldskærmsvindue på tagget ud af fuldskærm **Rettet** | `clear_fullscreen_flag` |
| 8 | Et navngivet scratchpad fra en regel blev skjult; mango viser det og skjuler de andre med `single_scratchpad`. `toggle_named_scratchpad` går nu også gennem `apply_named_scratchpad` (skjuler det viste på tagget, også uden fokus) **Rettet** | `apply_named_scratchpad` |
| 9 | `window_rule_once` virkede som `window_rule` **Rettet** | `is_once_applied` |
| 10 | Brøker i `width`/`height` var af arbejdsområdet; mango af hele skærmen. Forskydningen holdt ikke vinduet på skærmen **Rettet** | `client_apply_rules`, `client_center_geometry` |
| 11 | Af de skærme, en regel matcher, vandt den første; hos mango den sidste **Rettet** | `client_apply_rules` |

## 8. Fundet ved Fable-gennemgangen 2026-10-31

Fable gik hele koden igennem mod mangos kilde (kernen, layout, config, IPC, porten og
udvidelserne). Rettet med en test hver i `FidelityTests` og `IPCTests`, undtagen 2 og 7:

| # | Afvigelse | mango |
|---|---|---|
| 1 | `exec`/`exec_once` gik uden shell **Rettet** | `run_exec`, `run_exec_once` (reapply.c): `spawn_shell` |
| 2 | `toggleview` arrangerede som et tag-skift **Rettet** | `toggle_view`: `arrange(m, false, false)` |
| 3 | `centerwin` centrerede et fuldskærms- eller maksimeret vindue **Rettet** | `center_window` |
| 4 | Overview-dispatcherne virkede, mens et vindue blev trukket **Rettet** | `toggle_overview`, `enter_overview`, `leave_overview` |
| 5 | `resizewin` animerede et tiled vindue og ikke et flydende **Rettet** | `resize_window` |
| 6 | `incnmaster`, `setmfact`, `setlayout` og scrollerens dispatchere brugte vinduets skærm **Rettet** | `inc_nmaster`, `set_master_factor`, `set_layout`, `set_proportion`, `scroller_stack`: den valgte skærm |
| 7 | `toggleglobal`/`toggleoverlay` arrangerede **Rettet** | `toggle_global`, `toggle_overlay`: kun rammens farve og laget |
| 8 | Et tal i `focusmon`/`tagmon` valgte skærm nr. n (portens opfindelse) **Fjernet** | `parse_monitor_arg` |
| 9 | Skærmnavne i regler matchede uden hensyn til store og små bogstaver **Rettet** | `regex_match` (util.c) |
| 10 | Tom `jump_labels` var en fejl **Rettet** (ingen mærker) | `option_defs.c`, `create_jump_hints` |
| 11 | `mmsg dispatch spawn` tog resten rå **Rettet** | `combine_args_until_empty` |
| 12 | `scroller_proportion_preset` krævede rene tal, og `drop_color`s alpha var 0x80 **Rettet** | `sscanf("%f")`, `dropcolor[3] = 0.5f` |

Også rettet: navnene `getTagStatus`, `clientAtPoint` og `monitorAtPoint` (før `isOccupied`,
`client(at:)` og `monitor(containing:)`), forkerte doc-kommentarer og manglende "not in
mango"-mærker. `switch_keyboard_layout` står nu som ikke bygget endnu (macOS kan skifte
inputkilde med `TISSelectInputSource`), ikke som umulig.

Struktur, besluttet 2026-10-31:

- **Flyttet hjem til kernen (rettet):** dialogvalget (`handleClientFloatTypeKnown`, gennem
  `clientSetFloating`), minimering efter søvn (mangos `handleClientRequestMinimize`), et
  flydende vindues genlæste ramme (gennem `userMoved`) og tryk på fane- og gruppebjælken
  (`handleBarButtonPress` og mangos `client_handle_decorate_click`; et tryk på en
  gruppebjælke skifter nu gruppens fokus som i mango, og et højreklik på en fane uden
  `monocle_right_button_close` fokuserer den). Mangos træk af et gruppemedlem ud af
  bjælken (`group_bar_drag_pending`) er ikke porteret.
- **Flyttet ud til porten (rettet):** `macos_focus_app`s vælger (tasterne og at forlade
  den) ligger i `Port/Extensions/FocusApp.swift` og kobles på med `PortHooks.pickerKey` og
  `PortHooks.leavePicker`; feltet `picker` og to vagter bliver i kernen, mærket. Portens
  dispatchertabeller står nu i `MangoCompat` (`portDispatchers`, `portOldDispatcherNames`).
- **Animationerne:** valget ligger i kernen (`Engine/Animation.swift`: `clientAnimation`,
  `setClientOpenAnimation`, `isSpecialAnimationRule`, `setTaginAnimation`), porten tegner
  (trin 1). Slide ved åbning kommer fra den side, mango vælger: scrolleren og et enkelt
  vindue nedefra, tile/deck/right_tile efter `new_is_master`, ellers arbejdsområdets
  nærmeste kant (trin 2, **rettet**). Ind i overview (mangos `overining`) zoomer de kort,
  der ikke er det valgte vindue, ind fra 1,2 gange deres størrelse med tag-varigheden; ud
  af overview og flytninger i den er almindelige MOVE med flyttevarigheden (før brugte vi
  tag-varigheden begge veje) (trin 3, **rettet**; gælder overview uden Skærmoptagelse,
  hvor vinduerne flyttes). Ved et tag-skift glider vinduerne på det tag, man forlader, ud
  af skærmen og parkeres først bagefter (mangos `set_arrange_hidden`, `set_tagout_animation`;
  trin 4, **rettet**). Mangos slides for special-tagget og scratchpad (ind og ud foroven) er
  ikke porteret (M).
- **Tastatur og mus:** mangos beslutninger ligger i kernen som rene funktioner, som portens
  event tap kalder på sin egen tråd (macOS vil have svaret med det samme):
  `Keyboard.keyboardCheckKeybinding` (`keyboard_check_keybinding`),
  `Pointer.pointerProcessButtonPress` og `Pointer.handleCursorAxis` (pointer.c) (trin 1,
  **rettet**). Rækkefølgen i `handle_keyboard_key` og mangos tastaturtilstand
  (`last_hold_keycode`, de slugte taster) ligger der også: `Keyboard.handleKeyboardKey`
  og `Keyboard.handleUnboundKey` (trin 2, **rettet**). Porten beholder tråden, Caps Lock
  som Hyper, at sende en tast til en anden app, og sine udvidelser (⌘1-9, vælgerens
  taster) mellem de to. Tvunget (T): mango stopper søgningen efter bindinger, når en dispatcher svarer
  non-zero; det ved porten først på hovedtråden, så `setkeymode` og `chvt` stopper den.
- **Bliver i kernen, bevidst (V):** `Shortcuts.swift` (hotkeys-palettens data og `mmsg
  binds`), `SavedLayout`/`DepartedWindows` (vinduer overlever en genstart og dvale på macOS)
  og appens egne træk (`userMoved`, `followUserDrag`: macOS' svar på Waylands
  `request_move`). Alle mærket "not in mango".

## Det, der ikke kan lade sig gøre (T, kun til orientering)

Står i `docs/compatibility.md` og i `mango -p`:
blur, skygger, dæmpning, gennemsigtighed, layer-shell, tastatur-, mus- og
trackpadindstillinger, markør, skærmregler, HDR, tearing, virtuelle skærme,
virtuelle terminaler, lukkontakt, Xwayland, Wayland-protokoller,
skrivebordets farve (`root_color`: baggrunden er macOS') og luk-animationer.
