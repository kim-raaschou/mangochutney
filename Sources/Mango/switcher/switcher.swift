import CoreGraphics

// not in mango: the tiles' scene surfaces (switcher_tile_layout, switcher_surface_finish,
// switcher_surface_update_buffer, the surface listeners, switcher_tile_add_surface) are the port's
// pictures, drawn in its panel

package let SW_PAD: Int32 = 6
package let SW_GAP: Int32 = 14
package let SW_MARGIN: Int32 = 28
package let SW_PANEL_FRAC: Float = 0.8
package let SW_TILE_FRAC: Float = 0.25
package let SW_ASPECT_MIN: Float = 9.0 / 16.0
package let SW_ASPECT_MAX: Float = 12.0 / 5.0

/* Switcher candidate scope. */
let SW_CURRENT_TAG: Int32 = 0, SW_ALL_TAG: Int32 = 1, SW_ALL_MON: Int32 = 2

/// mango struct switcher_tile (switcher/switcher.h).
package final class SwitcherTile {
    package var c: Client!
    // not in mango: tree's position in the panel; tree, frame, content and surfaces are the port's
    package var x: Int32 = 0, y: Int32 = 0
    package var cw: Int32 = 0
    package var row: Int32 = 0
}

/// mango struct switcher_state (switcher/switcher.h).
package struct SwitcherState {
    package var mon: Monitor?
    package var tree = false   // not in mango: the port's panel stands for the scene tree
    package var tiles: [SwitcherTile] = []
    package var count: Int32 { Int32(tiles.count) }
    package var index: Int32 = 0
    package var tileH: Int32 = 0
    package var scope: Int32 = 0
    package var panelX: Int32 = 0
    package var panelY: Int32 = 0
    package var panelW: Int32 = 0
    package var panelH: Int32 = 0
}

package extension MangoServer {

    func switcherTileCreate(_ tile: SwitcherTile, _ c: Client) {
        tile.c = c
        let (srcW, srcH) = switcherContentSize(c)
        var aspect: Float = srcW > 0 && srcH > 0 ? srcW / srcH : 1.0
        aspect = max(SW_ASPECT_MIN, min(aspect, SW_ASPECT_MAX))
        tile.cw = max(1, Int32(Float(switcherState.tileH) * aspect))

        // not in mango: the tile's tree, frame and content are the port's (switcherPictures)
    }

    func switcherLayout() {
        let mon = switcherState.mon!
        let frameH = switcherState.tileH + 2 * SW_PAD
        let maxrowW = max(
            1, Int32(Float(Int32(mon.m.width)) * SW_PANEL_FRAC) - 2 * SW_MARGIN)

        var nrows: Int32 = 1
        var rowW: Int32 = 0
        var contentW: Int32 = 0
        for tile in switcherState.tiles {
            let fw = tile.cw + 2 * SW_PAD
            if rowW > 0 && rowW + SW_GAP + fw > maxrowW {
                nrows += 1
                rowW = fw
            } else {
                rowW = rowW == 0 ? fw : rowW + SW_GAP + fw
            }
            tile.row = nrows - 1
            contentW = max(contentW, rowW)
        }

        var rowsw = [Int32](repeating: 0, count: Int(nrows))
        for tile in switcherState.tiles {
            let fw = tile.cw + 2 * SW_PAD
            rowsw[Int(tile.row)] += rowsw[Int(tile.row)] == 0 ? fw : SW_GAP + fw
        }

        let panelW = contentW + 2 * SW_MARGIN
        let panelH = 2 * SW_MARGIN + nrows * frameH + (nrows - 1) * SW_GAP
        switcherState.panelX =
            Int32(mon.m.minX) + (Int32(mon.m.width) - panelW) / 2
        switcherState.panelY =
            Int32(mon.m.minY) + (Int32(mon.m.height) - panelH) / 2
        switcherState.panelW = panelW
        switcherState.panelH = panelH

        var row: Int32 = -1
        var x: Int32 = 0
        for tile in switcherState.tiles {
            if tile.row != row {
                row = tile.row
                x = SW_MARGIN + (contentW - rowsw[Int(row)]) / 2
            }
            tile.x = x
            tile.y = SW_MARGIN + row * (frameH + SW_GAP)
            x += tile.cw + 2 * SW_PAD + SW_GAP
        }
        // not in mango: the port's panel, where mango places the scene nodes
        if drawsOverlays {
            system.showSwitcher(panel: CGRect(x: Int(switcherState.panelX), y: Int(switcherState.panelY),
                                              width: Int(panelW), height: Int(panelH)),
                                tiles: switcherPictures(), look: SwitcherLook(focus: config.focuscolor, border: config.bordercolor),
                                scale: CGFloat(mon.screen.scale))
        }
        titleMessageBarUpdate(mon)
    }

    /// Not in mango: the tiles as the port draws them, each frame at its place on the screen.
    func switcherPictures() -> [SwitcherTilePicture] {
        let frameH = switcherState.tileH + 2 * SW_PAD
        return switcherState.tiles.enumerated().map { i, tile in
            SwitcherTilePicture(id: tile.c.id,
                                frame: CGRect(x: Int(switcherState.panelX + tile.x), y: Int(switcherState.panelY + tile.y),
                                              width: Int(tile.cw + 2 * SW_PAD), height: Int(frameH)),
                                size: tile.c.frame.size, pid: tile.c.pid, highlighted: Int32(i) == switcherState.index)
        }
    }

    func switcherApplyHighlight() {
        if drawsOverlays { system.switcherApplyHighlight(switcherPictures()) }   // not in mango: the port's frames
    }

    func switcherClose() {
        if !switcherIsActive() {
            return
        }
        let m = switcherState.mon
        system.closeSwitcherPanel()   // not in mango: the port's panel (wlr_scene_node_destroy)
        switcherState = SwitcherState()
        titleMessageBarHide(m)
    }

    // remove a single tile while the switcher stays open, then relayout
    func switcherRemoveClient(_ c: Client) {
        if !switcherIsActive() {
            return
        }
        guard let i = switcherState.tiles.firstIndex(where: { $0.c === c }) else {
            return
        }

        // not in mango: the tile's tree is the port's, drawn again by switcher_layout

        if switcherState.index > Int32(i) {
            switcherState.index -= 1
        }
        switcherState.tiles.remove(at: i)
        if switcherState.count == 0 {
            switcherClose()
            return
        }
        if switcherState.index >= switcherState.count {
            switcherState.index = switcherState.count - 1
        }
        switcherLayout()
        switcherApplyHighlight()
    }

    private func switcherClientEligible(_ c: Client?) -> Bool {
        // not in mango: every Client is a mapped window; no unmanaged clients or X11 popups
        guard let c else { return false }
        return c.mon != nil && !c.iskilling && !c.isminimized && !c.isunglobal
    }

    func switcherCommitClient(_ tc: Client) {
        switcherClose()
        if !switcherClientEligible(tc) {
            return
        }
        if !VISIBLEON(tc, tc.mon) {
            clientViewOnMonitor(Arg(ui: getTagsFirstTag(tc.tags)), true,
                                tc.mon, true)
        }
        clientFocus(tc, true)
    }

    func switcherCommit() {
        if !switcherIsActive() {
            return
        }
        switcherCommitClient(switcherState.tiles[Int(switcherState.index)].c)
    }

    func switcherClientAt(_ lx: CGFloat, _ ly: CGFloat) -> Client? {
        if !switcherIsActive() {
            return nil
        }
        for tile in switcherState.tiles {
            let box = CGRect(x: Int(switcherState.panelX + tile.x), y: Int(switcherState.panelY + tile.y),
                             width: Int(tile.cw + 2 * SW_PAD),
                             height: Int(switcherState.tileH + 2 * SW_PAD))
            if !(lx >= box.minX && lx < box.maxX && ly >= box.minY && ly < box.maxY) {
                continue
            }
            return tile.c
        }
        return nil
    }

    func switcherTitleMessageBarGeometry(_ m: Monitor?) -> (client: Client, box: CGRect)? {
        if !switcherIsActive() || m == nil || m !== switcherState.mon ||
            switcherState.count <= 0 || switcherState.index < 0 ||
            switcherState.index >= switcherState.count {
            return nil
        }

        return (switcherState.tiles[Int(switcherState.index)].c,
                CGRect(x: Int(switcherState.panelX),
                       y: Int(switcherState.panelY + switcherState.panelH +
                              Int32(config.titleMessageBarGap)),
                       width: Int(switcherState.panelW),
                       height: config.titleMessageBarHeight))
    }

    func switcherOpen(_ scope: Int32, _ dir: Int32) {
        var n: Int32 = 0

        for m in monitors {
            if m.isoverview {
                return
            }
        }

        switcherState.mon = selectedMonitor
        switcherState.scope = scope

        for c in focusStack.compactMap({ clientByIdAll($0) }) {
            if switcherCandidate(c) {
                n += 1
            }
        }
        if n == 0 {
            return
        }

        let mon: Monitor = selectedMonitor
        let maxRowW =
            Int32(Float(Int32(mon.m.width)) * SW_PANEL_FRAC) - 2 * SW_MARGIN
        let maxPanelH = Int32(Float(Int32(mon.m.height)) * SW_PANEL_FRAC)
        // size against the widest allowed tile so the panel always fits
        switcherState.tileH = 1
        for cols in 1...n {
            let rows = (n + cols - 1) / cols
            let hByW =
                Int32(Float(maxRowW - (cols - 1) * SW_GAP - 2 * cols * SW_PAD) /
                      (Float(cols) * SW_ASPECT_MAX))
            let hByH =
                (maxPanelH - 2 * SW_MARGIN - (rows - 1) * SW_GAP) / rows -
                2 * SW_PAD
            let h = min(Int32(Float(Int32(mon.m.height)) * SW_TILE_FRAC),
                        min(hByW, hByH))
            switcherState.tileH = max(switcherState.tileH, h)
        }

        switcherState.tree = true   // not in mango: the port's panel (the scene tree and its bg)
        switcherState.tiles = []
        for c in focusStack.compactMap({ clientByIdAll($0) }) {
            if !switcherCandidate(c) {
                continue
            }
            let tile = SwitcherTile()
            switcherTileCreate(tile, c)
            switcherState.tiles.append(tile)
        }
        // The current window is at the focus_stack head (tiles[0]); selecting the
        // second one and committing inserts it at the front, so the next open puts
        // the original first as second, toggling between the two most recent
        // windows. Forward (next) therefore starts at the second tile, while
        // backward (prev) has to start from the tail (the least recent window)
        // and walk in reverse.
        if switcherState.count > 1 {
            switcherState.index = dir < 0 ? switcherState.count - 1 : 1
        } else {
            switcherState.index = 0
        }
        switcherLayout()
        switcherApplyHighlight()

        // not in mango: no frame callbacks (client_send_frame_done); the port's pictures are taken as it opens
    }

    func switcherCycle(_ dir: Int32) {
        switcherState.index = (switcherState.index + dir + switcherState.count) %
            switcherState.count
        switcherApplyHighlight()
        titleMessageBarUpdate(switcherState.mon)
    }

    func switcher(_ arg: Arg) -> Int32 {
        let dir: Int32 = arg.i == PREV ? -1 : 1
        let scope = arg.i2
        // not in mango: no session lock
        if selectedMonitor == nil ||
            selectedMonitor.isJumpMode {
            return 0
        }
        if switcherIsActive() {
            if scope != switcherState.scope {
                switcherClose()
                switcherOpen(scope, dir)
            } else {
                switcherCycle(dir)
            }
        } else {
            switcherOpen(scope, dir)
        }
        return 0
    }

    func switcherIsActive() -> Bool { switcherState.tree }

    func switcherCandidate(_ c: Client) -> Bool {
        if !switcherClientEligible(c) {
            return false
        }

        if switcherState.scope == SW_CURRENT_TAG {
            return c.mon === switcherState.mon && VISIBLEON(c, switcherState.mon)
        }
        if switcherState.scope == SW_ALL_TAG {
            return c.mon === switcherState.mon
        }
        return Int32(bitPattern: c.tags) > 0
    }

    func switcherContentSize(_ c: Client) -> (Float, Float) {
        // not in mango: the window's frame, where mango reads the xdg geometry
        (Float(c.frame.width), Float(c.frame.height))
    }
}

package let switcherPanelColor: [Float] = [0.09, 0.09, 0.11, 0.92]
