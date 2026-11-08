import SwiftUI
import Mango

public enum PortAccent {
    public static func color(_ config: Config) -> Color { Color(config.focuscolor) }
}

extension Color {
    public init(_ c: RGBA) {
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }
}
