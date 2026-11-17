import Foundation
import CoreGraphics
import Mango

/// Port extension: not in mango. chutney_launch_or_focus's panel of given windows, laid out as mango's
/// switcher_open (the tile height), switcher_tile_create (the tile widths) and switcher_layout.
enum SwitcherPanelLayout {
    static let pad = Int(SW_PAD), gap = Int(SW_GAP), margin = Int(SW_MARGIN)
    static let panelFrac = SW_PANEL_FRAC, tileFrac = SW_TILE_FRAC
    static let aspectMin = SW_ASPECT_MIN, aspectMax = SW_ASPECT_MAX

    struct Result: Equatable {
        var panel: CGRect
        var tiles: [CGRect]
        var tileHeight: Int
    }

    static func switcherLayout(sizes: [CGSize], monitor: CGRect) -> Result {
        let n = sizes.count
        let monW = Int(monitor.width), monH = Int(monitor.height)
        guard n > 0 else { return Result(panel: .zero, tiles: [], tileHeight: 0) }

        let maxRowW = Int(Float(monW) * panelFrac) - 2 * margin
        let maxPanelH = Int(Float(monH) * panelFrac)
        var tileH = 1
        for cols in 1...n {
            let rows = (n + cols - 1) / cols
            let hByW = Int(Float(maxRowW - (cols - 1) * gap - 2 * cols * pad) / (Float(cols) * aspectMax))
            let hByH = (maxPanelH - 2 * margin - (rows - 1) * gap) / rows - 2 * pad
            let h = min(Int(Float(monH) * tileFrac), min(hByW, hByH))
            tileH = max(tileH, h)
        }

        let cws = sizes.map { s -> Int in
            var aspect: Float = s.width > 0 && s.height > 0 ? Float(s.width / s.height) : 1
            aspect = max(aspectMin, min(aspect, aspectMax))
            return max(1, Int(Float(tileH) * aspect))
        }

        let frameH = tileH + 2 * pad
        let maxRowWidth = max(1, Int(Float(monW) * panelFrac) - 2 * margin)
        var rowOf: [Int] = []
        var nrows = 1, rowW = 0, contentW = 0
        for cw in cws {
            let fw = cw + 2 * pad
            if rowW > 0 && rowW + gap + fw > maxRowWidth {
                nrows += 1
                rowW = fw
            } else {
                rowW = rowW == 0 ? fw : rowW + gap + fw
            }
            rowOf.append(nrows - 1)
            contentW = max(contentW, rowW)
        }
        var rowsW = [Int](repeating: 0, count: nrows)
        for (i, cw) in cws.enumerated() {
            let fw = cw + 2 * pad
            rowsW[rowOf[i]] += rowsW[rowOf[i]] == 0 ? fw : gap + fw
        }

        let panelW = contentW + 2 * margin
        let panelH = 2 * margin + nrows * frameH + (nrows - 1) * gap
        let panelX = Int(monitor.minX) + (monW - panelW) / 2
        let panelY = Int(monitor.minY) + (monH - panelH) / 2

        var tiles: [CGRect] = []
        var row = -1, x = 0
        for (i, cw) in cws.enumerated() {
            if rowOf[i] != row {
                row = rowOf[i]
                x = margin + (contentW - rowsW[row]) / 2
            }
            tiles.append(CGRect(x: panelX + x, y: panelY + margin + row * (frameH + gap),
                                width: cw + 2 * pad, height: frameH))
            x += cw + 2 * pad + gap
        }
        return Result(panel: CGRect(x: panelX, y: panelY, width: panelW, height: panelH),
                      tiles: tiles, tileHeight: tileH)
    }
}
