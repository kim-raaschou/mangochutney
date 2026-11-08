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

    func back(_ c: Client) -> DepartedWindow? {
        let back = departed.take(c.id).flatMap { d in d.bundleId.isEmpty || d.bundleId == c.bundleId ? d : nil }
        departed.endWave()
        return back
    }

    func leaving(_ server: MangoServer, _ c: Client, group: [ClientID], groupFocus: ClientID?, order: [ClientID]) {
        let snapshot = departed.orderSnapshot(leaving: c.id, order: order)
        departed.remember(c.id, DepartedWindow(
            tags: c.tags, displayID: c.mon?.screen.displayID, isFloating: Self.isFloating(c), isGlobal: c.isGlobal,
            isOverlay: c.isOverlay, isMinimized: c.isInScratchpad, isScratchpad: c.scratchpadShown,
            isNamedScratchpad: c.isNamedScratchpad, floatFrame: c.floatGeom,
            scrollerProportion: c.scrollerProportion, orderSnapshot: snapshot, at: CACurrentMediaTime(),
            bundleId: c.bundleId, homeDisplayID: c.oldmonname,
            isCustomSize: c.isCustomSize))
        departed.rememberGroup(DepartedGroup(members: group, focus: groupFocus))
    }

    func returned(_ server: MangoServer, _ c: Client) {
        guard let gi = departed.groups.firstIndex(where: { $0.members.contains(c.id) }) else { return }
        let g = departed.groups[gi]
        let present = g.members.compactMap { server.clientByIdAll($0) }.filter { $0.mon != nil }
        if present.count == g.members.count { departed.groups.remove(at: gi) }
        guard present.count > 1, server.overviewState == nil else { return }
        let focus = present.first { $0.id == g.focus }
            ?? present.first { $0.isGroupFocus && !$0.groupParked } ?? present[0]
        for m in present where m.isGroupMember {
            if m.groupParked { server.clientUnpark(m, after: focus) }
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
            server.clientPark(m)
        }
        if let m = focus.mon { server.arrange(m) }
    }

    static func isFloating(_ c: Client) -> Bool {
        c.overviewBackupGeom != nil ? c.overviewIsFloatingBak : c.isFloating
    }

    func currentLayout(_ server: MangoServer) -> SavedLayout {
        var windows: [SavedLayout.Window] = server.clientsAll.map { c in
            SavedLayout.Window(id: c.id, bundleId: c.bundleId, tags: c.tags, displayID: c.mon?.screen.displayID,
                               homeDisplayID: c.oldmonname, isFloating: Self.isFloating(c), isGlobal: c.isGlobal,
                               isOverlay: c.isOverlay, isMinimized: c.isInScratchpad, isScratchpad: c.scratchpadShown,
                               isNamedScratchpad: c.isNamedScratchpad, floatFrame: c.floatGeom,
                               scrollerProportion: c.scrollerProportion, orderSnapshot: nil,
                               isCustomSize: c.isCustomSize)
        }
        for (id, d) in departed.entries where server.clientByIdAll(id) == nil {
            windows.append(SavedLayout.Window(id: id, bundleId: d.bundleId, tags: d.tags, displayID: d.displayID,
                                              homeDisplayID: d.homeDisplayID, isFloating: d.isFloating,
                                              isGlobal: d.isGlobal, isOverlay: d.isOverlay, isMinimized: d.isMinimized,
                                              isScratchpad: d.isScratchpad, isNamedScratchpad: d.isNamedScratchpad,
                                              floatFrame: d.floatFrame,
                                              scrollerProportion: d.scrollerProportion, orderSnapshot: d.orderSnapshot,
                                              isCustomSize: d.isCustomSize))
        }
        windows.sort { $0.id < $1.id }
        var tagsets: [String: UInt32] = [:]
        var tagLayouts: [String: [SavedLayout.TagLayout]] = [:]
        var previousTagsets: [String: UInt32] = [:]
        var prevTags: [String: Int] = [:]
        for m in server.monitors {
            let display = String(m.screen.displayID)
            tagsets[display] = m.tagset[m.seltags]
            previousTagsets[display] = m.tagset[m.seltags ^ 1]
            prevTags[display] = m.prevTag
            tagLayouts[display] = m.pertag.map {
                SavedLayout.TagLayout(layout: $0.layout.name, configuredLayout: $0.configLayout.name)
            }
        }
        var groups = departed.groups
        for c in server.clientsAll where c.isGroupMember && c.groupPrev == nil {
            let members = server.groupMembers(c)
            groups.removeAll { !Set($0.members).isDisjoint(with: members.map(\.id)) }
            groups.append(DepartedGroup(members: members.map(\.id), focus: members.first { $0.isGroupFocus }?.id))
        }
        return SavedLayout(session: session, order: server.clients.map(\.id), windows: windows, tagsets: tagsets,
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
        if departed.hasSavedEntries { departed.dropSaved(keeping: server.system.allWindowIDs()) }
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
            if let t = saved.tagsets[display], t & ~TagMask.special != 0 {
                m.tagset[m.seltags] = t
                m.curtag = TagMask.getTagsFirstTagNum(t) ?? 1
            }
            if let t = saved.previousTagsets?[display], t & ~TagMask.special != 0 {
                m.tagset[m.seltags ^ 1] = t
            }
            if let t = saved.prevTags?[display], (1...31).contains(t) { m.prevTag = t }
            for (p, t) in zip(m.pertag, saved.tagLayouts?[display] ?? []) {
                if p.configLayout.name == (t.configuredLayout ?? LayoutKind.tile.name), let layout = LayoutKind(name: t.layout) {
                    p.layout = layout
                }
            }
        }
        lastSaved = saved
        wlrLog(.info, "restoring \(saved.windows.count) window(s) from \(url.path)")
    }
}
