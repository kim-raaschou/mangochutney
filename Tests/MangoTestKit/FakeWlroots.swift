import CoreGraphics
import Foundation
@testable import Mango

/// wlroots' part of a client: its scene node and its surface.
@MainActor
package final class FakeSurface: PlatformWindow {
    package var frame: CGRect
    package let isFloatType: Bool
    package var sceneNodeEnabled = true
    package var sceneSurfaceEnabled = true
    /// The xdg toplevel's min and max size.
    package var sizeHints = ClientSizeHints()
    /// The size mango configured, which the client takes when it commits (TestMango.frame).
    package var configured: CGSize?

    package init(frame: CGRect, isFloatType: Bool) {
        self.frame = frame
        self.isFloatType = isFloatType
    }
}

/// wlroots as mango's tests see it. It draws nothing and moves nothing: it does what mango asks
/// and remembers it, so a test can look afterwards.
@MainActor
package final class FakeWlroots: WindowSystem {
    package unowned let server: MangoServer
    package var screens: [Screen]

    package init(_ server: MangoServer, screens: [Screen]) {
        self.server = server
        self.screens = screens
    }

    // MARK: The seat

    package var pointer = CGPoint(x: 1, y: 1)
    package private(set) var warps: [CGPoint] = []
    package func warp(to p: CGPoint) {
        warps.append(p)
        pointer = p
    }

    private var keyboardFocus: Client?
    /// A surface that is gone has no focus, as wlroots clears it when the surface is destroyed.
    package var keyboardFocusedSurface: Client? {
        keyboardFocus.flatMap { server.clientByIdAll($0.id) === $0 ? $0 : nil }
    }
    package func clientNotifyEnter(_ c: Client) { keyboardFocus = c }
    package func keyboardNotifyClearFocus() { keyboardFocus = nil }

    package private(set) var pointerFocusedSurface: ClientID?
    package func seatPointerNotifyEnter(_ surface: ClientID) { pointerFocusedSurface = surface }
    package func seatPointerClearFocus() { pointerFocusedSurface = nil }

    /// The surface under the pointer, as the test sets it.
    package var surfaceUnderPointer: ClientID?
    /// The scene's stacking, bottom first: a client mapped goes on top, a raise moves it there.
    package var stacking: [ClientID] = []
    /// The topmost shown surface under `p` (wlr_scene_node_at): the highest layer, and in it the last
    /// raised; unless the test sets one.
    package func surfaceAt(_ p: CGPoint) -> ClientID? {
        if let surfaceUnderPointer { return surfaceUnderPointer }
        let hits = stacking.enumerated().compactMap { i, id -> (layer: Int, i: Int, id: ClientID)? in
            guard let c = server.clientByIdAll(id), c.platform.sceneNodeEnabled,
                  surface(c).frame.insetBy(dx: -c.bw, dy: -c.bw).contains(p) else { return nil }
            return (server.clientTargetLayer(c).rawValue, i, id)
        }
        return hits.max { ($0.layer, $0.i) < ($1.layer, $1.i) }?.id
    }

    /// The bar segment under `p`, as the scene finds a group or tab bar's node.
    package func barAt(_ p: CGPoint) -> BarButton? {
        for (strips, isTab) in [(tabBars, true), (groupBars, false)] {
            for strip in strips {
                if let s = strip.segments.first(where: { $0.frame.contains(p) }) {
                    return BarButton(client: ClientID(s.id), isTab: isTab, onClose: false)
                }
            }
        }
        return nil
    }

    package private(set) var activated: Set<ClientID> = []
    package func clientActivateSurface(_ c: Client, _ activated: Bool) {
        if activated { self.activated.insert(c.id) } else { self.activated.remove(c.id) }
    }

    package var modifiers: Modifiers = []
    package func keyboardHardModifiers() -> Modifiers { modifiers }

    // MARK: The scene

    package func sceneNodeSetEnabled(_ c: Client, _ enabled: Bool) { surface(c).sceneNodeEnabled = enabled }
    package func sceneSurfaceSetEnabled(_ c: Client, _ enabled: Bool) { surface(c).sceneSurfaceEnabled = enabled }
    /// The surface stands inside the border of the node mango placed (wlr_scene_node_set_position).
    package func sceneNodeSetPosition(_ c: Client, _ x: CGFloat, _ y: CGFloat) {
        surface(c).frame.origin = CGPoint(x: x + c.bw, y: y + c.bw)
    }
    package func sceneSubsurfaceTreeSetClip(_ c: Client, _ clip: CGRect) {}

    package private(set) var borders: [BorderSpec] = []
    package func drawBorders(_ specs: [BorderSpec]) { borders = specs }

    package private(set) var tabBars: [TabStrip] = []
    package private(set) var groupBars: [TabStrip] = []
    package func drawTabBars(_ strips: [TabStrip], style: TabStripStyle) { tabBars = strips }
    package func drawGroupBars(_ strips: [TabStrip], style: TabStripStyle) { groupBars = strips }

    /// The monitors mango asked to draw a frame on (wlr_output_schedule_frame).
    package private(set) var framesDue: Set<CGDirectDisplayID> = []
    package func outputScheduleFrame(_ m: Monitor) { framesDue.insert(m.screen.displayID) }
    package func takeFramesDue() -> Set<CGDirectDisplayID> {
        defer { framesDue.removeAll() }
        return framesDue
    }

    // MARK: Clients

    package var closed: [ClientID] = []
    package func clientSendClose(_ c: Client) { closed.append(c.id) }

    package private(set) var spawned: [String] = []
    package func spawn(_ command: String) { spawned.append(command) }
    /// The commands run through the shell (spawn_shell), also in `spawned`.
    package private(set) var shelled: [String] = []
    package func spawnShell(_ command: String) { spawned.append(command); shelled.append(command) }

    /// The xdg toplevel's parent, as the test sets it.
    package var parents: [ClientID: ClientID] = [:]
    package func clientGetParent(_ c: Client) -> Client? { parents[c.id].flatMap { server.clientByIdAll($0) } }
    package func toplevelFromWlrSurface(_ surface: ClientID) -> Client? { server.clientByIdAll(surface) }
    /// The size mango configures (xdg_toplevel configure); the client takes it when it commits, after
    /// mango's turn (TestMango.frame), as the facit client does.
    package func clientSetSize(_ c: Client, _ width: CGFloat, _ height: CGFloat, _ forceConfigure: Bool) -> UInt32 {
        surface(c).configured = CGSize(width: width, height: height)
        return 0
    }

    /// The clients commit the sizes they were configured to.
    package func commitConfigured() {
        for c in server.clientsAll {
            guard let s = c.platform as? FakeSurface, let size = s.configured else { continue }
            s.frame.size = size
            s.configured = nil
        }
    }
    package func clientGetGeometry(_ c: Client) -> CGRect { CGRect(origin: .zero, size: surface(c).frame.size) }
    package func sceneSurfaceCoords(_ c: Client) -> CGPoint { surface(c).frame.origin }
    package func clientSizeHints(_ c: Client) -> ClientSizeHints { (c.platform as? FakeSurface)?.sizeHints ?? ClientSizeHints() }
    package func clientSetMinimized(_ c: Client, _ minimizeWindow: Bool) {}
    package func clientNotifyFullscreen(_ c: Client, _ fullscreen: Bool) {}
    package func readFrame(_ c: Client, _ done: @escaping @MainActor (CGRect?) -> Void) { done(c.geom) }
    package func raise(_ c: Client) {
        stacking.removeAll { $0 == c.id }
        stacking.append(c.id)
    }
    package func restack() {}
    package func settle(_ c: Client) {}
    package func grabBegan(_ c: Client) {}
    package func grabEnded(_ c: Client) {}

    // MARK: What the tests of mango do not draw

    package var windowCornerRadius: CGFloat { 0 }
    package func showOverview(_ cards: [OverviewCard], on m: Monitor, look: OverviewLook) {}
    package func updateOverview(_ cards: [OverviewCard], on m: Monitor) {}
    package func captureOverviewCards(on m: Monitor, scale: CGFloat) {}
    package func closeOverview(on m: Monitor) {}
    package func showSwitcher(panel: CGRect, tiles: [SwitcherTilePicture], look: SwitcherLook, scale: CGFloat) {}
    package func switcherApplyHighlight(_ tiles: [SwitcherTilePicture]) {}
    package func closeSwitcherPanel() {}
    package func mangoBarDecorationCreate(_ m: Monitor, _ data: DecorateStyle, _ width: CGFloat, _ height: CGFloat) -> MangoBarDecoration? { nil }
    package func mangoJumpLabelNodeCreate(_ c: Client, _ data: DecorateStyle) -> MangoJumpLabel? { nil }
    /// xkb's keymap (us): the key that gives the character.
    package func findKeycodesForKeysym(_ keysym: Character) -> MultiKeycode { MultiKeycode(keycode1: FakeKeymap.code(String(keysym))) }
    package func showSpecialDim(on m: Monitor, alpha: Float?, over: Set<ClientID>) {}
    package func showDropArea(_ area: CGRect?, color: RGBA) {}
    package func nagSpawn(_ argv: [String], input: String) {}
    package func nagKill() {}
    package func setCursorHidden(_ hidden: Bool) {}
    package func setCursor(_ name: String?) {}

    // MARK: The server's life

    package let eventLoop: EventLoop = FakeEventLoop()
    package func quit() {}
    package func prepare() {}
    package func startWatching() {}
    package func shutdown() {}
    package func rescan() {}
    package var canCapture: Bool { false }
    package func askToCapture() {}
    package func setKeyboardOptions(_ options: String) {}
    package func ipcGetLayoutStr() -> String { "English (US)" }   // xkb's name of the us layout
    package var inputDevices: [InputDevice] { [] }
    package var mouseButtons: Int { 0 }
    package func startInput() {}
    package func watchGestures(_ on: Bool) {}
    package func keyboardCancelPendingReleaseBind() {}
    /// What mango last told the event tap: its keymode and bindings.
    package private(set) var input = InputState()
    package func publishInput(_ state: InputState) { input = state }
    package func publishGlobalKeys(_ keys: [GlobalKey]) {}

    private func surface(_ c: Client) -> FakeSurface { c.platform as! FakeSurface }
}

/// wl_event_loop: its timers and fds are kept, and nothing fires on its own.
@MainActor
package final class FakeEventLoop: EventLoop {
    private final class Source: EventSource {
        func remove() {}
        func timerUpdate(_ msDelay: Int32) {}
    }
    package func addFd(_ fd: Int32, _ readable: @escaping @MainActor () -> Void) -> EventSource { Source() }
    package func addTimer(_ fire: @escaping @MainActor () -> Void) -> EventSource { Source() }
}
