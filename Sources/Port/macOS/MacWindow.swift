import ApplicationServices
import QuartzCore
import Mango

@MainActor
final class MacWindow: PlatformWindow {
    var element: AXUIElement
    var frame: CGRect
    var parked = false
    /// What the port wrote to the app and what it answered (Placement).
    let placed = PlacedWindow()
    /// wlroots' c->scene->node.enabled and c->scene_surface->node.enabled.
    var sceneNodeEnabled = true
    var sceneSurfaceEnabled = true
    /// Where mango's scene node stands (the box with the border), and the window's box the port writes.
    var nodePosition: CGPoint
    var box: CGRect
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

    /// Where the macOS window stands, and whether it is parked off screen.
    var frame: CGRect {
        get { mac.frame }
        set { mac.frame = newValue }
    }
    var parked: Bool {
        get { mac.parked }
        set { mac.parked = newValue }
    }

    /// The window's box in its tile: mango's geom without the border.
    var tile: CGRect { geom.insetBy(dx: bw, dy: bw) }

    var element: AXUIElement {
        get { mac.element }
        set { mac.element = newValue }
    }
}
