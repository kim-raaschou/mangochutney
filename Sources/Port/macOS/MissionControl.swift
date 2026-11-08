import AppKit
import ApplicationServices
import Mango

@MainActor
public final class MissionControl {
    public private(set) var isActive = false
    public var onExit: (() -> Void)?
    private var observer: AXObserver?
    private var dock: AXUIElement?
    private var launchObserver: NSObjectProtocol?
    private var inputMonitor: Any?

    private static let dockBundleId = "com.apple.dock"
    private static let notifications = ["AXExposeShowAllWindows", "AXExposeShowFrontWindows",
                                        "AXExposeShowDesktop", "AXExposeExit"]

    public init() {}

    public func start() {
        observeDock()
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
