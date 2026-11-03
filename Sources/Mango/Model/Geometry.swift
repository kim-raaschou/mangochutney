import Foundation
import CoreGraphics

public typealias ClientID = UInt32

public enum Direction: String, CaseIterable, Sendable {
    case left, right, up, down

    public init?(mangoName: String) {
        self.init(rawValue: mangoName.lowercased())
    }

    public var isHorizontal: Bool { self == .left || self == .right }
    public var opposite: Direction {
        switch self {
        case .left: return .right
        case .right: return .left
        case .up: return .down
        case .down: return .up
        }
    }
}

public enum NextPrev: Sendable {
    case next, prev
    public init(mangoArg: String) {
        self = mangoArg.lowercased() == "next" ? .next : .prev
    }
}

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

// not in mango: the color as RGBA, nil where mango returns -1
public func parseColor(_ hexStr: String) -> RGBA? {
    var s = Substring(hexStr.lowercased()).drop { $0 == " " || $0 == "\t" }
    if s.hasPrefix("0x") { s = s.dropFirst(2) }
    guard s.allSatisfy(\.isHexDigit) else { return nil }
    let v = s.isEmpty ? 0 : UInt64(s, radix: 16) ?? UInt64(Int64.max)
    return RGBA(r: Double((v >> 24) & 0xff) / 255, g: Double((v >> 16) & 0xff) / 255,
                b: Double((v >> 8) & 0xff) / 255, a: Double(v & 0xff) / 255)
}

// not in mango: the numbers returned, nil where mango returns -1
public func parseDoubleArray(_ input: String, _ maxCount: Int) -> [Double]? {
    var output: [Double] = []
    for token in input.split(separator: ",") where output.count < maxCount {
        let t = token.trimmingCharacters(in: .whitespaces)
        guard t.range(of: #"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$"#, options: .regularExpression) != nil,
              let val = Double(t), val.isFinite, val >= 0 else { return nil }
        output.append(val)
    }
    return output
}
