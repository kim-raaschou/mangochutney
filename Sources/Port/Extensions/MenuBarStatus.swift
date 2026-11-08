import CoreGraphics
import Mango

public struct MenuBarTag: Equatable {
    public var number: Int
    public var active: Bool
    public var overlap: Bool

    public init(number: Int, active: Bool, overlap: Bool = false) { self.number = number; self.active = active; self.overlap = overlap }
}

public struct MenuBarMonitor: Equatable {
    public var name: String
    public var tags: [MenuBarTag]
    public var layout: LayoutKind
    public var selected: Bool
}

public struct MenuBarSuggestion: Equatable {
    public enum Action: Equatable {
        case moveToTag(ClientID, Int)
        case float(ClientID)
    }
    public var title: String
    public var action: Action
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
                tags.append(MenuBarTag(number: i, active: active, overlap: !overlaps(server, m, tag: i).isEmpty))
            }
        }
        if m.tagset[m.seltags] & (1 << 31) != 0 {
            tags.append(MenuBarTag(number: 0, active: true, overlap: !overlaps(server, m, tag: 0).isEmpty))
        }
        return tags
    }

    @MainActor
    static func overlaps(_ server: MangoServer, _ m: Monitor, tag t: Int) -> [(client: Client, width: Int, height: Int)] {
        guard server.config.chutneyOverlapWarning else { return [] }
        let bit: UInt32 = t == 0 ? 1 << 31 : 1 << UInt32(t - 1)
        let shown = server.tiledClients(m).filter { $0.tags & bit != 0 && !$0.parked && $0.geom != nil }
        return shown.compactMap { c -> (client: Client, width: Int, height: Int)? in
            let tile = shown.filter { $0.geom == c.geom }
            guard tile.count == 1 || c === (tile.first { $0.id == m.sel } ?? tile[0]), let rs = c.refusedSize, let g = c.geom
            else { return nil }
            let w = Int((rs.width - g.width).rounded()), h = Int((rs.height - g.height).rounded())
            guard w > 0 || h > 0 else { return nil }
            return (c, max(0, w), max(0, h))
        }.sorted { $0.width + $0.height > $1.width + $1.height }
    }

    @MainActor
    public static func overlapLines(_ server: MangoServer)
        -> [(heading: String, windows: [(app: String, by: String)], suggestions: [MenuBarSuggestion])] {
        let mons = server.monitors.sorted { ($0.screen.frame.minX, $0.screen.frame.minY) < ($1.screen.frame.minX, $1.screen.frame.minY) }
        return mons.flatMap { m in
            (Array(1...server.config.tagNum) + [0]).compactMap { t -> (heading: String, windows: [(app: String, by: String)], suggestions: [MenuBarSuggestion])? in
                let list = overlaps(server, m, tag: t)
                guard let first = list.first else { return nil }
                let tag = t == 0 ? "Special tag" : "Tag \(t)"
                let on = mons.count > 1 ? " on \(m.screen.name)" : ""
                let windows = list.map { o in
                    (o.client.appName, [o.width > 0 ? "\(o.width) pt larger in width" : nil,
                                        o.height > 0 ? "\(o.height) pt larger in height" : nil].compactMap { $0 }.joined(separator: ", "))
                }
                let view = m.tagset[m.seltags]
                let inView = t == 0 ? view & (1 << 31) != 0 : view & (1 << UInt32(t - 1)) != 0
                var suggestions: [MenuBarSuggestion] = []
                if inView {
                    let c = first.client
                    if let empty = (1...server.config.tagNum).first(where: { e in
                        let bit: UInt32 = 1 << UInt32(e - 1)
                        return view & bit == 0 && !server.clientsAll.contains { $0.mon === m && $0.tags & bit != 0 }
                    }) {
                        suggestions.append(MenuBarSuggestion(title: "Move \(c.appName) to tag \(empty)", action: .moveToTag(c.id, empty)))
                    }
                    suggestions.append(MenuBarSuggestion(title: "Float \(c.appName)", action: .float(c.id)))
                }
                return ("Overlap on \(tag)\(on)", windows, suggestions)
            }
        }
    }

    @MainActor
    public static func apply(_ server: MangoServer, _ s: MenuBarSuggestion) {
        switch s.action {
        case .moveToTag(let id, let t):
            guard let c = server.clientByIdAll(id) else { return }
            _ = server.dispatch(Dispatch(name: "tagsilent", args: ["\(t)"]), target: c)
        case .float(let id):
            guard let c = server.clientByIdAll(id) else { return }
            _ = server.dispatch(Dispatch(name: "togglefloating"), target: c)
        }
    }

    @MainActor
    public static func viewTag(_ server: MangoServer, monitor name: String, tag: Int) {
        guard tag > 0, let m = server.monitors.first(where: { $0.screen.name == name }) else { return }
        if m !== server.selectedMonitor { server.focusMonitor(m) }
        _ = server.dispatch(Dispatch(name: "view", args: ["\(tag)"]))
    }
}
