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

/// mango struct dvec2 (animation/common.h).
package struct DVec2 {
    var x: Double = 0, y: Double = 0
}

extension MangoServer {
    private func calculateBezierCurveFor(_ t: Double, _ curve: [Double]) -> DVec2 {
        var point = DVec2()
        point.x = 3 * t * (1 - t) * (1 - t) * curve[0] +
            3 * t * t * (1 - t) * curve[2] + t * t * t

        point.y = 3 * t * (1 - t) * (1 - t) * curve[1] +
            3 * t * t * (1 - t) * curve[3] + t * t * t
        return point
    }

    private func animationCurveForType(_ type: AnimationAction) -> AnimationCurve {
        if type == .open { return config.animationCurveOpen }
        if type == .tag { return config.animationCurveTag }
        if type == .close { return config.animationCurveClose }
        if type == .focus { return config.animationCurveFocus }
        // not in mango: no animation_curve_opafadein or animation_curve_opafadeout (no fades on macOS)
        return config.animationCurveMove
    }

    package func animationCurveEase(_ curve: AnimationCurve?, _ progress: Double) -> Double {
        guard let curve else { return fmax(0.0, fmin(1.0, progress)) }
        let progress = fmax(0.0, fmin(1.0, progress))
        if curve.type == .named { return applyNamedEasing(curve.easing, progress) }

        let bezier = curve.bezier
        var low = 0.0
        var high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2.0
            if calculateBezierCurveFor(mid, bezier).x < progress {
                low = mid
            } else {
                high = mid
            }
        }
        return calculateBezierCurveFor((low + high) / 2.0, bezier).y
    }

    package func animationCurveDurationMs(_ curve: AnimationCurve?, _ fallbackMs: UInt32) -> UInt32 {
        fallbackMs
    }

    package func animationDurationForType(_ type: AnimationAction, _ fallbackMs: UInt32) -> UInt32 {
        animationCurveDurationMs(animationCurveForType(type), fallbackMs)
    }

    private func easeOutBounce(_ t: Double) -> Double {
        var t = t
        let n1 = 7.5625
        let d1 = 2.75
        if t < 1.0 / d1 { return n1 * t * t }
        if t < 2.0 / d1 {
            t -= 1.5 / d1
            return n1 * t * t + 0.75
        }
        if t < 2.5 / d1 {
            t -= 2.25 / d1
            return n1 * t * t + 0.9375
        }
        t -= 2.625 / d1
        return n1 * t * t + 0.984375
    }

    private func applyNamedEasing(_ easing: AnimationEasing, _ t: Double) -> Double {
        let pi = acos(-1.0)
        switch easing {
        case .linear:
            return t
        case .easeInSine:
            return 1.0 - cos(t * pi / 2.0)
        case .easeOutSine:
            return sin(t * pi / 2.0)
        case .easeInOutSine:
            return -(cos(pi * t) - 1.0) / 2.0
        case .easeInQuad:
            return t * t
        case .easeOutQuad:
            return 1.0 - (1.0 - t) * (1.0 - t)
        case .easeInOutQuad:
            return t < 0.5 ? 2.0 * t * t : 1.0 - pow(-2.0 * t + 2.0, 2) / 2.0
        case .easeInCubic:
            return t * t * t
        case .easeOutCubic:
            return 1.0 - pow(1.0 - t, 3)
        case .easeInOutCubic:
            return t < 0.5 ? 4.0 * t * t * t : 1.0 - pow(-2.0 * t + 2.0, 3) / 2.0
        case .easeInQuart:
            return pow(t, 4)
        case .easeOutQuart:
            return 1.0 - pow(1.0 - t, 4)
        case .easeInOutQuart:
            return t < 0.5 ? 8.0 * pow(t, 4) : 1.0 - pow(-2.0 * t + 2.0, 4) / 2.0
        case .easeInQuint:
            return pow(t, 5)
        case .easeOutQuint:
            return 1.0 - pow(1.0 - t, 5)
        case .easeInOutQuint:
            return t < 0.5 ? 16.0 * pow(t, 5) : 1.0 - pow(-2.0 * t + 2.0, 5) / 2.0
        case .easeInExpo:
            return t <= 0.0 ? 0.0 : pow(2.0, 10.0 * t - 10.0)
        case .easeOutExpo:
            return t >= 1.0 ? 1.0 : 1.0 - pow(2.0, -10.0 * t)
        case .easeInOutExpo:
            if t <= 0.0 { return 0.0 }
            if t >= 1.0 { return 1.0 }
            return t < 0.5 ? pow(2.0, 20.0 * t - 10.0) / 2.0
                : (2.0 - pow(2.0, -20.0 * t + 10.0)) / 2.0
        case .easeInCirc:
            return 1.0 - sqrt(1.0 - pow(t, 2))
        case .easeOutCirc:
            return sqrt(1.0 - pow(t - 1.0, 2))
        case .easeInOutCirc:
            return t < 0.5 ? (1.0 - sqrt(1.0 - pow(2.0 * t, 2))) / 2.0
                : (sqrt(1.0 - pow(-2.0 * t + 2.0, 2)) + 1.0) / 2.0
        case .easeInBack:
            let c1 = 1.70158
            let c3 = c1 + 1.0
            return c3 * t * t * t - c1 * t * t
        case .easeOutBack:
            let c1 = 1.70158
            let c3 = c1 + 1.0
            let x = t - 1.0
            return 1.0 + c3 * x * x * x + c1 * x * x
        case .easeInOutBack:
            let c1 = 1.70158 * 1.525
            let c2 = c1 + 1.0
            return t < 0.5 ? (pow(2.0 * t, 2) * ((c2 + 1.0) * 2.0 * t - c2)) / 2.0
                : (pow(2.0 * t - 2.0, 2) * ((c2 + 1.0) * (2.0 * t - 2.0) + c2) + 2.0) / 2.0
        case .easeInElastic:
            let c4 = 2.0 * pi / 3.0
            if t <= 0.0 { return 0.0 }
            if t >= 1.0 { return 1.0 }
            return -pow(2.0, 10.0 * t - 10.0) * sin((t * 10.0 - 10.75) * c4)
        case .easeOutElastic:
            let c4 = 2.0 * pi / 3.0
            if t <= 0.0 { return 0.0 }
            if t >= 1.0 { return 1.0 }
            return pow(2.0, -10.0 * t) * sin((t * 10.0 - 0.75) * c4) + 1.0
        case .easeInOutElastic:
            let c5 = 2.0 * pi / 4.5
            if t <= 0.0 { return 0.0 }
            if t >= 1.0 { return 1.0 }
            return t < 0.5 ? -(pow(2.0, 20.0 * t - 10.0) * sin((20.0 * t - 11.125) * c5)) / 2.0
                : (pow(2.0, -20.0 * t + 10.0) * sin((20.0 * t - 11.125) * c5)) / 2.0 + 1.0
        case .easeInBounce:
            return 1.0 - easeOutBounce(1.0 - t)
        case .easeOutBounce:
            return easeOutBounce(t)
        case .easeInOutBounce:
            return t < 0.5 ? (1.0 - easeOutBounce(1.0 - 2.0 * t)) / 2.0
                : (1.0 + easeOutBounce(2.0 * t - 1.0)) / 2.0
        case .snappy:
            let curve = [0.05, 0.9, 0.1, 1.05]
            var low = 0.0
            var high = 1.0
            for _ in 0..<24 {
                let mid = (low + high) / 2.0
                if calculateBezierCurveFor(mid, curve).x < t {
                    low = mid
                } else {
                    high = mid
                }
            }
            return calculateBezierCurveFor((low + high) / 2.0, curve).y
        }
    }

    package func findAnimationCurveFor(_ t: Double, _ curve: AnimationCurve?) -> Double {
        animationCurveEase(curve, t)
    }

    package func findAnimationCurveAt(_ t: Double, _ type: AnimationAction) -> Double {
        animationCurveEase(animationCurveForType(type), t)
    }

    package func requestFreshAllMonitors() {
        for m in monitors {
            system.outputScheduleFrame(m)   // not in mango: the port's wlr_output_schedule_frame
        }
    }
}

/// mango enum animation_curve_type (config/parse.h)
public enum AnimationCurveType: Equatable, Sendable {
    case bezier, named
}

/// mango enum animation_easing (config/parse.h)
public enum AnimationEasing: Equatable, Sendable {
    case linear
    case easeInSine, easeOutSine, easeInOutSine
    case easeInQuad, easeOutQuad, easeInOutQuad
    case easeInCubic, easeOutCubic, easeInOutCubic
    case easeInQuart, easeOutQuart, easeInOutQuart
    case easeInQuint, easeOutQuint, easeInOutQuint
    case easeInExpo, easeOutExpo, easeInOutExpo
    case easeInCirc, easeOutCirc, easeInOutCirc
    case easeInBack, easeOutBack, easeInOutBack
    case easeInElastic, easeOutElastic, easeInOutElastic
    case easeInBounce, easeOutBounce, easeInOutBounce
    case snappy
}

/// mango AnimationCurve (config/parse.h)
public struct AnimationCurve: Equatable, Sendable {
    public var type: AnimationCurveType = .bezier
    public var easing: AnimationEasing = .linear
    public var bezier: [Double] = [0, 0, 0, 0]
    public init() {}
    // not in mango: set_bezier_curve's values as an initialiser
    public init(bezier: [Double]) { self.bezier = bezier }
}
