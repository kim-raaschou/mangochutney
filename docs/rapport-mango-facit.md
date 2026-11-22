# Rapport: mango som facit

22. november 2026. Strategien: rigtig mango 0.18.5 afgør, hvad vores kerne skal svare. Hvor vi før
testede vores egen læsning af mangos kode, spørger vi nu mango selv og holder vores svar op mod det.

## Kort fortalt

- **Mango svarer nu selv** på 315 scenarier og 56 config-filer. Vores kerne giver det samme svar i dem
  alle, bortset fra 48 steder, hvor vi med vilje svarer anderledes, og hvert af dem er markeret og
  står i `docs/afvigelser.md`.
- **Syv fejl i kernen er fundet og rettet**, som 854 tests ikke fandt.
- **203 Swift-tests er erstattet** af mangos egne svar. Mango var enig med hver eneste af dem.
- **Dækningen af kernen steg** fra 89,0 % til 92,9 %; mangos svar alene dækker 76,5 %.
- **Testene af mango kan læses uden Swift**: et scenarie er få linjer som `open a`, `key super+j`,
  `check`.

## Sådan virker det

1. Et scenarie beskriver, hvad der sker: vinduer åbnes og lukkes, dispatchere køres, taster trykkes,
   musen flyttes, config'en genindlæses, en skærm sættes til, en app beder om noget.
2. Optageren (`Tests/MangoFacit/record`) kører scenariet i rigtig mango, headless i en container, og
   gemmer mangos svar på `mmsg get` ved hvert `check`. Det er facit.
3. `FacitTests` kører samme scenarie på vores kerne gennem samme `mmsg`-linjer og sammenligner felt
   for felt. `ConfigFacitTests` gør det samme for `mango -c <fil> -p`.

Mango er kun med, når der optages. `make test` læser facit og kører uden container; de to
facit-tests tager tilsammen omkring et sekund.

## Hvad mango kan svare på

| Kanal | Hvad den viser |
|---|---|
| `mmsg get` ved hvert `check` | vinduer (plads, størrelse, tags, fokus, tilstande, rækkefølge), skærme, tags, markøren |
| `dispatch @titel` | dispatchere rettet mod et bestemt vindue |
| virtuelt tastatur og mus | key binds, keymodes, release-binds, musebinds, træk, resize ved rammen, scroll, hot area, switcher, jump mode, bjælkeklik |
| `mango -p` | hver fejl og advarsel i en config, med tekst, linje og exitkode, `.conf` og `.toml` |
| `get <emne>` | mangos hele svar på `all-tags`, `tag`, `client`, `monitor`, `keymode`, `layouts`, `version` … |
| `reload`, `output add`, `request` | genindlæsning, en skærm sat til, appens egne ønsker (minimer, titel, aktivering) |

## Fejl i kernen, som mango fandt

Alle er rettet til mangos opførsel og låst af det scenarie, der fandt dem.

| Hvad | Mangos svar | Vores før |
|---|---|---|
| `exchange_client` i dwindle | bytter vinduerne, fokuserer og arrangerer | byttede kun træets blade: intet synligt |
| tal i IPC | 15 cifre, som cJSON | 16–17 cifre |
| `is_focused` | mangos `isfocusing`-flag | skærmens valgte vindue |
| hvad der er under musen | hele scenen, også et vindue flyttet ind over en anden skærm | kun skærmen under punktet |
| et nyt vindue (map) | `resize`, ingen `arrange` | `arrange`, så et nyt vindue i overcircle stod i midten |
| `global_key_binding` i config'en | starter | gik ned, før der var en skærm |
| `default_master_factor=inf` | 0,9 (klemt) | 0,1 |

Undervejs blev en afvigelse, vi troede fandtes, afkræftet: den lå i testlaget, ikke i kernen.

## Hvad det gav for testene

| | Før | Nu |
|---|---|---|
| Swift-tests af kernen og porten (linjer) | 14.084 | 11.529 |
| Testfunktioner | 867 | 666 |
| Scenarier (filer / linjer) | 0 | 315 / 4.567 |
| Config-filer | 0 | 56 |
| Dækning af kernen, hele suiten | 89,0 % | 92,9 % |
| Dækning af kernen, mangos svar alene | 0 % | 76,5 % |

Dækning pr. område af kernen:

| Område | Hele suiten før | Hele suiten nu | Mangos svar alene |
|---|---|---|---|
| Layout | 90,8 % | 94,0 % | 89,0 % |
| dispatch | 75,9 % | 91,4 % | 89,8 % |
| manage | 85,2 % | 91,3 % | 86,1 % |
| Config | 94,5 % | 95,5 % | 81,4 % |
| switcher | 90,6 % | 97,1 % | 86,7 % |
| input | 88,5 % | 90,1 % | 56,2 % |
| IPC | 87,9 % | 90,2 % | 52,1 % |
| animation | 92,3 % | 93,0 % | 69,2 % |
| mangonag | 95,6 % | 95,6 % | 0 % |

Linjer er ikke målet: et scenarie er omtrent lige så langt som den Swift-test, det erstatter, og
testkoden er samlet ikke blevet mindre (afspiller og falsk wlroots 795 linjer, optager 713). Gevinsten
er, at svaret er mangos eget, at det fandt fejl, og at det kan læses uden Swift.

## Hvad der med vilje er tilbage som Swift-tests

- **Det, mangos svar ikke kan vise:** fokus-stakken, interne felter, hvad kernen beder porten om,
  tegning, animationens kurver, `watch`-strømmen (vores sender med vilje én linje pr. tur, §2).
- **Det, et virtuelt device ikke kan nå:** trackpad-gester (727 linjer i `input`), musebinds med
  modifier.
- **mangonag og fejl-nag:** egne programmer uden for `mmsg`.
- **Portens og udvidelsernes tests:** de tester ikke mango, så mango kan ikke være facit.

Reglen står i `Tests/README.md`: hvad mango selv kan svare på, spørges mango om; en Swift-test af
mango er for det, mangos svar ikke kan vise.

## Forskelle, vi har med vilje

48 `ours`-linjer markerer, hvor vi svarer anderledes med vilje, alle med en henvisning:

- **Mango-fejl, vi retter (§6):** tile giver det sidste vindue i en kolonne resten, CRLF-linjer,
  `incgaps` på special-tagget, en flydende fuldskærmsregel, `vertical_grid` med et flydende vindue.
  Mango selv bekræftede hver beskrivelse i §6.
- **Tvunget af macOS (§3):** skærmnavne med mellemrum (`get tag`), relativ `source=` læses fra
  config-mappen, bindinger på portens taster, `dim_*`-nøgler, macOS ikke kan.
- **Swift:** `nan` læses som 0.

## Testlaget blev bedre undervejs

Den falske wlroots står nu tættere på den rigtige: et vindue tager den størrelse, mango konfigurerer,
når appen svarer; scenen har en stakrækkefølge med lag; bjælkerne er noder, et klik finder; markøren
giver en frame; hvert vindue er sin egen app. Hver gang facit afslørede en forskel, blev det afgjort,
om fejlen lå i kernen eller i testlaget, før noget blev rettet.

## Hvad det koster

- En colima-profil, `mangofacit` (4 CPU, 4 GB), med `vkms` og en lille `LD_PRELOAD`, så mango kan
  tegne headless. Den er kun nødvendig, når der optages.
- At optage alle 315 scenarier tager omkring 10 minutter.
- Facit er bundet til mango 0.18.5. Ved en ny mango-version optages der igen, og forskellen i facit
  viser præcis, hvad mango har ændret.
- Testtiden for hele suiten er uændret (omkring 5½ minut); den bruges af portens tests, der venter i
  realtid.

## Commits

`41e3ae4` … `766f119` på `main`, 20 commits: 7 i kernen, resten i testene og rapporten. Den første
del af arbejdet (POC'en) er beskrevet i `docs/poc-mango-facit.md`.
