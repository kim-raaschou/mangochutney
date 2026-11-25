import CoreGraphics

extension MangoServer {
    func wsovPremultiplied(_ component: Double, _ alpha: Double) -> Double {
        component * alpha
    }

    func wsovSetRectColor(_ rect: WlrSceneRect?, _ color: RGBA) {
        guard let rect else { return }
        let premultiplied = RGBA(
            r: wsovPremultiplied(color.r, color.a),
            g: wsovPremultiplied(color.g, color.a),
            b: wsovPremultiplied(color.b, color.a),
            a: color.a)
        wlrSceneRectSetColor(rect, premultiplied)
    }

    func wsovUpdateStylesTags(_ tags: UInt32) {
        for cell in wsov.cells {
            if tags & wsovTagBit(cell.tag) == 0 {
                continue
            }
            let focused = cell.tag == wsov.targetTag
            if wsov.layout == WORKSPACE_OVERVIEW_SCROLL {
                cell.dimEnabled = false
                mangoDimNodeSetEnabled(cell.dim, false)
                cell.bordersEnabled = false
                for j in 0..<4 {
                    if let b = cell.border[j] { wlrSceneNodeSetEnabled(b, false) }
                }
            } else {
                let dimOpacity =
                    focused ? config.workspaceOverviewFocusedDimOpacity
                        : config.workspaceOverviewUnfocusedDimOpacity
                let dimColor = RGBA(r: 0, g: 0, b: 0, a: Double(dimOpacity))
                mangoDimNodeSetColor(cell.dim, dimColor)
                mangoDimNodeSetBox(cell.dim, cell.box.x + wsovBorderWidth(),
                                   cell.box.y + wsovBorderWidth(),
                                   cell.bufferW, cell.bufferH)
                cell.dimEnabled = dimOpacity > 0.0
                mangoDimNodeSetEnabled(cell.dim, cell.dimEnabled)
                if let dim = cell.dim { wlrSceneNodeRaiseToTop(dim.sceneBuffer) }
                for j in 0..<4 {
                    wsovSetRectColor(cell.border[j], focused
                        ? config.focuscolor
                        : config.bordercolor)
                }
            }
        }
        if let dropFill = wsov.dropFill {
            wsovSetRectColor(dropFill, config.dropcolor)
            if wsov.dropIndicatorVisible {
                wlrSceneNodeRaiseToTop(dropFill)
            }
        }
        if let dragBuffer = wsov.dragBuffer {
            wlrSceneNodeRaiseToTop(dragBuffer)
        }
    }

    func wsovUpdateStyles() {
        var tags: UInt32 = 0
        for cell in wsov.cells {
            tags |= wsovTagBit(cell.tag)
        }
        wsovUpdateStylesTags(tags)
    }

    func wsovSetDimEnabled(_ enabled: Bool) {
        for cell in wsov.cells {
            cell.dimEnabled = enabled
            mangoDimNodeSetEnabled(cell.dim, enabled)
        }
    }

    func wsovSetBordersEnabled(_ enabled: Bool) {
        var enabled = enabled
        if wsov.layout == WORKSPACE_OVERVIEW_SCROLL {
            enabled = false
        }
        for cell in wsov.cells {
            cell.bordersEnabled = enabled
            for j in 0..<4 {
                if let b = cell.border[j] { wlrSceneNodeSetEnabled(b, enabled) }
            }
        }
    }
}
