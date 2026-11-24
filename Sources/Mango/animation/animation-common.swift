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

/// mango BAKED_POINTS_COUNT (animation/common.h).
let BAKED_POINTS_COUNT: Int32 = 256

extension MangoServer {
    package func calculateAnimationCurveAt(_ t: Double, _ type: AnimationAction) -> DVec2 {
        var point = DVec2()
        let animationCurve: BezierCurve
        if type == .move {
            animationCurve = config.animationCurveMove
        } else if type == .open {
            animationCurve = config.animationCurveOpen
        } else if type == .tag {
            animationCurve = config.animationCurveTag
        } else if type == .close {
            animationCurve = config.animationCurveClose
        } else if type == .focus {
            animationCurve = config.animationCurveFocus
        } else {
            // not in mango: no animation_curve_opafadein or animation_curve_opafadeout (no fades on macOS)
            animationCurve = config.animationCurveMove
        }

        point.x = 3 * t * (1 - t) * (1 - t) * animationCurve.x1 +
            3 * t * t * (1 - t) * animationCurve.x2 + t * t * t

        point.y = 3 * t * (1 - t) * (1 - t) * animationCurve.y1 +
            3 * t * t * (1 - t) * animationCurve.y2 + t * t * t

        return point
    }

    package func initBakedPoints() {
        func baked(_ type: AnimationAction) -> [DVec2] {
            (0..<BAKED_POINTS_COUNT).map { i in
                calculateAnimationCurveAt(Double(i) / Double(BAKED_POINTS_COUNT - 1), type)
            }
        }
        bakedPointsMove = baked(.move)
        bakedPointsOpen = baked(.open)
        bakedPointsTag = baked(.tag)
        bakedPointsClose = baked(.close)
        bakedPointsFocus = baked(.focus)
        // not in mango: no baked_points_opafadein or baked_points_opafadeout (no fades on macOS)
    }

    package func findAnimationCurveAt(_ t: Double, _ type: AnimationAction) -> Double {
        var down: Int32 = 0
        var up: Int32 = BAKED_POINTS_COUNT - 1

        var middle = (up + down) / 2
        let bakedPoints: [DVec2]
        if type == .move {
            bakedPoints = bakedPointsMove
        } else if type == .open {
            bakedPoints = bakedPointsOpen
        } else if type == .tag {
            bakedPoints = bakedPointsTag
        } else if type == .close {
            bakedPoints = bakedPointsClose
        } else if type == .focus {
            bakedPoints = bakedPointsFocus
        } else {
            bakedPoints = bakedPointsMove
        }

        while up - down != 1 {
            if bakedPoints[Int(middle)].x <= t {
                down = middle
            } else {
                up = middle
            }
            middle = (up + down) / 2
        }
        return bakedPoints[Int(up)].y
    }

    package func requestFreshAllMonitors() {
        for m in monitors {
            system.outputScheduleFrame(m)   // not in mango: the port's wlr_output_schedule_frame
        }
    }
}

// not in mango: an animation_curve_* option's double[4] as its four points
public struct BezierCurve: Equatable, Sendable {
    public var x1: Double, y1: Double, x2: Double, y2: Double
    public init(x1: Double, y1: Double, x2: Double, y2: Double) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
    }
    public static let mangoDefault = BezierCurve(x1: 0.46, y1: 1.0, x2: 0.29, y2: 0.99)
    public static let linear = BezierCurve(x1: 0, y1: 0, x2: 1, y2: 1)
}
