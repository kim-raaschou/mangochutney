import CoreGraphics

/// mango ResizeOpts (animation/client.h).
package struct ResizeOpts {
    package var interact = false // Interactive resize (window resized by mouse drag).
    package var skipOvEnterAnim = false // Pre-arrangement stage: skip the overview enter
                                       // zoom.
    package var forceConfigure = false // Must be sent even if the box did not change (client
                                      // ConfigureRequest).
    package var dragEdge: WlrEdges = []
    package init(interact: Bool = false, skipOvEnterAnim: Bool = false, forceConfigure: Bool = false, dragEdge: WlrEdges = []) {
        self.interact = interact
        self.skipOvEnterAnim = skipOvEnterAnim
        self.forceConfigure = forceConfigure
        self.dragEdge = dragEdge
    }
}

/// mango struct ivec2 (common/util.h).
public struct IVec2: Equatable {
    public var x: CGFloat = 0, y: CGFloat = 0, width: CGFloat = 0, height: CGFloat = 0
}

/// mango GEZERO (common/util.h).
@inline(__always) func GEZERO(_ a: CGFloat) -> CGFloat { a > 0 ? a : 0 }

package extension MangoServer {
    func clientOpenAnimationType(_ c: Client) -> AnimationType {
        c.animationTypeOpen ?? config.animationTypeOpen
    }

    func clientAnimationsEnabled(_ c: Client?) -> Bool {
        if let c, c.noAnimation { return false }
        if config.animations { return true }
        return clientGestureDriven(c)
    }

    /// mango client_gesture_driven (input/trackpad.c).
    func clientGestureDriven(_ c: Client?) -> Bool {
        gestureDriveActive && c != nil && c?.mon === gestureDriveMon
    }

    func clientIsIgnoreOutputClip(_ c: Client) -> Bool {
        c === grab?.client || (!ISSCROLLTILED(c) && !c.animation.tagining && !c.animation.tagouting)
    }

    func computeEdgeOffsets(_ c: Client) -> IVec2 {
        var offsets = IVec2()
        if clientIsIgnoreOutputClip(c) { return offsets }
        guard let mon = c.mon else { return offsets }   // not in mango: c->mon is always set here

        let cur = c.animation.current, m = mon.screen.frame
        offsets.width = GEZERO(cur.minX + cur.width - m.minX - m.width) // right
        offsets.height = GEZERO(cur.minY + cur.height - m.minY - m.height) // bottom
        offsets.x = GEZERO(m.minX - cur.minX) // left
        offsets.y = GEZERO(m.minY - cur.minY) // top
        return offsets
    }

    func clientActualSize(_ c: Client) -> (width: CGFloat, height: CGFloat) {
        (c.animation.current.width - 2 * c.bw, c.animation.current.height - 2 * c.bw)
    }

    func isHorizontalStackLayout(_ m: Monitor) -> Bool {
        let tag = getMonCurtag(m)
        return m.pertag.ltidxs[tag] == .tile || m.pertag.ltidxs[tag] == .deck
    }

    func isHorizontalRightStackLayout(_ m: Monitor) -> Bool {
        let tag = getMonCurtag(m)
        return m.pertag.ltidxs[tag] == .rightTile
    }

    // not in mango: nil is UNDIR
    func isSpecialAnimationRule(_ c: Client) -> Direction? {
        guard let m = c.mon else { return nil }
        let visibleTilingClients = m.visibleTilingClients
        if m.layout.isScroller && !c.isfloating {
            return .down
        } else if visibleTilingClients == 1 && !c.isfloating {
            return .down
        } else if visibleTilingClients == 2 && !c.isfloating && !config.newIsMaster && isHorizontalStackLayout(m) {
            return .right
        } else if !c.isfloating && config.newIsMaster && isHorizontalStackLayout(m) {
            return .left
        } else if visibleTilingClients == 2 && !c.isfloating && !config.newIsMaster && isHorizontalRightStackLayout(m) {
            return .left
        } else if !c.isfloating && config.newIsMaster && isHorizontalRightStackLayout(m) {
            return .right
        } else {
            return nil
        }
    }

    func setOverviewEnterAnimation(_ c: Client) {
        if clientGestureDriven(c) {
            var start = c.overviewBackupGeom ?? .zero
            if start.width <= 0 || start.height <= 0 { start = c.animation.current }
            c.animainitGeom = start
            return
        }

        let geo = c.geom
        c.animainitGeom.size.width = (geo.width * 1.2).rounded(.towardZero)
        c.animainitGeom.size.height = (geo.height * 1.2).rounded(.towardZero)
        c.animainitGeom.origin.x = geo.minX + ((geo.width - c.animainitGeom.width) / 2).rounded(.towardZero)
        c.animainitGeom.origin.y = geo.minY + ((geo.height - c.animainitGeom.height) / 2).rounded(.towardZero)
    }

    func setClientOpenAnimation(_ c: Client, _ geo: CGRect) {
        let type = clientOpenAnimationType(c)

        if type == .none || c.animation.duration == 0 {
            c.animainitGeom = geo
            return
        } else if type == .fade {
            c.animainitGeom = geo
            return
        } else if type == .zoom {
            let w = (geo.width * CGFloat(config.zoomInitialRatio)).rounded(.towardZero)
            let h = (geo.height * CGFloat(config.zoomInitialRatio)).rounded(.towardZero)
            c.animainitGeom = CGRect(x: geo.minX + ((geo.width - w) / 2).rounded(.towardZero),
                                     y: geo.minY + ((geo.height - h) / 2).rounded(.towardZero), width: w, height: h)
            return
        } else {
            guard let mon = c.mon else { return }   // not in mango: c->mon is always set here
            let m = mon.screen.frame, w = mon.screen.workArea
            let slideDirection: Direction?
            let specialDirection = isSpecialAnimationRule(c)
            let centerX = c.geom.minX + (c.geom.width / 2).rounded(.towardZero)
            let centerY = c.geom.minY + (c.geom.height / 2).rounded(.towardZero)
            if specialDirection == nil {
                let horizontal: Direction = w.minX + w.width - centerX < centerX - w.minX ? .right : .left
                let horizontalValue = horizontal == .left ? centerX - w.minX : w.minX + w.width - centerX
                let vertical: Direction = w.minY + w.height - centerY < centerY - w.minY ? .down : .up
                let verticalValue = vertical == .up ? centerY - w.minY : w.minY + w.height - centerY
                slideDirection = horizontalValue < verticalValue ? horizontal : vertical
            } else {
                slideDirection = specialDirection
            }
            c.animainitGeom.size.width = c.geom.width
            c.animainitGeom.size.height = c.geom.height
            switch slideDirection {
            case .up:
                c.animainitGeom.origin.x = c.geom.minX
                c.animainitGeom.origin.y = m.minY - c.geom.height
            case .down:
                c.animainitGeom.origin.x = c.geom.minX
                c.animainitGeom.origin.y = c.geom.minY + m.height - (c.geom.minY - m.minY)
            case .left:
                c.animainitGeom.origin.x = m.minX - c.geom.width
                c.animainitGeom.origin.y = c.geom.minY
            case .right:
                c.animainitGeom.origin.x = c.geom.minX + m.width - (c.geom.minX - m.minX)
                c.animainitGeom.origin.y = c.geom.minY
            default:
                c.animainitGeom.origin.x = c.geom.minX
                c.animainitGeom.origin.y = 0 - c.geom.height
            }
        }
    }

    func clipToHide(_ c: Client, _ clipBox: inout CGRect, _ offsets: IVec2) -> IVec2 {
        var offset = IVec2()

        if !ISSCROLLTILED(c) && !c.animation.tagining && !c.animation.tagouted && !c.animation.tagouting {
            return offset
        }

        let bw = c.bw
        let left = offsets.x, right = offsets.width, top = offsets.y, bottom = offsets.height

        if left > 0 {
            offset.x = GEZERO(left - bw)
            clipBox.origin.x += offset.x
            clipBox.size.width -= offset.x
        } else if right > 0 {
            offset.width = GEZERO(right - bw)
            clipBox.size.width -= offset.width
        }

        if top > 0 {
            offset.y = GEZERO(top - bw)
            clipBox.origin.y += offset.y
            clipBox.size.height -= offset.y
        } else if bottom > 0 {
            offset.height = GEZERO(bottom - bw)
            clipBox.size.height -= offset.height
        }

        // not in mango: size.width, as CGRect's width is never negative and wlr_box's is
        if (clipBox.size.width + bw <= 0 || clipBox.size.height + bw <= 0)
            && (ISSCROLLTILED(c) || c.animation.tagouting || c.animation.tagining) {
            c.isClipToHide = true
            clientUpdateVisibility(c)
        } else if c.isClipToHide && (c.mon.map { VISIBLEON(c, $0) } ?? false || clientGestureDriven(c)) {
            c.isClipToHide = false
            clientUpdateVisibility(c)
        }

        return offset
    }

    func clientSetClip(_ c: Client, _ factor: Double) {
        if c.iskilling { return }

        // not in mango: the overview's card tree (ov_card_tree) is the port's pictures

        let offsets = computeEdgeOffsets(c)

        var clipBox: CGRect
        var shouldRenderClientSurface = false

        if !clientAnimationsEnabled(c) {
            c.animation.running = false
            c.animation.tagining = false
            c.animation.tagouting = false
            c.needOutputFlush = false
            c.animainitGeom = c.geom
            c.current = c.geom
            c.pending = c.geom
            c.animation.current = c.geom

            clipBox = clientGetClip(c)
            _ = clipToHide(c, &clipBox, offsets)

            bordersDirty = true   // not in mango: client_draw_border … client_draw_dim; the port draws them all at once

            shouldRenderClientSurface = clipBox.size.width > 0 && clipBox.size.height > 0
            c.isSurfaceHidden = !shouldRenderClientSurface
            clientUpdateVisibility(c)

            if !shouldRenderClientSurface { return }

            system.sceneSubsurfaceTreeSetClip(c, clipBox)   // not in mango: the port's wlr_scene_subsurface_tree_set_clip
            // not in mango: buffer_set_effect (no buffer effects on another app's window)
            return
        }

        let (width, height) = clientActualSize(c)

        clipBox = CGRect(x: 0, y: 0, width: width, height: height)   // not in mango: the xdg geometry's offset is 0

        _ = clipToHide(c, &clipBox, offsets)

        bordersDirty = true   // not in mango: client_draw_border … client_draw_blur; the port draws them all at once

        shouldRenderClientSurface = clipBox.size.width > 0 && clipBox.size.height > 0
        c.isSurfaceHidden = !shouldRenderClientSurface
        clientUpdateVisibility(c)

        if !shouldRenderClientSurface { return }

        system.sceneSubsurfaceTreeSetClip(c, clipBox)   // not in mango: the port's wlr_scene_subsurface_tree_set_clip
        // not in mango: buffer_set_effect (no buffer effects on another app's window)
        _ = factor
    }

    func clientAnimationNextTick(_ c: Client) {
        let passedTime = Int64(getNowInMs()) - Int64(c.animation.timeStarted)
        let animationPassed = c.animation.duration != 0 ? Double(passedTime) / Double(c.animation.duration) : 1.0

        let type: AnimationAction = c.animation.action == .none ? .move : c.animation.action
        let factor = CGFloat(findAnimationCurveAt(animationPassed, type))

        let initial = c.animation.initial
        let width = (initial.width + (c.current.width - initial.width) * factor).rounded(.towardZero)
        let height = (initial.height + (c.current.height - initial.height) * factor).rounded(.towardZero)
        let x = (initial.minX + (c.current.minX - initial.minX) * factor).rounded(.towardZero)
        let y = (initial.minY + (c.current.minY - initial.minY) * factor).rounded(.towardZero)

        system.sceneNodeSetPosition(c, x, y)   // not in mango: the port's wlr_scene_node_set_position
        c.animation.current = CGRect(x: x, y: y, width: width, height: height)

        c.isPendingOpenAnimation = false
        clientSetClip(c, Double(factor))

        if animationPassed >= 1.0 {
            c.animation.action = .move
            c.animation.tagining = false
            c.animation.running = false
            c.animation.overining = false

            if c.animation.tagouting {
                c.animation.tagouting = false
                clientUpdateVisibility(c)
                c.animation.tagouted = true
                c.animation.current = c.geom
                clientSetClip(c, 1.0)
            } else {
                /* Snap to the final box: an interpolated one can be a pixel off,
                 * which leaves X11 content stretched (blurry). */
                clientSetFinishGeometry(c)
            }

            // not in mango: wlr_seat_pointer_notify_enter; macOS gives the pointer to the window under it

            c.needOutputFlush = false
        }
    }

    func clientSetFinishGeometry(_ c: Client) {
        system.sceneNodeSetPosition(c, c.pending.minX, c.pending.minY)   // not in mango: the port's wlr_scene_node_set_position
        c.animation.current = c.geom
        c.animainitGeom = c.geom
        c.animation.initial = c.geom
        c.pending = c.geom
        c.current = c.geom
        clientSetClip(c, 1.0)
        c.needOutputFlush = false
    }

    func clientAnimationSetProgress(_ c: Client, _ progress: Double) {
        var p = progress
        if p < 0.0 { p = 0.0 }
        if p > 1.0 { p = 1.0 }

        let from = c.animation.initial
        let to = c.current

        let width = (from.width + (to.width - from.width) * p).rounded()
        let height = (from.height + (to.height - from.height) * p).rounded()
        let x = (from.minX + (to.minX - from.minX) * p).rounded()
        let y = (from.minY + (to.minY - from.minY) * p).rounded()

        system.sceneNodeSetPosition(c, x, y)   // not in mango: the port's wlr_scene_node_set_position
        c.animation.current = CGRect(x: x, y: y, width: width, height: height)

        c.isPendingOpenAnimation = false
        clientSetClip(c, 1.0)
    }

    func clientAnimationResume(_ c: Client, _ remaining: Double) {
        if !c.animation.running { return }

        if !config.animations || c.animation.duration == 0 || remaining < 0.05 {
            clientAnimationSetProgress(c, 1.0)
            c.animation.action = .move
            c.animation.tagining = false
            c.animation.overining = false
            c.animation.running = false
            if c.animation.tagouting {
                c.animation.tagouting = false
                clientUpdateVisibility(c)
                c.animation.tagouted = true
                c.animation.current = c.geom
            }
            c.needOutputFlush = false
            return
        }

        c.animation.initial = c.animation.current
        c.animation.timeStarted = getNowInMs()
        c.animation.running = true
        c.needOutputFlush = true
        requestFreshAllMonitors()
    }

    func clientCommit(_ c: Client) {
        c.current = c.pending

        if c.animation.shouldAnimate {
            if !c.animation.running { c.animation.current = c.animainitGeom }

            c.animation.initial = c.animainitGeom
            c.animation.timeStarted = getNowInMs()
            c.animation.running = true
            c.animation.shouldAnimate = false
        } else {
            if !c.animation.running {
                c.animation.current = c.geom
            }
        }

        // When animation is disabled, set the surface position and size early
        // so pointer_process_motion focus does not hit the surface from the
        // previous frame.
        if !clientAnimationsEnabled(c) { clientSetFinishGeometry(c) }

        requestFreshAllMonitors()
    }

    func clientSetPendingState(_ c: Client) {
        if c.iskilling { return }

        if !clientAnimationsEnabled(c) {
            c.animation.shouldAnimate = false
        } else if c.animation.tagining {
            c.animation.shouldAnimate = true
        } else if c.animation.action == .overview && c.animation.overviewEnterAnimSet {
            /* Overview enter animation: force start after setting the zoom; not
             * forced during pre-arrangement to avoid jitter. */
            c.animation.shouldAnimate = true
        } else if c === grab?.client || (!c.isPendingOpenAnimation && c.current == c.pending) {
            c.animation.shouldAnimate = false
        } else {
            c.animation.shouldAnimate = true
        }

        if clientOpenAnimationType(c) == .none && c.animation.action == .open {
            c.animation.duration = 0
        }

        if startDragWindow {
            c.animation.shouldAnimate = false
            c.animation.duration = 0
        }

        if c.noAnimation {
            c.animation.shouldAnimate = false
            c.animation.duration = 0
        }

        clientCommit(c)
        c.dirty = true
    }

    func resize(_ c: Client, _ geo: CGRect, _ opts: ResizeOpts) {
        guard let mon = c.mon else { return }

        c.needOutputFlush = true
        c.dirty = true

        let bbox = opts.interact || c.isfloating || c.isfullscreen ? sceneGeometry : mon.screen.workArea

        if mon.layout.isScroller && (!c.isfloating || c === grab?.client) {
            c.geom = geo
            c.geom.size.width = max(1 + 2 * c.bw, c.geom.width)
            c.geom.size.height = max(1 + 2 * c.bw, c.geom.height)
        } else {
            c.geom = geo
            clientSetBounds(c, bbox)
        }

        if !c.noSizeHint && !c.ismaximizescreen && !c.isfullscreen && c.isfloating {
            let anchorRight = c.geom.minX + c.geom.width
            let anchorBottom = c.geom.minY + c.geom.height
            clientSetSizeBound(c)
            if opts.dragEdge.contains(.left) { c.geom.origin.x = anchorRight - c.geom.width }
            if opts.dragEdge.contains(.top) { c.geom.origin.y = anchorBottom - c.geom.height }
        }

        if !c.isPendingOpenAnimation { c.animation.beginFadeIn = false }

        if c.animation.overining {
            c.animation.action = .overview
            c.animation.duration = UInt32(config.animationDurationTag)
        } else if c.animation.action == .open && !c.animation.tagining
                    && !c.animation.tagouting && c.geom == c.current {
            /* keep current action */
        } else if c.animation.tagouting {
            c.animation.duration = UInt32(config.animationDurationTag)
            c.animation.action = .tag
        } else if c.animation.tagining {
            c.animation.duration = UInt32(config.animationDurationTag)
            c.animation.action = .tag
        } else if c.isPendingOpenAnimation {
            c.animation.duration = UInt32(config.animationDurationOpen)
            c.animation.action = .open
        } else {
            c.animation.duration = UInt32(config.animationDurationMove)
            c.animation.action = .move
        }

        if c.animation.tagouting {
            c.animainitGeom = c.animation.current
        } else if c.animation.tagining {
            c.animainitGeom.size.height = c.animation.current.height
            c.animainitGeom.size.width = c.animation.current.width
        } else if c.isPendingOpenAnimation {
            setClientOpenAnimation(c, c.geom)
        } else {
            c.animainitGeom = c.animation.current
        }

        if c.noBorder || c.iskilling {
            c.bw = 0
        } else if !c.isfullscreen {
            c.bw = CGFloat(config.borderpx)
        }

        let hitNoBorder = checkHitNoBorder(c)
        if hitNoBorder {
            c.bw = 0
            c.fakeNoBorder = true
        } else {
            c.fakeNoBorder = false
        }

        if !mon.isoverview {
            c.configureSerial = system.clientSetSize(c, c.geom.width - 2 * c.bw, c.geom.height - 2 * c.bw,
                                                     opts.forceConfigure)   // not in mango: the port's client_set_size
        }

        // not in mango: no resizing_count_pending; the port's configure serial is always 0

        if c === grab?.client {
            let offsets = computeEdgeOffsets(c)

            c.animation.running = false
            c.animation.tagining = false
            c.animation.tagouting = false
            c.needOutputFlush = false
            c.animainitGeom = c.geom
            c.current = c.geom
            c.pending = c.geom
            c.animation.current = c.geom
            system.sceneNodeSetPosition(c, c.geom.minX, c.geom.minY)   // not in mango: the port's wlr_scene_node_set_position

            bordersDirty = true   // not in mango: client_draw_border … client_draw_shadow; the port draws them all at once
            var clip = clientGetClip(c)

            _ = clipToHide(c, &clip, offsets)

            system.sceneSubsurfaceTreeSetClip(c, clip)   // not in mango: the port's wlr_scene_subsurface_tree_set_clip
            return
        }

        if !c.animation.tagouting && !c.iskilling { c.pending = c.geom }

        // not in mango: no swallowing (c->swallowing, c->swallowdby)

        if (c.isglobal || c.isunglobal) && c.isfloating && c.animation.action == .tag {
            c.animainitGeom = c.geom
        }

        if c.scratchpadSwitchingMon && c.isfloating { c.animainitGeom = c.geom }

        if !opts.skipOvEnterAnim && mon.isoverview && c.animation.overining && !c.animation.overviewEnterAnimSet {
            if clientGestureDriven(c) {
                setOverviewEnterAnimation(c)
                c.animation.overining = false
                c.animation.overviewEnterAnimSet = true
            } else {
                c.animation.overining = false
                if c.id != mon.sel && c.animation.action == .overview {
                    c.animation.overviewEnterAnimSet = true
                    setOverviewEnterAnimation(c)
                }
            }
        }

        clientSetPendingState(c)
        bordersDirty = true   // not in mango: client_update_border_color; the port draws the borders at once
    }

    func clientDrawFrame(_ c: Client) -> Bool {
        let needNextTick = false

        // not in mango: no force_render (a disabled scene node is not drawn on macOS)

        if gestureDriveActive && c.mon === gestureDriveMon && c.animation.running && c.needOutputFlush {
            return clientSetFocusOpacity(c)
        }

        if !c.needOutputFlush { return clientSetFocusOpacity(c) || needNextTick }

        var next = needNextTick
        if config.animations && c.animation.running {
            next = true
            clientAnimationNextTick(c)
        } else {
            clientSetFinishGeometry(c)
        }

        let needFadeFocus = clientSetFocusOpacity(c)

        return next || needFadeFocus
    }

    // not in mango: opacity and blur of another app's window are out of reach (MangoCompat); no fade to step
    func clientSetFocusOpacity(_ c: Client) -> Bool { false }
}
