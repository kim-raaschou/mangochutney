import AppKit
import Mango

@MainActor
struct JumpLabelLook {
    var size: CGSize
    var font: NSFont
    var text: CGColor
    var background: CGColor
    var border: CGColor
    var borderWidth: CGFloat
    var cornerRadius: CGFloat

    init(_ label: String, decorate d: DecorateStyle, side: CGFloat, ring: CGColor) {
        func cg(_ c: RGBA) -> CGColor { CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a) }
        let mangoSized = d.fontDesc != nil || d.paddingX != nil || d.paddingY != nil
        font = d.fontDesc.map { decorateFont(FontDescription($0)) } ?? .boldSystemFont(ofSize: side * 0.53)
        borderWidth = d.borderWidth.map { CGFloat($0) } ?? (side >= 40 ? 2 : 1)
        if mangoSized {
            let t = (label as NSString).size(withAttributes: [.font: font])
            size = CGSize(width: ceil(t.width) + 2 * CGFloat(d.paddingX ?? 10) + 2 * borderWidth,
                          height: ceil(t.height) + 2 * CGFloat(d.paddingY ?? 10) + 2 * borderWidth)
        } else {
            size = CGSize(width: side, height: side)
        }
        text = d.fgColor.map(cg) ?? NSColor.white.cgColor
        background = d.bgColor.map(cg) ?? NSColor(calibratedWhite: 0.08, alpha: 0.9).cgColor
        border = d.borderColor.map(cg) ?? ring
        cornerRadius = d.cornerRadius.map { CGFloat($0) } ?? min(size.width, size.height) * 0.19
    }

    var textFrame: CGRect {
        let h = ceil(font.ascender - font.descender)
        return CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
    }
}
