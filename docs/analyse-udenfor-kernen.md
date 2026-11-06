# Alt uden for kernen: hvad har vi, hvad koster det, hvad kan blive enklere

2. november 2026. Udarbejdet i to runder med Fable og Sonnet. I første runde svarede de hver for sig. I anden runde svarede hver på den andens uenigheder. Påstande om kode og om mango er tjekket i kilden.

## 1. Status

| Del | Linjer (uden tomme) |
|---|---|
| Kernen, `Sources/Mango` | 13.272 |
| `Port/macOS` | 5.492 |
| `Port/Extensions` | 2.206 |
| `MangoApp` (menu, layoutpanel, `-p`) | 1.052 |
| `mmsg`s macOS-kommandoer (`Sources/Port/mmsg`; mangos mmsg er kernen, `Sources/Mango/mmsg`, fra 6. november) | 407 |
| `MangoPrivate` | 68 |
| **Uden for kernen i alt** | **9.285** |
| Tests | 8.702 |

**Kernen er næsten låst.** Siden første commit er den ændret i fire commits:

- `d04a616` (fokus før arrange): mangos egen rækkefølge, en troskabsrettelse.
- `9e111d2`: en linje i portens tabel `MangoCompat`, som må ligge i kernen.
- `16ff071` og `d06e237`: en lækage. Hotkeys-palettens tekst for en port-dispatcher og en adgangsændring ligger i kernens `Engine/Shortcuts.swift`. Den fil (164 linjer) er reelt portens.

Alle kroge går gennem `PortHooks`. Der er omkring 210 mærker "not in mango" i kernen (6. november 2026), og de står ærligt mærket.

### Reglen fra 2. november: kernen indeholder kun det, der findes i mangoWm

CLAUDE.md trækker nu grænsen efter, hvor koden stammer fra. Det, mangoWm ikke har, hører ikke til i `Sources/Mango`, uanset framework. Eneste undtagelse er kaldet over grænsen: én mærket linje, hvor mangos kode kalder porten i stedet for wlroots (`WindowSystem`), og hvor en udvidelse kobler sig på (`PortHooks`).

Det skal ud af kernen efter den regel:

| Hvad | Filer | Linjer | Hvorhen |
|---|---|---|---|
| Grænsefladen | `Engine/WindowSystem`, `Model/Screen`, `Engine/PortHooks`, `Engine/InputState` | ~290 | Et eget modul ved siden af kernen, der hvor wlroots står |
| Portens tabeller | `Config/MangoCompat`, `Config/PortOptions` | ~440 | Porten. Parseren får dem gennem en krog |
| Port-funktioner | `Engine/Shortcuts`, `Engine/DepartedWindows`, `Engine/SavedLayout`, `Engine/SwipeTracker` | ~430 | Porten, med en krog hvor mangos kode bruger dem |
| Portens felter i `Config` | omkring 20 `chutney*`-felter i `Model/Config.swift` | ~60 | Porten, fx en tabel med portens værdier |
| Mærket port-logik inde i mangos filer | omkring 210 mærker, mest i `MangoServer`, `WindowSystem`, `Dispatch`, `Input`, `Tabs` | ? | Gås igennem én ad gangen: et kald over grænsen bliver, port-logik flyttes ud bag en krog |

Rækkefølgen er de hele filer først, fordi de er mekaniske at flytte. Mærkerne kommer bagefter og kræver en vurdering hver især.

**Status efter trin 9 (2. november):** alle fem rækker er gjort. Det, der bevidst er blevet i kernen, og prisen for at flytte det, står i `docs/plan-kerne-backend.md` under "Det, der står tilbage i kernen".

## 2. Funktionerne uden for kernen

| Gruppe | Linjer | Vurdering |
|---|---|---|
| **Vinduer via Accessibility:** AX, AppWatcher, Placement, Animator, WindowClassifier, parkering, MacWindowSystem | ~3.000 | Behold. Det er wlroots' plads og bærer de egentlige macOS-farer. |
| **Input:** EventTap, InputRouter, KeyNames, gestures, KeyboardOptions | ~800 | Behold. |
| **Mangos egne tegninger:** kanter, faner, switcher, overview, jump-mærker, nag | ~1.300 | Behold. |
| Tilladelsesvinduet | ~250 | Behold. |
| Tastevalg ved første start (ConfigFiles, KeysChoice, HyperKeyRecorder) | ~250 | **Forenkl eller fjern** (punkt 3.3). |
| **Hotkeys-paletten** (Hotkeys, HotkeysModel, Shortcuts i kernen) | ~1.400 + 435 test | **Behold** (punkt 3.1). Stor, men funktionerne bliver brugt. |
| Layout-paletten | ~300 | Behold. |
| Menulinje-status og layoutpanel | ~800 | Behold. |
| **Menuens gemte valg:** MenuSave, OverridesWindow, konflikter, `-p`-advarsler | ~400 + 96 test | **Skær ned** (punkt 3.2 og afsnit 4). |
| `chutney_style` og tema (ChutneyTheme, PortAccent) | ~150 | Behold (afsnit 4). |
| `chutney_focus_app` | ~140 | Behold. Du har 25 taster på den. |
| Små nøgler: floating_color, tab-genveje, border_unfocused, physical_pixels, ignore_apps, set_proportion_all | ~100 | Behold. 10–25 linjer hver, og de er slået fra uden deres nøgle. |
| `mango -p`, `--list-ignored`, MangoCompat | ~470 | Behold. Regel 1 kræver listen. |
| `mmsg`s service, logs, reload og binds (porten; mangos mmsg er kernen) | ~410 | Behold. |
| MainThreadWatchdog | 66 | Behold. Den kører kun med `-d`, og dens timer er nævnt. |

## 3. Forenklinger, begge reviewere står bag

### 3.1 Hotkeys-paletten: bliver, som den er

Begge reviewere foreslog at fjerne Spotlight-apps, "senest brugt" og grupperne (cirka 250–350 linjer). **Fravalgt 2. november.** Til sammen er de kun cirka 200–250 af palettens 1.400 linjer, og de giver noget væsentligt:

- **Spotlight-apps** gør paletten til en app-starter, så Spotlight ikke skal bruges.
- **Grupperne** giver overblik over alle taster uden søgning. Det er opdagelsen.
- **"Senest brugt"** sætter de mest brugte taster øverst.

Skal paletten strammes op, er kandidaten de cirka 48 grene for mango-udseende i paletterne. Paletterne har intet mango-forbillede, så de kunne nøjes med ét udseende. Det kræver et ja fra dig.

### 3.2 Menuens konfliktmaskineri: cirka 150–250 linjer

- Fjern OverridesWindow, `MenuSave.conflicts` og `clear`/`clearAll` samt `-p`-advarslerne om menuens overstyring.
- En gråtonet "lås" virker ikke. Den udsendte `config.conf` sætter selv gaps og `border_px`, så alle panelets skydere ville være låst fra første dag.

### 3.3 Første start uden tekstkirurgi

Begge vil af med den kode, der omskriver dine filer (`withoutBindings`, `withHyperKeys`), og med optageren af Hyper-tasten. Det er den eneste kode, der skriver i brugerens config.

- **Fable:** behold valget, men lad et Makefile-trin bygge to hele filer (`config.conf` og `config-mac.conf`). Valget bliver så en ren kopi. Det sparer cirka 120–150 linjer og kræver en test, der holder `config-mac.conf` i trit med mango.
- **Sonnet:** fjern valget. Standarden er plain mango, og docs siger "kopier mac-bindings.conf". Det sparer cirka 250 linjer.

### 3.4 `Shortcuts.swift` ud af kernen

Flyt de 164 linjer til `Port/Extensions` med én krog til `get binds`. Så skal kernen ikke længere ændres, hver gang paletten får en ny dispatcher. Med reglen fra 2. november er det ikke længere et valg, men et krav (se afsnit 1).

### 3.5 Det, der bliver

- **Menulinjens fire nøgler:** at slå dem sammen sparer kun cirka 25 linjer, og din `chutney_menu.conf` bruger dem allerede. At fjerne dem ville smide din config væk.
- **Tab-genvejenes tilstand i kernen** (syv steder): den er viklet ind i event tap og faner. At flytte den giver flere kroge og sparer næsten intet.

## 4. Config-filerne

**I dag** er der fire filer: `config.conf` og `chutney.conf`, som du skriver i, og `chutney_theme.conf` og `chutney_menu.conf`, som appen skriver. Dine egne filer viser problemet:

- `config.conf` har 0 bindinger, og `chutney.conf` har 135.
- `chutney_menu.conf` overskriver i stilhed 12 værdier, som `config.conf` stadig viser med andre tal, fx `gappih` 5 mod 12, `border_px`, `scroller_default_proportion` 0.8 mod 1.00 og `tag_rule` for tag 1–9. Læser man `config.conf`, får man forkerte svar.
- En femte fil ligger skjult: `~/Library/Application Support/mango/hotkeys-usage.json`.

Reviewerne byttede standpunkt i anden runde. Det viser, at begge modeller kan forsvares, og at valget er dit:

| | **A. To brugerfiler, appen skriver intet** | **B. Én brugerfil, appens filer læses sidst** |
|---|---|---|
| Filer | `config.conf` (mangos), `chutney.conf` (Mac) | `config.conf` (din, med en `chutney_`-blok sidst). Appen ejer `chutney_menu.conf` og `chutney_theme.conf` med teksten "rør ikke" |
| Panelet | Gemmer ikke, som mangos `setoption`: det gælder til næste reload. Evt. en knap, der kopierer ændringerne som config-linjer | Gemmer, og det sidste vinder. Kontrollen viser en note som "config.conf:145 siger 5", men ingen lås |
| Tema | I hukommelsen, kun for farver, du ikke selv har sat. Det kræver en regel som "afviger fra mangos eksempel = din", og den er en heuristik | Uændret som fil |
| Kode | Cirka −400 linjer | Cirka −150–250 linjer |
| Du skal lære | To filer, uden læserækkefølge, og intet bliver overskrevet | Én fil at redigere. Appens filer vinder, men det kan ses |
| Mango | `config.conf` er mangos egen og kan læses af mango | Mango melder "Unknown keyword" for hver `chutney_`-linje (tjekket i `option_defs.c`), men læser resten |
| Risiko | Panelets valg forsvinder ved genstart: gaps og tag 1 som scroller skal flyttes ind i `chutney.conf` | Overstyringen i stilhed findes stadig, nu bare vist som note |

**Min anbefaling er B.** Din bekymring er antallet af filer, man skal forstå og opdatere. Med B redigerer du kun én, og de to andre er tydeligt appens. Overstyringen bliver synlig ved kontrollen i stedet for at gemme sig i en fil.

Vælger du A, bør knappen "kopiér som config-linjer" komme med. Ellers mister du dine panelvalg ved første genstart.

## 5. Rettede påstande undervejs

- **"Mango ignorerer ukendte nøgler i stilhed"** (Fable, runde 2): forkert. Mango melder "Unknown keyword" og springer linjen over. Teksten i `MangoCompat`, "this file will not load in mango", er dog for stærk og bør rettes til "mango reports each `chutney_` line".
- **"Tema i hukommelsen uden ændring i kernen"** (Fable, runde 1): teknisk muligt via `PortHooks.configLoaded`. Fable trak det dog selv tilbage, fordi porten ikke kan skelne mangos eksempelfarver fra dine egne.
- **"CRLF-håndteringen kan væk"** (første review): forkert, for `Resources/config.conf` er CRLF.

## 6. Rækkefølge, hvis vi går i gang

1. Config-modellen (A eller B). Den afgør punkt 3.2 og 3.3.
2. Menuens konfliktmaskineri (3.2).
3. Hotkeys-paletten (3.1): bliver, som den er.
4. Første start (3.3).
5. `Shortcuts.swift` ud af kernen (3.4).
