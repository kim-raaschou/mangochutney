import XCTest
@testable import Mango
@testable import Port

@MainActor
final class AnimationChoiceTests: MangoTestCase {
    func rig() -> (EngineRig, Client) {
        let r = EngineRig()
        r.server.config.animations = true
        let c = r.window(1)
        return (r, c)
    }
    let target = CGRect(x: 100, y: 100, width: 800, height: 600)
    let now = CGRect(x: 0, y: 0, width: 800, height: 600)

    func testOpen() {
        let (r, c) = rig()
        c.isPendingOpenAnimation = true
        let a = r.server.clientAnimation(c, to: target, .move, current: now, shown: true)
        XCTAssertEqual(a.action, .open)
        XCTAssertEqual(a.durationMs, r.server.config.animationDurationOpen)
        XCTAssertEqual(a.from, target.offsetBy(dx: 0, dy: r.screen.frame.maxY - target.minY))
        XCTAssertEqual(r.server.clientAnimation(c, to: target, .move, current: now, shown: true).action, .move)
        c.isPendingOpenAnimation = true
        c.animationTypeOpen = .zoom
        r.server.config.zoomInitialRatio = 0.5
        XCTAssertEqual(r.server.clientAnimation(c, to: target, .move, current: now, shown: true).from,
                       CGRect(x: 300, y: 250, width: 400, height: 300))
    }

    func testSlideFromTheNearestEdge() {
        let (r, c) = rig()
        c.isPendingOpenAnimation = true
        c.isFloating = true
        let m = r.screen.frame
        let nearLeft = CGRect(x: 10, y: 400, width: 300, height: 200)
        XCTAssertEqual(r.server.clientAnimation(c, to: nearLeft, .move, current: now, shown: true).from,
                       CGRect(x: m.minX - 300, y: 400, width: 300, height: 200))
        c.isPendingOpenAnimation = true
        let nearTop = CGRect(x: 700, y: 40, width: 300, height: 200)
        XCTAssertEqual(r.server.clientAnimation(c, to: nearTop, .move, current: now, shown: true).from,
                       CGRect(x: 700, y: m.minY - 200, width: 300, height: 200))
        c.isPendingOpenAnimation = true
        let nearRight = CGRect(x: 1400, y: 500, width: 300, height: 200)
        XCTAssertEqual(r.server.clientAnimation(c, to: nearRight, .move, current: now, shown: true).from,
                       CGRect(x: m.maxX, y: 500, width: 300, height: 200))
    }

    func testSlideBySpecialRule() {
        let (r, c) = rig()
        let m = r.screen.frame
        r.monitor.current.layout = .tile
        let d = r.window(2)
        d.isPendingOpenAnimation = true
        r.server.config.newIsMaster = true
        XCTAssertEqual(r.server.clientAnimation(d, to: target, .move, current: now, shown: true).from.minX,
                       m.minX - target.width, "new master: from the left")
        d.isPendingOpenAnimation = true
        r.server.config.newIsMaster = false
        XCTAssertEqual(r.server.clientAnimation(d, to: target, .move, current: now, shown: true).from.minX,
                       m.maxX, "the second window: from the right")
        d.isPendingOpenAnimation = true
        r.monitor.current.layout = .scroller
        XCTAssertEqual(r.server.clientAnimation(d, to: target, .move, current: now, shown: true).from.minY,
                       m.maxY, "scroller: from below")
        _ = c
    }

    func testMove() {
        let (r, c) = rig()
        c.isPendingOpenAnimation = false
        let a = r.server.clientAnimation(c, to: target, .move, current: now, shown: true)
        XCTAssertEqual(a, ClientAnimation(action: .move, from: now, durationMs: r.server.config.animationDurationMove,
                                          curve: r.server.config.animationCurveMove))
    }

    func testTagIn() {
        let (r, c) = rig()
        c.isPendingOpenAnimation = false
        let w = r.screen.frame.width
        let fwd = r.server.clientAnimation(c, to: target, .tag(forward: true), current: now, shown: false)
        XCTAssertEqual(fwd.action, .tag)
        XCTAssertEqual(fwd.durationMs, r.server.config.animationDurationTag)
        XCTAssertEqual(fwd.from, target.offsetBy(dx: w, dy: 0))
        XCTAssertEqual(r.server.clientAnimation(c, to: target, .tag(forward: false), current: now, shown: false).from,
                       target.offsetBy(dx: -w, dy: 0))
        XCTAssertEqual(r.server.clientAnimation(c, to: target, .move, current: now, shown: false).from, target)
    }

    func testEnteringOverview() {
        let (r, c) = rig()
        c.isPendingOpenAnimation = false
        r.monitor.sel = nil
        c.overining = true
        let card = CGRect(x: 100, y: 100, width: 400, height: 300)
        let a = r.server.clientAnimation(c, to: card, .move, current: now, shown: true)
        XCTAssertEqual(a.action, .overview)
        XCTAssertEqual(a.durationMs, r.server.config.animationDurationTag)
        XCTAssertEqual(a.from, CGRect(x: 60, y: 70, width: 480, height: 360))
        XCTAssertFalse(c.overining)
        XCTAssertEqual(r.server.clientAnimation(c, to: card, .move, current: now, shown: true).action, .move)
        c.overining = true
        r.monitor.sel = c.id
        XCTAssertEqual(r.server.clientAnimation(c, to: card, .move, current: now, shown: true).from, now,
                       "the selected window moves from where it is")
    }

    func testNoAnimation() {
        let (r, c) = rig()
        c.isPendingOpenAnimation = false
        XCTAssertEqual(r.server.clientAnimation(c, to: target, .none, current: now, shown: true).from, target)
        c.noAnimation = true
        XCTAssertEqual(r.server.clientAnimation(c, to: target, .move, current: now, shown: true).durationMs, 0)
        c.noAnimation = false
        r.server.config.animations = false
        XCTAssertEqual(r.server.clientAnimation(c, to: target, .move, current: now, shown: true).durationMs, 0)
    }

    func testTagOut() {
        let (r, c) = rig()
        c.isPendingOpenAnimation = false
        c.geom = target
        c.frame = target
        let m = r.screen.frame
        let fwd = r.server.setTagoutAnimation(c, on: r.monitor, forward: true)
        XCTAssertEqual(fwd.to, CGRect(x: min(m.minX - 800, target.minX - m.width), y: target.minY, width: 800, height: 600))
        XCTAssertEqual(fwd.durationMs, r.server.config.animationDurationTag)
        XCTAssertEqual(r.server.setTagoutAnimation(c, on: r.monitor, forward: false).to.minX, max(m.maxX, target.minX + m.width))
    }

    func testLeavingATagSlidesOut() {
        let (r, c) = rig()
        r.server.arrange(r.monitor, .none)
        XCTAssertFalse(c.isPendingOpenAnimation)
        _ = r.server.dispatch(Dispatch(name: "view", args: ["2"]))
        XCTAssertTrue(c.tagouting, "sliding out")
        XCTAssertFalse(c.parked, "not hidden yet")
        _ = r.server.dispatch(Dispatch(name: "view", args: ["1"]))
        XCTAssertFalse(c.tagouting, "shown again: no longer on its way out")

        r.server.config.animations = false
        _ = r.server.dispatch(Dispatch(name: "view", args: ["2"]))
        XCTAssertFalse(c.tagouting)
        XCTAssertTrue(c.parked, "hidden at once")
    }

    func testSpecialAndScratchpadSlideInFromAbove() {
        let (r, c) = rig()
        c.isPendingOpenAnimation = false
        let top = r.screen.frame.minY
        c.tags = TagMask.special
        let a = r.server.clientAnimation(c, to: target, .tag(forward: true), current: now, shown: false)
        XCTAssertEqual(a.action, .tag)
        XCTAssertEqual(a.from, CGRect(x: target.minX, y: top - target.height, width: target.width, height: target.height))
        c.tags = 1
        c.isInScratchpad = true
        c.scratchpadTagin = true
        let s = r.server.clientAnimation(c, to: target, .move, current: now, shown: false)
        XCTAssertEqual(s.from.minY, top - target.height)
        XCTAssertFalse(c.scratchpadTagin, "once")
    }

    func testAScratchpadPutAwaySlidesOutAtTheTop() {
        let (r, c) = rig()
        r.server.arrange(r.monitor, .none)
        _ = r.server.dispatch(Dispatch(name: "minimized"), target: c)
        XCTAssertTrue(c.isInScratchpad && c.isMinimized)
        XCTAssertTrue(c.tagouting, "sliding out")
        XCTAssertFalse(c.parked)
    }
}
