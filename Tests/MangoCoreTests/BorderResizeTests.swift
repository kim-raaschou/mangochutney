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
        return (r, a, b)
    }

    func floating() -> (EngineRig, Client) {
        let r = EngineRig()
        r.server.renderBorder = true
        let c = r.window(1, floating: true, frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        return (r, c)
    }

    func fake(_ r: EngineRig) -> FakeWindowSystem { r.server.system as! FakeWindowSystem }

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
        XCTAssertEqual(s.resizeCursorName([.left, .top], floating: true), "nw-resize")
        XCTAssertEqual(s.resizeCursorName([.right], floating: false), "col-resize")
        XCTAssertEqual(s.resizeCursorName([.bottom], floating: false), "row-resize")
    }

    func testAnotherSurfaceOnTheStripKeepsItsInput() {
        let (r, a, _) = sideBySide()
        XCTAssertEqual(r.server.clientResizeEdgeAt(a, 99, 496, 400), [])
    }

    func testNoStripInTheOverviewOrFullscreen() {
        let (r, a, _) = sideBySide()
        a.isFullscreen = true
        XCTAssertEqual(r.server.clientResizeEdgeAt(a, a.id, 496, 400), [])
        a.isFullscreen = false
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
        r.server.handleCursorMotion(CGPoint(x: 496, y: 400), time: 1)
        XCTAssertEqual(r.server.hoverResizeEdge, .right)
        XCTAssertEqual(fake(r).cursorName, .some("col-resize"))
        r.server.handleCursorMotion(CGPoint(x: 300, y: 400), time: 2)
        XCTAssertEqual(r.server.hoverResizeEdge, [])
        XCTAssertEqual(fake(r).cursorName, .some(nil), "given back to the window")
    }

    func testTheStripIsTheWindows() {
        let (r, a, b) = sideBySide()
        r.server.config.sloppyfocus = true
        r.server.clientFocus(b)
        r.server.handleCursorMotion(CGPoint(x: 496, y: 400), time: 1)
        XCTAssertEqual(r.monitor.sel, a.id)
        XCTAssertEqual(r.server.hoverResizeEdge, .right)
        XCTAssertNil(r.server.clientAtPoint(CGPoint(x: 505, y: 400)), "the gap is no window's")
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
        r.server.handleCursorMotion(CGPoint(x: 496, y: 400), time: 1)
        XCTAssertEqual(r.server.hoverResizeEdge, [])
        XCTAssertFalse(r.server.pointerProcessButtonPress(button: 0, pressed: true, at: CGPoint(x: 496, y: 400), mods: []))
        XCTAssertNil(r.server.grab)
    }

    func testAPressOnTheStripBeginsABorderResize() throws {
        let (r, a, _) = sideBySide()
        XCTAssertTrue(r.server.pointerProcessButtonPress(button: 0, pressed: true, at: CGPoint(x: 496, y: 400), mods: []))
        let g = try XCTUnwrap(r.server.grab)
        XCTAssertTrue(g.client === a)
        XCTAssertEqual(g.mode, .resize)
        XCTAssertTrue(g.isBorderResize)
        XCTAssertEqual(fake(r).cursorName, .some("col-resize"))
        r.server.pointerProcessButtonPress(button: 0, pressed: false, at: CGPoint(x: 496, y: 400), mods: [])
        XCTAssertNil(r.server.grab)
    }

    func testDraggingAFloatingEdgeChangesOnlyThatEdge() {
        let (r, c) = floating()
        r.server.arrange(r.monitor, .none)
        let before = c.frame
        r.server.pointerProcessButtonPress(button: 0, pressed: true, at: CGPoint(x: before.maxX - 2, y: before.midY), mods: [])
        XCTAssertEqual(r.server.grab?.resizeEdge, .right)
        r.server.handleCursorMotion(CGPoint(x: before.maxX + 48, y: before.midY + 30), time: 100)
        XCTAssertEqual(c.frame.width, before.width + 50, accuracy: 1)
        XCTAssertEqual(c.frame.height, before.height)
        XCTAssertEqual(c.frame.minX, before.minX)
        r.server.pointerProcessButtonPress(button: 0, pressed: false, at: CGPoint(x: before.maxX + 48, y: before.midY + 30), mods: [])

        let f = c.frame
        r.server.pointerProcessButtonPress(button: 0, pressed: true, at: CGPoint(x: f.minX + 2, y: f.midY), mods: [])
        XCTAssertEqual(r.server.grab?.resizeEdge, .left)
        r.server.handleCursorMotion(CGPoint(x: f.minX + 32, y: f.midY), time: 200)
        XCTAssertEqual(c.frame.maxX, f.maxX, accuracy: 1, "the right side stays")
        XCTAssertEqual(c.frame.width, f.width - 30, accuracy: 1)
    }

    func testAPlainClickOnAStripDoesNotSnap() {
        let (r, c) = floating()
        r.server.config.enableFloatingSnap = true
        c.frame = CGRect(x: 20, y: 300, width: 400, height: 300)
        c.floatGeom = c.frame
        r.app.frames[c.id] = c.frame
        let strip = CGPoint(x: c.frame.maxX - 2, y: c.frame.midY)
        r.server.pointerProcessButtonPress(button: 0, pressed: true, at: strip, mods: [])
        r.server.pointerProcessButtonPress(button: 0, pressed: false, at: strip, mods: [])
        XCTAssertEqual(c.floatGeom.minX, 20, "a plain click: no snap")
        r.server.pointerProcessButtonPress(button: 0, pressed: true, at: strip, mods: [])
        let moved = CGPoint(x: strip.x + 10, y: strip.y)
        r.server.handleCursorMotion(moved, time: 100)
        r.server.pointerProcessButtonPress(button: 0, pressed: false, at: moved, mods: [])
        XCTAssertLessThan(c.floatGeom.minX, 20, "moved: the window snaps to the screen's edge")
    }

    func testDraggingATiledStripMovesTheSplit() throws {
        let r = EngineRig()
        r.server.renderBorder = true
        let w1 = r.map(1), w2 = r.map(2)
        r.server.arrange(r.monitor, .none)
        let (a, b) = try XCTUnwrap(w1.geom).minX < XCTUnwrap(w2.geom).minX ? (w1, w2) : (w2, w1)
        let ga = try XCTUnwrap(a.geom), gb = try XCTUnwrap(b.geom)
        XCTAssertLessThan(ga.maxX, gb.minX, "a left of b")
        let strip = CGPoint(x: a.frame.maxX - 2, y: a.frame.midY)
        XCTAssertTrue(r.server.pointerProcessButtonPress(button: 0, pressed: true, at: strip, mods: []))
        XCTAssertEqual(fake(r).cursorName, .some("col-resize"))
        r.server.handleCursorMotion(strip, time: 1)
        r.server.handleCursorMotion(CGPoint(x: strip.x + 120, y: strip.y), time: 100)
        r.server.pointerProcessButtonPress(button: 0, pressed: false, at: CGPoint(x: strip.x + 120, y: strip.y), mods: [])
        XCTAssertGreaterThan(try XCTUnwrap(a.geom).width, ga.width + 60, "the split moved right")
        XCTAssertLessThan(try XCTUnwrap(b.geom).width, gb.width - 60)
        XCTAssertNil(r.server.grab)
    }

    func testAPressTheTapLetThroughIsTheApps() {
        let (r, _, _) = sideBySide()
        XCTAssertFalse(r.server.pointerProcessButtonPress(button: 0, pressed: true, at: CGPoint(x: 496, y: 400), mods: [],
                                                          borderResizeTaken: false))
        XCTAssertNil(r.server.grab)
    }

    func testNoStripCursorDuringAGrab() {
        let (r, _, _) = sideBySide()
        let router = fake(r).router
        var set: [String] = []
        router.setCursor = { set.append($0) }
        r.server.handleCursorMotion(CGPoint(x: 496, y: 400), time: 1)
        router.mouseMoved(CGPoint(x: 496, y: 401))
        XCTAssertEqual(set, ["col-resize"])
        r.server.pointerProcessButtonPress(button: 0, pressed: true, at: CGPoint(x: 496, y: 400), mods: [])
        router.mouseMoved(CGPoint(x: 497, y: 401))
        XCTAssertEqual(set, ["col-resize"], "not during the grab")
    }

    func testTheSavedLayoutKeepsFloatingInTheOverview() {
        let (r, c) = floating()
        _ = r.server.dispatch(Dispatch(name: "toggleoverview"))
        XCTAssertFalse(c.isFloating)
        let saved = r.server.mac.memory.currentLayout(r.server).windows.first { $0.id == c.id }
        XCTAssertEqual(saved?.isFloating, true)
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
