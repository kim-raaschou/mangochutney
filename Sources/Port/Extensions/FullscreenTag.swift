import AppKit
import CoreGraphics
import Mango

/// Port extension: not in mango. chutney_fullscreen_tag: as macOS gives a window in fullscreen its own
/// Space, mango gives it its own tag. The tags F1–F12 lie above mango's tags (tag_num) and below the
/// special tag. A window mango manages that goes into macOS fullscreen moves alone to the first free F tag
/// on its monitor, and that tag is viewed; the tag it left closes up. While an F tag is viewed the other
/// view of the monitor is the desktop's, and the desktop's windows stay where they are. Into its Space,
/// its F tag is viewed; out of it, the desktop's view, and a tag with no window to focus takes macOS back
/// to the desktop by mango's own window there. An F tag holds its window alone: mango's keys used from it
/// (tag, toggletag, toggleview) change the window's own tags, not the F tag. Out of fullscreen it is back
/// on its own tags, in its place. With no free F tag it is out of the layout as without the key.
@MainActor
enum FullscreenTag {
    /// Where a window on an F tag came from, and its F tag.
    struct Home: Equatable {
        var tags: UInt32
        var bit: UInt32
    }

    /// What the extension keeps: the windows on F tags, the displays an F tag was viewed on when mango
    /// last said what it shows, and mango's own window on each display's desktop.
    struct State {
        var homes: [ClientID: Home] = [:]
        var viewed: Set<CGDirectDisplayID> = []
        var anchors: [CGDirectDisplayID: SpaceAnchorWindow] = [:]
    }

    static let count = 12

    static func isOn(_ server: MangoServer) -> Bool { server.config.chutneyFullscreenTag }

    /// The F tags' bits: above tag_num, below the special tag.
    static func mask(_ config: Config) -> UInt32 {
        let n = max(0, min(count, 31 - config.tagNum))
        return n == 0 ? 0 : ((UInt32(1) << UInt32(n)) - 1) << UInt32(config.tagNum)
    }

    static func bits(_ config: Config) -> [UInt32] {
        let m = mask(config)
        return (0..<31).map { UInt32(1) << UInt32($0) }.filter { m & $0 != 0 }
    }

    /// "F1" for the first F tag's bit.
    static func name(_ bit: UInt32, _ config: Config) -> String { "F\(bit.trailingZeroBitCount - config.tagNum + 1)" }

    static func isFullscreenView(_ m: Monitor, _ config: Config) -> Bool {
        config.chutneyFullscreenTag && m.tagset[m.seltags] & mask(config) != 0
    }

    /// The desktop's view of `m`: the view, or while an F tag is viewed the other one; tag 1 where neither is.
    static func desktopView(_ m: Monitor, _ config: Config) -> UInt32 {
        let f = mask(config)
        let now = m.tagset[m.seltags] & ~f, other = m.tagset[m.seltags ^ 1] & ~f
        return now != 0 ? now : other != 0 ? other : 1
    }

    /// mango keeps a global window on every view's tags (arrange): the F tag's rule is not for it.
    static func isglobal(_ c: Client) -> Bool { c.isglobal || c.isunglobal }

    /// The window on F tag `bit` of `m`.
    static func window(_ server: MangoServer, on m: Monitor, _ bit: UInt32) -> Client? {
        server.mac.fullscreenTag.homes.first { $0.value.bit == bit && server.clientByIdAll($0.key)?.mon === m }
            .flatMap { server.clientByIdAll($0.key) }
    }

    // MARK: in and out

    /// A window mapped (`map`) while macOS has it in fullscreen (`onFTag`): nothing is written to it, and
    /// once mapped it is on its F tag, or out of the layout without a free one.
    static func mapInFullscreen(_ server: MangoServer, _ c: Client, _ onFTag: Bool, map: () -> Void) {
        if onFTag { c.nativeFullscreen = true }
        map()
        guard onFTag, server.clientByIdAll(c.id) === c else { return }
        c.nativeFullscreen = false
        if !enter(server, c, discovered: true) { server.mac.goAway(c, .fullscreen) }
    }

    /// The first F tag on `m` with no window but `c`'s.
    static func freeBit(_ server: MangoServer, _ c: Client, _ m: Monitor) -> UInt32? {
        let used = server.clientsAll.filter { $0 !== c && $0.mon === m }.reduce(UInt32(0)) { $0 | $1.tags }
        return bits(server.config).first { used & $0 == 0 }
    }

    static func enter(_ server: MangoServer, _ c: Client, discovered: Bool = false) -> Bool {
        guard isOn(server), let m = c.mon, let bit = freeBit(server, c, m) else { return false }
        if server.selectedMonitor?.isoverview == true { _ = server.dispatch(Dispatch(name: "toggleoverview")) }
        let mac = server.mac
        let own = c.tags & ~mask(server.config)
        mac.fullscreenTag.homes[c.id] = Home(tags: own != 0 ? own : desktopView(m, server.config), bit: bit)
        c.nativeFullscreen = true
        mac.forgetPlacement(c)
        mac.animator.cancel(c.id)
        c.tags = bit
        c.scheduledFullscreen = true
        c.fullscreenPending = false
        wlrLog(.info, "chutney_fullscreen_tag: \(c.appName) window \(c.id) is in macOS fullscreen, on \(name(bit, server.config))")
        if discovered && !mac.windowOnScreen(c.id) {
            server.arrange(m, .none)
            server.printstatus(.arrangge)
        } else {
            view(server, m, bit)
        }
        // mango's fullscreen, as a Wayland app's request (handle_client_request_fullscreen) gives it; by mango's
        // togglefullscreen, which also takes it out of a scratchpad.
        if !c.isfullscreen { _ = server.dispatch(Dispatch(name: "togglefullscreen"), target: c, rescan: false) }
        return true
    }

    static func leave(_ server: MangoServer, _ c: Client) {
        if server.selectedMonitor?.isoverview == true { _ = server.dispatch(Dispatch(name: "toggleoverview")) }
        c.scheduledFullscreen = false
        c.fullscreenPending = false
        // Out of mango's fullscreen too, while macOS still places it (as in enter).
        if c.isfullscreen { _ = server.dispatch(Dispatch(name: "togglefullscreen"), target: c, rescan: false) }
        c.nativeFullscreen = false
        server.mac.forgetPlacement(c)
        guard let home = server.mac.fullscreenTag.homes.removeValue(forKey: c.id) else { return }
        c.tags = home.tags
        wlrLog(.info, "chutney_fullscreen_tag: \(c.appName) window \(c.id) is out of macOS fullscreen, back on its tag")
        guard let m = c.mon else { return }
        if m.tagset[m.seltags] & home.bit != 0 {
            let desktop = m.tagset[m.seltags ^ 1]
            server.clientViewOnMonitor(c.tags, on: m)
            m.tagset[m.seltags ^ 1] = desktop & ~mask(server.config) != 0 ? desktop : m.tagset[m.seltags]
            server.clientFocus(c, true)
        } else {
            server.arrange(m, .none)
            server.printstatus(.arrangge)
        }
    }

    /// The window leaves mango while in fullscreen (closed, hidden, its app quit): it is remembered on its
    /// own tags; its F tag goes when mango next says what it shows.
    static func unmapped(_ server: MangoServer, _ c: Client) {
        if c.nativeFullscreen || c.scheduledFullscreen { c.isfullscreen = false }
        c.scheduledFullscreen = false
        c.fullscreenPending = false
        guard c.nativeFullscreen else { return }
        c.nativeFullscreen = false
        guard let home = server.mac.fullscreenTag.homes.removeValue(forKey: c.id) else { return }
        c.tags = home.tags
    }

    /// mango tells the app it is fullscreen or not (client_notify_fullscreen): macOS's own fullscreen, which
    /// takes it to its F tag. Not what the app was last told, nor a window with no F tag to go to or out of
    /// view; where the app cannot, it stays in mango's fullscreen.
    static func notify(_ server: MangoServer, _ c: Client, _ fullscreen: Bool) {
        guard isOn(server), c.scheduledFullscreen != fullscreen, let m = c.mon else { return }
        if fullscreen, c.parked || freeBit(server, c, m) == nil { return }
        c.scheduledFullscreen = fullscreen
        c.fullscreenPending = true
        server.mac.forgetPlacement(c)
        server.mac.animator.cancel(c.id)
        server.mac.setNativeFullscreen(c, fullscreen) { took in
            guard !took, c.scheduledFullscreen == fullscreen, server.clientByIdAll(c.id) === c else { return }
            wlrLog(.info, "chutney_fullscreen_tag: \(c.appName) window \(c.id) cannot go \(fullscreen ? "into" : "out of") macOS fullscreen")
            c.scheduledFullscreen = c.nativeFullscreen
            c.fullscreenPending = false
            if let m = c.mon { server.arrange(m) }
        }
    }

    /// After a Space change macOS has the window out of fullscreen, though it was told to go in (or in and
    /// out): it never went, or was taken out on the way. Out of mango's fullscreen too, back in its place.
    static func notTaken(_ server: MangoServer, _ c: Client) {
        c.scheduledFullscreen = false
        c.fullscreenPending = false
        if c.isfullscreen {
            _ = server.dispatch(Dispatch(name: "togglefullscreen"), target: c, rescan: false)
        } else if let m = c.mon {
            server.arrange(m)
        }
    }

    // MARK: the view

    /// The F tag `bit` viewed on `m`, its window focused: from the desktop's view mango's other view keeps
    /// it; from another F tag, it is replaced. Whether `m` has a window there.
    @discardableResult
    static func view(_ server: MangoServer, _ m: Monitor, _ bit: UInt32) -> Bool {
        guard let c = window(server, on: m, bit) else { return false }
        if m.tagset[m.seltags] != bit {
            if !isFullscreenView(m, server.config) { m.seltags ^= 1 }
            m.tagset[m.seltags] = bit
            let before = m.pertag.curtag
            m.pertag.curtag = UInt32(bit.trailingZeroBitCount + 1)
            if before != m.pertag.curtag { m.pertag.prevtag = before }
            server.arrange(m, .none)
        }
        server.clientFocus(c, true)
        server.printstatus(.arrangge)
        return true
    }

    /// Back to the desktop's view, mango's other view, as macOS went there: mango moves no focus, which
    /// could take macOS to another Space, and its own window is not taken.
    static func viewDesktop(_ server: MangoServer, _ m: Monitor) {
        guard isFullscreenView(m, server.config), !m.isoverview else { return }
        server.mac.fullscreenTag.viewed.remove(m.screen.displayID)
        server.clientViewOnMonitor(desktopView(m, server.config), on: m, changeFocus: false)
    }

    /// The active Space changed: on each monitor, the F tag of the window in fullscreen on screen (the
    /// focused one of two side by side), else the desktop's view.
    static func followSpace(_ server: MangoServer) {
        guard !server.monitors.contains(where: \.isoverview) else { return }
        let mac = server.mac
        for m in server.monitors {
            let shown = mac.fullscreenTag.homes.compactMap { id, home -> (Client, UInt32)? in
                guard let c = server.clientByIdAll(id), c.mon === m, mac.windowOnScreen(id) else { return nil }
                return (c, home.bit)
            }
            if let (_, bit) = shown.first(where: { $0.0 === server.focused }) ?? shown.first {
                if m.tagset[m.seltags] & bit == 0 { view(server, m, bit) }
            } else {
                viewDesktop(server, m)
            }
        }
    }

    /// mango said what it shows. An F tag holds its window alone: mango's keys used from it are folded
    /// back. An F tag left empty is left for the desktop's view. A view left from an F tag by mango's keys
    /// to tags with no window to focus takes macOS back to the desktop by mango's own window there.
    static func statusChanged(_ server: MangoServer) {
        guard isOn(server) || !server.mac.fullscreenTag.homes.isEmpty else { return }
        let mac = server.mac
        let f = mask(server.config)
        var changed: [Monitor] = []
        var follow: [(Monitor, UInt32)] = []
        for (id, home) in mac.fullscreenTag.homes {
            guard let c = server.clientByIdAll(id), !isglobal(c), c.tags != home.bit else { continue }
            // mango's tag replaces its tags, toggletag toggles them (with the F bit kept): its own tags.
            let own = c.tags & ~f
            let tags = c.tags & home.bit != 0 ? home.tags ^ own : own
            if tags != 0 { mac.fullscreenTag.homes[id]?.tags = tags }
            c.tags = home.bit
            guard let m = c.mon else { continue }
            changed.append(m)
            // mango's tag follows the window to its tags: it is on its F tag still.
            if server.focused === c, m.tagset[m.seltags] & home.bit == 0 { follow.append((m, home.bit)) }
        }
        for c in server.clientsAll where !c.nativeFullscreen && !isglobal(c) && c.tags & f != 0 {
            let own = c.tags & ~f
            c.tags = own != 0 ? own : (c.mon.map { desktopView($0, server.config) } ?? 1)
            if let m = c.mon { changed.append(m) }
        }
        for m in server.monitors {
            let other = m.tagset[m.seltags ^ 1] & f
            if other != 0, window(server, on: m, UInt32(1) << UInt32(other.trailingZeroBitCount)) == nil {
                m.tagset[m.seltags ^ 1] = m.tagset[m.seltags]   // no F tag left empty to go back to
            }
        }
        for m in server.monitors where isFullscreenView(m, server.config) {
            let view = m.tagset[m.seltags]
            if view & ~f != 0 {
                m.tagset[m.seltags] = UInt32(1) << UInt32((view & f).trailingZeroBitCount)
                changed.append(m)
            }
        }
        if let (m, bit) = follow.first {
            view(server, m, bit)
            return
        }
        if !changed.isEmpty {
            for m in server.monitors where changed.contains(where: { $0 === m }) { server.arrange(m, .none) }
            server.printstatus(.arrangge)
            return
        }
        for m in server.monitors where !m.isoverview {
            let display = m.screen.displayID
            let fullscreen = isFullscreenView(m, server.config)
            if fullscreen, window(server, on: m, m.tagset[m.seltags]) == nil {
                viewDesktop(server, m)   // says again what mango shows, for the other monitors too
                return
            }
            let wasFullscreen = mac.fullscreenTag.viewed.contains(display)
            if fullscreen { mac.fullscreenTag.viewed.insert(display) } else { mac.fullscreenTag.viewed.remove(display) }
            if wasFullscreen && !fullscreen && server.selectedMonitor === m && server.focused?.mon !== m {
                mac.focusSpaceAnchor(m)
            }
        }
    }

    /// macOS focused a window in fullscreen whose F tag is not viewed (Cmd-Tab, the Dock, the other side
    /// of Split View): its F tag is, rather than mango's activation, which knows no tag above tag_num.
    static func focusedByMacOS(_ server: MangoServer, _ c: Client) {
        guard let m = c.mon, let home = server.mac.fullscreenTag.homes[c.id] else { return }
        view(server, m, home.bit)
    }

    // MARK: what is saved

    /// The tags a window is saved on: its own, not its F tag.
    static func savedTags(_ server: MangoServer, _ c: Client) -> UInt32 { server.mac.fullscreenTag.homes[c.id]?.tags ?? c.tags }

    /// The views a monitor is saved with: the desktop's for an F tag.
    static func savedView(_ server: MangoServer, _ m: Monitor) -> (now: UInt32, before: UInt32) {
        let f = mask(server.config)
        let now = m.tagset[m.seltags], other = m.tagset[m.seltags ^ 1]
        guard (now | other) & f != 0 else { return (now, other) }
        let desktop = desktopView(m, server.config)
        return (desktop, other & f == 0 ? other : desktop)
    }

    // MARK: the menu bar and keys

    /// The F tags on `m`, each with its window's app.
    static func menuBarTags(_ server: MangoServer, _ m: Monitor) -> [MenuBarTag] {
        bits(server.config).compactMap { bit in
            guard let c = window(server, on: m, bit) else { return nil }
            return MenuBarTag(number: bit.trailingZeroBitCount + 1, active: m.tagset[m.seltags] & bit != 0,
                              app: c.pid, label: name(bit, server.config))
        }
    }

    /// The dispatcher chutney_view_fullscreen,N: F tag N, on the selected monitor or else the first that
    /// has it; nothing where no window is in fullscreen there.
    static func viewDispatch(_ server: MangoServer, _ arg: String) -> String? {
        let bits = bits(server.config)
        guard let n = Int(arg.trimmingCharacters(in: .whitespaces)), (1...max(1, bits.count)).contains(n), n <= bits.count else {
            return "chutney_view_fullscreen: F tag 1–\(bits.count), not \(arg)"
        }
        let bit = bits[n - 1]
        let monitors = [server.selectedMonitor].compactMap { $0 } + server.monitors.filter { $0 !== server.selectedMonitor }
        guard let m = monitors.first(where: { window(server, on: $0, bit) != nil }) else { return nil }
        if m !== server.selectedMonitor { server.focusMonitor(m) }
        view(server, m, bit)
        return nil
    }

    /// A click on an F tag: its window focused, so macOS goes to its Space.
    static func viewTag(_ server: MangoServer, _ m: Monitor, tag: Int) {
        view(server, m, UInt32(1) << UInt32(tag - 1))
    }

    /// mango's own window on `m`'s desktop focused, so macOS leaves a fullscreen Space for the desktop.
    static func focusSpaceAnchor(_ server: MangoServer, _ m: Monitor) {
        let mac = server.mac
        let id = m.screen.displayID
        let w = mac.fullscreenTag.anchors[id] ?? SpaceAnchorWindow(on: m.screen.frame)
        mac.fullscreenTag.anchors[id] = w
        w.setFrameOrigin(SpaceAnchorWindow.origin(m.screen.frame))
        wlrLog(.debug, "chutney_fullscreen_tag: no window to focus on \(m.screen.name): mango's own, for the desktop")
        NativeFocus.focusOwn(windowID: CGWindowID(w.windowNumber))
    }
}

/// Port extension: chutney_fullscreen_tag. mango's own window on a monitor's desktop Space, nearly
/// transparent and out of the pointer's way: focused when a view has no window of its own to focus, so
/// macOS leaves a fullscreen Space for the desktop.
final class SpaceAnchorWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    /// Its place at `screen`'s bottom left corner, in AppKit's points.
    static func origin(_ screen: CGRect) -> NSPoint {
        let primary = NSScreen.screens.first?.frame.height ?? screen.maxY
        return NSPoint(x: screen.minX, y: primary - screen.maxY)
    }

    convenience init(on screen: CGRect) {
        self.init(contentRect: NSRect(origin: Self.origin(screen), size: NSSize(width: 1, height: 1)),
                  styleMask: .borderless, backing: .buffered, defer: false)
        // On every desktop Space, never in a fullscreen one: macOS goes to the desktop it last showed.
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenNone, .stationary]
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        alphaValue = 0.01
        ignoresMouseEvents = true
        hasShadow = false
        orderFront(nil)
    }
}
