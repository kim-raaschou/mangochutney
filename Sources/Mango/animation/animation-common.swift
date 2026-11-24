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

public struct BezierCurve: Equatable, Sendable {
    public var x1: Double, y1: Double, x2: Double, y2: Double
    public init(x1: Double, y1: Double, x2: Double, y2: Double) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
    }
    public static let mangoDefault = BezierCurve(x1: 0.46, y1: 1.0, x2: 0.29, y2: 0.99)
    public static let linear = BezierCurve(x1: 0, y1: 0, x2: 1, y2: 1)

    private func calculateAnimationCurveAt(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let mt = 1 - t
        return 3 * mt * mt * t * a + 3 * mt * t * t * b + t * t * t
    }
    public func findAnimationCurveAt(at x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<24 {
            let sx = calculateAnimationCurveAt(t, x1, x2)
            if abs(sx - x) < 1e-5 { break }
            if sx < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return calculateAnimationCurveAt(t, y1, y2)
    }
}
