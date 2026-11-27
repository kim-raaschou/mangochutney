import CoreGraphics
import Foundation
import QuartzCore
import Mango

@MainActor
final class WindowMemory {
    var departed = DepartedWindows()
    var layoutURL: URL? = SavedLayout.defaultURL
    let session = SavedLayout.currentSession
    var lastSaved: SavedLayout?
    let queue = DispatchQueue(label: "mango.layout", qos: .utility)
    private var pruning = false
    /// The managed windows when the saved entries were last pruned.
    private var prunedWith: Set<ClientID>?

    func back(_ c: Client) -> DepartedWindow? {
        let back = departed.take(c.windowID).flatMap { d in d.bundleId.isEmpty || d.bundleId == c.bundleId ? d : nil }
        departed.endWave()
        return back
    }

    func leaving(_ server: MangoServer, _ c: Client, group: [ClientID], groupFocus: ClientID?, order: [ClientID]) {
        let snapshot = departed.orderSnapshot(leaving: c.windowID, order: order)
        var d = DepartedWindow(
            tags: c.tags, displayID: c.mon?.screen.displayID, isfloating: Self.isfloating(c), isglobal: c.isglobal,
            isoverlay: c.isoverlay, isminimized: c.isInScratchpad, isScratchpad: SCRATCHPAD_SHOWN(c),
            isnamedscratchpad: c.isnamedscratchpad, floatFrame: c.floatGeom.insetBy(dx: c.bw, dy: c.bw),
            scrollerProportion: CGFloat(c.scrollerProportion), orderSnapshot: snapshot, at: CACurrentMediaTime(),
            bundleId: c.bundleId, homeDisplayID: c.oldmonname,
            iscustomsize: c.iscustomsize)
        d.isfullscreen = c.overviewBackedUp ? c.overviewIsfullscreenbak : c.isfullscreen
        d.ismaximizescreen = c.overviewBackedUp ? c.overviewIsmaximizescreenbak : c.ismaximizescreen
        departed.remember(c.windowID, d)
        departed.rememberGroup(DepartedGroup(members: group, focus: groupFocus))
    }

    func returned(_ server: MangoServer, _ c: Client) {
        guard let gi = departed.groups.firstIndex(where: { $0.members.contains(c.windowID) }) else { return }
        let g = departed.groups[gi]
        let present = g.members.compactMap { server.clientByWindowID($0) }.filter { $0.mon != nil || server.clientIsParked($0) }
        if present.count == g.members.count { departed.groups.remove(at: gi) }
        guard present.count > 1, !server.monitors.contains(where: \.isoverview) else { return }
        let focus = present.first { $0.windowID == g.focus }
            ?? present.first { $0.isGroupFocus && !server.clientIsParked($0) } ?? present[0]
        for m in present where server.clientIsGroupMember(m) {
            if server.clientIsParked(m) { server.clientUnpark(m, focus) }
            server.clientGroupDetach(m)
        }
        for (i, m) in present.enumerated() {
            m.groupPrev = i > 0 ? present[i - 1] : nil
            m.groupNext = i + 1 < present.count ? present[i + 1] : nil
            m.isGroupFocus = m === focus
        }
        for m in present where m !== focus {
            m.mon = focus.mon
            m.tags = focus.tags
            m.tagVisible = false
            server.clientUpdateVisibility(m)
            server.clientPark(m)
        }
        if let m = focus.mon { server.arrange(m, false, false) }
    }

    static func isfloating(_ c: Client) -> Bool {
        c.overviewBackedUp ? c.overviewIsfloatingbak : c.isfloating
    }

    func currentLayout(_ server: MangoServer) -> SavedLayout {
        var windows: [SavedLayout.Window] = server.clientsAll.map { c in
            // Port extension: chutney_fullscreen_tag saves a window on its own tags, not its F tag.
            SavedLayout.Window(id: c.windowID, bundleId: c.bundleId, tags: server.mac.fullscreenHooks.savedTags(c), displayID: c.mon?.screen.displayID,
                               homeDisplayID: c.oldmonname, isfloating: Self.isfloating(c), isglobal: c.isglobal,
                               isoverlay: c.isoverlay, isminimized: c.isInScratchpad, isScratchpad: SCRATCHPAD_SHOWN(c),
                               isnamedscratchpad: c.isnamedscratchpad, floatFrame: c.floatGeom.insetBy(dx: c.bw, dy: c.bw),
                               scrollerProportion: CGFloat(c.scrollerProportion), orderSnapshot: nil,
                               iscustomsize: c.iscustomsize)
        }
        for (id, d) in departed.entries where server.clientByWindowID(id) == nil {
            windows.append(SavedLayout.Window(id: id, bundleId: d.bundleId, tags: d.tags, displayID: d.displayID,
                                              homeDisplayID: d.homeDisplayID, isfloating: d.isfloating,
                                              isglobal: d.isglobal, isoverlay: d.isoverlay, isminimized: d.isminimized,
                                              isScratchpad: d.isScratchpad, isnamedscratchpad: d.isnamedscratchpad,
                                              floatFrame: d.floatFrame,
                                              scrollerProportion: d.scrollerProportion, orderSnapshot: d.orderSnapshot,
                                              iscustomsize: d.iscustomsize))
        }
        windows.sort { $0.id < $1.id }
        var tagsets: [String: UInt32] = [:]
        var tagLayouts: [String: [SavedLayout.TagLayout]] = [:]
        var previousTagsets: [String: UInt32] = [:]
        var prevTags: [String: Int] = [:]
        for m in server.monitors {
            let display = String(m.screen.displayID)
            let view = server.mac.fullscreenHooks.savedView(m)   // Port extension: chutney_fullscreen_tag
            tagsets[display] = view.now
            previousTagsets[display] = view.before
            prevTags[display] = Int(m.pertag.prevtag)
            tagLayouts[display] = zip(m.pertag.ltidxs, m.pertag.configLtidxs).map {
                SavedLayout.TagLayout(layout: $0.name, configuredLayout: $1.name)
            }
        }
        var groups = departed.groups
        for c in server.clientsAll where server.clientIsGroupMember(c) && c.groupPrev == nil {
            let members = server.groupMembers(c)
            groups.removeAll { !Set($0.members).isDisjoint(with: members.map(\.windowID)) }
            groups.append(DepartedGroup(members: members.map(\.windowID), focus: members.first { $0.isGroupFocus }?.windowID))
        }
        return SavedLayout(session: session, order: server.clients.map(\.windowID), windows: windows, tagsets: tagsets,
                           tagLayouts: tagLayouts, previousTagsets: previousTagsets, prevTags: prevTags,
                           groups: groups.isEmpty ? nil : groups)
    }

    func save(_ server: MangoServer, final: Bool = false) {
        guard server.started, let url = layoutURL, !session.isEmpty else { return }
        if final {
            let now = currentLayout(server)
            queue.sync { Self.write(now, to: url) }
            return
        }
        // The window server's list is asked for on the memory's queue: on the main thread it is a round trip
        // at every status change while saved entries remain. It is asked for only when the managed windows
        // changed: asked off the main thread while the main thread commits its windows (a drag moves the
        // borders at every frame), the window server holds both for up to 400 ms.
        let managed = Set(server.clientsAll.map(\.windowID))
        if departed.hasSavedEntries && !pruning && managed != prunedWith {
            pruning = true
            prunedWith = managed
            queue.async { [weak self] in
                let ids = AppWorker.allWindowIDs()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.pruning = false
                        self.departed.dropSaved(keeping: ids)
                    }
                }
            }
        }
        let now = currentLayout(server)
        guard now != lastSaved else { return }
        lastSaved = now
        queue.async { Self.write(now, to: url) }
    }

    nonisolated private static func write(_ layout: SavedLayout, to url: URL) {
        do { try layout.write(to: url) } catch { wlrLog(.error, "cannot write \(url.path): \(error.localizedDescription)") }
    }

    func restore(_ server: MangoServer) {
        if session.isEmpty { wlrLog(.info, "no window server session id: the layout is not kept across restarts") }
        guard let url = layoutURL, let saved = SavedLayout.load(from: url, session: session) else { return }
        let now = CACurrentMediaTime()
        for (id, d) in saved.departed(at: now) { departed.remember(id, d) }
        for g in saved.groups ?? [] { departed.rememberGroup(g) }
        for m in server.monitors {
            let display = String(m.screen.displayID)
            if let t = saved.tagsets[display], t & ~TAG0_MASK != 0 {
                m.tagset[m.seltags] = t
                m.pertag.curtag = t == 0 ? 1 : server.getTagsFirstTagNum(t)
            }
            if let t = saved.previousTagsets?[display], t & ~TAG0_MASK != 0 {
                m.tagset[m.seltags ^ 1] = t
            }
            if let t = saved.prevTags?[display], (1...31).contains(t) { m.pertag.prevtag = UInt32(t) }
            for (i, t) in (saved.tagLayouts?[display] ?? []).enumerated() where i < Int(PERTAG_SLOTS) {
                if m.pertag.configLtidxs[i].name == (t.configuredLayout ?? LayoutKind.tile.name), let layout = LayoutKind(name: t.layout) {
                    m.pertag.ltidxs[i] = layout
                }
            }
        }
        lastSaved = saved
        wlrLog(.info, "restoring \(saved.windows.count) window(s) from \(url.path)")
    }
}
