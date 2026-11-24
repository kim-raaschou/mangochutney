import XCTest
@testable import Mango
@testable import Port

/// mango's pointer_focus (pointer.c): sloppy focus only on a motion with a time, and only when the
/// pointer enters another surface.
@MainActor
final class PointerFocusTests: MangoTestCase {
    func sideBySide() -> (EngineRig, Client, Client) {
        let r = EngineRig()
        r.server.config.sloppyfocus = true
        let a = r.window(1, frame: CGRect(x: 100, y: 100, width: 400, height: 600))
        let b = r.window(2, frame: CGRect(x: 600, y: 100, width: 400, height: 600))
        return (r, a, b)
    }

    func testAMotionWithoutATimeNeverFocuses() {
        let (r, a, b) = sideBySide()
        r.server.clientFocus(b, false)
        r.server.motion(to: CGPoint(x: 300, y: 400), time: 0)
        XCTAssertEqual(r.monitor.sel?.id, b.id, "time 0 restores the pointer focus only")
        XCTAssertEqual(r.server.system.pointerFocusedSurface, a.id, "the pointer has entered a")
    }

    func testUnmapRestoresThePointerFocus() {
        let (r, a, b) = sideBySide()
        r.server.motion(to: CGPoint(x: 800, y: 400), time: 1)
        XCTAssertEqual(r.server.system.pointerFocusedSurface, b.id)
        r.server.handleClientUnmap(b)
        XCTAssertNotEqual(r.server.system.pointerFocusedSurface, b.id, "handle_client_unmap ends in pointer_process_motion(0)")
        XCTAssertEqual(r.monitor.sel?.id, a.id)
    }
}
