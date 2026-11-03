import SwiftUI
import Mango

/// Port extension: not in mango. The colour the port's own windows mark with (the palettes'
/// selection, the menu panel's values): mango's focus_color (with chutney_style the accent
/// colour, from chutney_theme.conf).
public enum PortAccent {
    public static func color(_ config: Config) -> Color { Color(config.focuscolor) }
}

extension Color {
    /// A mango colour (focus_color, root_color, …).
    public init(_ c: RGBA) {
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }
}
