import Foundation
import CoreGraphics

/// What mango's code asks of the system it runs on, where mango asks wlroots
/// (docs/plan-kerne-backend.md, "Grænsen"). The port answers on macOS (MacWindowSystem);
/// more of mango's calls move behind it step by step.
@MainActor
package protocol WindowSystem: AnyObject {
    /// Where the pointer is (AX coordinates, y down).
    var pointer: CGPoint { get }
    /// mango quit (bind.c).
    func quit()
    /// mango client_activate_surface and client_notify_enter (manage/client.c).
    /// The window gets the keyboard (client_focus, wlr_seat_keyboard_notify_enter);
    /// `raise`: and comes to the front.
    func focus(_ c: Client, raise: Bool)
    /// Not in mango: the port's side (wlr_cursor_warp_closest).
    /// The pointer put at `p` (wlr_cursor_warp_closest).
    func warp(to p: CGPoint)
    /// What mango draws with the windows (borders, bars) back above them: their stacking
    /// changed.
    func restack()
    /// mango client_draw_border (animation/client.c).
    /// The windows' borders, as they are now (all of them; an empty list removes them).
    func drawBorders(_ specs: [BorderSpec])
    /// mango global_draw_tab_bar (tab.c).
    /// The tab bars and the group bars, as they are now.
    /// mango's tab bars were refreshed (tab_refresh_bars), drawn or not: the port's tab keys
    /// follow them (chutney_tab_bar_shortcuts).
    func tabBarsChanged()
    func drawTabBars(_ strips: [TabStrip], style: TabStripStyle)
    /// mango global_draw_group_bar (animation/client.c).
    func drawGroupBars(_ strips: [TabStrip], style: TabStripStyle)
    /// The corner radius of the system's windows (the bars' corners follow it).
    var windowCornerRadius: CGFloat { get }
    /// mango overview_layout_card (overview/overview.c), for every card.
    /// The overview drawn as pictures over `m`'s work area.
    func showOverview(_ cards: [OverviewCard], on m: Monitor, look: OverviewLook)
    /// mango overview_layout_card (overview/overview.c), the cards redrawn.
    func updateOverview(_ cards: [OverviewCard])
    /// mango overview_card_surface_add (overview/overview.c).
    func captureOverviewCards(scale: CGFloat)
    /// mango overview_destroy_card (overview/overview.c), for every card.
    func closeOverview()
    /// mango create_jump_hints (layout/overview.c), its label nodes.
    /// The jump labels (togglejump) on their cards.
    func showJumpLabels(_ labels: [(String, CGRect)], look: DecorateStyle)
    /// mango finish_jump_mode (layout/overview.c).
    func closeJumpLabels()
    /// mango switcher_tile_create (switcher.c), with the panel.
    /// mango's switcher panel; `highlightSwitcher` moves only the highlight.
    func showSwitcher(panel: CGRect, tiles: [SwitcherTile], look: SwitcherLook, scale: CGFloat)
    /// mango switcher_apply_highlight (switcher.c).
    func highlightSwitcher(_ tiles: [SwitcherTile])
    /// mango switcher_close (switcher.c), its scene part.
    func closeSwitcherPanel()
    /// mango title_message_bar_set_text and title_message_bar_update_geometry (title_message_bar.c).
    /// mango's title message bar.
    func showTitleMessageBar(frame: CGRect, title: String, appid: String, look: DecorateStyle)
    /// mango title_message_bar_hide (title_message_bar.c).
    func hideTitleMessageBar()
    /// mango special_update_dim (monitor.c).
    /// mango's special_dim over `m`, under the windows `over`; nil `alpha` hides it.
    func showSpecialDim(on m: Monitor, alpha: Double?, over: Set<ClientID>)
    /// mango client_set_drop_area (animation/client.c), its scene part.
    /// mango's drop area (drag_tile_to_tile); nil hides it.
    func showDropArea(_ area: CGRect?, color: RGBA)
    /// mango config_error_nag_update (error_nag.c).
    /// mango's error_nag for config errors; empty hides it.
    func showConfigErrors(_ errors: [ConfigError], configURL: URL)
    /// mango pointer_hide_cursor and pointer_cursor_activity (pointer.c), the cursor image.
    /// The pointer hidden (cursor_hide_timeout, cursor_hide_on_keypress) or shown.
    func setCursorHidden(_ hidden: Bool)
    /// wlroots wlr_cursor_set_xcursor: the cursor image by its xcursor name; nil gives the
    /// cursor back to the window under it (wlr_seat_pointer_clear_focus).
    func setCursor(_ name: String?)
    /// wlroots wlr_scene_node_at, its surface: the window under `p`; nil where mango has none.
    func surfaceAt(_ p: CGPoint) -> ClientID?
    /// Not in mango: the port's side (wlr_scene_node_raise_to_top).
    /// A window to the front (wlr_scene_node_raise_to_top).
    func raise(_ c: Client)
    /// Not in mango: the port's side. A window macOS minimized (the Dock) shown again
    /// (mango's unminimize, client.c, is the scratchpad's and is not this).
    func unminimize(_ c: Client)
    /// Before mango reads its config: the port's extensions register, the system is set up.
    func prepare()
    /// Not in mango: the port's side (window events, as setup's listeners).
    /// The system starts reporting windows (mango's handlers) and animating.
    func startWatching()
    /// mango quits: windows hidden by the system are shown again, and the apps get their
    /// own settings back.
    func shutdown()
    /// The event loop mango's IPC hands its sockets to (wl_event_loop).
    var eventLoop: EventLoop { get }
    /// Not in mango: the port's side (looks for windows again).
    /// The windows are looked for again (a dispatch on a window not known yet).
    func rescan()
    /// mango spawn (bind.c).
    /// mango spawn (a command) and spawn_shell (through the shell).
    func spawn(_ command: String)
    /// mango spawn_shell (bind.c).
    func spawnShell(_ command: String)
    /// mango config_watcher_update (watcher.c).
    /// auto_reload_config: these files are watched (none: not watched); a change reloads.
    func watchConfig(_ files: [URL])
    /// Not in mango: the port's side (stops a window's animation).
    /// The animations: one stopped, where a window is shown during one, a call once all
    /// have ended, and a live gesture holding them at a point (hold, progress, resume or
    /// let go).
    func cancelAnimation(_ id: ClientID)
    /// Not in mango: the port's side (c->animation.current).
    func animatedFrame(_ id: ClientID) -> CGRect?
    /// Not in mango: the port's side (a call once animations end).
    func whenAnimationsIdle(_ body: @escaping () -> Void)
    var animationsActive: Bool { get }
    /// mango swipe_drive_freeze (trackpad.c).
    func holdAnimations()
    /// mango client_animation_set_progress (animation/client.c).
    func setAnimationProgress(_ p: Double)
    /// mango client_animation_resume (animation/client.c).
    func resumeAnimations(from p: Double)
    /// mango swipe_drive_unfreeze (trackpad.c).
    func letGoAnimations()
    /// Pictures of windows can be taken (the overview's cards); `askToCapture` asks the
    /// user once.
    var canCapture: Bool { get }
    /// Not in mango: the port's side (macOS screen capture permission).
    func askToCapture()
    /// The modifier keys held now.
    var modifiers: Modifiers { get }
    /// The displays (mango's outputs), as they are now.
    var screens: [Screen] { get }
    /// Not in mango: the port's side (the window server's windows).
    /// Every window the window server has now (any app, any state).
    func allWindowIDs() -> Set<ClientID>
    /// mango's xkb_rules_options applied to the keyboard (empty: none).
    func setKeyboardOptions(_ options: String)
    /// The keyboard layout's name (IPC's keyboard_layout).
    var keyboardLayout: String { get }
    /// The mouse buttons held now (bit 0: left).
    var mouseButtons: Int { get }
    /// Not in mango: the port's side (event tap for keys, mouse, trackpad).
    /// Input starts: keys, mouse and trackpad come to mango's handlers.
    func startInput()
    /// Not in mango: the port's side (trackpad swipes watched).
    /// mango's gesturebind: trackpad swipes are watched (only while some are bound).
    func watchGestures(_ on: Bool)
    /// mango keyboard_cancel_pending_release_bind (keyboard.c): the key held now no longer
    /// fires a release bind (a swipe began). The port's input router keeps the last key.
    func keyboardCancelPendingReleaseBind()
    /// Not in mango: the port's side (state for the event tap).
    /// What input needs from mango, and the global_key_binding keys with their windows.
    func publishInput(_ state: InputState)
    /// Not in mango: the port's side (global_key_binding keys for the event tap).
    func publishGlobalKeys(_ keys: [GlobalKey])
    /// mango resize (animation/client.c).
    /// mango's resize_client for a monitor's windows, animated per `anim`. Where they go
    /// is mango's; how they get there (covered windows, writes the app did not take,
    /// sizes it refuses) is the system's. `rising`: windows raised as they are placed.
    func resize(_ placements: [(Client, CGRect)], _ anim: ArrangeAnimation, rising: Set<ClientID>)
    /// mango resize (animation/client.c), the port's side: one window's resize_client, drawn
    /// with the animation mango's clientAnimation decides.
    func resize(_ c: Client, to frame: CGRect, _ anim: ArrangeAnimation, cover: CGRect?, now: CGRect?)
    /// mango set_arrange_hidden (tag.c).
    /// A window on a tag not in view hidden (show_hide_client).
    func hide(_ c: Client)
    /// mango set_tagout_animation's resize, the port's side: the window slides to `tagout.to`
    /// and is hidden at the end (unless it is shown again meanwhile: `c.tagouting` cleared).
    func hide(_ c: Client, tagout: TagoutAnimation)
    /// Not in mango: the port's side (keeps a hidden window hidden).
    /// A hidden window seen at `actual` (nil: unknown): it stays hidden.
    func keepHidden(_ c: Client, seenAt actual: CGRect?)
    /// A tiled window its app moved off `target`: put back where mango has it.
    func keepPlaced(_ c: Client, at target: CGRect)
    /// Where a window ended after a move mango did not place (a dropped grab) is taken.
    func settle(_ c: Client)
    /// Not in mango: the port's side (places a window at once).
    /// A window put at `frame` now, no animation (`size`: its size too).
    func setFrame(_ c: Client, _ frame: CGRect, size: Bool)
    /// Not in mango: the port's side (reads a frame back from the app).
    /// Where a window really is, read back from its app (nil: no answer).
    func readFrame(_ c: Client, _ done: @escaping @MainActor (CGRect?) -> Void)
    /// mango client_send_close (manage/client.c).
    /// A window asked to close (mango's killclient, politely).
    func clientSendClose(_ c: Client)
    /// Not in mango: the port's side (macOS shows a window on one display).
    /// A floating window's frame as `m`'s display can hold it.
    func keepOnDisplay(_ frame: CGRect, _ m: Monitor) -> CGRect
    /// Not in mango: the port's side (the app's own move reports while mango moves it).
    /// A grab on the window began, and ended.
    func grabBegan(_ c: Client)
    func grabEnded(_ c: Client)
}

package extension WindowSystem {
    /// mango resize (animation/client.c).
    func resize(_ c: Client, to frame: CGRect, _ anim: ArrangeAnimation) {
        resize(c, to: frame, anim, cover: nil, now: nil)
    }
}
