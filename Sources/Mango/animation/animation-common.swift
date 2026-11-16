import Foundation
import CoreGraphics

/// mango's animation types (animation/common.h): NONE, OPEN, MOVE, CLOSE, TAG, FOCUS, OPAFADEIN, OPAFADEOUT, OVERVIEW.
public enum AnimationAction: Int32, Equatable, Sendable {
    case none, open, move, close, tag, focus, opafadein, opafadeout, overview
}

/// mango struct mango_animation (animation/common.h).
public struct MangoAnimation: Equatable {
    public var shouldAnimate = false
    public var running = false
    public var tagining = false
    public var tagouted = false
    public var tagouting = false
    public var beginFadeIn = false
    public var tagFromRule = false
    public var overining = false
    public var overviewEnterAnimSet = false
    public var timeStarted: UInt32 = 0
    public var duration: UInt32 = 0
    public var initial: CGRect = .zero
    public var current: CGRect = .zero
    public var action: AnimationAction = .none
    public init() {}
}

/// mango get_now_in_ms (common/util.c).
@MainActor
public func getNowInMs() -> UInt32 {
    // not in mango: the port's clock; tests move it
    if let now = nowInMsOverride { return now() }
    return UInt32(truncatingIfNeeded: clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000)
}

/// Not in mango: a clock the tests can set.
@MainActor
public var nowInMsOverride: (() -> UInt32)?

extension MangoServer {
    /// mango find_animation_curve_at (animation/common.c). Not in mango: the curve is solved, not baked.
    package func findAnimationCurveAt(_ t: Double, _ type: AnimationAction) -> Double {
        let curve: BezierCurve
        switch type {
        case .move: curve = config.animationCurveMove
        case .open: curve = config.animationCurveOpen
        case .tag: curve = config.animationCurveTag
        // not in mango: no CLOSE, FOCUS, OPAFADEIN or OPAFADEOUT curve; no close, focus or fade animation here (MangoCompat)
        default: curve = config.animationCurveMove
        }
        return curve.findAnimationCurveAt(at: t)
    }

    package func requestFreshAllMonitors() {
        for m in monitors {
            system.outputScheduleFrame(m)   // not in mango: the port's wlr_output_schedule_frame
        }
    }
}
