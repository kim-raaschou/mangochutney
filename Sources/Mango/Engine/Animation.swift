import CoreGraphics

package enum AnimationAction: Equatable {
    case none, open, move, tag, overview
}

package struct TagoutAnimation: Equatable {
    package var to: CGRect
    package var durationMs: Int
    package var curve: BezierCurve
}

package struct ClientAnimation: Equatable {
    package var action: AnimationAction
    package var from: CGRect
    package var durationMs: Int
    package var curve: BezierCurve
}

package extension MangoServer {
    // not in mango: resize's choice of animation, which the port asks before it moves the window
    func clientAnimation(_ c: Client, to target: CGRect, _ anim: ArrangeAnimation, current: CGRect,
                         shown: Bool) -> ClientAnimation {
        let wasTagouting = c.tagouting
        c.tagouting = false
        var a = ClientAnimation(action: .move, from: current, durationMs: config.animationDurationMove,
                                curve: config.animationCurveMove)
        if c.overining && !c.isNew {
            c.overining = false
            a.action = .overview
            a.durationMs = config.animationDurationTag
            a.curve = config.animationCurveTag
            if c.id != c.mon?.sel { a.from = setOverviewEnterAnimation(target) }
        } else if c.scratchpadShown && c.scratchpadTagin {
            c.scratchpadTagin = false
            a.action = .tag
            a.durationMs = config.animationDurationTag
            a.curve = config.animationCurveTag
            if shown && wasTagouting { a.from = current } else { a.from = setArrangeVisible(c, target) }
            c.isNew = false
        } else if c.isNew {
            c.isNew = false
            a.action = .open
            a.durationMs = config.animationDurationOpen
            a.curve = config.animationCurveOpen
            a.from = setClientOpenAnimation(c, target)
        } else if !shown {
            if case .tag = anim, c.tags & TagMask.special != 0 {
                a.action = .tag
                a.durationMs = config.animationDurationTag
                a.curve = config.animationCurveTag
                a.from = setArrangeVisible(c, target)
            } else if case .tag(let forward) = anim {
                a.action = .tag
                a.durationMs = config.animationDurationTag
                a.curve = config.animationCurveTag
                a.from = setTaginAnimation(c, target, forward: forward)
            } else {
                a.action = .none
                a.from = target
            }
        } else if case .none = anim {
            a.action = .none
            a.from = target
        }
        if !config.animations || c.noAnimation || grab?.client === c { a.durationMs = 0 }
        return a
    }

/// mango set_client_open_animation (animation/client.c). Not in mango: fade starts in place (another app's window cannot be faded).
    func setClientOpenAnimation(_ c: Client, _ target: CGRect) -> CGRect {
        switch c.animationTypeOpen ?? config.animationTypeOpen {
        case .zoom:
            let r = CGFloat(config.zoomInitialRatio)
            let w = (target.width * r).rounded(.towardZero), h = (target.height * r).rounded(.towardZero)
            return CGRect(x: target.minX + ((target.width - w) / 2).rounded(.towardZero),
                          y: target.minY + ((target.height - h) / 2).rounded(.towardZero), width: w, height: h)
        case .fade, .none:
            return target
        case .slide:
            guard let mon = c.mon else { return target }
            let m = mon.screen.frame, w = mon.screen.workArea
            var direction = isSpecialAnimationRule(c)
            if direction == nil {
                let cx = target.minX + (target.width / 2).rounded(.towardZero)
                let cy = target.minY + (target.height / 2).rounded(.towardZero)
                let horizontal: Direction = w.maxX - cx < cx - w.minX ? .right : .left
                let horizontalValue = horizontal == .left ? cx - w.minX : w.maxX - cx
                let vertical: Direction = w.maxY - cy < cy - w.minY ? .down : .up
                let verticalValue = vertical == .up ? cy - w.minY : w.maxY - cy
                direction = horizontalValue < verticalValue ? horizontal : vertical
            }
            switch direction! {
            case .up: return CGRect(x: target.minX, y: m.minY - target.height, width: target.width, height: target.height)
            case .down: return CGRect(x: target.minX, y: m.maxY, width: target.width, height: target.height)
            case .left: return CGRect(x: m.minX - target.width, y: target.minY, width: target.width, height: target.height)
            case .right: return CGRect(x: m.maxX, y: target.minY, width: target.width, height: target.height)
            }
        }
    }

    func isSpecialAnimationRule(_ c: Client) -> Direction? {
        guard let m = c.mon, !c.isFloating else { return nil }
        let layout = m.layout
        let visibleTilingClients = tiledClients(m).count
        let horizontalStack = layout == .tile || layout == .deck
        let horizontalRightStack = layout == .rightTile
        if layout.isScroller { return .down }
        if visibleTilingClients == 1 { return .down }
        if visibleTilingClients == 2 && !config.newIsMaster && horizontalStack { return .right }
        if config.newIsMaster && horizontalStack { return .left }
        if visibleTilingClients == 2 && !config.newIsMaster && horizontalRightStack { return .left }
        if config.newIsMaster && horizontalRightStack { return .right }
        return nil
    }

/// mango set_overview_enter_animation (animation/client.c). Not in mango: no gesture-driven start; the port's live gesture moves the cards.
    func setOverviewEnterAnimation(_ target: CGRect) -> CGRect {
        let w = (target.width * 1.2).rounded(.towardZero), h = (target.height * 1.2).rounded(.towardZero)
        return CGRect(x: target.minX + ((target.width - w) / 2).rounded(.towardZero),
                      y: target.minY + ((target.height - h) / 2).rounded(.towardZero), width: w, height: h)
    }

    func setArrangeHidden(_ m: Monitor, _ c: Client, _ anim: ArrangeAnimation) {
        if c.tagouting { return }
        let animates = !c.isNew && !c.parked && config.animations && !c.noAnimation && grab?.client !== c
        let special = c.tags & TagMask.special != 0
        if !special && c.isInScratchpad && c.isMinimized {
            if animates {
                let g = c.geom ?? c.frame
                c.tagouting = true
                system.hide(c, tagout: TagoutAnimation(to: CGRect(x: g.minX, y: m.screen.frame.minY - g.height, width: g.width, height: g.height),
                                                       durationMs: config.animationDurationTag, curve: config.animationCurveTag))
            } else {
                system.hide(c)
            }
            return
        }
        if special {
            var tagSwitch = false
            if case .tag = anim { tagSwitch = true }
            if tagSwitch && overviewState?.monitor !== m && animates {
                let g = c.geom ?? c.frame
                c.tagouting = true
                system.hide(c, tagout: TagoutAnimation(to: CGRect(x: g.minX, y: m.screen.frame.minY - g.height, width: g.width, height: g.height),
                                                       durationMs: config.animationDurationTag, curve: config.animationCurveTag))
            } else { system.hide(c) }
            return
        }
        let prev = m.prevTag, cur = m.curtag
        if prev != 0, cur != 0, c.tags & (1 << UInt32(prev - 1)) != 0, animates {
            let forward: Bool
            if case .tag(let f) = anim { forward = f } else { forward = m.carouselAnimDir != 0 ? m.carouselAnimDir > 0 : cur > prev }
            c.tagouting = true
            system.hide(c, tagout: setTagoutAnimation(c, on: m, forward: forward))
        } else {
            system.hide(c)
        }
    }


    func setArrangeVisible(_ c: Client, _ target: CGRect) -> CGRect {
        let top = c.mon?.screen.frame.minY ?? target.minY
        return CGRect(x: target.minX, y: top - target.height, width: target.width, height: target.height)
    }

    func setTagoutAnimation(_ c: Client, on m: Monitor, forward: Bool) -> TagoutAnimation {
        let g = c.geom ?? c.frame, sf = m.screen.frame
        var to = CGRect(x: g.minX, y: c.frame.minY, width: g.width, height: g.height)
        if config.tagAnimationDirection == 1 {
            to.origin.x = forward ? min(sf.minX - g.width, g.minX - sf.width) : max(sf.maxX, g.minX + sf.width)
        } else {
            to.origin.x = c.frame.minX
            to.origin.y = forward ? min(sf.minY - g.height, g.minY - sf.height) : max(sf.maxY, g.minY + sf.height)
        }
        return TagoutAnimation(to: to, durationMs: config.animationDurationTag, curve: config.animationCurveTag)
    }

    func setTaginAnimation(_ c: Client, _ target: CGRect, forward: Bool) -> CGRect {
        let sf = c.mon?.screen.frame ?? target
        if config.tagAnimationDirection == 1 {
            return target.offsetBy(dx: forward ? sf.width : -sf.width, dy: 0)
        }
        return target.offsetBy(dx: 0, dy: forward ? sf.height : -sf.height)
    }
}
