import CoreGraphics
@testable import Mango

extension MangoServer {
    var fake: FakeWindowSystem { system as! FakeWindowSystem }

    func mousebind(_ b: MouseBinding, at p: CGPoint) {
        fake.fakePointer = p
        _ = dispatch(b.dispatch)
    }

    /// A press of the left button at `p` (the pointer there), as the port gives it.
    @discardableResult
    func press(at p: CGPoint, mods: Modifiers = [], button: Int = 0, borderResizeTaken: Bool = true) -> Bool {
        fake.fakePointer = p
        return pointerProcessButtonPress(button: button, pressed: true, at: p, mods: mods, borderResizeTaken: borderResizeTaken)
    }

    @discardableResult
    func release(at p: CGPoint, mods: Modifiers = [], button: Int = 0) -> Bool {
        fake.fakePointer = p
        return pointerProcessButtonPress(button: button, pressed: false, at: p, mods: mods)
    }

    func buttonReleased(at p: CGPoint) {
        fake.fakePointer = p
        pointerProcessButtonPress(button: 0, pressed: false, at: p, mods: [])
    }

    /// The pointer moved to `p` (wlroots' cursor), and pointer_process_motion with the time and the deltas.
    func motion(to p: CGPoint, time: UInt32 = 1, dx: Double = 0, dy: Double = 0) {
        fake.fakePointer = p
        pointerProcessMotion(time, dx, dy)
    }

    /// The pointer moved to `p`, as the port gives handle_cursor_motion.
    func cursorMotion(to p: CGPoint, time: UInt32 = 1, dx: Double = 0, dy: Double = 0) {
        fake.fakePointer = p
        handleCursorMotion(time, dx, dy)
    }

    func hotarea(_ p: CGPoint) {
        toggleHotarea(Int32(p.x), Int32(p.y))
    }
}
