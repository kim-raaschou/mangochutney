import XCTest
@testable import Mango
@testable import Port

@MainActor
final class BorderResizeTests: MangoTestCase {
    func sideBySide() -> (EngineRig, Client, Client) {
        let r = EngineRig()
        r.server.renderBorder = true
        let a = r.window(1, frame: CGRect(x: 100, y: 100, width: 400, height: 600))
        let b = r.window(2, frame: CGRect(x: 510, y: 100, width: 400, height: 600))
        bordered(r, a)
        bordered(r, b)
        return (r, a, b)
    }

    func floating() -> (EngineRig, Client) {
        let r = EngineRig()
        r.server.renderBorder = true
        let c = r.window(1, floating: true, frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        bordered(r, c)
        return (r, c)
    }

    /// mango's geom and bw as resize leaves them: the box with the border.
    func bordered(_ r: EngineRig, _ c: Client) {
        c.bw = CGFloat(r.server.config.borderpx)
        c.geom = c.frame.insetBy(dx: -c.bw, dy: -c.bw)
        c.floatGeom = c.isfloating ? c.geom : c.floatGeom
        c.animation.current = c.geom
        c.current = c.geom
        c.pending = c.geom
    }

    func fake(_ r: EngineRig) -> FakeWindowSystem { r.server.system as! FakeWindowSystem }
    /// The pointer moved, as wlroots' cursor is before mango hears of it, and the frame that shows it.
    func motion(_ r: EngineRig, _ p: CGPoint, time: UInt32) {
        r.nextFrame()
        r.server.cursorMotion(to: p, time: time)
        r.frame()
    }

    func testATiledWindowHasAStripOnlyWhereItFacesATiledNeighbour() {
        let (r, a, _) = sideBySide()
        let s = r.server
        XCTAssertEqual(s.clientResizeEdgeAt(a, nil, 502, 400), .right, "on the border")
        XCTAssertEqual(s.clientResizeEdgeAt(a, a.id, 496, 400), .right, "inside the window")
        XCTAssertEqual(s.clientResizeEdgeAt(a, a.id, 400, 400), [], "away from the edge")
        XCTAssertEqual(s.clientResizeEdgeAt(a, a.id, 98, 400), [], "the left edge faces no window")
        XCTAssertEqual(s.clientResizeEdgeAt(a, a.id, 496, 98), .right, "a corner gives only the shared edge")
    }

    func testAFloatingWindowHasEveryEdgeAndCorner() {
        let (r, c) = floating()
        let s = r.server
        XCTAssertEqual(s.clientResizeEdgeAt(c, nil, 97, 97), [.left, .top])
        XCTAssertEqual(s.clientResizeEdgeAt(c, c.id, 498, 398), [.right, .bottom])
        XCTAssertEqual(s.clientResizeEdgeAt(c, c.id, 300, 98), [.top])
        XCTAssertEqual(s.resizeCursorName([.left, .top], true), "nw-resize")
        XCTAssertEqual(s.resizeCursorName([.right], false), "col-resize")
        XCTAssertEqual(s.resizeCursorName([.bottom], false), "row-resize")
    }

    func testAnotherSurfaceOnTheStripKeepsItsInput() {
        let (r, a, _) = sideBySide()
        XCTAssertEqual(r.server.clientResizeEdgeAt(a, 99, 496, 400), [])
    }

    func testNoStripInTheOverviewOrFullscreen() {
        let (r, a, _) = sideBySide()
        a.isfullscreen = true
        XCTAssertEqual(r.server.clientResizeEdgeAt(a, a.id, 496, 400), [])
        a.isfullscreen = false
        _ = r.server.dispatch(Dispatch(name: "toggleoverview"))
        XCTAssertEqual(r.server.clientResizeEdgeAt(a, a.id, 496, 400), [])
    }

    func testSizeZeroIsTheBorder() {
        let (r, a, _) = sideBySide()
        r.server.config.borderResizeSize = 0
        XCTAssertEqual(r.server.clientResizeEdgeAt(a, nil, 502, 400), .right)
        XCTAssertEqual(r.server.clientResizeEdgeAt(a, a.id, 496, 400), [], "inside the window: not the border")
    }

    func testHoverSetsTheCursorAndLeavingGivesItBack() {
        let (r, _, _) = sideBySide()
        motion(r, CGPoint(x: 496, y: 400), time: 1)
        XCTAssertEqual(r.server.hoverResizeEdge, .right)
        XCTAssertEqual(fake(r).cursorName, .some("col-resize"))
        motion(r, CGPoint(x: 300, y: 400), time: 2)
        XCTAssertEqual(r.server.hoverResizeEdge, [])
        XCTAssertEqual(fake(r).cursorName, .some(nil), "given back to the window")
    }

    func testTheStripIsTheWindows() {
        let (r, a, b) = sideBySide()
        r.server.config.sloppyfocus = true
        r.server.clientFocus(b, true)
        motion(r, CGPoint(x: 496, y: 400), time: 1)
        XCTAssertEqual(r.monitor.sel, a.id)
        XCTAssertEqual(r.server.hoverResizeEdge, .right)
        XCTAssertNil(r.server.nodeAtPoint(CGPoint(x: 505, y: 400)), "the gap is no window's")
    }

    func testTheTapSetsTheStripsCursorAsThePointerMoves() {
        let router = InputRouter()
        var set: [String] = []
        router.setCursor = { set.append($0) }
        router.mouseMoved(CGPoint(x: 1, y: 1))
        XCTAssertEqual(set, [])
        router.publish { $0.hoverResizeCursor = "col-resize" }
        router.mouseMoved(CGPoint(x: 2, y: 1))
        router.mouseMoved(CGPoint(x: 3, y: 1))
        XCTAssertEqual(set, ["col-resize", "col-resize"])
    }

    func testOffWithoutEnableBorderResize() {
        let (r, _, _) = sideBySide()
        r.server.config.enableBorderResize = false
        motion(r, CGPoint(x: 496, y: 400), time: 1)
        XCTAssertEqual(r.server.hoverResizeEdge, [])
        XCTAssertFalse(r.server.press(at: CGPoint(x: 496, y: 400), mods: []))
        XCTAssertNil(r.server.grabClient)
    }

    func testAPressOnTheStripBeginsABorderResize() throws {
        let (r, a, _) = sideBySide()
        XCTAssertTrue(r.server.press(at: CGPoint(x: 496, y: 400), mods: []))
        XCTAssertTrue(try XCTUnwrap(r.server.grabClient) === a)
        XCTAssertEqual(r.server.cursorMode, CurResize)
        XCTAssertTrue(r.server.grabIsBorderResize)
        XCTAssertEqual(fake(r).cursorName, .some("col-resize"))
        r.server.release(at: CGPoint(x: 496, y: 400), mods: [])
        XCTAssertNil(r.server.grabClient)
    }

    func testDraggingAFloatingEdgeChangesOnlyThatEdge() {
        let (r, c) = floating()
        r.arrange()
        let before = c.frame
        r.server.press(at: CGPoint(x: before.maxX - 2, y: before.midY), mods: [])
        XCTAssertNotNil(r.server.grabClient)
        XCTAssertEqual(r.server.resizeEdge, .right)
        motion(r, CGPoint(x: before.maxX + 48, y: before.midY + 30), time: 100)
        XCTAssertEqual(c.frame.width, before.width + 50, accuracy: 1)
        XCTAssertEqual(c.frame.height, before.height)
        XCTAssertEqual(c.frame.minX, before.minX)
        r.server.release(at: CGPoint(x: before.maxX + 48, y: before.midY + 30), mods: [])

        let f = c.frame
        r.server.press(at: CGPoint(x: f.minX + 2, y: f.midY), mods: [])
        XCTAssertNotNil(r.server.grabClient)
        XCTAssertEqual(r.server.resizeEdge, .left)
        motion(r, CGPoint(x: f.minX + 32, y: f.midY), time: 200)
        XCTAssertEqual(c.frame.maxX, f.maxX, accuracy: 1, "the right side stays")
        XCTAssertEqual(c.frame.width, f.width - 30, accuracy: 1)
    }

    func testAPlainClickOnAStripDoesNotSnap() {
        let (r, c) = floating()
        r.server.config.enableFloatingSnap = true
        c.frame = CGRect(x: 20, y: 300, width: 400, height: 300)
        r.app.frames[c.id] = c.frame
        bordered(r, c)
        let strip = CGPoint(x: c.frame.maxX - 2, y: c.frame.midY)
        r.server.press(at: strip, mods: [])
        r.server.release(at: strip, mods: [])
        XCTAssertEqual(c.floatGeom.minX, 20 - c.bw, "a plain click: no snap")
        r.server.press(at: strip, mods: [])
        let moved = CGPoint(x: strip.x + 10, y: strip.y)
        motion(r, moved, time: 100)
        r.server.release(at: moved, mods: [])
        XCTAssertLessThan(c.floatGeom.minX, 20 - c.bw, "moved: the window snaps to the screen's edge")
    }

    func testDraggingATiledStripMovesTheSplit() throws {
        let r = EngineRig()
        r.server.renderBorder = true
        let w1 = r.map(1), w2 = r.map(2)
        r.arrange()
        let (a, b) = try XCTUnwrap(w1.geom).minX < XCTUnwrap(w2.geom).minX ? (w1, w2) : (w2, w1)
        let ga = try XCTUnwrap(a.geom), gb = try XCTUnwrap(b.geom)
        XCTAssertLessThan(ga.maxX, gb.minX, "a left of b")
        let strip = CGPoint(x: a.frame.maxX - 2, y: a.frame.midY)
        XCTAssertTrue(r.server.press(at: strip, mods: []))
        XCTAssertEqual(fake(r).cursorName, .some("col-resize"))
        motion(r, strip, time: 1)
        motion(r, CGPoint(x: strip.x + 120, y: strip.y), time: 100)
        r.server.release(at: CGPoint(x: strip.x + 120, y: strip.y), mods: [])
        XCTAssertGreaterThan(try XCTUnwrap(a.geom).width, ga.width + 60, "the split moved right")
        XCTAssertLessThan(try XCTUnwrap(b.geom).width, gb.width - 60)
        XCTAssertNil(r.server.grabClient)
    }

    func testAPressTheTapLetThroughIsTheApps() {
        let (r, _, _) = sideBySide()
        XCTAssertFalse(r.server.press(at: CGPoint(x: 496, y: 400), mods: [],
                                                          borderResizeTaken: false))
        XCTAssertNil(r.server.grabClient)
    }

    func testNoStripCursorDuringAGrab() {
        let (r, _, _) = sideBySide()
        let router = fake(r).router
        var set: [String] = []
        router.setCursor = { set.append($0) }
        motion(r, CGPoint(x: 496, y: 400), time: 1)
        router.mouseMoved(CGPoint(x: 496, y: 401))
        XCTAssertEqual(set, ["col-resize"])
        r.server.press(at: CGPoint(x: 496, y: 400), mods: [])
        router.mouseMoved(CGPoint(x: 497, y: 401))
        XCTAssertEqual(set, ["col-resize"], "not during the grab")
    }

    func testTheSavedLayoutKeepsFloatingInTheOverview() {
        let (r, c) = floating()
        _ = r.server.dispatch(Dispatch(name: "toggleoverview"))
        XCTAssertFalse(c.isfloating)
        let saved = r.server.mac.memory.currentLayout(r.server).windows.first { $0.id == c.id }
        XCTAssertEqual(saved?.isfloating, true)
    }

    func testTheTapTakesTheLeftPressOnTheStrip() {
        func press(_ button: Int, hover: Bool) -> Pointer.ButtonPress {
            Pointer.pointerProcessButtonPress(button: button, at: .zero, mods: [], switcherActive: false, overviewFrame: nil,
                                              mouseBindings: [], mode: "default", hoverResizeEdge: hover)
        }
        XCTAssertEqual(press(0, hover: true), .borderResize)
        XCTAssertEqual(press(1, hover: true), .none)
        XCTAssertEqual(press(0, hover: false), .none)
    }
}
