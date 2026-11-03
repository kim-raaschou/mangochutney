import CoreGraphics
@testable import Mango

/// mango's mousebind: the pointer at `p` (server.cursor), then the binding's dispatcher (m->func).
extension MangoServer {
    func mousebind(_ b: MouseBinding, at p: CGPoint) {
        (system as! FakeWindowSystem).fakePointer = p
        _ = dispatch(b.dispatch)
    }

    /// mango pointer_process_button_press, released.
    func buttonReleased(at p: CGPoint) {
        pointerProcessButtonPress(button: 0, pressed: false, at: p, mods: [])
    }
}
