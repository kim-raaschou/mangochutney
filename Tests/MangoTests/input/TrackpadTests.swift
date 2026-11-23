import XCTest
@testable import Mango
import MangoTestKit

/// mango's src/input/trackpad.c
@MainActor
final class TrackpadTests: XCTestCase {

    // MARK: fire_gesture_motion

    func testAGestureFiresEveryMatch() {
        let mango = TestMango("""
            gesturebind=none,left,3,setlayout,monocle
            gesturebind=none,alldir,3,togglegaps
            gesturebind=none,left,3,moveresize,curmove
            """)
        XCTAssertEqual(mango.server.config.gestureBindings.count, 3)
        let gaps = mango.server.enableGaps

        XCTAssertTrue(mango.server.fireGestureMotion(SWIPE_LEFT, 3))

        XCTAssertEqual(mango.monitor.layout, .monocle)
        XCTAssertNotEqual(mango.server.enableGaps, gaps, "alldir fired too")
    }
}
