import CoreGraphics
import Foundation
import QuartzCore
import Mango

/// Not in mango: windows that leave and come back. macOS reports windows gone and back
/// around sleep, and a restart of mango (an update, the LaunchAgent after a crash) finds
/// every window anew; mango itself has neither. What a window had is remembered as it goes
/// (DepartedWindows) and kept on disk (SavedLayout), and given back to mango's
/// handle_client_map when the window is found again. Joined to mango's code through
/// MacEvents.windowDiscovered (back, returned) and PortHooks (windowLeaving, saveLayout, restoreLayout).
@MainActor
final class WindowMemory {
    var departed = DepartedWindows()
    /// Where the layout is kept; nil keeps none (tests).
    var layoutURL: URL? = SavedLayout.defaultURL
    let session = SavedLayout.currentSession
    var lastSaved: SavedLayout?
    let queue = DispatchQueue(label: "mango.layout", qos: .utility)

    /// A window found: what it had when it left, if it is the same app's window (the same
    /// id for another app's window cannot happen within a session; the saved layout checks
    /// the session too). The next window to leave starts a new wave.
    func back(_ c: Client) -> DepartedWindow? {
        let back = departed.take(c.id).flatMap { d in d.bundleId.isEmpty || d.bundleId == c.bundleId ? d : nil }
        departed.endWave()
        return back
    }

    /// A window leaves: what it had, its place in the client order and its group.
    func leaving(_ server: MangoServer, _ c: Client, group: [ClientID], groupFocus: ClientID?, order: [ClientID]) {
        let snapshot = departed.orderSnapshot(leaving: c.id, order: order)
        departed.remember(c.id, DepartedWindow(
            tags: c.tags, displayID: c.mon?.screen.displayID, isFloating: c.isFloating, isGlobal: c.isGlobal,
            isOverlay: c.isOverlay, isMinimized: c.isInScratchpad, isScratchpad: c.scratchpadShown,
            isNamedScratchpad: c.isNamedScratchpad, floatFrame: c.floatGeom,
            scrollerProportion: c.scrollerProportion, orderSnapshot: snapshot, at: CACurrentMediaTime(),
            bundleId: c.bundleId, homeDisplayID: c.oldmonname,
            isCustomSize: c.isCustomSize))
        departed.rememberGroup(DepartedGroup(members: group, focus: groupFocus))
    }

    /// A window back (after sleep, or found after a restart) whose group was kept: the
    /// group is built again from its members that are here, in their order, with the one
    /// that was in view in view (the others parked, as client_park). Built again as each
    /// member comes back; forgotten once all are.
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

    // MARK: The saved layout (survives a restart of mango)

    /// Every managed window, plus the ones that are away (sleep) or not seen yet since
    /// the start (an app that has not answered), so a write never forgets a window.
    func currentLayout(_ server: MangoServer) -> SavedLayout {
        var windows: [SavedLayout.Window] = server.clientsAll.map { c in
            SavedLayout.Window(id: c.id, bundleId: c.bundleId, tags: c.tags, displayID: c.mon?.screen.displayID,
                               homeDisplayID: c.oldmonname, isFloating: c.isFloating, isGlobal: c.isGlobal,
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
        // The groups in use, and those with members away.
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

    /// Written only when something in it changed (a comparison, no timer), off the main
    /// thread; the last write wins because the queue is serial. `final` (quit): written
    /// now, as it is, before anything moves.
    func save(_ server: MangoServer, final: Bool = false) {
        guard server.started, let url = layoutURL, !session.isEmpty else { return }
        if final {
            let now = currentLayout(server)
            queue.sync { Self.write(now, to: url) }
            return
        }
        // Saved windows not found yet are kept while the window server has them.
        if departed.hasSavedEntries { departed.dropSaved(keeping: server.system.allWindowIDs()) }
        let now = currentLayout(server)
        guard now != lastSaved else { return }
        lastSaved = now
        queue.async { Self.write(now, to: url) }
    }

    nonisolated private static func write(_ layout: SavedLayout, to url: URL) {
        do { try layout.write(to: url) } catch { Log.error("cannot write \(url.path): \(error.localizedDescription)") }
    }

    /// At start, before the first scan: the saved windows become departed ones (restored
    /// as each is found), and each display shows the tags it showed, in the layouts they
    /// had: a restart keeps what a reload of the config keeps.
    func restore(_ server: MangoServer) {
        if session.isEmpty { Log.info("no window server session id: the layout is not kept across restarts") }
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
                // As a reload does (mango parse_tagrule): a tag_rule whose layout changed since
                // gives its layout; otherwise the layout in use stays.
                if p.configLayout.name == (t.configuredLayout ?? LayoutKind.tile.name), let layout = LayoutKind(name: t.layout) {
                    p.layout = layout
                }
            }
        }
        lastSaved = saved
        Log.info("restoring \(saved.windows.count) window(s) from \(url.path)")
    }
}
