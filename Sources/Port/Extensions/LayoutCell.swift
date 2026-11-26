import SwiftUI
import Mango

/// A layout's cell, as the menu's layout panel draws it: the layout's icon (LayoutIcon), its name below
/// (or none), on a rounded box that is the theme's colour where the layout is the chosen one. The menu's
/// layout panel, the layout switcher and the workspace overview's cards draw their layouts with it.
public struct LayoutCell: View {
    let kind: LayoutKind
    let selected: Bool
    var tint: Color
    var iconSize = CGSize(width: 30, height: 20)
    /// The name's font; nil shows the icon alone.
    var nameFont: Font? = .system(size: 9, design: .monospaced)
    var spacing: CGFloat = 3
    var size: CGSize?
    var padding = EdgeInsets()
    var cornerRadius: CGFloat = 6
    var selectedFill: Color?
    var fill = Color.primary.opacity(0.06)
    var text = Color.primary
    var selectedText = Color.white

    public init(kind: LayoutKind, selected: Bool, tint: Color, iconSize: CGSize = CGSize(width: 30, height: 20),
                nameFont: Font? = .system(size: 9, design: .monospaced), spacing: CGFloat = 3, size: CGSize? = nil,
                padding: EdgeInsets = EdgeInsets(), cornerRadius: CGFloat = 6, selectedFill: Color? = nil,
                fill: Color = Color.primary.opacity(0.06), text: Color = .primary, selectedText: Color = .white) {
        self.kind = kind; self.selected = selected; self.tint = tint; self.iconSize = iconSize
        self.nameFont = nameFont; self.spacing = spacing; self.size = size; self.padding = padding
        self.cornerRadius = cornerRadius; self.selectedFill = selectedFill; self.fill = fill
        self.text = text; self.selectedText = selectedText
    }

    public var body: some View {
        VStack(spacing: spacing) {
            LayoutIcon(kind: kind, selected: selected, tint: tint, size: iconSize)
            if let nameFont {
                Text(kind.name)
                    .font(nameFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(padding)
        .frame(width: size?.width, height: size?.height)
        .background { RoundedRectangle(cornerRadius: cornerRadius).fill(selected ? (selectedFill ?? tint) : fill) }
        .foregroundStyle(selected ? selectedText : text)
    }
}
