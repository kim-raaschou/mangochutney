import Foundation

package struct SwipeDrive {
    static let lockDistance = 16.0
    static let flickMaxMs: UInt32 = 200

    enum Kind { case transition, pan, drag }

    var locked = false
    var horizontal = false
    var consumed = false
    var active = false
    var kind = Kind.transition
    var dir = 1.0
    var base = 0.0
    var maxDelta = 0.0
    var prevAxis = 0.0
    var avgSpeed = 0.0
    var speedPoints = 0
    var firstTime: UInt32 = 0
    var lastTime: UInt32 = 0
}
