import XCTest
@testable import Mango
@testable import Port

@MainActor
final class TagToCurrentTagTests: MangoTestCase {
    func testTaggingOntoTheTagInViewPlacesTheWindow() {
        let r = EngineRig()
        let c = r.window(900_950, tags: TAG0_MASK)
        r.window(900_951)
        r.arrange()
        r.settle()
        XCTAssertTrue(c.parked, "on the special tag, out of view")
        _ = r.server.dispatch(Dispatch(name: "tag", args: ["1"]), target: c)
        r.frame()
        XCTAssertFalse(c.parked)
        XCTAssertEqual(r.app.frames[900_950], c.tile, "in its tile")
    }
}
