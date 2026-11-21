import XCTest
@testable import Mango
import MangoTestKit

/// mango's src/manage/client.c
@MainActor
final class ClientTests: XCTestCase {

    // MARK: handle_client_map

    func testANewClientGoesLast() {
        let mango = TestMango("new_is_master=0")
        mango.map("a"); mango.map("b")

        mango.map("c")

        XCTAssertEqual(mango.clients, ["a", "b", "c"])
    }

    func testWithNewIsMasterANewClientGoesFirst() {
        let mango = TestMango("new_is_master=1")
        mango.map("a"); mango.map("b")

        mango.map("c")

        XCTAssertEqual(mango.clients, ["c", "b", "a"])
    }

    func testANewClientIsFocused() {
        let mango = TestMango()
        mango.map("a")

        mango.map("b")

        XCTAssertEqual(mango.focused, "b")
        XCTAssertEqual(mango.focusStack, ["b", "a"])
    }

    // MARK: handle_client_unmap

    func testUnmappingTheFocusedClientFocusesTheNextOnTheMonitor() {
        let mango = TestMango()
        mango.map("a"); mango.map("b")

        mango.unmap("b")

        XCTAssertEqual(mango.focused, "a")
        XCTAssertEqual(mango.clients, ["a"])
    }

    func testUnmappingAClientElsewhereFocusesTheTopOfTheSelectedMonitor() {
        let mango = TestMango()
        let main = mango.monitor
        let side = mango.addMonitorOnTheRight()
        mango.map("a")
        let b = mango.map("b")
        mango.server.clientSetMonitor(b, side, 0, focus: false)
        mango.server.setSelectedMonitor(main)
        main.sel = nil

        mango.unmap("b")

        // client_set_monitor(c, NULL, 0, true) ends in client_focus(client_focus_top(selmon))
        XCTAssertEqual(mango.focused, "a")
    }

    // MARK: client_focus_top

    func testTheTopIsTheLastFocusedEvenWithNoFocus() {
        let mango = TestMango()
        mango.map("a")
        mango.map("b").noFocus = true

        XCTAssertEqual(mango.server.clientFocusTop(mango.monitor)?.title, "b")
    }

    func testTheTopSkipsAnUnglobalClient() {
        let mango = TestMango()
        mango.map("a")
        mango.map("b").isunglobal = true

        XCTAssertEqual(mango.server.clientFocusTop(mango.monitor)?.title, "a")
    }
}
