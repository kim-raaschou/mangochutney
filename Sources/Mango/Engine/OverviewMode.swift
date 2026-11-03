import CoreGraphics

@MainActor
package struct OverviewState {
    package let monitor: Monitor
    package let previousSel: ClientID?
    var cards: [ClientID: CGRect]
    package var jump: [String: ClientID]?
    var labelsShown = false
    var circle = false
    package var members: [ClientID] = []
    package var circleFocus: ClientID?
    package var thumbnails = false
}

package extension MangoServer {
    func toggleOverview(onlyCurrent: Bool, jump: Bool, circle: Bool = false) {
        if overviewState != nil { leaveOverview(select: nil); return }
        let m = selectedMonitor!
        let tagmask = TagMask.mask(forTagNum: config.tagNum)
        let members: [Client] = clients.filter { c in
            c.mon === m && !c.isMinimized && !c.isUnglobal && c.tags & TagMask.special == 0
                && (!onlyCurrent || c.isVisible(on: m))
        }
        guard !members.isEmpty else { return }
        for c in members {
            c.overviewBackupGeom = c.isFloating ? c.floatGeom : (c.geom ?? c.frame)
            c.overining = true
        }
        let sizes = members.map { c -> (id: ClientID, size: CGSize) in
            let f = c.overviewBackupGeom!
            return (c.id, f.width <= 0 || f.height <= 0 ? CGSize(width: 100, height: 100) : f.size)
        }
        let focusID = m.sel.flatMap { id in members.contains { $0.id == id } ? id : nil } ?? members[0].id
        let cards = circle
            ? OverviewLayout.overviewScaleTab(clients: sizes, focused: focusID, workArea: m.screen.workArea,
                                            gapInner: CGFloat(config.overviewgappi), gapOuter: CGFloat(config.overviewgappo),
                                            centerRatio: CGFloat(config.overcircleCenterRatio),
                                            titleBlockHeight: config.titleMessageBarHeight > 0
                                                ? CGFloat(config.titleMessageBarHeight + config.titleMessageBarGap) : 0)
            : OverviewLayout.overviewScale(clients: sizes, workArea: m.screen.workArea,
                                  gapInner: CGFloat(config.overviewgappi),
                                  gapOuter: CGFloat(config.overviewgappo))
        m.ovbkCurrentTagset = m.tagset[m.seltags]
        m.ovbkPrevTagset = m.tagset[m.seltags ^ 1]
        var state = OverviewState(monitor: m, previousSel: m.sel, cards: cards)
        state.circle = circle
        state.members = members.map(\.id)
        state.circleFocus = circle ? focusID : nil
        if jump {
            var map: [String: ClientID] = [:]
            let letters = config.jumpLabels.map { String($0).uppercased() }
            for (i, c) in members.enumerated() where i < letters.count { map[letters[i]] = c.id }
            state.jump = map
        }
        if system.canCapture {
            state.thumbnails = true
            let look = OverviewLook(focusColor: config.focuscolor, borderColor: config.bordercolor,
                                    jumpLook: mangoBarDecorationApplyConfig(config.jumplabeldata, mango: .mangoJumpLabel),
                                    // Port extension: not in mango. The port's look (chutney_style).
                                    mango: barsInsideBorder ? nil
                                        : (config.rootcolor, CGFloat(config.borderpx), CGFloat(config.borderRadius)))
            overviewState = state
            clientViewOnMonitor(onlyCurrent ? m.tagset[m.seltags] & tagmask : tagmask, on: m, changeFocus: true)
            system.showOverview(overlayCards(state, focused: state.circleFocus ?? m.sel), on: m, look: look)
            overviewCardSurfaceAdd(state)
            titleMessageBarRefresh(m)
            printstatus()
            return
        }
        system.askToCapture()
        overviewState = state
        clientViewOnMonitor(onlyCurrent ? m.tagset[m.seltags] & tagmask : tagmask, on: m, changeFocus: true)
        arrange(m)
        titleMessageBarRefresh(m)
        if jump, let map = state.jump {
            system.whenAnimationsIdle { [weak self] in
                guard let self, var ov = self.overviewState, ov.monitor === m, ov.jump != nil, !ov.labelsShown else { return }
                let look = self.mangoBarDecorationApplyConfig(self.config.jumplabeldata, mango: .mangoJumpLabel)
                self.system.showJumpLabels(map.compactMap { label, id in ov.cards[id].map { (label, $0) } }, look: look)
                ov.labelsShown = true
                self.overviewState = ov
            }
        }
        printstatus()
    }


    func fixMonTagsetFromOverview(_ m: Monitor) {
        let tagmask = TagMask.mask(forTagNum: config.tagNum)
        if m.tagset[m.seltags] == m.ovbkPrevTagset & tagmask {
            m.tagset[m.seltags ^ 1] = m.ovbkCurrentTagset
            m.prevTag = TagMask.getTagsFirstTagNum(m.ovbkCurrentTagset) ?? m.prevTag
        } else {
            m.tagset[m.seltags ^ 1] = m.ovbkPrevTagset
            m.prevTag = TagMask.getTagsFirstTagNum(m.ovbkPrevTagset) ?? m.prevTag
        }
    }

    /// Not in mango: card list for the port's overview overlay.
    func overlayCards(_ ov: OverviewState, focused: ClientID?) -> [OverviewCard] {
        let labelOf = Dictionary((ov.jump ?? [:]).map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
        return ov.cards.compactMap { id, frame in
            guard let c = clientByIdAll(id) else { return nil }
            return OverviewCard(id: id, frame: frame, label: labelOf[id], title: c.title.isEmpty ? c.appName : c.title,
                                pid: c.pid, focused: id == focused)
        }
    }

    func overviewCardSurfaceAdd(_ ov: OverviewState) {
        if ov.thumbnails { system.captureOverviewCards(scale: CGFloat(ov.monitor.screen.scale)) }
    }



    func overCircle(forward: Bool) {
        guard var ov = overviewState, ov.circle, !ov.members.isEmpty else { return }
        let ids = ov.members.filter { clientByIdAll($0) != nil }
        guard !ids.isEmpty else { return }
        let members = Set(ids)
        let order = clients.map(\.id).filter { members.contains($0) } + ids.filter { id in !clients.contains { $0.id == id } }
        let i = (ov.circleFocus ?? selectedMonitor.sel).flatMap { order.firstIndex(of: $0) } ?? 0
        let next = order[forward ? (i + 1) % order.count : (i - 1 + order.count) % order.count]
        let sizes = ids.compactMap { id -> (id: ClientID, size: CGSize)? in
            guard let c = clientByIdAll(id) else { return nil }
            let f = c.overviewBackupGeom ?? (c.isFloating ? c.floatGeom : (c.geom ?? c.frame))
            return (id, f.width <= 0 || f.height <= 0 ? CGSize(width: 100, height: 100) : f.size)
        }
        ov.circleFocus = next
        ov.cards = OverviewLayout.overviewScaleTab(clients: sizes, focused: next, workArea: ov.monitor.screen.workArea,
                                            gapInner: CGFloat(config.overviewgappi), gapOuter: CGFloat(config.overviewgappo),
                                            centerRatio: CGFloat(config.overcircleCenterRatio),
                                            titleBlockHeight: config.titleMessageBarHeight > 0
                                                ? CGFloat(config.titleMessageBarHeight + config.titleMessageBarGap) : 0)
        overviewState = ov
        titleMessageBarRefresh(ov.monitor)
        if ov.thumbnails {
            system.updateOverview(overlayCards(ov, focused: next))
// not in mango: only selected; the real window stays under the pictures
            if let c = clientByIdAll(next) { clientFocus(c, raise: false) }
            return
        }
        overview(ov)
        if let c = clientByIdAll(next) { clientFocus(c) }
    }

    func overview(_ ov: OverviewState) {
        let m = ov.monitor
        for c in clientsAll where c.mon === m {
            if let f = ov.cards[c.id] {
                system.resize(c, to: f, .move)
            } else {
                system.hide(c)
            }
        }
        updateBorders()
    }

    // not in mango: set_overview's leaving branch, which toggle_overview with a tc runs
    func leaveOverview(select: Client?) {
        guard let ov = overviewState else { return }
        if ov.labelsShown { system.closeJumpLabels() }
        if ov.thumbnails { system.closeOverview() }
        if ov.circle { system.hideTitleMessageBar() }
        overviewState = nil
        let m = ov.monitor
        let sel = select ?? m.sel.flatMap { clientByIdAll($0) }
        let tagmask = TagMask.mask(forTagNum: config.tagNum)
        var target: UInt32
        if let s = sel, s.tags & tagmask != 0 {
            target = getTagsFirstTag(s.tags)
        } else {
            target = m.ovbkCurrentTagset != 0 ? m.ovbkCurrentTagset & tagmask : (m.prevTag > 0 ? 1 << UInt32(m.prevTag - 1) : 1)
            if target == 0 { target = 1 }
        }
        m.tagset[m.seltags] = target
        for id in ov.members {
            guard let c = clientByIdAll(id), let b = c.overviewBackupGeom else { continue }
            if !ov.thumbnails && !c.isFloating { c.geom = b }
            c.overviewBackupGeom = nil
        }
        clientViewOnMonitor(target, on: m, changeFocus: true)
        fixMonTagsetFromOverview(m)
        for id in ov.members { clientByIdAll(id)?.overining = false }
        if !ov.thumbnails { arrange(m) }
        if let s = sel, s.tags & target != 0 { clientFocus(s) }
        printstatus()
    }
}
