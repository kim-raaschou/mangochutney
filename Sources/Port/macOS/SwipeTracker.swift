import CoreGraphics
import Mango

/// Not in mango: what libinput does for it. A trackpad swipe as mango gets it from
/// libinput (`Swipe`): three or more fingers that move
/// together, one gesture per finger count, ended when a finger lifts. Fed the touches'
/// centre (millimetres on the trackpad, y down) frame by frame, it reports the swipe's
/// travel since it began (libinput's swipe_dx/dy, in libinput's units: 1/1000 inch,
/// unaccelerated) while the fingers move, and once more when it ends.
struct SwipeTracker {
    static let unitsPerMM = 1000 / 25.4
    /// libinput tells a swipe from resting fingers by their travel before it begins the
    /// gesture; this stands in for that detection.
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

    /// Not in mango: builds libinput-style swipes from touches.
    /// One frame: `count` fingers on the trackpad, their centre at `centre`.
    mutating func frame(fingers count: Int, centre: CGPoint) -> SwipeEvent? {
        if count >= 3 && count == fingers {
            last = centre
            if !began {
                guard hypot(centre.x - start.x, centre.y - start.y) >= Self.beginMM else { return nil }
                // The gesture begins here: its travel counts from now, as libinput's.
                began = true
                start = centre
            }
            return .update(swipe)
        }
        // A finger lifted (or the swipe ends with all of them): the gesture ends. A finger
        // more starts another gesture, as libinput's count change does.
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
