import XCTest
@testable import Mango
@testable import Port

@MainActor
final class HotkeysPaletteTests: MangoTestCase {
    let hyper: Modifiers = [.superKey, .ctrl, .alt]

    func model(_ config: String, apps: [String: String] = [:], context: HotkeysContext = HotkeysContext(hasFocused: true),
               windows: [HotkeysWindow] = [], installed: [HotkeysApp] = [], usage: [String: Double] = [:]) -> HotkeysModel {
        let parsed = ConfigParser.parse(text: config, baseDirectory: FileManager.default.temporaryDirectory,
                                        fileName: "test.conf")
        XCTAssertEqual(parsed.errors, [])
        let m = HotkeysModel()
        m.load(ShortcutFormatter.rows(parsed.config), hyper: hyper, context: context, windows: windows, apps: installed,
               usage: usage, appName: { apps[$0] }, appPath: { apps[$0].map { "/Applications/\($0).app" } })
        m.refuse = {}
        return m
    }

    let config = """
    chutney_hyper_modifier=super+ctrl+alt
    bind=hyper,Left,focusdir,left
    bind=hyper,1,view,1,0
    bind=hyper,2,view,2,0
    bind=hyper+shift,1,tag,1,0
    bind=hyper,Return,spawn,open -na Terminal
    bind=hyper,q,killclient,
    mousebind=hyper,btn_left,moveresize,curmove
    bind=hyper,w,setkeymode,window
    key_mode=window
    bind=none,Left,resizewin,-50,+0
    key_mode=default
    """

    func testWithoutASearchTheGroupsShowInOrderWithTheirCounts() {
        let m = model(config)
        XCTAssertEqual(m.items, [.group("Apps", 1), .group("Focus", 1), .group("Move & swap", 1), .group("Tags", 2),
                                 .group("Window", 1), .group("Mouse & trackpad", 1), .group("mango", 1)],
                       "by what a binding does: window mode's resizewin is in Move & swap")
    }

    func testEveryWordOfTheSearchMustMatch() {
        let m = model(config)
        m.query = "tag 1"
        XCTAssertEqual(m.items.compactMap { if case .row(let r) = $0 { return r.action } else { return nil } },
                       ["view tag 1–2", "send window to tag 1"], "view tag 1 and 2 are one row")
        m.query = "hyper ←"
        XCTAssertEqual(m.items.count, 2, "the keycaps are searched too: Hyper ←, and ← in window mode (Hyper W › ←)")
        m.query = "nothing like it"
        XCTAssertEqual(m.items, [])
    }

    func testTheHyperModifiersAreOneKeycap() {
        let m = model(config)
        m.query = "send window"
        guard case .row(let r) = m.items.first else { return XCTFail("no row") }
        XCTAssertEqual(r.keys, ["Hyper", "⇧", "1"])
    }

    func testReturnOpensAGroupAndADigitRunsAFoldedRun() {
        let m = model(config)
        var ran: [HotkeyRow] = []
        m.run = { ran.append($0) }
        m.move(3)
        m.enter()
        XCTAssertEqual(m.openSection, "Tags")
        XCTAssertEqual(m.selectedRow?.keys, ["Hyper", "1–2"])
        XCTAssertFalse(m.digit(5), "no tag 5 in the run: the digit is typed")
        XCTAssertTrue(m.digit(2))
        XCTAssertEqual(ran.map(\.dispatch), ["view"])
        XCTAssertEqual(ran.first?.args, ["2", "0"])
        m.move(1)
        m.enter()
        XCTAssertEqual(ran.last?.dispatch, "tag")
    }

    func testBackAndEscapeUndoOneStepAtATime() {
        let m = model(config)
        m.move(2)
        XCTAssertTrue(m.openSelected())
        m.query = "2"
        XCTAssertTrue(m.escape(), "the search is cleared first")
        XCTAssertEqual(m.query, "")
        XCTAssertTrue(m.escape(), "then the group closes")
        XCTAssertNil(m.openSection)
        XCTAssertEqual(m.selection, 2, "on the group that was open")
        XCTAssertFalse(m.escape(), "nothing left: the palette closes")
    }

    func testTheSelectionWrapsAndADragDoesNotRun() {
        let m = model(config)
        m.move(-1)
        XCTAssertEqual(m.selection, m.items.count - 1)
        var ran = 0
        var refused = 0
        m.run = { _ in ran += 1 }
        m.refuse = { refused += 1 }
        m.query = "move window"
        m.enter()
        XCTAssertEqual([ran, refused], [0, 1], "moveresize needs a drag")
    }

    func testTheAppsNameFindsItsKey() {
        let m = model("""
        chutney_hyper_modifier=super+ctrl+alt
        bind=hyper,a,setkeymode,apps
        key_mode=apps
        bindc=none,a,chutney_launch_or_focus,company.thebrowser.Browser
        bindc=none,a,setkeymode,default
        bindc=none,v,chutney_launch_or_focus,com.microsoft.VSCode
        bindc=none,v,setkeymode,default
        bind=none,Escape,setkeymode,default
        key_mode=default
        """, apps: ["company.thebrowser.Browser": "Arc", "com.microsoft.VSCode": "Visual Studio Code"])
        m.query = "arc"
        guard case .row(let r) = m.items.first else { return XCTFail("Arc not found") }
        XCTAssertEqual(r.action, "focus or open Arc")
        XCTAssertEqual(r.keys, ["Hyper", "A", "›", "A"], "the key that enters the mode first")
        m.query = "visual"
        XCTAssertEqual(m.items.count, 1)
        m.query = ""
        m.open("Apps")
        XCTAssertEqual(m.items.count, 2, "in Apps, though they are in a key mode; the setkeymode,default after each is left out")
    }

    func testTheBestMatchComesFirstAndLettersInOrderFindAWord() {
        let m = model(config)
        m.query = "close"
        guard case .row(let r) = m.items.first else { return XCTFail("nothing for close") }
        XCTAssertEqual(r.dispatch, "killclient", "found by its keyword")
        m.query = "wrkspc"
        XCTAssertFalse(m.items.isEmpty, "letters in order within one word")
        m.query = "term"
        guard case .row(let t) = m.items.first else { return XCTFail("nothing for term") }
        XCTAssertEqual(t.dispatch, "spawn")
    }

    func testAKeyModesBindingRunsFromThePalette() {
        let m = model(config)
        var ran: [String] = []
        m.run = { ran.append($0.dispatch) }
        m.query = "resize"
        m.enter()
        XCTAssertEqual(ran, ["resizewin"])
    }

    func testABindingShowsItsStateAndIsDimmedWhenItWouldDoNothing() {
        let conf = """
        chutney_hyper_modifier=super+ctrl+alt
        bind=hyper,f,togglefloating
        bind=hyper,t,setlayout,tile
        bind=hyper,s,setlayout,scroller
        bind=hyper,u,focusmon,next
        bind=hyper,e,set_proportion,1.0
        bind=hyper,2,view,2,0
        """
        var ctx = HotkeysContext(hasFocused: true, floating: true, layout: "tile", viewedTags: [2])
        var m = model(conf, context: ctx)
        func row(_ d: String, _ a: String? = nil) -> HotkeyRow? {
            m.rows.first { $0.dispatch == d && (a == nil || $0.args.first == a) }
        }
        XCTAssertEqual(row("togglefloating")?.state, "on")
        XCTAssertEqual(row("setlayout", "tile")?.state, "●", "the layout in view")
        XCTAssertNil(row("setlayout", "scroller")?.state)
        XCTAssertEqual(row("view")?.state, "●", "the tag in view")
        XCTAssertEqual(row("focusmon")?.enabled, false, "one monitor")
        XCTAssertEqual(row("set_proportion")?.enabled, false, "a scroller's, in tile")
        m.open("Layout")
        XCTAssertEqual(m.items.last.flatMap { if case .row(let r) = $0 { return r.dispatch } else { return nil } },
                       "set_proportion", "what would do nothing comes last")
        ctx.hasFocused = false
        m = model(conf, context: ctx)
        XCTAssertEqual(row("togglefloating")?.enabled, false, "no window to act on")
        var refused = 0
        m.refuse = { refused += 1 }
        m.query = "floating"
        m.enter()
        XCTAssertEqual(refused, 1)
    }

    func testTheRowsUsedMostComeFirstWithoutASearch() {
        let conf = "chutney_hyper_modifier=super+ctrl+alt\nbind=hyper,q,killclient,\nbind=hyper,2,view,2,0\nbind=hyper,3,view,3,0\n"
        let m = model(conf, usage: ["b|default|view|3,0": 5, "b|default|killclient|": 1])
        guard case .row(let first) = m.items[0], case .row(let second) = m.items[1] else { return XCTFail("no recent rows") }
        XCTAssertEqual(first.args, ["3", "0"])
        XCTAssertEqual(second.dispatch, "killclient")
        if case .group = m.items[2] {} else { XCTFail("the groups after them") }
        m.query = "view tag"
        guard case .row(let top) = m.items.first else { return XCTFail("no row") }
        XCTAssertEqual(top.digits.keys.sorted(), [2, 3], "the search shows the folded run")
    }

    func testUseIsSavedAndFadesWithTime() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hotkeys-usage-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        HotkeysUsage.record("b|x", at: t0, url: url)
        HotkeysUsage.record("b|x", at: t0, url: url)
        let entries = HotkeysUsage.read(url)
        XCTAssertEqual(HotkeysUsage.scores(entries, now: t0)["b|x"], 2)
        XCTAssertEqual(HotkeysUsage.scores(entries, now: t0.addingTimeInterval(7 * 86400))["b|x"], 1, "a week halves it")
    }

    func testTheOpenWindowsAreRowsThatGoToTheWindow() {
        let wins = [HotkeysWindow(id: 7, app: "Arc", bundleID: "company.thebrowser.Browser", title: "Omarchy Manual", tag: 2),
                    HotkeysWindow(id: 9, app: "Mail", bundleID: "com.apple.mail", title: "Inbox", tag: nil)]
        let m = model(config, windows: wins)
        XCTAssertEqual(m.items.first, .group("Windows", 2), "the windows' group first")
        var ran: [HotkeyRow] = []
        m.run = { ran.append($0) }
        m.query = "omarchy"
        m.enter()
        XCTAssertEqual(ran.first?.kind, .window(7))
        m.query = "inbox"
        guard case .row(let mail) = m.items.first else { return XCTFail("no Mail row") }
        XCTAssertEqual(mail.keys, ["minimized"])
    }

    func testInstalledAppsAreFoundOnlyBySearchAndNotTwice() {
        let conf = """
        chutney_hyper_modifier=super+ctrl+alt
        bind=hyper,a,chutney_launch_or_focus,company.thebrowser.Browser
        """
        let installed = [HotkeysApp(name: "Arc", path: "/Applications/Arc.app", bundleID: "company.thebrowser.Browser",
                                    useCount: 900),
                         HotkeysApp(name: "Calculator", path: "/System/Applications/Calculator.app", bundleID: "com.apple.calculator")]
        let wins = [HotkeysWindow(id: 7, app: "Arc", bundleID: "company.thebrowser.Browser", title: "Omarchy Manual", tag: 2),
                    HotkeysWindow(id: 8, app: "Calculator", bundleID: "com.apple.calculator", title: "Calculator", tag: 1)]
        let m = model(conf, apps: ["company.thebrowser.Browser": "Arc"], windows: wins, installed: installed)
        XCTAssertFalse(m.items.contains { if case .row(let r) = $0 { return r.section == "Launch" } else { return false } },
                       "not without a search")
        m.query = "calc"
        guard case .row(let calc) = m.items.first else { return XCTFail("no Calculator") }
        XCTAssertEqual(calc.kind, .app(path: "/System/Applications/Calculator.app"))
        XCTAssertFalse(m.items.contains { if case .row(let r) = $0 { return r.kind == .window(8) } else { return false } },
                       "a window titled with its app's name is the app's row, not one of its own")
        m.query = "arc"
        guard m.items.count == 1, case .row(let arc) = m.items[0] else { return XCTFail("Arc once: its binding, not its window") }
        XCTAssertEqual(arc.dispatch, "chutney_launch_or_focus")
        XCTAssertEqual(arc.useCount, 900, "ranked by the app's use, as the app would be")
        XCTAssertNotNil(arc.iconPath)
        XCTAssertEqual(arc.place, "tag 2", "where its window is, as the window's row would say")
        m.query = "omarchy"
        guard case .row(let win) = m.items.first else { return XCTFail("the window by its title") }
        XCTAssertEqual(win.kind, .window(7))
        m.query = "arc omarchy"
        XCTAssertTrue(m.items.contains { if case .row(let r) = $0 { return r.kind == .window(7) } else { return false } },
                      "the app's name and the title together find the window")
    }

    func testALongBrowseTakesTwoColumnsAndALongSearchItsBestRows() {
        let binds = (0..<20).map { "bind=hyper,F\($0 + 1),spawn,app\($0)" }.joined(separator: "\n")
        let m = model("chutney_hyper_modifier=super+ctrl+alt\n" + binds)
        m.maxRows = 8
        m.open("Apps")
        XCTAssertEqual(m.page.columns, 2)
        XCTAssertEqual(m.page.rows, 8)
        XCTAssertEqual(m.page.more, 4, "20 rows, 16 shown")
        XCTAssertTrue(m.moveColumn(1))
        XCTAssertEqual(m.selection, 8, "across to the second column")
        XCTAssertFalse(m.moveColumn(1), "no third column")
        XCTAssertTrue(m.moveColumn(-1))
        XCTAssertEqual(m.selection, 0)
        m.query = "app"
        XCTAssertEqual(m.page.columns, 1)
        XCTAssertEqual(m.page.items.count, 8)
        XCTAssertEqual(m.page.more, 12)
    }

    func testTheHeightFollowsTheRowsShown() {
        var heights: [Int] = []
        let m = model(config)
        m.onLayout = { heights.append($0) }
        m.query = "tag"
        m.query = ""
        XCTAssertEqual(heights, [2, 7], "two matches, then the seven groups")
    }

    func testSpotlightsAppsAreTheOnesAPersonOpens() {
        XCTAssertTrue(SpotlightApps.isApp("/Applications/Arc.app"))
        XCTAssertTrue(SpotlightApps.isApp("/Users/me/Applications/JetBrains Toolbox/IntelliJ IDEA.app"))
        XCTAssertTrue(SpotlightApps.isApp("/System/Library/CoreServices/Finder.app"))
        XCTAssertFalse(SpotlightApps.isApp("/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"))
        XCTAssertFalse(SpotlightApps.isApp("/Users/me/Library/Application Support/Foo/Helper.app"))
    }

    func testAnAppUsedMoreComesFirstAndAppsArriveLate() {
        let m = model(config)
        m.query = "not"
        XCTAssertEqual(m.items, [], "no apps yet: Spotlight has not answered")
        m.setApps([HotkeysApp(name: "Notes", path: "/System/Applications/Notes.app", bundleID: "com.apple.Notes", useCount: 2),
                   HotkeysApp(name: "Notion", path: "/Applications/Notion.app", bundleID: "notion.id", useCount: 400)])
        guard case .row(let top) = m.items.first else { return XCTFail("no app") }
        XCTAssertEqual(top.action, "open Notion", "Spotlight's use count breaks the tie")
    }

    func testAppsWindowsAndAppBindingsShowTheirAppsIcon() {
        let conf = "chutney_hyper_modifier=super+ctrl+alt\nbind=hyper,a,chutney_launch_or_focus,company.thebrowser.Browser\nbind=hyper,q,killclient,\n"
        let m = model(conf, apps: ["company.thebrowser.Browser": "Arc"],
                      windows: [HotkeysWindow(id: 3, app: "Mail", bundleID: "com.apple.mail", title: "Inbox", tag: 1,
                                              appPath: "/System/Applications/Mail.app")],
                      installed: [HotkeysApp(name: "Notes", path: "/System/Applications/Notes.app", bundleID: "com.apple.Notes")])
        XCTAssertEqual(m.rows.first { $0.dispatch == "chutney_launch_or_focus" }?.iconPath, "/Applications/Arc.app")
        XCTAssertNil(m.rows.first { $0.dispatch == "killclient" }?.iconPath, "a binding of mango's own: its symbol")
        XCTAssertEqual(m.rows.first { $0.kind == .window(3) }?.iconPath, "/System/Applications/Mail.app")
        m.query = "notes"
        guard case .row(let notes) = m.items.first else { return XCTFail("no Notes") }
        XCTAssertEqual(notes.iconPath, "/System/Applications/Notes.app")
    }
}

extension HotkeysPaletteTests {
    func testAnAppsPlaceIsItsWindowsTags() {
        func w(_ id: Int, _ tag: Int?) -> HotkeysWindow {
            HotkeysWindow(id: ClientID(id), app: "Code", bundleID: "com.microsoft.VSCode", title: "t\(id)", tag: tag)
        }
        XCTAssertEqual(HotkeysModel.places([w(1, 3), w(2, 1), w(3, 3)])["com.microsoft.VSCode"], "tag 1, 3")
        XCTAssertEqual(HotkeysModel.places([w(1, 0), w(2, nil), w(3, 2)])["com.microsoft.VSCode"], "tag 2 · special · minimized")
        XCTAssertNil(HotkeysModel.places([w(1, 1)])["com.apple.Safari"])
    }

    func testAnAppsKeySaysWhatReturnDoes() {
        let ws = [HotkeysWindow(id: 1, app: "Arc", bundleID: "a", title: "x", tag: 1),
                  HotkeysWindow(id: 2, app: "Arc", bundleID: "a", title: "y", tag: 2)]
        func next(_ rule: LaunchOrFocusRule, _ n: Int, inApp: Bool = false) -> String {
            HotkeysModel.next(HotkeysAppStep(rule: rule, windows: n, inApp: inApp), name: "Arc", windows: ws, viewed: [1])
        }
        XCTAssertEqual(next(.launch, 0), "start Arc")
        XCTAssertEqual(next(.focus(1), 1), "go to Arc", "on the tag in view: no tag named")
        XCTAssertEqual(next(.focus(2), 2), "go to Arc on tag 2")
        XCTAssertEqual(next(.focus(2), 2, inApp: true), "the other Arc window")
    }

    func testTheLegendSaysWhatSuperAndHyperAre() {
        var c = Config()
        XCTAssertEqual(ModifierLegend.text(c), "Super ⌘   Hyper ⌃⌥⌘")
        c.chutneyHyperModifier = "super+ctrl+alt+shift"
        c.xkbRulesOptions = "ctrl:nocaps, caps:hyper"
        XCTAssertEqual(ModifierLegend.text(c), "Super ⌘   Hyper ⌃⌥⇧⌘ or Caps Lock")
    }
}

@MainActor
final class HotkeysTypedArgumentTests: MangoTestCase {
    func model(_ config: String) -> HotkeysModel {
        let parsed = ConfigParser.parse(text: config, baseDirectory: nil, fileName: "t")
        let m = HotkeysModel()
        m.load(ShortcutFormatter.rows(parsed.config), hyper: [.superKey, .ctrl, .alt],
               context: HotkeysContext(hasFocused: true, layout: "scroller"))
        return m
    }

    func selected(_ m: HotkeysModel) -> HotkeyRow? {
        if case .row(let r) = m.items.first { return r } else { return nil }
    }

    func testTheNumberIsTheArgumentNotASearchWord() {
        XCTAssertEqual(HotkeysModel.splitQuery("every col w:60").words, ["every", "col"])
        XCTAssertEqual(HotkeysModel.splitQuery("every col w:60").argument, 60)
        XCTAssertEqual(HotkeysModel.splitQuery("width :0.6").argument, 0.6)
    }

    func testOfferedWithoutAKeyAndRunWithTheTypedShare() throws {
        let m = model("bind=alt,s,spawn,open -a Notes")
        XCTAssertFalse(m.items.contains { if case .group("Layout", 1) = $0 { return true } else { return false } },
                       "not among the groups")
        m.query = "column width w:60"
        let r = try XCTUnwrap(selected(m))
        XCTAssertEqual(r.dispatch, "set_proportion")
        XCTAssertEqual(r.keys, [])
        XCTAssertEqual(m.typedArguments(r), ["0.6"], "over 1: a percentage")
        m.query = "column width :0.5"
        XCTAssertEqual(m.typedArguments(try XCTUnwrap(selected(m))), ["0.5"])
    }

    func testTheShareStaysInMangosRange() throws {
        let m = model("bind=alt,e,set_proportion,1.0")
        for (typed, share) in [("w:2", "0.1"), ("w:10", "0.1"), ("w:250", "1"), ("w:0.05", "0.1"), ("w:45", "0.45")] {
            m.query = "column width \(typed)"
            XCTAssertEqual(m.typedArguments(try XCTUnwrap(selected(m))), [share], typed)
        }
        m.query = "column width w:0"
        XCTAssertNil(m.typedArguments(try XCTUnwrap(selected(m))), "0: the row's own")
    }

    func testARowThatTakesTheNumberComesFirst() throws {
        let m = model("""
        bind=alt,e,set_proportion,1.0
        bind=alt,s,spawn,open -a "System Settings"
        """)
        m.query = "set w:2"
        XCTAssertTrue(HotkeysModel.takesValue(try XCTUnwrap(selected(m))))
        m.query = "set"
        XCTAssertFalse(HotkeysModel.takesValue(try XCTUnwrap(selected(m))), "without a number, the best match")
    }
}
