import XCTest
@testable import Mango
@testable import Port

@MainActor
final class BorderOnRefusedTests: MangoTestCase {
    func check(layout: LayoutKind, min: [CGWindowID: CGSize], animations: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let r = EngineRig()
        r.server.config.animations = animations
        r.server.config.borderpx = 4
        r.server.renderBorder = true
        r.server.drawsOverlays = true
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = layout
        for id: CGWindowID in 1...3 { r.window(id) }
        for (id, size) in min { r.app.minSize[id] = size }
        r.arrange()
        r.settle(2)
        let fake = r.server.system as! FakeWindowSystem
        for (id, _) in min {
            let spec = fake.shownBorderSpecs.first { $0.id == id }
            XCTAssertEqual(spec?.frame, r.app.frames[id], "\(layout) id \(id) anim \(animations): border \(String(describing: spec?.frame)) window \(String(describing: r.app.frames[id])) tile \(String(describing: r.server.clientByIdAll(id)?.geom))", file: file, line: line)
        }
    }

    func testTheBorderIsOnTheWindow() {
        for anim in [false, true] {
            check(layout: .tile, min: [1: CGSize(width: 1100, height: 0)], animations: anim)
            check(layout: .tile, min: [2: CGSize(width: 1000, height: 600)], animations: anim)
            check(layout: .tile, min: [3: CGSize(width: 0, height: 700)], animations: anim)
        }
    }
    /// wlroots shows a window and its border in one frame: a window coming back from parking gets its
    /// border when the app has moved it, not before.
    func testAWindowFromParkingGetsItsBorderWhenItIsBack() {
        let r = EngineRig()
        r.server.renderBorder = true
        r.server.drawsOverlays = true
        let fake = r.server.system as! FakeWindowSystem
        r.window(1)
        let b = r.window(2, tags: 1 << 1)
        r.arrange()
        r.settle()
        XCTAssertTrue(b.parked)
        _ = r.server.dispatch(Dispatch(name: "view", args: ["2"]))
        r.settle()
        _ = r.server.dispatch(Dispatch(name: "view", args: ["1"]))
        r.settle(until: { b.parked })
        XCTAssertTrue(b.parked)
        _ = r.server.dispatch(Dispatch(name: "view", args: ["2"]))
        r.frame()
        XCTAssertFalse(b.parked)
        XCTAssertTrue(b.mac.placed.comingBack, "written, not yet moved")
        XCTAssertEqual(r.app.writes.last { $0.id == 2 }?.setSize, false, "back at its size: the position alone")
        XCTAssertFalse(r.server.mac.shownBorders(fake.borderSpecs).contains { $0.id == 2 }, "no border before the window")
        r.settle(until: { !b.mac.placed.comingBack })
        XCTAssertFalse(b.mac.placed.comingBack)
        XCTAssertTrue(r.server.mac.shownBorders(fake.borderSpecs).contains { $0.id == 2 }, "the border with the window")
    }
    /// wlroots shows a border with its window in one frame: while the app has a frame it has not yet
    /// carried out, the border stays where the app last put the window, and follows when it answers.
    func testTheBorderFollowsTheWindowNotTheLayout() {
        let r = EngineRig()
        r.server.renderBorder = true
        r.server.drawsOverlays = true
        let fake = r.server.system as! FakeWindowSystem
        let a = r.map(1)
        r.arrange()
        r.settle()
        let before = r.app.frames[1]!
        XCTAssertTrue(a.mac.placed.inSync)
        r.app.appliesAfter = 0.3
        r.map(2)
        r.arrange()
        XCTAssertFalse(a.mac.placed.inSync, "a new tile is written")
        XCTAssertNotEqual(a.frame, before)
        XCTAssertEqual(r.server.mac.shownBorders(fake.borderSpecs).first { $0.id == 1 }?.frame, before,
                       "the border stays on the window till the app has moved it")
        r.settle(0.6)
        XCTAssertTrue(a.mac.placed.inSync)
        XCTAssertEqual(r.server.mac.shownBorders(fake.borderSpecs).first { $0.id == 1 }?.frame, r.app.frames[1],
                       "and follows it when it has")
    }
}
