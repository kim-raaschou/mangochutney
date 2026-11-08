import AppKit
import Mango

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
public final class BorderManager {
    private var windows: [CGWindowID: (NSWindow, BorderView, BorderSpec)] = [:]

    public init() {}

    public func update(_ specs: [BorderSpec]) {
        var seen: Set<CGWindowID> = []
        for spec in specs {
            let f = spec.frame
            guard !f.isNull, f.minX.isFinite, f.minY.isFinite, f.width.isFinite, f.height.isFinite else { continue }
            seen.insert(spec.id)
            if let (win, view, old) = windows[spec.id] {
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
