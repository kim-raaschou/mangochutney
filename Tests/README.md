# Tests

The tests are split as the code is.

| Target | What it tests | Stands on |
|---|---|---|
| `MangoTests` | mango's own behaviour, on the core alone | `MangoTestKit` (mango with wlroots faked); the port is not imported |
| `PortTests` | the port and its extensions, and mango through the port | `EngineRig` (the port with the apps faked) |

`MangoTestKit` holds `TestMango` and `FakeWlroots`. `FakeWlroots` stands where wlroots stands: it
does what mango asks and remembers it, nothing more.

## A test of mango

What mango itself can answer is asked of mango: a scenario in `Tests/MangoFacit` (below). A Swift
test of mango is for what mango's answers cannot show: the focus stack, internal state, what mango
asks of wlroots. One file per mango source file, at the same path (`src/manage/client.c` is
`MangoTests/manage/ClientTests.swift`), and one `// MARK:` per mango function.

```swift
// MARK: handle_client_map

func testANewClientIsFocused() {
    let mango = TestMango()
    mango.map("a")

    mango.map("b")

    XCTAssertEqual(mango.focused, "b")
    XCTAssertEqual(mango.focusStack, ["b", "a"])
}
```

- The config is mango's own lines; with none, mango's defaults (animations off).
- Clients are named by their title.
- A dispatcher is run as a key binding runs it.
- Three parts: the setup, one blank line, what is done, one blank line, what is checked.
- The expected value is mango's, read in mango's source. A comment quotes mango where the reason is
  not plain.
- A mango bug we fix (`docs/afvigelser.md` §6) is named so in the test's comment.
- No test of a single detail of mango's code (an order, a limit, a parse rule): that we are 1:1 is
  checked against mango's source, file by file (`docs/verificeret.md`). A §6 fix is the exception.

## mango's own answers (facit)

`Tests/MangoFacit` holds scenarios and what mango 0.19.0 itself answered to them. A scenario is
played on real mango, run headless in a container, and `mmsg get` is asked at each `check`; the
answers are the facit. `FacitTests` plays the same scenario on our mango and asks the same `mmsg`
lines through our IPC: the answers must be the same.

```
# tile with 1, 2, 3 and 5 windows, then nmaster, mfact and gaps.
config new_is_master=0
dispatch setlayout,tile
open a
check
open b
check
dispatch incnmaster,1
check
ours e.height 351
```

| Step | What it does |
|---|---|
| `config <line>` | a line of mango's config |
| `monitors 2` | two outputs side by side (one when not given); `monitors 2560x1440 1280x1024` gives their sizes |
| `open a [1200x500] [dialog]` | a window titled `a`, of its own size (800x600 unless given; a dialog has a fixed size, 400x300 unless given, and floats) |
| `request a minimize` | the app asks for itself: `minimize`, or `title <new title>` |
| `request a activate by c` | `a` asks to be activated with a token the focused `c` gave it (xdg_activation_v1) |
| `reload gap_inner_horizontal=20` | a line added to the config, then `reload_config` |
| `output add EXTRA` | a new output (mango's `create_virtual_output`; a display plugged in for ours), placed by its `monitor_rule` |
| `close a` | the window goes |
| `dispatch focusstack,next` | `mmsg dispatch focusstack,next` |
| `dispatch @b killclient` | aimed at the window titled `b`: `mmsg dispatch killclient client,<its id>` |
| `key super+shift+j` | keys of a virtual keyboard: down in order, then up the other way |
| `keydown super` / `keyup super` | one key down or up, held across the steps between |
| `pointer 500,300` | the virtual pointer to 500,300 in the layout |
| `move -400,500` | the pointer moved by -400,500 (kept off the layout's edges) |
| `click left` | a button down and up; `button left down` / `button left up` alone |
| `scroll down` | one notch of the wheel (up, down, left, right) |
| `check` | mango's clients, monitors and pointer are compared here |
| `get all-tags` | mango's whole answer to `mmsg get all-tags` is compared here (`get client @b` names a window) |
| `ours a.height 351` | where we answer otherwise on purpose: a mango bug we fix (`docs/afvigelser.md` §6); after a `get`, a path into its answer (`ours clients.3.height 351`) |

Keys and the pointer reach mango as a virtual keyboard and pointer (`recorder/facit-input.c`), and
reach our mango as the port gives them (`TestMango.key`, `pointer`, `move`, `button`, `scroll`); the
key names are xkb's us keymap with evdev codes (`FakeKeymap`). As in mango, a virtual keyboard's
modifiers do not count for mouse and axis binds, and its mode key's release neither leaves overcircle
nor commits the switcher.

A config file in `Tests/MangoFacit/configs` (`.conf` or `.toml`) is checked by mango as
`mango -c <file> -p` checks it: its exit and its errors are the facit (`facit/configs/<file>.json`).
`ConfigFacitTests` reads the same file with our parser and the macOS port's side of the config, as our
`mango -p` reads it, and compares error by error. `# ours: drop <error>` and `# ours: add <error>` in
the file mark where we judge otherwise on purpose, the error written as the test prints it.

A new scenario is recorded with `Tests/MangoFacit/record scenarios/<name>.mango` (the header of
`record` says what it needs); `make test` only reads the facit and needs no container. The checks go
by their order, so a comment or an `ours` line needs no new recording.
