import AppKit

/// Not in mango. The system's material behind one of the port's floating panels
/// (chutney_style): Liquid Glass on macOS 26 and later, the older blur before it. The
/// panel's content is added above the material (`addContent`), never as the glass's own
/// content view, so the material can be hidden on its own where a mango colour replaces
/// it (the title message bar's focus_bg_color, a plain tab strip). Neutral, never tinted:
/// the accent is on what stands on it.
@MainActor
final class GlassBacking: NSView {
    private let effect: NSView

    /// `material`: what macOS before 26 draws.
    init(material: NSVisualEffectView.Material, cornerRadius: CGFloat = 0) {
        if #available(macOS 26.0, *) {
            let g = NSGlassEffectView()
            g.style = .regular
            g.cornerRadius = cornerRadius
            effect = g
        } else {
            let v = NSVisualEffectView()
            v.material = material
            v.blendingMode = .behindWindow
            v.state = .active
            effect = v
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = cornerRadius
        effect.autoresizingMask = [.width, .height]
        effect.frame = bounds
        addSubview(effect)
    }

    required init?(coder: NSCoder) { nil }

    /// The content, above the material, following the backing's size.
    func addContent(_ view: NSView) {
        view.autoresizingMask = [.width, .height]
        view.frame = bounds
        addSubview(view)
    }

    /// Rounds the material and clips the content.
    var cornerRadius: CGFloat {
        get { layer?.cornerRadius ?? 0 }
        set {
            layer?.cornerRadius = newValue
            if #available(macOS 26.0, *), let g = effect as? NSGlassEffectView { g.cornerRadius = newValue }
        }
    }

    /// The material alone hidden (the content stays): a mango colour stands in its place.
    var materialHidden: Bool {
        get { effect.isHidden }
        set { effect.isHidden = newValue }
    }
}
