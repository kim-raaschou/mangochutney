import CoreGraphics
import Mango

/// Not in mango: a drag the app itself does, the user holding a window by its own title bar
/// or edges. On Wayland the compositor does every move (pointer.c's grab); on macOS the app
/// moves its window and mango only hears of it afterwards. Here such a drag is followed and,
/// on release, given to mango's code as its own grab's end would be (drag_tile_to_tile,
/// resize_tile_client, the monitor it was let go on).
struct UserDrag {
    let client: Client
    let startFrame: CGRect
    var resized: Bool
}

extension MacWindowSystem {
    /// A plain left press: remember the window under it and where the window server has it.
    func plainMouseDown(at p: CGPoint) {
        pressed = nil
        guard let c = server.clientAtPoint(p), !c.parked, let f = windowServerFrame(c.id) else { return }
        pressed = (c, f)
    }

    /// The pointer moved with the button down: if the pressed window has really moved or
    /// resized since the press, treat it like the app's own move notification. Java apps
    /// (and others) send too few of those while the user drags, so the border stayed behind.
    func followUserDrag() {
        guard let (c, start) = pressed, server.clientByIdAll(c.id) === c, !c.parked,
              let now = windowServerFrame(c.id), now != start, now != c.frame else { return }
        moved(c, to: now, resized: now.size != start.size)
    }

    /// A button let go, after mango's own handling of it (mouseButtonUp).
    func userButtonReleased(button: Int, at p: CGPoint) {
        guard button == 0 else { return }
        pressed = nil
        if let d = userDrag {
            userDrag = nil
            finishUserDrag(d, at: p)
        }
    }

    /// The user moved or resized the window with its own title bar or edges (`dragging`:
    /// still holding it), or its app did. On Wayland neither can happen; mango's own moves
    /// never come here.
    func userMoved(_ c: Client, to actual: CGRect, resized: Bool, dragging: Bool) {
        if dragging {
            if userDrag == nil || userDrag?.client !== c {
                userDrag = UserDrag(client: c, startFrame: c.frame, resized: resized)
                // The app's own title-bar drag of a tiled window: mango's interactive move.
                if !resized { server.clientBeginDragFloat(c, at: pointer) }
            }
            if resized { userDrag?.resized = true }
            if c.isFloating { c.floatGeom = actual; c.isCustomSize = true }
            c.frame = actual
            server.updateBorders(animating: [c.id: actual])
            if server.dragTile?.client === c { server.updateDragTile(at: pointer) }
            return
        }
        if c.isFloating {
            c.floatGeom = actual
            c.frame = actual
            server.updateBorders()
            return
        }
        // App changed its own frame: re-assert (rate limited to avoid fights).
        c.frame = actual
        if let target = c.geom, MangoServer.frameDistance(actual, target) > 0.5 {
            keepPlaced(c, at: target)
        }
        server.updateBorders()
    }

    /// End of a title-bar drag / edge resize by the user: read the final frame on the app's
    /// queue, then apply it on the main thread.
    func finishUserDrag(_ d: UserDrag, at p: CGPoint) {
        let c = d.client
        guard server.clientByIdAll(c.id) === c else { return }
        readFrame(c) { [weak self] actual in
            self?.completeUserDrag(d, actual: actual ?? c.frame, at: p)
        }
    }

    /// As mango's pointer_end_grab_client ends its own grab.
    func completeUserDrag(_ d: UserDrag, actual: CGRect, at p: CGPoint) {
        let c = d.client
        guard server.clientByIdAll(c.id) === c, let m = c.mon else { return }
        if server.dragTile?.client === c {
            c.frame = actual
            server.dropDraggedTile(at: p)
            if !server.config.dragTileToTile {
                if let cm = c.mon { server.arrange(cm, .none) }
                server.applyWindowSnap(c)
                server.printstatus()
            }
            return
        }
        if c.isFloating {
            c.floatGeom = actual
            c.isCustomSize = true
            c.frame = actual
            // as mango's pointer_end_grab_client: the monitor it was let go on takes it
            if let target = server.monitorAtPoint(actual.center), target !== m {
                server.clientSetMonitor(c, target, 0, focus: true)
            }
            server.updateBorders()
            server.applyWindowSnap(c)
            return
        }
        if d.resized {
            // As mango's resizewin step: the size's change. Dwindle's step moves the split
            // lines, so a pulled left or top edge moves them the other way.
            var dx = actual.width - d.startFrame.width, dy = actual.height - d.startFrame.height
            if m.layout == .dwindle {
                if abs(actual.minX - d.startFrame.minX) > 1 { dx = -dx }
                if abs(actual.minY - d.startFrame.minY) > 1 { dy = -dy }
            }
            server.resizeTileClient(c, offsetX: dx, offsetY: dy)
        }
        c.frame = actual
        server.arrange(m, .move)
        server.printstatus()
    }
}
