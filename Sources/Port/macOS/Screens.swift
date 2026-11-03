import AppKit
import CoreGraphics
import Mango


public enum Screens {
    /// Height of the screen whose frame origin is (0,0); used for the y flip.
    public static var primaryHeight: CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?.frame.height ?? 0
    }

    /// NSScreen (bottom-left origin) -> AX rect (top-left origin).
    public static func flip(_ r: CGRect, primaryHeight h: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    public static func flip(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    public static func all() -> [Screen] {
        let h = primaryHeight
        return NSScreen.screens.map { s in
            let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return Screen(displayID: id,
                          name: s.localizedName,
                          frame: flip(s.frame, primaryHeight: h),
                          workArea: flip(s.visibleFrame, primaryHeight: h),
                          scale: s.backingScaleFactor,
                          isMain: s.frame.origin == .zero,
                          refresh: Int32(s.maximumFramesPerSecond * 1000))
        }
        // Sort left-to-right, then top-to-bottom, so "left"/"right" monitors are stable.
        .sorted { a, b in a.frame.minX != b.frame.minX ? a.frame.minX < b.frame.minX : a.frame.minY < b.frame.minY }
    }

    /// Mouse location in AX coordinates.
    public static var mouseLocation: CGPoint { flip(NSEvent.mouseLocation) }
}
