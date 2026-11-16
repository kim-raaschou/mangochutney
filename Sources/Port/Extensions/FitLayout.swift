import CoreGraphics
import Foundation
import Mango

/// Port extension: not in mango. chutney_fit_layout: where a tiled window's app keeps it larger than
/// its tile and the layout has room for it on that side, mango's own resizewin on the window by what
/// it lacks, as from the keyboard (the far border, or the near one at the layout's far edge); nothing
/// where the windows beside it leave no room. The dispatcher chutney_fit_layout always; 1: the menu
/// bar's "Fit layout"; 2: also a macOS notification with a Fit button, or one saying there is no room;
/// 3: also by itself.
@MainActor
enum FitLayout {
    enum Axis: String { case width, height }

    struct Step: Equatable {
        var id: ClientID
        var axis: Axis
        var by: Int
    }

    struct Plan: Equatable {
        var title: String
        var steps: [Step]
        var over: [String] = []
    }

    /// What the extension remembers: the view and notification seen, the fits made by itself, the sides
    /// resizewin did not grow, and the least size each open window's app has kept it at.
    struct State {
        var seen: String?
        var notified: String?
        var autoView: String?
        var autoFits = 0
        var lastAuto: [Step]?
        var stuck: Set<String> = []
        var waiting = false
        var minimum: [ClientID: CGSize] = [:]
    }

    static let autoFitsPerView = 3

    // MARK: the plan

    /// The tiled windows shown: on one tile only the one shown.
    static func shown(_ server: MangoServer, _ m: Monitor) -> [Client] {
        let tiled = server.tiledClients(m).filter { !$0.parked }
        return tiled.filter { c in
            let tile = tiled.filter { $0.tile == c.tile }
            return tile.count == 1 || c === (tile.first { $0.id == m.sel } ?? tile[0])
        }
    }

    static func view(_ server: MangoServer, _ m: Monitor) -> String {
        let ids = server.tiledClients(m).map { String($0.id) }.joined(separator: ",")
        return "\(m.screen.name)|\(m.tagset[m.seltags])|\(m.layout)|\(ids)"
    }

    static func span(_ r: CGRect, _ axis: Axis) -> (lo: CGFloat, hi: CGFloat) {
        axis == .width ? (r.minX, r.maxX) : (r.minY, r.maxY)
    }

    static func size(_ s: CGSize, _ axis: Axis) -> CGFloat { axis == .width ? s.width : s.height }

    /// What a window keeps beyond its tile on `axis`.
    static func lacks(_ c: Client, _ axis: Axis) -> CGFloat {
        guard let rs = c.refusedSize else { return 0 }
        return size(rs, axis) - size(c.tile.size, axis)
    }

    /// The sizes the apps keep their windows at, larger than their tiles, while the windows stand still:
    /// on each side the largest seen, for as long as the window is open.
    static func learn(_ server: MangoServer, _ m: Monitor) {
        let mac = server.mac
        guard server.grab == nil, !mac.animationsRunning else { return }
        let open = Set(server.clientsAll.map(\.id))
        mac.fitState.minimum = mac.fitState.minimum.filter { open.contains($0.key) }
        for c in shown(server, m) {
            guard let rs = c.refusedSize else { continue }
            var least = mac.fitState.minimum[c.id] ?? .zero
            if lacks(c, .width) > 0.5 { least.width = max(least.width, rs.width) }
            if lacks(c, .height) > 0.5 { least.height = max(least.height, rs.height) }
            if least != .zero { mac.fitState.minimum[c.id] = least }
        }
    }

    /// Whether the layout has room for `c` at the size it keeps on `axis`: along its row (or column), the
    /// size it keeps, the windows beside it at the sizes they keep on that side (where they fit, the least
    /// their apps have kept them at, none where not seen) and the gaps between them, within the tiles'
    /// extent.
    static func room(_ c: Client, _ axis: Axis, _ windows: [Client], minimum: [ClientID: CGSize] = [:]) -> Bool {
        guard let rs = c.refusedSize else { return false }
        let g = c.tile
        let across: Axis = axis == .width ? .height : .width
        let band = span(g, across)
        let line = windows.filter { o in
            let s = span(o.tile, across)
            return min(s.hi, band.hi) - max(s.lo, band.lo) > 0.5
        }
        var lanes: [(lo: CGFloat, hi: CGFloat, keeps: CGFloat)] = []
        for o in line {
            let s = span(o.tile, axis)
            let keeps = o === c ? size(rs, axis)
                : lacks(o, axis) > 0.5 ? size(o.refusedSize!, axis)
                : minimum[o.id].map { size($0, axis) } ?? 0
            if let i = lanes.firstIndex(where: { min($0.hi, s.hi) - max($0.lo, s.lo) > 0.5 }) {
                lanes[i] = (min(lanes[i].lo, s.lo), max(lanes[i].hi, s.hi), max(lanes[i].keeps, keeps))
            } else {
                lanes.append((s.lo, s.hi, keeps))
            }
        }
        guard let lo = lanes.map(\.lo).min(), let hi = lanes.map(\.hi).max() else { return false }
        let gaps = (hi - lo) - lanes.reduce(0) { $0 + $1.hi - $1.lo }
        return lanes.reduce(0) { $0 + $1.keeps } + gaps <= hi - lo + 0.5
    }

    static func plan(_ server: MangoServer, _ m: Monitor) -> Plan? {
        learn(server, m)
        let minimum = server.mac.fitState.minimum
        let windows = shown(server, m)
        let over = windows.filter { $0.refusedSize != nil }
        let key = view(server, m)
        var steps: [Step] = []
        var names: [String] = []
        for c in over {
            guard let rs = c.refusedSize else { continue }
            let g = c.tile
            for axis in [Axis.width, .height] {
                let lack = size(rs, axis) - size(g.size, axis)
                guard lack > 0.5, !server.mac.fitState.stuck.contains("\(key)|\(c.id)|\(axis)"),
                      room(c, axis, windows, minimum: minimum) else { continue }
                let by = Int(lack.rounded(.up))
                steps.append(Step(id: c.id, axis: axis, by: by))
                names.append("\(c.appName) \(by) pt \(axis == .width ? "wider" : "taller")")
            }
        }
        guard !steps.isEmpty else { return nil }
        var apps: [String] = []
        for c in over where steps.contains(where: { $0.id == c.id }) && !apps.contains(c.appName) { apps.append(c.appName) }
        return Plan(title: "Fit layout: " + names.joined(separator: ", "), steps: steps, over: apps)
    }

    // MARK: doing it

    /// mango's resizewin on the window: its far border out, or its near one where it is at the far edge
    /// of the layout; again while it grows and still lacks (mango's ratios round), at most three times.
    /// Where the first one does not grow it (dwindle moves the split above it, which may be its near
    /// border), the other way once. One that takes from a window already larger than its tile is put
    /// back too. A side that grows neither way is not offered again in this view. The sizes the windows
    /// keep are the ones seen before: the apps say again only after the layout is written.
    static func apply(_ server: MangoServer, _ plan: Plan) {
        guard let m = server.selectedMonitor else { return }
        let key = view(server, m)
        var kept: [ClientID: CGSize] = [:]
        for c in shown(server, m) { kept[c.id] = c.refusedSize }
        func lack(_ c: Client, _ axis: Axis) -> CGFloat {
            guard let k = kept[c.id] else { return 0 }
            return size(k, axis) - size(c.tile.size, axis)
        }
        for s in plan.steps {
            guard let c = server.clientByIdAll(s.id) else { continue }
            let g0 = c.tile
            let tiles = shown(server, m).map(\.tile).reduce(CGRect.null) { $0.union($1) }
            let atFar = span(tiles, s.axis).hi - span(g0, s.axis).hi <= 1
            var sign = atFar ? -1 : 1
            var by = CGFloat(s.by)
            var grown = false
            var turned = false
            var tries = 0
            while tries < 3 {
                let before = c.tile
                let others = shown(server, m).filter { $0 !== c && lack($0, s.axis) > 0.5 }
                let lacked = others.map { lack($0, s.axis) }
                let offset = Int(by.rounded(.up)) * sign
                resizewin(server, c, s.axis, offset)
                let after = c.tile
                let grew = size(after.size, s.axis) - size(before.size, s.axis)
                let worse = zip(others, lacked).contains { lack($0, s.axis) > $1 + 0.5 }
                if grew < 0.5 || worse {
                    if abs(grew) > 0.5 { putBack(server, c, s.axis, to: size(before.size, s.axis), offset: offset, grew: grew) }
                    if !grown && !turned {
                        turned = true
                        sign = -sign
                        continue
                    }
                    server.mac.fitState.stuck.insert("\(key)|\(c.id)|\(s.axis)")
                    break
                }
                grown = true
                tries += 1
                by = lack(c, s.axis)
                if by <= 0.5 { break }
            }
        }
    }

    static func resizewin(_ server: MangoServer, _ c: Client, _ axis: Axis, _ offset: Int) {
        let args = axis == .width ? ["\(offset)", "0"] : ["0", "\(offset)"]
        _ = server.dispatch(Dispatch(name: "resizewin", args: args), target: c)
    }

    /// resizewin until the window is back at `to` on `axis`, each offset from what the one before did:
    /// mango's resizewin works from the ratios it finds, so the same offset the other way does not land
    /// where it began. Its own ratio is the one resizewin changed, so the others are back too.
    static func putBack(_ server: MangoServer, _ c: Client, _ axis: Axis, to target: CGFloat, offset: Int, grew: CGFloat) {
        var k = grew / CGFloat(offset)
        for _ in 0..<8 {
            guard abs(k) > 0.001 else { return }
            let now = size(c.tile.size, axis)
            let miss = target - now
            if abs(miss) < 0.5 { return }
            let step = Int((miss / k).rounded())
            if step == 0 { return }
            resizewin(server, c, axis, step)
            let moved = size(c.tile.size, axis) - now
            if abs(moved) > 0.5 { k = moved / CGFloat(step) }
        }
    }

    /// The dispatcher chutney_fit_layout: the selected monitor's view.
    static func fit(_ server: MangoServer) {
        guard let m = server.selectedMonitor, let plan = plan(server, m) else { return }
        apply(server, plan)
    }

    /// mango's status changed (printstatus): the notification (2) or the fit by itself (3), for the
    /// selected monitor's view, once for each view, size and level seen, when the windows stand still.
    static func statusChanged(_ server: MangoServer) {
        let level = server.config.chutneyFitLayout
        let mac = server.mac
        if level >= 1, let m = server.selectedMonitor { learn(server, m) }
        guard level >= 2, let m = server.selectedMonitor else {
            if mac.fitState.notified != nil { notify(server, nil) }
            mac.fitState.seen = nil
            return
        }
        // Not while windows move: the sizes between are not the layout's.
        guard server.grab == nil, !mac.animationsRunning else {
            if mac.animationsRunning && !mac.fitState.waiting {
                mac.fitState.waiting = true
                mac.whenAnimationsIdle {
                    mac.fitState.waiting = false
                    statusChanged(server)
                }
            }
            return
        }
        let windows = shown(server, m).map { c in
            "\(c.id):\(c.tile):\(c.refusedSize.map { "\($0)" } ?? "")"
        }
        let seen = "\(level)|\(!m.isoverview)|\(server.grab == nil)|\(m.screen.name)|\(m.tagset[m.seltags])|\(m.layout)|\(m.sel ?? 0)|\(windows.joined(separator: ","))"
        guard mac.fitState.seen != seen else { return }
        mac.fitState.seen = seen
        let plan = plan(server, m)
        let over = shown(server, m).filter { $0.refusedSize != nil }
        if !over.isEmpty {
            let sizes = over.map { c in
                "\(c.appName) tile \(Int(c.tile.width))x\(Int(c.tile.height)) keeps \(c.refusedSize.map { "\(Int($0.width))x\(Int($0.height))" } ?? "-")"
            }
            let least = shown(server, m).filter { $0.refusedSize == nil }.compactMap { c in
                mac.fitState.minimum[c.id].map { "\(c.appName) at least \(Int($0.width))x\(Int($0.height))" }
            }
            wlrLog(.debug, "chutney_fit_layout: \(m.layout): \(plan?.title ?? "no room") (\((sizes + least).joined(separator: "; ")))")
        }
        if let plan, level >= 3 {
            if mac.fitState.notified != nil { notify(server, nil) }
            auto(server, m, plan)
        } else if let plan {
            notify(server, plan)
        } else {
            noRoom(server, over.filter { lacks($0, .width) > 0.5 || lacks($0, .height) > 0.5 })
        }
    }

    static func title(_ apps: [String]) -> String {
        "\(apps.joined(separator: ", ")) larger than \(apps.count == 1 ? "its tile" : "their tiles")"
    }

    /// A macOS notification with a Fit button; once for a plan, taken away when there is none.
    static func notify(_ server: MangoServer, _ plan: Plan?) {
        guard let plan else {
            post(server, nil)
            return
        }
        post(server, (title(plan.over), plan.title, true))
    }

    /// Where windows are larger than their tiles and the layout has no room for them: a notification that
    /// says so, with no button; once for what they need, taken away when none is over.
    static func noRoom(_ server: MangoServer, _ over: [Client]) {
        guard !over.isEmpty else {
            post(server, nil)
            return
        }
        var apps: [String] = []
        for c in over where !apps.contains(c.appName) { apps.append(c.appName) }
        let needs = over.map { c in
            let sides = [Axis.width, .height].filter { lacks(c, $0) > 0.5 }
                .map { "\(Int(size(c.refusedSize!, $0).rounded())) pt \($0.rawValue)" }
            return "\(c.appName) needs \(sides.joined(separator: " and "))"
        }
        let body = "No room in this layout: \(needs.joined(separator: ", ")). Another layout or fewer windows on the tag may give it room."
        post(server, (title(apps), body, false))
    }

    static func post(_ server: MangoServer, _ note: (title: String, body: String, fit: Bool)?) {
        let mac = server.mac
        guard let note else {
            if mac.fitState.notified != nil { mac.removeFitNotification() }
            mac.fitState.notified = nil
            return
        }
        guard !server.monitors.contains(where: \.isoverview), server.grab == nil else { return }
        guard mac.fitState.notified != note.title + note.body else { return }
        mac.fitState.notified = note.title + note.body
        mac.postFitNotification(title: note.title, body: note.body, fit: note.fit)
    }

    /// The fit by itself: not in overview or a drag, the same fit not twice, and at most three while the
    /// view (tags, layout, windows) stays, so two windows that take each other's room cannot go on.
    /// The fit runs after this turn of the main queue (not a timer), out of Placement's reading.
    static func auto(_ server: MangoServer, _ m: Monitor, _ plan: Plan) {
        guard !server.monitors.contains(where: \.isoverview), server.grab == nil else { return }
        let key = view(server, m)
        let mac = server.mac
        if mac.fitState.autoView != key {
            mac.fitState.autoView = key
            mac.fitState.autoFits = 0
            mac.fitState.lastAuto = nil
        }
        guard mac.fitState.lastAuto != plan.steps, mac.fitState.autoFits < autoFitsPerView else { return }
        mac.fitState.autoFits += 1
        mac.fitState.lastAuto = plan.steps
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard server.selectedMonitor === m, let now = FitLayout.plan(server, m), now == plan else { return }
                apply(server, now)
            }
        }
    }
}
