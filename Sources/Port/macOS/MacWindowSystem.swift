import AppKit
import Mango

@MainActor
class MacWindowSystem: WindowSystem {
    unowned let server: MangoServer
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
    var away: [ClientID: (client: Client, reasons: Set<AwayReason>)] = [:]
    var loggedWindowCount = -1
    var restackGeneration = 0
    let borders = BorderManager()
    let memory = WindowMemory()
    var userDrag: UserDrag?
    var restarting = false
    var opacityWarned = false
    var dispatchersWarned = Set<String>()
    var focusHistory: [ClientID] = []
    var pressed: (client: Client, frame: CGRect)?
    var tabNumbersShown = false
    var publishedTabShortcuts = 0
    let tabBars = TabBarManager()
    let groupBars = TabBarManager()
    var overviewOverlay: OverviewOverlay?
    var jumpLabels: JumpLabelSet?
    var switcherPanel: SwitcherPanel?
    var titleBar: TitleMessageBar?
    var specialDims: [CGDirectDisplayID: SpecialDimView] = [:]
    var dropArea: DropAreaView?
    let nagDisplay = Nag()
    let tap = EventTap()
    let router = InputRouter()
    let gestures = GestureRecognizer()
    var windowServerOverride: ((CGWindowID) -> CGRect?)?
    let watcher = AppWatcher()
    let animator = Animator()
    let watchdog = MainThreadWatchdog()
    let missionControl = MissionControl()
    var configWatcher: ConfigWatcher?
    var writerOverride: ((pid_t) -> (any WindowWriter)?)?
    var stackingOverride: (() -> [StackedWindow])?

    func writer(for pid: pid_t) -> (any WindowWriter)? {
        if let writerOverride { return writerOverride(pid) }
        return watcher.writeQueue(for: pid)
    }

    func stackingOrder() -> [StackedWindow] {
        stackingOverride?() ?? AppWorker.stackingOrder()
    }
    var observers: [NSObjectProtocol] = []

    init(_ server: MangoServer) {
        self.server = server
        tabBars.onSelect = { [weak self] id in self?.barPress(id, isTab: true, right: false, onClose: false) }
        tabBars.onRightClick = { [weak self] id in self?.barPress(id, isTab: true, right: true, onClose: false) }
        groupBars.onSelect = { [weak self] id in self?.barPress(id, isTab: false, right: false, onClose: false) }
        groupBars.onRightClick = { [weak self] id in self?.barPress(id, isTab: false, right: true, onClose: false) }
        groupBars.onClose = { [weak self] id in self?.barPress(id, isTab: false, right: false, onClose: true) }
    }

    var pointer: CGPoint { Screens.mouseLocation }

    let eventLoop: EventLoop = MainEventLoop()

    func quit() { NSApp.terminate(nil) }

    func focus(_ c: Client, raise: Bool) {
        if holdFocus { heldFocus = c; return }
        let first = pendingFocus == nil
        pendingFocus = (c, raise || (pendingFocus?.client === c && pendingFocus?.raise == true))
        guard first else { return }
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.sendFocus() } }
    }

    private func sendFocus() {
        guard let (c, raise) = pendingFocus else { return }
        pendingFocus = nil
        guard Self.stillFocused(c, in: server) else { return }
        let lift = Self.lifts(c, raise: raise, in: server)
        wlrLog(.debug, "\(c.appName): mango focuses window \(c.id)\(lift ? "" : " without lifting it")")
        NativeFocus.focus(windowID: c.id, pid: c.pid, element: c.element, raise: lift) { [weak self] in self?.restack() }
    }

    static func stillFocused(_ c: Client, in server: MangoServer) -> Bool {
        server.clientByIdAll(c.id) === c && server.focused === c
    }

    static func lifts(_ c: Client, raise: Bool, in server: MangoServer) -> Bool {
        guard raise, let m = c.mon else { return false }
        let layer = server.clientTargetLayer(c)
        return !server.clientsAll.contains { d in
            d !== c && d.mon === m && d.isVisible(on: m) && !d.parked
                && server.clientTargetLayer(d) > layer && d.frame.intersects(c.frame)
        }
    }

    func warp(to p: CGPoint) {
        guard server.drawsOverlays else { return }
        NativeFocus.warpCursor(to: p)
    }

    func restack() { restack(pid: server.focused?.pid) }

    func barPress(_ id: ClientID, isTab: Bool, right: Bool, onClose: Bool) {
        server.pointerProcessButtonPress(button: right ? 1 : 0, pressed: true, at: pointer, mods: modifiers,
                                         bar: BarButton(client: id, isTab: isTab, onClose: onClose))
    }

    func restack(pid: pid_t?) {
        guard let pid else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.animator.whenIdle { [weak self] in self?.restackNow(pid) } }
        }
    }

    private func restackNow(_ pid: pid_t, reserve: Bool = true) {
        let ids = Set(server.clientsAll.filter { $0.pid == pid }.map(\.id))
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
        tabBars.update(withTabNumbers(strips), style: withAppIcons(style, server.config.chutneyTabBarDecorateIcon), keyFocus: server.focused?.id)
    }

    func drawGroupBars(_ strips: [TabStrip], style: TabStripStyle) {
        groupBars.update(strips, style: withAppIcons(style, server.config.chutneyGroupBarDecorateIcon), keyFocus: server.focused?.id)
    }

    var windowCornerRadius: CGFloat { BorderGeometry.cornerRadius }

    func showOverview(_ cards: [OverviewCard], on m: Monitor, look: OverviewLook) {
        overviewOverlay?.close()
        let overlay = OverviewOverlay(workArea: m.screen.workArea, top: m.screen.frame.minY, focusColor: look.focusColor, borderColor: look.borderColor,
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

    func nagSpawn(_ argv: [String], input: String) {
        nagDisplay.spawn(argv, input: input, macOS: server.config.chutneyStyle)
    }

    func nagKill() {
        nagDisplay.kill()
    }

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

    var mouseButtons: Int { Int(NSEvent.pressedMouseButtons) }

    var keyboardLayout: String { KeyNames.currentLayoutName() }

    var keyMappings: [KeyboardOptions.Mapping] = []
    var userKeyMappings: [KeyboardOptions.Mapping]?
    var appliedKeyMappings: [KeyboardOptions.Mapping]?

    func setKeyboardOptions(_ options: String) {
        var m = KeyboardOptions.mappings(MangoServer.xkbOptions(options))
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
        wlrLog(.info, m.isEmpty ? "xkb_rules_options: the keyboard's key mapping cleared"
                           : "xkb_rules_options: \(m.count) key(s) moved")
    }

    func allWindowIDs() -> Set<ClientID> { AppWorker.allWindowIDs() }

    func prepare() {
        ChutneyTheme.sync(configURL: server.configURL)
        server.registerPortExtensions()
        AX.setGlobalTimeout()
        KeyNames.install()
        _ = KeyNames.keyCodes(forName: "a")
    }

    func startWatching() {
        watcher.delegate = self
        watcher.start()
        missionControl.onExit = { [weak server] in server?.arrangeAll(.none) }
        missionControl.start()
        animator.onFrame = { [weak server] frames in server?.clientDrawFrame(frames) }
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

    func keepOnDisplay(_ frame: CGRect, _ m: Monitor) -> CGRect { Self.clampToScreen(frame, m.screen.workArea) }

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
        animator.cancelAll()
        if let user = userKeyMappings, appliedKeyMappings != user { KeyboardOptions.apply(user) }
        let restore = DispatchGroup()
        if restarting {
            wlrLog(.info, "restarting: hidden windows stay hidden for the next mango")
            restoreAppSettings(restore)
            _ = restore.wait(timeout: .now() + 1)
            return
        }
        for c in server.clientsAll {
            guard let m = c.mon, c.parked || Hider.isParked(c.frame, in: m.screen.frame) else { continue }
            let f = c.isFloating ? c.floatGeom : (c.geom ?? c.floatGeom)
            writer(for: c.pid)?.setFrame(c.element, id: c.id, frame: Self.clampToScreen(f, m.screen.workArea))
        }
        for (c, _) in away.values {
            guard let m = c.mon ?? server.monitors.first else { continue }
            let real = windowServerFrame(c.id) ?? c.frame
            guard c.parked || Hider.isParked(real, in: m.screen.frame) else { continue }
            let f = c.isFloating ? c.floatGeom : (c.geom ?? c.floatGeom)
            writer(for: c.pid)?.setFrame(c.element, id: c.id, frame: Self.clampToScreen(f, m.screen.workArea))
        }
        restoreAppSettings(restore)
        _ = restore.wait(timeout: .now() + 2)
    }

    func rescan() {
        animator.whenIdle { [weak self] in self?.watcher.refreshAll(recheckRejected: true) }
    }

    func spawn(_ command: String) { Spawn.run(command) }

    func spawnShell(_ command: String) { Spawn.shell(command) }

    func watchConfig(_ files: [URL]) {
        configWatcher = nil
        guard !files.isEmpty else { return }
        configWatcher = ConfigWatcher(files: files) { [weak server] changed in
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

    func windowServerFrame(_ id: ClientID) -> CGRect? {
        if let windowServerOverride { return windowServerOverride(id) }
        return AppWorker.windowServerFrame(id)
    }

    func startInput() {
        CursorHider.prepareTapCursors()
        router.server = server
        let r = router
        tap.onKey = { [unowned tap] ev in r.key(ev, modifierOnlySinceDown: tap.lastKeyPressWasModifierOnly) }
        tap.onMouseButton = { ev in r.mouseButton(ev) }
        tap.onMouseDragged = { p in r.dragged(p) }
        tap.onMouseMoved = { p in r.mouseMoved(p) }
        tap.onScroll = { ev in r.scroll(ev) }
        if !tap.start() { wlrLog(.error, "could not create event tap (Accessibility permission missing?)") }
        gestures.onEvent = { [weak server] event, time in
            MainActor.assumeIsolated {
                switch event {
                case .update(let s): server?.handleCursorSwipeUpdate(s, time: time)
                case .end(let s): server?.handleCursorSwipeEnd(s)
                }
            }
        }
        let close: @Sendable (Notification) -> Void = { [weak server] _ in
            MainActor.assumeIsolated { server?.switcherClose() }
        }
        let dnc = DistributedNotificationCenter.default(), ws = NSWorkspace.shared.notificationCenter
        let layoutChanged: @Sendable (Notification) -> Void = { [weak server] _ in
            MainActor.assumeIsolated { server?.printstatus() }
        }
        observers = [
            dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: close),
            ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main, using: close),
            dnc.addObserver(forName: Notification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
                            object: nil, queue: .main, using: layoutChanged),
        ]
    }

    func keyboardCancelPendingReleaseBind() { router.cancelPendingReleaseBind() }

    func watchGestures(_ on: Bool) {
        if on { gestures.start() } else { gestures.stop() }
    }

    static func hyperTap(key: String, tap: String) -> InputRouter.HyperTap {
        guard let k = KeyboardOptions.hyperKey(key), let original = k.original else { return .none }
        switch tap {
        case "escape": return .key(53)
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
            s.capsHyper = state.capsHyper ?? (hyperKey.isEmpty ? nil : Modifiers.parse("hyper", hyperModifier: hyperModifier))
            s.hyperTap = Self.hyperTap(key: hyperKey, tap: hyperTap)
            s.wantsMouseMoved = state.wantsMouseMoved
            s.cursorHideOnKeypress = state.cursorHideOnKeypress
            s.hoverResizeCursor = state.hoverResizeCursor
        }
        tabBarsChanged()
    }

    func publishGlobalKeys(_ keys: [GlobalKey]) {
        let routed = keys.map { InputRouter.RoutedGlobalKey(mods: $0.mods, keyCodes: Set(KeyNames.keyCodes(forName: $0.keyName)), pid: $0.pid) }
        router.publish { $0.globalKeys = routed }
    }

    func setCursorHidden(_ hidden: Bool) {
        if hidden { CursorHider.hide() } else { CursorHider.show() }
    }

    func setCursor(_ name: String?) { CursorHider.setCursor(name) }

    func surfaceAt(_ p: CGPoint) -> ClientID? { CursorHider.windowAt(p) }

    func raise(_ c: Client) { writer(for: c.pid)?.raise(c.element) }

    func unminimize(_ c: Client) {
        writer(for: c.pid)?.async { [el = c.element] in el.setMinimized(false) }
    }

    var canCapture: Bool { WindowSnapshot.hasPermission }

    func askToCapture() { Permissions.shared.askForCapture() }

    var modifiers: Modifiers { Modifiers(cgFlags: CGEventSource.flagsState(.combinedSessionState)) }

    func setFrame(_ c: Client, _ frame: CGRect, size: Bool) {
        writer(for: c.pid)?.setFrame(c.element, id: c.id, frame: frame, setSize: size)
    }

    func readFrame(_ c: Client, _ done: @escaping @MainActor (CGRect?) -> Void) {
        guard let q = writer(for: c.pid) else { done(nil); return }
        q.readBack(c.element, completion: done)
    }

    func clientSendClose(_ c: Client) {
        let el = c.element, name = c.appName, id = c.id
        writer(for: c.pid)?.async {
            if el.closeButton == nil { wlrLog(.debug, "\(name): window \(id) has no close button to press (element invalid?)") }
            el.close()
        }
    }

    func settle(_ c: Client) {
        guard let q = writer(for: c.pid) else { return }
        readBack(c, q)
    }

    func grabBegan(_ c: Client) { watcher.suppressGeometry(c.id, until: CACurrentMediaTime() + 3600) }
    func grabEnded(_ c: Client) { watcher.suppressGeometry(c.id, until: CACurrentMediaTime() + 0.4) }
}

extension MangoServer {
    public func useMacSystem() { system = MacWindowSystem(self) }

    var mac: MacWindowSystem { system as! MacWindowSystem }

    public var holdNativeFocus: Bool {
        get { (system as? MacWindowSystem)?.holdFocus ?? false }
        set { (system as? MacWindowSystem)?.holdFocus = newValue }
    }
}
