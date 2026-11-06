import AppKit
import ApplicationServices
import MangoPrivate
import Mango

public struct DiscoveredWindow {
    public var id: CGWindowID
    public var pid: pid_t
    public var element: AXUIElement
    public var bundleId: String
    public var appName: String
    public var title: String
    public var subrole: String
    /// AeroSpace's dialog (`AxUiElementWindowType`): mango opens it floating.
    public var isDialog: Bool
    public var frame: CGRect
    public var isMinimized: Bool
    public var isFullscreen: Bool
    public var isAppHidden: Bool
    /// Found by the first scan of an app that was already running when mango
    /// started (placed by position, no open animation, no focus change).
    public var isInitial: Bool = false
}

@MainActor
public protocol AppWatcherDelegate: AnyObject {
    func windowDiscovered(_ w: DiscoveredWindow)
    func windowDestroyed(id: CGWindowID)
    /// A move/resize notification, with the frame read on the app's own thread.
    /// `isFullscreen` is only read for resizes.
    func windowGeometryChanged(id: CGWindowID, frame: CGRect, resized: Bool, isFullscreen: Bool?)
    func windowMinimized(id: CGWindowID, minimized: Bool)
    func windowTitleChanged(id: CGWindowID, title: String)
    func windowFocused(id: CGWindowID)
    func appActivated(pid: pid_t)
    func appHidden(pid: pid_t, hidden: Bool)
    /// A window whose AX element went invalid (around sleep) has a new element; the
    /// window itself never went away. `state` is what it has now: writes to the dead
    /// element went nowhere, and nothing was reported while it was dead.
    func windowReacquired(id: CGWindowID, element: AXUIElement, state: ReacquiredState)
    /// The app stopped answering Accessibility (`responding` false: a debugger paused it,
    /// or it is busy) or answers again.
    func appResponding(pid: pid_t, responding: Bool)
    func appTerminated(pid: pid_t)
    func screensChanged()
}

/// Events an `AppWorker` sends from its thread to the main thread.
enum AppEvent {
    case discovered([DiscoveredWindow])
    case destroyed(CGWindowID)
    case geometry(CGWindowID, CGRect, resized: Bool, fullscreen: Bool?)
    case minimized(CGWindowID, Bool)
    case title(CGWindowID, String)
    case focused(CGWindowID)
    case responding(Bool)
    case reacquired(CGWindowID, AXUIElement, ReacquiredState)
}

/// A reacquired window's frame and native state, read with its new element.
public struct ReacquiredState {
    public var frame: CGRect?
    /// nil: the window did not answer.
    public var minimized: Bool?
    public var fullscreen: Bool?
    public var appHidden: Bool
}

/// State the main thread publishes for the app threads (lock-protected).
final class WatcherShared: @unchecked Sendable {
    private let lock = NSLock()
    private var suppressUntil: [CGWindowID: TimeInterval] = [:]

    /// While mango itself moves a window (placement, animation, mouse grab) its
    /// move/resize notifications are not read back: mango already knows the
    /// target and `verifyFrame` reads the real frame once it settles.
    func suppress(_ id: CGWindowID, until t: TimeInterval) {
        lock.lock()
        // Entries of windows destroyed while suppressed are never read again: drop the
        // expired ones here so the map does not grow over a long session.
        if suppressUntil.count > 64 {
            let now = CACurrentMediaTime()
            suppressUntil = suppressUntil.filter { $0.value > now }
        }
        suppressUntil[id] = t
        lock.unlock()
    }

    func isSuppressed(_ id: CGWindowID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let t = suppressUntil[id] else { return false }
        if CACurrentMediaTime() < t { return true }
        suppressUntil.removeValue(forKey: id)
        return false
    }
}

/// One running app. Owns a dedicated thread (AeroSpace / rift design): the
/// AXObserver runs on it and every synchronous AX read happens there, so an app
/// that is slow or hung only blocks its own thread, never mango's main thread
/// or the keyboard. Writes go through `writeQueue` (also off the main thread).
public final class AppWorker: @unchecked Sendable {
    public let pid: pid_t
    public let nsApp: NSRunningApplication
    public let bundleId: String
    public let name: String
    public let ax: AXUIElement
    public let writeQueue: AXWriteQueue
    let thread: AXThread
    let shared: WatcherShared
    private let deliver: (AppEvent) -> Void
    private let initial: Bool

    // Confined to `thread`.
    private var observer: AXObserverBox?
    /// The app's windows and what a refresh decides about them (`WindowBook`).
    private var book = WindowBook<AXUIElement, DiscoveredWindow>()
    /// App-level notifications registered (they can fail while an app is still starting).
    private var appSubscribed = false
    private var scannedOnce = false
    private var unresponsive = false
    /// Until the app has answered once, its element waits as long as macOS does by
    /// default (as AeroSpace does): an app that is starting (VS Code, Brave) is busy for
    /// seconds, and nothing else asks again until the user does something. Only this
    /// app's thread waits, nothing else waits for it; once the app has answered,
    /// `AX.messagingTimeout` applies again so a hang later costs half a second.
    private static let firstContactTimeout: Float = 6
    private var answered = false
    private var startedAt: CFTimeInterval = 0

    // Refresh coalescing: at most one refresh waiting behind the one running,
    // so a hung app never accumulates a backlog.
    private let lock = NSLock()
    private var refreshQueued = false
    private var queuedRecheck = false

    // Move/resize coalescing: one main-thread hop for a burst of notifications.
    private var pendingGeometry: [CGWindowID: (CGRect, Bool, Bool?)] = [:]
    private var geometryScheduled = false

    init(nsApp: NSRunningApplication, shared: WatcherShared, initial: Bool,
         deliver: @escaping (AppEvent) -> Void) {
        pid = nsApp.processIdentifier
        self.nsApp = nsApp
        bundleId = nsApp.bundleIdentifier ?? ""
        name = nsApp.localizedName ?? ""
        ax = AX.appElement(pid: pid)
        AXUIElementSetMessagingTimeout(ax, Self.firstContactTimeout)
        writeQueue = AXWriteQueue(pid: pid)
        thread = AXThread(name: "mango.ax.\(pid) \(name)")
        self.shared = shared
        self.initial = initial
        self.deliver = deliver
    }

    func start() {
        startedAt = CACurrentMediaTime()
        thread.startAndWait()
        thread.perform { [self] in
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            observer = AXObserverBox(pid: pid, callback: workerAXCallback, refcon: refcon, runLoop: thread.runLoop)
            runRefresh(recheck: false)   // subscribes the app first
        }
    }

    /// On `thread`. Retried on every refresh until it succeeds (Electron and Java apps
    /// bring up accessibility late; without these the app's windows are only seen by rescans).
    private func subscribeApp() {
        guard !appSubscribed, let obs = observer else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // Stop at the first failure: an app that does not answer would make each
        // registration wait out the timeout in turn.
        for n in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                  kAXMainWindowChangedNotification, kAXApplicationActivatedNotification] {
            guard obs.add(ax, n, refcon: refcon) else { return }
        }
        appSubscribed = true
    }

    func stop() {
        thread.perform { [self] in observer = nil }
        thread.stop()
    }

    private func post(_ e: AppEvent) {
        DispatchQueue.main.async { [deliver] in deliver(e) }
    }

    // MARK: Refresh (window discovery)

    /// Callable from any thread.
    func requestRefresh(recheck: Bool) {
        lock.lock()
        if refreshQueued {
            queuedRecheck = queuedRecheck || recheck
            lock.unlock()
            return
        }
        refreshQueued = true
        queuedRecheck = recheck
        lock.unlock()
        thread.perform { [self] in
            lock.lock()
            let r = queuedRecheck
            refreshQueued = false
            lock.unlock()
            runRefresh(recheck: r)
        }
    }

    /// On `thread`. `recheck`: re-classify windows rejected earlier (Electron,
    /// Java and Qt create the AX window before its buttons/subrole are populated).
    /// `recheck` comes from a rescan on user interaction (bounded per window) or, as
    /// `notified`, from the app's own notifications (always re-checks).
    private func runRefresh(recheck: Bool, notified: Bool = false) {
        let isInitialScan = initial && !scannedOnce
        scannedOnce = true
        subscribeApp()
        let (err, value) = ax.attributeResult(kAXWindowsAttribute)
        if err == .cannotComplete {
            // Timed out: the app is busy or hung. Its windows are not gone; try again later.
            if !answered {
                // Still starting: it has no windows to keep, and it is not hung.
                return
            }
            if !unresponsive {
                wlrLog(.info, "\(name) is not responding; keeping its windows")
                post(.responding(false))
            }
            unresponsive = true
            return
        }
        if !answered {
            answered = true
            AXUIElementSetMessagingTimeout(ax, AX.messagingTimeout)
        }
        if unresponsive {
            wlrLog(.info, "\(name) is responding again")
            post(.responding(true))
        }
        unresponsive = false
        let listed = ((value as? [AXUIElement]) ?? []).compactMap { el in el.windowID.map { ($0, el) } }
        let out = book.refresh(listed: listed, recheck: recheck, notified: notified, answers: .init(
            subscribe: { [self] in subscribeWindow($0) },
            unsubscribe: { [self] in unsubscribeWindow($0) },
            isInvalid: { $0.attributeResult(kAXRoleAttribute).0 == .invalidUIElement },
            onScreen: { AppWorker.windowServerFrame($0) != nil },
            classify: { [self] el, id in
                guard var dw = classify(el, id: id) else { return nil }
                dw.isInitial = isInitialScan
                return dw
            }))
        for (id, el) in out.reacquired {
            post(.reacquired(id, el, ReacquiredState(frame: el.frame, minimized: Self.answeredBool(el, kAXMinimizedAttribute),
                                                     fullscreen: Self.answeredBool(el, "AXFullScreen"), appHidden: nsApp.isHidden)))
        }
        if !out.found.isEmpty { post(.discovered(out.found)) }
        for (id, why) in out.gone {
            switch why {
            case .elementInvalid: wlrLog(.debug, "\(name): window \(id) gone (no longer listed, element invalid)")
            case .notOnScreen: wlrLog(.debug, "\(name): window \(id) gone (no longer on screen)")
            }
            post(.destroyed(id))
        }
    }

    /// A boolean attribute, nil when the window did not answer (a timeout right after
    /// wake must not read as "not minimized"); an unsupported attribute is false.
    private static func answeredBool(_ el: AXUIElement, _ name: String) -> Bool? {
        let (err, value) = el.attributeResult(name)
        if err == .cannotComplete || err == .invalidUIElement { return nil }
        return (value as? Bool) ?? false
    }

    /// Returns false when a notification could not be registered (retried on refresh).
    /// Stops at the first failure, as `subscribeApp` does.
    @discardableResult
    private func subscribeWindow(_ el: AXUIElement) -> Bool {
        guard let obs = observer else { return false }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.windowNotifications {
            guard obs.add(el, n, refcon: refcon) else { return false }
        }
        return true
    }

    private static let windowNotifications = [
        kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification, kAXMovedNotification, kAXResizedNotification,
        kAXTitleChangedNotification]

    /// Drop a dead element's registrations (the observer keeps a list of them).
    private func unsubscribeWindow(_ el: AXUIElement) {
        guard let obs = observer else { return }
        for n in Self.windowNotifications { obs.remove(el, n) }
    }

    // MARK: Classification (on `thread`)

    /// AeroSpace getAxUiElementWindowType (tree/MacApp.swift): a popup is not managed, a
    /// dialog opens floating (`WindowClassifier`).
    private func classify(_ el: AXUIElement, id: CGWindowID) -> DiscoveredWindow? {
        let level = MacOsWindowLevel.of(id)
        let type = Self.windowType(el.getWindowType(axApp: ax, KnownBundleId(rawValue: bundleId),
                                                    nsApp.activationPolicy, level), level: level)
        let frame = el.frame ?? .zero
        wlrLog(.debug, "classified \(id) \(bundleId) '\(el.title)' as \(type): subrole \(el.subrole ?? "-") level \(level.map { "\($0)" } ?? "-") frame \(frame)")
        guard type != .popup else { return nil }
        return DiscoveredWindow(id: id, pid: pid, element: el, bundleId: bundleId, appName: name,
                                title: el.title, subrole: el.subrole ?? "", isDialog: type == .dialog,
                                frame: frame, isMinimized: el.isMinimized, isFullscreen: el.isFullscreen,
                                isAppHidden: nsApp.isHidden)
    }

    /// Not in AeroSpace: its window-level rule for every app. AeroSpace treats a window above
    /// the normal level as a popup only for the apps it has dumps of, rolling it out app by
    /// app; here it holds for all (a notification or a floating panel is the app's own, as a
    /// layer surface is in mango). A window not on screen (no level) is decided as before.
    static func windowType(_ type: AxUiElementWindowType, level: MacOsWindowLevel?) -> AxUiElementWindowType {
        guard let level, level != .normalWindow else { return type }
        return .popup
    }

    /// The window's frame as the window server has it (top-left origin, like AX). Needs
    /// no answer from the app, so it is right even while the app is frozen.
    public static func windowServerFrame(_ id: CGWindowID) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let bounds = info.first?[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    /// The windows the window server shows, front to back, where it has them.
    public static func stackingOrder() -> [StackedWindow] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { w in
            guard let id = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return nil }
            return StackedWindow(id: id, frame: r, opaque: ((w[kCGWindowAlpha as String] as? Double) ?? 1) >= 1)
        }
    }

    /// Every window the window server has, on screen or not (minimized, hidden, other Space).
    /// The ids alone (CGWindowListCreate): a dispatch asks, and every window's description
    /// (CGWindowListCopyWindowInfo) took 5 ms to the ids' 2.
    public static func allWindowIDs() -> Set<CGWindowID> {
        guard let list = mango_WindowListCreate() else { return [] }
        return Set((0..<CFArrayGetCount(list)).map {
            CGWindowID(truncatingIfNeeded: UInt(bitPattern: CFArrayGetValueAtIndex(list, $0)))
        })
    }

    /// The windows on screen, front to back, ids alone (about 2 ms; an order is about 2 ms each).
    public static func onScreenOrder() -> [CGWindowID] {
        guard let list = mango_WindowListCreateOnScreen() else { return [] }
        return (0..<CFArrayGetCount(list)).map {
            CGWindowID(truncatingIfNeeded: UInt(bitPattern: CFArrayGetValueAtIndex(list, $0)))
        }
    }

    /// Normal-layer windows the window server shows for `pid` (diagnostics).
    static func onScreenWindowCount(pid: pid_t) -> Int {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return 0 }
        return info.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }.count
    }

    // MARK: Focus

    /// Reads the app's focused window on `thread` and reports it if tracked.
    /// The main thread only acts on it while this app is frontmost.
    func requestFocusReport() {
        thread.perform { [self] in reportFocus() }
    }

    private func reportFocus() {
        guard let id = ax.focusedWindow?.windowID, book.windows[id] != nil else { return }
        post(.focused(id))
    }

    // MARK: AX notifications (on `thread`)

    fileprivate func handle(notification: String, element: AXUIElement) {
        switch notification {
        case kAXWindowCreatedNotification:
            runRefresh(recheck: true, notified: true)
        case kAXMainWindowChangedNotification, kAXApplicationActivatedNotification, kAXFocusedWindowChangedNotification:
            runRefresh(recheck: true, notified: true)
            reportFocus()
        case kAXUIElementDestroyedNotification:
            if let id = windowID(of: element, orphans: true) {
                wlrLog(.debug, "\(name): window \(id) gone (destroyed notification)")
                book.forget(id)
                unsubscribeWindow(element)
                post(.destroyed(id))
            } else {
                runRefresh(recheck: false)
            }
        case kAXWindowMiniaturizedNotification:
            if let id = windowID(of: element) { post(.minimized(id, true)) }
        case kAXWindowDeminiaturizedNotification:
            if let id = windowID(of: element) { post(.minimized(id, false)) }
        case kAXMovedNotification, kAXResizedNotification:
            guard let id = windowID(of: element), !shared.isSuppressed(id) else { return }
            let resized = notification == kAXResizedNotification
            guard let frame = element.frame else { return }
            queueGeometry(id, frame, resized: resized, fullscreen: resized ? element.isFullscreen : nil)
        case kAXTitleChangedNotification:
            if let id = windowID(of: element) { post(.title(id, element.title)) }
        default:
            break
        }
    }

    private func queueGeometry(_ id: CGWindowID, _ frame: CGRect, resized: Bool, fullscreen: Bool?) {
        lock.lock()
        let old = pendingGeometry[id]
        pendingGeometry[id] = (frame, resized || (old?.1 ?? false), fullscreen ?? old?.2)
        let schedule = !geometryScheduled
        geometryScheduled = true
        lock.unlock()
        guard schedule else { return }
        DispatchQueue.main.async { [self] in
            lock.lock()
            let batch = pendingGeometry
            pendingGeometry.removeAll()
            geometryScheduled = false
            lock.unlock()
            for (id, g) in batch { deliver(.geometry(id, g.0, resized: g.1, fullscreen: g.2)) }
        }
    }

    /// `orphans`: an orphan's element too (its destroyed notice; see WindowBook.orphans).
    private func windowID(of element: AXUIElement, orphans: Bool = false) -> CGWindowID? {
        let books = orphans ? [book.windows, book.orphans] : [book.windows]
        for windows in books {
            if let id = element.windowID, windows[id] != nil { return id }
            for (id, el) in windows where CFEqual(el, element) { return id }
        }
        return nil
    }
}

private func workerAXCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
                              _ info: CFDictionary, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let worker = Unmanaged<AppWorker>.fromOpaque(refcon).takeUnretainedValue()
    worker.handle(notification: notification as String, element: element)
}

/// Tracks running apps. Runs on the main thread but never makes a synchronous
/// AX call itself: each app's `AppWorker` does that on its own thread and sends
/// the results here.
@MainActor
public final class AppWatcher {
    public weak var delegate: AppWatcherDelegate?

    public private(set) var apps: [pid_t: AppWorker] = [:]
    /// Main-thread mirror of tracked windows (for `element(for:)`).
    private var owners: [CGWindowID: (pid: pid_t, element: AXUIElement)] = [:]
    public var ignoredBundleIds: Set<String> = [] {
        didSet { if ignoredBundleIds != oldValue { caughtUp = false } }   // an app ignored before is looked at again
    }
    /// The running apps have been looked at once. After that an app is taken when it launches
    /// or is activated: asking every running app its pid or policy is a call to LaunchServices
    /// once an activation has made the answers stale, 9 ms on every key.
    private var caughtUp = false
    let shared = WatcherShared()
    private var mouseUpMonitor: Any?
    private var commandKeyMonitor: Any?
    private var screenParamsDebounce: DispatchWorkItem?

    public init() {}

    // MARK: Lifecycle

    public func start() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                // An app activated while starting is tracked already, and its first scans
                // were refused: its accessibility comes up when it has finished launching,
                // which is this notification. Ask now, or nothing asks until the user acts.
                if self.apps[app.processIdentifier] != nil {
                    self.refresh(pid: app.processIdentifier, recheckRejected: true)
                } else {
                    self.register(app, initial: false)
                }
            }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.unregister(pid: app.processIdentifier) }
        }
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.apps[app.processIdentifier] == nil {
                    self.register(app, initial: false)
                }
                // All apps: the one left behind may have closed a window on the way out.
                self.refreshAll(recheckRejected: true)
                self.delegate?.appActivated(pid: app.processIdentifier)
            }
        }
        nc.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.delegate?.appHidden(pid: app.processIdentifier, hidden: true) }
        }
        nc.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                self?.refresh(pid: app.processIdentifier)
                self?.delegate?.appHidden(pid: app.processIdentifier, hidden: false)
            }
        }
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAll() }
        }
        // After sleep every window's AX element has gone invalid: look for the new ones
        // on each wake step. Apps that list their windows later still announce them
        // (window created, focus), and the next click or key catches the rest.
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshAll(recheckRejected: true) }
            }
        }
        // Fires several times in a burst when displays change or the Dock resizes; coalesce.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.screenParamsDebounce?.cancel()
                let item = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        self?.delegate?.screensChanged()
                    }
                }
                self.screenParamsDebounce = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
            }
        }

        for app in NSWorkspace.shared.runningApplications { register(app, initial: true) }

        // AXWindowCreated / AXUIElementDestroyed are not fully reliable. Instead of polling
        // on a clock, rescan when the user does something (as AeroSpace does): a click
        // (a close button in a background window, a new window that missed its
        // notification), a Command shortcut (Cmd-N, Cmd-W) in the frontmost app, an app
        // switch and every dispatcher (MangoServer.dispatch). Each rescan runs on the
        // app's own thread; a hung app keeps at most one waiting. What changes while the
        // user does nothing is seen at the next interaction.
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAll(recheckRejected: true) }
        }
        commandKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] e in
            guard e.modifierFlags.contains(.command) else { return }
            MainActor.assumeIsolated {
                if let front = NSWorkspace.shared.frontmostApplication {
                    self?.refresh(pid: front.processIdentifier, recheckRejected: true)
                }
            }
        }
    }

    public func writeQueue(for pid: pid_t) -> AXWriteQueue? { apps[pid]?.writeQueue }
    public func worker(for pid: pid_t) -> AppWorker? { apps[pid] }
    public func element(for id: CGWindowID) -> AXUIElement? { owners[id]?.element }

    private func register(_ nsApp: NSRunningApplication, initial: Bool) {
        let pid = nsApp.processIdentifier
        guard apps[pid] == nil, pid != getpid() else { return }
        guard nsApp.activationPolicy == .regular, !nsApp.isTerminated else { return }
        if let b = nsApp.bundleIdentifier, ignoredBundleIds.contains(b) { return }
        let worker = AppWorker(nsApp: nsApp, shared: shared, initial: initial) { [weak self] e in
            MainActor.assumeIsolated { self?.receive(e, pid: pid) }
        }
        apps[pid] = worker
        worker.start()
    }

    private func unregister(pid: pid_t) {
        guard let worker = apps.removeValue(forKey: pid) else { return }
        wlrLog(.debug, "\(worker.name) (pid \(pid)) ended: its windows are dropped")
        worker.stop()
        for (id, o) in owners where o.pid == pid {
            owners.removeValue(forKey: id)
            delegate?.windowDestroyed(id: id)
        }
        delegate?.appTerminated(pid: pid)
    }

    private func receive(_ e: AppEvent, pid: pid_t) {
        guard apps[pid] != nil else { return }   // app quit meanwhile
        switch e {
        case .discovered(let ws):
            for w in ws {
                owners[w.id] = (pid, w.element)
                delegate?.windowDiscovered(w)
            }
        case .destroyed(let id):
            guard owners.removeValue(forKey: id) != nil else { return }
            delegate?.windowDestroyed(id: id)
        case .geometry(let id, let frame, let resized, let fs):
            guard owners[id] != nil else { return }
            delegate?.windowGeometryChanged(id: id, frame: frame, resized: resized, isFullscreen: fs)
        case .minimized(let id, let m):
            delegate?.windowMinimized(id: id, minimized: m)
        case .title(let id, let t):
            delegate?.windowTitleChanged(id: id, title: t)
        case .responding(let r):
            delegate?.appResponding(pid: pid, responding: r)
        case .reacquired(let id, let element, let state):
            owners[id] = (pid, element)
            delegate?.windowReacquired(id: id, element: element, state: state)
        case .focused(let id):
            // Only the frontmost app's current focused window counts as focused. Our own
            // AXRaise calls make background apps report main/focused-window changes, and
            // stale notifications arrive after focus moved on; acting on them steals focus.
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, owners[id] != nil else { return }
            delegate?.windowFocused(id: id)
        }
    }

    // MARK: Requests (all asynchronous, executed on the app's thread)

    public func refreshAll(recheckRejected: Bool = false) {
        for w in apps.values {
            // The process is gone: it ended. (isTerminated would ask LaunchServices; the
            // app's instance is not always the one runningApplications lists.)
            if kill(w.pid, 0) != 0 && errno == ESRCH { unregister(pid: w.pid); continue }
            w.requestRefresh(recheck: recheckRejected)
        }
        // Apps launched before we registered observers
        guard !caughtUp else { return }
        caughtUp = true
        for a in NSWorkspace.shared.runningApplications where apps[a.processIdentifier] == nil {
            register(a, initial: false)
        }
    }

    public func refresh(pid: pid_t, recheckRejected: Bool = false) {
        guard let w = apps[pid] else { return }
        if w.nsApp.isTerminated { unregister(pid: pid); return }
        w.requestRefresh(recheck: recheckRejected)
    }

    /// Ask the app which window it has focused; arrives as `windowFocused`.
    public func requestFocusReport(pid: pid_t) {
        apps[pid]?.requestFocusReport()
    }

    /// Skip reading back move/resize notifications we cause ourselves.
    public func suppressGeometry(_ id: CGWindowID, until t: TimeInterval) {
        shared.suppress(id, until: t)
    }
}

/// A window as the window server stacks it: where it is, and whether its window alpha is
/// whole. A window drawn with a transparent background (a terminal's background opacity,
/// vibrancy) still counts as opaque: the window server does not report that.
public struct StackedWindow: Equatable, Sendable {
    public var id: CGWindowID
    public var frame: CGRect
    public var opaque: Bool

    public init(id: CGWindowID, frame: CGRect, opaque: Bool = true) {
        self.id = id; self.frame = frame; self.opaque = opaque
    }
}
