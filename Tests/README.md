# Tests

The tests are split as the code is.

| Target | What it tests | Stands on |
|---|---|---|
| `MangoTests` | mango's own behaviour, on the core alone | `MangoTestKit` (mango with wlroots faked); the port is not imported |
| `MangoCoreTests` | the port and its extensions, and mango through the port | `EngineRig` (the port with the apps faked) |

`MangoTestKit` holds `TestMango` and `FakeWlroots`. `FakeWlroots` stands where wlroots stands: it
does what mango asks and remembers it, nothing more.

## A test of mango

One file per mango source file, at the same path (`src/dispatch/bind.c` is
`MangoTests/dispatch/BindTests.swift`), and one `// MARK:` per mango function.

```swift
// MARK: focusstack

func testFocusStackNextGoesDownTheClientsList() {
    let mango = TestMango("new_is_master=0")
    mango.map("a"); mango.map("b"); mango.map("c")
    mango.server.clientFocus(mango.client("a"), true)

    mango.run("focusstack", "next")

    XCTAssertEqual(mango.focused, "b")
}
```

- The config is mango's own lines; with none, mango's defaults (animations off).
- Clients are named by their title.
- A dispatcher is run as a key binding runs it.
- Three parts: the setup, one blank line, what is done, one blank line, what is checked.
- The expected value is mango's, read in mango's source. A comment quotes mango where the reason is
  not plain.
- A mango bug we fix (`docs/afvigelser.md` §6) is named so in the test's comment.

## mango's own answers (facit)

`Tests/MangoFacit` holds scenarios and what mango 0.18.5 itself answered to them. A scenario is
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
| `monitors 2` | two outputs side by side (one when not given) |
| `open a [dialog]` | a window titled `a` (a dialog has a fixed 400x300 and floats) |
| `close a` | the window goes |
| `dispatch focusstack,next` | `mmsg dispatch focusstack,next` |
| `dispatch @b killclient` | aimed at the window titled `b`: `mmsg dispatch killclient client,<its id>` |
| `check` | mango's clients, monitors and pointer are compared here |
| `ours a.height 351` | where we answer otherwise on purpose: a mango bug we fix (`docs/afvigelser.md` §6) |

A new scenario is recorded with `Tests/MangoFacit/record scenarios/<name>.mango` (the header of
`record` says what it needs); `make test` only reads the facit and needs no container. The checks go
by their order, so a comment or an `ours` line needs no new recording.
