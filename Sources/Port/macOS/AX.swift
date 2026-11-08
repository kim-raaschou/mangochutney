import AppKit
import ApplicationServices
import QuartzCore
import MangoPrivate
import Mango

public enum AX {
    public static let messagingTimeout: Float = 0.5

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    public static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

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

    func close() { closeButton?.press() }

    var enhancedUserInterface: Bool {
        get { (attribute("AXEnhancedUserInterface") as Bool?) ?? false }
        set { setAttribute("AXEnhancedUserInterface", newValue as CFBoolean) }
    }

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

public final class AXObserverBox {
    public let observer: AXObserver
    public let pid: pid_t
    private var registered: [(AXUIElement, String)] = []

    private let runLoop: CFRunLoop

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

public protocol WindowWriter: AnyObject {
    func write(_ element: AXUIElement, id: CGWindowID, frame: CGRect, setSize: Bool, animating: Bool,
               written: (@MainActor (CGRect) -> Void)?)
    func readBack(_ element: AXUIElement, completion: @escaping @MainActor (CGRect?) -> Void)
    func raise(_ element: AXUIElement)
    func async(_ body: @escaping () -> Void)
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
        var written: (@MainActor (CGRect) -> Void)?
    }
    private var pending: [CGWindowID: PendingWrite] = [:]
    private var scheduled: Set<CGWindowID> = []
    public let pid: pid_t
    private let app: AXUIElement
    private var enhancedUIOff = false
    private var enhancedUIKnownOffUntil: CFTimeInterval = 0
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

    public func write(_ element: AXUIElement, id: CGWindowID, frame: CGRect, setSize: Bool, animating: Bool,
                      written: (@MainActor (CGRect) -> Void)?) {
        lock.lock()
        let keepSize = pending[id]?.setSize ?? false
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
                el.setPosition(r.origin)
                el.setSize(r.size)
            } else {
                el.setPosition(r.origin)
            }
        }
    }

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

    public func raise(_ element: AXUIElement) { queue.async { element.raise() } }

    public func async(_ body: @escaping () -> Void) { queue.async(execute: body) }
    public func sync(_ body: () -> Void) { queue.sync(execute: body) }
}

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
        RunLoop.current.add(NSMachPort(), forMode: .default)
        ready.signal()
        while !isCancelled {
            CFRunLoopRunInMode(.defaultMode, 3600, false)
        }
    }

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
