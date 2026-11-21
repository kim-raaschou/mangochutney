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
