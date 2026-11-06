import AppKit
import ApplicationServices
import Mango

/// Whether Mission Control (or App Exposé, Show Desktop) is up, from the Dock's own
/// Accessibility notifications, as yabai does (`mission_control.c`). While it is up the
/// Dock moves every window, hidden ones included, and apps report those moves: they are
/// not the user's, so the engine ignores them.
@MainActor
public final class MissionControl {
    public private(set) var isActive = false
    /// Called when Mission Control closes.
    public var onExit: (() -> Void)?
    private var observer: AXObserver?
    private var dock: AXUIElement?
    private var launchObserver: NSObjectProtocol?
    /// While it is up: the next click or key ends it for us if its exit notice is lost.
    private var inputMonitor: Any?

    private static let dockBundleId = "com.apple.dock"
    private static let notifications = ["AXExposeShowAllWindows", "AXExposeShowFrontWindows",
                                        "AXExposeShowDesktop", "AXExposeExit"]

    public init() {}

    public func start() {
        observeDock()
        // `killall Dock` (or a Dock crash) starts a new Dock: observe that one.
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Self.dockBundleId else { return }
            MainActor.assumeIsolated { self?.observeDock() }
        }
    }

    private func observeDock() {
        stopObserving()
        set(active: false, because: "Dock started")
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.dockBundleId).first else { return }
        let pid = app.processIdentifier
        var obs: AXObserver?
        guard AXObserverCreate(pid, missionControlCallback, &obs) == .success, let obs else { return }
        let el = AX.appElement(pid: pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.notifications { AXObserverAddNotification(obs, el, n as CFString, refcon) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        dock = el
    }

    private func stopObserving() {
        guard let observer, let dock else { return }
        for n in Self.notifications { AXObserverRemoveNotification(observer, dock, n as CFString) }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = nil
        self.dock = nil
    }

    fileprivate func handle(_ notification: String) {
        set(active: notification != "AXExposeExit", because: notification)
    }

    private func set(active: Bool, because why: String) {
        guard active != isActive else { return }
        isActive = active
        wlrLog(.debug, active ? "Mission Control is up (\(why)); window moves are ignored" : "Mission Control closed (\(why))")
        if active {
            // A click or key closes Mission Control in any case; if the Dock's exit notice
            // never comes, this keeps window moves from being ignored for good. Presses, not
            // releases: the release of the key or click that opened it comes after this.
            // Not a Space change: opening Mission Control is reported as one.
            inputMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.set(active: false, because: "click or key") }
            }
        } else {
            if let m = inputMonitor { NSEvent.removeMonitor(m) }
            inputMonitor = nil
            onExit?()
        }
    }
}

private func missionControlCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
                                    _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let mc = Unmanaged<MissionControl>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    MainActor.assumeIsolated { mc.handle(name) }
}
