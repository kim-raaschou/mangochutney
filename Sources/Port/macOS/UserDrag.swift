import CoreGraphics
import Mango

/// An app's own move of its window by its title bar: not in mango, which has no client-driven move. A tiled
/// window the app moves is a grab the app drives: mango's grab_client and client_begin_drag_float while the
/// button is down, the drop area of pointer_process_motion, and the drop of pointer_end_grab_client.
struct UserDrag {
    let client: Client
    let startFrame: CGRect
    var resized: Bool
}

extension MacWindowSystem {
    func plainMouseDown(at p: CGPoint) {
        pressed = nil
        guard let c = server.nodeAtPoint(p), !c.parked, let f = windowServerFrame(c.id) else { return }
        pressed = (c, f)
    }

    func followUserDrag() {
        guard let (c, start) = pressed, server.clientByIdAll(c.id) === c, !c.parked,
              let now = windowServerFrame(c.id), now != start, now != c.frame else { return }
        moved(c, to: now, resized: now.size != start.size)
    }

    func userButtonReleased(button: Int, at p: CGPoint) {
        guard button == 0 else { return }
        pressed = nil
        if let d = userDrag {
            userDrag = nil
            finishUserDrag(d, at: p)
        }
    }

    func userMoved(_ c: Client, to actual: CGRect, resized: Bool, dragging: Bool) {
        if dragging {
            if userDrag == nil || userDrag?.client !== c {
                userDrag = UserDrag(client: c, startFrame: c.frame, resized: resized)
                if !resized { beginAppDrag(c) }
            }
            if resized { userDrag?.resized = true }
            if c.isfloating { c.floatGeom = actual.insetBy(dx: -c.bw, dy: -c.bw); c.geom = c.floatGeom; c.iscustomsize = true }
            c.frame = actual
            standsAt(c, actual)
            server.updateBorders()
            if c.dragToTile { appDragDropArea(c) }
            return
        }
        if c.isfloating {
            c.floatGeom = actual.insetBy(dx: -c.bw, dy: -c.bw)
            c.geom = c.floatGeom
            c.frame = actual
            standsAt(c, actual)
            server.updateBorders()
            return
        }
        c.frame = actual
        let target = c.mac.box
        if MangoServer.frameDistance(actual, target) > 0.5 {
            wlrLog(.debug, "\(c.appName): window \(c.id) moved to \(actual) by the app; its tile is \(target)")
            keepPlaced(c, at: target)
        }
        server.updateBorders()
    }

    /// pointer_begin_move_resize's grab and client_begin_drag_float for a tiled window the app moves.
    func beginAppDrag(_ c: Client) {
        guard !c.isfloating, server.grabClient == nil, c.mon != nil, !c.isfullscreen, !c.ismaximizescreen else { return }
        server.grabClient = c
        server.clientBeginDragFloat(c)
        if server.config.dragTileToTile && server.config.dragTileSmall {
            let p = pointer
            c.geom = CGRect(x: p.x.rounded() - 150, y: p.y.rounded() - 150, width: 300, height: 300)
            server.resize(c, c.geom, ResizeOpts(interact: true))
        }
    }

    /// pointer_process_motion's drop area (CurMove) for the window the app moves.
    func appDragDropArea(_ c: Client) {
        let p = pointer
        let target = server.groupBarTargetAt(p.x, p.y, c)
        server.dropToGroup = target != nil
        let closet = server.config.dragTileToTile ? (target ?? server.findClosestTiledClient(c)) : target
        if let closet, let dc = server.dropClient, closet !== dc {
            dc.enableDropAreaDraw = false
            server.clientSetDropArea(dc)
            server.dropClient = closet
            closet.enableDropAreaDraw = true
            server.clientSetDropArea(closet)
        } else if let closet {
            server.dropClient = closet
            closet.enableDropAreaDraw = true
            server.clientSetDropArea(closet)
        } else {
            dropAreaOff()
        }
    }

    func dropAreaOff() {
        guard let dc = server.dropClient else { return }
        dc.enableDropAreaDraw = false
        server.clientSetDropArea(dc)
        server.dropClient = nil
    }

    /// The button's release (a group bar under the pointer) and pointer_end_grab_client's drop, for the
    /// window the app moved.
    func finishAppDrag(_ c: Client) {
        let p = pointer
        server.dropToGroup = false
        if let target = server.groupBarTargetAt(p.x, p.y, c) {
            if server.grabClient === c { server.grabClient = nil }
            c.dragToTile = false
            dropAreaOff()
            server.clientGroupJoin(c, target)
            return
        }
        // The app's own drag ends as mango's move grab does: pointer_end_grab_client.
        server.grabClient = c
        server.cursorMode = CurMove
        server.pointerEndGrabClient(true)
        dropAreaOff()
        server.printstatus(.arrangge)
    }

    /// The user or the app moved the window: mango's box stands where it is, as an interactive move
    /// (resize with the grab) leaves it, so the next animation starts there.
    func standsAt(_ c: Client, _ actual: CGRect) {
        guard !c.animation.running else { return }
        c.animation.current = actual.insetBy(dx: -c.bw, dy: -c.bw)
        c.mac.nodePosition = c.animation.current.origin
    }

    func finishUserDrag(_ d: UserDrag, at p: CGPoint) {
        let c = d.client
        guard server.clientByIdAll(c.id) === c else { return }
        readFrame(c) { [weak self] actual in
            self?.completeUserDrag(d, actual: actual ?? c.frame, at: p)
        }
    }

    func completeUserDrag(_ d: UserDrag, actual: CGRect, at p: CGPoint) {
        let c = d.client
        guard server.clientByIdAll(c.id) === c, let m = c.mon else { return }
        if c.dragToTile {
            c.frame = actual
            finishAppDrag(c)
            return
        }
        if c.isfloating {
            c.floatGeom = actual.insetBy(dx: -c.bw, dy: -c.bw)
            c.geom = c.floatGeom
            c.iscustomsize = true
            c.frame = actual
            if let target = server.monitorAtPoint(actual.center), target !== m {
                server.clientSetMonitor(c, target, 0, focus: true)
            }
            server.updateBorders()
            server.applyWindowSnap(c)
            return
        }
        if d.resized {
            var dx = actual.width - d.startFrame.width, dy = actual.height - d.startFrame.height
            if m.layout == .dwindle {
                if abs(actual.minX - d.startFrame.minX) > 1 { dx = -dx }
                if abs(actual.minY - d.startFrame.minY) > 1 { dy = -dy }
            }
            server.resizeTileClient(c, false, Int32(dx), Int32(dy))
        }
        c.frame = actual
        server.arrange(m, false, false)
        server.printstatus(.arrangge)
    }
}
