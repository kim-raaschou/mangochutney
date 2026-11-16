import SwiftUI
import Mango

public struct LayoutIcon: View {
    let kind: LayoutKind
    let selected: Bool
    var tint: Color = .accentColor
    var size = CGSize(width: 30, height: 20)

    public init(kind: LayoutKind, selected: Bool, tint: Color = .accentColor, size: CGSize = CGSize(width: 30, height: 20)) {
        self.kind = kind; self.selected = selected; self.tint = tint; self.size = size
    }

    public var body: some View {
        Canvas { ctx, size in
            for (r, alpha) in Self.frames(kind, in: CGRect(origin: .zero, size: size)) {
                let path = Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 1.5)
                ctx.fill(path, with: .color(selected ? .white.opacity(0.9 * alpha) : tint.opacity(0.75 * alpha)))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    public static func frames(_ kind: LayoutKind, in area: CGRect) -> [(rect: CGRect, alpha: CGFloat)] {
        let placed = placedFrames(kind, in: area)
        var piles: [[CGRect]] = []
        for r in placed {
            if let i = piles.firstIndex(where: { p in abs(p[0].minX - r.minX) < 1 && abs(p[0].minY - r.minY) < 1
                                                    && abs(p[0].width - r.width) < 1 && abs(p[0].height - r.height) < 1 }) {
                piles[i].append(r)
            } else {
                piles.append([r])
            }
        }
        let d = max(1.5, min(area.width, area.height) * 0.14)
        var out: [(rect: CGRect, alpha: CGFloat)] = []
        for pile in piles {
            let n = pile.count, base = pile[0]
            let shrink = CGFloat(n - 1) * d
            for i in stride(from: n - 1, through: 0, by: -1) {
                let r = CGRect(x: base.minX + CGFloat(i) * d, y: base.minY + CGFloat(n - 1 - i) * d,
                               width: base.width - shrink, height: base.height - shrink)
                out.append((r, i == 0 ? 1 : 0.55 - 0.15 * CGFloat(i - 1)))
            }
        }
        return out
    }

    /// Three windows on a 1500x1000 monitor (inner gaps 60, no outer gaps, the first focused, the
    /// scroller's proportion 0.6), as mango's layouts place them.
    private static let placed: [LayoutKind: [CGRect]] = [
        .tile: [CGRect(x: 0, y: 0, width: 798, height: 1000), CGRect(x: 858, y: 0, width: 642, height: 470), CGRect(x: 858, y: 530, width: 642, height: 470)],
        .scroller: [CGRect(x: 20, y: 0, width: 840, height: 1000), CGRect(x: 920, y: 0, width: 840, height: 1000), CGRect(x: 1820, y: 0, width: 840, height: 1000)],
        .grid: [CGRect(x: 10, y: 10, width: 737, height: 487), CGRect(x: 752, y: 10, width: 737, height: 487), CGRect(x: 381, y: 502, width: 737, height: 487)],
        .monocle: [CGRect(x: 0, y: 0, width: 1500, height: 1000), CGRect(x: 0, y: 0, width: 1500, height: 1000), CGRect(x: 0, y: 0, width: 1500, height: 1000)],
        .deck: [CGRect(x: 0, y: 0, width: 825, height: 1000), CGRect(x: 885, y: 0, width: 615, height: 1000), CGRect(x: 885, y: 0, width: 615, height: 1000)],
        .centerTile: [CGRect(x: 354, y: 0, width: 792, height: 1000), CGRect(x: 0, y: 0, width: 294, height: 1000), CGRect(x: 1206, y: 0, width: 294, height: 1000)],
        .rightTile: [CGRect(x: 702, y: 0, width: 798, height: 1000), CGRect(x: 0, y: 0, width: 642, height: 470), CGRect(x: 0, y: 530, width: 642, height: 470)],
        .verticalScroller: [CGRect(x: 0, y: 20, width: 1500, height: 540), CGRect(x: 0, y: 620, width: 1500, height: 540), CGRect(x: 0, y: 1220, width: 1500, height: 540)],
        .verticalTile: [CGRect(x: 0, y: 0, width: 1440, height: 523), CGRect(x: 0, y: 583, width: 690, height: 417), CGRect(x: 750, y: 583, width: 690, height: 417)],
        .verticalGrid: [CGRect(x: 10, y: 10, width: 737, height: 487), CGRect(x: 10, y: 502, width: 737, height: 487), CGRect(x: 752, y: 256, width: 737, height: 487)],
        .verticalDeck: [CGRect(x: 0, y: 0, width: 1500, height: 550), CGRect(x: 0, y: 610, width: 1500, height: 390), CGRect(x: 0, y: 610, width: 1500, height: 390)],
        .fair: [CGRect(x: 0, y: 0, width: 720, height: 1000), CGRect(x: 780, y: 0, width: 720, height: 470), CGRect(x: 780, y: 530, width: 720, height: 470)],
        .verticalFair: [CGRect(x: 0, y: 0, width: 1500, height: 470), CGRect(x: 0, y: 530, width: 720, height: 470), CGRect(x: 780, y: 530, width: 720, height: 470)],
        .dwindle: [CGRect(x: 0, y: 0, width: 720, height: 470), CGRect(x: 780, y: 0, width: 720, height: 1000), CGRect(x: 0, y: 530, width: 720, height: 470)],
    ]

    private static func placedFrames(_ kind: LayoutKind, in area: CGRect) -> [CGRect] {
        let screen = CGRect(x: 0, y: 0, width: 1500, height: 1000)
        let sx = area.width / screen.width, sy = area.height / screen.height
        return (placed[kind] ?? []).compactMap { f in
            let r = f.intersection(screen)
            guard !r.isNull, r.width >= 1, r.height >= 1 else { return nil }
            return CGRect(x: area.minX + r.minX * sx, y: area.minY + r.minY * sy, width: r.width * sx, height: r.height * sy)
        }
    }
}

