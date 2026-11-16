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
    /// wlroots' c->scene->node.enabled and c->scene_surface->node.enabled.
    var sceneNodeEnabled = true
    var sceneSurfaceEnabled = true
    /// Where mango's scene node stands (the box with the border), and the window's box the port writes.
    var nodePosition: CGPoint
    var box: CGRect
    /// Whether the last frame written was a step of an animation.
    var moving = false
    /// Port extension: chutney_fullscreen_tag. On its F tag in macOS fullscreen, in its own Space: macOS
    /// places it, the port writes nothing to it.
    var nativeFullscreen = false
    /// Port extension: chutney_fullscreen_tag. The fullscreen the port last told the app (wlroots'
    /// scheduled.fullscreen), and whether macOS has yet to answer it: till then macOS moves the window and
    /// the port writes nothing to it.
    var scheduledFullscreen = false
    var fullscreenPending = false

    let isFloatType: Bool

    init(element: AXUIElement, frame: CGRect, isFloatType: Bool = false) {
        self.element = element
        self.frame = frame
        self.nodePosition = frame.origin
        self.box = frame
        self.isFloatType = isFloatType
    }
}

extension Client {
    convenience init(window w: DiscoveredWindow, monitor: Monitor, tags: UInt32) {
        self.init(id: w.id, pid: w.pid, platform: MacWindow(element: w.element, frame: w.frame, isFloatType: w.isDialog),
                  bundleId: w.bundleId, appName: w.appName, title: w.title, monitor: monitor, tags: tags, frame: w.frame)
    }

    var mac: MacWindow { platform as! MacWindow }

    /// The window's box in its tile: mango's geom without the border.
    var tile: CGRect { geom.insetBy(dx: bw, dy: bw) }

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
    var nativeFullscreen: Bool {
        get { mac.nativeFullscreen }
        set { mac.nativeFullscreen = newValue }
    }
    var scheduledFullscreen: Bool {
        get { mac.scheduledFullscreen }
        set { mac.scheduledFullscreen = newValue }
    }
    var fullscreenPending: Bool {
        get { mac.fullscreenPending }
        set { mac.fullscreenPending = newValue }
    }
    /// Port extension: chutney_fullscreen_tag. In macOS fullscreen, or told to go in or out: macOS places it.
    var leftToMacOS: Bool { mac.nativeFullscreen || mac.fullscreenPending }
}
