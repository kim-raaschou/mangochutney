import AppKit
import Mango

@MainActor
class MacWindowSystem: WindowSystem {
    unowned let server: MangoServer
    var holdFocus = false {
        didSet {
            guard !holdFocus, oldValue, let c = heldFocus else { return }
            if server.clientByIdAll(c.id) === c { raise(c) }
            releaseHeldFocus()
        }
    }
    var heldFocus: Client?
    var fullscreenTag = FullscreenTag.State()   // Port extension: chutney_fullscreen_tag
    /// Windows back from macOS fullscreen before its Space change was done: placed again at it.
    var fullscreenReturns: Set<ClientID> = []

    /// macOS's fullscreen for the window; nil where the app does not answer.
    func fullscreenNow(_ c: Client) -> Bool? { c.element.attribute("AXFullScreen") as Bool? }

    /// Whether a window is on the active Space.
    func windowOnScreen(_ id: CGWindowID) -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]] else { return false }
        return info.first?[kCGWindowIsOnscreen as String] as? Bool ?? false
    }

    /// The app is asked which of its windows has the keys; its answer is mango's focus.
    func askFocus(_ c: Client) { watcher.requestFocusReport(pid: c.pid) }

    /// Port extension: chutney_fullscreen_tag. mango's own window on `m`'s desktop Space focused.
    func focusSpaceAnchor(_ m: Monitor) { FullscreenTag.focusSpaceAnchor(server, m) }

    /// Port extension: chutney_fullscreen_tag. macOS's fullscreen set for the window; `done` says whether
    /// the app took it (false where it has no fullscreen button or cannot be set).
    func setNativeFullscreen(_ c: Client, _ fullscreen: Bool, _ done: @escaping @MainActor (Bool) -> Void) {
        guard let q = writer(for: c.pid) else { done(false); return }
        q.async { [el = c.element] in
            var settable = DarwinBoolean(false)
            let ok = el.fullscreenButton != nil
                && AXUIElementIsAttributeSettable(el, "AXFullScreen" as CFString, &settable) == .success && settable.boolValue
                && el.setAttribute("AXFullScreen", fullscreen as CFBoolean) == .success
            DispatchQueue.main.async { MainActor.assumeIsolated { done(ok) } }
        }
    }
    private var pendingFocus: Client?
    private var pendingRaises: [Client] = []
    private var flushScheduled = false
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
    func postFitNotification(title: String, body: String, fit: Bool = true) { FitNotification.shared.post(server, title: title, body: body, fit: fit) }
    func removeFitNotification() { FitNotification.shared.remove() }
    var dispatchersWarned = Set<String>()
    var pressed: (client: Client, frame: CGRect)?
    let tabBars: any BarDrawing
    let groupBars: any BarDrawing
    var overviewOverlays: [ObjectIdentifier: OverviewOverlay] = [:]
    var switcherPanel: SwitcherPanel?
    var specialDims: [CGDirectDisplayID: SpecialDimView] = [:]
    var swipeSent: Swipe?
    var dropArea: DropAreaView?
    let nagDisplay = Nag()
    let tap = EventTap()
    let router = InputRouter()
    let gestures = GestureRecognizer()
    var windowServerOverride: ((CGWindowID) -> CGRect?)?
    let watcher = AppWatcher()
    lazy var frameClock: FrameClock = {
        let clock = FrameClock(server)
        clock.commit = { [weak self] in self?.commitFrame() }
        return clock
    }()
    /// The port's time; the tests give their own.
    var clock: any PortClock = HostClock()
    /// What the frame writes and parks, and the windows waited for (Placement).
    var placing = Placing()
    /// The borders and bars mango last drew; the port shows them again where the windows stand when an
    /// app answers (showAgain).
    private var drawnBorders: [BorderSpec] = []
    private var drawnTabBars: (strips: [TabStrip], style: TabStripStyle)?
    private var drawnGroupBars: (strips: [TabStrip], style: TabStripStyle)?
    lazy var edgePlates: EdgePlates = {
        let plates = EdgePlates()
        plates.onClick = { [weak self] id in
            guard let self, let c = self.server.clientByIdAll(id) else { return }
            self.server.clientFocus(c, true)
        }
        return plates
    }()

    /// The plate for a window parked at its monitor's edge (EdgePlates).
    func showEdgePlate(_ c: Client, box: CGRect) {
        guard let m = monitor(of: c) else { return }
        edgePlates.show(c.id, pid: c.pid, box: box, monitor: m.screen.frame, border: plateBorder(c))
    }

    /// The window's border as updateBorders draws it: mango's color, width and radius, and the port's
    /// extensions on it as on the other borders (chutney_macos_appearance).
    func plateBorder(_ c: Client) -> EdgePlates.Border {
        let draws = server.renderBorder && server.config.borderpx > 0
        let width = draws ? c.bw : 0
        let mango = server.clientNoRadiusActive(c) ? 0 : CGFloat(server.config.borderRadius)
        let spec = BorderSpec(id: c.id, frame: c.mac.box, color: server.getBorderColor(c), width: width, radius: mango)
        let corner = MacOSAppearance.borders([spec], server.config).first?.radius ?? mango   // Port extension
        let col = spec.color
        return EdgePlates.Border(color: NSColor(red: col.r, green: col.g, blue: col.b, alpha: col.a).cgColor, width: width,
                                 radius: BorderGeometry.outerRadius(corner: corner, width: width), innerRadius: corner)
    }

    func hideEdgePlate(_ id: ClientID) { edgePlates.hide(id) }
    let watchdog = MainThreadWatchdog()
    let missionControl = MissionControl()
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

    var pointer: CGPoint { Screens.mouseLocation }

    let eventLoop: EventLoop = MainEventLoop()

    func quit() { NSApp.terminate(nil) }

    /// The port's own focus: back to mango's window after the port's panel.
    func focus(_ c: Client, raise: Bool) {
        seatFocus = c
        if raise { self.raise(c) }
        focusLater(c)
    }

    var keyboardFocusedSurface: Client? {
        seatFocus.flatMap { server.clientByIdAll($0.id) === $0 ? $0 : nil }
    }

    func clientNotifyEnter(_ c: Client) {
        seatFocus = c
        if macOSFocused == c.id { return }
        focusLater(c)
    }

    /// macOS activates a window as it gives it the keyboard (clientNotifyEnter).
    func clientActivateSurface(_ c: Client, _ activated: Bool) {}

    /// The seat only: macOS keeps its focus.
    func keyboardNotifyClearFocus() { seatFocus = nil }

    /// A scene raise: done with the turn's focus, as one native call where it is the focused window.
    /// Whether it is parked is read at the flush, after the turn's arrange has placed it.
    func raise(_ c: Client) {
        pendingRaises.removeAll { $0 === c }
        pendingRaises.append(c)
        scheduleFlush()
    }

    private func focusLater(_ c: Client) {
        if holdFocus || !overviewOverlays.isEmpty { heldFocus = c; return }
        pendingFocus = c
        scheduleFlush()
    }

    func releaseHeldFocus() {
        guard !holdFocus, overviewOverlays.isEmpty, let c = heldFocus else { return }
        heldFocus = nil
        if server.clientByIdAll(c.id) === c { focusLater(c) }
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.flushFocus() } }
    }

    private func flushFocus() {
        flushScheduled = false
        let raises = pendingRaises, f = pendingFocus
        pendingRaises = []
        pendingFocus = nil
        let shown = raises.filter { server.clientByIdAll($0.id) === $0 && !$0.parked && !$0.groupParked }
        for r in shown where r !== f { sendNativeRaise(r) }
        guard let c = f, Self.stillFocused(c, in: server) else { return }
        let lift = Self.lifts(c, raise: shown.contains { $0 === c }, in: server)
        wlrLog(.debug, "\(c.appName): mango focuses window \(c.id)\(lift ? "" : " without lifting it")")
        sendNativeFocus(c, raise: lift)
    }

    func sendNativeFocus(_ c: Client, raise: Bool) {
        NativeFocus.focus(windowID: c.id, pid: c.pid, element: c.element, raise: raise) { [weak self] in self?.restack() }
    }

    func sendNativeRaise(_ c: Client) { writer(for: c.pid)?.raise(c.element) }

    static func stillFocused(_ c: Client, in server: MangoServer) -> Bool {
        server.clientByIdAll(c.id) === c && server.focused === c
    }

    static func lifts(_ c: Client, raise: Bool, in server: MangoServer) -> Bool {
        guard raise, let m = c.mon else { return false }
        let layer = server.clientTargetLayer(c)
        return !server.clientsAll.contains { d in
            d !== c && d.mon === m && VISIBLEON(d, m) && !d.parked
                && server.clientTargetLayer(d) > layer && d.frame.intersects(c.frame)
        }
    }

    func warp(to p: CGPoint) {
        guard server.drawsOverlays else { return }
        NativeFocus.warpCursor(to: p)
    }

    /// The seat's pointer focus is only remembered: on macOS the apps get the pointer from the system.
    var pointerFocusedSurface: ClientID? { seatPointerFocus }
    func seatPointerNotifyEnter(_ surface: ClientID) { seatPointerFocus = surface }
    func seatPointerClearFocus() { seatPointerFocus = nil }

    func restack() { restack(pid: server.focused?.pid) }

    func barPress(_ id: ClientID, isTab: Bool, right: Bool, onClose: Bool) {
        server.pointerProcessButtonPress(button: right ? 1 : 0, pressed: true, at: pointer, mods: keyboardHardModifiers(),
                                         bar: BarButton(client: id, isTab: isTab, onClose: onClose))
    }

    func restack(pid: pid_t?) {
        guard let pid else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.frameClock.whenIdle { [weak self] in self?.restackNow(pid) } }
        }
    }

    /// The window server's stacking is asked for off the main thread (it waits for the window server's
    /// pending transactions); the overlays are ordered on the main thread with what it answered.
    private func restackNow(_ pid: pid_t, reserve: Bool = true) {
        Self.stackingQueue.async { [weak self] in
            let order = AppWorker.onScreenOrder()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.restackApply(pid, order, reserve: reserve) }
            }
        }
    }

    private static let stackingQueue = DispatchQueue(label: "mango.stacking", qos: .userInteractive)

    private func restackApply(_ pid: pid_t, _ order: [CGWindowID], reserve: Bool) {
        let ids = Set(server.clientsAll.filter { $0.pid == pid }.map(\.id))
        let at = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        let ours = Set(((NSApp as NSApplication?)?.windows ?? []).map { CGWindowID(truncatingIfNeeded: $0.windowNumber) })
        func inPlace(_ overlay: CGWindowID, _ target: CGWindowID, above: Bool) -> Bool {
            guard let o = at[overlay], let t = at[target], above ? o < t : o > t else { return false }
            return order[(min(o, t) + 1)..<max(o, t)].allSatisfy(ours.contains)
        }
        borders.restack(ids) { inPlace($0, $1, above: true) }
        tabBars.restack(ids) { inPlace($0, $1, above: false) }
        groupBars.restack(ids) { inPlace($0, $1, above: false) }
        for m in server.monitors where isSpecialActive(m) { server.specialUpdateDim(m) }
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
        drawnBorders = specs
        showBorders()
    }

    /// The borders and bars mango last drew, shown again where the windows stand now: an app answered,
    /// and nothing of mango's changed.
    func showAgain() {
        showBorders()
        if let d = drawnTabBars { showTabBars(d.strips, style: d.style) }
        if let d = drawnGroupBars { showGroupBars(d.strips, style: d.style) }
    }

    private func showBorders() {
        let specs = MacOSAppearance.borders(shownBorders(drawnBorders), server.config)
        borders.update(specs)
        for c in server.clientsAll where c.mac.placed.offEdge { edgePlates.setBorder(c.id, plateBorder(c)) }
    }

    /// The borders macOS shows now: mango's, around the window where it stands. A parked window has
    /// none, and a window coming back from parking gets its border when the app has moved it
    /// (comingBack). Port extension: chutney_fullscreen_tag. No border for a window in its own
    /// fullscreen Space.
    func shownBorders(_ specs: [BorderSpec]) -> [BorderSpec] {
        specs.compactMap { s in
            guard let c = server.clientByIdAll(s.id) else { return s }
            if c.parked || leftToMacOS(c) || c.mac.placed.comingBack { return nil }
            guard let d = lag(c) else { return nil }
            var s = s
            s.frame = CGRect(x: s.frame.minX + d.dx, y: s.frame.minY + d.dy,
                             width: s.frame.width + d.dw, height: s.frame.height + d.dh)
            return s
        }
    }

    /// How far the window as macOS shows it is from mango's box this frame (c->animation.current without
    /// the border): origin and size differences, a smaller window's negative (no CGRect, which would read
    /// them as a rect of its own).
    struct Lag: Equatable {
        var dx: CGFloat, dy: CGFloat, dw: CGFloat, dh: CGFloat
    }

    /// The window's lag: till its app has answered, where the app last put it; then, standing still, where
    /// it stands (an app may refuse its size); while it animates, none. Nil out of view.
    func lag(_ c: Client) -> Lag? {
        let box = c.animation.current.insetBy(dx: c.bw, dy: c.bw)
        let shown: CGRect
        if !c.mac.placed.inSync {
            guard let a = c.mac.placed.applied else { return nil }
            shown = a
        } else if c.animation.running {
            return Lag(dx: 0, dy: 0, dw: 0, dh: 0)
        } else {
            shown = c.frame
        }
        return Lag(dx: shown.minX - box.minX, dy: shown.minY - box.minY, dw: shown.width - box.width, dh: shown.height - box.height)
    }

    /// A strip moves with its window's border (lag): bars and border lie together. A parked window's tab
    /// bar is not shown.
    func followingWindows(_ strips: [TabStrip], tabs: Bool) -> [TabStrip] {
        strips.compactMap { strip in
            guard let c = server.clientByIdAll(strip.above) else { return strip }
            if tabs && c.parked { return nil }
            guard let d = lag(c), d.dx != 0 || d.dy != 0 else { return strip }
            var s = strip
            s.frame.origin.x += d.dx
            s.frame.origin.y += d.dy
            for i in s.segments.indices {
                s.segments[i].frame.origin.x += d.dx
                s.segments[i].frame.origin.y += d.dy
            }
            return s
        }
    }

    func drawTabBars(_ strips: [TabStrip], style: TabStripStyle) {
        drawnTabBars = (strips, style)
        showTabBars(strips, style: style)
    }

    private func showTabBars(_ strips: [TabStrip], style: TabStripStyle) {
        let strips = followingWindows(strips, tabs: true)
        var style = withAppIcons(style, server.config.chutneyTabBarDecorateIcon)
        style.decorate = MacOSAppearance.bar(style.decorate, set: server.config.tabbardata, server.config)
        tabBars.update(strips, style: style, keyFocus: server.focused?.id)
        let frames = strips.map { CGRect(x: $0.frame.minX, y: $0.frame.minY, width: $0.frame.width, height: $0.barHeight) }
        router.publish { $0.tabBarFrames = frames }
    }

    func drawGroupBars(_ strips: [TabStrip], style: TabStripStyle) {
        drawnGroupBars = (strips, style)
        showGroupBars(strips, style: style)
    }

    private func showGroupBars(_ strips: [TabStrip], style: TabStripStyle) {
        let strips = followingWindows(strips, tabs: false)
        var style = withAppIcons(style, server.config.chutneyGroupBarDecorateIcon)
        style.decorate = MacOSAppearance.bar(style.decorate, set: server.config.groupbardata, server.config)
        groupBars.update(strips, style: style, keyFocus: server.focused?.id)
        let frames = strips.map { CGRect(x: $0.frame.minX, y: $0.frame.minY, width: $0.frame.width, height: $0.barHeight) }
        router.publish { $0.groupBarFrames = frames }
    }

    var windowCornerRadius: CGFloat { BorderGeometry.cornerRadius }

    func showOverview(_ cards: [OverviewCard], on m: Monitor, look: OverviewLook) {
        overviewOverlays[ObjectIdentifier(m)]?.close()
        let macOS = server.config.chutneyMacOSAppearance
        let overlay = OverviewOverlay(workArea: m.screen.workArea, top: m.screen.frame.minY, focusColor: look.focusColor, borderColor: look.borderColor,
                                      mango: macOS ? nil : .init(root: look.mango.root, borderWidth: look.mango.borderWidth,
                                                                 cornerRadius: look.mango.cornerRadius))
        overviewOverlays[ObjectIdentifier(m)] = overlay
        overlay.show(cards.map(Self.card))
    }

    func updateOverview(_ cards: [OverviewCard], on m: Monitor) {
        overviewOverlays[ObjectIdentifier(m)]?.update(cards.map(Self.card))
    }

    func captureOverviewCards(on m: Monitor, scale: CGFloat) {
        overviewOverlays[ObjectIdentifier(m)]?.captureCards(scale: scale)
    }

    func closeOverview(on m: Monitor) {
        overviewOverlays.removeValue(forKey: ObjectIdentifier(m))?.close()
        releaseHeldFocus()
    }

    static func card(_ c: OverviewCard) -> OverviewOverlay.Card {
        .init(id: c.id, frame: c.frame, title: c.title, pid: c.pid, focused: c.focused)
    }

    func showSwitcher(panel: CGRect, tiles: [SwitcherTilePicture], look: SwitcherLook, scale: CGFloat) {
        switcherPanel?.close()
        switcherPanel = SwitcherPanel(panel: panel, tiles: tiles.map(Self.tile),
                                      style: .init(focus: look.focus, border: look.border, macOS: server.config.chutneyMacOSAppearance),
                                      scale: scale)
    }

    func switcherApplyHighlight(_ tiles: [SwitcherTilePicture]) { switcherPanel?.highlight(tiles.map(Self.tile)) }

    func closeSwitcherPanel() {
        switcherPanel?.close()
        switcherPanel = nil
    }

    static func tile(_ t: SwitcherTilePicture) -> SwitcherPanel.Tile {
        .init(id: t.id, frame: t.frame, size: t.size, pid: t.pid, highlighted: t.highlighted)
    }

    func mangoBarDecorationCreate(_ m: Monitor, _ data: DecorateStyle, _ width: CGFloat, _ height: CGFloat) -> MangoBarDecoration? {
        let bar = TitleMessageBarDecoration(data) { [unowned self] in server.config }
        bar.setSize(width, height)
        return bar
    }

    func mangoJumpLabelNodeCreate(_ c: Client, _ data: DecorateStyle) -> MangoJumpLabel? {
        JumpLabelNode(data) { [unowned self] in server.config }
    }

    func findKeycodesForKeysym(_ keysym: Character) -> MultiKeycode {
        let codes = KeyNames.keyCodes(forName: String(keysym))
        return MultiKeycode(keycode1: codes.first, keycode2: codes.dropFirst().first, keycode3: codes.dropFirst(2).first)
    }

    func showSpecialDim(on m: Monitor, alpha: Float?, over: Set<ClientID>) {
        let id = m.screen.displayID
        guard let alpha else { specialDims[id]?.hide(); return }
        let backmost = stackingOrder().last { over.contains($0.id) }?.id
        let view = specialDims[id] ?? SpecialDimView()
        specialDims[id] = view
        view.show(frame: m.screen.frame, alpha: Double(alpha), below: backmost)
    }

    func showDropArea(_ area: CGRect?, color: RGBA) {
        guard let area else { dropArea?.hide(); return }
        if dropArea == nil { dropArea = DropAreaView() }
        dropArea?.show(area, color: color)
    }

    func nagSpawn(_ argv: [String], input: String) {
        nagDisplay.spawn(argv, input: input, selected: server.selectedMonitor?.screen.displayID,
                         macOS: server.config.chutneyMacOSAppearance)   // Port extension: not in mango (chutney_macos_appearance)
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

    func ipcGetLayoutStr() -> String { KeyNames.currentLayoutName() }

    var inputDevices: [InputDevice] { InputDevices.all() }

    var keyMappings: [KeyboardOptions.Mapping] = []
    var userKeyMappings: [KeyboardOptions.Mapping]?
    var appliedKeyMappings: [KeyboardOptions.Mapping]?

    func setKeyboardOptions(_ options: String) {
        var m = KeyboardOptions.mappings(KeyboardOptions.xkbOptions(options))
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

    func statusChanged() {
        memory.save(server)
        FitLayout.statusChanged(server)   // Port extension: chutney_fit_layout
        FullscreenTag.statusChanged(server)   // Port extension: chutney_fullscreen_tag
        onStatusChange?()
    }

    func startWatching() {
        memory.restore(server)
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
        edgePlates.hideAll()
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
            writer(for: c.pid)?.setFrame(c.element, id: c.id, frame: Self.clampToScreen(f, m.screen.workArea))
        }
        for (c, _) in away.values {
            guard let m = c.mon ?? server.monitors.first else { continue }
            let real = windowServerFrame(c.id) ?? c.frame
            guard c.parked || Hider.isParked(real, in: m.screen.frame) else { continue }
            let f = c.isfloating ? c.floatGeom.insetBy(dx: c.bw, dy: c.bw) : c.tile
            writer(for: c.pid)?.setFrame(c.element, id: c.id, frame: Self.clampToScreen(f, m.screen.workArea))
        }
        restoreAppSettings(restore)
        _ = restore.wait(timeout: .now() + 2)
    }

    func rescan() {
        frameClock.whenIdle { [weak self] in self?.watcher.refreshAll(recheckRejected: true) }
    }

    func spawn(_ command: String) { Spawn.run(command) }

    func spawnShell(_ command: String) { Spawn.shell(command) }

    var animationsRunning: Bool { frameClock.animationsRunning }
    func whenAnimationsIdle(_ body: @escaping () -> Void) { frameClock.whenIdle(body) }

    var screens: [Screen] { Screens.all() }

    func windowServerFrame(_ id: ClientID) -> CGRect? {
        if let windowServerOverride { return windowServerOverride(id) }
        return AppWorker.windowServerFrame(id)
    }

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
        gestures.onEvent = { [weak self] event, time in
            MainActor.assumeIsolated {
                switch event {
                case .update(let s): self?.swipeUpdate(s, time)
                case .end(_, let cancelled): self?.swipeEnd(cancelled: cancelled)
                }
            }
        }
        let close: @Sendable (Notification) -> Void = { [weak server] _ in
            MainActor.assumeIsolated { server?.switcherClose() }
        }
        let dnc = DistributedNotificationCenter.default(), ws = NSWorkspace.shared.notificationCenter
        let layoutChanged: @Sendable (Notification) -> Void = { [weak server] _ in
            MainActor.assumeIsolated { server?.printstatus(.kbLayout) }
        }
        // Behind a locked screen Accessibility gives no windows: they are read again once it is unlocked.
        let unlocked: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.watcher.refreshAll(recheckRejected: true) }
        }
        observers = [
            dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: close),
            dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: unlocked),
            ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main, using: close),
            dnc.addObserver(forName: Notification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
                            object: nil, queue: .main, using: layoutChanged),
        ]
    }

    func keyboardCancelPendingReleaseBind() { router.cancelPendingReleaseBind() }

    func watchGestures(_ on: Bool) {
        if on { gestures.start() } else { gestures.stop() }
    }

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
            s.overcircleActive = state.overcircleActive
            s.switcherActive = state.switcherActive
            s.tagCombo = state.tagCombo
            s.hyper = hyper
            s.hyperKey = hyperKey
            s.wantsMouseMoved = state.wantsMouseMoved
            s.cursorHideOnKeypress = state.cursorHideOnKeypress
            s.hoverResizeCursor = state.hoverResizeCursor
        }
    }

    func publishGlobalKeys(_ keys: [GlobalKey]) {
        let routed = keys.map { InputRouter.RoutedGlobalKey(mods: $0.mods, keyCodes: Set(KeyNames.keyCodes(forName: $0.keyName)), pid: $0.pid) }
        router.publish { $0.globalKeys = routed }
    }

    func setCursorHidden(_ hidden: Bool) {
        if hidden { CursorHider.hide() } else { CursorHider.show() }
    }

    func setCursor(_ name: String?) {
        // mango's default cursor where no client is: the port's own windows (its panels) set their own
        if name == "default" && NSApp.isActive { return }
        CursorHider.setCursor(name)
    }

    /// The window server's answer for a point, kept for the turn: mango asks twice for one motion.
    private var surfaceAtTurn: (p: CGPoint, id: ClientID?)?

    func surfaceAt(_ p: CGPoint) -> ClientID? {
        if let k = surfaceAtTurn, k.p == p { return k.id }
        if surfaceAtTurn == nil {
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.surfaceAtTurn = nil } }
        }
        let id = CursorHider.windowAt(p)
        surfaceAtTurn = (p, id)
        return id
    }

    /// A window's owner does not change: asked for once.
    private var surfaceOwners: [ClientID: pid_t] = [:]


    /// A managed window is its own client; another window of an app (a menu, a popup) belongs to the
    /// app's window that had the focus last, as a popup belongs to its toplevel.
    func toplevelFromWlrSurface(_ surface: ClientID) -> Client? {
        if let c = server.clientByIdAll(surface) { return c }
        let pid: pid_t
        if let known = surfaceOwners[surface] {
            pid = known
        } else {
            guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(surface)) as? [[String: Any]])?.first,
                  let p = info[kCGWindowOwnerPID as String] as? pid_t else { return nil }
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

    var canCapture: Bool { WindowSnapshot.hasPermission }

    func askToCapture() { Permissions.shared.askForCapture() }

    func keyboardHardModifiers() -> Modifiers {
        KeyboardOptions.hyperMods(Modifiers(cgFlags: CGEventSource.flagsState(.combinedSessionState)),
                                  hyper: KeyboardOptions.hyperSet(server.config), keyHeld: router.hyperKeyHeld)
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

    /// Port extension: chutney_fullscreen_tag (with the key off the app is not told).
    func clientNotifyFullscreen(_ c: Client, _ fullscreen: Bool) { FullscreenTag.notify(server, c, fullscreen) }

    func settle(_ c: Client) {
        guard let q = writer(for: c.pid) else { return }
        readBack(c, q)
    }

    func grabBegan(_ c: Client) { watcher.suppressGeometry(c.id, for: 3600) }
    func grabEnded(_ c: Client) { watcher.suppressGeometry(c.id, for: 0.4) }
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
