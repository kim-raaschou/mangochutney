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

    private static func placedFrames(_ kind: LayoutKind, in area: CGRect) -> [CGRect] {
        let screen = CGRect(x: 0, y: 0, width: 1500, height: 1000)
        let ids: [ClientID] = [1, 2, 3]
        let start = CGRect(x: 700, y: 450, width: 100, height: 100)
        var config = Config()
        config.scrollerDefaultProportion = 0.6
        let input = LayoutInput(
            workArea: screen, monitorFrame: screen, gaps: Gaps(ih: 60, iv: 60, oh: 0, ov: 0),
            clients: ids.map { LayoutClient(id: $0, currentFrame: start) },
            focusedID: 1, prevFocusedID: nil,
            pertag: PertagSettings(nmaster: 1, mfact: 0.55, scrollerDefaultProportion: 0.6),
            config: config)
        let result = LayoutEngine.arrange(kind, input: input, state: TagLayoutState())
        let sx = area.width / screen.width, sy = area.height / screen.height
        return ids.compactMap { id in
            guard let f = result.frames[id] else { return nil }
            let r = f.intersection(screen)
            guard !r.isNull, r.width >= 1, r.height >= 1 else { return nil }
            return CGRect(x: area.minX + r.minX * sx, y: area.minY + r.minY * sy, width: r.width * sx, height: r.height * sy)
        }
    }
}

