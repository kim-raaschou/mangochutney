import AppKit
import Mango

/// mango's focus and raises as macOS gets them: gathered for the turn and sent as one native call, held
/// while the port's own panels are up; and the port's overlays (borders, bars) stacked with the windows.
extension MacWindowSystem {
    /// The port's own focus: back to mango's window after the port's panel.
    func focus(_ c: Client, raise: Bool) {
        seatFocus = c
        if raise { self.raise(c) }
        focusLater(c)
    }

    var keyboardFocusedSurface: Client? {
        seatFocus.flatMap { server.clientByWindowID($0.windowID) === $0 ? $0 : nil }
    }

    func clientNotifyEnter(_ c: Client) {
        seatFocus = c
        if macOSFocused == c.windowID { return }
        focusLater(c)
    }

    /// macOS activates a window as it gives it the keyboard (clientNotifyEnter).
    func clientActivateSurface(_ c: Client, _ activated: Bool) {}

    /// The seat only: macOS keeps its focus.
    func keyboardNotifyClearFocus() { seatFocus = nil }

    /// A scene raise: done with the turn's focus, as one native call where it is the focused window.
    /// Whether it is parked is read at the flush, after the turn's arrange has placed it.
    func raise(_ c: Client) {
        if holdingWrites { return }
        pendingRaises.removeAll { $0 === c }
        pendingRaises.append(c)
        scheduleFlush()
    }

    private func focusLater(_ c: Client) {
        if holdFocus || panels.overviewShown || !scenePanels.isEmpty { heldFocus = c; return }
        pendingFocus = c
        scheduleFlush()
    }

    func releaseHeldFocus() {
        guard !holdFocus, !panels.overviewShown, scenePanels.isEmpty, let c = heldFocus else { return }
        heldFocus = nil
        if server.clientByWindowID(c.windowID) === c { focusLater(c) }
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.flushFocus() } }
    }

    private func flushFocus() {
        flushScheduled = false
        let raises = pendingRaises, f = pendingFocus
        pendingRaises = []
        pendingFocus = nil
        let shown = raises.filter { server.clientByWindowID($0.windowID) === $0 && !$0.parked && !server.clientIsParked($0) }
        for r in shown where r !== f { sendNativeRaise(r) }
        guard let c = f, Self.stillFocused(c, in: server) else { return }
        let lift = Self.lifts(c, raise: shown.contains { $0 === c }, in: server)
        wlrLog(.debug, "\(c.appName): mango focuses window \(c.windowID)\(lift ? "" : " without lifting it")")
        sendNativeFocus(c, raise: lift)
    }

    func sendNativeFocus(_ c: Client, raise: Bool) { native.sendNativeFocus(c, raise: raise) }

    func sendNativeRaise(_ c: Client) { native.sendNativeRaise(c) }

    static func stillFocused(_ c: Client, in server: MangoServer) -> Bool {
        server.clientByWindowID(c.windowID) === c && server.focused === c
    }

    static func lifts(_ c: Client, raise: Bool, in server: MangoServer) -> Bool {
        guard raise, let m = c.mon else { return false }
        let layer = server.clientTargetLayer(c)
        return !server.clientsAll.contains { d in
            d !== c && d.mon === m && VISIBLEON(d, m) && !d.parked
                && server.clientTargetLayer(d) > layer && d.frame.intersects(c.frame)
        }
    }

    func restack() { restack(pid: server.focused?.pid) }

    func restack(pid: pid_t?) {
        guard let pid else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.frameClock.whenIdle { [weak self] in self?.restackNow(pid) } }
        }
    }

    /// The window server's stacking is asked for off the main thread (it waits for the window server's
    /// pending transactions); the overlays are ordered on the main thread with what it answered.
    private func restackNow(_ pid: pid_t, reserve: Bool = true) {
        let onScreenOrder = native.onScreenOrder
        Self.stackingQueue.async { [weak self] in
            let order = onScreenOrder()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.restackApply(pid, order, reserve: reserve) }
            }
        }
    }

    private static let stackingQueue = DispatchQueue(label: "mango.stacking", qos: .userInteractive)

    private func restackApply(_ pid: pid_t, _ order: [CGWindowID], reserve: Bool) {
        let ids = Set(server.clientsAll.filter { $0.pid == pid }.map(\.windowID))
        let at = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        let ours = Set(((NSApp as NSApplication?)?.windows ?? []).map { CGWindowID(truncatingIfNeeded: $0.windowNumber) })
        func inPlace(_ overlay: CGWindowID, _ target: CGWindowID, above: Bool) -> Bool {
            guard let o = at[overlay], let t = at[target], above ? o < t : o > t else { return false }
            return order[(min(o, t) + 1)..<max(o, t)].allSatisfy(ours.contains)
        }
        borders.restack(ids) { inPlace($0, $1, above: true) }
        tabBars.restack(ids) { inPlace($0, $1, above: false) }
        groupBars.restack(ids) { inPlace($0, $1, above: false) }
        for m in server.monitors where isSpecialActive(m) { server.specialUpdateDim(m) }
        guard reserve else { return }
        restackGeneration &+= 1
        let gen = restackGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.restackGeneration == gen else { return }
                self.frameClock.whenIdle { [weak self] in self?.restackNow(pid, reserve: false) }
            }
        }
    }
}
