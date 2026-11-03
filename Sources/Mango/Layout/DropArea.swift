import Foundation
import CoreGraphics

public enum DropDirection: Sendable { case none, left, right, up, down }

public enum DropArea {
    public static func clientSetDropArea(layout: LayoutKind, target: CGRect, at p: CGPoint, isMaster: Bool, tiled: Int,
                               dwindleSimpleSplit: Bool, dwindleSplitRatio: Double) -> (DropDirection, CGRect) {
        let w = Int(target.width), h = Int(target.height)
        let x0 = Int(target.minX), y0 = Int(target.minY)
        let relX = Double(p.x - target.minX), relY = Double(p.y - target.minY)
        func box(_ x: Int, _ y: Int, _ bw: Int, _ bh: Int) -> CGRect { CGRect(x: x0 + x, y: y0 + y, width: bw, height: bh) }
        let leftHalf = (DropDirection.left, box(0, 0, w / 2, h)), rightHalf = (DropDirection.right, box(w / 2, 0, w / 2, h))
        let topHalf = (DropDirection.up, box(0, 0, w, h / 2)), bottomHalf = (DropDirection.down, box(0, h / 2, w, h / 2))
        let whole = (DropDirection.none, box(0, 0, w, h))

        switch layout {
        case .dwindle where dwindleSimpleSplit:
            let ratio = Float(dwindleSplitRatio)
            if w >= h {
                let a = Int(Float(w) * ratio)
                return relX < Double(w) * 0.5 ? (.left, box(0, 0, a, h)) : (.right, box(a, 0, w - a, h))
            }
            let a = Int(Float(h) * ratio)
            return relY < Double(h) * 0.5 ? (.up, box(0, 0, w, a)) : (.down, box(0, a, w, h - a))
        case .tile, .deck, .centerTile, .rightTile:
            if isMaster {
                if tiled == 1 { return relX < Double(w) * 0.5 ? leftHalf : rightHalf }
                return whole
            }
            return relY < Double(h) * 0.5 ? topHalf : bottomHalf
        case .verticalTile, .verticalDeck:
            if isMaster {
                if tiled == 1 { return relY < Double(h) * 0.5 ? topHalf : bottomHalf }
                return whole
            }
            return relX < Double(w) * 0.5 ? leftHalf : rightHalf
        default:
            let left = relX, right = Double(w) - relX, top = relY, bottom = Double(h) - relY
            if left <= right && left <= top && left <= bottom { return leftHalf }
            if right <= top && right <= bottom { return rightHalf }
            return top <= bottom ? topHalf : bottomHalf
        }
    }
}
