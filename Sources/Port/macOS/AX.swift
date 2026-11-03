import AppKit
import ApplicationServices
import QuartzCore
import MangoPrivate
import Mango

/// Thin wrappers around the Accessibility API. All calls are synchronous IPC
/// to the target app; a per-element messaging timeout keeps hung apps from
/// blocking us for long.
public enum AX {
    public static let messagingTimeout: Float = 0.5

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt if not trusted.
    public static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// The per-element timeout only applies to the element it is set on; window
    /// elements obtained from `kAXWindowsAttribute` would otherwise use the 6s
    /// default. Setting it on the system-wide element makes it global (rift does
    /// the same), so a hung app blocks us for at most `messagingTimeout`.
    public static func setGlobalTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
    }

    public static func appElement(pid: pid_t) -> AXUIElement {
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, messagingTimeout)
        return el
    }

    public static func systemWide() -> AXUIElement {
        let el = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(el, messagingTimeout)
        return el
    }
}

public extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(self, name as CFString, &value)
        guard err == .success, let v = value else { return nil }
        return v as? T
    }

    /// Attribute read that keeps the AX error, so a timeout (`.cannotComplete`: the
    /// app is busy or hung) can be told apart from a dead element (`.invalidUIElement`).
    func attributeResult(_ name: String) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(self, name as CFString, &value)
        return (err, value)
    }

    func rawAttribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(self, name as CFString, &value)
        return err == .success ? value : nil
    }

    @discardableResult
    func setAttribute(_ name: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(self, name as CFString, value)
    }

    func isSettable(_ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(self, name as CFString, &settable) == .success && settable.boolValue
    }

    var pid: pid_t? {
        var p: pid_t = 0
        return AXUIElementGetPid(self, &p) == .success ? p : nil
    }

    /// CGWindowID via the private `_AXUIElementGetWindow`.
    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        let err = _AXUIElementGetWindow(self, &id)
        return err == .success && id != 0 ? id : nil
    }

    var role: String? { attribute(kAXRoleAttribute) }
    var subrole: String? { attribute(kAXSubroleAttribute) }
    var title: String { attribute(kAXTitleAttribute) ?? "" }
    var identifier: String? { attribute(kAXIdentifierAttribute) }

    var isMinimized: Bool { (attribute(kAXMinimizedAttribute) as Bool?) ?? false }
    var isFullscreen: Bool { (attribute("AXFullScreen") as Bool?) ?? false }
    var isMain: Bool { (attribute(kAXMainAttribute) as Bool?) ?? false }
    var isFocused: Bool { (attribute(kAXFocusedAttribute) as Bool?) ?? false }

    var windows: [AXUIElement] {
        (attribute(kAXWindowsAttribute) as [AXUIElement]?) ?? []
    }
    var focusedWindow: AXUIElement? { attribute(kAXFocusedWindowAttribute) }
    var mainWindow: AXUIElement? { attribute(kAXMainWindowAttribute) }

    var closeButton: AXUIElement? { attribute(kAXCloseButtonAttribute) }
    var zoomButton: AXUIElement? { attribute(kAXZoomButtonAttribute) }
    var fullscreenButton: AXUIElement? { attribute(kAXFullScreenButtonAttribute) }
    var minimizeButton: AXUIElement? { attribute(kAXMinimizeButtonAttribute) }
    var isEnabled: Bool { (attribute(kAXEnabledAttribute) as Bool?) ?? true }

    var position: CGPoint? {
        guard let v = rawAttribute(kAXPositionAttribute) else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }
    var size: CGSize? {
        guard let v = rawAttribute(kAXSizeAttribute) else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }
    var frame: CGRect? {
        guard let p = position, let s = size else { return nil }
        return CGRect(origin: p, size: s)
    }

    @discardableResult
    func setPosition(_ p: CGPoint) -> AXError {
        var pt = p
        guard let v = AXValueCreate(.cgPoint, &pt) else { return .failure }
        return setAttribute(kAXPositionAttribute, v)
    }

    @discardableResult
    func setSize(_ s: CGSize) -> AXError {
        var sz = s
        guard let v = AXValueCreate(.cgSize, &sz) else { return .failure }
        return setAttribute(kAXSizeAttribute, v)
    }

    /// Size, position, size (AeroSpace order: avoids clamping at screen edges).
    func setFrame(_ r: CGRect) {
        setSize(r.size)
        setPosition(r.origin)
        setSize(r.size)
    }

    func raise() { AXUIElementPerformAction(self, kAXRaiseAction as CFString) }
    func press() { AXUIElementPerformAction(self, kAXPressAction as CFString) }

    func setMinimized(_ v: Bool) { setAttribute(kAXMinimizedAttribute, v as CFBoolean) }
    func setFullscreen(_ v: Bool) { setAttribute("AXFullScreen", v as CFBoolean) }
    func setMain() { setAttribute(kAXMainAttribute, kCFBooleanTrue) }

    /// Close via the close button (polite close, like mango's killclient).
    func close() { closeButton?.press() }

    /// `AXEnhancedUserInterface` on the app element makes some apps animate
    /// and clamp frame changes; temporarily disable it while we move windows.
    var enhancedUserInterface: Bool {
        get { (attribute("AXEnhancedUserInterface") as Bool?) ?? false }
        set { setAttribute("AXEnhancedUserInterface", newValue as CFBoolean) }
    }

    /// Topmost AX element at a screen point (AX coordinates), and its window.
    static func elementAt(_ point: CGPoint) -> AXUIElement? {
        var el: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(AX.systemWide(), Float(point.x), Float(point.y), &el)
        return err == .success ? el : nil
    }

    var containingWindow: AXUIElement? {
        if role == kAXWindowRole { return self }
        return attribute(kAXWindowAttribute)
    }
}

/// Observer wrapper; the run loop source is attached to `runLoop`.
public final class AXObserverBox {
    public let observer: AXObserver
    public let pid: pid_t
    private var registered: [(AXUIElement, String)] = []

    private let runLoop: CFRunLoop

    /// The observer's callbacks run on `runLoop` (an app's own `AXThread`, so
    /// notifications from a hung app never reach the main thread).
    public init?(pid: pid_t, callback: @escaping AXObserverCallbackWithInfo, refcon: UnsafeMutableRawPointer?,
                 runLoop: CFRunLoop = CFRunLoopGetMain()) {
        var obs: AXObserver?
        guard AXObserverCreateWithInfoCallback(pid, callback, &obs) == .success, let o = obs else { return nil }
        observer = o
        self.pid = pid
        self.runLoop = runLoop
        CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(o), .commonModes)
        _ = refcon
    }

    @discardableResult
    public func add(_ element: AXUIElement, _ notification: String, refcon: UnsafeMutableRawPointer?) -> Bool {
        let err = AXObserverAddNotification(observer, element, notification as CFString, refcon)
        if err == .success || err == .notificationAlreadyRegistered {
            registered.append((element, notification))
            return true
        }
        return false
    }

    public func remove(_ element: AXUIElement, _ notification: String) {
        AXObserverRemoveNotification(observer, element, notification as CFString)
        registered.removeAll { CFEqual($0.0, element) && $0.1 == notification }
    }

    deinit {
        for (el, n) in registered { AXObserverRemoveNotification(observer, el, n as CFString) }
        CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(observer), .commonModes)
    }
}

/// Serial per-process queue for AX writes, so a hung app does not block the
/// main thread or other apps' animations. Only the newest pending frame per
/// window is kept.
/// The writes mango makes to another app's windows, in order, off the main thread.
/// `AXWriteQueue` is the real one; the tests drive the engine through a fake app.
public protocol WindowWriter: AnyObject {
    /// `written` runs on the main thread once the frame has been written (not for a
    /// write a newer one replaced before it was sent). Callers use `setFrame`.
    func write(_ element: AXUIElement, id: CGWindowID, frame: CGRect, setSize: Bool, animating: Bool,
               written: (@MainActor (CGRect) -> Void)?)
    /// The window's real frame after every write queued before this call (nil: no answer).
    func readBack(_ element: AXUIElement, completion: @escaping @MainActor (CGRect?) -> Void)
    func raise(_ element: AXUIElement)
    func async(_ body: @escaping () -> Void)
    /// After the last write (quit): leave the app as it was, e.g. AXEnhancedUserInterface on.
    func restoreAppSettings()
}

public extension WindowWriter {
    func setFrame(_ element: AXUIElement, id: CGWindowID, frame: CGRect, setSize: Bool = true, animating: Bool = false,
                  written: (@MainActor (CGRect) -> Void)? = nil) {
        write(element, id: id, frame: frame, setSize: setSize, animating: animating, written: written)
    }
}

public final class AXWriteQueue: WindowWriter {
    private let queue: DispatchQueue
    private let lock = NSLock()
    private struct PendingWrite {
        var element: AXUIElement
        var frame: CGRect
        var setSize: Bool
        var animating: Bool
        /// Called on the main thread once this frame has been written (not for a write a
        /// newer one replaced before it was sent).
        var written: (@MainActor (CGRect) -> Void)?
    }
    private var pending: [CGWindowID: PendingWrite] = [:]
    private var scheduled: Set<CGWindowID> = []
    public let pid: pid_t
    /// Apps with AXEnhancedUserInterface on (set by assistive tools; Ghostty, Electron
    /// apps) apply frame writes late and animated, then finish a resize with a stale
    /// position. Like rift and yabai it is switched off while we move the app's
    /// windows and back on by the read-back after the last write. Queue-confined.
    private let app: AXUIElement
    private var enhancedUIOff = false
    /// The app answered "off" this recently: no need to ask (an AX round trip) on every frame.
    private var enhancedUIKnownOffUntil: CFTimeInterval = 0
    /// Read-backs waiting on the queue (lock). A hung app would otherwise collect a backlog
    /// of stale reads that all run once it recovers.
    private var pendingReads = 0
    private static let maxPendingReads = 4

    public init(pid: pid_t) {
        self.pid = pid
        app = AXUIElementCreateApplication(pid)
        queue = DispatchQueue(label: "mango.ax.\(pid)", qos: .userInteractive)
    }

    private func suspendEnhancedUI() {
        let now = CACurrentMediaTime()
        guard !enhancedUIOff, now >= enhancedUIKnownOffUntil else { return }
        guard app.enhancedUserInterface else {
            enhancedUIKnownOffUntil = now + 2
            return
        }
        app.enhancedUserInterface = false
        enhancedUIOff = true
    }

    /// Switched back on once the writes are done: by the read-back that follows every
    /// placement (verifyFrame, parking, the end of a grab), when no other write is
    /// waiting, and at quit (`restoreAppSettings`). No timer.
    public func restoreAppSettings() {
        queue.async { [self] in restoreEnhancedUIIfIdle() }
    }

    private func restoreEnhancedUIIfIdle() {
        guard enhancedUIOff else { return }
        lock.lock()
        let idle = pending.isEmpty
        lock.unlock()
        guard idle else { return }
        app.enhancedUserInterface = true
        enhancedUIOff = false
    }

    /// `animating`: an animation frame, written in two calls (below). A slow app gets fewer
    /// of them, never a wrong one: only the newest frame waits while it is busy.
    /// `written` runs on the main thread after the app has been given the frame: the
    /// window is there now (its content may still be redrawing), so a border drawn from
    /// it stays with the window instead of running ahead of a slow app.
    public func write(_ element: AXUIElement, id: CGWindowID, frame: CGRect, setSize: Bool, animating: Bool,
                      written: (@MainActor (CGRect) -> Void)?) {
        lock.lock()
        // Coalescing keeps only the newest frame, but a size write that has not been
        // sent yet must survive a newer position-only write (e.g. an animation tick).
        let keepSize = pending[id]?.setSize ?? false
        // A replaced write's callback moves to the newer write, so a report someone waits
        // for (an animation's last frame) is not lost when another write overtakes it; it
        // then reports the frame that was really written.
        let report = written ?? pending[id]?.written
        pending[id] = PendingWrite(element: element, frame: frame, setSize: setSize || keepSize, animating: animating, written: report)
        let needSchedule = !scheduled.contains(id)
        scheduled.insert(id)
        lock.unlock()
        guard needSchedule else { return }
        queue.async { [self] in
            lock.lock()
            let job = pending.removeValue(forKey: id)
            scheduled.remove(id)
            lock.unlock()
            guard let job else { return }
            let (el, r, withSize, animating) = (job.element, job.frame, job.setSize, job.animating)
            defer {
                if let done = job.written {
                    DispatchQueue.main.async { MainActor.assumeIsolated { done(r) } }
                }
            }
            suspendEnhancedUI()
            if withSize && !animating {
                el.setFrame(r)
            } else if withSize {
                // Animation frame: position then size, two calls. The size-position-size
                // order of a single write costs apps two to three times as much (Ghostty
                // 15 vs 12 ms, Claude 5 vs 2 ms) and is only needed against clamping at a
                // screen edge, which the final frame still gets. Always in this order:
                // measured in the window server, Claude's window showed the move together
                // with the resize that followed it, but a resize sent first was on screen
                // before the move (a tile whose top went down while its bottom held still
                // had its bottom up to 11 pt too high on each frame; position first, it never
                // moved). Ghostty was off by a few points in either order.
                el.setPosition(r.origin)
                el.setSize(r.size)
            } else {
                el.setPosition(r.origin)
            }
        }
    }

    /// Reads the window's real frame after every write queued before this call
    /// (the queue is serial). Apps clamp sizes (minimum size, aspect ratio) and
    /// then send no resize notification, so this is the only way to know.
    public func readBack(_ element: AXUIElement, completion: @escaping @MainActor (CGRect?) -> Void) {
        lock.lock()
        guard pendingReads < Self.maxPendingReads else { lock.unlock(); return }
        pendingReads += 1
        lock.unlock()
        queue.async { [self] in
            lock.lock(); pendingReads -= 1; lock.unlock()
            let f = element.frame
            restoreEnhancedUIIfIdle()
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(f) } }
        }
    }

    /// AXRaise is synchronous IPC too; keep it off the main thread.
    public func raise(_ element: AXUIElement) { queue.async { element.raise() } }

    public func async(_ body: @escaping () -> Void) { queue.async(execute: body) }
    public func sync(_ body: () -> Void) { queue.sync(execute: body) }
}

/// A thread with its own CFRunLoop (AeroSpace / rift: one per app). Blocks
/// passed to `perform` run in order on that thread; AX observers can attach to
/// `runLoop`. A slow or hung app only ever blocks its own thread.
public final class AXThread: Thread, @unchecked Sendable {
    private var loop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)

    public init(name: String) {
        super.init()
        self.name = name
        qualityOfService = .userInteractive
    }

    public override func main() {
        loop = CFRunLoopGetCurrent()
        // A run loop with no sources exits immediately; keep it alive with a port.
        RunLoop.current.add(NSMachPort(), forMode: .default)
        ready.signal()
        while !isCancelled {
            CFRunLoopRunInMode(.defaultMode, 3600, false)
        }
    }

    /// Starts the thread and waits (microseconds) until its run loop exists.
    public func startAndWait() {
        start()
        ready.wait()
    }

    public var runLoop: CFRunLoop { loop! }

    public func perform(_ block: @escaping () -> Void) {
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(loop)
    }

    public func stop() {
        cancel()
        perform { CFRunLoopStop(CFRunLoopGetCurrent()) }
    }
}
