import CoreGraphics
@testable import Mango

extension MangoServer {
    func mousebind(_ b: MouseBinding, at p: CGPoint) {
        (system as! FakeWindowSystem).fakePointer = p
        _ = dispatch(b.dispatch)
    }

    func buttonReleased(at p: CGPoint) {
        pointerProcessButtonPress(button: 0, pressed: false, at: p, mods: [])
    }
}
