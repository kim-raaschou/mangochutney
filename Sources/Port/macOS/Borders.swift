import AppKit
import Mango

/// Not in mango: the ring is drawn *around* the window (macOS windows cannot be clipped
/// like mango clips Wayland surfaces), so its inner edge follows the window's own
/// rounded corners (chutney_style, PortHooks.borderRadius).
public enum BorderGeometry {
    /// Corner radius of standard macOS windows, measured on macOS 27 (16 pt) and
    /// Sonoma/Sequoia (10 pt). The ring follows it; macOS draws the corners.
    public static var cornerRadius: CGFloat {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 16 : 10
    }

    /// Frame of the overlay window: the window frame grown by the border width.
    public static func overlayFrame(window: CGRect, width: CGFloat) -> CGRect {
        window.insetBy(dx: -width, dy: -width)
    }

    /// Radius of the ring's outer edge (a layer border is drawn inward from it), so its
    /// inner edge has the window's radius.
    public static func outerRadius(corner: CGFloat, width: CGFloat) -> CGFloat {
        corner > 0 ? corner + width : 0
    }
}

/// The ring is the view's layer border: Core Animation renders it in the window
/// server, so the window has no backing store. (Drawing it in `draw(_:)` gave every
/// border a buffer the size of its window, ~40 MB for a large Retina window.)
final class BorderView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var isOpaque: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    private var splitLayer: CALayer?

    /// `split`: one side of the ring, between the rounded corners, in its own colour
    /// (mango's split indicator).
    func set(color: NSColor, width: CGFloat, radius: CGFloat, split: (side: BorderSpec.SplitSide, color: NSColor)? = nil) {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.borderColor = color.cgColor
        layer.borderWidth = width
        layer.cornerRadius = radius
        if let split {
            let s = splitLayer ?? CALayer()
            if splitLayer == nil { layer.addSublayer(s); splitLayer = s }
            s.backgroundColor = split.color.cgColor
            let b = bounds
            s.frame = split.side == .bottom
                ? CGRect(x: radius, y: 0, width: max(0, b.width - 2 * radius), height: width)   // AppKit: y up
                : CGRect(x: b.width - width, y: radius, width: width, height: max(0, b.height - 2 * radius))
        } else {
            splitLayer?.removeFromSuperlayer()
            splitLayer = nil
        }
        CATransaction.commit()
    }
}

/// Border overlays: one transparent, click-through NSWindow per managed
/// window, ordered directly above it in the window server's z-order. They are only
/// re-ordered when created and on `restack()` (focus, activation), not on every
/// update: during an animation `update` runs every frame.
@MainActor
public final class BorderManager {
    private var windows: [CGWindowID: (NSWindow, BorderView, BorderSpec)] = [:]

    public init() {}

    public func update(_ specs: [BorderSpec]) {
        var seen: Set<CGWindowID> = []
        for spec in specs {
            seen.insert(spec.id)
            if let (win, view, old) = windows[spec.id] {
                // Also when only the overlay moved: macOS relocates our windows itself when
                // a display goes away, and the primary screen's height (the flip) changes.
                if old != spec || Self.distance(win.frame, Self.appKitFrame(spec)) > 0.5 {
                    apply(spec, to: win, view: view)
                    windows[spec.id] = (win, view, spec)
                }
            } else {
                let win = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
                win.isOpaque = false
                win.backgroundColor = .clear
                win.hasShadow = false
                win.ignoresMouseEvents = true
                win.level = .normal
                win.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone, .transient]
                win.isReleasedWhenClosed = false
                win.animationBehavior = .none
                let view = BorderView(frame: .zero)
                win.contentView = view
                apply(spec, to: win, view: view)
                win.orderFrontRegardless()
                win.order(.above, relativeTo: Int(spec.id))
                windows[spec.id] = (win, view, spec)
            }
        }
        for id in windows.keys where !seen.contains(id) {
            windows[id]?.0.orderOut(nil)
            windows[id]?.0.close()
            windows.removeValue(forKey: id)
        }
    }

    /// Re-stack above the target (call after focus changes): those of `ids` (nil: all) that are
    /// not in place already. Each order waits for the window server, about 2 ms.
    public func restack(_ ids: Set<CGWindowID>? = nil, inPlace: (CGWindowID, CGWindowID) -> Bool = { _, _ in false }) {
        for (id, (win, _, _)) in windows where ids?.contains(id) ?? true {
            if !inPlace(CGWindowID(truncatingIfNeeded: win.windowNumber), id) { win.order(.above, relativeTo: Int(id)) }
        }
    }

    public func removeAll() {
        for (_, (win, _, _)) in windows { win.orderOut(nil); win.close() }
        windows.removeAll()
    }

    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }

    private static func appKitFrame(_ spec: BorderSpec) -> CGRect {
        let h = Screens.primaryHeight
        let outer = BorderGeometry.overlayFrame(window: spec.frame, width: spec.width)
        return CGRect(x: outer.minX, y: h - outer.maxY, width: outer.width, height: outer.height)
    }

    private func apply(_ spec: BorderSpec, to win: NSWindow, view: BorderView) {
        win.setFrame(Self.appKitFrame(spec), display: false)
        func ns(_ c: RGBA) -> NSColor { NSColor(red: c.r, green: c.g, blue: c.b, alpha: c.a) }
        view.set(color: ns(spec.color), width: spec.width,
                 radius: BorderGeometry.outerRadius(corner: spec.radius, width: spec.width),
                 split: spec.split.map { ($0.side, ns($0.color)) })
    }
}
