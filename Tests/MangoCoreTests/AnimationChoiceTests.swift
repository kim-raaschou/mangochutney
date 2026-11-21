import XCTest
@testable import Mango
@testable import Port

/// mango's resize and the animation it sets (animation/client.c, animation/tag.c).
@MainActor
final class AnimationChoiceTests: MangoTestCase {
    func rig() -> (EngineRig, Client) {
        let r = EngineRig()
        r.server.config.animations = true
        let c = r.window(1)
        c.tagVisible = true
        c.geom = now
        c.animation.current = now
        c.current = now
        c.pending = now
        return (r, c)
    }
    let target = CGRect(x: 100, y: 100, width: 800, height: 600)
    let now = CGRect(x: 0, y: 40, width: 800, height: 600)

    func testOpen() {
        let (r, c) = rig()
        let m = r.screen.frame
        r.server.preCalculateBeforeArrange(r.monitor, false, false, true)
        c.isPendingOpenAnimation = true
        r.server.resize(c, target, ResizeOpts())
        XCTAssertEqual(c.animation.action, .open)
        XCTAssertEqual(c.animation.duration, UInt32(r.server.config.animationDurationOpen))
        XCTAssertTrue(c.animation.running)
        XCTAssertEqual(c.animation.initial, CGRect(x: 100, y: target.minY + m.height - (target.minY - m.minY), width: 800, height: 600),
                       "one tiled window: from below")
        r.server.clientAnimationNextTick(c)
        XCTAssertFalse(c.isPendingOpenAnimation, "the first frame ends the pending open")
        r.server.resize(c, target.offsetBy(dx: 10, dy: 0), ResizeOpts())
        XCTAssertEqual(c.animation.action, .move)

        c.isPendingOpenAnimation = true
        c.animation.running = false
        c.animationTypeOpen = .zoom
        r.server.config.zoomInitialRatio = 0.5
        r.server.resize(c, target, ResizeOpts())
        XCTAssertEqual(c.animation.initial, CGRect(x: 300, y: 250, width: 400, height: 300))
    }

    func testSlideFromTheNearestEdge() {
        let (r, c) = rig()
        c.isfloating = true
        let m = r.screen.frame
        func from(_ box: CGRect) -> CGRect {
            c.isPendingOpenAnimation = true
            c.animation.running = false
            r.server.resize(c, box, ResizeOpts())
            return c.animation.initial
        }
        XCTAssertEqual(from(CGRect(x: 10, y: 400, width: 300, height: 200)), CGRect(x: m.minX - 300, y: 400, width: 300, height: 200))
        XCTAssertEqual(from(CGRect(x: 700, y: 40, width: 300, height: 200)), CGRect(x: 700, y: m.minY - 200, width: 300, height: 200))
        XCTAssertEqual(from(CGRect(x: 1400, y: 500, width: 300, height: 200)), CGRect(x: m.maxX, y: 500, width: 300, height: 200))
    }

    func testSlideBySpecialRule() {
        let (r, _) = rig()
        let m = r.screen.frame
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .tile
        let d = r.window(2)
        r.server.preCalculateBeforeArrange(r.monitor, false, false, true)
        func from() -> CGRect {
            d.isPendingOpenAnimation = true
            d.animation.running = false
            r.server.resize(d, target, ResizeOpts())
            return d.animation.initial
        }
        r.server.config.newIsMaster = true
        XCTAssertEqual(from().minX, m.minX - target.width, "new master: from the left")
        r.server.config.newIsMaster = false
        XCTAssertEqual(from().minX, m.maxX, "the second window: from the right")
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .scroller
        XCTAssertEqual(from().minY, m.maxY, "scroller: from below")
    }

    func testMove() {
        let (r, c) = rig()
        c.isPendingOpenAnimation = false
        r.server.resize(c, target, ResizeOpts())
        XCTAssertEqual(c.animation.action, .move)
        XCTAssertEqual(c.animation.duration, UInt32(r.server.config.animationDurationMove))
        XCTAssertEqual(c.animation.initial, now)
        XCTAssertEqual(c.current, target)
        XCTAssertTrue(c.animation.running)

        c.animation.running = false
        c.animation.current = target
        r.server.resize(c, target, ResizeOpts())
        XCTAssertFalse(c.animation.running, "where it is: no animation")
    }

    func testTagIn() {
        let (r, c) = rig()
        let m = r.monitor, w = r.screen.frame.width
        c.isPendingOpenAnimation = false
        c.tags = 2
        func from(prev: UInt32, cur: UInt32, want: Bool = true) -> CGRect {
            c.geom = target
            c.animation.current = target
            c.animation.running = false
            c.mac.sceneNodeEnabled = false
            m.pertag.prevtag = prev
            m.pertag.curtag = cur
            r.server.setArrangeVisible(m, c, want)
            return c.animation.initial
        }
        XCTAssertEqual(from(prev: 1, cur: 2), target.offsetBy(dx: w, dy: 0))
        XCTAssertEqual(c.animation.action, .tag)
        XCTAssertEqual(c.animation.duration, UInt32(r.server.config.animationDurationTag))
        XCTAssertEqual(from(prev: 3, cur: 2), target.offsetBy(dx: -w, dy: 0))
        XCTAssertEqual(from(prev: 1, cur: 2, want: false), target)
    }

    func testEnteringOverview() {
        let (r, c) = rig()
        c.isPendingOpenAnimation = false
        r.monitor.isoverview = true
        r.monitor.sel = nil
        c.animation.overining = true
        let card = CGRect(x: 100, y: 100, width: 400, height: 300)
        r.server.resize(c, card, ResizeOpts())
        XCTAssertEqual(c.animation.action, .overview)
        XCTAssertEqual(c.animation.duration, UInt32(r.server.config.animationDurationTag))
        XCTAssertEqual(c.animation.initial, CGRect(x: 60, y: 70, width: 480, height: 360))
        XCTAssertFalse(c.animation.overining)

        c.animation.overining = true
        c.animation.overviewEnterAnimSet = false
        c.animation.running = false
        c.animation.current = now
        c.current = now
        c.pending = now
        r.monitor.sel = c.id
        r.server.resize(c, card, ResizeOpts())
        XCTAssertEqual(c.animation.initial, now, "the selected window moves from where it is")
    }

    func testNoAnimation() {
        let (r, c) = rig()
        c.isPendingOpenAnimation = false
        c.noAnimation = true
        r.server.resize(c, target, ResizeOpts())
        XCTAssertEqual(c.animation.duration, 0)
        XCTAssertFalse(c.animation.running)
        XCTAssertEqual(c.animation.current, target, "at its place at once")

        c.noAnimation = false
        r.server.config.animations = false
        r.server.resize(c, now, ResizeOpts())
        XCTAssertFalse(c.animation.running)
        XCTAssertEqual(c.animation.current, now)
    }

    func testTagOut() {
        let (r, c) = rig()
        let m = r.monitor, sf = r.screen.frame
        c.isPendingOpenAnimation = false
        c.tags = 1
        func to(prev: UInt32, cur: UInt32) -> CGRect {
            c.geom = target
            c.animation.current = target
            c.animation.running = false
            c.animation.tagouting = true
            m.pertag.prevtag = prev
            m.pertag.curtag = cur
            r.server.setTagoutAnimation(m, c)
            return c.current
        }
        XCTAssertEqual(to(prev: 1, cur: 2), CGRect(x: min(sf.minX - 800, target.minX - sf.width), y: target.minY, width: 800, height: 600))
        XCTAssertEqual(c.animation.action, .tag)
        XCTAssertEqual(c.animation.duration, UInt32(r.server.config.animationDurationTag))
        XCTAssertEqual(c.geom, target, "its place stays")
        XCTAssertEqual(to(prev: 1, cur: 0).minX, max(sf.maxX, target.minX + sf.width))
    }

    func testLeavingATagSlidesOut() {
        let (r, c) = rig()
        r.arrange()
        XCTAssertFalse(c.isPendingOpenAnimation)
        _ = r.server.dispatch(Dispatch(name: "view", args: ["2"]))
        XCTAssertTrue(c.animation.tagouting, "sliding out")
        XCTAssertFalse(c.parked, "not hidden yet")
        _ = r.server.dispatch(Dispatch(name: "view", args: ["1"]))
        XCTAssertFalse(c.animation.tagouting, "shown again: no longer on its way out")

        r.server.config.animations = false
        _ = r.server.dispatch(Dispatch(name: "view", args: ["2"]))
        XCTAssertFalse(c.animation.tagouting)
        r.settle()
        XCTAssertTrue(c.parked, "hidden on the next frame")
    }

    func testTheBorderSlidesOutWithItsWindow() {
        let (r, c) = rig()
        r.server.config.borderpx = 2
        r.server.renderBorder = true
        r.server.drawsOverlays = true
        let fake = r.server.system as! FakeWindowSystem
        r.arrange()
        _ = r.server.dispatch(Dispatch(name: "view", args: ["2"]))
        XCTAssertTrue(c.animation.tagouting, "sliding out")
        r.server.updateBorders()
        XCTAssertNotNil(fake.borderSpecs.first { $0.id == c.id }, "client_set_clip draws the border while the scene is enabled")
    }

    func testSpecialAndScratchpadSlideInFromAbove() {
        let (r, c) = rig()
        c.isPendingOpenAnimation = false
        let top = r.screen.frame.minY
        c.geom = target
        c.tags = TAG0_MASK
        r.server.setArrangeVisible(r.monitor, c, true)
        XCTAssertEqual(c.animation.action, .tag)
        XCTAssertEqual(c.animation.initial, CGRect(x: target.minX, y: top - target.height, width: target.width, height: target.height))

        c.tags = 1
        c.isInScratchpad = true
        c.scratchpadTagin = true
        c.animation.running = false
        r.server.setArrangeVisible(r.monitor, c, false)
        XCTAssertEqual(c.animation.initial.minY, top - target.height)
        XCTAssertFalse(c.scratchpadTagin, "once")
    }

    func testAScratchpadPutAwaySlidesOutAtTheTop() {
        let (r, c) = rig()
        r.arrange()
        _ = r.server.dispatch(Dispatch(name: "minimized"), target: c)
        XCTAssertTrue(c.isInScratchpad && c.isminimized)
        XCTAssertTrue(c.animation.tagouting, "sliding out")
        XCTAssertFalse(c.parked)
    }

    func testAnAnimationRunsFrameByFrameToItsPlace() {
        let (r, c) = rig()
        c.isPendingOpenAnimation = false
        var clock: UInt32 = 1000
        nowInMsOverride = { clock }
        defer { nowInMsOverride = nil }
        r.server.resize(c, target, ResizeOpts())
        clock += UInt32(r.server.config.animationDurationMove / 2)
        r.frame()
        XCTAssertTrue(c.animation.running)
        XCTAssertNotEqual(c.animation.current, now)
        XCTAssertNotEqual(c.animation.current, target)
        XCTAssertEqual(r.app.frames[1], c.animation.current, "the window is written where the frame puts it")
        clock += UInt32(r.server.config.animationDurationMove)
        r.frame()
        XCTAssertFalse(c.animation.running)
        XCTAssertEqual(c.animation.current, target)
        XCTAssertEqual(r.app.frames[1], target)
    }
}
