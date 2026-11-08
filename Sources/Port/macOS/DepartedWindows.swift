import CoreGraphics
import QuartzCore
import Mango

struct DepartedGroup: Codable, Equatable {
    var members: [CGWindowID]
    var focus: CGWindowID?
}

struct DepartedWindows {
    static let keepFor: CFTimeInterval = 3600
    private(set) var entries: [CGWindowID: DepartedWindow] = [:]
    var groups: [DepartedGroup] = []
    private var waveOrder: [CGWindowID]?

    mutating func orderSnapshot(leaving id: CGWindowID, order: [CGWindowID]) -> [CGWindowID] {
        if let w = waveOrder, w.contains(id) { return w }
        waveOrder = order
        return order
    }

    mutating func endWave() {
        waveOrder = nil
    }

    mutating func remember(_ id: CGWindowID, _ d: DepartedWindow) {
        prune(now: d.at)
        entries[id] = d
    }

    mutating func take(_ id: CGWindowID, now: CFTimeInterval = CACurrentMediaTime()) -> DepartedWindow? {
        prune(now: now)
        return entries.removeValue(forKey: id)
    }

    mutating func prune(now: CFTimeInterval) {
        entries = entries.filter { $0.value.fromSavedLayout || now - $0.value.at < Self.keepFor }
        pruneGroups()
    }

    mutating func pruneGroups() {
        groups.removeAll { g in !g.members.contains { entries[$0] != nil } }
    }

    mutating func rememberGroup(_ g: DepartedGroup) {
        guard g.members.count > 1 else { return }
        if let i = groups.firstIndex(where: { !Set($0.members).isDisjoint(with: g.members) }) {
            if g.members.count > groups[i].members.count { groups[i] = g }
        } else {
            groups.append(g)
        }
    }

    var hasSavedEntries: Bool { entries.values.contains { $0.fromSavedLayout } }

    mutating func dropSaved(keeping existing: Set<CGWindowID>) {
        entries = entries.filter { !$0.value.fromSavedLayout || existing.contains($0.key) }
        pruneGroups()
    }
}
