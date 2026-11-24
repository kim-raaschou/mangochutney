import Foundation
import CoreGraphics

// not in mango: mango's wl_list helpers (common/util.c) on server.clients, which is an array here
package extension MangoServer {
    /// mango wl_list_safe_reinsert_prev (common/util.c): l2 goes just before l1.
    func wlListSafeReinsertPrev(_ l1: Client, _ l2: Client) {
        if l1 === l2 { return }
        guard let i1 = clients.firstIndex(where: { $0 === l1 }) else { return }
        if i1 > 0 && clients[i1 - 1] === l2 { return }

        clients.removeAll { $0 === l2 }
        clients.insert(l2, at: clients.firstIndex(where: { $0 === l1 })!)
    }

    /// mango wl_list_safe_reinsert_next (common/util.c): l2 goes just after l1.
    func wlListSafeReinsertNext(_ l1: Client, _ l2: Client) {
        if l1 === l2 { return }
        guard let i1 = clients.firstIndex(where: { $0 === l1 }) else { return }
        if i1 + 1 < clients.count && clients[i1 + 1] === l2 { return }

        clients.removeAll { $0 === l2 }
        clients.insert(l2, at: clients.firstIndex(where: { $0 === l1 })! + 1)
    }

    /// mango wl_list_swap (common/util.c).
    func wlListSwap(_ a: Client, _ b: Client) {
        guard let i = clients.firstIndex(where: { $0 === a }), let j = clients.firstIndex(where: { $0 === b }) else { return }
        clients.swapAt(i, j)
    }
}

/// mango regex_match (common/util.c)
// not in mango: ICU's regex (NSRegularExpression) stands for PCRE2; its error has no offset, and the
// empty pattern, which ICU refuses, is PCRE2's "(?:)"
func regexMatch(_ pattern: String?, _ str: String?) -> Bool {
    guard let pattern, let str else {
        return false
    }

    let re: NSRegularExpression
    do {
        re = try NSRegularExpression(pattern: pattern.isEmpty ? "(?:)" : pattern)
    } catch {
        mangoError(false, .error, "PCRE2 error: \(error.localizedDescription)\n")
        return false
    }

    return re.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)) != nil
}

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
