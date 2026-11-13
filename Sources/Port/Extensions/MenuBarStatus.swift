import CoreGraphics
import Mango

public struct MenuBarTag: Equatable {
    public var number: Int
    public var active: Bool
    public var overlap: Bool
    /// Port extension: chutney_fullscreen_tag. An F tag: its window's app, drawn by its icon, and its name.
    public var app: pid_t?
    public var label: String?

    public init(number: Int, active: Bool, overlap: Bool = false, app: pid_t? = nil, label: String? = nil) {
        self.number = number; self.active = active; self.overlap = overlap; self.app = app; self.label = label
    }
}

public struct MenuBarMonitor: Equatable {
    public var name: String
    public var tags: [MenuBarTag]
    public var layout: LayoutKind
    public var selected: Bool
}

public struct MenuBarTagHit: Equatable, Sendable {
    public var frame: CGRect
    public var monitor: String
    public var tag: Int

    public init(frame: CGRect, monitor: String, tag: Int) { self.frame = frame; self.monitor = monitor; self.tag = tag }
}

public enum MenuBarStatus {
    @MainActor
    public static func publishTags(_ server: MangoServer, _ hits: [MenuBarTagHit]) {
        server.mac.router.publish { $0.menuBarTags = hits.filter { $0.tag > 0 } }
    }

    @MainActor
    public static func monitors(_ server: MangoServer) -> [MenuBarMonitor] {
        server.monitors
            .sorted { ($0.screen.frame.minX, $0.screen.frame.minY) < ($1.screen.frame.minX, $1.screen.frame.minY) }
            .map { MenuBarMonitor(name: $0.screen.name, tags: tags(server, $0), layout: $0.layout, selected: $0 === server.selectedMonitor) }
    }

    @MainActor
    static func tags(_ server: MangoServer, _ m: Monitor) -> [MenuBarTag] {
        var tags: [MenuBarTag] = []
        for i in 1...server.config.tagNum {
            let bit: UInt32 = 1 << UInt32(i - 1)
            let active = m.tagset[m.seltags] & bit != 0
            let occupied = server.clientsAll.contains { $0.mon === m && $0.tags & bit != 0 && !$0.isMinimized }
            if active || occupied || m.pertag[i].noHide {
                tags.append(MenuBarTag(number: i, active: active, overlap: overlaps(server, m, tag: i)))
            }
        }
        tags += FullscreenTag.menuBarTags(server, m)   // Port extension: chutney_fullscreen_tag
        if m.tagset[m.seltags] & (1 << 31) != 0 {
            tags.append(MenuBarTag(number: 0, active: true, overlap: overlaps(server, m, tag: 0)))
        }
        return tags
    }

    /// Port extension: chutney_overlap_warning. A tiled window shown on the tag that its app keeps larger than its tile.
    @MainActor
    static func overlaps(_ server: MangoServer, _ m: Monitor, tag t: Int) -> Bool {
        guard server.config.chutneyOverlapWarning else { return false }
        let bit: UInt32 = t == 0 ? 1 << 31 : 1 << UInt32(t - 1)
        let shown = server.tiledClients(m).filter { $0.tags & bit != 0 && !$0.parked && $0.geom != nil }
        return shown.contains { c in
            let tile = shown.filter { $0.geom == c.geom }
            guard tile.count == 1 || c === (tile.first { $0.id == m.sel } ?? tile[0]), let rs = c.refusedSize, let g = c.geom
            else { return false }
            return rs.width > g.width + 0.5 || rs.height > g.height + 0.5
        }
    }

    /// Port extension: chutney_fit_layout. The menu's "Fit layout", where the selected monitor's view can be fitted.
    @MainActor
    public static func fitTitle(_ server: MangoServer) -> String? {
        guard server.config.chutneyFitLayout > 0, let m = server.selectedMonitor else { return nil }
        return FitLayout.plan(server, m)?.title
    }

    @MainActor
    public static func fit(_ server: MangoServer) { FitLayout.fit(server) }

    @MainActor
    public static func viewTag(_ server: MangoServer, monitor name: String, tag: Int) {
        guard tag > 0, let m = server.monitors.first(where: { $0.screen.name == name }) else { return }
        if m !== server.selectedMonitor { server.focusMonitor(m) }
        if tag > server.config.tagNum { return FullscreenTag.viewTag(server, m, tag: tag) }   // Port extension: chutney_fullscreen_tag
        _ = server.dispatch(Dispatch(name: "view", args: ["\(tag)"]))
    }
}
