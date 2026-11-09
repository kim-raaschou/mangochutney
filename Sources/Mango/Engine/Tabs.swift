import CoreGraphics

package extension MangoServer {
    func tabLayoutIdSupported(_ id: LayoutKind) -> Bool {
        if id == .monocle { return config.monocleTabMode }
        if id == .deck || id == .verticalDeck { return config.deckTabMode }
        return false
    }

    func tabLayoutEnabled(_ m: Monitor) -> Bool { tabLayoutIdSupported(m.layout) }

    func tabLayoutActive(_ m: Monitor) -> Bool { overviewState?.monitor !== m && tabLayoutEnabled(m) }

    func tabStateOk(_ c: Client) -> Bool {
        guard c.mon != nil, !c.isMinimized else { return false }
        return !c.isFloating && !c.isUnglobal && !c.isInScratchpad
    }

    func tabIsStackCandidate(_ m: Monitor, _ target: Client) -> Bool {
        if m.layout == .monocle { return true }
        if m.layout != .deck && m.layout != .verticalDeck { return false }
        return !target.isMaster
    }

    // not in mango: the tab chain of the tags in view, as tab_member_kept keeps it (mango links it per window)
    func tabMembers(_ m: Monitor) -> [Client] {
        guard config.tabBarHeight > 0, tabLayoutActive(m) else { return [] }
        let members = visibleClients(m).filter { tabStateOk($0) && tabIsStackCandidate(m, $0) }
        return members.count >= 2 ? members : []
    }

    func tabChainFocus(_ members: [Client], on m: Monitor) -> Client? {
        let sel = members.first { $0.id == m.sel }
        let focus = sel ?? members.first(where: { $0.isTabFocus }) ?? members.first
        for c in members { c.isTabFocus = c === focus }
        return focus
    }

    // not in mango: client_tile_resize's tab strip, over the frames of a layout that is pure here
    func reserveTabStrip(_ frames: inout [ClientID: CGRect], on m: Monitor) {
        let members = tabMembers(m)
        guard !members.isEmpty else { return }
        let h = CGFloat(config.tabBarHeight)
        for c in members {
            guard var f = frames[c.id], f.height > h else { continue }
            f.origin.y += h
            f.size.height -= h
            frames[c.id] = f
        }
    }

    var barsInsideBorder: Bool {
        // Port extension: not in mango. The bars inside the border (chutney_macos_appearance).
        portHooks.barsInsideBorder?(self) ?? false
    }

    func mangoBarDecorationApplyConfig(_ set: DecorateStyle, mango: DecorateStyle) -> DecorateStyle {
        set.setValueDefault(from: mango)
    }

    func topBars(_ c: Client, tabMember: Bool) -> CGFloat {
        (clientWantsGroupBar(c) ? CGFloat(config.groupBarHeight) : 0) + (tabMember ? CGFloat(config.tabBarHeight) : 0)
    }

    func clientCheckTabNodeVisible(_ c: Client, on m: Monitor) -> Bool {
        clientWantsGroupBar(c) && overviewState?.monitor !== m && !c.isFullscreen && !c.parked && c.isVisible(on: m)
    }

    func tabRefreshBars(animating: [ClientID: CGRect] = [:]) {
        guard drawsOverlays else { return }
        var strips: [TabStrip] = []
        for m in monitors {
            guard let f = tabChainFocus(tabMembers(m), on: m), !f.parked, !f.isFullscreen, !f.isMaximizeScreen else { continue }
            let members = tabMembers(m)
            let h = CGFloat(config.tabBarHeight)
            let radius = system.windowCornerRadius
            let ported = barsInsideBorder
            let shown = ported ? shownFrame(f, animating: animating)
                               : shownFrame(f, animating: animating).insetBy(dx: -borderWidth(f, on: m), dy: -borderWidth(f, on: m))
            let group = clientCheckTabNodeVisible(f, on: m) ? CGFloat(config.groupBarHeight) : 0
            let under = group > 0 || !ported ? 0 : min(radius, shown.height)
            strips.append(TabStrip(
                frame: CGRect(x: shown.minX, y: shown.minY - group - h, width: shown.width, height: h + under),
                barHeight: h, cornerRadius: radius,
                segments: members.map { c in
                    .init(id: c.id, title: c.title.isEmpty ? c.appName : c.title, focused: c === f, pid: c.pid)
                },
                above: f.id, plain: !ported))
        }
        var style = TabStripStyle(accent: config.focuscolor, accentWidth: CGFloat(min(3, max(1, config.borderpx))))
        style.decorate = mangoBarDecorationApplyConfig(config.tabbardata, mango: .mangoTabBar)
        system.drawTabBars(strips, style: style)
        style.decorate = mangoBarDecorationApplyConfig(config.groupbardata, mango: .mangoGroupBar)
        system.drawGroupBars(clientDrawGroupBar(animating: animating), style: style)
    }

    func clientDrawGroupBar(animating: [ClientID: CGRect]) -> [TabStrip] {
        var out: [TabStrip] = []
        for m in monitors {
            for c in visibleClients(m) where clientCheckTabNodeVisible(c, on: m) {
                let ported = barsInsideBorder
                let bw = ported ? 0 : borderWidth(c, on: m)
                let shown = shownFrame(c, animating: animating).insetBy(dx: -bw, dy: -bw)
                let h = CGFloat(config.groupBarHeight)
                let radius = system.windowCornerRadius
                let under = ported ? min(radius, shown.height) : 0
                out.append(TabStrip(
                    frame: CGRect(x: shown.minX, y: shown.minY - h, width: shown.width, height: h + under),
                    barHeight: h, cornerRadius: radius,
                    segments: groupMembers(c).map { g in
                        .init(id: g.id, title: g.title.isEmpty ? g.appName : g.title, focused: g === c, pid: g.pid)
                    },
                    above: c.id,
                    closeButton: config.groupBarCloseButtonEnable
                        ? .init(size: CGFloat(config.groupBarButtonSize), margin: CGFloat(config.groupBarButtonMargin),
                                color: config.groupBarButtonColor)
                        : nil,
                    plain: !ported))
            }
        }
        return out
    }

    func clientHandleDecorateClick(_ c: Client, isTab: Bool) {
        if isTab {
            tabFocusMember(c.id)
        } else if !c.isGroupMember {
            clientFocus(c)
        } else {
            clientFocusGroupMember(c)
        }
    }

    func tabFocusMember(_ id: CGWindowID) {
        guard let c = clientByIdAll(id), let m = c.mon else { return }
        clientFocus(c)
        arrange(m, .none)
    }
}
