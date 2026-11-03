import CoreGraphics

package extension MangoServer {
    package func handleCursorSwipeUpdate(_ s: Swipe, time: UInt32) {
        // not in mango: no swipe begin from macOS; the first update begins it (handle_cursor_swipe_begin)
        if swipeDrive == nil {
            system.keyboardCancelPendingReleaseBind()
            swipeDrive = SwipeDrive()
        }
        swipeDriveUpdate(s, time: time)
    }

    package func handleCursorSwipeEnd(_ s: Swipe) {
        let consumed = swipeDrive?.consumed ?? false
        swipeDriveEnd(s)
        if !consumed { pointerProcessSwipeEnd(s) }
        swipeDrive = nil
    }

    func swipeFindBinding(_ motion: Direction, fingers: Int) -> GestureBinding? {
        let mods = system.modifiers.subtracting(.fn)
        return config.gestureBindings.first {
            ($0.mode == "common" || $0.mode == keyMode) && $0.mods == mods && !$0.isUndir && ($0.direction == nil || $0.direction == motion) && $0.fingers == fingers
        }
    }

    static let viewOpposites = [
        "viewtoleft": "viewtoright", "viewtoright": "viewtoleft",
        "viewtoleft_have_client": "viewtoright_have_client", "viewtoright_have_client": "viewtoleft_have_client",
        "viewprev_have_client": "viewnext_have_client", "viewnext_have_client": "viewprev_have_client",
    ]

    func swipeFuncDrivable(_ b: GestureBinding, _ motion: Direction, on m: Monitor) -> Bool {
        let name = b.dispatch.name
        if name == "moveresize" || Self.viewOpposites[name] != nil { return true }
        let vertical = motion == .up || motion == .down
        switch name {
        case "focusdir":
            guard m.layout.isScroller, let d = Direction(mangoName: b.dispatch.arg(0)) else { return false }
            return m.layout == .verticalScroller ? !d.isHorizontal : d.isHorizontal
        case "toggleoverview":
            return vertical && (overviewState != nil ? motion == .down : motion == .up)
        case "enteroverview":
            return vertical && overviewState == nil
        case "leaveoverview":
            return vertical && overviewState != nil
        default:
            return false
        }
    }

    internal func swipeDriveUpdate(_ s: Swipe, time: UInt32) {
        guard var drive = swipeDrive else { return }
        if !drive.locked {
            if abs(s.dx) < SwipeDrive.lockDistance && abs(s.dy) < SwipeDrive.lockDistance { return }
            drive.locked = true
            drive.horizontal = abs(s.dx) >= abs(s.dy)
        }
        let axis = drive.horizontal ? s.dx : s.dy
        let step = abs(axis - drive.prevAxis)
        drive.prevAxis = axis
        if drive.speedPoints < 1000 {
            drive.avgSpeed = (drive.avgSpeed * Double(drive.speedPoints) + step) / Double(drive.speedPoints + 1)
            if drive.speedPoints == 0 { drive.firstTime = time }
            drive.speedPoints += 1
            drive.lastTime = time
        }
        defer { swipeDrive = drive }
        guard drive.active, let d = swipeDriving else {
            if !drive.consumed { swipeDrive = drive; swipeDriveBegin(s); drive = swipeDrive ?? drive }
            return
        }
        let m = d.monitor
        let distance = Double(config.gestureSwipeDistance)
        switch drive.kind {
        case .drag:
            let w = m.screen.workArea
            pointerProcessMotion(CGPoint(x: d.dragStart.x + s.dx * w.width / distance, y: d.dragStart.y + s.dy * w.height / distance),
                                 time: time)
        case .pan:
            let extent = Double(drive.horizontal ? m.screen.workArea.width : m.screen.workArea.height)
            swipeDriveApplyPan(swipeDrivePanOffset((axis - drive.base) / distance * extent, horizontal: drive.horizontal, on: m),
                     horizontal: drive.horizontal)
        case .transition:
            let delta = (axis - drive.base) * drive.dir
            if delta / distance < 1 && delta > drive.maxDelta { drive.maxDelta = delta }
            system.setAnimationProgress(min(1, max(0, delta / distance)))
        }
    }

    internal func swipeDriveBegin(_ s: Swipe) {
        guard var drive = swipeDrive, let m = selectedMonitor else { return }
        let axis = drive.horizontal ? s.dx : s.dy
        let motion: Direction = drive.horizontal ? (axis < 0 ? .left : .right) : (axis < 0 ? .up : .down)
        func begin(_ kind: SwipeDrive.Kind) {
            drive.consumed = true
            drive.kind = kind
            drive.dir = axis < 0 ? -1 : 1
            drive.base = kind == .pan ? axis : axis - drive.dir * SwipeDrive.lockDistance
            drive.active = true
        }
        guard let b = swipeFindBinding(motion, fingers: s.fingers), swipeFuncDrivable(b, motion, on: m) else { return }
        let name = b.dispatch.name
        let drag = name == "moveresize"
        if !config.gestureLive && !drag { return }
        let selBefore = m.sel
        if drag {
            guard let c = focused, !c.isFullscreen, !c.isMaximizeScreen else { drive.consumed = false; swipeDrive = drive; return }
            let p = system.pointer
            pointerBeginMoveResize(c, b.dispatch.arg(0) == "curresize" ? .resize : .move, at: p)
            guard let g = grab else { swipeDrive = drive; return }
            begin(.drag)
            swipeDrive = drive
            swipeDriving = (b, m, selBefore, [:], g.startMouse)
            return
        }
        if name == "focusdir" {
            begin(.pan)
            swipeDrive = drive
            let frames = Dictionary(uniqueKeysWithValues: tiledClients(m).compactMap { c in c.geom.map { (c.id, $0) } })
            swipeDriving = (b, m, selBefore, frames, .zero)
            swipeDriveApplyPan(0, horizontal: drive.horizontal)
            return
        }
        begin(.transition)
        system.holdAnimations()
        _ = dispatch(b.dispatch)
        guard system.animationsActive else {
            system.letGoAnimations()
            drive.active = false
            swipeDrive = drive
            return
        }
        swipeDrive = drive
        swipeDriving = (b, m, selBefore, [:], .zero)
        system.setAnimationProgress(0)
    }

    internal func swipeDriveEnd(_ s: Swipe) {
        guard let drive = swipeDrive, drive.active, let d = swipeDriving else { return }
        swipeDriving = nil
        let m = d.monitor
        let distance = Double(config.gestureSwipeDistance)
        let axis = drive.horizontal ? s.dx : s.dy
        let quick = drive.speedPoints > 0
            && (drive.avgSpeed >= config.gestureSwipeMinSpeedToForce || drive.lastTime &- drive.firstTime <= SwipeDrive.flickMaxMs)
        switch drive.kind {
        case .drag:
            if let g = grab {
                let w = m.screen.workArea
                pointerEndGrabClient(g, at: CGPoint(x: g.startMouse.x + s.dx * w.width / distance,
                                                    y: g.startMouse.y + s.dy * w.height / distance), followPointer: false)
            }
        case .pan:
            let extent = Double(drive.horizontal ? m.screen.workArea.width : m.screen.workArea.height)
            var offset = swipeDrivePanOffset((axis - drive.base) / distance * extent, horizontal: drive.horizontal, on: m)
            var target = swipeDrivePanTarget(offset, horizontal: drive.horizontal, frames: d.panFrames, on: m)
            if target?.id == d.startSel, quick,
               let flick = swipeDrivePanFlickTarget(dir: offset < 0 ? -1 : 1, horizontal: drive.horizontal, frames: d.panFrames, on: m) {
                (offset, target) = flick
            }
            if let t = target, t.id != d.startSel {
                swipeDriveApplyPan(offset, horizontal: drive.horizontal)
                clientFocus(t)
            }
            arrange(m, .move)
        case .transition:
            let delta = (axis - drive.base) * drive.dir
            let overview = ["toggleoverview", "enteroverview", "leaveoverview"].contains(d.binding.dispatch.name)
            let flick = delta >= drive.maxDelta - SwipeDrive.lockDistance && quick
            if overview || delta >= distance * config.gestureSwipeCancelRatio || flick {
                system.resumeAnimations(from: min(1, max(0, delta / distance)))
            } else {
                system.letGoAnimations()
                if let back = Self.viewOpposites[d.binding.dispatch.name] {
                    _ = dispatch(Dispatch(name: back, args: d.binding.dispatch.args))
                }
            }
        }
    }

    func swipeDriveApplyPan(_ offset: Double, horizontal: Bool) {
        guard let d = swipeDriving else { return }
        var shown: [ClientID: CGRect] = [:]
        for (id, f) in d.panFrames {
            guard let c = clientByIdAll(id) else { continue }
            let to = f.offsetBy(dx: horizontal ? CGFloat(offset.rounded()) : 0, dy: horizontal ? 0 : CGFloat(offset.rounded()))
            c.frame = to
            c.parked = false
            system.setFrame(c, to, size: false)
            shown[id] = to
        }
        updateBorders(animating: shown)
    }

    func swipeDrivePanOffset(_ raw: Double, horizontal: Bool, on m: Monitor) -> Double {
        let w = m.screen.workArea
        let monCenter = Double(horizontal ? w.width : w.height) / 2
        let offsets = (swipeDriving?.panFrames.values.map { f in
            monCenter - Double(horizontal ? f.midX - w.minX : f.midY - w.minY)
        }) ?? []
        guard let lo = offsets.min(), let hi = offsets.max() else { return raw }
        if raw < lo { return lo + (raw - lo) * 0.25 }
        if raw > hi { return hi + (raw - hi) * 0.25 }
        return raw
    }

    func swipeDrivePanTarget(_ offset: Double, horizontal: Bool, frames: [ClientID: CGRect], on m: Monitor) -> Client? {
        let w = m.screen.workArea
        return frames.min { a, b in
            func dist(_ f: CGRect) -> Double {
                let cx = Double(f.midX) + (horizontal ? offset : 0), cy = Double(f.midY) + (horizontal ? 0 : offset)
                return pow(cx - Double(w.midX), 2) + pow(cy - Double(w.midY), 2)
            }
            return dist(a.value) < dist(b.value)
        }.flatMap { clientByIdAll($0.key) }
    }

    func swipeDrivePanFlickTarget(dir: Double, horizontal: Bool, frames: [ClientID: CGRect], on m: Monitor) -> (Double, Client)? {
        guard let sel = m.sel, let selFrame = frames[sel] else { return nil }
        let w = m.screen.workArea
        let origin = Double(horizontal ? w.minX : w.minY), monCenter = Double(horizontal ? w.width : w.height) / 2
        func offset(_ f: CGRect) -> Double { monCenter - (Double(horizontal ? f.midX : f.midY) - origin) }
        let base = offset(selFrame)
        var best: (delta: Double, offset: Double, id: ClientID)?
        for (id, f) in frames where id != sel {
            let o = offset(f), delta = (o - base) * dir
            guard delta > 0 else { continue }
            if best == nil || delta < best!.delta { best = (delta, o, id) }
        }
        guard let b = best, let c = clientByIdAll(b.id) else { return nil }
        return (b.offset, c)
    }

    @discardableResult
    func pointerProcessSwipeEnd(_ s: Swipe) -> Bool {
        let adx = Int(abs(s.dx).rounded()), ady = Int(abs(s.dy).rounded())
        if adx * adx + ady * ady < config.swipeMinThreshold * config.swipeMinThreshold { return false }
        let motion: Direction
        if adx > ady {
            motion = s.dx < 0 ? .left : .right
        } else {
            motion = s.dy < 0 ? .up : .down
        }
        return fireGestureMotion(motion, s.fingers)
    }
}
