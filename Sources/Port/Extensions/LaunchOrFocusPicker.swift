import CoreGraphics
import Mango

/// Port extension: not in mango. chutney_launch_or_focus's picture of the app's windows, in the
/// switcher's panel, where the key's choice is not given: two windows seen from another app, or
/// three or more. The key again or an arrow moves, Return or a click goes, Esc, any other key or a
/// click outside closes, a right click closes the window clicked and the picture. The
/// highlighted window's title and app stand in mango's title message bar under it, as in mango's switcher.
@MainActor
final class LaunchOrFocusPicker {
    static let shared = LaunchOrFocusPicker()

    private(set) var app: String?
    private(set) var windows: [ClientID] = []
    private(set) var index = 0
    private var panel: SwitcherPanel?
    private var panelFrame: CGRect = .zero
    private var monitor: Monitor?
    private(set) var tileFrames: [ClientID: CGRect] = [:]

    var isOpen: Bool { app != nil }
    var highlighted: ClientID? { windows.indices.contains(index) ? windows[index] : nil }

    nonisolated static func shows(windows: [ClientID], current: ClientID?) -> Bool {
        windows.count >= 3 || (windows.count == 2 && !(current.map(windows.contains) ?? false))
    }

    func open(_ server: MangoServer, app: String, windows: [ClientID], start: ClientID) {
        close(server)
        self.app = app
        self.windows = windows
        monitor = server.selectedMonitor
        index = windows.firstIndex(of: start) ?? 0
        let opening = server.mac.router.lastKeyDown
        server.mac.router.publish { $0.launchOrFocusPicker = .some(opening) }
        draw(server)
    }

    func move(_ server: MangoServer, by step: Int) {
        guard !windows.isEmpty else { return }
        index = (index + step + windows.count) % windows.count
        panel?.highlight(tiles(server).tiles)
        showTitle(server)
    }

    func commit(_ server: MangoServer) {
        let id = highlighted
        close(server)
        if let c = id.flatMap({ server.clientByIdAll($0) }) { server.clientActive(c) }
    }

    func close(_ server: MangoServer) {
        panel?.close()
        if panel != nil, let monitor { server.titleMessageBarHide(monitor) }
        panel = nil
        monitor = nil
        tileFrames = [:]
        guard app != nil else { return }
        app = nil
        windows = []
        server.mac.router.publish { $0.launchOrFocusPicker = nil }
    }

    /// A click while it is open, its buttons as mango's switcher's: the left goes to the window clicked,
    /// the right closes it; then the picture closes, as it does on a click outside the windows.
    func click(_ server: MangoServer, at p: CGPoint, button: Int) {
        guard isOpen else { return }
        guard let id = tileFrames.first(where: { $0.value.contains(p) })?.key,
              let c = server.clientByIdAll(id) else { return close(server) }
        close(server)
        if button == 0 { server.clientActive(c) } else { server.system.clientSendClose(c) }
    }

    /// Return, keypad Enter, Esc, the arrows and Tab.
    nonisolated static let keys: Set<UInt16> = [36, 76, 53, 123, 124, 125, 126, 48]

    /// A key while it is open; any key not its own closes it (the key goes on as usual).
    func key(_ server: MangoServer, keyCode: UInt16, mods: Modifiers, opening: UInt16?) {
        guard isOpen else { return }
        switch keyCode {
        case 36, 76: commit(server)
        case 53: close(server)
        case 123, 126: move(server, by: -1)
        case 124, 125: move(server, by: 1)
        case 48: move(server, by: mods.contains(.shift) ? -1 : 1)
        case opening where mods.subtracting(.fn).isEmpty: move(server, by: 1)
        default: close(server)
        }
    }

    private func tiles(_ server: MangoServer) -> (layout: SwitcherLayout.Result, tiles: [SwitcherPanel.Tile]) {
        let clients = windows.compactMap { server.clientByIdAll($0) }
        let monitor = server.selectedMonitor.screen.frame
        let layout = SwitcherLayout.switcherLayout(sizes: clients.map(\.frame.size), monitor: monitor)
        let tiles = clients.enumerated().map { i, c in
            SwitcherPanel.Tile(id: c.id, frame: layout.tiles[i], size: c.frame.size, pid: c.pid, highlighted: c.id == highlighted)
        }
        return (layout, tiles)
    }

    private func draw(_ server: MangoServer) {
        let (layout, tiles) = tiles(server)
        guard !tiles.isEmpty else { return close(server) }
        panelFrame = layout.panel
        tileFrames = Dictionary(uniqueKeysWithValues: tiles.map { ($0.id, $0.frame) })
        guard server.drawsOverlays else { return }
        let style = SwitcherPanel.Style(focus: server.config.focuscolor, border: server.config.bordercolor,
                                        macOS: server.config.chutneyMacOSAppearance)
        panel = SwitcherPanel(panel: layout.panel, tiles: tiles, style: style, scale: CGFloat(server.selectedMonitor.screen.scale))
        showTitle(server)
    }

    /// As mango's switcher_title_message_bar_geometry: the bar under the panel, for the highlighted window.
    func titleMessageBarGeometry(_ server: MangoServer, _ m: Monitor) -> (client: Client, box: CGRect)? {
        guard panel != nil, monitor === m, let c = highlighted.flatMap({ server.clientByIdAll($0) }) else { return nil }
        return (c, CGRect(x: panelFrame.minX, y: panelFrame.maxY + CGFloat(server.config.titleMessageBarGap),
                          width: panelFrame.width, height: CGFloat(server.config.titleMessageBarHeight)))
    }

    private func showTitle(_ server: MangoServer) {
        if let monitor { server.titleMessageBarUpdate(monitor) }
    }
}
