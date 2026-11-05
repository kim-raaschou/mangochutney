import AppKit
import Mango

/// WindowSystem on macOS: Accessibility for other apps' windows, the window server for
/// the pointer, ScreenCaptureKit for pictures.
@MainActor
class MacWindowSystem: WindowSystem {
    unowned let server: MangoServer
    /// While mango's own menu is open, making another app frontmost would close it:
    /// native focus changes wait until the menu closes.
    var holdFocus = false {
        didSet {
            guard !holdFocus, oldValue, let c = heldFocus else { return }
            heldFocus = nil
            if server.clientByIdAll(c.id) === c { focus(c, raise: true) }
        }
    }
    var heldFocus: Client?
    private var pendingFocus: (client: Client, raise: Bool)?
    var initialSettlePending = false
    /// Windows macOS has away (AwayWindows.swift), unmapped from mango until they are back.
    var away: [ClientID: (client: Client, reasons: Set<AwayReason>)] = [:]
    var loggedWindowCount = -1
    var restackGeneration = 0
    /// The borders, one panel per window (Borders.swift).
    let borders = BorderManager()
    /// Not in mango: windows that leave and come back, and the layout kept across a restart.
    let memory = WindowMemory()
    /// A drag the app itself does (UserDrag.swift), and the window under a plain left press
    /// with its window-server frame then: a drag follows it from the window server, for
    /// apps that send no move notifications.
    var userDrag: UserDrag?
    /// chutney_restart: a new mango takes over at once, so hidden windows stay hidden.
    var restarting = false
    var opacityWarned = false
    var dispatchersWarned = Set<String>()
    /// chutney_focus_app's "used last": the windows that have had the focus, most recent
    /// first (mango's focus_stack takes a window as it maps, focused or not).
    var focusHistory: [ClientID] = []
    var pressed: (client: Client, frame: CGRect)?
    /// Port extension (chutney_tab_bar_shortcuts): ⌘ alone is held, so the tabs show their
    /// numbers; and how many tabs the event tap last learned ⌘1-9 picks (TabShortcuts.swift).
    var tabNumbersShown = false
    var publishedTabShortcuts = 0
    /// The tab bars and mango's group bars, drawn alike (TabBars.swift).
    let tabBars = TabBarManager()
    let groupBars = TabBarManager()
    /// The overview as pictures, its jump labels, mango's switcher panel, title message
    /// bar, special dims (one per display), drop area and error nag.
    var overviewOverlay: OverviewOverlay?
    var jumpLabels: JumpLabelSet?
    var switcherPanel: SwitcherPanel?
    var titleBar: TitleMessageBar?
    var specialDims: [CGDirectDisplayID: SpecialDimView] = [:]
    var dropArea: DropAreaView?
    let nag = Nag()
    /// Keys and mouse on the tap's own thread, decided by the router there; the trackpad.
    let tap = EventTap()
    let router = InputRouter()
    let gestures = GestureRecognizer()
    /// Tests answer for the window server.
    var windowServerOverride: ((CGWindowID) -> CGRect?)?
    /// Other apps' windows (one thread per app), the animations, Mission Control, the
    /// main-thread watchdog (-d) and the config file watcher.
    let watcher = AppWatcher()
    let animator = Animator()
    let watchdog = MainThreadWatchdog()
    let missionControl = MissionControl()
    var configWatcher: ConfigWatcher?
    /// Tests write to a fake app, and answer for the window server's stacking.
    var writerOverride: ((pid_t) -> (any WindowWriter)?)?
    var stackingOverride: (() -> [StackedWindow])?

    /// The queue that writes to `pid`'s windows.
    func writer(for pid: pid_t) -> (any WindowWriter)? {
        if let writerOverride { return writerOverride(pid) }
        return watcher.writeQueue(for: pid)
    }

    func stackingOrder() -> [StackedWindow] {
        stackingOverride?() ?? AppWorker.stackingOrder()
    }
    var lockObservers: [NSObjectProtocol] = []

    init(_ server: MangoServer) {
        self.server = server
        // A press on a bar's segment goes to mango's pointer_process_button_press, as the bar node.
        tabBars.onSelect = { [weak self] id in self?.barPress(id, isTab: true, right: false, onClose: false) }
        tabBars.onRightClick = { [weak self] id in self?.barPress(id, isTab: true, right: true, onClose: false) }
        groupBars.onSelect = { [weak self] id in self?.barPress(id, isTab: false, right: false, onClose: false) }
        groupBars.onRightClick = { [weak self] id in self?.barPress(id, isTab: false, right: true, onClose: false) }
        groupBars.onClose = { [weak self] id in self?.barPress(id, isTab: false, right: false, onClose: true) }
    }

    var pointer: CGPoint { Screens.mouseLocation }

    let eventLoop: EventLoop = MainEventLoop()

    func quit() { NSApp.terminate(nil) }

    /// mango's client_focus sets the seat's focus; on macOS focus is a request to the window
    /// server and the app, waited for on the main thread. One dispatcher often focuses twice
    /// (the view's top window, then the window), so the request goes once, at the end of the
    /// turn, for the last window focused.
    func focus(_ c: Client, raise: Bool) {
        if holdFocus { Log.debug("focus: mango focuses \(c.appName) \(c.id), held (a menu or palette is open)"); heldFocus = c; return }
        let first = pendingFocus == nil
        pendingFocus = (c, raise || (pendingFocus?.client === c && pendingFocus?.raise == true))
        guard first else { return }
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.sendFocus() } }
    }

    private func sendFocus() {
        guard let (c, raise) = pendingFocus else { return }
        pendingFocus = nil
        guard server.clientByIdAll(c.id) === c else { return }
        Log.debug("focus: mango focuses \(c.appName) \(c.id)\(raise ? ", raised" : "")")
        NativeFocus.focus(windowID: c.id, pid: c.pid, element: c.element, raise: raise) { [weak self] in self?.restack() }
    }

    /// Never before start() (drawsOverlays).
    func warp(to p: CGPoint) {
        guard server.drawsOverlays else { return }
        NativeFocus.warpCursor(to: p)
    }

    /// Borders back above their windows: on mango's focus and the app's own focus and
    /// activation notifications (windowFocused, appActivated call this), and once more a
    /// moment later for an app that reorders its windows after those (no event says the
    /// z-order changed; with -d, 54 of 711 found a border below its window by then). Only the
    /// front app's: an activation raises that app's windows, the others keep their order with
    /// their borders. Once the windows have stopped moving: an order waits for the window
    /// server to show what we sent it, and while borders move every frame that took 30 ms,
    /// just when an animation's first frames were due. A border is drawn around its window,
    /// so one left under its window for those 200 ms is still seen.
    func restack() { restack(pid: server.focused?.pid) }

    /// A press on a bar's segment: mango's pointer_process_button_press, with the bar as its node.
    func barPress(_ id: ClientID, isTab: Bool, right: Bool, onClose: Bool) {
        server.pointerProcessButtonPress(button: right ? 1 : 0, pressed: true, at: pointer, mods: modifiers,
                                         bar: BarButton(client: id, isTab: isTab, onClose: onClose))
    }

    func restack(pid: pid_t?) {
        guard let pid else { return }
        // On the next turn: mango's focus restacks before the arrange that starts its animation.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.animator.whenIdle { [weak self] in self?.restackNow(pid) } }
        }
    }

    private func restackNow(_ pid: pid_t, reserve: Bool = true) {
        let ids = Set(server.clientsAll.filter { $0.pid == pid }.map(\.id))
        // One look at the window server's order (2 ms) instead of an order per overlay (2 ms each):
        // an overlay is in place on its side of its window, with only mango's own between.
        let order = AppWorker.onScreenOrder()
        let at = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        let ours = Set(((NSApp as NSApplication?)?.windows ?? []).map { CGWindowID(truncatingIfNeeded: $0.windowNumber) })
        func inPlace(_ overlay: CGWindowID, _ target: CGWindowID, above: Bool) -> Bool {
            guard let o = at[overlay], let t = at[target], above ? o < t : o > t else { return false }
            return order[(min(o, t) + 1)..<max(o, t)].allSatisfy(ours.contains)
        }
        borders.restack(ids) { inPlace($0, $1, above: true) }
        tabBars.restack(ids) { inPlace($0, $1, above: false) }
        groupBars.restack(ids) { inPlace($0, $1, above: false) }
        for m in server.monitors where server.isSpecialActive(m) { server.specialUpdateDim(m) }
        guard reserve else { return }
        restackGeneration &+= 1
        let gen = restackGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.restackGeneration == gen else { return }
                self.restackNow(pid, reserve: false)
            }
        }
    }

    func drawBorders(_ specs: [BorderSpec]) {
        if specs.isEmpty { borders.removeAll() } else { borders.update(specs) }
    }

    func drawTabBars(_ strips: [TabStrip], style: TabStripStyle) {
        tabBars.update(withTabNumbers(strips), style: withAppIcons(style))
    }

    func drawGroupBars(_ strips: [TabStrip], style: TabStripStyle) { groupBars.update(strips, style: withAppIcons(style)) }

    var windowCornerRadius: CGFloat { BorderGeometry.cornerRadius }

    func showOverview(_ cards: [OverviewCard], on m: Monitor, look: OverviewLook) {
        overviewOverlay?.close()
        let overlay = OverviewOverlay(workArea: m.screen.workArea, focusColor: look.focusColor, borderColor: look.borderColor,
                                      jumpLook: look.jumpLook,
                                      mango: look.mango.map { .init(root: $0.root, borderWidth: $0.borderWidth, cornerRadius: $0.cornerRadius) })
        overviewOverlay = overlay
        overlay.show(cards.map(Self.card))
    }

    func updateOverview(_ cards: [OverviewCard]) { overviewOverlay?.update(cards.map(Self.card)) }

    func captureOverviewCards(scale: CGFloat) { overviewOverlay?.captureCards(scale: scale) }

    func closeOverview() {
        overviewOverlay?.close()
        overviewOverlay = nil
    }

    static func card(_ c: OverviewCard) -> OverviewOverlay.Card {
        .init(id: c.id, frame: c.frame, label: c.label, title: c.title, pid: c.pid, focused: c.focused)
    }

    func showJumpLabels(_ labels: [(String, CGRect)], look: DecorateStyle) {
        jumpLabels?.close()
        jumpLabels = JumpLabelSet(labels, look: look)
    }

    func closeJumpLabels() {
        jumpLabels?.close()
        jumpLabels = nil
    }

    func showSwitcher(panel: CGRect, tiles: [SwitcherTile], look: SwitcherLook, scale: CGFloat) {
        switcherPanel?.close()
        switcherPanel = SwitcherPanel(panel: panel, tiles: tiles.map(Self.tile),
                                      style: .init(focus: look.focus, border: look.border, macOS: look.macOS), scale: scale)
    }

    func highlightSwitcher(_ tiles: [SwitcherTile]) { switcherPanel?.highlight(tiles.map(Self.tile)) }

    func closeSwitcherPanel() {
        switcherPanel?.close()
        switcherPanel = nil
    }

    static func tile(_ t: SwitcherTile) -> SwitcherPanel.Tile {
        .init(id: t.id, frame: t.frame, size: t.size, pid: t.pid, highlighted: t.highlighted)
    }

    func showTitleMessageBar(frame: CGRect, title: String, appid: String, look: DecorateStyle) {
        if titleBar == nil { titleBar = TitleMessageBar() }
        titleBar?.show(frame: frame, title: title, appid: appid, style: look)
    }

    func hideTitleMessageBar() { titleBar?.hide() }

    /// Under the backmost of `over` in the window server's stacking.
    func showSpecialDim(on m: Monitor, alpha: Double?, over: Set<ClientID>) {
        let id = m.screen.displayID
        guard let alpha else { specialDims[id]?.hide(); return }
        let backmost = stackingOrder().last { over.contains($0.id) }?.id
        let view = specialDims[id] ?? SpecialDimView()
        specialDims[id] = view
        view.show(frame: m.screen.frame, alpha: alpha, below: backmost)
    }

    func showDropArea(_ area: CGRect?, color: RGBA) {
        guard let area else { dropArea?.hide(); return }
        if dropArea == nil { dropArea = DropAreaView() }
        dropArea?.show(area, color: color)
    }

    /// mangonag's bar, or the port's look over it (chutney_style).
    func showConfigErrors(_ errors: [ConfigError], configURL: URL) {
        if errors.isEmpty { nag.hide() } else { nag.show(errors: errors, configURL: configURL, macOS: server.config.chutneyStyle) }
    }

    /// The config was read (also on each setoption): what macOS cannot do is said once,
    /// each dispatcher the bindings use that does nothing here and the opacity
    /// (focused_opacity, unfocused_opacity: changing another process's window alpha needs
    /// SLSSetWindowAlpha from the Dock connection, which SIP blocks).
    func configLoaded(_ config: Config) {
        // One line per mango dispatcher the bindings use that does nothing on macOS.
        let used = config.keyBindings.map(\.dispatch.name) + config.mouseBindings.map(\.dispatch.name)
            + config.axisBindings.map(\.dispatch.name) + config.gestureBindings.map(\.dispatch.name)
        for name in used where dispatchersWarned.insert(name).inserted {
            if case (.unsupportedDispatcher, let why)? = ConfigParser.port?.dispatcherNote(name) {
                Log.info("config: \(name): \(why)")
            }
        }
        let wantsOpacity = config.focusedOpacity < 1 || config.unfocusedOpacity < 1
            || config.windowRules.contains { ($0.focusedOpacity ?? 1) < 1 || ($0.unfocusedOpacity ?? 1) < 1 }
        if wantsOpacity && !opacityWarned {
            opacityWarned = true
            Log.info("config: focused_opacity / unfocused_opacity are not supported on macOS and are ignored "
                     + "(changing another process's window alpha needs SLSSetWindowAlpha from the Dock connection, which SIP blocks)")
        }
    }

    var mouseButtons: Int { Int(NSEvent.pressedMouseButtons) }

    var keyboardLayout: String { KeyNames.currentLayoutName() }

    /// The key moves mango set (none: mango never touched the keyboard's mapping).
    var keyMappings: [KeyboardOptions.Mapping] = []
    /// The user's own key moves, read when mango first sets its own (hidutil's are global),
    /// without a key a mango before this one left on F18 (a crash); given back at the end.
    var userKeyMappings: [KeyboardOptions.Mapping]?
    /// The keyboard's whole mapping as it is now.
    var appliedKeyMappings: [KeyboardOptions.Mapping]?

    func setKeyboardOptions(_ options: String) {
        var m = KeyboardOptions.mappings(MangoServer.xkbOptions(options))
        // Port extension: not in mango (chutney_hyper_key), unless an xkb option moved that key.
        if let h = KeyboardOptions.hyperKeyMapping(server.config.chutneyHyperKey), !m.contains(where: { $0.src == h.src }) {
            m.append(h)
        }
        if userKeyMappings == nil {
            let now = KeyboardOptions.current() ?? []
            userKeyMappings = now.filter { $0.dst != KeyboardOptions.f18 }
            appliedKeyMappings = now
        }
        let all = KeyboardOptions.merged(user: userKeyMappings ?? [], mango: m)
        keyMappings = m
        guard all != appliedKeyMappings else { return }
        appliedKeyMappings = all
        KeyboardOptions.apply(all)
        if KeyboardOptions.takesCapsLock(m) { KeyboardOptions.capsLockOff() }
        Log.info(m.isEmpty ? "xkb_rules_options: the keyboard's key mapping cleared"
                           : "xkb_rules_options: \(m.count) key(s) moved")
    }

    func allWindowIDs() -> Set<ClientID> { AppWorker.allWindowIDs() }

    func prepare() {
        ChutneyTheme.sync(configURL: server.configURL)   // not in mango: chutney_style's colours, before the config is read
        server.registerPortExtensions()   // before the config is read: chutney_ignore_apps takes it
        AX.setGlobalTimeout()
        KeyNames.install()                     // mango's key names in the current keyboard layout
        _ = KeyNames.keyCodes(forName: "a")   // build the keyboard layout table on the main thread
    }

    func startWatching() {
        watcher.delegate = self
        watcher.start()
        // The Dock moved every window while it was up; put back whatever is off.
        missionControl.onExit = { [weak server] in server?.arrangeAll(.none) }
        missionControl.start()
        animator.onFrame = { [weak server] frames in server?.clientDrawFrame(frames) }
        if Log.verbose { watchdog.start() }   // diagnostics: a periodic ping, so only with -d
        Log.info("scanning \(watcher.apps.count) app(s)")
    }

    /// Every app mango wrote to gets its own settings back (AXEnhancedUserInterface).
    /// `done` is left once each app's queue has got that far (queues are serial).
    func restoreAppSettings(_ done: DispatchGroup) {
        for pid in Set(server.clientsAll.map(\.pid)) {
            guard let q = writer(for: pid) else { continue }
            q.restoreAppSettings()
            done.enter()
            q.async { done.leave() }
        }
    }

    func shutdown() {
        animator.cancelAll()
        // The keyboard as it was: the user's own moves, without mango's.
        if let user = userKeyMappings, appliedKeyMappings != user { KeyboardOptions.apply(user) }
        let restore = DispatchGroup()
        if restarting {
            Log.info("restarting: hidden windows stay hidden for the next mango")
            restoreAppSettings(restore)
            _ = restore.wait(timeout: .now() + 1)
            return
        }
        for c in server.clientsAll {
            guard let m = c.mon, c.parked || Hider.isParked(c.frame, in: m.screen.frame) else { continue }
            let f = c.isFloating ? c.floatGeom : (c.geom ?? c.floatGeom)
            // Written as every frame is, on the app's queue: it replaces a frame an animation
            // left waiting, and restoreAppSettings' mark on the queue comes after it.
            writer(for: c.pid)?.setFrame(c.element, id: c.id, frame: server.clampToScreen(f, m.screen.workArea))
        }
        restoreAppSettings(restore)   // after the restores on each app's queue
        // Restores run on the per-app queues in parallel; a hung app cannot hold up quit.
        _ = restore.wait(timeout: .now() + 2)
    }

    /// After the windows have moved: a scan asks every app for its windows, and an app answers
    /// accessibility requests one at a time, behind which an animation's moves would wait.
    func rescan() {
        animator.whenIdle { [weak self] in self?.watcher.refreshAll(recheckRejected: true) }
    }

    func spawn(_ command: String) { Spawn.run(command) }

    func spawnShell(_ command: String) { Spawn.shell(command) }

    func watchConfig(_ files: [URL]) {
        configWatcher = nil
        guard !files.isEmpty else { return }
        configWatcher = ConfigWatcher(files: files) { [weak server] changed in
            // Port extension: not in mango. The menu panel's own save (chutney_menu_config):
            // its value is already set, a reload would only arrange everything again.
            if changed.allSatisfy(MenuSave.isOwnWrite) { return }
            MainActor.assumeIsolated { server?.reloadConfig() }
        }
    }

    func cancelAnimation(_ id: ClientID) { animator.cancel(id) }
    func animatedFrame(_ id: ClientID) -> CGRect? { animator.shownRect(id) }
    func whenAnimationsIdle(_ body: @escaping () -> Void) { animator.whenIdle(body) }
    var animationsActive: Bool { animator.isActive }
    func holdAnimations() { animator.hold() }
    func setAnimationProgress(_ p: Double) { animator.setProgress(p) }
    func resumeAnimations(from p: Double) { animator.resume(from: p) }
    func letGoAnimations() { animator.letGo() }


    var screens: [Screen] { Screens.all() }

    /// See `AppWorker.windowServerFrame`.
    func windowServerFrame(_ id: ClientID) -> CGRect? {
        if let windowServerOverride { return windowServerOverride(id) }
        return AppWorker.windowServerFrame(id)
    }

    func startInput() {
        router.server = server
        let r = router
        tap.onKey = { [unowned tap] ev in r.key(ev, modifierOnlySinceDown: tap.lastKeyPressWasModifierOnly) }
        tap.onMouseButton = { ev in r.mouseButton(ev) }
        tap.onMouseDragged = { p in r.dragged(p) }
        tap.onMouseMoved = { p in r.mouseMoved(p) }
        tap.onScroll = { ev in r.scroll(ev) }
        if !tap.start() { Log.error("could not create event tap (Accessibility permission missing?)") }
        gestures.onEvent = { [weak server] event, time in
            MainActor.assumeIsolated {
                switch event {
                case .update(let s): server?.handleCursorSwipeUpdate(s, time: time)
                case .end(let s): server?.handleCursorSwipeEnd(s)
                }
            }
        }
        // mango closes the switcher when the session locks (keyboard.c): the screen locks,
        // or another user takes the screen.
        let close: @Sendable (Notification) -> Void = { [weak server] _ in
            MainActor.assumeIsolated { server?.switcherClose() }
        }
        let dnc = DistributedNotificationCenter.default(), ws = NSWorkspace.shared.notificationCenter
        lockObservers = [
            dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: close),
            ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main, using: close),
        ]
    }

    func keyboardCancelPendingReleaseBind() { router.cancelPendingReleaseBind() }

    func watchGestures(_ on: Bool) {
        // Started and stopped only as gesture bindings come or go (start does nothing while it
        // runs): a stop clears what the trackpad's own thread is reading.
        if on { gestures.start() } else { gestures.stop() }
    }

    /// chutney_hyper_tap for chutney_hyper_key's key: as Raycast's Quick Press, only for
    /// Caps Lock and a function key (a modifier pressed alone is already something).
    static func hyperTap(key: String, tap: String) -> InputRouter.HyperTap {
        guard let k = KeyboardOptions.hyperKey(key), let original = k.original else { return .none }
        switch tap {
        case "escape": return .key(53)   // kVK_Escape
        case "original": return original == KeyboardOptions.capsLockKeyCode ? .capsLock : .key(original)
        default: return .none
        }
    }

    func publishInput(_ state: InputState) {
        let hyperKey = server.config.chutneyHyperKey, hyperTap = server.config.chutneyHyperTap
        let hyperModifier = server.config.hyperModifier
        router.publish { s in
            s.keymode = state.keymode
            s.bindings = state.bindings
            s.mouseBindings = state.mouseBindings
            s.axisBindings = state.axisBindings
            s.axisTimeout = state.axisTimeout
            s.overviewFrame = state.overviewFrame
            s.jumpActive = state.jumpLabels != nil
            s.jumpKeys = Set((state.jumpLabels ?? []).flatMap { KeyNames.keyCodes(forName: $0.lowercased()) })
            s.overcircleActive = state.overcircleActive
            s.switcherActive = state.switcherActive
            s.tagCombo = state.tagCombo
            // Port extension: not in mango. chutney_hyper_key's key is held as Hyper too.
            s.capsHyper = state.capsHyper ?? (hyperKey.isEmpty ? nil : Modifiers.parse("hyper", hyperModifier: hyperModifier))
            s.hyperTap = Self.hyperTap(key: hyperKey, tap: hyperTap)
            s.wantsMouseMoved = state.wantsMouseMoved
            s.cursorHideOnKeypress = state.cursorHideOnKeypress
        }
        tabBarsChanged()   // the port's tab keys (chutney_tab_bar_shortcuts), with the rest
    }

    func publishGlobalKeys(_ keys: [GlobalKey]) {
        let routed = keys.map { InputRouter.RoutedGlobalKey(mods: $0.mods, keyCodes: Set(KeyNames.keyCodes(forName: $0.keyName)), pid: $0.pid) }
        router.publish { $0.globalKeys = routed }
    }

    func setCursorHidden(_ hidden: Bool) {
        if hidden { CursorHider.hide() } else { CursorHider.show() }
    }

    func raise(_ c: Client) { writer(for: c.pid)?.raise(c.element) }

    func unminimize(_ c: Client) {
        writer(for: c.pid)?.async { [el = c.element] in el.setMinimized(false) }
    }

    var canCapture: Bool { WindowSnapshot.hasPermission }

    /// Not in mango: the port's permissions window, once per run.
    func askToCapture() { Permissions.shared.askForCapture() }

    var modifiers: Modifiers { Modifiers(cgFlags: CGEventSource.flagsState(.combinedSessionState)) }

    func setFrame(_ c: Client, _ frame: CGRect, size: Bool) {
        writer(for: c.pid)?.setFrame(c.element, id: c.id, frame: frame, setSize: size)
    }

    func readFrame(_ c: Client, _ done: @escaping @MainActor (CGRect?) -> Void) {
        guard let q = writer(for: c.pid) else { done(nil); return }
        q.readBack(c.element, completion: done)
    }

    /// Via the close button, on the app's own queue (never blocks main).
    func clientSendClose(_ c: Client) {
        let el = c.element, name = c.appName, id = c.id
        writer(for: c.pid)?.async {
            // Around sleep the element can be dead until the app lists the window again.
            if el.closeButton == nil { Log.debug("\(name): window \(id) has no close button to press (element invalid?)") }
            el.close()
        }
    }

    func settle(_ c: Client) {
        guard let q = writer(for: c.pid) else { return }
        readBack(c, q)
    }

    func ignoreMoves(_ c: Client, until: Double) { watcher.suppressGeometry(c.id, until: until) }
}

extension MangoServer {
    /// mango on macOS: the port's system stands where wlroots does.
    public func useMacSystem() { system = MacWindowSystem(self) }

    /// The port's system (the port sets it, so it is always this one).
    var mac: MacWindowSystem { system as! MacWindowSystem }

    /// mango's own menu is open (MangoApp): native focus waits.
    public var holdNativeFocus: Bool {
        get { (system as? MacWindowSystem)?.holdFocus ?? false }
        set { (system as? MacWindowSystem)?.holdFocus = newValue }
    }
}
