import CoreGraphics

package extension MangoServer {








    var barsInsideBorder: Bool {
        // Port extension: not in mango. The bars inside the border (chutney_macos_appearance).
        portHooks.barsInsideBorder?(self) ?? false
    }

    func mangoBarDecorationApplyConfig(_ set: DecorateStyle, mango: DecorateStyle) -> DecorateStyle {
        set.filled(from: mango)
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
            for f in clients where f.mon === m && f.isTabFocus && tabIsMember(f) && !f.parked {   // not in mango: parked is the port's
                if let s = clientDrawTabbar(f, computeEdgeOffsets(f)) {
                    strips.append(s)
                }
            }
        }
        var style = TabStripStyle(accent: config.focuscolor, accentWidth: CGFloat(min(3, max(1, config.borderpx))))
        style.decorate = mangoBarDecorationApplyConfig(config.tabbardata, mango: .mangoTabBar)
        system.drawTabBars(strips, style: style)
        style.decorate = mangoBarDecorationApplyConfig(config.groupbardata, mango: .mangoGroupBar)
        system.drawGroupBars(groups, style: style)
    }

    // not in mango: c->animation.current; a window standing still is drawn where it stands (an app may refuse its size)
    func animationCurrent(_ c: Client) -> CGRect {
        c.animation.running ? c.animation.current : c.frame.insetBy(dx: -c.bw, dy: -c.bw)
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


    func clientDrawGroupBar(_ c: Client, _ offsets: IVec2) -> TabStrip? {
        guard let m = c.mon, config.groupBarHeight > 0, clientWantsGroupBar(c) else { return nil }   // not in mango: c->group_bar, which exists only when group_bar_height > 0
        /* Owner hidden by tab: hide the whole strip, otherwise its nodes (they are
         * not children of the window) would float over the visible window. */
        if c.isTabHidden { return nil }
        let members = groupMembers(c)
        var current = animationCurrent(c)
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
                .init(id: cur.id, title: cur.title.isEmpty ? cur.appName : cur.title, focused: cur.id == sel,
                      pid: cur.pid, frame: box)
            },
            above: c.id,
            closeButton: config.groupBarCloseButtonEnable
                ? .init(size: CGFloat(config.groupBarButtonSize), margin: CGFloat(config.groupBarButtonMargin),
                        color: config.groupBarButtonColor)
                : nil,
            plain: !ported)
    }


}
