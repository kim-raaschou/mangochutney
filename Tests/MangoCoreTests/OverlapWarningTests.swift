import XCTest
@testable import Mango
@testable import Port

@MainActor
final class OverlapWarningTests: MangoTestCase {
    func rig(on: Bool = true) -> EngineRig {
        let r = EngineRig()
        r.server.config.chutneyOverlapWarning = on
        for id: CGWindowID in 1...3 { r.window(id) }
        r.app.minSize[1] = CGSize(width: 1100, height: 0)
        r.server.arrange(r.monitor, .none)
        r.settle(1.5)
        return r
    }

    func testAWindowOverItsNeighbourMarksItsTag() {
        let r = rig()
        let tile = r.server.clientByIdAll(1)!.geom!
        XCTAssertTrue(r.app.frames[1]!.intersects(r.app.frames[2]!), "over its neighbour, as mango's layout leaves it")
        XCTAssertEqual(MenuBarStatus.monitors(r.server)[0].tags.first?.overlap, true)
        let tag = try! XCTUnwrap(MenuBarStatus.overlapLines(r.server).first)
        XCTAssertEqual(tag.heading, "Overlap on Tag 1")
        XCTAssertEqual(tag.windows.first?.app, "Test")
        XCTAssertEqual(tag.windows.first?.by, "\(1100 - Int(tile.width)) pt larger in width")
        XCTAssertEqual(tag.suggestions.map(\.action), [.moveToTag(1, 2), .float(1)])
        XCTAssertEqual(tag.suggestions.map(\.title), ["Move Test to tag 2", "Float Test"])
    }

    func testMovingItAwayClearsTheMark() {
        let r = rig()
        MenuBarStatus.apply(r.server, MenuBarStatus.overlapLines(r.server)[0].suggestions[0])
        r.settle(1)
        XCTAssertEqual(r.server.clientByIdAll(1)!.tags, 1 << 1)
        XCTAssertEqual(MenuBarStatus.monitors(r.server)[0].tags.first?.overlap, false)
        XCTAssertTrue(MenuBarStatus.overlapLines(r.server).isEmpty, "nor on tag 2, not in view")
    }

    func testFloatingItClearsTheMark() {
        let r = rig()
        MenuBarStatus.apply(r.server, MenuBarStatus.overlapLines(r.server)[0].suggestions[1])
        r.settle(1)
        XCTAssertTrue(r.server.clientByIdAll(1)!.isFloating)
        XCTAssertTrue(MenuBarStatus.overlapLines(r.server).isEmpty)
    }

    func testTheMenuBarIsToldWhenAWindowGoesOver() {
        let r = EngineRig()
        r.server.config.chutneyOverlapWarning = true
        var told = 0
        r.server.onStateChange = { told += 1 }
        for id: CGWindowID in 1...2 { r.window(id) }
        r.app.minSize[1] = CGSize(width: 1100, height: 0)
        r.server.arrange(r.monitor, .none)
        told = 0
        r.settle(1.5)
        XCTAssertGreaterThan(told, 0)
    }

    func testInMonocleOnlyTheWindowShownCounts() {
        let r = EngineRig()
        r.server.config.chutneyOverlapWarning = true
        r.server.config.monocleTabMode = false
        r.monitor.current.layout = .monocle
        for id: CGWindowID in 1...3 { r.window(id) }
        r.app.minSize[3] = CGSize(width: 2000, height: 0)
        r.monitor.sel = 1
        r.server.arrange(r.monitor, .none)
        r.settle(1.5)
        XCTAssertNotNil(r.server.clientByIdAll(3)!.refusedSize, "larger than the screen")
        XCTAssertTrue(MenuBarStatus.overlapLines(r.server).isEmpty, "under the one shown")
        r.monitor.sel = 3
        XCTAssertEqual(MenuBarStatus.overlapLines(r.server).first?.windows.count, 1, "shown now")
    }

    func testAWindowMovedAwayNoLongerCountsAtOnce() {
        let r = rig()
        r.server.config.animations = true
        _ = r.server.dispatch(Dispatch(name: "tagsilent", args: ["2"]), target: r.server.clientByIdAll(1)!)
        XCTAssertTrue(MenuBarStatus.overlapLines(r.server).isEmpty)
        XCTAssertEqual(MenuBarStatus.monitors(r.server)[0].tags.map(\.overlap), [false, false])
    }

    func testWithoutTheKeyNothingIsMarked() {
        let r = rig(on: false)
        XCTAssertNotNil(r.server.clientByIdAll(1)!.refusedSize)
        XCTAssertEqual(MenuBarStatus.monitors(r.server)[0].tags.first?.overlap, false)
        XCTAssertTrue(MenuBarStatus.overlapLines(r.server).isEmpty)
    }
}
