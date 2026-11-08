import XCTest
@testable import Mango
@testable import Port

final class EngineFollowupTests: MangoTestCase {
    func testClampMatchesMangoOverrideConfig() {
        var c = Config()
        c.overcircleCenterRatio = 0.99
        c.hotareaSize = 0
        c.gestureSwipeDistance = 5
        c.gestureSwipeCancelRatio = 1
        c.scratchpadWidthRatio = 3
        c.specialGappoh = -4
        c.gestureSwipeMinSpeedToForce = -1
        c.overrideConfig()
        XCTAssertEqual(c.overcircleCenterRatio, 0.9)
        XCTAssertEqual(c.hotareaSize, 1)
        XCTAssertEqual(c.gestureSwipeDistance, 32)
        XCTAssertEqual(c.gestureSwipeCancelRatio, 0.95)
        XCTAssertEqual(c.scratchpadWidthRatio, 1)
        XCTAssertEqual(c.specialGappoh, 0)
        XCTAssertEqual(c.gestureSwipeMinSpeedToForce, 0)
    }

    @MainActor
    func testDispatcherNumbersMustBeFinite() {
        let server = MangoServer(configURL: URL(fileURLWithPath: "/nonexistent/mango.conf"))
        server.system = FakeWindowSystem(server)
        XCTAssertNil(server.finiteDouble("nan"))
        XCTAssertNil(server.finiteDouble("inf"))
        XCTAssertNil(server.finiteDouble("-infinity"))
        XCTAssertEqual(server.finiteDouble(" 0.05 "), 0.05)
        XCTAssertEqual(server.relOrAbs("nan", 120), 120)
        XCTAssertEqual(server.relOrAbs("+30", 120), 150)
        XCTAssertEqual(server.relOrAbs("40", 120), 40)
    }
}
