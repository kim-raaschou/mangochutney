import CoreGraphics
import Mango

public enum HideCorner { case bottomLeft, bottomRight }

public enum Hider {
    public static func corner(for screen: CGRect, others: [CGRect]) -> HideCorner {
        func contains(_ p: CGPoint) -> Int { others.contains { $0.contains(p) } ? 1 : 0 }
        let xOff = screen.width * 0.1, yOff = screen.height * 0.1
        let br = screen.bottomRight, bl = screen.bottomLeft
        let brScore = contains(br + CGPoint(x: 2, y: -yOff)) + contains(br + CGPoint(x: -xOff, y: 2))
            + 10 * contains(br + CGPoint(x: 2, y: 2))
        let blScore = contains(bl + CGPoint(x: -2, y: -yOff)) + contains(bl + CGPoint(x: xOff, y: 2))
            + 10 * contains(bl + CGPoint(x: -2, y: 2))
        return blScore < brScore ? .bottomLeft : .bottomRight
    }

    public static func parkedOrigin(size: CGSize, workArea: CGRect, corner: HideCorner) -> CGPoint {
        switch corner {
        case .bottomRight:
            return CGPoint(x: workArea.maxX - 1, y: workArea.maxY - 1)
        case .bottomLeft:
            return CGPoint(x: workArea.minX + 1 - size.width, y: workArea.maxY - 1)
        }
    }

    public static func isParked(_ frame: CGRect, in screen: CGRect) -> Bool {
        let visible = frame.intersection(screen)
        if visible.isNull { return true }
        return visible.width <= 3 || visible.height <= 3
    }
}
