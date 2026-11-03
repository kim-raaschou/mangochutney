import CoreGraphics
import Mango

/// Port extension: not in mango. What the menu bar item (`chutney_menu_bar`) shows. mango has
/// no bar of its own; a bar such as waybar shows each output its own tags. A menu bar item is
/// one, and macOS draws a copy of it on every display, so it shows every monitor: its tags and
/// layout in a group, in the order the displays stand, the selected monitor's in full and the
/// others dimmed (as AeroSpace and rift do).
public struct MenuBarTag: Equatable {
    /// 0 is the special tag.
    public var number: Int
    /// In view (filled) or not (outlined).
    public var active: Bool

    public init(number: Int, active: Bool) { self.number = number; self.active = active }
}

public struct MenuBarMonitor: Equatable {
    public var tags: [MenuBarTag]
    public var layout: LayoutKind
    /// The selected monitor: drawn in full.
    public var selected: Bool
}

public enum MenuBarStatus {
    /// Every monitor, left to right (top to bottom where they stand above each other).
    @MainActor
    public static func monitors(_ server: MangoServer) -> [MenuBarMonitor] {
        server.monitors
            .sorted { ($0.screen.frame.minX, $0.screen.frame.minY) < ($1.screen.frame.minX, $1.screen.frame.minY) }
            .map { MenuBarMonitor(tags: tags(server, $0), layout: $0.layout, selected: $0 === server.selectedMonitor) }
    }

    /// A tag shows when it is in view, has windows, or its tag_rule says no_hide (mango).
    @MainActor
    static func tags(_ server: MangoServer, _ m: Monitor) -> [MenuBarTag] {
        var tags: [MenuBarTag] = []
        for i in 1...server.config.tagNum {
            let bit: UInt32 = 1 << UInt32(i - 1)
            let active = m.tagset[m.seltags] & bit != 0
            let occupied = server.clientsAll.contains { $0.mon === m && $0.tags & bit != 0 && !$0.isMinimized }
            if active || occupied || m.pertag[i].noHide { tags.append(MenuBarTag(number: i, active: active)) }
        }
        if m.tagset[m.seltags] & (1 << 31) != 0 { tags.append(MenuBarTag(number: 0, active: true)) }
        return tags
    }
}
