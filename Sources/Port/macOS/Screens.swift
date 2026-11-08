import AppKit
import CoreGraphics
import Mango

public enum Screens {
    public static var primaryHeight: CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?.frame.height ?? 0
    }

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
            let ident = DisplayIdentity.of(id)
            var screen = Screen(displayID: id,
                          name: s.localizedName,
                          frame: flip(s.frame, primaryHeight: h),
                          workArea: flip(s.visibleFrame, primaryHeight: h),
                          scale: s.backingScaleFactor,
                          isMain: s.frame.origin == .zero,
                          refresh: Int32(s.maximumFramesPerSecond * 1000),
                          make: ident?.make, model: ident?.model, serial: ident?.serial)
            screen.transform = Int32(CGDisplayRotation(id) / 90) % 4
            return screen
        }
        .sorted { a, b in a.frame.minX != b.frame.minX ? a.frame.minX < b.frame.minX : a.frame.minY < b.frame.minY }
    }

    public static var mouseLocation: CGPoint { flip(NSEvent.mouseLocation) }
}
