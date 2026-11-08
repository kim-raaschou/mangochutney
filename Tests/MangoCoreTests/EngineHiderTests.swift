import XCTest
import CoreGraphics
@testable import Mango
@testable import Port

final class EngineHiderTests: MangoTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let work = CGRect(x: 0, y: 25, width: 1920, height: 985)

    func testParkedOriginLeavesOnePixelVisible() {
        let size = CGSize(width: 800, height: 600)
        let br = Hider.parkedOrigin(size: size, workArea: work, corner: .bottomRight)
        XCTAssertEqual(br, CGPoint(x: work.maxX - 1, y: work.maxY - 1))
        let bl = Hider.parkedOrigin(size: size, workArea: work, corner: .bottomLeft)
        XCTAssertEqual(bl, CGPoint(x: work.minX + 1 - size.width, y: work.maxY - 1))
        for p in [br, bl] {
            let f = CGRect(origin: p, size: size)
            let visible = f.intersection(work)
            XCTAssertEqual(visible.width, 1); XCTAssertEqual(visible.height, 1)
            XCTAssertTrue(Hider.isParked(f, in: screen))
        }
    }

    func testTiledFrameIsNotParked() {
        XCTAssertFalse(Hider.isParked(CGRect(x: 10, y: 35, width: 900, height: 900), in: screen))
        XCTAssertFalse(Hider.isParked(CGRect(x: 1900, y: 35, width: 900, height: 900), in: screen), "20px visible is a real window")
    }

    func testCornerAvoidsNeighbouringDisplay() {
        let right = CGRect(x: 1920, y: 200, width: 1920, height: 1080)
        XCTAssertEqual(Hider.corner(for: screen, others: [right]), .bottomLeft)
        let left = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        XCTAssertEqual(Hider.corner(for: screen, others: [left]), .bottomRight)
        XCTAssertEqual(Hider.corner(for: screen, others: []), .bottomRight)
    }

    @MainActor
    func testFrozenWindowCountsAsAwayOnlyWhenParked() {
        let parked = CGRect(origin: Hider.parkedOrigin(size: CGSize(width: 800, height: 80), workArea: work,
                                                       corner: .bottomRight), size: CGSize(width: 800, height: 80))
        XCTAssertTrue(MacWindowSystem.isStuckAway(realFrame: parked, screen: screen))
        XCTAssertTrue(MacWindowSystem.isStuckAway(realFrame: CGRect(x: 3000, y: 0, width: 800, height: 600), screen: screen))
        XCTAssertFalse(MacWindowSystem.isStuckAway(realFrame: CGRect(x: 916, y: 198, width: 800, height: 139), screen: screen))
        XCTAssertFalse(MacWindowSystem.isStuckAway(realFrame: nil, screen: screen), "unknown frame: keep it")
    }
}

final class EngineParkAgainTests: MangoTestCase {
    @MainActor
    func testParkedWindowsMoveToTheirDisplaysCornerAsItIsNow() {
        let rig = EngineRig()
        let benqAlone = Screen(displayID: 2, name: "BenQ", frame: CGRect(x: 0, y: 0, width: 2560, height: 1707),
                               workArea: CGRect(x: 0, y: 30, width: 2560, height: 1677), scale: 2, isMain: true)
        rig.server.rebuildMonitors(screens: [benqAlone])
        rig.window(1, tags: 1)
        let hidden = rig.window(2, tags: 2)
        rig.server.arrangeAll(.none)
        rig.settle()
        XCTAssertTrue(hidden.parked)
        XCTAssertEqual(rig.app.frames[2]?.origin, CGPoint(x: 2559, y: 1706))

        let laptop = Screen(displayID: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                            workArea: CGRect(x: 0, y: 37, width: 1728, height: 1080), scale: 2, isMain: true)
        let benq = Screen(displayID: 2, name: "BenQ", frame: CGRect(x: 1728, y: 0, width: 3360, height: 2240),
                          workArea: CGRect(x: 1728, y: 30, width: 3360, height: 2210), scale: 2, isMain: false)
        rig.server.rebuildMonitors(screens: [laptop, benq])
        rig.server.arrangeAll(.none)
        rig.server.mac.parkAgainAfterScreensChanged()
        rig.settle()
        XCTAssertTrue(hidden.parked)
        XCTAssertEqual(rig.app.frames[2]?.origin, CGPoint(x: 5087, y: 2239))
        XCTAssertTrue(Hider.isParked(rig.app.frames[2]!, in: benq.frame))
    }
}
