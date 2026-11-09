import CoreGraphics
import Mango

/// Port extension: not in mango. chutney_macos_appearance: what no `*_decorate_*` key sets is
/// drawn the macOS way, and the border follows the window's own corners.
enum MacOSAppearance {
    /// A bar's look: mango's, or with chutney_macos_appearance only the keys set.
    static func bar(_ mango: DecorateStyle, set: DecorateStyle, _ config: Config) -> DecorateStyle {
        config.chutneyMacOSAppearance ? set : mango
    }

    static func borders(_ specs: [BorderSpec], _ config: Config) -> [BorderSpec] {
        guard config.chutneyMacOSAppearance else { return specs }
        return specs.map { var s = $0; s.radius = BorderGeometry.cornerRadius; return s }
    }
}
