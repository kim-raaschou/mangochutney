import XCTest
@testable import Mango
@testable import Port

@MainActor
final class SwitcherTests: MangoTestCase {
    func rig() -> EngineRig {
        let r = EngineRig()
        r.window(900_200)
        r.window(900_201)
        r.window(900_202, tags: 2)
        r.server.clientFocus(r.server.clientByIdAll(900_200)!, false)
        r.server.clientFocus(r.server.clientByIdAll(900_201)!, false)
        return r
    }

    func open(_ r: EngineRig, _ arg: String = "next") {
        _ = r.server.dispatch(Dispatch(name: "switcher", args: [arg]))
    }

    var highlighted: (EngineRig) -> ClientID? {
        { r in r.server.switcherIsActive() ? r.server.switcherState.tiles[Int(r.server.switcherState.index)].c.id : nil }
    }
    func tiles(_ r: EngineRig) -> [ClientID]? {
        r.server.switcherIsActive() ? r.server.switcherState.tiles.map { $0.c.id } : nil
    }
    func panel(_ r: EngineRig) -> CGRect {
        let st = r.server.switcherState
        return CGRect(x: Int(st.panelX), y: Int(st.panelY), width: Int(st.panelW), height: Int(st.panelH))
    }
    func tileFrames(_ r: EngineRig) -> [CGRect] {
        let st = r.server.switcherState
        return st.tiles.map { CGRect(x: Int(st.panelX + $0.x), y: Int(st.panelY + $0.y),
                                     width: Int($0.cw + 2 * SW_PAD), height: Int(st.tileH + 2 * SW_PAD)) }
    }

    func testThePanelIsLaidOutAsMangoDoes() {
        let r = EngineRig()
        let screen = Screen(displayID: 1, name: "S", frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                            workArea: CGRect(x: 0, y: 0, width: 1728, height: 1117), scale: 1, isMain: true)
        r.server.rebuildMonitors(screens: [screen])
        for id: CGWindowID in [900_200, 900_201, 900_202] {
            r.window(id, floating: true, frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        }
        open(r)
        XCTAssertEqual(r.server.switcherState.tileH, 268)
        XCTAssertEqual(panel(r), CGRect(x: 268, y: 390, width: 1191, height: 336))
        XCTAssertEqual(tileFrames(r), [CGRect(x: 296, y: 418, width: 369, height: 280),
                                       CGRect(x: 679, y: 418, width: 369, height: 280),
                                       CGRect(x: 1062, y: 418, width: 369, height: 280)])
    }

    func testNextStartsOnThePreviousWindowAndPrevOnTheLeastRecent() {
        let r = rig()
        open(r)
        XCTAssertEqual(tiles(r), [900_201, 900_200], "the current tag only")
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
        XCTAssertEqual(tiles(r), [900_201, 900_200, 900_202], "mango's focus stack: a window joins its head as it maps")
        open(r, "next")
        XCTAssertEqual(r.server.switcherState.scope, SW_CURRENT_TAG, "another scope opens it again")
        XCTAssertEqual(tiles(r)?.count, 2)
        r.server.clientByIdAll(900_200)!.isInScratchpad = true
        r.server.clientByIdAll(900_200)!.isminimized = true
        r.server.switcherClose()
        open(r, "all_next")
        XCTAssertEqual(tiles(r), [900_201, 900_202], "minimized windows are left out")
    }

    func testCommittingAWindowOnAnotherTagViewsItsTag() {
        let r = rig()
        open(r, "all_tag_prev")
        XCTAssertEqual(highlighted(r), 900_202)
        r.server.switcherCommit()
        XCTAssertFalse(r.server.switcherIsActive())
        XCTAssertEqual(r.monitor.sel, 900_202)
        XCTAssertEqual(r.monitor.tagset[r.monitor.seltags], 2)
    }

    func testReleasingAModifierChoosesTheHighlightedWindow() {
        let r = rig()
        r.server.mac.router.server = r.server
        open(r)
        let release = KeyEvent(keyCode: 58, mods: [], isDown: false, isRepeat: false, isModifierKey: true)
        XCTAssertFalse(r.server.mac.router.key(release, modifierOnlySinceDown: false))
        r.settle()
        XCTAssertFalse(r.server.switcherIsActive())
        XCTAssertEqual(r.monitor.sel, 900_200)
    }

    func testClicks() {
        let r = rig()
        r.server.mac.router.server = r.server
        open(r)
        let outside = MouseButtonEvent(button: 0, mods: [], isDown: true, location: CGPoint(x: 1, y: 1))
        XCTAssertTrue(r.server.mac.router.mouseButton(outside), "the switcher's own")
        r.settle()
        XCTAssertFalse(r.server.switcherIsActive(), "a click elsewhere closes it")
        XCTAssertEqual(r.monitor.sel, 900_201, "and changes nothing")

        open(r)
        let first = tileFrames(r)[0]
        XCTAssertTrue(r.server.mac.router.mouseButton(MouseButtonEvent(button: 0, mods: [], isDown: true,
                                                               location: CGPoint(x: first.midX, y: first.midY))))
        r.settle()
        XCTAssertFalse(r.server.switcherIsActive())
        XCTAssertEqual(r.monitor.sel, 900_201, "the clicked tile, not the highlighted one")
    }

    func testAWindowThatGoesLeavesTheSwitcher() {
        let r = rig()
        open(r, "all_tag_next")
        open(r)
        open(r, "all_tag_next")
        open(r, "all_tag_next")
        XCTAssertEqual(highlighted(r), 900_202)
        let tileH = r.server.switcherState.tileH
        r.server.mac.windowDestroyed(id: 900_200)
        XCTAssertEqual(tiles(r), [900_201, 900_202])
        XCTAssertEqual(highlighted(r), 900_202, "the highlight stays on its window")
        XCTAssertEqual(r.server.switcherState.tileH, tileH, "switcher_layout keeps switcher_open's tile height")
        r.server.mac.windowDestroyed(id: 900_201)
        r.server.mac.windowDestroyed(id: 900_202)
        XCTAssertFalse(r.server.switcherIsActive(), "closed with its last window")
    }

    func testNotInOverview() {
        let r = rig()
        r.monitor.isoverview = true
        open(r)
        XCTAssertFalse(r.server.switcherIsActive())
    }
}

final class SnapshotSizeTests: MangoTestCase {
    func testAWideLowWindowFitsInsideTheBoxInItsProportions() {
        XCTAssertEqual(WindowSnapshot.fitted(CGSize(width: 580, height: 180), in: CGSize(width: 714, height: 298)),
                       CGSize(width: 714, height: 222))
        XCTAssertEqual(WindowSnapshot.fitted(CGSize(width: 400, height: 800), in: CGSize(width: 400, height: 400)),
                       CGSize(width: 200, height: 400))
    }
}

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
