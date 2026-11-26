import AppKit
import Mango

/// What the port asks of macOS about other apps' windows, and does to them outside mango's writes:
/// whether a window is in macOS fullscreen or on the active Space, which window is under a point,
/// focus, raise, close, macOS fullscreen, and asking an app which window has the keys. The seam between
/// MacWindowSystem and macOS (Accessibility, the window server): MacNativeWindows in the app; the tests
/// give their own.
@MainActor
protocol NativeWindows: AnyObject {
    /// macOS's fullscreen for the window; nil where the app does not answer.
    func fullscreenNow(_ c: Client) -> Bool?
    /// Whether a window is on the active Space.
    func windowOnScreen(_ id: CGWindowID) -> Bool
    /// The window under a point (the window server's answer), nil for none of mango's.
    func surfaceAt(_ p: CGPoint) -> ClientID?
    /// The app is asked which of its windows has the keys; its answer comes as a focus report.
    func askFocus(_ c: Client)
    func sendNativeFocus(_ c: Client, raise: Bool)
    func sendNativeRaise(_ c: Client)
    func clientSendClose(_ c: Client)
    /// Port extension: chutney_fullscreen_tag. macOS's fullscreen set for the window; `done` says whether
    /// the app took it.
    func setNativeFullscreen(_ c: Client, _ fullscreen: Bool, _ done: @escaping @MainActor (Bool) -> Void)
    /// Port extension: chutney_fullscreen_tag. mango's own window on `m`'s desktop Space focused.
    func focusSpaceAnchor(_ m: Monitor)
}

/// macOS's answers, through Accessibility and the window server.
@MainActor
final class MacNativeWindows: NativeWindows {
    private unowned let mac: MacWindowSystem
    /// The window server's answer for a point, kept for the turn: mango asks twice for one motion.
    private var surfaceAtTurn: (p: CGPoint, id: ClientID?)?

    init(_ mac: MacWindowSystem) { self.mac = mac }

    func fullscreenNow(_ c: Client) -> Bool? { c.element.attribute("AXFullScreen") as Bool? }

    func windowOnScreen(_ id: CGWindowID) -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]] else { return false }
        return info.first?[kCGWindowIsOnscreen as String] as? Bool ?? false
    }

    func surfaceAt(_ p: CGPoint) -> ClientID? {
        if let k = surfaceAtTurn, k.p == p { return k.id }
        if surfaceAtTurn == nil {
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.surfaceAtTurn = nil } }
        }
        let id = CursorHider.windowAt(p)
        surfaceAtTurn = (p, id)
        return id
    }

    func askFocus(_ c: Client) { mac.watcher.requestFocusReport(pid: c.pid) }

    func sendNativeFocus(_ c: Client, raise: Bool) {
        NativeFocus.focus(windowID: c.windowID, pid: c.pid, element: c.element, raise: raise) { [weak mac] in mac?.restack() }
    }

    func sendNativeRaise(_ c: Client) { mac.writer(for: c.pid)?.raise(c.element) }

    func clientSendClose(_ c: Client) {
        let el = c.element, name = c.appName, id = c.windowID
        mac.writer(for: c.pid)?.async {
            if el.closeButton == nil { wlrLog(.debug, "\(name): window \(id) has no close button to press (element invalid?)") }
            el.close()
        }
    }

    func setNativeFullscreen(_ c: Client, _ fullscreen: Bool, _ done: @escaping @MainActor (Bool) -> Void) {
        guard let q = mac.writer(for: c.pid) else { done(false); return }
        q.async { [el = c.element] in
            var settable = DarwinBoolean(false)
            let ok = el.fullscreenButton != nil
                && AXUIElementIsAttributeSettable(el, "AXFullScreen" as CFString, &settable) == .success && settable.boolValue
                && el.setAttribute("AXFullScreen", fullscreen as CFBoolean) == .success
            DispatchQueue.main.async { MainActor.assumeIsolated { done(ok) } }
        }
    }

    func focusSpaceAnchor(_ m: Monitor) { FullscreenTag.focusSpaceAnchor(mac.server, m) }
}
