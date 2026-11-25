# Plan: mangos workspace overview (wsov) på macOS

Mango 0.19.0 (`a005a27`), `src/workspace_overview/` (11 filer, ca. 5.600 linjer) og kernens kald ind i
den. Aftalt 25. nov. at porte den som en opgave for sig, efter resten af 0.19.0 (`5d7bb7a`).

## Valg (25. nov.)

1. **Kortenes indhold: arrange uden at skrive.** Mangos `wsov_capture_workspace_tags` kører
   `arrange(m, false, true)` på hvert tag efter tur og læser `animation.current`. Vi gør det samme i
   kernen; porten holder skrivningerne tilbage, mens der måles (ét kald over grænsen, mærket). Hvert
   vindue vises som skærmbillede (ScreenCaptureKit, som overview) på sin plads i kortet.
2. **Live tagskift som mango.** `wsov_activate_target_tag` viser tagget live ved hver ændring af
   markeringen (hover, taster, hjul). Panelet dækker skærmen; parkering sker bag det.
3. **Baggrund: `rootcolor`.** Ingen layer shell på macOS. Skrivebordsbilledet kan blive en
   port-udvidelse senere.
4. **Gitter og scroll på én gang.** Hele logikken i ét stræk.

## Deling

**Kernen (`Sources/Mango/workspace_overview/`), 1:1 med mangos navne**, ca. 2.800 linjer logik:

| mango | indhold |
|---|---|
| `tag.c` | tag-sæt (all/occupied, `retained_tags`), standardmål, retningsvalg, aktivering af tag |
| `input.c` | taster (Escape/Return/pile/hjkl), knapper, bevægelse, hjul |
| `workspace_card.c` | gitter- og scroll-geometri, scroll-grænser, hjulets deceleration, træk-scroll, layout-animation |
| `drag_drop.c` | drop-kort/-vindue/-zone (`client_drop_zone`), tags ved drop (Ctrl/Shift), flydende placering, gem/genskab flydende |
| `viewport_camera.c` | kameraets visning (zoom ind/ud), skærmbokse, hit-test, synlighed |
| `event_hooks.c` | hooks fra kernen og frame-tilstandsmaskinen |
| `workspace_overview.c` | åbn/luk/genopbyg, dispatcherne |
| `offscreen_texture.c` | kun logikken: `wsov_capture_workspace_tags`, `wsov_capture_cell_items`, `wsov_position_cell_items`, valg af bjælker |
| `decoration.c` | valg af farve og dæmpning |
| `client.c` | kun valget af hvilket kort der ejer et vindue live |

Kernens kald ind i wsov (`workspace_overview_*`, `wsov_hidden`, `is_ws_overview`) sættes ind dér, hvor
mango har dem; markørerne "no workspace overview" fjernes.

**Porten (`Port/macOS`)**: tegningen. Ét panel pr. skærm (som overview) med kortenes ramme, kant,
dæmpning, `rootcolor`, vinduernes skærmbilleder på deres pladser, drop-feltet og træk-billedet.
Frame-løkken drives af portens frame clock. Skjulning (`wsov_hidden`) er parkering bag panelet.

**Ikke her** (wlroots/scenefx): offscreen GL-rendering, live `wlr_surface`-montering, scenefx-effekter
(`client_effects.c`), layer shell (`layer.c`), blur-baggrund.

## Grænsen

- `WindowSystem`: vis/opdatér/luk wsov-panelet med kortene og deres indhold (porten tegner);
  hold skrivninger tilbage under målingen.
- Input: når wsov er aktiv, sender porten knapper, bevægelse, hjul og taster til kernens
  `workspace_overview_handle_*`, som mango gør i `pointer.c` og `keyboard.c`.

## Tests

Facit fra rigtig mango 0.19.0 for wsov: åbn/luk i begge scopes og layouts, piletaster, Return,
Escape, klik på et kort, træk af et vindue til et andet tag (med og uden Ctrl/Shift), hjul i
scroll-tilstand. `mmsg get` efter hvert skridt (tags, fokus, geometri).
