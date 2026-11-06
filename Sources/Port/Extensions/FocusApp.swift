import AppKit
import Mango

/// `chutney_focus_app,<bundle id or app name>[,<command>]`, a port extension: one key per app,
/// with AeroControl's rules (its `Visit.open` and `Strip.opened`). The app's windows are
/// looked for on every tag and monitor.
enum FocusAppRule: Equatable {
    case launch
    case focus(ClientID)

    /// `windows`: the app's windows in grid order (tag by tag, each tag in layout order).
    /// `recent`: focus history, most recent first.
    static func decide(windows: [ClientID], current: ClientID?, recent: [ClientID]) -> FocusAppRule {
        switch (windows.count, current.flatMap { windows.firstIndex(of: $0) }) {
        case (0, _):
            return .launch                                           // none: start it
        case (1, _):
            return .focus(windows[0])                                // one: focus it
        case (2, let at?):
            return .focus(windows[1 - at])                           // two, in one: the other
        case (_, nil):
            // From another app: the one used last, as ⌘Tab does.
            return .focus(recent.first(where: windows.contains) ?? windows[0])
        case (_, let at?):
            // Three or more, in one: the one used last other than this one, or else the next.
            return .focus(recent.first { windows.contains($0) && $0 != windows[at] } ?? windows[(at + 1) % windows.count])
        }
    }
}

extension MangoServer {
    /// The windows that have had the focus, most recent first (PortHooks.clientFocused).
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

    /// AeroControl's grid order: tag by tag (monitor by monitor within a tag), each in
    /// layout order.
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
