import AppKit
import Mango

enum FocusAppRule: Equatable {
    case launch
    case focus(ClientID)

    static func decide(windows: [ClientID], current: ClientID?, recent: [ClientID]) -> FocusAppRule {
        switch (windows.count, current.flatMap { windows.firstIndex(of: $0) }) {
        case (0, _):
            return .launch
        case (1, _):
            return .focus(windows[0])
        case (2, let at?):
            return .focus(windows[1 - at])
        case (_, nil):
            return .focus(recent.first(where: windows.contains) ?? windows[0])
        case (_, let at?):
            return .focus(recent.first { windows.contains($0) && $0 != windows[at] } ?? windows[(at + 1) % windows.count])
        }
    }
}

extension MangoServer {
    var focusHistory: [ClientID] { (system as? MacWindowSystem)?.focusHistory ?? [] }

    func focusApp(_ app: String, command: String) {
        let key = app.lowercased()
        if overviewState != nil { leaveOverview(select: nil) }
        let windows = appWindowsInGridOrder(key)
        let rule = FocusAppRule.decide(windows: windows.map(\.id), current: focused?.id, recent: focusHistory)
        switch rule {
        case .launch:
            Spawn.run(command.isEmpty ? "open -b '\(app.replacingOccurrences(of: "'", with: ""))'" : command)
        case .focus(let id):
            if let c = clientByIdAll(id) { clientActive(c) }
        }
    }

    func appWindowsInGridOrder(_ key: String) -> [Client] {
        let position = Dictionary(clients.enumerated().map { ($1.id, $0) }, uniquingKeysWith: min)
        let monitorIndex = { (c: Client) in self.monitors.firstIndex { $0 === c.mon } ?? Int.max }
        return clientsAll
            .filter { c in
                !c.isMinimized && c.tags & TagMask.special == 0
                    && (c.appid.lowercased() == key || c.appName.lowercased() == key)
            }
            .sorted { a, b in
                let ka = (TagMask.getTagsFirstTagNum(a.tags) ?? Int.max, monitorIndex(a), position[a.id] ?? Int.max)
                let kb = (TagMask.getTagsFirstTagNum(b.tags) ?? Int.max, monitorIndex(b), position[b.id] ?? Int.max)
                return ka < kb
            }
    }
}
