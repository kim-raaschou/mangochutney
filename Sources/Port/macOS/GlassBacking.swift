import AppKit

@MainActor
final class GlassBacking: NSView {
    private let effect: NSView

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

    func addContent(_ view: NSView) {
        view.autoresizingMask = [.width, .height]
        view.frame = bounds
        addSubview(view)
    }

    var cornerRadius: CGFloat {
        get { layer?.cornerRadius ?? 0 }
        set {
            layer?.cornerRadius = newValue
            if #available(macOS 26.0, *), let g = effect as? NSGlassEffectView { g.cornerRadius = newValue }
        }
    }

    var materialHidden: Bool {
        get { effect.isHidden }
        set { effect.isHidden = newValue }
    }
}
