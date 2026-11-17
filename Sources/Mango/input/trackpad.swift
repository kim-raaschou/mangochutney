/* Trackpad gestures (swipe / pinch / hold). */
import CoreGraphics
import Foundation

// not in mango: pointer_is_trackpad, check_trackpad_disabled and trackpad_enabled (disable_trackpad is
// MangoCompat's: macOS cannot switch the trackpad off); the pinch and hold handlers (macOS's multitouch frames
// give the port no pinch or hold); the gestures sent on to the client (wlr_pointer_gestures_v1, macOS's)

let SWIPE_LOCK_DISTANCE = 16.0
let SWIPE_FLICK_MAX_MS: UInt32 = 200

package struct SwipeDrive {
    var active = false
    var consumed = false
    var pan = false
    var drag = false
    var mon: Monitor?
    var fingers: UInt32 = 0
    var startSel: ClientID?
    var horizontal = false
    var base = 0.0
    var dir = 0.0
    var prevAxis = 0.0
    var avgSpeed = 0.0
    var speedPoints: UInt32 = 0
    var firstTime: UInt32 = 0
    var lastTime: UInt32 = 0
    var dragPrevDx = 0.0
    var dragPrevDy = 0.0
    var motion: UInt32 = 0
    var maxDelta = 0.0
    var `func`: String?   // not in mango: the dispatcher's name (Swift cannot compare functions)
    var arg = Arg()
}

package extension MangoServer {
    @discardableResult
    func fireGestureMotion(_ motion: UInt32, _ fingers: UInt32) -> Bool {
        var handled = false
        let mods = system.keyboardHardModifiers().subtracting(.fn)

        for g in config.gestureBindings {
            if (g.mode == "common" || g.mode == keyMode) &&
                mods == g.mods &&
                fingers == g.fingersCount &&
                (g.motion == UInt32(ALLDIR) || motion == g.motion) {
                if g.dispatch.name == "moveresize" {
                    continue
                }
                _ = dispatch(g.dispatch)
                handled = true
            }
        }

        return handled
    }

    func swipeOppositeMotion(_ motion: UInt32) -> UInt32 {
        if motion == SWIPE_LEFT { return SWIPE_RIGHT }
        if motion == SWIPE_RIGHT { return SWIPE_LEFT }
        if motion == SWIPE_UP { return SWIPE_DOWN }
        return SWIPE_UP
    }

    func trackpadGestureDragActive() -> Bool {
        swipeActive && swipeDrive.drag && swipeDrive.active
    }

    func viewOppositeFunc(_ f: String) -> String? {
        if f == "viewtoleft" { return "viewtoright" }
        if f == "viewtoright" { return "viewtoleft" }
        if f == "viewtoleft_have_client" { return "viewtoright_have_client" }
        if f == "viewtoright_have_client" { return "viewtoleft_have_client" }
        if f == "viewprev_have_client" { return "viewnext_have_client" }
        if f == "viewnext_have_client" { return "viewprev_have_client" }
        return nil
    }

    func swipeFuncIsView(_ f: String) -> Bool {
        viewOppositeFunc(f) != nil
    }

    func swipeFuncIsOverview(_ f: String) -> Bool {
        f == "toggleoverview" || f == "enteroverview" || f == "leaveoverview"
    }

    func swipeLayoutIsScroller(_ m: Monitor?, _ vertical: inout Bool) -> Bool {
        guard let m else { return false }
        let l = m.pertag.ltidxs[getMonCurtag(m)]
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

    func swipeFuncDrivable(_ f: String, _ arg: Arg, _ motion: UInt32, _ m: Monitor) -> Bool {
        if f == "moveresize" { return true }

        if swipeFuncIsView(f) { return true }

        if f == "focusdir" {
            var vertical = false
            if !swipeLayoutIsScroller(m, &vertical) { return false }
            if vertical { return arg.i == UP || arg.i == DOWN }
            return arg.i == LEFT || arg.i == RIGHT
        }

        if f == "toggleoverview" {
            if motion != SWIPE_UP && motion != SWIPE_DOWN { return false }
            return m.isoverview ? motion == SWIPE_DOWN : motion == SWIPE_UP
        }

        if f == "enteroverview" {
            if motion != SWIPE_UP && motion != SWIPE_DOWN { return false }
            return !m.isoverview
        }

        if f == "leaveoverview" {
            if motion != SWIPE_UP && motion != SWIPE_DOWN { return false }
            return m.isoverview
        }

        return false
    }

    func swipeFindBinding(_ motion: UInt32, _ fingers: UInt32) -> GestureBinding? {
        let mods = system.keyboardHardModifiers().subtracting(.fn)

        for g in config.gestureBindings {
            if (g.mode == "common" || g.mode == keyMode) &&
                mods == g.mods &&
                fingers == g.fingersCount &&
                (g.motion == UInt32(ALLDIR) || motion == g.motion) {
                return g
            }
        }
        return nil
    }

    // not in mango: the binding's func and Arg, as parse_func_name gives them when mango reads the config
    func swipeBindingFunc(_ d: Dispatch) -> (func: String, arg: Arg) {
        var arg = Arg()
        let a = (0..<5).map { $0 < d.args.count ? d.args[$0] : "0" }
        _ = BindingParser.parseFuncName(d.name, &arg, a[0], a[1], a[2], a[3], a[4])
        return (d.name, arg)
    }

    // not in mango: func(&arg), the function found by its name
    func swipeCall(_ f: String, _ arg: Arg) {
        var unused = Arg()
        guard let fn = BindingParser.parseFuncName(f, &unused, "0", "0", "0", "0", "0") else { return }
        _ = fn(self)(arg)
        system.rescan()   // not in mango: the port's side
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
                if ISTILED(c) { tiled += 1 }
            }
            if c.animation.running && c.needOutputFlush {
                running += 1
                if c.animation.action == .tag || c.animation.action == .move || c.animation.action == .overview { geometry += 1 }
            }
        }

        mangoError(true, .debug, "swipe drive: \(why) (vis=\(visible) tiled=\(tiled) run=\(running) geom=\(geometry) "
                   + "sel_changed=\(selChanged ? 1 : 0) sel_before=\(selBefore.map(String.init) ?? "nil") sel_now=\(m.sel.map(String.init) ?? "nil"))\n")
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

        let monCx = Double(m.w.minX) + Double(m.w.width) / 2.0
        let monCy = Double(m.w.minY) + Double(m.w.height) / 2.0
        var best: Client?
        var bestDist = 0.0
        let horizontal = swipeHorizontal

        for c in clients {
            /* Scroller pages include maximized/fullscreen windows, which are
             * excluded by ISTILED; keep the drag strip consistent with scroller()
             * so a maximized/fullscreen page can be panned away like any other. */
            if c.mon !== m || !VISIBLEON(c, m) || !ISSCROLLTILED(c) { continue }

            var cx = Double(c.geom.minX) + Double(c.geom.width) / 2.0
            var cy = Double(c.geom.minY) + Double(c.geom.height) / 2.0
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
            if c.mon !== m || !VISIBLEON(c, m) || !ISSCROLLTILED(c) { continue }

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
        let monCenter = Double(horizontal ? m.w.width : m.w.height) / 2.0

        for c in clients {
            if c.mon !== m || !VISIBLEON(c, m) || !ISSCROLLTILED(c) { continue }

            let center = horizontal ? Double(c.geom.minX) + Double(c.geom.width) / 2.0
                                    : Double(c.geom.minY) + Double(c.geom.height) / 2.0
            let centerRel = center - Double(horizontal ? m.w.minX : m.w.minY)
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

        let horizontal = swipeHorizontal
        let monOrigin = Double(horizontal ? m.w.minX : m.w.minY)
        let monCenter = Double(horizontal ? m.w.width : m.w.height) / 2.0
        let selCenter = horizontal ? Double(sel.geom.minX) + Double(sel.geom.width) / 2.0
                                   : Double(sel.geom.minY) + Double(sel.geom.height) / 2.0
        let baseOffset = monCenter - (selCenter - monOrigin)

        var best: Client?
        var bestDelta = 0.0
        var bestOffset = 0.0
        for c in clients {
            if c.mon !== m || !VISIBLEON(c, m) || !ISSCROLLTILED(c) || c === sel { continue }

            let center = horizontal ? Double(c.geom.minX) + Double(c.geom.width) / 2.0
                                    : Double(c.geom.minY) + Double(c.geom.height) / 2.0
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

    func swipeDriveBegin(_ fingers: UInt32) -> Bool {
        guard let m = selectedMonitor else { return false }
        let selBefore = m.sel

        let axis = swipeDriveAxis()
        let motion = swipeHorizontal ? (axis < 0 ? SWIPE_LEFT : SWIPE_RIGHT)
                                     : (axis < 0 ? SWIPE_UP : SWIPE_DOWN)

        guard let binding = swipeFindBinding(motion, fingers) else { return false }
        let (execFunc, execArg) = swipeBindingFunc(binding.dispatch)
        if !swipeFuncDrivable(execFunc, execArg, motion, m) { return false }

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

            let cursor = system.pointer
            if !pointerBeginMoveResize(target, execArg.ui, cursor.x, cursor.y, []) {
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
        swipeCall(execFunc, execArg)

        if !swipeHasRunningTransition(m) {
            swipeDriveUnfreeze()
            swipeDriveLogState(m, "fired but no transition", m.sel != selBefore, selBefore)
            let name = execFunc == "toggleoverview" ? "toggle_overview"
                : execFunc == "enteroverview" ? "enter_overview"
                : execFunc == "leaveoverview" ? "leave_overview"
                : execFunc == "focusdir" ? "focus_direction"
                : "view switch"
            mangoError(true, .debug, "swipe drive: \(name) fired but produced no transition\n")
            return true /* command had no effect (edge, empty tag, ...) */
        }

        swipeDrive.active = true
        swipeDriveApply(m, 0.0)
        swipeDriveLogState(m, "driving transition", m.sel != selBefore, selBefore)
        mangoError(true, .debug, "swipe drive: driving transition, motion=\(swipeDrive.motion) fingers=\(swipeDrive.fingers)\n")
        return true
    }

    @discardableResult
    func swipeDriveFireOpposite() -> Bool {
        guard let f = swipeDrive.func else { return false }

        if swipeFuncIsView(f) {
            guard let opposite = viewOppositeFunc(f) else { return false }
            swipeCall(opposite, swipeDrive.arg)
            swipeDrive.func = opposite
        } else if f == "focusdir" {
            var a = swipeDrive.arg
            if swipeDrive.motion == SWIPE_LEFT {
                a.i = RIGHT
            } else if swipeDrive.motion == SWIPE_RIGHT {
                a.i = LEFT
            } else if swipeDrive.motion == SWIPE_UP {
                a.i = DOWN
            } else {
                a.i = UP
            }
            swipeCall("focusdir", a)
            swipeDrive.arg = a
        } else if f == "toggleoverview" {
            swipeCall("toggleoverview", swipeDrive.arg)
        } else if f == "enteroverview" {
            swipeCall("leaveoverview", swipeDrive.arg)
            swipeDrive.func = "leaveoverview"
        } else if f == "leaveoverview" {
            swipeCall("enteroverview", swipeDrive.arg)
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

        guard grabClient != nil, let m, distance > 0 else { return }

        let scaleX = Double(m.w.width) / distance
        let scaleY = Double(m.w.height) / distance

        let dx = (swipeDx - swipeDrive.dragPrevDx) * scaleX
        let dy = (swipeDy - swipeDrive.dragPrevDy) * scaleY
        swipeDrive.dragPrevDx = swipeDx
        swipeDrive.dragPrevDy = swipeDy

        if dx == 0.0 && dy == 0.0 { return }

        // not in mango: pointer_process_motion's wlr_cursor_move (macOS moves the pointer itself for its own events)
        let p = system.pointer
        system.warp(to: CGPoint(x: p.x + dx, y: p.y + dy))
        pointerProcessMotion(time, dx, dy)
        requestFreshAllMonitors()
    }

    /* Advance the driven transition on every swipe update.  Returns true when the
     * compositor took over the gesture. */
    @discardableResult
    func swipeDriveUpdate(_ fingers: UInt32, _ time: UInt32) -> Bool {
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

        let m = swipeDrive.mon

        if swipeDrive.drag {
            swipeDriveApplyDrag(m, time)
            return true
        }

        guard let m else { return true }   // not in mango: mon is optional

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
            pointerEndGrabClient(false)
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
                    mangoError(true, .debug, "swipe drive: pan commit, offset=\(Int(offset.rounded())) target=\(target.id)\n")

                    let shift = CGFloat(offset.rounded())
                    if shift != 0 {
                        for c in clients {
                            if c.mon !== m || !VISIBLEON(c, m) || !ISSCROLLTILED(c) { continue }
                            if swipeHorizontal { c.geom.origin.x += shift } else { c.geom.origin.y += shift }
                        }
                    }

                    clientFocus(target, true)
                    arrange(m, false, false)
                } else {
                    mangoError(true, .debug, "swipe drive: pan revert, offset=\(Int(offset.rounded()))\n")
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
                mangoError(true, .debug, "swipe drive: commit, p=\(String(format: "%.2f", p)) speed=\(String(format: "%.1f", swipeDrive.avgSpeed))\n")
                for c in clients {
                    if c.mon !== m || !c.animation.running || !c.needOutputFlush { continue }
                    if c.animation.action != .tag && c.animation.action != .move
                        && c.animation.action != .overview && !c.animation.tagining
                        && !c.animation.tagouting { continue }

                    clientAnimationResume(c, 1.0 - p)
                }
                requestFreshAllMonitors()
                if !config.animations { pointerProcessMotion(0, 0, 0) }
            } else {
                mangoError(true, .debug, "swipe drive: revert, p=\(String(format: "%.2f", p)) speed=\(String(format: "%.1f", swipeDrive.avgSpeed))\n")
                swipeDriveFireOpposite()
            }

            swipeDrive.active = false
        }

        swipeDrive.consumed = false
        swipeDrive.speedPoints = 0
        swipeDrive.avgSpeed = 0
    }

    // not in mango: the event's fingers
    package func handleCursorSwipeBegin(_ fingers: Int) {
        system.keyboardCancelPendingReleaseBind()

        swipeDriveUnfreeze()
        swipeActive = true
        swipeLocked = false
        swipeHorizontal = false
        swipeDrive = SwipeDrive()
        swipeFingers = UInt32(fingers)
        swipeDx = 0
        swipeDy = 0
    }

    // not in mango: the event's fields
    package func handleCursorSwipeUpdate(_ event: Swipe, time: UInt32) {
        swipeFingers = UInt32(event.fingers)
        // Accumulate swipe distance
        swipeDx += event.dx
        swipeDy += event.dy

        swipeDriveUpdate(UInt32(event.fingers), time)
    }

    // not in mango: no event; a swipe is never cancelled (macOS's multitouch frames, docs/afvigelser.md §3)
    // not in mango: the event's cancelled flag alone
    package func handleCursorSwipeEnd(cancelled: Bool = false) {
        let consumed = swipeDrive.consumed
        swipeDriveEnd()

        if !consumed && !cancelled {
            /* No finger-driven transition: keep the previous release-based
             * behavior so short flicks and non-drivable bindings still work. */
            pointerProcessSwipeEnd(cancelled: cancelled)
        }

        swipeActive = false
        swipeDx = 0
        swipeDy = 0
    }

    // New from here
    // not in mango: the event's cancelled flag alone
    @discardableResult
    func pointerProcessSwipeEnd(cancelled: Bool = false) -> Int32 {
        let motion: UInt32
        let adx = UInt32(Int32(abs(swipeDx).rounded()))
        let ady = UInt32(Int32(abs(swipeDy).rounded()))

        if cancelled {
            return 0
        }

        // Require absolute distance movement beyond a small thresh-hold
        let threshold = UInt32(truncatingIfNeeded: config.swipeMinThreshold)
        if adx &* adx &+ ady &* ady < threshold &* threshold {
            return 0
        }

        if adx > ady {
            motion = swipeDx < 0 ? SWIPE_LEFT : SWIPE_RIGHT
        } else {
            motion = swipeDy < 0 ? SWIPE_UP : SWIPE_DOWN
        }

        return fireGestureMotion(motion, swipeFingers) ? 1 : 0
    }
}
