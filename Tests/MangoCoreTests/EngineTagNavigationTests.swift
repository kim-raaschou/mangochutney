import XCTest
@testable import Mango
@testable import Port

/// viewtoleft/right, viewtoleft/right_have_client, tagtoleft/right (mango view_shift_tag,
/// view_shift_tag_have_client, tag_to_left/right), through the engine.
@MainActor
final class EngineTagNavigationTests: MangoTestCase {
    /// A rig viewing `view`, with a window on each tag of `occupied`.
    func rig(view: UInt32 = 1, occupied: [Int] = [], gather: Bool = false, carousel: Bool = false) -> EngineRig {
        let r = EngineRig()
        r.server.config.tagGather = gather
        r.server.config.tagCarousel = carousel
        for (i, t) in occupied.enumerated() { r.window(CGWindowID(900_960 + i), tags: 1 << UInt32(t - 1)) }
        r.monitor.tagset[r.monitor.seltags] = view
        return r
    }
    func view(_ r: EngineRig) -> UInt32 { r.monitor.tagset[r.monitor.seltags] }
    func go(_ r: EngineRig, _ name: String) { _ = r.server.dispatch(Dispatch(name: name, args: [])) }

    func testPlainNeighbours() {
        let r = rig(view: 1)
        go(r, "viewtoright")
        XCTAssertEqual(view(r), 1 << 1)
        go(r, "viewtoleft")
        XCTAssertEqual(view(r), 1)
    }

    func testStopsAtEdgesWithoutCarousel() {
        let r = rig(view: 1 << 8)
        go(r, "viewtoright")
        XCTAssertEqual(view(r), 1 << 8)
        let l = rig(view: 1)
        go(l, "viewtoleft")
        XCTAssertEqual(view(l), 1)
    }

    func testCarouselWraps() {
        let r = rig(view: 1 << 8, carousel: true)
        go(r, "viewtoright")
        XCTAssertEqual(view(r), 1)
        go(r, "viewtoleft")
        XCTAssertEqual(view(r), 1 << 8)
    }

    /// mango view_shift_tag: several tags in view shift as a block.
    func testSeveralTagsShiftTogether() {
        let r = rig(view: 0b11)
        go(r, "viewtoright")
        XCTAssertEqual(view(r), 0b110)
    }

    func testHaveClientSkipsEmptyTags() {
        let r = rig(view: 1, occupied: [1, 4, 7])
        go(r, "viewtoright_have_client")
        XCTAssertEqual(view(r), 1 << 3)
        go(r, "viewtoright_have_client")
        XCTAssertEqual(view(r), 1 << 6)
        go(r, "viewtoright_have_client")
        XCTAssertEqual(view(r), 1 << 6, "none after it")
    }

    func testHaveClientWrapsOnlyWithCarousel() {
        let r = rig(view: 1 << 6, occupied: [1, 4, 7], carousel: true)
        go(r, "viewtoright_have_client")
        XCTAssertEqual(view(r), 1)
        go(r, "viewtoleft_have_client")
        XCTAssertEqual(view(r), 1 << 6)
    }

    /// mango view_shift_tag: tag_gather sets where the carousel wraps; without carousel the
    /// shift goes on past it.
    func testGatherSetsTheCarouselsWrap() {
        let r = rig(view: 1 << 3, occupied: [1, 2, 3], gather: true, carousel: true)
        go(r, "viewtoright")
        XCTAssertEqual(view(r), 1, "wraps after the first empty tag")
        go(r, "viewtoleft")
        XCTAssertEqual(view(r), 1 << 3)
    }

    /// mango view_shift_tag: nothing from the special tag.
    func testNothingFromTheSpecialTag() {
        let r = rig(view: TagMask.special)
        go(r, "viewtoright")
        XCTAssertEqual(view(r), TagMask.special)
    }
}

/// mango's tag to the tag in view: the window comes to its place there.
@MainActor
final class TagToCurrentTagTests: MangoTestCase {
    func testTaggingOntoTheTagInViewPlacesTheWindow() {
        let r = EngineRig()
        let c = r.window(900_950, tags: TagMask.special)
        r.window(900_951)
        r.server.arrange(r.monitor, .none)
        XCTAssertTrue(c.parked, "on the special tag, out of view")
        _ = r.server.dispatch(Dispatch(name: "tag", args: ["1"]), target: c)
        XCTAssertFalse(c.parked)
        XCTAssertEqual(r.app.frames[900_950], c.geom, "in its tile")
    }
}
