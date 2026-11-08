package struct Swipe: Equatable {
    package var dx: Double, dy: Double
    package var fingers: Int

    package init(dx: Double, dy: Double, fingers: Int) { self.dx = dx; self.dy = dy; self.fingers = fingers }
}

package enum SwipeEvent: Equatable {
    case update(Swipe)
    case end(Swipe)
}
