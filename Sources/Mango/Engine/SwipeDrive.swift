import Foundation

let SWIPE_LOCK_DISTANCE = 16.0
let SWIPE_FLICK_MAX_MS: UInt32 = 200

package struct SwipeDrive {
    var active = false
    var consumed = false
    var pan = false
    var drag = false
    var mon: Monitor?
    var fingers = 0
    var startSel: ClientID?
    var horizontal = false
    var base = 0.0
    var dir = 0.0
    var prevAxis = 0.0
    var avgSpeed = 0.0
    var speedPoints: UInt32 = 0
    var firstTime: UInt32 = 0
    var lastTime: UInt32 = 0
    var dragPrevDx = 0.0
    var dragPrevDy = 0.0
    var motion: Direction = .up
    var maxDelta = 0.0
    var `func`: String?
    var arg: [String] = []
}
