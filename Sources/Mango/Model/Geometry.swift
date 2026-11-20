import Foundation
import CoreGraphics

public typealias ClientID = UInt32

public extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
    var topLeft: CGPoint { CGPoint(x: minX, y: minY) }
    var bottomRight: CGPoint { CGPoint(x: maxX, y: maxY) }
    var bottomLeft: CGPoint { CGPoint(x: minX, y: maxY) }

    /// Not in mango: a geometry helper.
    func insetBy(horizontal: CGFloat, vertical: CGFloat) -> CGRect {
        CGRect(x: minX + horizontal, y: minY + vertical,
               width: max(1, width - 2 * horizontal), height: max(1, height - 2 * vertical))
    }

    /// Not in mango: a geometry helper.
    func overlapArea(_ other: CGRect) -> CGFloat {
        let i = intersection(other)
        return i.isNull ? 0 : i.width * i.height
    }

    /// Not in mango: whole-point rounding of macOS frames.
    func rounded() -> CGRect {
        func up(_ v: CGFloat) -> CGFloat { (v + 0.5).rounded(.down) }
        let x = up(minX), y = up(minY)
        return CGRect(x: x, y: y, width: up(maxX) - x, height: up(maxY) - y)
    }
}

public extension CGPoint {
    /// Not in mango: a geometry helper.
    func distance(to p: CGPoint) -> CGFloat {
        let dx = x - p.x, dy = y - p.y
        return (dx * dx + dy * dy).squareRoot()
    }
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
}

public struct RGBA: Equatable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public var hexString: String {
        String(format: "0x%02x%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))
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
    public var extremes: (low: Double, high: Double) {
        let a = 3 * y1 - 3 * y2 + 1, b = 3 * y2 - 6 * y1, c = 3 * y1
        var turns: [Double] = []
        if abs(a) < 1e-12 {
            if abs(b) > 1e-12 { turns = [-c / (2 * b)] }
        } else {
            let d = 4 * b * b - 12 * a * c
            if d >= 0 { turns = [(-2 * b + d.squareRoot()) / (6 * a), (-2 * b - d.squareRoot()) / (6 * a)] }
        }
        let ys = turns.filter { $0 > 0 && $0 < 1 }.map { calculateAnimationCurveAt($0, y1, y2) }
        return (ys.reduce(0, min), ys.reduce(1, max))
    }
}
