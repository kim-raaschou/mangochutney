import XCTest
@testable import Mango
@testable import Port

final class EngineDepartedTests: MangoTestCase {
    func departed(tags: UInt32 = 1 << 2, at: CFTimeInterval) -> DepartedWindow {
        DepartedWindow(tags: tags, displayID: 1, isFloating: true, isGlobal: false, isOverlay: false,
                       isMinimized: false, isScratchpad: false, isNamedScratchpad: false,
                       floatFrame: CGRect(x: 10, y: 20, width: 300, height: 200),
                       scrollerProportion: nil, orderSnapshot: [7, 8, 9], at: at)
    }

    func testAWindowThatComesBackGetsItsStateOnce() {
        var store = DepartedWindows()
        store.remember(9980, departed(at: 100))
        let back = store.take(9980, now: 100 + 1140)
        XCTAssertEqual(back?.tags, 1 << 2)
        XCTAssertEqual(back?.orderSnapshot, [7, 8, 9])
        XCTAssertNil(store.take(9980, now: 1300), "taken once")
    }

    func testForgottenAfterAnHour() {
        var store = DepartedWindows()
        store.remember(1, departed(at: 0))
        XCTAssertNil(store.take(1, now: DepartedWindows.keepFor + 1))
        store.remember(2, departed(at: 0))
        store.remember(3, departed(at: DepartedWindows.keepFor + 5))
        XCTAssertNil(store.entries[2])
        XCTAssertNotNil(store.entries[3])
    }

    func testUnknownWindowIsNew() {
        var store = DepartedWindows()
        store.remember(1, departed(at: 0))
        XCTAssertNil(store.take(2, now: 1))
    }

    func testOrderComesBackAsItWasWhateverOrderWindowsLeaveAndReturn() {
        let claude: CGWindowID = 44, ghostty: CGWindowID = 123, arc: CGWindowID = 68
        let mail: CGWindowID = 231, messages: CGWindowID = 149
        var order: [CGWindowID] = [claude, ghostty, arc, mail, messages]
        var store = DepartedWindows()
        var snapshots: [CGWindowID: [CGWindowID]] = [:]
        for leaving in [arc, messages, claude, mail, ghostty] {
            snapshots[leaving] = store.orderSnapshot(leaving: leaving, order: order)
            order.removeAll { $0 == leaving }
        }
        for returning in [claude, mail, arc, messages, ghostty] {
            let i = DepartedWindow.insertionIndex(of: returning, snapshot: snapshots[returning]!, into: order)
            order.insert(returning, at: i)
        }
        XCTAssertEqual(order, [claude, ghostty, arc, mail, messages])
    }

    func testInsertionUsesNearestNeighbourPresent() {
        typealias D = DepartedWindow
        XCTAssertEqual(D.insertionIndex(of: 2, snapshot: [1, 2, 3], into: [1, 3]), 1, "after its predecessor")
        XCTAssertEqual(D.insertionIndex(of: 1, snapshot: [1, 2, 3], into: [3, 2]), 1, "before its nearest successor (2)")
        XCTAssertEqual(D.insertionIndex(of: 3, snapshot: [1, 2, 3], into: [9]), 1, "no neighbour: at the end")
        XCTAssertEqual(D.insertionIndex(of: 5, snapshot: [1, 2], into: [1, 2]), 2, "not in its snapshot: at the end")
    }

    func testANewWaveStartsWhenAWindowAppears() {
        var store = DepartedWindows()
        XCTAssertEqual(store.orderSnapshot(leaving: 1, order: [1, 2, 3]), [1, 2, 3])
        XCTAssertEqual(store.orderSnapshot(leaving: 2, order: [2, 3]), [1, 2, 3], "same wave")
        store.endWave()
        XCTAssertEqual(store.orderSnapshot(leaving: 3, order: [3, 4]), [3, 4], "after a window appeared: a new wave")
        XCTAssertEqual(store.orderSnapshot(leaving: 5, order: [5, 6]), [5, 6], "not in the wave's order: a new wave")
    }
}
