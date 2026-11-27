import AppKit
import Mango

@MainActor
class MacWindowSystem: WindowSystem {
    unowned let server: MangoServer
    var holdFocus = false {
        didSet {
            guard !holdFocus, oldValue, let c = heldFocus else { return }
            if server.clientByWindowID(c.windowID) === c { raise(c) }
            releaseHeldFocus()
        }
    }
    var heldFocus: Client?
    /// holdWrites: the scenes mango set while the port held its writes back.
    var holdingWrites = false
    var heldScenes: Set<ClientID> = []
    var fullscreenTag = FullscreenTag.State()   // Port extension: chutney_fullscreen_tag
    /// A window in macOS fullscreen as the port takes it (MacFullscreenHooks): out of the layout, or as an
    /// extension hooks in (chutney_fullscreen_tag).
    var fullscreenHooks: any MacFullscreenHooks = NoFullscreenTag()
    /// Windows back from macOS fullscreen before its Space change was done: placed again at it.
    var fullscreenReturns: Set<ClientID> = []

    /// What the port asks of macOS about other apps' windows (NativeWindows): macOS's in the app, the
    /// tests' own in tests.
    lazy var native: any NativeWindows = MacNativeWindows(self)
    /// What the port asks of the machine itself (HostSystem): macOS's in the app, the tests' own in tests.
    lazy var host: any HostSystem = MacHostSystem(self)

    func fullscreenNow(_ c: Client) -> Bool? { native.fullscreenNow(c) }
    func windowOnScreen(_ id: CGWindowID) -> Bool { native.windowOnScreen(id) }
    func askFocus(_ c: Client) { native.askFocus(c) }
    func focusSpaceAnchor(_ m: Monitor) { native.focusSpaceAnchor(m) }
    func setNativeFullscreen(_ c: Client, _ fullscreen: Bool, _ done: @escaping @MainActor (Bool) -> Void) {
        native.setNativeFullscreen(c, fullscreen, done)
    }

    var pendingFocus: Client?
    var pendingRaises: [Client] = []
    var flushScheduled = false
    /// wlroots' seat: the client mango last gave the keyboard.
    var seatFocus: Client?
    /// macOS gave this window the keyboard itself: mango's notify sends nothing.
    var macOSFocused: ClientID?
    var initialSettlePending = false
    var away: [ClientID: (client: Client, reasons: Set<AwayReason>)] = [:]
    var loggedWindowCount = -1
    var restackGeneration = 0
    let borders: any BorderDrawing
    let memory = WindowMemory()
    var onStatusChange: (() -> Void)?
    var userDrag: UserDrag?
    var seatPointerFocus: ClientID?
    var restarting = false
    var opacityWarned = false
    var fitState = FitLayout.State()   // Port extension: chutney_fit_layout
    func postFitNotification(title: String, body: String, fit: Bool = true) { panels.postFitNotification(title: title, body: body, fit: fit) }
    func removeFitNotification() { panels.removeFitNotification() }
    var dispatchersWarned = Set<String>()
    var pressed: (client: Client, frame: CGRect)?
    let tabBars: any BarDrawing
    let groupBars: any BarDrawing
    /// The panels the port draws (PortPanels): AppKit's in the app, the tests' own in tests.
    lazy var panels: any PortPanels = AppKitPanels(self)
    /// The panels of the trees mango builds under the special overlay layer (the workspace overview).
    var scenePanels: [ObjectIdentifier: any ScenePanelDrawing] = [:]
    var layoutIconCache: [LayoutKind: CGImage] = [:]
    var layoutIconTheme: RGBA?
    var swipeSent: Swipe?
    let tap = EventTap()
    let router = InputRouter()
    let gestures = GestureRecognizer()
    let watcher = AppWatcher()
    lazy var frameClock: FrameClock = {
        let clock = FrameClock(server)
        clock.commit = { [weak self] in
            self?.commitFrame()
            self?.drawScene()
        }
        return clock
    }()
    /// The port's time; the tests give their own.
    var clock: any PortClock = HostClock()
    /// What the frame writes and parks, and the windows waited for (Placement).
    var placing = Placing()
    /// The borders and bars mango last drew; the port shows them again where the windows stand when an
    /// app answers (showAgain).
    var drawnBorders: [BorderSpec] = []
    var drawnTabBars: (strips: [TabStrip], style: TabStripStyle)?
    var drawnGroupBars: (strips: [TabStrip], style: TabStripStyle)?
    /// The plate for a window parked at its monitor's edge (EdgePlates).
    func showEdgePlate(_ c: Client, box: CGRect) {
        guard let m = monitor(of: c) else { return }
        panels.showEdgePlate(c, box: box, monitor: m.screen.frame, border: plateBorder(c))
    }

    /// The window's border as updateBorders draws it: mango's color, width and radius, and the port's
    /// extensions on it as on the other borders (chutney_macos_appearance).
    func plateBorder(_ c: Client) -> EdgePlates.Border {
        let draws = server.renderBorder && server.config.borderpx > 0
        let width = draws ? c.bw : 0
        let mango = server.clientNoRadiusActive(c) ? 0 : CGFloat(server.config.borderRadius)
        let spec = BorderSpec(id: c.windowID, frame: c.mac.box, color: server.getBorderColor(c), width: width, radius: mango)
        let corner = MacOSAppearance.borders([spec], server.config).first?.radius ?? mango   // Port extension
        let col = spec.color
        return EdgePlates.Border(color: NSColor(red: col.r, green: col.g, blue: col.b, alpha: col.a).cgColor, width: width,
                                 radius: BorderGeometry.outerRadius(corner: corner, width: width), innerRadius: corner)
    }

    func hideEdgePlate(_ id: ClientID) { panels.hideEdgePlate(id) }
    let watchdog = MainThreadWatchdog()
    let missionControl = MissionControl()

    func writer(for pid: pid_t) -> (any WindowWriter)? {
        native.writer(for: pid)
    }

    func stackingOrder() -> [StackedWindow] { native.stackingOrder() }
    var observers: [NSObjectProtocol] = []

    /// The borders and bars are drawn by AppKit unless others are given (the tests').
    init(_ server: MangoServer, borders: (any BorderDrawing)? = nil, tabBars: (any BarDrawing)? = nil,
         groupBars: (any BarDrawing)? = nil) {
        self.server = server
        self.borders = borders ?? BorderManager()
        self.tabBars = tabBars ?? TabBarManager()
        self.groupBars = groupBars ?? TabBarManager()
        server.onStateChange = { [unowned self] in statusChanged() }
        self.tabBars.onSelect = { [weak self] id in self?.barPress(id, isTab: true, right: false, onClose: false) }
        self.tabBars.onRightClick = { [weak self] id in self?.barPress(id, isTab: true, right: true, onClose: false) }
        self.groupBars.onSelect = { [weak self] id in self?.barPress(id, isTab: false, right: false, onClose: false) }
        self.groupBars.onRightClick = { [weak self] id in self?.barPress(id, isTab: false, right: true, onClose: false) }
        self.groupBars.onClose = { [weak self] id in self?.barPress(id, isTab: false, right: false, onClose: true) }
    }

    var pointer: CGPoint { host.pointer }

    let eventLoop: EventLoop = MainEventLoop()

    func quit() { host.quit() }

    func warp(to p: CGPoint) { host.warp(to: p) }

    /// The seat's pointer focus is only remembered: on macOS the apps get the pointer from the system.
    var pointerFocusedSurface: ClientID? { seatPointerFocus }
    func seatPointerNotifyEnter(_ surface: ClientID) { seatPointerFocus = surface }
    func seatPointerClearFocus() { seatPointerFocus = nil }

    func barPress(_ id: ClientID, isTab: Bool, right: Bool, onClose: Bool) {
        server.pointerProcessButtonPress(button: right ? 1 : 0, pressed: true, at: pointer, mods: keyboardHardModifiers(),
                                         bar: BarButton(client: id, isTab: isTab, onClose: onClose))
    }


    func drawBorders(_ specs: [BorderSpec]) {
        drawnBorders = specs
        showBorders()
    }

    func drawTabBars(_ strips: [TabStrip], style: TabStripStyle) {
        drawnTabBars = (strips, style)
        showTabBars(strips, style: style)
    }

    func drawGroupBars(_ strips: [TabStrip], style: TabStripStyle) {
        drawnGroupBars = (strips, style)
        showGroupBars(strips, style: style)
    }

    var windowCornerRadius: CGFloat { BorderGeometry.cornerRadius }

    func showOverview(_ cards: [OverviewCard], on m: Monitor, look: OverviewLook) {
        showOverviewPanel(cards, on: m, look: look)
        fullscreenHooks.overviewShown(m)   // Port extension: chutney_fullscreen_tag
    }

    func showOverviewPanel(_ cards: [OverviewCard], on m: Monitor, look: OverviewLook) {
        panels.showOverview(cards, on: m, look: look)
    }

    func updateOverview(_ cards: [OverviewCard], on m: Monitor) { panels.updateOverview(cards, on: m) }

    func captureOverviewCards(on m: Monitor, scale: CGFloat) { panels.captureOverviewCards(on: m, scale: scale) }

    func closeOverview(on m: Monitor) {
        panels.closeOverview(on: m)
        releaseHeldFocus()
    }

    func showSwitcher(panel: CGRect, tiles: [SwitcherTilePicture], look: SwitcherLook, scale: CGFloat) {
        panels.showSwitcher(panel: panel, tiles: tiles, look: look, scale: scale)
    }

    func switcherApplyHighlight(_ tiles: [SwitcherTilePicture]) { panels.switcherApplyHighlight(tiles) }

    func closeSwitcherPanel() { panels.closeSwitcher() }

    func mangoBarDecorationCreate(_ m: Monitor, _ data: DecorateDrawData, _ width: CGFloat, _ height: CGFloat) -> MangoBarDecoration? {
        panels.barDecoration(m, data, width, height)
    }

    func mangoJumpLabelNodeCreate(_ c: Client, _ data: DecorateDrawData) -> MangoJumpLabel? {
        panels.jumpLabel(c, data)
    }

    func findKeycodesForKeysym(_ keysym: Character) -> MultiKeycode { host.findKeycodesForKeysym(keysym) }

    func showSpecialDim(on m: Monitor, alpha: Float?, over: Set<ClientID>) {
        let backmost = alpha == nil ? nil : stackingOrder().last { over.contains($0.id) }?.id
        panels.showSpecialDim(on: m, alpha: alpha, below: backmost)
    }

    func showDropArea(_ area: CGRect?, color: RGBA) { panels.showDropArea(area, color: color) }

    func nagSpawn(_ argv: [String], input: String) {
        panels.nagSpawn(argv, input: input, selected: server.selectedMonitor?.screen.displayID,
                        macOS: server.config.chutneyMacOSAppearance)   // Port extension: not in mango (chutney_macos_appearance)
    }

    func nagKill() { panels.nagKill() }

    func configLoaded(_ config: Config) {
        let used = config.keyBindings.map(\.dispatch.name) + config.mouseBindings.map(\.dispatch.name)
            + config.axisBindings.map(\.dispatch.name) + config.gestureBindings.map(\.dispatch.name)
        for name in used where dispatchersWarned.insert(name).inserted {
            if case (.unsupportedDispatcher, let why)? = ConfigParser.port?.dispatcherNote(name) {
                wlrLog(.info, "config: \(name): \(why)")
            }
        }
        let wantsOpacity = config.focusedOpacity < 1 || config.unfocusedOpacity < 1
            || config.windowRules.contains { ($0.focusedOpacity ?? 1) < 1 || ($0.unfocusedOpacity ?? 1) < 1 }
        if wantsOpacity && !opacityWarned {
            opacityWarned = true
            wlrLog(.info, "config: focused_opacity / unfocused_opacity are not supported on macOS and are ignored "
                     + "(changing another process's window alpha needs SLSSetWindowAlpha from the Dock connection, which SIP blocks)")
        }
    }

    var mouseButtons: Int { host.mouseButtons }

    func ipcGetLayoutStr() -> String { KeyNames.currentLayoutName() }

    var inputDevices: [InputDevice] { host.inputDevices }

    var keyMappings: [KeyboardOptions.Mapping] = []
    var userKeyMappings: [KeyboardOptions.Mapping]?
    var appliedKeyMappings: [KeyboardOptions.Mapping]?

    func setKeyboardOptions(_ options: String) { host.setKeyboardOptions(options) }

    func prepare() {
        ChutneyTheme.sync(configURL: server.configURL)
        server.registerPortExtensions()
        AX.setGlobalTimeout()
        KeyNames.install()
        _ = KeyNames.keyCodes(forName: "a")
    }

    func statusChanged() {
        memory.save(server)
        FitLayout.statusChanged(server)   // Port extension: chutney_fit_layout
        fullscreenHooks.statusChanged()   // Port extension: chutney_fullscreen_tag
        onStatusChange?()
    }

    func startWatching() {
        memory.restore(server)
        watcher.shared.remembered = Set(memory.departed.entries.keys)
        watcher.delegate = self
        watcher.start()
        missionControl.onExit = { [weak server] in server?.arrangeAll(false) }
        missionControl.start()
        if wlrLogGetVerbosity() == .debug { watchdog.start() }
        wlrLog(.info, "scanning \(watcher.apps.count) app(s)")
    }

    func restoreAppSettings(_ done: DispatchGroup) {
        for pid in Set(server.clientsAll.map(\.pid)) {
            guard let q = writer(for: pid) else { continue }
            q.restoreAppSettings()
            done.enter()
            q.async { done.leave() }
        }
    }


    static func clampToScreen(_ f: CGRect, _ work: CGRect) -> CGRect {
        var r = f
        r.size.width = min(r.width, work.width)
        r.size.height = min(r.height, work.height)
        if r.minX < work.minX { r.origin.x = work.minX }
        if r.minY < work.minY { r.origin.y = work.minY }
        if r.maxX > work.maxX { r.origin.x = work.maxX - r.width }
        if r.maxY > work.maxY { r.origin.y = work.maxY - r.height }
        return r
    }

    func shutdown() {
        memory.save(server, final: true)
        frameClock.stop()
        panels.hideAllEdgePlates()
        if let user = userKeyMappings, appliedKeyMappings != user { KeyboardOptions.apply(user) }
        let restore = DispatchGroup()
        if restarting {
            wlrLog(.info, "restarting: hidden windows stay hidden for the next mango")
            restoreAppSettings(restore)
            _ = restore.wait(timeout: .now() + 1)
            return
        }
        for c in server.clientsAll {
            guard let m = monitor(of: c), c.parked || Hider.isParked(c.frame, in: m.screen.frame) else { continue }
            let f = c.isfloating ? c.floatGeom.insetBy(dx: c.bw, dy: c.bw) : c.tile
            writer(for: c.pid)?.setFrame(c.element, id: c.windowID, frame: Self.clampToScreen(f, m.screen.workArea))
        }
        for (c, _) in away.values {
            guard let m = c.mon ?? server.monitors.first else { continue }
            let real = windowServerFrame(c.windowID) ?? c.frame
            guard c.parked || Hider.isParked(real, in: m.screen.frame) else { continue }
            let f = c.isfloating ? c.floatGeom.insetBy(dx: c.bw, dy: c.bw) : c.tile
            writer(for: c.pid)?.setFrame(c.element, id: c.windowID, frame: Self.clampToScreen(f, m.screen.workArea))
        }
        restoreAppSettings(restore)
        _ = restore.wait(timeout: .now() + 2)
    }

    func rescan() { host.rescan() }

    func spawn(_ command: String) { host.spawn(command) }

    func spawnShell(_ command: String) { host.spawnShell(command) }

    var animationsRunning: Bool { frameClock.animationsRunning }
    func whenAnimationsIdle(_ body: @escaping () -> Void) { frameClock.whenIdle(body) }

    var screens: [Screen] { host.screens }

    func windowServerFrame(_ id: ClientID) -> CGRect? { native.windowServerFrame(id) }

    /// macOS's tracker gives the swipe so far and no begin; mango's handlers get a begin and each step.
    func swipeUpdate(_ s: Swipe, _ time: UInt32) {
        let sent = swipeSent ?? Swipe(dx: 0, dy: 0, fingers: s.fingers)
        if swipeSent == nil { server.handleCursorSwipeBegin(s.fingers) }
        swipeSent = s
        server.handleCursorSwipeUpdate(Swipe(dx: s.dx - sent.dx, dy: s.dy - sent.dy, fingers: s.fingers), time: time)
    }

    func swipeEnd(cancelled: Bool) {
        guard swipeSent != nil else { return }
        swipeSent = nil
        server.handleCursorSwipeEnd(cancelled: cancelled)
    }

    func startInput() { host.startInput() }

    func keyboardCancelPendingReleaseBind() { router.cancelPendingReleaseBind() }

    func watchGestures(_ on: Bool) { host.watchGestures(on) }

    func publishInput(_ state: InputState) {
        let hyperKey = !server.config.chutneyHyperKey.isEmpty
            || KeyboardOptions.xkbOptions(server.config.xkbRulesOptions).contains("caps:hyper")
        let hyper = KeyboardOptions.hyperSet(server.config)
        router.publish { s in
            s.keymode = state.keymode
            s.bindings = state.bindings
            s.mouseBindings = state.mouseBindings
            s.axisBindings = state.axisBindings
            s.axisBindApplyTimeout = state.axisBindApplyTimeout
            s.overviewFrame = state.overviewFrame
            s.jumpMode = state.jumpMode
            s.jumpKeys = state.jumpKeycodes
            s.switcherActive = state.switcherActive
            s.workspaceOverviewActive = state.workspaceOverviewActive
            s.hyper = hyper
            s.hyperKey = hyperKey
            s.wantsMouseMoved = state.wantsMouseMoved
            s.hoverResizeCursor = state.hoverResizeCursor
        }
    }

    func publishGlobalKeys(_ keys: [GlobalKey]) {
        let routed = keys.map { InputRouter.RoutedGlobalKey(mods: $0.mods, keyCodes: Set(KeyNames.keyCodes(forName: $0.keyName)), pid: $0.pid) }
        router.publish { $0.globalKeys = routed }
    }

    func setCursorHidden(_ hidden: Bool) { panels.setCursorHidden(hidden) }

    func setCursor(_ name: String?) { panels.setCursor(name) }

    func surfaceAt(_ p: CGPoint) -> ClientID? { native.surfaceAt(p) }

    /// A window's owner does not change: asked for once.
    private var surfaceOwners: [ClientID: pid_t] = [:]


    /// A managed window is its own client; another window of an app (a menu, a popup) belongs to the
    /// app's window that had the focus last, as a popup belongs to its toplevel.
    func toplevelFromWlrSurface(_ surface: ClientID) -> Client? {
        if let c = server.clientByWindowID(surface) { return c }
        let pid: pid_t
        if let known = surfaceOwners[surface] {
            pid = known
        } else {
            guard let p = native.windowOwner(surface) else { return nil }
            if surfaceOwners.count > 256 { surfaceOwners.removeAll() }
            surfaceOwners[surface] = p
            pid = p
        }
        for c in server.focusStack {
            if c.pid == pid, c.mon != nil { return c }
        }
        return nil
    }

    /// macOS has no parent toplevel: a dialog's parent is its app's window that had the focus last.
    func clientGetParent(_ c: Client) -> Client? {
        guard c.mac.isFloatType else { return nil }
        for p in server.focusStack where p !== c {
            if p.pid == c.pid, !p.mac.isFloatType, p.mon != nil { return p }
        }
        return nil
    }

    func clientSetMinimized(_ c: Client, _ minimizeWindow: Bool) {
        writer(for: c.pid)?.async { [el = c.element] in el.setMinimized(minimizeWindow) }
    }

    var canCapture: Bool { host.canCapture }

    func askToCapture() { host.askToCapture() }

    func keyboardHardModifiers() -> Modifiers { host.keyboardHardModifiers() }


    func readFrame(_ c: Client, _ done: @escaping @MainActor (CGRect?) -> Void) {
        guard let q = writer(for: c.pid) else { done(nil); return }
        q.readBack(c.element, completion: done)
    }

    func clientSendClose(_ c: Client) { native.clientSendClose(c) }

    /// Port extension: chutney_fullscreen_tag (with the key off the app is not told).
    func clientNotifyFullscreen(_ c: Client, _ fullscreen: Bool) { fullscreenHooks.notify(c, fullscreen) }   // Port extension: chutney_fullscreen_tag

    func settle(_ c: Client) {
        guard let q = writer(for: c.pid) else { return }
        readBack(c, q)
    }

    func grabBegan(_ c: Client) { watcher.suppressGeometry(c.windowID, for: 3600) }
    func grabEnded(_ c: Client) { watcher.suppressGeometry(c.windowID, for: 0.4) }
}

extension MangoServer {
    public func useMacSystem() { system = MacWindowSystem(self) }

    /// What the app does on a status change (the menu bar); the layout is saved first.
    public var onStatusChange: (() -> Void)? {
        get { mac.onStatusChange }
        set { mac.onStatusChange = newValue }
    }

    var mac: MacWindowSystem { system as! MacWindowSystem }

    public var holdNativeFocus: Bool {
        get { (system as? MacWindowSystem)?.holdFocus ?? false }
        set { (system as? MacWindowSystem)?.holdFocus = newValue }
    }
}
