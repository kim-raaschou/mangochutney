import CoreGraphics
import Mango

struct SwipeTracker {
    static let unitsPerMM = 1000 / 25.4
    static let beginMM = 2.0

    init() {}

    private var fingers = 0
    private var start = CGPoint.zero
    private var last = CGPoint.zero
    private var began = false

    private var swipe: Swipe {
        Swipe(dx: Double(last.x - start.x) * Self.unitsPerMM, dy: Double(last.y - start.y) * Self.unitsPerMM,
              fingers: fingers)
    }

    mutating func frame(fingers count: Int, centre: CGPoint) -> SwipeEvent? {
        if count >= 3 && count == fingers {
            last = centre
            if !began {
                guard hypot(centre.x - start.x, centre.y - start.y) >= Self.beginMM else { return nil }
                began = true
                start = centre
            }
            return .update(swipe)
        }
        let ended: SwipeEvent? = fingers >= 3 && count < fingers && began ? .end(swipe) : nil
        if count >= 3 {
            fingers = count
            start = centre
            last = centre
        } else {
            fingers = 0
        }
        began = false
        return ended
    }
}
