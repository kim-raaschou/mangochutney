import CoreGraphics

package struct SwitcherState {
    enum Scope { case currentTag, allTags, allMonitors }

    let monitor: Monitor
    let scope: Scope
    var tiles: [ClientID]
    var index: Int
    var layout: SwitcherLayout.Result
}

package extension MangoServer {
    func switcher(_ arg: String) {
        let (dir, scope): (Int, SwitcherState.Scope) = switch arg {
        case "all_next": (1, .allMonitors)
        case "all_prev": (-1, .allMonitors)
        case "all_tag_next": (1, .allTags)
        case "all_tag_prev": (-1, .allTags)
        case "prev": (-1, .currentTag)
        default: (1, .currentTag)
        }
        guard selectedMonitor != nil, overviewState == nil else { return }
        if let sw = switcherState {
            if scope != sw.scope {
                switcherClose()
                switcherOpen(scope, dir)
            } else {
                switcherCycle(dir)
            }
        } else {
            switcherOpen(scope, dir)
        }
    }

    func switcherClientEligible(_ c: Client) -> Bool {
        c.mon != nil && !c.isMinimized && !c.isUnglobal
    }

    var switcherOrder: [Client] { focusStack.compactMap { clientByIdAll($0) } }

    internal func switcherOpen(_ scope: SwitcherState.Scope, _ dir: Int) {
        let m = selectedMonitor!
        let tiles = switcherOrder.filter { c in
            guard switcherClientEligible(c) else { return false }
            switch scope {
            case .currentTag: return c.mon === m && c.isVisible(on: m)
            case .allTags: return c.mon === m
            case .allMonitors: return Int32(bitPattern: c.tags) > 0
            }
        }
        guard !tiles.isEmpty else { return }
        let index = tiles.count > 1 ? (dir < 0 ? tiles.count - 1 : 1) : 0
        switcherState = SwitcherState(monitor: m, scope: scope, tiles: tiles.map(\.id), index: index,
                                 layout: SwitcherLayout.switcherLayout(sizes: tiles.map(\.frame.size), monitor: m.screen.frame))
        drawSwitcher(fresh: true)
    }

    func switcherCycle(_ dir: Int) {
        guard var sw = switcherState else { return }
        sw.index = (sw.index + dir + sw.tiles.count) % sw.tiles.count
        switcherState = sw
        drawSwitcher(fresh: false)
    }

    func switcherClose() {
        guard switcherState != nil else { return }
        switcherState = nil
        system.closeSwitcherPanel()
        system.hideTitleMessageBar()
    }

    func switcherCommitClient(_ c: Client?) {
        switcherClose()
        guard let c, switcherClientEligible(c), let cm = c.mon else { return }
        if !c.isVisible(on: cm) { clientViewOnMonitor(getTagsFirstTag(c.tags), on: cm) }
        clientFocus(c)
    }

    func switcherCommit() {
        guard let sw = switcherState else { return }
        switcherCommitClient(clientByIdAll(sw.tiles[sw.index]))
    }

    func switcherRemoveClient(_ id: ClientID) {
        guard var sw = switcherState, let i = sw.tiles.firstIndex(of: id) else { return }
        sw.tiles.remove(at: i)
        if sw.tiles.isEmpty { switcherClose(); return }
        if sw.index > i { sw.index -= 1 }
        sw.index = min(sw.index, sw.tiles.count - 1)
        let sizes = sw.tiles.map { clientByIdAll($0)?.frame.size ?? .zero }
        sw.layout = SwitcherLayout.switcherLayout(sizes: sizes, monitor: sw.monitor.screen.frame)
        switcherState = sw
        drawSwitcher(fresh: true)
    }

    // not in mango: switcher_tile_create's tiles, drawn by the port in one overlay
    func drawSwitcher(fresh: Bool) {
        guard drawsOverlays, let sw = switcherState else { return }
        let tiles: [SwitcherTile] = sw.tiles.enumerated().compactMap { i, id in
            guard let c = clientByIdAll(id) else { return nil }
            return SwitcherTile(id: id, frame: sw.layout.tiles[i], size: c.frame.size, pid: c.pid,
                                highlighted: i == sw.index)
        }
        let look = SwitcherLook(focus: config.focuscolor, border: config.bordercolor)
        if fresh {
            system.showSwitcher(panel: sw.layout.panel, tiles: tiles, look: look, scale: CGFloat(sw.monitor.screen.scale))
        } else {
            system.highlightSwitcher(tiles)
        }
        titleMessageBarRefresh(sw.monitor)
    }

    func switcherTitleMessageBarGeometry(_ m: Monitor) -> (client: Client, box: CGRect)? {
        guard let sw = switcherState, sw.monitor === m, let c = clientByIdAll(sw.tiles[sw.index]),
              let box = SwitcherLayout.titleMessageBarGeometry(below: sw.layout.panel, height: config.titleMessageBarHeight,
                                                               gap: config.titleMessageBarGap) else { return nil }
        return (c, box)
    }

    func overcircleTitleBarGeometry(_ m: Monitor) -> (client: Client, box: CGRect)? {
        guard let ov = overviewState, ov.monitor === m, ov.circle, let id = ov.circleFocus, let card = ov.cards[id],
              let c = clientByIdAll(id),
              let box = SwitcherLayout.titleMessageBarGeometry(below: card, height: config.titleMessageBarHeight,
                                                               gap: config.titleMessageBarGap) else { return nil }
        return (c, box)
    }

    func titleMessageBarGeometry(_ m: Monitor) -> (client: Client, box: CGRect)? {
        switcherTitleMessageBarGeometry(m) ?? overcircleTitleBarGeometry(m)
    }

    func titleMessageBarRefresh(_ m: Monitor) {
        guard drawsOverlays, let (c, box) = titleMessageBarGeometry(m), box.width > 0, box.height > 0 else {
            system.hideTitleMessageBar()
            return
        }
        system.showTitleMessageBar(frame: box, title: c.title, appid: c.appid,
                                   look: mangoBarDecorationApplyConfig(config.titleMessageBardata, mango: .mangoTitleMessageBar))
    }

    func titleMessageBarUpdateTitle(_ c: Client) {
        guard let m = c.mon ?? selectedMonitor, titleMessageBarGeometry(m)?.client === c else { return }
        titleMessageBarRefresh(m)
    }
}
