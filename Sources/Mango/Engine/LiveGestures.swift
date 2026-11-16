import CoreGraphics
import Foundation

package extension MangoServer {
    func trackpadGestureDragActive() -> Bool {
        swipeActive && swipeDrive.drag && swipeDrive.active
    }

    func swipeOppositeMotion(_ motion: Direction) -> Direction {
        if motion == .left { return .right }
        if motion == .right { return .left }
        if motion == .up { return .down }
        return .up
    }

    func viewOppositeFunc(_ f: String) -> String? {
        switch f {
        case "viewtoleft": return "viewtoright"
        case "viewtoright": return "viewtoleft"
        case "viewtoleft_have_client": return "viewtoright_have_client"
        case "viewtoright_have_client": return "viewtoleft_have_client"
        case "viewprev_have_client": return "viewnext_have_client"
        case "viewnext_have_client": return "viewprev_have_client"
        default: return nil
        }
    }

    func swipeFuncIsView(_ f: String) -> Bool { viewOppositeFunc(f) != nil }

    func swipeFuncIsOverview(_ f: String) -> Bool {
        f == "toggleoverview" || f == "enteroverview" || f == "leaveoverview"
    }

    func swipeLayoutIsScroller(_ m: Monitor, _ vertical: inout Bool) -> Bool {
        let l = m.layout
        if l == .verticalScroller {
            vertical = true
            return true
        }
        if l == .scroller {
            vertical = false
            return true
        }
        return false
    }

    func swipeFuncDrivable(_ f: String, _ arg: [String], _ motion: Direction, _ m: Monitor) -> Bool {
        if f == "moveresize" { return true }

        if swipeFuncIsView(f) { return true }

        if f == "focusdir" {
            var vertical = false
            if !swipeLayoutIsScroller(m, &vertical) { return false }
            let i = Direction(mangoName: arg.first ?? "")
            if vertical { return i == .up || i == .down }
            return i == .left || i == .right
        }

        let isoverview = m.isoverview
        if f == "toggleoverview" {
            if motion != .up && motion != .down { return false }
            return isoverview ? motion == .down : motion == .up
        }

        if f == "enteroverview" {
            if motion != .up && motion != .down { return false }
            return !isoverview
        }

        if f == "leaveoverview" {
            if motion != .up && motion != .down { return false }
            return isoverview
        }

        return false
    }

    func swipeFindBinding(_ motion: Direction, _ fingers: Int) -> GestureBinding? {
        let mods = system.keyboardHardModifiers().subtracting(.fn)
        return config.gestureBindings.first {
            ($0.mode == "common" || $0.mode == keyMode) && $0.mods == mods && $0.fingers == fingers
                && !$0.isUndir && ($0.direction == nil || $0.direction == motion)
        }
    }

    func swipeHasRunningTransition(_ m: Monitor) -> Bool {
        for c in clients {
            if c.mon !== m || !c.animation.running || !c.needOutputFlush { continue }
            if c.animation.action == .tag || c.animation.action == .move
                || c.animation.action == .overview || c.animation.tagining
                || c.animation.tagouting { return true }
        }
        return false
    }

    func swipeDriveLogState(_ m: Monitor?, _ why: String, _ selChanged: Bool, _ selBefore: ClientID?) {
        guard let m else { return }

        var visible = 0
        var tiled = 0
        var running = 0
        var geometry = 0

        for c in clients {
            if c.mon !== m { continue }
            if VISIBLEON(c, m) {
                visible += 1
                if Self.isTiled(c) { tiled += 1 }
            }
            if c.animation.running {
                running += 1
                if c.animation.action == .tag || c.animation.action == .move || c.animation.action == .overview { geometry += 1 }
            }
        }

        wlrLog(.debug, "swipe drive: \(why) (vis=\(visible) tiled=\(tiled) run=\(running) geom=\(geometry) "
               + "sel_changed=\(selChanged ? 1 : 0) sel_before=\(selBefore.map(String.init) ?? "nil") sel_now=\(m.sel.map(String.init) ?? "nil"))")
    }

    func swipeDriveFreeze(_ m: Monitor) {
        gestureDriveMon = m
        gestureDriveActive = true
    }

    func swipeDriveUnfreeze() {
        gestureDriveActive = false
        gestureDriveMon = nil
    }

    func swipeDriveAxis() -> Double {
        swipeHorizontal ? swipeDx : swipeDy
    }

    func swipeDriveApply(_ m: Monitor, _ p: Double) {
        for c in clients {
            if c.mon !== m || !c.animation.running || !c.needOutputFlush { continue }
            if c.animation.action != .tag && c.animation.action != .move
                && c.animation.action != .overview && !c.animation.tagining
                && !c.animation.tagouting { continue }
            clientAnimationSetProgress(c, p)
        }

        requestFreshAllMonitors()
    }

    func swipeDrivePanTarget(_ m: Monitor, _ offset: Double) -> Client? {
        if m.sel == nil { return nil }

        let w = m.w
        let monCx = Double(w.minX + w.width / 2)
        let monCy = Double(w.minY + w.height / 2)
        var best: Client?
        var bestDist = 0.0
        let horizontal = swipeHorizontal

        for c in clients {
            /* Scroller pages include maximized/fullscreen windows, which are
             * excluded by ISTILED; keep the drag strip consistent with scroller()
             * so a maximized/fullscreen page can be panned away like any other. */
            if c.mon !== m || !VISIBLEON(c, m) || !Self.isScrollTiled(c) { continue }
            let g = c.geom

            var cx = Double(g.minX + g.width / 2)
            var cy = Double(g.minY + g.height / 2)
            if horizontal { cx += offset } else { cy += offset }

            let dx = cx - monCx
            let dy = cy - monCy
            let dist = dx * dx + dy * dy
            if best == nil || dist < bestDist {
                best = c
                bestDist = dist
            }
        }

        return best
    }

    func swipeDriveApplyPan(_ m: Monitor, _ offset: Double) {
        let horizontal = swipeHorizontal

        for c in clients {
            if c.mon !== m || !VISIBLEON(c, m) || !Self.isScrollTiled(c) { continue }

            var box = c.geom
            if horizontal { box.origin.x += CGFloat(offset.rounded()) } else { box.origin.y += CGFloat(offset.rounded()) }

            system.sceneNodeSetPosition(c, box.minX, box.minY)   // not in mango: the port's wlr_scene_node_set_position
            c.animation.current = box
            c.current = box
            clientSetClip(c, 1.0)
        }

        requestFreshAllMonitors()
    }

    /* Computes the pan range that keeps at least one window centrable, then
     * applies a soft rubber band outside of it so the strip never hard-stops
     * mid-gesture. */
    func swipeDrivePanOffset(_ m: Monitor, _ raw: Double) -> Double {
        var lo = 0.0, hi = 0.0
        var first = true
        let horizontal = swipeHorizontal
        let w = m.w
        let monCenter = Double(horizontal ? w.width : w.height) / 2

        for c in clients {
            if c.mon !== m || !VISIBLEON(c, m) || !Self.isScrollTiled(c) { continue }
            let g = c.geom

            let center = Double(horizontal ? g.minX + g.width / 2 : g.minY + g.height / 2)
            let centerRel = center - Double(horizontal ? w.minX : w.minY)
            let o = monCenter - centerRel
            if first {
                lo = o
                hi = o
                first = false
            } else {
                if o < lo { lo = o }
                if o > hi { hi = o }
            }
        }

        if first { return raw }

        /* Soft rubber band outside the valid range; never a hard stop. */
        if raw < lo { return lo + (raw - lo) * 0.25 }
        if raw > hi { return hi + (raw - hi) * 0.25 }
        return raw
    }

    func swipeDrivePanFlickTarget(_ m: Monitor, _ dir: Double) -> (offset: Double, client: Client)? {
        guard let sel = m.sel.flatMap({ clientByIdAll($0) }) else { return nil }
        let sg = sel.geom

        let horizontal = swipeHorizontal
        let w = m.w
        let monOrigin = Double(horizontal ? w.minX : w.minY)
        let monCenter = Double(horizontal ? w.width : w.height) / 2
        let selCenter = Double(horizontal ? sg.minX + sg.width / 2 : sg.minY + sg.height / 2)
        let baseOffset = monCenter - (selCenter - monOrigin)

        var best: Client?
        var bestDelta = 0.0
        var bestOffset = 0.0
        for c in clients {
            if c.mon !== m || !VISIBLEON(c, m) || !Self.isScrollTiled(c) || c === sel { continue }
            let g = c.geom

            let center = Double(horizontal ? g.minX + g.width / 2 : g.minY + g.height / 2)
            let offset = monCenter - (center - monOrigin)
            let delta = (offset - baseOffset) * dir
            if delta <= 0 { continue }
            if best == nil || delta < bestDelta {
                best = c
                bestDelta = delta
                bestOffset = offset
            }
        }

        guard let best else { return nil }
        return (bestOffset, best)
    }

    func swipeDriveBegin(_ fingers: Int) -> Bool {
        guard let m = selectedMonitor else { return false }
        let selBefore = m.sel

        let axis = swipeDriveAxis()
        let motion: Direction = swipeHorizontal ? (axis < 0 ? .left : .right) : (axis < 0 ? .up : .down)

        guard let binding = swipeFindBinding(motion, fingers),
              swipeFuncDrivable(binding.dispatch.name, binding.dispatch.args, motion, m) else { return false }

        let execFunc = binding.dispatch.name
        let execArg = binding.dispatch.args

        let drag = execFunc == "moveresize"
        if !config.gestureLive && !drag { return false }

        swipeDrive.consumed = true
        swipeDrive.mon = m
        swipeDrive.fingers = fingers
        swipeDrive.horizontal = swipeHorizontal
        swipeDrive.dir = axis < 0 ? -1.0 : 1.0
        swipeDrive.base = axis - swipeDrive.dir * SWIPE_LOCK_DISTANCE
        swipeDrive.motion = motion
        swipeDrive.func = execFunc
        swipeDrive.arg = execArg
        swipeDrive.active = false
        swipeDrive.pan = false
        swipeDrive.drag = false
        swipeDrive.startSel = selBefore

        if drag {
            let target = m.sel.flatMap { clientByIdAll($0) }

            let mode: Grab.Mode = Dispatch(name: execFunc, args: execArg).arg(0) == "curresize" ? .resize : .move
            if !pointerBeginMoveResize(target, mode, at: system.pointer) {
                swipeDrive.consumed = false
                swipeDriveLogState(m, "drag: no window to move", false, selBefore)
                return false
            }

            swipeDrive.drag = true
            swipeDrive.active = true
            swipeDrive.dragPrevDx = swipeDx
            swipeDrive.dragPrevDy = swipeDy
            swipeDriveLogState(m, "dragging window", false, selBefore)
            return true
        }

        if execFunc == "focusdir" {
            swipeDrive.base = axis
            swipeDrive.pan = true
            swipeDrive.active = true
            swipeDriveFreeze(m)
            swipeDriveApplyPan(m, 0.0)
            swipeDriveLogState(m, "panning scroller", false, selBefore)
            return true
        }

        swipeDriveFreeze(m)
        _ = dispatch(Dispatch(name: execFunc, args: execArg))

        if !swipeHasRunningTransition(m) {
            swipeDriveUnfreeze()
            swipeDriveLogState(m, "fired but no transition", m.sel != selBefore, selBefore)
            wlrLog(.debug, "swipe drive: \(swipeFuncIsOverview(execFunc) || execFunc == "focusdir" ? execFunc : "view switch") fired but produced no transition")
            return true /* command had no effect (edge, empty tag, ...) */
        }

        swipeDrive.active = true
        swipeDriveApply(m, 0.0)
        swipeDriveLogState(m, "driving transition", m.sel != selBefore, selBefore)
        wlrLog(.debug, "swipe drive: driving transition, motion=\(swipeDrive.motion) fingers=\(swipeDrive.fingers)")
        return true
    }

    @discardableResult
    func swipeDriveFireOpposite() -> Bool {
        guard let f = swipeDrive.func else { return false }

        if swipeFuncIsView(f) {
            guard let opposite = viewOppositeFunc(f) else { return false }
            _ = dispatch(Dispatch(name: opposite, args: swipeDrive.arg))
            swipeDrive.func = opposite
        } else if f == "focusdir" {
            var a = swipeDrive.arg
            let i: String
            if swipeDrive.motion == .left {
                i = "right"
            } else if swipeDrive.motion == .right {
                i = "left"
            } else if swipeDrive.motion == .up {
                i = "down"
            } else {
                i = "up"
            }
            if a.isEmpty { a = [i] } else { a[0] = i }
            _ = dispatch(Dispatch(name: "focusdir", args: a))
            swipeDrive.arg = a
        } else if f == "toggleoverview" {
            _ = dispatch(Dispatch(name: "toggleoverview", args: swipeDrive.arg))
        } else if f == "enteroverview" {
            _ = dispatch(Dispatch(name: "leaveoverview", args: swipeDrive.arg))
            swipeDrive.func = "leaveoverview"
        } else if f == "leaveoverview" {
            _ = dispatch(Dispatch(name: "enteroverview", args: swipeDrive.arg))
            swipeDrive.func = "enteroverview"
        } else {
            return false
        }

        swipeDrive.motion = swipeOppositeMotion(swipeDrive.motion)
        swipeDrive.dir = -swipeDrive.dir
        return true
    }

    func swipeDriveApplyDrag(_ m: Monitor?, _ time: UInt32) {
        let distance = Double(config.gestureSwipeDistance)

        guard grab != nil, let m, distance > 0 else { return }

        let scaleX = Double(m.w.width) / distance
        let scaleY = Double(m.w.height) / distance

        let dx = (swipeDx - swipeDrive.dragPrevDx) * scaleX
        let dy = (swipeDy - swipeDrive.dragPrevDy) * scaleY
        swipeDrive.dragPrevDx = swipeDx
        swipeDrive.dragPrevDy = swipeDy

        if dx == 0.0 && dy == 0.0 { return }

        // not in mango: pointer_process_motion's wlr_cursor_move (macOS moves the pointer itself for its own events)
        let p = system.pointer
        let moved = CGPoint(x: p.x + dx, y: p.y + dy)
        system.warp(to: moved)
        pointerProcessMotion(moved, time: time)
    }

    /* Advance the driven transition on every swipe update.  Returns true when the
     * compositor took over the gesture. */
    @discardableResult
    func swipeDriveUpdate(_ fingers: Int, _ time: UInt32) -> Bool {
        if !swipeActive { return false }

        let adx = abs(swipeDx)
        let ady = abs(swipeDy)
        if !swipeLocked {
            if adx < SWIPE_LOCK_DISTANCE && ady < SWIPE_LOCK_DISTANCE { return false }
            swipeLocked = true
            swipeHorizontal = adx >= ady
        }

        let axis = swipeDriveAxis()
        let step = abs(axis - swipeDrive.prevAxis)
        swipeDrive.prevAxis = axis
        if swipeDrive.speedPoints < 1000 {
            swipeDrive.avgSpeed = (swipeDrive.avgSpeed * Double(swipeDrive.speedPoints) + step) / Double(swipeDrive.speedPoints + 1)
            if swipeDrive.speedPoints == 0 { swipeDrive.firstTime = time }
            swipeDrive.speedPoints += 1
            swipeDrive.lastTime = time
        }

        if !swipeDrive.active {
            if swipeDrive.consumed { return true }
            return swipeDriveBegin(fingers)
        }

        guard let m = swipeDrive.mon else { return true }   // not in mango: mon is optional

        if swipeDrive.drag {
            swipeDriveApplyDrag(m, time)
            return true
        }

        let distance = Double(config.gestureSwipeDistance)
        let delta = (axis - swipeDrive.base) * swipeDrive.dir
        var p = delta / distance

        if swipeDrive.pan {
            let extent = Double(swipeHorizontal ? m.w.width : m.w.height)
            let raw = ((axis - swipeDrive.base) / distance) * extent
            let offset = swipeDrivePanOffset(m, raw)
            swipeDriveApplyPan(m, offset)
            return true
        }

        if p >= 1.0 {
            swipeDriveApply(m, 1.0)
            return true
        }

        if delta > swipeDrive.maxDelta { swipeDrive.maxDelta = delta }
        if p < 0.0 { p = 0.0 }
        if p > 1.0 { p = 1.0 }
        swipeDriveApply(m, p)
        return true
    }

    func swipeDriveEnd() {
        let m = swipeDrive.mon

        if swipeDrive.drag {
            if let g = grab { pointerEndGrabClient(g, at: system.pointer, followPointer: false) }
            swipeDrive.drag = false
            swipeDrive.active = false
            swipeDrive.consumed = false
            swipeDrive.speedPoints = 0
            swipeDrive.avgSpeed = 0
            return
        }

        if swipeDrive.active, let m {
            if swipeDrive.pan {
                let axis = swipeDriveAxis()
                let distance = Double(config.gestureSwipeDistance)
                let extent = Double(swipeHorizontal ? m.w.width : m.w.height)
                let raw = ((axis - swipeDrive.base) / distance) * extent
                var offset = swipeDrivePanOffset(m, raw)

                swipeDriveUnfreeze()

                var target = swipeDrivePanTarget(m, offset)

                let dur = swipeDrive.lastTime &- swipeDrive.firstTime
                let speedHit = swipeDrive.speedPoints > 0 && swipeDrive.avgSpeed >= config.gestureSwipeMinSpeedToForce
                let quickHit = swipeDrive.speedPoints > 0 && dur <= SWIPE_FLICK_MAX_MS

                if target?.id == swipeDrive.startSel && (speedHit || quickHit) {
                    let dir = raw < 0 ? -1.0 : 1.0

                    if let flick = swipeDrivePanFlickTarget(m, dir) {
                        offset = flick.offset
                        target = flick.client
                    }
                }

                if let target, target.id != swipeDrive.startSel {
                    wlrLog(.debug, "swipe drive: pan commit, offset=\(Int(offset)) target=\(target.id)")

                    let shift = CGFloat(offset.rounded())
                    if shift != 0 {
                        for c in clients {
                            if c.mon !== m || !VISIBLEON(c, m) || !Self.isScrollTiled(c) { continue }
                            if swipeHorizontal { c.geom.origin.x += shift } else { c.geom.origin.y += shift }
                        }
                    }

                    clientFocus(target, true)
                    arrange(m, false, false)
                } else {
                    wlrLog(.debug, "swipe drive: pan revert, offset=\(Int(offset))")
                    arrange(m, false, false)
                }

                swipeDrive.active = false
                swipeDrive.consumed = false
                swipeDrive.speedPoints = 0
                swipeDrive.avgSpeed = 0
                return
            }

            let axis = swipeDriveAxis()
            let distance = Double(config.gestureSwipeDistance)
            let delta = (axis - swipeDrive.base) * swipeDrive.dir
            var p = delta / distance
            if p < 0.0 { p = 0.0 }
            if p > 1.0 { p = 1.0 }

            let dur = swipeDrive.lastTime &- swipeDrive.firstTime
            let flick = swipeDrive.speedPoints > 0
                && delta >= swipeDrive.maxDelta - SWIPE_LOCK_DISTANCE
                && (swipeDrive.avgSpeed >= config.gestureSwipeMinSpeedToForce || dur <= SWIPE_FLICK_MAX_MS)
            let commit = swipeFuncIsOverview(swipeDrive.func ?? "")
                || delta >= distance * config.gestureSwipeCancelRatio
                || flick

            swipeDriveUnfreeze()

            if commit {
                wlrLog(.debug, "swipe drive: commit, p=\(p) speed=\(swipeDrive.avgSpeed)")
                for c in clients {
                    if c.mon !== m || !c.animation.running || !c.needOutputFlush { continue }
                    if c.animation.action != .tag && c.animation.action != .move
                        && c.animation.action != .overview && !c.animation.tagining
                        && !c.animation.tagouting { continue }

                    clientAnimationResume(c, 1.0 - p)
                }
                if !config.animations { pointerProcessMotion(system.pointer, time: 0) }
            } else {
                wlrLog(.debug, "swipe drive: revert, p=\(p) speed=\(swipeDrive.avgSpeed)")
                swipeDriveFireOpposite()
            }

            swipeDrive.active = false
        }

        swipeDrive.consumed = false
        swipeDrive.speedPoints = 0
        swipeDrive.avgSpeed = 0
    }

    package func handleCursorSwipeBegin(_ fingers: Int) {
        system.keyboardCancelPendingReleaseBind()

        swipeDriveUnfreeze()
        swipeActive = true
        swipeLocked = false
        swipeHorizontal = false
        swipeDrive = SwipeDrive()
        swipeFingers = fingers
        swipeDx = 0
        swipeDy = 0
    }

    package func handleCursorSwipeUpdate(_ event: Swipe, time: UInt32) {
        swipeFingers = event.fingers
        // Accumulate swipe distance
        swipeDx += event.dx
        swipeDy += event.dy

        swipeDriveUpdate(event.fingers, time)
    }

    package func handleCursorSwipeEnd() {
        let consumed = swipeDrive.consumed
        swipeDriveEnd()

        if !consumed {
            /* No finger-driven transition: keep the previous release-based
             * behavior so short flicks and non-drivable bindings still work. */
            pointerProcessSwipeEnd()
        }

        swipeActive = false
        swipeDx = 0
        swipeDy = 0
    }

    @discardableResult
    func pointerProcessSwipeEnd() -> Bool {
        let adx = Int(abs(swipeDx).rounded())
        let ady = Int(abs(swipeDy).rounded())

        // Require absolute distance movement beyond a small thresh-hold
        if adx * adx + ady * ady < config.swipeMinThreshold * config.swipeMinThreshold { return false }

        let motion: Direction
        if adx > ady {
            motion = swipeDx < 0 ? .left : .right
        } else {
            motion = swipeDy < 0 ? .up : .down
        }

        return fireGestureMotion(motion, swipeFingers)
    }
}
