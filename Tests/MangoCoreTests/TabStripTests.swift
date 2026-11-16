import XCTest
import AppKit
@testable import Mango
@testable import Port

@MainActor
final class TabStripTests: MangoTestCase {
    func rig(_ kind: LayoutKind, windows: Int) -> EngineRig {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = kind
        for i in 0..<windows { r.window(CGWindowID(900_100 + i)) }
        return r
    }

    func testMonocleWindowsMakeRoomForTheStrip() {
        let r = rig(.monocle, windows: 3)
        r.server.config.monocleTabMode = false
        r.arrange()
        let plain = r.server.clientByIdAll(900_100)!.geom
        r.server.config.monocleTabMode = true
        r.arrange()
        let tabbed = r.server.clientByIdAll(900_100)!.geom
        XCTAssertEqual(r.server.tabChain(r.monitor).count, 3)
        XCTAssertEqual(tabbed.minY, plain.minY + 33)
        XCTAssertEqual(tabbed.height, plain.height - 33)
    }

    func testMembersOtherThanTheFocusedOneAreHidden() {
        let r = rig(.monocle, windows: 3)
        r.server.clientFocus(r.server.clientByIdAll(900_101)!, false)
        r.arrange()
        r.settle()
        let parked = { (id: CGWindowID) in r.server.clientByIdAll(id)!.parked }
        XCTAssertEqual([parked(900_100), parked(900_101), parked(900_102)], [true, false, true])
        XCTAssertTrue(Hider.isParked(r.app.frames[900_100]!, in: r.screen.frame))

        r.server.config.animations = true
        let writes = r.app.writes.count
        r.server.tabFocusMember(r.server.clientByIdAll(900_102)!)
        r.settle()
        XCTAssertEqual([parked(900_100), parked(900_101), parked(900_102)], [true, true, false])
        let after = r.app.writes.dropFirst(writes)
        let shown = after.firstIndex { $0.id == 900_102 }, hidden = after.firstIndex { $0.id == 900_101 }
        XCTAssertNotNil(shown)
        XCTAssertLessThan(shown ?? .max, hidden ?? .max, "the new member is written before the old one is parked: no wallpaper between")
        XCTAssertEqual(r.app.frames[900_102], r.server.clientByIdAll(900_102)!.geom, "shown where the layout has it")
    }

    func testWithoutTabModeNoMonocleWindowIsHidden() {
        let r = rig(.monocle, windows: 3)
        r.server.config.monocleTabMode = false
        r.arrange()
        XCTAssertFalse(r.server.clientsAll.contains { $0.parked })
    }

    func testTheDeckHidesItsStackButTheFocusedMember() {
        let r = rig(.deck, windows: 4)
        r.server.clientFocus(r.server.clientByIdAll(900_102)!, false)
        r.arrange()
        r.settle()
        let parked = (0..<4).map { r.server.clientByIdAll(CGWindowID(900_100 + $0))!.parked }
        XCTAssertEqual(parked, [false, true, false, true])
        r.server.clientFocus(r.server.clientByIdAll(900_100)!, false)
        XCTAssertFalse(r.server.clientByIdAll(900_102)!.parked, "the master focused: the stack keeps its last focused member")
    }

    func testOneWindowHasNoStrip() {
        let r = rig(.monocle, windows: 1)
        XCTAssertTrue(r.server.tabChain(r.monitor).isEmpty)
    }

    func testTheDeckTabsItsStackNotItsMaster() {
        let r = rig(.deck, windows: 3)
        r.arrange()
        let ids = r.server.tabChain(r.monitor).map(\.id)
        XCTAssertEqual(ids, [900_101, 900_102], "the master (first) is not a member")
    }

    func testTheSelectedMemberIsFocusedElseTheOneShownLast() {
        let r = rig(.monocle, windows: 3)
        r.arrange()
        r.monitor.sel = 900_102
        r.server.tabSyncMonitor(r.monitor)
        XCTAssertEqual(r.server.tabFocus(r.monitor)?.id, 900_102)
        r.monitor.sel = nil
        r.server.tabSyncMonitor(r.monitor)
        XCTAssertEqual(r.server.tabFocus(r.monitor)?.id, 900_102)
        for c in r.server.tabChain(r.monitor) { c.isTabFocus = false }
        r.server.tabSyncMonitor(r.monitor)
        XCTAssertEqual(r.server.tabFocus(r.monitor)?.id, 900_100, "none shown yet: the first")
    }

    func cmd(_ code: UInt16, modifier: Bool = false, down: Bool = true) -> KeyEvent {
        KeyEvent(keyCode: code, mods: down ? .superKey : [], isDown: down, isRepeat: false, isModifierKey: modifier)
    }

    func testTheStripSitsOnTheFocusedMemberOnly() {
        let r = rig(.monocle, windows: 3)
        let fake = r.server.system as! FakeWindowSystem
        r.server.drawsOverlays = true
        r.arrange()
        r.monitor.sel = 900_101
        r.server.tabSyncMonitor(r.monitor)
        r.server.drawBars()
        XCTAssertEqual(fake.tabStrips.first?.segments.first(where: \.focused)?.id, 900_101)
        r.server.clientByIdAll(900_101)!.isfullscreen = true
        r.server.drawBars()
        XCTAssertTrue(fake.tabStrips.isEmpty, "no strip over a fullscreen window")
        r.server.clientByIdAll(900_101)!.isfullscreen = false
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .tile
        r.server.drawBars()
        XCTAssertTrue(fake.tabStrips.isEmpty)
    }

    func drawn(_ r: EngineRig, animating: [ClientID: CGRect] = [:]) -> FakeWindowSystem {
        let fake = r.server.system as! FakeWindowSystem
        r.server.drawsOverlays = true
        for (id, f) in animating {
            let c = r.server.clientByIdAll(id)!
            let bw = r.server.borderWidth(c, on: r.monitor)
            c.animation.running = true
            c.animation.current = f.insetBy(dx: -bw, dy: -bw)
        }
        r.server.drawBars()
        return fake
    }

    func focus(_ r: EngineRig) -> Client {
        r.server.tabFocus(r.monitor)!
    }

    func testTheTabBarsAreMangosBoxesSideBySide() {
        let r = rig(.monocle, windows: 3)
        r.arrange()
        let s = drawn(r).tabStrips[0]
        let tw = Int(s.frame.width)
        XCTAssertEqual(s.segments.map { Int($0.frame.width) }, (0..<3).map { tw / 3 + ($0 < tw % 3 ? 1 : 0) })
        XCTAssertEqual(s.segments[0].frame.minX, s.frame.minX)
        XCTAssertEqual(s.segments[1].frame.minX, s.segments[0].frame.maxX)
        XCTAssertEqual(s.segments[2].frame.maxX, s.frame.maxX)
        XCTAssertTrue(s.segments.allSatisfy { $0.frame.minY == s.frame.minY && $0.frame.height == 33 })
    }

    func testTheTabBarIsClippedAtTheMonitorEdge() {
        let r = rig(.monocle, windows: 2)
        r.arrange()
        let f = focus(r)
        var shown = f.tile
        shown.origin.x = r.screen.frame.maxX - 100
        let s = drawn(r, animating: [f.id: shown]).tabStrips[0]
        let bw = r.server.borderWidth(f, on: r.monitor)
        XCTAssertEqual(s.frame.minX, shown.minX - bw)
        XCTAssertEqual(s.frame.maxX, r.screen.frame.maxX, "compute_edge_offsets: the right overhang is cut")
        XCTAssertEqual(s.segments.last!.frame.maxX, r.screen.frame.maxX)
    }

    func testDuringTheOpenAnimationTheTabBarSitsWhereTheWindowGoes() {
        let r = rig(.monocle, windows: 2)
        r.arrange()
        let f = focus(r)
        let bw = r.server.borderWidth(f, on: r.monitor)
        let shown = f.tile.insetBy(dx: 100, dy: 100)
        f.animation.action = .open
        XCTAssertEqual(drawn(r, animating: [f.id: shown]).tabStrips[0].frame.minX, f.geom.minX, "c->geom while opening")
        f.animation.action = .move
        XCTAssertEqual(drawn(r, animating: [f.id: shown]).tabStrips[0].frame.minX, shown.minX - bw, "c->animation.current")
    }

    func testAGroupBarOverATabHiddenOwnerIsNotDrawn() {
        let r = rig(.monocle, windows: 3)
        let a = r.server.clientByIdAll(900_100)!, b = r.server.clientByIdAll(900_101)!
        r.server.clientGroupJoin(b, a)
        let owner = [a, b].first { !$0.groupParked }!
        r.server.clientFocus(owner, false)
        r.arrange()
        XCTAssertEqual(drawn(r).groupStrips.map(\.above), [owner.id])
        r.server.clientFocus(r.server.clientByIdAll(900_102)!, false)
        r.arrange()
        XCTAssertTrue(owner.isTabHidden)
        XCTAssertTrue(drawn(r).groupStrips.isEmpty)
    }

    func testAGroupBarIsFocusedOnlyWhileItsWindowIsTheSelection() {
        let r = rig(.tile, windows: 3)
        let a = r.server.clientByIdAll(900_100)!, b = r.server.clientByIdAll(900_101)!
        r.server.clientGroupJoin(b, a)
        let owner = [a, b].first { !$0.groupParked }!
        r.server.clientFocus(owner, false)
        XCTAssertEqual(drawn(r).groupStrips[0].segments.filter(\.focused).map(\.id), [owner.id])
        r.server.clientFocus(r.server.clientByIdAll(900_102)!, false)
        XCTAssertEqual(drawn(r).groupStrips[0].segments.filter(\.focused), [],
                       "client_check_tab_node_visible: focused is cur == selected_monitor->sel")
    }

    func testSegmentsShareTheWidthLikeMango() {
        let f = TabStripLayout.segmentFrames(width: 100, count: 3)
        XCTAssertEqual(f.map(\.width), [34, 33, 33])
        XCTAssertEqual(f.map(\.minX), [0, 34, 67])
    }
}

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

    func testMangosLookDrawsEachBarInItsBox() {
        let v = TabStripView(frame: CGRect(x: 0, y: 0, width: 400, height: 33))
        var s = strip(width: 400)
        s.frame = CGRect(x: 50, y: 10, width: 400, height: 33)
        s.plain = true
        s.segments[0].frame = CGRect(x: 50, y: 10, width: 200, height: 33)
        s.segments[1].frame = CGRect(x: 250, y: 10, width: 200, height: 33)
        v.show(s, style: TabStripStyle(accent: RGBA(r: 1, g: 0, b: 0, a: 1)))
        XCTAssertEqual(v.layer!.sublayers![0].frame, CGRect(x: 0, y: 0, width: 200, height: 33))
        XCTAssertEqual(v.layer!.sublayers![1].frame, CGRect(x: 200, y: 0, width: 200, height: 33))
    }

    func testTheSelectedTabIsRingedOnlyWhileItsWindowHasTheFocus() {
        let v = TabStripView(frame: CGRect(x: 0, y: 0, width: 400, height: 40))
        let style = TabStripStyle(accent: RGBA(r: 1, g: 0, b: 0, a: 1), accentWidth: 2)
        v.keyFocus = 0
        v.show(strip(width: 400), style: style)
        XCTAssertEqual(v.layer!.sublayers![0].borderWidth, 2, "its window has the focus")
        v.keyFocus = 99
        v.show(strip(width: 400), style: style)
        XCTAssertEqual(v.layer!.sublayers![0].borderWidth, 0)
        XCTAssertNotNil(v.layer!.sublayers![0].backgroundColor, "still the selected one")
        var mango = style
        mango.decorate.borderColor = RGBA(r: 0, g: 0, b: 1, a: 1)
        v.show(strip(width: 400), style: mango)
        XCTAssertEqual(v.layer!.sublayers![0].borderWidth, 2, "mango's decorate keys as set")
    }
}
