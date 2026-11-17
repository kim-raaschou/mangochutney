import Foundation
import CoreGraphics

@MainActor
package protocol WindowSystem: AnyObject {
    var pointer: CGPoint { get }
    func quit()
    /// wlroots' seat->keyboard_state.focused_surface: the client mango last gave the keyboard.
    var keyboardFocusedSurface: Client? { get }
    /// client_notify_enter (wlr_seat_keyboard_notify_enter).
    func clientNotifyEnter(_ c: Client)
    /// client_activate_surface.
    func clientActivateSurface(_ c: Client, _ activated: Bool)
    /// client_get_parent: the client this one is a child of.
    func clientGetParent(_ c: Client) -> Client?
    /// toplevel_from_wlr_surface: the client a surface (a window, or a popup over one) belongs to.
    func toplevelFromWlrSurface(_ surface: ClientID) -> Client?
    /// wlr_seat_keyboard_notify_clear_focus.
    func keyboardNotifyClearFocus()
    func warp(to p: CGPoint)
    /// wlroots' seat->pointer_state.focused_surface: the surface mango last gave the pointer.
    var pointerFocusedSurface: ClientID? { get }
    /// wlr_seat_pointer_notify_enter.
    func seatPointerNotifyEnter(_ surface: ClientID)
    /// wlr_seat_pointer_notify_clear_focus and wlr_seat_pointer_clear_focus.
    func seatPointerClearFocus()
    func restack()
    func drawBorders(_ specs: [BorderSpec])
    func drawTabBars(_ strips: [TabStrip], style: TabStripStyle)
    func drawGroupBars(_ strips: [TabStrip], style: TabStripStyle)
    var windowCornerRadius: CGFloat { get }
    func showOverview(_ cards: [OverviewCard], on m: Monitor, look: OverviewLook)
    func updateOverview(_ cards: [OverviewCard], on m: Monitor)
    func captureOverviewCards(on m: Monitor, scale: CGFloat)
    func closeOverview(on m: Monitor)
    func showSwitcher(panel: CGRect, tiles: [SwitcherTile], look: SwitcherLook, scale: CGFloat)
    func switcherApplyHighlight(_ tiles: [SwitcherTile])
    func closeSwitcherPanel()
    /// mango_bar_decoration_create for the title message bar: its type and its layer
    /// (LyrSpecialOverlay, ignoring hits) are the port's.
    func mangoBarDecorationCreate(_ m: Monitor, _ data: DecorateStyle, _ width: CGFloat, _ height: CGFloat) -> MangoBarDecoration?
    /// mango_jump_label_node_create on the client's scene.
    func mangoJumpLabelNodeCreate(_ c: Client, _ data: DecorateStyle) -> MangoJumpLabel?
    /// find_keycodes_for_keysym on xkb's keymap: the keys that type this character.
    func findKeycodesForKeysym(_ keysym: Character) -> MultiKeycode
    func showSpecialDim(on m: Monitor, alpha: Double?, over: Set<ClientID>)
    func showDropArea(_ area: CGRect?, color: RGBA)
    func nagSpawn(_ argv: [String], input: String)
    func nagKill()
    func setCursorHidden(_ hidden: Bool)
    func setCursor(_ name: String?)
    func surfaceAt(_ p: CGPoint) -> ClientID?
    func raise(_ c: Client)
    func clientSetMinimized(_ c: Client, _ minimizeWindow: Bool)
    func prepare()
    func startWatching()
    func shutdown()
    var eventLoop: EventLoop { get }
    func rescan()
    func spawn(_ command: String)
    func spawnShell(_ command: String)
    /// client_set_size: the size the window is to have, without the border; the configure serial.
    func clientSetSize(_ c: Client, _ width: CGFloat, _ height: CGFloat, _ forceConfigure: Bool) -> UInt32
    /// The toplevel's min and max size (toplevel->current), 0 where it has none.
    func clientSizeHints(_ c: Client) -> ClientSizeHints
    /// wlr_scene_node_set_position on the client's scene: where its box (with the border) stands.
    func sceneNodeSetPosition(_ c: Client, _ x: CGFloat, _ y: CGFloat)
    /// wlr_scene_subsurface_tree_set_clip on the client's surface.
    func sceneSubsurfaceTreeSetClip(_ c: Client, _ clip: CGRect)
    /// wlr_scene_node_set_enabled on the client's scene.
    func sceneNodeSetEnabled(_ c: Client, _ enabled: Bool)
    /// wlr_scene_node_set_enabled on the client's surface.
    func sceneSurfaceSetEnabled(_ c: Client, _ enabled: Bool)
    /// wlr_output_schedule_frame: the port calls handleOutputFrame(m) on the monitor's next frame.
    func outputScheduleFrame(_ m: Monitor)
    var canCapture: Bool { get }
    func askToCapture()
    func keyboardHardModifiers() -> Modifiers
    var screens: [Screen] { get }
    func setKeyboardOptions(_ options: String)
    func ipcGetLayoutStr() -> String
    /// server.input_devices.
    var inputDevices: [InputDevice] { get }
    var mouseButtons: Int { get }
    func startInput()
    func watchGestures(_ on: Bool)
    func keyboardCancelPendingReleaseBind()
    func publishInput(_ state: InputState)
    func publishGlobalKeys(_ keys: [GlobalKey])
    func settle(_ c: Client)
    func setFrame(_ c: Client, _ frame: CGRect, size: Bool)
    func readFrame(_ c: Client, _ done: @escaping @MainActor (CGRect?) -> Void)
    func clientSendClose(_ c: Client)
    func clientNotifyFullscreen(_ c: Client, _ fullscreen: Bool)
    func grabBegan(_ c: Client)
    func grabEnded(_ c: Client)
}

/// The toplevel's min and max size (wlr_xdg_toplevel_state's min_width … max_height).
public struct ClientSizeHints {
    public var minWidth: CGFloat = 0, minHeight: CGFloat = 0, maxWidth: CGFloat = 0, maxHeight: CGFloat = 0
    public init() {}
}
