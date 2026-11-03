import ApplicationServices
import QuartzCore
import Mango

/// The macOS side of a managed window (plan step 2): its Accessibility element, and the
/// bookkeeping of mango's writes to an app that may refuse, lag or move the window
/// itself. Kept as the Client's `platform`.
@MainActor
final class MacWindow: PlatformWindow {
    var element: AXUIElement
    /// Where the window is: the last frame written to it, or seen when its app or the user
    /// moved it.
    var frame: CGRect
    /// Hidden the macOS way: moved into a corner with a pixel showing (Hider).
    var parked = false
    /// Programmatic writes until this time are not treated as user moves.
    var ignoreMovesUntil: TimeInterval = 0
    /// Last time the frame was re-asserted after the app moved itself.
    var lastReassert: TimeInterval = 0
    /// Frames mango has written to this window (`place`).
    var writes = 0
    /// Re-placements of the same target (an app that keeps moving itself is not fought forever).
    var retryTarget: CGRect?
    var retryCount = 0
    /// Re-parks since the window was last placed: an app that keeps moving its hidden
    /// window back into view is not fought forever.
    var parkRetries = 0
    var deferredRetryPending = false
    /// The size the app keeps the window at, larger than its tile (its minimum size); nil
    /// once it takes a tile's size. The window then grows inward (Placement.inwardOrigin).
    var refusedSize: CGSize?

    init(element: AXUIElement, frame: CGRect) {
        self.element = element
        self.frame = frame
    }
}

extension Client {
    /// A window the watcher found, with its macOS side.
    convenience init(window w: DiscoveredWindow, monitor: Monitor, tags: UInt32) {
        self.init(id: w.id, pid: w.pid, platform: MacWindow(element: w.element, frame: w.frame), bundleId: w.bundleId,
                  appName: w.appName, title: w.title, monitor: monitor, tags: tags, frame: w.frame)
        isDialog = w.isDialog
    }

    var mac: MacWindow { platform as! MacWindow }   // the port makes every Client's platform

    var element: AXUIElement {
        get { mac.element }
        set { mac.element = newValue }
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
