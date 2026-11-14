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
    /// wlr_seat_keyboard_notify_clear_focus.
    func keyboardNotifyClearFocus()
    func warp(to p: CGPoint)
    func restack()
    func drawBorders(_ specs: [BorderSpec])
    func drawTabBars(_ strips: [TabStrip], style: TabStripStyle)
    func drawGroupBars(_ strips: [TabStrip], style: TabStripStyle)
    var windowCornerRadius: CGFloat { get }
    func showOverview(_ cards: [OverviewCard], on m: Monitor, look: OverviewLook)
    func updateOverview(_ cards: [OverviewCard])
    func captureOverviewCards(scale: CGFloat)
    func closeOverview()
    func showJumpLabels(_ labels: [(String, CGRect)], look: DecorateStyle)
    func closeJumpLabels()
    func showSwitcher(panel: CGRect, tiles: [SwitcherTile], look: SwitcherLook, scale: CGFloat)
    func switcherApplyHighlight(_ tiles: [SwitcherTile])
    func closeSwitcherPanel()
    /// mango_bar_decoration_create for the title message bar: its type and its layer
    /// (LyrSpecialOverlay, ignoring hits) are the port's.
    func mangoBarDecorationCreate(_ m: Monitor, _ data: DecorateStyle, _ width: CGFloat, _ height: CGFloat) -> MangoBarDecoration?
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
    func cancelAnimation(_ id: ClientID)
    func animatedFrame(_ id: ClientID) -> CGRect?
    func whenAnimationsIdle(_ body: @escaping () -> Void)
    func clientAnimationRunning(_ c: Client) -> Bool
    func clientAnimationSetProgress(_ c: Client, _ p: Double)
    func clientAnimationResume(_ c: Client, _ remaining: Double)
    var canCapture: Bool { get }
    func askToCapture()
    func keyboardHardModifiers() -> Modifiers
    var screens: [Screen] { get }
    func setKeyboardOptions(_ options: String)
    func ipcGetLayoutStr() -> String
    var mouseButtons: Int { get }
    func startInput()
    func watchGestures(_ on: Bool)
    func keyboardCancelPendingReleaseBind()
    func publishInput(_ state: InputState)
    func publishGlobalKeys(_ keys: [GlobalKey])
    func resize(_ placements: [(Client, CGRect)], _ anim: ArrangeAnimation, rising: Set<ClientID>)
    func resize(_ c: Client, to frame: CGRect, _ anim: ArrangeAnimation, cover: CGRect?, now: CGRect?)
    func hide(_ c: Client)
    func hide(_ c: Client, tagout: TagoutAnimation)
    func settle(_ c: Client)
    func setFrame(_ c: Client, _ frame: CGRect, size: Bool)
    func readFrame(_ c: Client, _ done: @escaping @MainActor (CGRect?) -> Void)
    func clientSendClose(_ c: Client)
    func clientNotifyFullscreen(_ c: Client, _ fullscreen: Bool)
    func keepOnDisplay(_ frame: CGRect, _ m: Monitor) -> CGRect
    func grabBegan(_ c: Client)
    func grabEnded(_ c: Client)
}

package extension WindowSystem {
    func resize(_ c: Client, to frame: CGRect, _ anim: ArrangeAnimation) {
        resize(c, to: frame, anim, cover: nil, now: nil)
    }
}
