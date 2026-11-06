import XCTest
@testable import Mango
@testable import Port

/// mango's dwindle_smart_resize, split indicator (split_color) and the scroller's
/// edge_scroller_pointer_focus / edge_scroller_focus_allow_speed.
@MainActor
final class DwindleScrollerOptionTests: MangoTestCase {
    func dwindle(_ windows: Int) -> EngineRig {
        let r = EngineRig()
        r.monitor.current.layout = .dwindle
        for i in 0..<windows { r.window(CGWindowID(900_400 + i)) }
        r.server.arrange(r.monitor, .none)
        return r
    }

    /// Grabs the right one of two windows side by side at its middle (right of the split
    /// line) with a resize mousebind, and drags it `dx` across: the first motion begins the
    /// drag (start_drag_window), the second is a frame later.
    func dragRight(_ r: EngineRig, by dx: CGFloat) -> CGFloat {
        let resize = MouseBinding(mods: [.superKey], button: .right, dispatch: Dispatch(name: "moveresize", args: ["curresize"]))
        let right = r.server.clientByIdAll(900_401)!.geom!
        let p = CGPoint(x: right.midX, y: right.midY)
        r.server.mousebind(resize, at: p)
        r.server.pointerProcessMotion(p, time: 1000)
        r.server.pointerProcessMotion(CGPoint(x: p.x + dx, y: p.y), time: 1100)
        return r.server.clientByIdAll(900_400)!.geom!.width
    }

    /// mango dwindle_resize_client: the split line follows the pointer's travel from where
    /// the drag began.
    func testADragMovesTheSplitLineWithThePointer() {
        let r = dwindle(2)
        let before = r.server.clientByIdAll(900_400)!.geom!.width
        XCTAssertEqual(dragRight(r, by: 100), before + 100, accuracy: 2)
    }

    /// dwindle_smart_resize: begun right of the split line, the drag moves it the other way.
    func testSmartResizeInvertsBeyondTheSplitLine() {
        let r = dwindle(2)
        r.server.config.dwindleSmartResize = true
        let before = r.server.clientByIdAll(900_400)!.geom!.width
        XCTAssertEqual(dragRight(r, by: 100), before - 100, accuracy: 2)
    }

    /// mango 09828ec: a tiled drag lays out on every motion, however soon after the last.
    /// (A floating resize keeps one a frame: 60 Hz when the monitor's rate is not known.)
    func testATiledDragLaysOutOnEveryMotion() {
        let r = dwindle(2)
        let width = dragRight(r, by: 100)
        r.server.pointerProcessMotion(CGPoint(x: 0, y: 0), time: 1110)
        XCTAssertNotEqual(r.server.clientByIdAll(900_400)!.geom!.width, width, "1 ms later: laid out")
        XCTAssertEqual(r.server.dragRefreshIntervalMs(r.monitor), 16)
        r.monitor.screen.refresh = 120_000
        XCTAssertEqual(r.server.dragRefreshIntervalMs(r.monitor), 8)
    }

    func testTheSplitIndicatorShowsTheNextSplitsSide() {
        let r = dwindle(2)
        let c = r.server.clientByIdAll(900_400)!
        XCTAssertNil(r.server.clientDrawSplitBorder(c, on: r.monitor), "only with dwindle_manual_split")
        r.server.config.dwindleManualSplit = true
        let horizontal = r.monitor.current.state.dwindleRoot.leafSplitHorizontal(for: c.id)!
        XCTAssertEqual(r.server.clientDrawSplitBorder(c, on: r.monitor)?.side, horizontal ? .right : .bottom)
        XCTAssertEqual(r.server.clientDrawSplitBorder(c, on: r.monitor)?.color, r.server.config.splitcolor)
        r.monitor.current.state.dwindleRoot.dwindleSetSplitDirection(c.id, horizontal: nil)
        XCTAssertEqual(r.server.clientDrawSplitBorder(c, on: r.monitor)?.side, horizontal ? .bottom : .right)
        c.isUrgent = true
        XCTAssertEqual(r.server.clientDrawSplitBorder(c, on: r.monitor)?.color, r.server.config.urgentcolor)
        c.isFloating = true
        XCTAssertNil(r.server.clientDrawSplitBorder(c, on: r.monitor), "tiled windows only")
    }

    /// A scroller: 900_410 inside the screen, 900_411 and 900_412 partly off its right edge.
    func scroller() -> EngineRig {
        let r = EngineRig()
        r.monitor.current.layout = .scroller
        r.server.config.sloppyfocus = true
        let w = r.screen.frame
        r.window(900_410, frame: CGRect(x: 100, y: 100, width: 600, height: 800))
        r.window(900_411, frame: CGRect(x: w.maxX - 300, y: 100, width: 600, height: 400))
        r.window(900_412, frame: CGRect(x: w.maxX - 300, y: 520, width: 600, height: 400))
        r.server.clientFocus(r.server.clientByIdAll(900_410)!, raise: false)
        startFrames = [900_410: CGRect(x: 100, y: 100, width: 600, height: 800),
                       900_411: CGRect(x: w.maxX - 300, y: 100, width: 600, height: 400),
                       900_412: CGRect(x: w.maxX - 300, y: 520, width: 600, height: 400)]
        return r
    }

    var startFrames: [CGWindowID: CGRect] = [:]

    /// The pointer onto `id`, with the windows back where scroller() put them (a focus
    /// arranges the scroller, which moves them).
    func move(_ r: EngineRig, to id: CGWindowID, speed: CGFloat) {
        for (wid, frame) in r.app.frames where wid >= 900_410 && wid <= 900_412 {
            r.server.clientByIdAll(wid)!.frame = startFrames[wid] ?? frame
            r.server.clientByIdAll(wid)!.parked = false
        }
        let f = r.server.clientByIdAll(id)!.frame
        r.server.handleCursorMotion(CGPoint(x: f.minX + 50, y: f.midY), time: 1, speed: speed)
    }

    func testAWindowOffTheEdgeTakesTheFocusByDefault() {
        let r = scroller()
        move(r, to: 900_411, speed: 0)
        XCTAssertEqual(r.monitor.sel, 900_411)
    }

    func testWithoutEdgeFocusItDoesNot() {
        let r = scroller()
        r.server.config.edgeScrollerPointerFocus = false
        move(r, to: 900_411, speed: 50)
        XCTAssertEqual(r.monitor.sel, 900_410)
        move(r, to: 900_410, speed: 0)
        XCTAssertEqual(r.monitor.sel, 900_410, "inside: as always")
    }

    func testOnlyFastEnough() {
        let r = scroller()
        r.server.config.edgeScrollerFocusAllowSpeed = 20
        move(r, to: 900_411, speed: 5)
        XCTAssertEqual(r.monitor.sel, 900_410, "too slow")
        move(r, to: 900_411, speed: 30)
        XCTAssertEqual(r.monitor.sel, 900_411)
    }

    /// Once a window off the edge has the focus, no other one takes it until the pointer
    /// has been on a window inside the screen.
    func testTheLock() {
        let r = scroller()
        move(r, to: 900_411, speed: 0)
        move(r, to: 900_412, speed: 0)
        XCTAssertEqual(r.monitor.sel, 900_411, "locked")
        move(r, to: 900_410, speed: 0)
        move(r, to: 900_412, speed: 0)
        XCTAssertEqual(r.monitor.sel, 900_412, "the lock went with the window inside")
    }
}
