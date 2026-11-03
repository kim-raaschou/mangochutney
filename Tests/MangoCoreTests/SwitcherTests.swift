import XCTest
@testable import Mango
@testable import Port

/// mango's switcher (switcher.c): which windows, in what order, the panel's geometry,
/// and how a choice is made.
@MainActor
final class SwitcherTests: MangoTestCase {
    /// Two windows on tag 1 (900_201 focused last) and one on tag 2.
    func rig() -> EngineRig {
        let r = EngineRig()
        r.window(900_200)
        r.window(900_201)
        r.window(900_202, tags: 2)
        r.server.clientFocus(r.server.clientByIdAll(900_200)!, raise: false)
        r.server.clientFocus(r.server.clientByIdAll(900_201)!, raise: false)
        return r
    }

    func open(_ r: EngineRig, _ arg: String = "next") {
        _ = r.server.dispatch(Dispatch(name: "switcher", args: [arg]))
    }

    var highlighted: (EngineRig) -> ClientID? { { r in r.server.switcherState.map { $0.tiles[$0.index] } } }

    /// mango's numbers for three 800×600 windows on a 1728×1117 monitor, worked by hand:
    /// tile_h 268 (two columns win), pictures 357 wide, one row of 369-wide tiles.
    func testThePanelIsLaidOutAsMangoDoes() {
        let size = CGSize(width: 800, height: 600)
        let l = SwitcherLayout.switcherLayout(sizes: [size, size, size], monitor: CGRect(x: 0, y: 0, width: 1728, height: 1117))
        XCTAssertEqual(l.tileHeight, 268)
        XCTAssertEqual(l.panel, CGRect(x: 268, y: 390, width: 1191, height: 336))
        XCTAssertEqual(l.tiles, [CGRect(x: 296, y: 418, width: 369, height: 280),
                                 CGRect(x: 679, y: 418, width: 369, height: 280),
                                 CGRect(x: 1062, y: 418, width: 369, height: 280)])
    }

    func testTheTitleBarLiesBelowAndIsOffAtHeightZero() {
        let panel = CGRect(x: 10, y: 20, width: 300, height: 100)
        XCTAssertEqual(SwitcherLayout.titleMessageBarGeometry(below: panel, height: 52, gap: 20), CGRect(x: 10, y: 140, width: 300, height: 52))
        XCTAssertNil(SwitcherLayout.titleMessageBarGeometry(below: panel, height: 0, gap: 20))
    }

    /// Focus order, most recent first; next starts on the second window, prev on the last.
    func testNextStartsOnThePreviousWindowAndPrevOnTheLeastRecent() {
        let r = rig()
        open(r)
        XCTAssertEqual(r.server.switcherState?.tiles, [900_201, 900_200], "the current tag only")
        XCTAssertEqual(highlighted(r), 900_200)
        open(r)
        XCTAssertEqual(highlighted(r), 900_201, "wraps")
        r.server.switcherClose()
        open(r, "prev")
        XCTAssertEqual(highlighted(r), 900_200)
    }

    func testTheScopes() {
        let r = rig()
        open(r, "all_tag_next")
        XCTAssertEqual(r.server.switcherState?.tiles, [900_201, 900_200, 900_202], "mango's focus stack: a window joins its head as it maps")
        open(r, "next")
        XCTAssertEqual(r.server.switcherState?.scope, .currentTag, "another scope opens it again")
        XCTAssertEqual(r.server.switcherState?.tiles.count, 2)
        r.server.clientByIdAll(900_200)!.isInScratchpad = true
        r.server.clientByIdAll(900_200)!.isMinimized = true
        r.server.switcherClose()
        open(r, "all_next")
        XCTAssertEqual(r.server.switcherState?.tiles, [900_201, 900_202], "minimized windows are left out")
    }

    func testCommittingAWindowOnAnotherTagViewsItsTag() {
        let r = rig()
        open(r, "all_tag_prev")
        XCTAssertEqual(highlighted(r), 900_202)
        r.server.switcherCommit()
        XCTAssertNil(r.server.switcherState)
        XCTAssertEqual(r.monitor.sel, 900_202)
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 2)
    }

    /// Through the event tap: releasing a modifier chooses, and goes on to the app.
    func testReleasingAModifierChoosesTheHighlightedWindow() {
        let r = rig()
        r.server.mac.router.server = r.server
        open(r)
        let release = KeyEvent(keyCode: 58, mods: [], isDown: false, isRepeat: false, isModifierKey: true)
        XCTAssertFalse(r.server.mac.router.key(release, modifierOnlySinceDown: false))
        r.settle()
        XCTAssertNil(r.server.switcherState)
        XCTAssertEqual(r.monitor.sel, 900_200)
    }

    func testClicks() {
        let r = rig()
        r.server.mac.router.server = r.server
        open(r)
        let outside = MouseButtonEvent(button: 0, mods: [], isDown: true, location: CGPoint(x: 1, y: 1))
        XCTAssertTrue(r.server.mac.router.mouseButton(outside), "the switcher's own")
        r.settle()
        XCTAssertNil(r.server.switcherState, "a click elsewhere closes it")
        XCTAssertEqual(r.monitor.sel, 900_201, "and changes nothing")

        open(r)
        let first = r.server.switcherState!.layout.tiles[0]
        XCTAssertTrue(r.server.mac.router.mouseButton(MouseButtonEvent(button: 0, mods: [], isDown: true,
                                                               location: CGPoint(x: first.midX, y: first.midY))))
        r.settle()
        XCTAssertNil(r.server.switcherState)
        XCTAssertEqual(r.monitor.sel, 900_201, "the clicked tile, not the highlighted one")
    }

    func testAWindowThatGoesLeavesTheSwitcher() {
        let r = rig()
        open(r, "all_tag_next")
        open(r)   // the current tag again
        open(r, "all_tag_next")
        open(r, "all_tag_next")   // highlight on 900_202, the third
        XCTAssertEqual(highlighted(r), 900_202)
        r.server.mac.windowDestroyed(id: 900_200)
        XCTAssertEqual(r.server.switcherState?.tiles, [900_201, 900_202])
        XCTAssertEqual(highlighted(r), 900_202, "the highlight stays on its window")
        XCTAssertEqual(r.server.switcherState?.layout.tiles.count, 2)
        r.server.mac.windowDestroyed(id: 900_201)
        r.server.mac.windowDestroyed(id: 900_202)
        XCTAssertNil(r.server.switcherState, "closed with its last window")
    }

    func testNotInOverview() {
        let r = rig()
        r.server.overviewState = OverviewState(monitor: r.monitor, previousSel: nil, cards: [:])   // drawn by nothing
        open(r)
        XCTAssertNil(r.server.switcherState)
    }
}

/// A window's picture is taken in its own proportions, whatever box it is shown in.
final class SnapshotSizeTests: MangoTestCase {
    func testAWideLowWindowFitsInsideTheBoxInItsProportions() {
        XCTAssertEqual(WindowSnapshot.fitted(CGSize(width: 580, height: 180), in: CGSize(width: 714, height: 298)),
                       CGSize(width: 714, height: 222))
        XCTAssertEqual(WindowSnapshot.fitted(CGSize(width: 400, height: 800), in: CGSize(width: 400, height: 400)),
                       CGSize(width: 200, height: 400))
    }
}

/// mango's title_message_bar_decorate_* and its Pango font descriptions.
final class TitleBarDecorateTests: MangoTestCase {
    func testPangoDescriptions() {
        let d = FontDescription("monospace Bold 13")
        XCTAssertEqual(d.families, ["monospace"])
        XCTAssertEqual(d.weight, .bold)
        XCTAssertEqual(d.pixelSize, 13 * 96 / 72, accuracy: 0.01, "points at 96 dpi, as Pango in mango")
        let e = FontDescription("JetBrains Mono, monospace Semi-Bold Italic 20px")
        XCTAssertEqual(e.families, ["JetBrains Mono", "monospace"])
        XCTAssertEqual(e.weight, .semiBold)
        XCTAssertTrue(e.italic)
        XCTAssertEqual(e.pixelSize, 20)
    }

    func testTheKeysSetTheBar() {
        let parsed = ConfigParser.parse(text: """
            title_message_bar_decorate_font_desc=Sans 11
            title_message_bar_decorate_focus_bg_color=0x112233ff
            title_message_bar_decorate_border_width=150
            """, baseDirectory: FileManager.default.temporaryDirectory, fileName: "test.conf")
        XCTAssertEqual(parsed.config.titleMessageBardata.fontDesc, "Sans 11")
        XCTAssertEqual(parsed.config.titleMessageBardata.focusBgColor, parseColor("0x112233ff"))
        XCTAssertEqual(parsed.config.titleMessageBardata.borderWidth, 100, "mango clamps to 0-100")
        XCTAssertNil(Config().titleMessageBardata.cornerRadius, "unset: the macOS style")
    }

    /// Each picture fills its tile in its own proportions, a much smaller window less;
    /// never stretched.
    @MainActor
    func testEachPictureFillsItsTileInItsProportions() {
        let big = SwitcherPanel.Tile(id: 1, frame: CGRect(x: 0, y: 0, width: 412, height: 280),
                                     size: CGSize(width: 1600, height: 1068), pid: 0, highlighted: false)
        let wide = SwitcherPanel.Tile(id: 2, frame: CGRect(x: 426, y: 0, width: 412, height: 280),
                                      size: CGSize(width: 580, height: 180), pid: 0, highlighted: false)
        let f = SwitcherPanel.pictureFrames([big, wide])
        XCTAssertEqual(f[1]!.width, 400, accuracy: 1, "the largest fills its tile inside the pad")
        XCTAssertEqual(f[2]!.width, 240, accuracy: 1, "a far smaller one 60 % of that")
        XCTAssertEqual(f[2]!.width / f[2]!.height, 580.0 / 180, accuracy: 0.05, "in its own proportions")
        XCTAssertEqual(f[2]!.midY, wide.frame.midY, accuracy: 1, "centred")
        XCTAssertEqual(SwitcherPanel.smallScale(area: 50, largest: 100), 0.84, accuracy: 0.01)
    }
}
