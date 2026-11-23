import AppKit
import Mango

/// Where the port's borders are drawn: AppKit overlays (BorderManager), or the tests' record.
@MainActor
public protocol BorderDrawing: AnyObject {
    /// The borders shown now; a window with none has its border taken away.
    func update(_ specs: [BorderSpec])
    /// The window is gone.
    func forget(_ id: CGWindowID)
    /// The borders put back above their windows, unless `inPlace` says one stands right already.
    func restack(_ ids: Set<CGWindowID>?, inPlace: (CGWindowID, CGWindowID) -> Bool)
}

public enum BorderGeometry {
    public static var cornerRadius: CGFloat {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 16 : 10
    }

    public static func overlayFrame(window: CGRect, width: CGFloat) -> CGRect {
        window.insetBy(dx: -width, dy: -width)
    }

    public static func outerRadius(corner: CGFloat, width: CGFloat) -> CGFloat {
        corner > 0 ? corner + width : 0
    }
}

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
                ? CGRect(x: radius, y: 0, width: max(0, b.width - 2 * radius), height: width)
                : CGRect(x: b.width - width, y: radius, width: width, height: max(0, b.height - 2 * radius))
        } else {
            splitLayer?.removeFromSuperlayer()
            splitLayer = nil
        }
        CATransaction.commit()
    }
}

@MainActor
public final class BorderManager: BorderDrawing {
    /// Each window's overlay; with no spec it is ordered out and kept for when the window is shown again
    /// (a new NSWindow costs the window server several round trips), till the window is gone (forget).
    private var windows: [CGWindowID: (NSWindow, BorderView, BorderSpec?)] = [:]

    public init() {}

    public func update(_ specs: [BorderSpec]) {
        var seen: Set<CGWindowID> = []
        for spec in specs {
            let f = spec.frame
            guard !f.isNull, f.minX.isFinite, f.minY.isFinite, f.width.isFinite, f.height.isFinite else { continue }
            seen.insert(spec.id)
            if let (win, view, old) = windows[spec.id] {
                if old != spec || !win.isVisible || Self.distance(win.frame, Self.appKitFrame(spec)) > 0.5 {
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
                let content = NSView(frame: .zero)
                content.wantsLayer = true
                content.layer?.masksToBounds = true
                content.addSubview(view)
                win.contentView = content
                apply(spec, to: win, view: view)
                windows[spec.id] = (win, view, spec)
            }
        }
        for (id, (win, view, old)) in windows where !seen.contains(id) && old != nil {
            win.orderOut(nil)
            windows[id] = (win, view, nil)
        }
    }

    /// The window is gone: its overlay is closed.
    public func forget(_ id: CGWindowID) {
        guard let (win, _, _) = windows.removeValue(forKey: id) else { return }
        win.orderOut(nil)
        win.close()
    }

    public func restack(_ ids: Set<CGWindowID>? = nil, inPlace: (CGWindowID, CGWindowID) -> Bool = { _, _ in false }) {
        for (id, (win, _, spec)) in windows where spec != nil && (ids?.contains(id) ?? true) {
            if !inPlace(CGWindowID(truncatingIfNeeded: win.windowNumber), id) { win.order(.above, relativeTo: Int(id)) }
        }
    }

    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }

    /// The overlay: the border's box, cut at the monitor's edge where mango cuts it.
    private static func appKitFrame(_ spec: BorderSpec) -> CGRect {
        let outer = BorderGeometry.overlayFrame(window: spec.frame, width: spec.width)
        return appKit(spec.clip.map { outer.intersection($0) } ?? outer)
    }

    private static func appKit(_ r: CGRect) -> CGRect {
        let h = Screens.primaryHeight
        return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    private func apply(_ spec: BorderSpec, to win: NSWindow, view: BorderView) {
        let frame = Self.appKitFrame(spec)
        win.setFrame(frame.isNull ? .zero : frame, display: false)
        let outer = Self.appKit(BorderGeometry.overlayFrame(window: spec.frame, width: spec.width))
        view.frame = CGRect(x: outer.minX - frame.minX, y: outer.minY - frame.minY, width: outer.width, height: outer.height)
        func ns(_ c: RGBA) -> NSColor { NSColor(red: c.r, green: c.g, blue: c.b, alpha: c.a) }
        view.set(color: ns(spec.color), width: spec.width,
                 radius: BorderGeometry.outerRadius(corner: spec.radius, width: spec.width),
                 split: spec.split.map { ($0.side, ns($0.color)) })
        // shown last: a kept overlay still has the frame and look it was hidden with
        if frame.isNull || frame.isEmpty {
            if win.isVisible { win.orderOut(nil) }
        } else if !win.isVisible {
            win.orderFrontRegardless()
            win.order(.above, relativeTo: Int(spec.id))
        }
    }
}
