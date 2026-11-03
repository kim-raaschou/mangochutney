import CoreGraphics
import QuartzCore
import Mango

/// Not in mango: a window group with a member away (sleep) or not found yet since a restart:
/// its members, head first, and the one in view. Built again as they come back.
struct DepartedGroup: Codable, Equatable {
    var members: [CGWindowID]
    var focus: CGWindowID?
}

/// Departed windows for an hour of awake time (CACurrentMediaTime stops during sleep,
/// so the night itself does not count).
struct DepartedWindows {
    static let keepFor: CFTimeInterval = 3600
    private(set) var entries: [CGWindowID: DepartedWindow] = [:]
    /// Groups whose members are away, until all are back (or none is kept any more).
    var groups: [DepartedGroup] = []
    /// The order when the first window of the current wave left. Windows leave in a wave
    /// (a sleep) until one appears or comes back: `endWave`.
    private var waveOrder: [CGWindowID]?

    /// Not in mango: windows that leave and come back.
    /// The order to remember for a window leaving now: the order when the first window of
    /// this wave left, so the last ones to leave still know all their neighbours.
    mutating func orderSnapshot(leaving id: CGWindowID, order: [CGWindowID]) -> [CGWindowID] {
        if let w = waveOrder, w.contains(id) { return w }
        waveOrder = order
        return order
    }

    /// Not in mango: windows that leave and come back.
    /// A window appeared or came back: the next one to leave starts a new wave.
    mutating func endWave() {
        waveOrder = nil
    }

    /// Not in mango: windows that leave and come back.
    mutating func remember(_ id: CGWindowID, _ d: DepartedWindow) {
        prune(now: d.at)
        entries[id] = d
    }

    /// Not in mango: windows that leave and come back.
    /// The window's state if it departed less than `keepFor` ago; forgotten after.
    mutating func take(_ id: CGWindowID, now: CFTimeInterval = CACurrentMediaTime()) -> DepartedWindow? {
        prune(now: now)
        return entries.removeValue(forKey: id)
    }

    /// Not in mango: windows that leave and come back.
    mutating func prune(now: CFTimeInterval) {
        entries = entries.filter { $0.value.fromSavedLayout || now - $0.value.at < Self.keepFor }
        pruneGroups()
    }

    /// Not in mango: a group with no member away any more is done.
    mutating func pruneGroups() {
        groups.removeAll { g in !g.members.contains { entries[$0] != nil } }
    }

    /// Not in mango: a group member leaves; its whole group is kept (once).
    mutating func rememberGroup(_ g: DepartedGroup) {
        guard g.members.count > 1 else { return }
        if let i = groups.firstIndex(where: { !Set($0.members).isDisjoint(with: g.members) }) {
            if g.members.count > groups[i].members.count { groups[i] = g }
        } else {
            groups.append(g)
        }
    }

    var hasSavedEntries: Bool { entries.values.contains { $0.fromSavedLayout } }

    /// Not in mango: windows that leave and come back.
    /// Forget saved entries whose window no longer exists.
    mutating func dropSaved(keeping existing: Set<CGWindowID>) {
        entries = entries.filter { !$0.value.fromSavedLayout || existing.contains($0.key) }
        pruneGroups()
    }
}
