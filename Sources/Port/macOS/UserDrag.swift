import CoreGraphics
import Mango

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
                if !resized { server.clientBeginDragFloat(c, at: pointer) }
            }
            if resized { userDrag?.resized = true }
            if c.isfloating { c.floatGeom = actual.insetBy(dx: -c.bw, dy: -c.bw); c.geom = c.floatGeom; c.iscustomsize = true }
            c.frame = actual
            standsAt(c, actual)
            server.updateBorders()
            if server.dragTile?.client === c { server.updateDragTile(at: pointer) }
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
        if server.dragTile?.client === c {
            c.frame = actual
            server.dropDraggedTile(at: p)
            if !server.config.dragTileToTile {
                if let cm = c.mon { server.arrange(cm, false, false) }
                server.applyWindowSnap(c)
                server.printstatus(.arrangge)
            }
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
            server.resizeTileClient(c, offsetX: dx, offsetY: dy)
        }
        c.frame = actual
        server.arrange(m, false, false)
        server.printstatus(.arrangge)
    }
}
