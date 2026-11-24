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

    func clientNoRadiusActive(_ c: Client) -> Bool {
        guard let m = c.mon else { return false }

        if c.isfullscreen || (config.noRadiusWhenSingle && m.visibleTilingClients == 1) {
            return true
        }

        return config.monocleNoRadius && ISFAKETILED(c) && !m.isoverview && isMonocleLayout(m)
    }

    func clientAnimationsEnabled(_ c: Client?) -> Bool {
        if let c, c.noAnimation { return false }
        if config.animations { return true }
        return clientGestureDriven(c)
    }

    func clientIsIgnoreOutputClip(_ c: Client) -> Bool {
        c === grabClient || (!ISSCROLLTILED(c) && !c.animation.tagining && !c.animation.tagouting)
    }

    func computeEdgeOffsets(_ c: Client) -> IVec2 {
        var offsets = IVec2()
        if clientIsIgnoreOutputClip(c) { return offsets }
        guard let mon = c.mon else { return offsets }   // not in mango: c->mon is always set here

        let cur = c.animation.current, m = mon.m
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

    func isSpecialAnimationRule(_ c: Client) -> Int32 {
        guard let m = c.mon else { return UNDIR }   // not in mango: c->mon is always set here
        let visibleTilingClients = m.visibleTilingClients
        if isScrollerLayout(m) && !c.isfloating {
            return DOWN
        } else if visibleTilingClients == 1 && !c.isfloating {
            return DOWN
        } else if visibleTilingClients == 2 && !c.isfloating && !config.newIsMaster && isHorizontalStackLayout(m) {
            return RIGHT
        } else if !c.isfloating && config.newIsMaster && isHorizontalStackLayout(m) {
            return LEFT
        } else if visibleTilingClients == 2 && !c.isfloating && !config.newIsMaster && isHorizontalRightStackLayout(m) {
            return LEFT
        } else if !c.isfloating && config.newIsMaster && isHorizontalRightStackLayout(m) {
            return RIGHT
        } else {
            return UNDIR
        }
    }

    func setOverviewEnterAnimation(_ c: Client) {
        if clientGestureDriven(c) {
            var start = c.overviewBackupGeom
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
            let w = CGFloat((Float(geo.width) * config.zoomInitialRatio).rounded(.towardZero))
            let h = CGFloat((Float(geo.height) * config.zoomInitialRatio).rounded(.towardZero))
            c.animainitGeom = CGRect(x: geo.minX + ((geo.width - w) / 2).rounded(.towardZero),
                                     y: geo.minY + ((geo.height - h) / 2).rounded(.towardZero), width: w, height: h)
            return
        } else {
            guard let mon = c.mon else { return }   // not in mango: c->mon is always set here
            let m = mon.m, w = mon.w
            let slideDirection: Int32
            let specialDirection = isSpecialAnimationRule(c)
            let centerX = c.geom.minX + (c.geom.width / 2).rounded(.towardZero)
            let centerY = c.geom.minY + (c.geom.height / 2).rounded(.towardZero)
            if specialDirection == UNDIR {
                let horizontal = w.minX + w.width - centerX < centerX - w.minX ? RIGHT : LEFT
                let horizontalValue = horizontal == LEFT ? centerX - w.minX : w.minX + w.width - centerX
                let vertical = w.minY + w.height - centerY < centerY - w.minY ? DOWN : UP
                let verticalValue = vertical == UP ? centerY - w.minY : w.minY + w.height - centerY
                slideDirection = horizontalValue < verticalValue ? horizontal : vertical
            } else {
                slideDirection = specialDirection
            }
            c.animainitGeom.size.width = c.geom.width
            c.animainitGeom.size.height = c.geom.height
            switch slideDirection {
            case UP:
                c.animainitGeom.origin.x = c.geom.minX
                c.animainitGeom.origin.y = m.minY - c.geom.height
            case DOWN:
                c.animainitGeom.origin.x = c.geom.minX
                c.animainitGeom.origin.y = c.geom.minY + m.height - (c.geom.minY - m.minY)
            case LEFT:
                c.animainitGeom.origin.x = m.minX - c.geom.width
                c.animainitGeom.origin.y = c.geom.minY
            case RIGHT:
                c.animainitGeom.origin.x = c.geom.minX + m.width - (c.geom.minX - m.minX)
                c.animainitGeom.origin.y = c.geom.minY
            default:
                c.animainitGeom.origin.x = c.geom.minX
                c.animainitGeom.origin.y = 0 - c.geom.height
            }
        }
    }

    var barsInsideBorder: Bool {
        // Port extension: not in mango. The bars inside the border (chutney_macos_appearance).
        portHooks.barsInsideBorder?(self) ?? false
    }

    // not in mango: client_set_clip's client_draw_group_bar and client_draw_tabbar for every client at once
    func drawBars() {
        guard drawsOverlays else { return }
        var strips: [TabStrip] = []
        var groups: [TabStrip] = []
        for m in monitors {
            for c in visibleClients(m) where clientCheckTabNodeVisible(c, on: m) {
                if let s = clientDrawGroupBar(c, computeEdgeOffsets(c)) {
                    groups.append(s)
                }
            }
            for f in clients where f.mon === m && f.isTabFocus && tabIsMember(f) {
                if let s = clientDrawTabbar(f, computeEdgeOffsets(f)) {
                    strips.append(s)
                }
            }
        }
        var style = TabStripStyle(accent: config.focuscolor, accentWidth: CGFloat(min(3, max(1, config.borderpx))))
        style.decorate = decorateDrawData(config.tabbardata, mango: .mangoTabBar)
        system.drawTabBars(strips, style: style)
        style.decorate = decorateDrawData(config.groupbardata, mango: .mangoGroupBar)
        system.drawGroupBars(groups, style: style)
    }

    // not in mango: the edge clipping both bars share, as client_draw_tabbar and client_draw_group_bar write it
    func clipBar(_ anchor: CGRect, y: CGFloat, height: CGFloat, _ offsets: IVec2, on m: Monitor) -> CGRect {
        var tabX = anchor.minX, tabY = y, tw = anchor.width, th = height
        if offsets.y > 0 {
            tabY = m.m.minY
            th = height - offsets.y
        }
        if offsets.height > 0 { th = th - max(0, offsets.height - anchor.height) }
        if offsets.width > 0 { tw = tw - offsets.width }
        if offsets.x > 0 {
            tabX = m.m.minX
            tw = tw - offsets.x
        }
        return CGRect(x: tabX, y: tabY, width: tw, height: th)
    }

    func clientDrawGroupBar(_ c: Client, _ offsets: IVec2) -> TabStrip? {
        guard let m = c.mon, config.groupBarHeight > 0, clientWantsGroupBar(c) else { return nil }   // not in mango: c->group_bar, which exists only when group_bar_height > 0
        /* Owner hidden by tab: hide the whole strip, otherwise its nodes (they are
         * not children of the window) would float over the visible window. */
        if c.isTabHidden { return nil }
        let members = groupMembers(c)
        var current = c.animation.current
        // Port extension: not in mango. The bars inside the border (chutney_macos_appearance).
        let ported = barsInsideBorder
        if ported { current = current.insetBy(dx: borderWidth(c, on: m), dy: borderWidth(c, on: m)) }
        let h = CGFloat(config.groupBarHeight)
        let bar = clipBar(current, y: current.minY - h, height: h, offsets, on: m)
        if bar.width <= 0 || bar.height <= 0 { return nil }
        let radius = system.windowCornerRadius   // not in mango: the port's side
        let under = ported ? min(radius, current.height) : 0
        let sel = selectedMonitor.sel
        return TabStrip(
            frame: CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: bar.height + under),
            barHeight: bar.height, cornerRadius: radius,
            segments: zip(members, barSegments(bar, members)).map { cur, box in
                .init(id: cur.windowID, title: cur.title.isEmpty ? cur.appName : cur.title, focused: cur === sel,
                      pid: cur.pid, frame: box)
            },
            above: c.windowID,
            closeButton: config.groupBarCloseButtonEnable
                ? .init(size: CGFloat(config.groupBarButtonSize), margin: CGFloat(config.groupBarButtonMargin),
                        color: config.groupBarButtonColor)
                : nil,
            plain: !ported)
    }

    // not in mango: global_draw_tab_bar and global_draw_group_bar for every member, side by side
    func barSegments(_ bar: CGRect, _ members: [Client]) -> [CGRect] {
        let count = members.count
        let tw = Int(bar.width.rounded(.towardZero))
        let barW = tw / count, rem = tw % count
        var x = bar.minX
        return (0..<count).map { i in
            let w = CGFloat(barW + (i < rem ? 1 : 0))
            defer { x += w }
            return CGRect(x: x, y: bar.minY, width: w, height: bar.height)
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

    func clientSetDropArea(_ c: Client?) {
        var firstDraw = false
        var dropDirection = UNDIR

        guard let c, let mon = c.mon else { return }

        if !c.enableDropAreaDraw && !c.dropareaEnabled { return }

        if !c.enableDropAreaDraw && c.dropareaEnabled {
            c.dropareaEnabled = false
            system.showDropArea(nil, color: config.dropcolor)   // not in mango: the port's droparea node
            return
        } else if c.enableDropAreaDraw && !c.dropareaEnabled {
            c.dropareaEnabled = true
            firstDraw = true
        }

        let bw = Int32(c.bw)
        let clientWidth = Int32(c.geom.width) - 2 * bw
        let clientHeight = Int32(c.geom.height) - 2 * bw

        // not in mango: the port's droparea node, set where mango sets its position and size
        func dropArea(_ x: Int32, _ y: Int32, _ width: Int32, _ height: Int32) {
            system.showDropArea(CGRect(x: c.geom.minX + CGFloat(x), y: c.geom.minY + CGFloat(y),
                                       width: CGFloat(width), height: CGFloat(height)), color: config.dropcolor)
        }

        if clientWidth <= 0 || clientHeight <= 0 {
            c.dropareaEnabled = false
            system.showDropArea(nil, color: config.dropcolor)   // not in mango: the port's droparea node
            return
        }

        if dropToGroup && dropClient === c {
            if !firstDraw && c.dropDirection == UNDIR { return }
            c.dropDirection = UNDIR
            dropArea(bw, bw, clientWidth, clientHeight)
            return
        }

        let cursor = system.pointer   // not in mango: the port's cursor
        let relX = Double(cursor.x - c.geom.minX) - Double(bw)
        let relY = Double(cursor.y - c.geom.minY) - Double(bw)

        var dropBox = (x: Int32(0), y: Int32(0), width: Int32(0), height: Int32(0))
        let curLayout = mon.pertag.ltidxs[getClientTagIdx(c)]
        let dwindleFamiliar = curLayout == .dwindle && config.dwindleDropSimpleSplit

        if dwindleFamiliar {
            let splitH = c.geom.width >= c.geom.height
            let ratio = config.dwindleSplitRatio
            if splitH {
                if relX < Double(clientWidth) * 0.5 {
                    dropDirection = LEFT
                    dropBox = (bw, bw, Int32(Float(clientWidth) * ratio), clientHeight)
                } else {
                    dropDirection = RIGHT
                    dropBox = (bw + Int32(Float(clientWidth) * ratio), bw,
                               clientWidth - Int32(Float(clientWidth) * ratio), clientHeight)
                }
            } else {
                if relY < Double(clientHeight) * 0.5 {
                    dropDirection = UP
                    dropBox = (bw, bw, clientWidth, Int32(Float(clientHeight) * ratio))
                } else {
                    dropDirection = DOWN
                    dropBox = (bw, bw + Int32(Float(clientHeight) * ratio),
                               clientWidth, clientHeight - Int32(Float(clientHeight) * ratio))
                }
            }
        } else if curLayout == .tile || curLayout == .deck ||
                    curLayout == .centerTile || curLayout == .rightTile {
            if c.ismaster {
                if mon.visibleTilingClients == 1 {
                    if relX < Double(clientWidth) * 0.5 {
                        dropDirection = LEFT
                        dropBox = (bw, bw, clientWidth / 2, clientHeight)
                    } else {
                        dropDirection = RIGHT
                        dropBox = (bw + clientWidth / 2, bw, clientWidth / 2, clientHeight)
                    }
                } else {
                    dropBox = (bw, bw, clientWidth, clientHeight)
                    dropDirection = UNDIR
                }
            } else {
                if relY < Double(clientHeight) * 0.5 {
                    dropDirection = UP
                    dropBox = (bw, bw, clientWidth, clientHeight / 2)
                } else {
                    dropDirection = DOWN
                    dropBox = (bw, bw + clientHeight / 2, clientWidth, clientHeight / 2)
                }
            }
        } else if curLayout == .verticalTile || curLayout == .verticalDeck {
            if c.ismaster {
                if mon.visibleTilingClients == 1 {
                    if relY < Double(clientHeight) * 0.5 {
                        dropDirection = UP
                        dropBox = (bw, bw, clientWidth, clientHeight / 2)
                    } else {
                        dropDirection = DOWN
                        dropBox = (bw, bw + clientHeight / 2, clientWidth, clientHeight / 2)
                    }
                } else {
                    dropBox = (bw, bw, clientWidth, clientHeight)
                    dropDirection = UNDIR
                }
            } else {
                if relX < Double(clientWidth) * 0.5 {
                    dropDirection = LEFT
                    dropBox = (bw, bw, clientWidth / 2, clientHeight)
                } else {
                    dropDirection = RIGHT
                    dropBox = (bw + clientWidth / 2, bw, clientWidth / 2, clientHeight)
                }
            }
        } else {
            let distLeft = relX
            let distRight = Double(clientWidth) - relX
            let distTop = relY
            let distBottom = Double(clientHeight) - relY

            if distLeft <= distRight && distLeft <= distTop &&
                distLeft <= distBottom {
                dropDirection = LEFT
                dropBox = (bw, bw, clientWidth / 2, clientHeight)
            } else if distRight <= distTop && distRight <= distBottom {
                dropDirection = RIGHT
                dropBox = (bw + clientWidth / 2, bw, clientWidth / 2, clientHeight)
            } else if distTop <= distBottom {
                dropDirection = UP
                dropBox = (bw, bw, clientWidth, clientHeight / 2)
            } else {
                dropDirection = DOWN
                dropBox = (bw, bw + clientHeight / 2, clientWidth, clientHeight / 2)
            }
        }

        if !firstDraw && c.dropDirection == dropDirection { return }
        c.dropDirection = dropDirection

        dropArea(dropBox.x, dropBox.y, dropBox.width, dropBox.height)
    }

    func clientSetClip(_ c: Client, _ factor: Float) {
        if c.iskilling { return }

        // not in mango: the overview's card tree (ov_card_tree) and overview_scene_surface are the port's pictures

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
        clientSetClip(c, Float(factor))

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
        } else if c === grabClient || (!c.isPendingOpenAnimation && c.current == c.pending) {
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

        let bbox = opts.interact || c.isfloating || c.isfullscreen ? sceneGeometry : mon.w

        if isScrollerLayout(mon) && (!c.isfloating || c === grabClient) {
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

        if c === grabClient {
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
                if c !== mon.sel && c.animation.action == .overview {
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
