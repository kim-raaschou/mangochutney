import ApplicationServices
import QuartzCore
import Mango

@MainActor
final class MacWindow: PlatformWindow {
    var element: AXUIElement
    var frame: CGRect
    var parked = false
    var ignoreMovesUntil: TimeInterval = 0
    var lastReassert: TimeInterval = 0
    var writes = 0
    var retryTarget: CGRect?
    var retryCount = 0
    var parkRetries = 0
    var deferredRetryPending = false
    var refusedSize: CGSize?

    let isFloatType: Bool

    init(element: AXUIElement, frame: CGRect, isFloatType: Bool = false) {
        self.element = element
        self.frame = frame
        self.isFloatType = isFloatType
    }
}

extension Client {
    convenience init(window w: DiscoveredWindow, monitor: Monitor, tags: UInt32) {
        self.init(id: w.id, pid: w.pid, platform: MacWindow(element: w.element, frame: w.frame, isFloatType: w.isDialog),
                  bundleId: w.bundleId, appName: w.appName, title: w.title, monitor: monitor, tags: tags, frame: w.frame)
    }

    var mac: MacWindow { platform as! MacWindow }

    var element: AXUIElement {
        get { mac.element }
        set { mac.element = newValue }
    }
    var ignoreMovesUntil: TimeInterval {
        get { mac.ignoreMovesUntil }
        set { mac.ignoreMovesUntil = newValue }
    }
    var lastReassert: TimeInterval {
        get { mac.lastReassert }
        set { mac.lastReassert = newValue }
    }
    var writes: Int {
        get { mac.writes }
        set { mac.writes = newValue }
    }
    var retryTarget: CGRect? {
        get { mac.retryTarget }
        set { mac.retryTarget = newValue }
    }
    var retryCount: Int {
        get { mac.retryCount }
        set { mac.retryCount = newValue }
    }
    var parkRetries: Int {
        get { mac.parkRetries }
        set { mac.parkRetries = newValue }
    }
    var deferredRetryPending: Bool {
        get { mac.deferredRetryPending }
        set { mac.deferredRetryPending = newValue }
    }
    var refusedSize: CGSize? {
        get { mac.refusedSize }
        set { mac.refusedSize = newValue }
    }
}
