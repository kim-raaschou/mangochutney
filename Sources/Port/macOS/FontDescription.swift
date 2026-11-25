import Foundation

/// The font description the *_decorate_font_desc keys give, read as pango_font_description_from_string reads it
/// (family list, style words, size in points or px), for the port's NSFont.
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
