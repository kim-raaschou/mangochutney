import XCTest
@testable import Mango
@testable import Port

/// mango's resize (animation/client.c), its animation part, in the core (clientAnimation):
/// the action, duration, curve and start the port draws.
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

    /// A new window: OPEN, the open duration; slide starts below the screen, zoom at
    /// zoom_initial_ratio around the centre. Only the first resize is OPEN.
    func testOpen() {
        let (r, c) = rig()
        c.isNew = true
        let a = r.server.clientAnimation(c, to: target, .move, current: now, shown: true)
        XCTAssertEqual(a.action, .open)
        XCTAssertEqual(a.durationMs, r.server.config.animationDurationOpen)
        XCTAssertEqual(a.from, target.offsetBy(dx: 0, dy: r.screen.frame.maxY - target.minY))
        XCTAssertEqual(r.server.clientAnimation(c, to: target, .move, current: now, shown: true).action, .move)
        c.isNew = true
        c.animationTypeOpen = .zoom
        r.server.config.zoomInitialRatio = 0.5
        XCTAssertEqual(r.server.clientAnimation(c, to: target, .move, current: now, shown: true).from,
                       CGRect(x: 300, y: 250, width: 400, height: 300))
    }

    /// set_client_open_animation, slide: a floating window from the work area's edge nearest
    /// its centre, just outside the monitor.
    func testSlideFromTheNearestEdge() {
        let (r, c) = rig()
        c.isNew = true
        c.isFloating = true
        let m = r.screen.frame
        let nearLeft = CGRect(x: 10, y: 400, width: 300, height: 200)
        XCTAssertEqual(r.server.clientAnimation(c, to: nearLeft, .move, current: now, shown: true).from,
                       CGRect(x: m.minX - 300, y: 400, width: 300, height: 200))
        c.isNew = true
        let nearTop = CGRect(x: 700, y: 40, width: 300, height: 200)
        XCTAssertEqual(r.server.clientAnimation(c, to: nearTop, .move, current: now, shown: true).from,
                       CGRect(x: 700, y: m.minY - 200, width: 300, height: 200))
        c.isNew = true
        let nearRight = CGRect(x: 1400, y: 500, width: 300, height: 200)
        XCTAssertEqual(r.server.clientAnimation(c, to: nearRight, .move, current: now, shown: true).from,
                       CGRect(x: m.maxX, y: 500, width: 300, height: 200))
    }

    /// is_special_animation_rule: the scroller and a single tiled window from below; tile's
    /// new master (new_is_master) from the left, a second window without it from the right.
    func testSlideBySpecialRule() {
        let (r, c) = rig()
        let m = r.screen.frame
        r.monitor.current.layout = .tile
        let d = r.window(2)
        d.isNew = true
        r.server.config.newIsMaster = true
        XCTAssertEqual(r.server.clientAnimation(d, to: target, .move, current: now, shown: true).from.minX,
                       m.minX - target.width, "new master: from the left")
        d.isNew = true
        r.server.config.newIsMaster = false
        XCTAssertEqual(r.server.clientAnimation(d, to: target, .move, current: now, shown: true).from.minX,
                       m.maxX, "the second window: from the right")
        d.isNew = true
        r.monitor.current.layout = .scroller
        XCTAssertEqual(r.server.clientAnimation(d, to: target, .move, current: now, shown: true).from.minY,
                       m.maxY, "scroller: from below")
        _ = c
    }

    /// A move: MOVE, from where it is, the move duration and curve.
    func testMove() {
        let (r, c) = rig()
        c.isNew = false
        let a = r.server.clientAnimation(c, to: target, .move, current: now, shown: true)
        XCTAssertEqual(a, ClientAnimation(action: .move, from: now, durationMs: r.server.config.animationDurationMove,
                                          curve: r.server.config.animationCurveMove))
    }

    /// set_tagin_animation: a window coming into view on a tag switch starts a monitor's
    /// width away on the side it comes from; one that was hidden otherwise appears in place.
    func testTagIn() {
        let (r, c) = rig()
        c.isNew = false
        let w = r.screen.frame.width
        let fwd = r.server.clientAnimation(c, to: target, .tag(forward: true), current: now, shown: false)
        XCTAssertEqual(fwd.action, .tag)
        XCTAssertEqual(fwd.durationMs, r.server.config.animationDurationTag)
        XCTAssertEqual(fwd.from, target.offsetBy(dx: w, dy: 0))
        XCTAssertEqual(r.server.clientAnimation(c, to: target, .tag(forward: false), current: now, shown: false).from,
                       target.offsetBy(dx: -w, dy: 0))
        XCTAssertEqual(r.server.clientAnimation(c, to: target, .move, current: now, shown: false).from, target)
    }

    /// Entering overview (overining): OVERVIEW with the TAG duration and curve; a card that is
    /// not the selected window zooms in from 1.2 times its size (set_overview_enter_animation),
    /// the selected one moves from where it is. Only the first move; then MOVE again.
    func testEnteringOverview() {
        let (r, c) = rig()
        c.isNew = false
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

    /// No animation: animations off, no_animation, a grabbed window, or an arrange without.
    func testNoAnimation() {
        let (r, c) = rig()
        c.isNew = false
        XCTAssertEqual(r.server.clientAnimation(c, to: target, .none, current: now, shown: true).from, target)
        c.noAnimation = true
        XCTAssertEqual(r.server.clientAnimation(c, to: target, .move, current: now, shown: true).durationMs, 0)
        c.noAnimation = false
        r.server.config.animations = false
        XCTAssertEqual(r.server.clientAnimation(c, to: target, .move, current: now, shown: true).durationMs, 0)
    }

    /// set_tagout_animation: forward, out past the monitor's left edge; back, past its
    /// right; the TAG duration.
    func testTagOut() {
        let (r, c) = rig()
        c.isNew = false
        c.geom = target
        c.frame = target
        let m = r.screen.frame
        let fwd = r.server.setTagoutAnimation(c, on: r.monitor, forward: true)
        XCTAssertEqual(fwd.to, CGRect(x: min(m.minX - 800, target.minX - m.width), y: target.minY, width: 800, height: 600))
        XCTAssertEqual(fwd.durationMs, r.server.config.animationDurationTag)
        XCTAssertEqual(r.server.setTagoutAnimation(c, on: r.monitor, forward: false).to.minX, max(m.maxX, target.minX + m.width))
    }

    /// set_arrange_hidden: on a tag switch a window of the tag left slides out and is hidden
    /// at the end (tagouting); with animations off it is hidden at once.
    func testLeavingATagSlidesOut() {
        let (r, c) = rig()
        r.server.arrange(r.monitor, .none)
        XCTAssertFalse(c.isNew)
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

    /// set_arrange_visible: the special tag's windows slide in from just above the monitor on
    /// an animated switch; a scratchpad brought here (scratchpad_tagin) too.
    func testSpecialAndScratchpadSlideInFromAbove() {
        let (r, c) = rig()
        c.isNew = false
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

    /// set_arrange_hidden: a scratchpad put away slides up and out before it is hidden.
    func testAScratchpadPutAwaySlidesOutAtTheTop() {
        let (r, c) = rig()
        r.server.arrange(r.monitor, .none)
        _ = r.server.dispatch(Dispatch(name: "minimized"), target: c)
        XCTAssertTrue(c.isInScratchpad && c.isMinimized)
        XCTAssertTrue(c.tagouting, "sliding out")
        XCTAssertFalse(c.parked)
    }
}
