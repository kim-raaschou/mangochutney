# mango for macOS

A Swift port of the mango Wayland compositor (reference: `~/sources/mango`, mango 0.18.2).
The user writes Danish; answer in Danish.

## Tro mod huset (faithful to mango) — rule 1

Someone who knows mango's source must recognise our Mango side, and everything they do not
recognise must be marked as port or extension.

1. **Everything mango has.** Every function, dispatcher and config key. Only what macOS
   physically cannot do may be missing, and it is listed with the reason (`mango -p`,
   `MangoCompat`, `docs/afvigelser.md`).
2. **Behaves as mango.** The same steps, conditions, order and edge cases. Mango's source is
   the answer, not an interpretation of it. A deviation is a bug.
3. **Mango's defaults.** Default values, looks and config are mango's. With no settings the
   port behaves as plain mango.
4. **Mango's names.** Types, functions and fields carry mango's names, in lowerCamelCase:
   `MangoServer`/`server`, `Client`, `Monitor`, `handleClientUnmap`, `selectedMonitor`,
   `floatGeom`. Where mango splits work in two (unmap/destroy), so do we. Check
   `~/sources/mango` before naming anything.
5. **Mango's structure.** `server` is mango's `struct MangoServer`; `Client` carries its
   platform part (`platform: MacWindow`) as mango's `Client` carries wlroots. The port stands
   where wlroots stands and calls mango's handlers as wlroots does (`WindowSystem` is the
   boundary).
6. **What is not mango is apart and marked.**
   - macOS layer (Accessibility, parking, native focus) lives in `Port/macOS`.
   - Port extensions (`focus_app`, `chutney_style`, `auto_float_oversized`, …) live in
     `Port/Extensions`, are off when their key is absent, and change nothing of mango's
     behaviour when off. They hook in only through `PortHooks`. Their config keys are the
     port's (`PortOptions`).
   - Both are marked `not in mango` / `Port extension: not in mango` where used. Few places.
7. **No inventions in mango's code.** No special cases, own names or "improvements". Anything
   macOS-specific is an override in the port, never a change to mango's logic. The one
   exception is a bug in mango (below).
8. **Comments in the core are mango's or a deviation's.** A comment in `Sources/Mango` is either
   mango's own comment, 1:1, or marks where we differ from mango (`not in mango: …`, one short
   sentence). A function with another name than mango's carries one line, `/// mango
   <function> (<file>)`. Nothing else: no explanations of what mango does.

**Mango's bugs.** Where mango's own code is plainly wrong (a bug, not a choice we would make
otherwise), we may differ. Each one is agreed with the user. The fix is the smallest that
will do, preferably mango's own answer from elsewhere in its code. It is marked where it is
made (`not in mango: … (a mango bug, docs/afvigelser.md §6)`), listed in `docs/afvigelser.md`
§6 with mango's result and ours, and locked with a test.

**Within reason.** Faithful as long as it does not get too complex. Something simple in mango
is not to be forced onto macOS at any cost when it gets too complex or awkward there. That is
judged case by case, not by a rule: say what it would cost and decide with the user. When the
answer is a near equivalent or leaving it out, mark it and list it (`docs/afvigelser.md`).

**Where the line is.** `Sources/Mango` holds what is in mangoWm and nothing else: what mangoWm
does not have is not in `Sources/Mango`, however small and whatever framework it uses.
Everything else is the port, `Sources/Port`: `macOS/` and `Extensions/`, which may name and do
things its own way. The one thing that is not mango's and still touches mango's code is the
call across the boundary: where mango calls wlroots, its code calls the port (`WindowSystem`),
and where an extension joins in, it calls `PortHooks`. One marked line at each such place.
The boundary itself (`WindowSystem`, `Screen`, `PortHooks`, `ConfigPort`, …) is declared in
`Sources/Boundary`, built in the same module because its types use mango's; the port's
tables (`MangoCompat`, `PortOptions`) are in the port, as wlroots is outside mango. Anything in
`Sources/Mango` that mangoWm does not have is a deviation: it is listed
(`docs/analyse-udenfor-kernen.md`) and moved out.

**Checking.** Read mango's version before changing a mango function. A known deviation stays
in `docs/afvigelser.md` until fixed. Lock mango's behaviour with a test where possible.

**The core is changed last.** `Sources/Mango` is to stay 1:1 with mango and hold nothing else,
so every change there is weighed carefully before it is made. Port work goes in the port
(`Port/macOS`, `Port/Extensions`, `PortHooks`). A change in the core needs a reason: mango's own
behaviour, or a call across the boundary the port cannot do without. It is the smallest that
will do (an access level, one hook call), marked as the port's, and said to the user before it
is made.

**When rules meet.** Mango's look and behaviour are the base; the macOS way is a port override,
off unless set (`chutney_style`). A config key the user sets always wins.

**Names that clash.** Mango's name wins; our own thing that had the name is renamed.

## Other rules

- No special cases: fix the general rule, never per app or per situation.
- Avoid timers; when one is used, say so.
- Tests never draw on the screen, move the pointer or take focus (`FakeWindowSystem`).
- Least aggressive decision when in doubt.

## Build

`make test`, `make install`, then `open -a "Mango Chutney"` (the app is named Mango Chutney;
its programs keep mango's names, `mango` and `mmsg`). Plan for the Mango/Port split:
`docs/plan-kerne-backend.md`.
