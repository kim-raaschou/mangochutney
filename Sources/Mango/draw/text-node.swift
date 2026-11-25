import Foundation

// not in mango: the text nodes (pango and cairo buffers, scene nodes, the font cache, jump labels and
// bar decorations, their geometry, close buttons and colours) are the port's, behind MangoBarDecoration
// and MangoJumpLabel (Sources/Boundary)

// not in mango: a nil field is one the config does not set
public struct DecorateDrawData: Equatable, Sendable {
    public var fontDesc: String?
    public var fgColor: RGBA?
    public var bgColor: RGBA?
    public var focusFgColor: RGBA?
    public var focusBgColor: RGBA?
    public var borderColor: RGBA?
    public var borderWidth: Int?
    public var cornerRadius: Int?
    public var paddingX: Int?
    public var paddingY: Int?

    public init() {}

    public init(fontDesc: String?, fg: String?, bg: String?, focusFg: String?, focusBg: String?, border: String?,
                borderWidth: Int?, cornerRadius: Int?, paddingX: Int?, paddingY: Int?) {
        self.fontDesc = fontDesc
        fgColor = fg.flatMap { parseColor($0) }
        bgColor = bg.flatMap { parseColor($0) }
        focusFgColor = focusFg.flatMap { parseColor($0) }
        focusBgColor = focusBg.flatMap { parseColor($0) }
        borderColor = border.flatMap { parseColor($0) }
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.paddingX = paddingX
        self.paddingY = paddingY
    }

    // not in mango: set_value_default's values for each bar, as styles
    public static let mangoGroupBar = DecorateDrawData(
        fontDesc: "monospace Bold 13", fg: "0xc0caf5ff", bg: "0x1d2021ff", focusFg: "0x9ece6aff", focusBg: "0x3c3836ff",
        border: "0x3b4261ff", borderWidth: 4, cornerRadius: 5, paddingX: 0, paddingY: 0)
    public static var mangoTabBar: DecorateDrawData {
        var s = mangoGroupBar
        s.focusFgColor = parseColor("0x7aa2f7ff")
        return s
    }
    public static var mangoTitleMessageBar: DecorateDrawData {
        var s = mangoGroupBar
        s.borderWidth = 0
        s.cornerRadius = 15
        return s
    }
    public static let mangoJumpLabel = DecorateDrawData(
        fontDesc: "monospace Bold 16", fg: "0xc4939dff", bg: "0x323232ff", focusFg: "0xeda6b4ff", focusBg: "0x4e453cff",
        border: "0x8baa9bff", borderWidth: 4, cornerRadius: 5, paddingX: 10, paddingY: 10)

    // not in mango: the fields the config sets, the others from d
    public func filled(from d: DecorateDrawData) -> DecorateDrawData {
        var s = self
        s.fontDesc = fontDesc ?? d.fontDesc
        s.fgColor = fgColor ?? d.fgColor
        s.bgColor = bgColor ?? d.bgColor
        s.focusFgColor = focusFgColor ?? d.focusFgColor
        s.focusBgColor = focusBgColor ?? d.focusBgColor
        s.borderColor = borderColor ?? d.borderColor
        s.borderWidth = borderWidth ?? d.borderWidth
        s.cornerRadius = cornerRadius ?? d.cornerRadius
        s.paddingX = paddingX ?? d.paddingX
        s.paddingY = paddingY ?? d.paddingY
        return s
    }
}
