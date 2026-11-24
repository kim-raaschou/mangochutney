import XCTest
@testable import Mango
import MangoTestKit

/// mango's src/layout/arrange.c
@MainActor
final class ArrangeTests: XCTestCase {

    // MARK: arrange

    func testArrangeFillsTheSelection() {
        let mango = TestMango()
        let a = mango.map("a")
        mango.monitor.sel = nil

        mango.server.arrange(mango.monitor, false, false)

        XCTAssertEqual(mango.monitor.sel?.windowID, a.windowID)
    }

    // MARK: resize_tile_client

    func testAGridResizeIsKeptOnTheClients() {
        let mango = grid(of: 4)
        let first = mango.server.clients[0], second = mango.server.clients[1]
        let before = first.geom.width

        mango.server.resizeTileClient(first, false, 200, 0)

        XCTAssertGreaterThan(first.gridColPer, 1)
        XCTAssertLessThan(second.gridColPer, 1)
        XCTAssertGreaterThan(first.geom.width, before + 100)
        mango.server.arrange(mango.monitor, false, false)
        XCTAssertGreaterThan(first.geom.width, before + 100, "kept on the clients")
    }

    /// Keyboard repeats and pointer motion are coalesced to once per output frame.
    func testATiledResizeIsTakenOncePerFrame() {
        let mango = TestMango()
        let a = mango.map("a")
        mango.map("b")
        nextFrame(mango)
        let before = a.geom.width

        mango.server.resizeTileClient(a, false, 50, 0)
        let once = a.geom.width
        mango.server.resizeTileClient(a, false, 50, 0)

        XCTAssertNotEqual(once, before)
        XCTAssertEqual(a.geom.width, once, "the same frame: dropped")
        nextFrame(mango)
        mango.server.resizeTileClient(a, false, 50, 0)
        XCTAssertNotEqual(a.geom.width, once, "the next frame: taken")
    }

    func testAGridDragMovesTheEdgeItGrabs() throws {
        let mango = grid(of: 6)
        let tiled = mango.server.tiledClients(mango.monitor)
        XCTAssertEqual(Set(tiled.map(\.gridColIdx)), [0, 1, 2], "three columns")
        let middle = try XCTUnwrap(tiled.first { $0.gridColIdx == 1 })
        let left = tiled.filter { $0.gridColIdx == 0 }, right = tiled.filter { $0.gridColIdx == 2 }
        let grab = CGPoint(x: middle.geom.minX + 5, y: middle.geom.midY)

        mango.wlroots.pointer = grab
        mango.server.resizeTileClient(middle, true, 0, 0)
        nextFrame(mango)
        mango.wlroots.pointer = CGPoint(x: grab.x - 80, y: grab.y)
        mango.server.resizeTileClient(middle, true, 0, 0)

        XCTAssertGreaterThan(middle.gridColPer, 1, "the middle column grows to the left")
        XCTAssertTrue(left.allSatisfy { $0.gridColPer < 1 }, "the left column gives the room")
        XCTAssertTrue(right.allSatisfy { $0.gridColPer == 1 }, "the right column is not touched")
    }

    private func grid(of n: Int) -> TestMango {
        let mango = TestMango()
        mango.monitor.pertag.ltidxs[getMonCurtag(mango.monitor)] = .grid
        for i in 0..<n { mango.map(String(UnicodeScalar(UInt8(97 + i)))) }
        return mango
    }

    /// The output's next frame.
    private func nextFrame(_ mango: TestMango) {
        mango.wlroots.outputScheduleFrame(mango.monitor)
        mango.frame()
    }
}
