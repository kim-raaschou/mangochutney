import CoreGraphics

package struct DragTile {
    package let client: Client
    let floatBackup: CGRect
}

package extension MangoServer {
    func clientBeginDragFloat(_ c: Client, at p: CGPoint) {
        guard dragTile == nil, !c.isFloating, let m = c.mon,
              tiledClients(m).contains(where: { $0 === c }) else { return }
        dragTile = DragTile(client: c, floatBackup: c.floatGeom)
        setSizePer(m, c)
        Log.debug("drag tile: \(c.appName) \(c.id) floats while dragged")
        if config.dragTileToTile, config.dragTileSmall {
            let small = CGRect(x: p.x.rounded() - 150, y: p.y.rounded() - 150, width: 300, height: 300)
            system.cancelAnimation(c.id)
            c.frame = small
            system.setFrame(c, small, size: true)
            updateBorders(animating: [c.id: small])
            system.readFrame(c) { [weak self] actual in
                guard let self, let actual, self.dragTile?.client === c, actual.size != small.size else { return }
                c.frame.size = actual.size
                self.updateBorders(animating: [c.id: c.frame])
            }
        }
        c.floatGeom = c.frame
        c.isFloating = true
        arrange(m, .move)
    }

    func findClosestTiledClient(to p: CGPoint, except c: Client) -> Client? {
        guard let m = monitorAtPoint(p) else { return nil }
        let tiles = tiledClients(m).filter { $0 !== c }
        if let hit = tiles.first(where: { tileBox($0, on: m).contains(p) }) { return hit }
        return tiles.min { a, b in
            let fa = tileBox(a, on: m), fb = tileBox(b, on: m)
            return hypot(fa.midX - p.x, fa.midY - p.y) < hypot(fb.midX - p.x, fb.midY - p.y)
        }
    }

    /// Not in mango: stands for c->geom with its border.
    func tileBox(_ c: Client, on m: Monitor) -> CGRect {
        let bw = borderWidth(c, on: m)
        return (c.geom ?? c.frame).insetBy(dx: -bw, dy: -bw)
    }

    func groupBarTargetAt(at p: CGPoint, except c: Client) -> Client? {
        guard let m = monitorAtPoint(p) else { return nil }
        let h = CGFloat(config.groupBarHeight)
        return visibleClients(m).first { g in
            g !== c && clientCheckTabNodeVisible(g, on: m) && CGRect(x: g.frame.minX, y: g.frame.minY - h, width: g.frame.width, height: h).contains(p)
        }
    }

    // not in mango: the drop client and client_set_drop_area's direction, worked out where mango keeps them
    func dropTarget(at p: CGPoint, except c: Client) -> (tile: Client, direction: DropDirection, area: CGRect)? {
        if let g = groupBarTargetAt(at: p, except: c) { return (g, .none, g.frame) }
        guard let t = findClosestTiledClient(to: p, except: c), let m = t.mon else { return nil }
        let tiled = tiledClients(m)
        let isMaster = (tiled.firstIndex { $0 === t } ?? .max) < m.current.settings.nmaster
        let (direction, area) = DropArea.clientSetDropArea(layout: m.layout, target: t.geom ?? t.frame, at: p,
                                                 isMaster: isMaster, tiled: tiled.count,
                                                 dwindleSimpleSplit: config.dwindleDropSimpleSplit,
                                                 dwindleSplitRatio: config.dwindleSplitRatio)
        return (t, direction, area)
    }

    // not in mango: pointer_process_motion's drop area, apart for an app's own title-bar drag too
    func updateDragTile(at p: CGPoint) {
        guard let d = dragTile, drawsOverlays else { return }
        let onBar = groupBarTargetAt(at: p, except: d.client) != nil
        guard onBar || config.dragTileToTile, let drop = dropTarget(at: p, except: d.client) else {
            Log.debug("drag tile: no tile near \(p)")
            system.showDropArea(nil, color: config.dropcolor)
            return
        }
        Log.debug("drag tile: at \(p) on \(drop.tile.appName) \(drop.tile.id), \(drop.direction), area \(drop.area)")
// not in mango: above the dragged window, which keeps its whole size in a macOS title-bar drag.
        system.showDropArea(drop.area, color: config.dropcolor)
    }

    // not in mango: pointer_end_grab_client's drag tile, apart for an app's own title-bar drag too
    func dropDraggedTile(at p: CGPoint) {
        guard let d = dragTile else { return }
        if config.dragTileToTile { pointerPlaceDragTile(at: p); return }
        dragTile = nil
        system.showDropArea(nil, color: config.dropcolor)
        let c = d.client
        c.floatGeom = c.frame
        c.isCustomSize = true
    }

    func pointerPlaceDragTile(at p: CGPoint) {
        guard let d = dragTile else { return }
        dragTile = nil
        system.showDropArea(nil, color: config.dropcolor)
        let c = d.client
        guard clientByIdAll(c.id) === c else { return }
        if let g = groupBarTargetAt(at: p, except: c) {
            c.isFloating = false
            c.floatGeom = d.floatBackup
            clientGroupJoin(c, into: g)
            printstatus()
            return
        }
        let drop = dropTarget(at: p, except: c)
        Log.debug("drag tile: dropped at \(p) \(drop.map { "\($0.direction) of \($0.tile.appName) \($0.tile.id)" } ?? "on no tile")")
        c.isFloating = false
        c.floatGeom = d.floatBackup
        // Dropped on another monitor: it joins it (client_set_monitor). The grab's end has
        // done it already; a drag by the app itself (not in mango) has not.
        if let target = monitorAtPoint(p), target !== c.mon { clientSetMonitor(c, target, 0, focus: true) }
        guard let m = c.mon else { return }
        if let drop, drop.tile.mon === m {
            let t = drop.tile, direction = drop.direction
            func inOrder(before: Bool) {
                clients.removeAll { $0 === c }
                guard let i = clients.firstIndex(where: { $0 === t }) else { clients.append(c); return }
                clients.insert(c, at: before ? i : i + 1)
            }
            if direction == .none { inOrder(before: true) } else {
                switch m.layout {
                case .scroller, .verticalScroller:
                    let vertical = m.layout == .verticalScroller
                    let along: Bool = vertical ? (direction == .left || direction == .right) : (direction == .up || direction == .down)
                    m.current.state.scrollerState.scrollerDropTile(c.id, onto: t.id, intoStack: along,
                                                  before: direction == .left || direction == .up)
                case .dwindle:
                    m.current.state.dwindleRoot.drop(c.id, nextTo: t.id, asFirst: direction == .left || direction == .up,
                                                 splitH: direction == .left || direction == .right,
                                                 lock: !config.dwindleDropSimpleSplit, config: config)
                case .rightTile:
                    inOrder(before: direction == .right || direction == .up)
                default:
                    inOrder(before: direction == .left || direction == .up)
                }
            }
        }
        if m.sel != c.id { m.prevsel = m.sel; m.sel = c.id }
        arrange(m, .move)
        printstatus()
    }
}
