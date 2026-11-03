/// The boundary, not in mango: a trackpad swipe as libinput hands it to mango
/// (wlr_pointer_swipe_update_event and _end_event): its travel since the gesture began, in
/// libinput's units (1/1000 inch, unaccelerated), and the finger count. The port makes them
/// (SwipeTracker); mango's trackpad code (LiveGestures.swift) reads them. To be declared
/// outside the core with the rest of the boundary (plan, K6).
package struct Swipe: Equatable {
    /// Since the gesture began.
    package var dx: Double, dy: Double
    package var fingers: Int

    package init(dx: Double, dy: Double, fingers: Int) { self.dx = dx; self.dy = dy; self.fingers = fingers }
}

package enum SwipeEvent: Equatable {
    case update(Swipe)
    case end(Swipe)
}
