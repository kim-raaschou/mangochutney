import Foundation

public struct DecorateStyle: Equatable, Sendable {
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

    public static let mangoGroupBar = DecorateStyle(
        fontDesc: "monospace Bold 13", fg: "0xc0caf5ff", bg: "0x1d2021ff", focusFg: "0x9ece6aff", focusBg: "0x3c3836ff",
        border: "0x3b4261ff", borderWidth: 4, cornerRadius: 5, paddingX: 0, paddingY: 0)
    public static var mangoTabBar: DecorateStyle {
        var s = mangoGroupBar
        s.focusFgColor = parseColor("0x7aa2f7ff")
        return s
    }
    public static var mangoTitleMessageBar: DecorateStyle {
        var s = mangoGroupBar
        s.borderWidth = 0
        s.cornerRadius = 15
        return s
    }
    public static let mangoJumpLabel = DecorateStyle(
        fontDesc: "monospace Bold 16", fg: "0xc4939dff", bg: "0x323232ff", focusFg: "0xeda6b4ff", focusBg: "0x4e453cff",
        border: "0x8baa9bff", borderWidth: 4, cornerRadius: 5, paddingX: 10, paddingY: 10)

    public func setValueDefault(from d: DecorateStyle) -> DecorateStyle {
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

public struct FontDescription: Equatable, Sendable {
    public enum Weight: Int, Sendable { case thin = 100, ultraLight = 200, light = 300, regular = 400, medium = 500,
                                             semiBold = 600, bold = 700, ultraBold = 800, heavy = 900 }
    public var families: [String]
    public var weight: Weight = .regular
    public var italic = false
    public var pixelSize: Double = 13.0 * 96 / 72

    public init(_ desc: String) {
        var words = desc.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        if let last = words.last {
            if last.hasSuffix("px"), let px = Double(last.dropLast(2)) {
                pixelSize = px
                words.removeLast()
            } else if let pt = Double(last) {
                pixelSize = pt * 96 / 72
                words.removeLast()
            }
        }
        let weights: [String: Weight] = [
            "thin": .thin, "ultra-light": .ultraLight, "extra-light": .ultraLight, "light": .light,
            "book": .regular, "regular": .regular, "normal": .regular, "medium": .medium,
            "semi-bold": .semiBold, "demi-bold": .semiBold, "bold": .bold, "ultra-bold": .ultraBold,
            "extra-bold": .ultraBold, "heavy": .heavy, "black": .heavy,
        ]
        while let w = words.last?.lowercased() {
            if let weight = weights[w] { self.weight = weight } else if w == "italic" || w == "oblique" { italic = true }
            else if ["condensed", "expanded", "small-caps", "semi-condensed", "semi-expanded"].contains(w) {}
            else { break }
            words.removeLast()
        }
        families = words.joined(separator: " ").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
