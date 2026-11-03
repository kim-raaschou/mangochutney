import XCTest
import AppKit
@testable import Mango
@testable import Port

/// mango's tab mode: members, the room above them, the segments.
@MainActor
final class TabStripTests: MangoTestCase {
    func rig(_ kind: LayoutKind, windows: Int) -> EngineRig {
        let r = EngineRig()
        r.monitor.current.layout = kind
        for i in 0..<windows { r.window(CGWindowID(900_100 + i)) }
        return r
    }

    func testMonocleWindowsMakeRoomForTheStrip() {
        let r = rig(.monocle, windows: 3)
        r.server.config.monocleTabMode = false
        r.server.arrange(r.monitor, .none)
        let plain = r.server.clientByIdAll(900_100)!.geom!
        r.server.config.monocleTabMode = true
        r.server.arrange(r.monitor, .none)
        let tabbed = r.server.clientByIdAll(900_100)!.geom!
        XCTAssertEqual(r.server.tabMembers(r.monitor).count, 3)
        XCTAssertEqual(tabbed.minY, plain.minY + 33)
        XCTAssertEqual(tabbed.height, plain.height - 33)
    }

    /// mango's is_tab_hidden: a member that is not the strip's focus is hidden (parked
    /// here, as a window on a hidden tag), not left behind the shown one.
    func testMembersOtherThanTheFocusedOneAreHidden() {
        let r = rig(.monocle, windows: 3)
        r.server.clientFocus(r.server.clientByIdAll(900_101)!, raise: false)
        r.server.arrange(r.monitor, .none)
        let parked = { (id: CGWindowID) in r.server.clientByIdAll(id)!.parked }
        XCTAssertEqual([parked(900_100), parked(900_101), parked(900_102)], [true, false, true])
        XCTAssertTrue(Hider.isParked(r.app.frames[900_100]!, in: r.screen.frame))

        r.server.tabFocusMember(900_102)
        XCTAssertEqual([parked(900_100), parked(900_101), parked(900_102)], [true, true, false])
        XCTAssertEqual(r.app.frames[900_102], r.server.clientByIdAll(900_102)!.geom, "shown where the layout has it")
    }

    /// Without tab mode mango hides none of them: they lie behind the focused one.
    func testWithoutTabModeNoMonocleWindowIsHidden() {
        let r = rig(.monocle, windows: 3)
        r.server.config.monocleTabMode = false
        r.server.arrange(r.monitor, .none)
        XCTAssertFalse(r.server.clientsAll.contains { $0.parked })
    }

    /// The deck: the master stays, and of the stack only the focused member is shown.
    func testTheDeckHidesItsStackButTheFocusedMember() {
        let r = rig(.deck, windows: 4)
        r.server.clientFocus(r.server.clientByIdAll(900_102)!, raise: false)
        r.server.arrange(r.monitor, .none)
        let parked = (0..<4).map { r.server.clientByIdAll(CGWindowID(900_100 + $0))!.parked }
        XCTAssertEqual(parked, [false, true, false, true])
        r.server.clientFocus(r.server.clientByIdAll(900_100)!, raise: false)
        XCTAssertFalse(r.server.clientByIdAll(900_102)!.parked, "the master focused: the stack keeps its last focused member")
    }

    func testOneWindowHasNoStrip() {
        let r = rig(.monocle, windows: 1)
        XCTAssertTrue(r.server.tabMembers(r.monitor).isEmpty)
    }

    func testTheDeckTabsItsStackNotItsMaster() {
        let r = rig(.deck, windows: 3)
        r.server.arrange(r.monitor, .none)   // mango: ismaster is reset_size_per_mon's, set by arrange
        let ids = r.server.tabMembers(r.monitor).map(\.id)
        XCTAssertEqual(ids, [900_101, 900_102], "the master (first) is not a member")
    }

    /// mango tab_chain_focus: the selected member, else the one the chain showed last
    /// (is_tab_focus), else the first.
    func testTheSelectedMemberIsFocusedElseTheOneShownLast() {
        let r = rig(.monocle, windows: 3)
        let members = r.server.tabMembers(r.monitor)
        r.monitor.sel = 900_102
        XCTAssertEqual(r.server.tabChainFocus(members, on: r.monitor)?.id, 900_102)
        r.monitor.sel = nil
        XCTAssertEqual(r.server.tabChainFocus(members, on: r.monitor)?.id, 900_102)
        for c in members { c.isTabFocus = false }
        XCTAssertEqual(r.server.tabChainFocus(members, on: r.monitor)?.id, 900_100, "none shown yet: the first")
    }

    func testCmdDigitsPickTheFocusedMonitorsTabs() {
        let r = rig(.monocle, windows: 3)
        XCTAssertEqual(r.server.tabBarShortcutTabs, 0, "off unless chutney_tab_bar_shortcuts")
        r.server.config.chutneyTabBarShortcuts = true
        XCTAssertEqual(r.server.tabBarShortcutTabs, 3)
        r.server.tabFocusMember(number: 2)
        XCTAssertEqual(r.monitor.sel, 900_101)
        r.server.tabFocusMember(number: 4)
        XCTAssertEqual(r.monitor.sel, 900_101, "no fourth tab")
        r.monitor.current.layout = .tile
        XCTAssertEqual(r.server.tabBarShortcutTabs, 0, "no tab bar")
    }

    func cmd(_ code: UInt16, modifier: Bool = false, down: Bool = true) -> KeyEvent {
        KeyEvent(keyCode: code, mods: down ? .superKey : [], isDown: down, isRepeat: false, isModifierKey: modifier)
    }

    func testHeldCmdShowsTheNumbersAndAnyOtherKeyHidesThem() {
        let r = rig(.monocle, windows: 3)
        r.server.config.chutneyTabBarShortcuts = true
        r.server.mac.router.server = r.server
        r.server.publishInputState()
        _ = r.server.mac.router.key(cmd(55, modifier: true), modifierOnlySinceDown: true)   // ⌘ down
        r.settle()
        XCTAssertTrue(r.server.mac.tabNumbersShown)
        _ = r.server.mac.router.key(cmd(8), modifierOnlySinceDown: false)                   // ⌘C
        r.settle()
        XCTAssertFalse(r.server.mac.tabNumbersShown)
    }

    func testTheEventTapLearnsWhenATabGoes() {
        let r = rig(.monocle, windows: 3)
        r.server.config.chutneyTabBarShortcuts = true
        r.server.publishInputState()
        XCTAssertTrue(r.server.mac.router.key(cmd(20), modifierOnlySinceDown: false))       // ⌘3
        r.server.mac.windowDestroyed(id: 900_102)
        XCTAssertFalse(r.server.mac.router.key(cmd(20), modifierOnlySinceDown: false), "two tabs left: ⌘3 is the app's")
    }

    func testNoShortcutsUnderAFullscreenWindow() {
        let r = rig(.monocle, windows: 3)
        r.server.config.chutneyTabBarShortcuts = true
        r.monitor.sel = 900_100
        r.server.clientByIdAll(900_100)!.isFullscreen = true
        XCTAssertEqual(r.server.tabBarShortcutTabs, 0)
        r.server.tabFocusMember(number: 2)
        XCTAssertEqual(r.monitor.sel, 900_100)
    }

    func testAUserBindOnCmdDigitWins() {
        let r = rig(.monocle, windows: 3)
        r.server.config.chutneyTabBarShortcuts = true
        r.server.publishInputState()
        r.server.mac.router.publish { $0.bindings = [KeyBinding(mods: .superKey, keyName: "2", keyCodes: [19],
                                                        dispatch: Dispatch(name: "view", args: ["2"]))] }
        r.server.mac.router.server = nil   // the bind's dispatch is not under test
        XCTAssertTrue(r.server.mac.router.key(cmd(19), modifierOnlySinceDown: false))
    }

    func testTheStripSitsOnTheFocusedMemberOnly() {
        let r = rig(.monocle, windows: 3)
        let fake = r.server.system as! FakeWindowSystem
        r.server.drawsOverlays = true
        r.monitor.sel = 900_101
        r.server.tabRefreshBars()
        XCTAssertEqual(fake.tabStrips.first?.segments.first(where: \.focused)?.id, 900_101)
        r.server.clientByIdAll(900_101)!.isFullscreen = true
        r.server.tabRefreshBars()
        XCTAssertTrue(fake.tabStrips.isEmpty, "no strip over a fullscreen window")
        r.server.clientByIdAll(900_101)!.isFullscreen = false
        r.monitor.current.layout = .tile
        r.server.tabRefreshBars()
        XCTAssertTrue(fake.tabStrips.isEmpty)
    }

    func testSegmentsShareTheWidthLikeMango() {
        let f = TabStripLayout.segmentFrames(width: 100, count: 3)
        XCTAssertEqual(f.map(\.width), [34, 33, 33])
        XCTAssertEqual(f.map(\.minX), [0, 34, 67])
    }
}

/// A strip that only changes size (every frame of an animation) keeps its tab layers.
@MainActor
final class TabStripViewTests: MangoTestCase {
    func strip(width: CGFloat, titles: [String] = ["a", "b"]) -> TabStrip {
        TabStrip(frame: CGRect(x: 0, y: 0, width: width, height: 40), barHeight: 33, cornerRadius: 10,
                 segments: titles.enumerated().map { .init(id: CGWindowID($0.offset), title: $0.element, focused: $0.offset == 0) },
                 above: 0)
    }

    func testANewWidthLaysOutTheSameLayers() {
        let v = TabStripView(frame: CGRect(x: 0, y: 0, width: 400, height: 40))
        let style = TabStripStyle(accent: RGBA(r: 1, g: 0, b: 0, a: 1))
        v.show(strip(width: 400), style: style)
        let layers = v.layer?.sublayers ?? []
        XCTAssertEqual(layers.count, 2)
        v.show(strip(width: 600), style: style)
        XCTAssertTrue(zip(layers, v.layer?.sublayers ?? []).allSatisfy { $0 === $1 }, "kept, not rebuilt")
        XCTAssertEqual(layers[1].frame.maxX, 597)
        v.show(strip(width: 600, titles: ["a", "c"]), style: style)
        XCTAssertFalse(layers[0] === v.layer?.sublayers?[0], "new titles: rebuilt")
    }

    func testHeldCmdShowsTheNumbersAtTheTrailingEdge() {
        let v = TabStripView(frame: CGRect(x: 0, y: 0, width: 400, height: 40))
        var s = strip(width: 400)
        s.segments[1].shortcut = 2
        v.show(s, style: TabStripStyle(accent: RGBA(r: 1, g: 0, b: 0, a: 1)))
        let tab = v.layer!.sublayers![1]
        let number = tab.sublayers!.first { $0.sublayers?.contains { ($0 as? CATextLayer)?.string as? String == "⌘2" } == true }
        XCTAssertNotNil(number)
        XCTAssertEqual(number!.frame.maxX, tab.frame.width - 6)
        let title = tab.sublayers!.compactMap { $0 as? CATextLayer }.first { ($0.string as? String) == "b" }!
        XCTAssertLessThanOrEqual(title.frame.maxX, number!.frame.minX)
        XCTAssertEqual(title.frame.midX, tab.frame.width / 2, accuracy: 0.5, "still centred")
    }

    func testATabTooNarrowForItsNumberHidesIt() {
        let v = TabStripView(frame: CGRect(x: 0, y: 0, width: 60, height: 40))
        var s = strip(width: 60)
        s.segments[1].shortcut = 2
        v.show(s, style: TabStripStyle(accent: RGBA(r: 1, g: 0, b: 0, a: 1)))
        let number = v.layer!.sublayers![1].sublayers!.first {
            $0.sublayers?.contains { ($0 as? CATextLayer)?.string as? String == "⌘2" } == true
        }
        XCTAssertEqual(number?.isHidden, true)
    }
}
