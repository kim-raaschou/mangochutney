import Foundation
import CoreGraphics
import QuartzCore

public let mangoVersion = "0.0.4-20261109-beta"
// not in mango: meson.build's VERSION, with the commit of mango this port follows
public let VERSION = "0.18.5(21f80a9)"

/* Scene layer ids; the scene tree keeps one tree per layer. */
public enum Lyr: Int, Comparable {
    case bg
    case blur
    case bottom
    case tile
    case maximize
    case float
    case top
    case fullscreen
    case overlay
    case specialDim
    case specialTile
    case specialMaximize
    case specialTop
    case specialFloat
    case specialFullscreen
    case fadeOut
    case specialOverlay
    case imPopup
    case block

    public static func < (a: Lyr, b: Lyr) -> Bool { a.rawValue < b.rawValue }
}

@MainActor
public final class MangoServer {
    public internal(set) var config = Config()
    var tagmask: UInt32 = (1 << 9) - 1 /* default 9 tags; updated with config.tag_num */
    public var configURL: URL
    public internal(set) var configErrors: [ConfigError] = []
    var configFiles: [URL] = []

    public internal(set) var monitors: [Monitor] = []
    public package(set) var clients: [Client] = []
    func clientById(_ id: ClientID) -> Client? { clients.first { $0.id == id } }
    public func clientByIdAll(_ id: ClientID) -> Client? { clientsAll.first { $0.id == id } }
    public var clientsAll: [Client] {
        var out: [Client] = []
        for c in clients {
            if c.isGroupMember { out += groupMembers(c).filter { m in m === c || m.groupParked } } else { out.append(c) }
        }
        return out
    }
    public package(set) var focusStack: [ClientID] = []
    public package(set) var selectedMonitor: Monitor!
    public var keyMode = "default" { didSet { publishInputState() } }

    var ipc: IPCServer?

    package var enableGaps = true
    var renderBorder = true
    package var drawsOverlays = false
    package internal(set) var started = false
    public var cliDebugLog = false

    package var tagCombo = false { didSet { if tagCombo != oldValue { publishInputState() } } }
    var switcherState: SwitcherState? { didSet { publishInputState() } }
    var publishedGlobalKeys = false
    package var grab: Grab? {
        didSet { if (oldValue == nil) != (grab == nil) { publishInputState() } }   // not in mango: the event tap's snapshot
    }
    var startDragWindow = false
    var confinePointerLast: ClientID?
    var dragBeginCursor: CGPoint = .zero
    package var dragTile: DragTile?
    package var system: WindowSystem!
    /// Port extension: not in mango. Where the port's extensions join (PortHooks.swift).
    package var portHooks = PortHooks()
    package var groupBarDrag: (client: Client, start: CGPoint)?
    var cursorHidden = false
    package var hoverResizeEdge: WlrEdges = []
    var hoverResizeFloating = false
    var cursorHideTimerArmed = false
    var lastPointerActivity: CFTimeInterval = 0
    var swipeDrive = SwipeDrive()
    var swipeActive = false
    var swipeLocked = false
    var swipeHorizontal = false
    var swipeDx = 0.0
    var swipeDy = 0.0
    var swipeFingers = 0
    var gestureDriveMon: Monitor?
    var gestureDriveActive = false
    var bordersDirty = false   // not in mango: a border changed; the port draws them all at once
    var watchTimer: EventSource?
    var watchedFiles: [WatchedFile] = []
    var watcherActive = false
    var kqueueFd: Int32 = -1
    var kqueueSource: EventSource?
    var scrollerFocusLock = false

    /// The boundary, not in mango: the port's status change, which printstatus gives.
    public var onStateChange: (() -> Void)?

    public init(configURL: URL? = nil) {
        self.configURL = configURL ?? ConfigParser.defaultConfigURL()
    }

    public func setup() {
        drawsOverlays = true
        system.prepare()   // not in mango: the port's side
        parseConfig()
        if cliDebugLog {
            config.logLevel = .debug
        }
        // not in mango: no init_baked_points, the port's animator bakes its own curves
        setEnvWithoutDisplay()
        wlrLogInit(config.logLevel)
        system.setKeyboardOptions(config.xkbRulesOptions)   // not in mango: keyboard_group_create's keymap, the port's side
        // Port extension: not in mango. The port takes its own options.
        for loaded in portHooks.configLoaded { loaded(self) }
        rebuildMonitors()
        system.startWatching()   // not in mango: the port's side
        publishInputState()
        system.startInput()   // not in mango: the port's side
        system.watchGestures(!config.gestureBindings.isEmpty)   // not in mango: the port's side

        let server = IPCServer(server: self, loop: system.eventLoop)
        do { try server.ipcInit(); ipc = server } catch { wlrLog(.error, "IPC server failed: \(error)") }   // not in mango: ipc_init's failures thrown
        configWatcherInit(system.eventLoop)
        configErrorNagInit()

        // not in mango: run's part of the start, in setup
        setEnvDisplay()
        started = true
        arrangeAll(false)
        printstatus(.arrangge)
        pointerCursorActivity()
        runExec()
        runExecOnce()
    }

    public func cleanup() {
        // not in mango: the pointer shown again, as macOS keeps it hidden after mango
        if cursorHidden { cursorHidden = false; system.setCursorHidden(false) }
        system.drawBorders([])
        system.shutdown()   // not in mango: the port's side
        ipc?.ipcCleanup()
        configWatcherDestroy()
        configErrorNagDestroy()
    }

    func clientNoRadiusActive(_ c: Client) -> Bool {
        guard let m = c.mon else { return false }

        if c.isfullscreen || (config.noRadiusWhenSingle && tiledClients(m).count == 1) {
            return true
        }

        return config.monocleNoRadius && !c.isfloating && !c.isminimized && !c.isunglobal
            && !m.isoverview && m.layout == .monocle
    }

    // not in mango: the server's side of parse_config, the config read, its errors and the nag
    func parseConfig() {
        configErrorStoreBegin()
        let parsed = ConfigParser.parseConfig(fileAt: configURL, emits: true)
        config = parsed.config
        updateGlobalVar()   // not in mango: override_config's last step, as parse_config runs it
        configErrors = parsed.errors
        configFiles = parsed.sourcedFiles
        configErrorStoreEnd()
        configErrorNagUpdate()
    }

    func configGetFilePaths() -> [String] {
        configFiles.map(\.path)
    }

    func setEnvWithoutDisplay() {
        for (k, v) in config.envVars {
            if k == "DISPLAY" {
                continue // Skip setting DISPLAY
            }
            setenv(k, v, 1)
        }
    }

    func setEnvDisplay() {
        for (k, v) in config.envVars where k == "DISPLAY" {
            setenv("DISPLAY", v, 1)
        }
    }

    func runExec() {
        for cmd in config.exec { system.spawnShell(cmd) }
    }

    func runExecOnce() {
        for cmd in config.execOnce { system.spawnShell(cmd) }
    }

    func reapplyProperty() {
        // reset border width when config change
        for c in clients {
            // not in mango: no bw to reset, the border width is read from the config where it is drawn
            clientSetGroupConfig(c)
            // not in mango: no client_set_tab_bar_config, the port draws the tab bar from the config
        }
    }

    func reapplyTagrule() {
        for m in monitors {
            parseTagrule(m)
        }
    }

    func resetOption() {
        // not in mango: no init_baked_points, the port's animator bakes its own curves
        pointerCursorActivity()
        resetKeyboardLayout()
        // not in mango: no reset_blur_params, macOS has no blur (MangoCompat)
        setEnvWithoutDisplay()
        setEnvDisplay()
        runExec()

        reapplyCursorStyle()
        reapplyProperty()
        // not in mango: no reapply_rootbg, the port reads rootcolor where it draws
        // not in mango: no reapply_keyboard, key repeat is macOS's (MangoCompat)
        system.watchGestures(!config.gestureBindings.isEmpty)   // not in mango: the port's side, where reapply_pointer stands
        reapplyMaster()

        reapplyTagrule()
        // not in mango: no reapply_monitor_rules, monitor_rule is macOS's (MangoCompat)

        // Port extension: not in mango. The port takes its own options.
        for loaded in portHooks.configLoaded { loaded(self) }
        publishInputState()   // not in mango: the event tap's snapshot

        /* A global reload must re-apply every monitor, not just the selected one:
         * layout-affecting options such as always_show_group_bar reserve or release
         * space on all outputs. */
        for m in monitors {
            titleMessageBarApplyConfig(m)
            titleMessageBarUpdate(m)
            arrange(m, false, false)
        }
    }

    func resetKeyboardLayout() {
        system.setKeyboardOptions(config.xkbRulesOptions)   // not in mango: xkb_keymap_new_from_names, the port's side
    }

    func reapplyCursorStyle() {
        // not in mango: no xcursor manager, macOS draws the cursor (MangoCompat)
        if !cursorHidden {
            lastPointerActivity = CACurrentMediaTime()
            armCursorHideTimer()
        }
    }

    func reapplyMaster() {
        for i in 0..<PERTAG_SLOTS {
            for m in monitors {
                m.pertag.nmasters[i] = Int32(config.defaultNmaster)
                m.pertag.mfacts[i] = Float(config.defaultMfact)
                m.gappih = Int32(config.gappih)
                m.gappiv = Int32(config.gappiv)
                m.gappoh = Int32(config.gappoh)
                m.gappov = Int32(config.gappov)
                m.specialGappih = Int32(config.specialGappih)
                m.specialGappiv = Int32(config.specialGappiv)
                m.specialGappoh = Int32(config.specialGappoh)
                m.specialGappov = Int32(config.specialGappov)
            }
        }
    }

    public func reloadConfig() {
        let oldTagNum = config.tagNum
        parseConfig()
        resetTag(oldTagNum)
        resetOption()
        printstatus(.arrangge)
        configWatcherUpdate()
    }

    func resetTag(_ oldTagNum: Int) {
        guard config.tagNum != oldTagNum else { return }
        let tagmask = TAGMASK
        let last: UInt32 = 1 << UInt32(config.tagNum - 1)
        for c in clientsAll where c.tags & ~tagmask != 0 {
            c.tags = last
            c.oldtags = last
        }
        for m in monitors {
            m.tagset[0] &= tagmask
            m.tagset[1] &= tagmask
            if m.tagset[m.seltags] == 0 { m.tagset[m.seltags] = last }
            if m.pertag.curtag > UInt32(config.tagNum) { m.pertag.curtag = UInt32(config.tagNum) }
            if m.pertag.prevtag > UInt32(config.tagNum) { m.pertag.prevtag = UInt32(config.tagNum) }
        }
    }

    // not in mango: handle_new_output and cleanup_monitor for the screens the system has (macOS reports the set)
    func rebuildMonitors(screens given: [Screen]? = nil) {
        let screens = given ?? system.screens
        var newMonitors: [Monitor] = []
        for s in screens {
            if let existing = monitors.first(where: { $0.screen.displayID == s.displayID }) {
                existing.screen = s
                newMonitors.append(existing)
            } else {
                let m = Monitor(screen: s, config: config)
                // Applies the tag rule.
                parseTagrule(m)
                newMonitors.append(m)
            }
        }
        guard !newMonitors.isEmpty else { return }
        let removed = monitors.filter { m in !newMonitors.contains { $0 === m } }
        let added = newMonitors.filter { m in !monitors.contains { $0 === m } }
        for m in removed where m.isoverview {
            // not in mango: the closed monitor's overview, not the selected one's (a mango bug, docs/afvigelser.md §6)
            let keep = selectedMonitor
            selectedMonitor = m
            toggleOverview()
            selectedMonitor = keep
        }
        for m in removed { titleMessageBarFinish(m) }
        monitors = newMonitors
        if selectedMonitor == nil || removed.contains(where: { $0 === selectedMonitor }) {
            selectedMonitor = monitors.first { $0.screen.isMain } ?? monitors[0]
        }
        for c in clientsAll where c.mon == nil || removed.contains(where: { $0 === c.mon }) {
            if c.oldmonname == nil, let from = c.mon { clientUpdateOldmonnameRecord(c, from) }
            clientChangeMon(c, to: selectedMonitor, focus: false)
        }
        for m in added {
            for c in clientsAll where c.oldmonname == m.screen.displayID && c.mon !== m {
                clientChangeMon(c, to: m, focus: false)
            }
        }
        if started && (!removed.isEmpty || !added.isEmpty) { clientFocus(clientFocusTop(selectedMonitor), true) }
    }

    func clientChangeMon(_ c: Client, to m: Monitor, focus: Bool = true) {
        clientSetMonitor(c, m, c.tags, focus: focus)
        c.parked = false   // not in mango: the system places it on the new display
        if c.isfloating {
            c.floatGeom = clientCenterGeometry(c, m, c.floatGeom)
        }
    }

    public func handleOutputLayoutChange() {
        rebuildMonitors()
        arrangeAll(false)
        printstatus(.arrangge)
    }

    package func monitorAtPoint(_ p: CGPoint) -> Monitor? {
        if let m = monitors.first(where: { $0.screen.frame.contains(p) }) { return m }
        return monitors.min { a, b in a.screen.frame.center.distance(to: p) < b.screen.frame.center.distance(to: p) }
    }

    /// Not in mango: the VISIBLEON filter as a list.
    func visibleClients(_ m: Monitor) -> [Client] {
        clients.filter { VISIBLEON($0, m) }
    }

    /// Not in mango: the VISIBLEON and ISTILED filter as a list.
    package func tiledClients(_ m: Monitor) -> [Client] {
        visibleClients(m).filter {
            !$0.isunglobal && !$0.isfloating && !$0.isfullscreen && !$0.ismaximizescreen && !SCRATCHPAD_SHOWN($0) && !$0.isminimized
        }
    }

    /// Not in mango: the special tag's windows as a list.
    func specialClients(_ m: Monitor) -> [Client] {
        guard m.tagset[m.seltags] & TAG0_MASK != 0 else { return [] }
        return clients.filter {
            $0.mon === m && $0.tags & TAG0_MASK != 0 && !$0.isminimized
        }
    }

    package var focused: Client? { selectedMonitor.sel.flatMap { clientByIdAll($0) } }

    package func clientFocusTop(_ m: Monitor) -> Client? {
        for id in focusStack {
            if let c = clientByIdAll(id), !c.isunglobal, VISIBLEON(c, m) { return c }
        }
        return nil
    }

    // not in mango: a frame's length, for frame_serial (mango 0.18.2's drag_refresh_interval_ms)
    func dragRefreshIntervalMs(_ m: Monitor?) -> UInt32 {
        var refreshMhz = m?.screen.refresh ?? 0
        if refreshMhz <= 0 { refreshMhz = 60000 }
        let ms = Int32(1000.0 / (Double(refreshMhz) / 1000.0))
        return ms > 0 ? UInt32(ms) : 1
    }

    /// Not in mango: arrange on every monitor.
    package func arrangeAll(_ wantAnimation: Bool) {
        for m in monitors { arrange(m, wantAnimation, false) }
    }

    package func arrange(_ m: Monitor, _ wantAnimation: Bool, _ fromView: Bool) {
        guard started else { return }
        // not in mango: pre_calculate_before_arrange's hide_clients, here before the overview
        m.hideClients = 0
        for c in clients where c.isminimized { m.hideClients += 1 }
        if m.isoverview {
            overview(m)
            return
        }
        if m.sel == nil { m.sel = clientFocusTop(m)?.id }
        if isSpecialActive(m) && specialClients(m).isEmpty {
            if fromView { m.specialEmptyView = true }
            else if !m.specialEmptyView { toggleSpecialTagMon(m); return }
        } else {
            m.specialEmptyView = false
        }
        for c in clientsAll where c.mon === m && (c.isglobal || c.isunglobal) { c.tags = m.tagset[m.seltags] }

        let visible = visibleClients(m)
        let tiled = tiledClients(m)
        let work = m.screen.workArea
        // not in mango: the layout engine's gaps, from the monitor's
        let monGaps = isSpecialActive(m)
            ? Gaps(ih: CGFloat(m.specialGappih), iv: CGFloat(m.specialGappiv), oh: CGFloat(m.specialGappoh), ov: CGFloat(m.specialGappov))
            : Gaps(ih: CGFloat(m.gappih), iv: CGFloat(m.gappiv), oh: CGFloat(m.gappoh), ov: CGFloat(m.gappov))
        let gaps = enableGaps ? monGaps : .zero
        let fakeTiled = visible.filter { !$0.isfloating && !$0.isminimized && !$0.isunglobal }

        // not in mango: pre_calculate_before_arrange's weights, here in arrange
        let nmasters = Int(m.pertag.nmasters[getMonCurtag(m)])
        var totalMaster: CGFloat = 0, totalStack: CGFloat = 0, totalLeft: CGFloat = 0, totalRight: CGFloat = 0
        var masterNum = 0, stackNum = 0
        for (i, c) in fakeTiled.enumerated() {
            if c.masterSizeWeight <= 0 { c.masterSizeWeight = 1 }
            if c.stackSizeWeight <= 0 { c.stackSizeWeight = 1 }
            if i < nmasters {
                masterNum += 1
                totalMaster += c.masterSizeWeight
            } else {
                stackNum += 1
                totalStack += c.stackSizeWeight
                let stackIndex = i - nmasters
                if (stackIndex % 2 == 1) != (tiled.count % 2 == 0) {
                    c.isleftstack = false
                    totalRight += c.stackSizeWeight
                } else {
                    c.isleftstack = true
                    totalLeft += c.stackSizeWeight
                }
            }
        }
        resetSizePerMon(m, fakeTiled, totalLeftStackWeight: totalLeft, totalRightStackWeight: totalRight,
                        totalStackWeight: totalStack, totalMasterWeight: totalMaster, masterNum: masterNum, stackNum: stackNum)

        let members = tabMembers(m)
        let strips = Set(members.map(\.id))
        let shownMember = tabChainFocus(members, on: m)
        let tabHidden = Set(members.filter { $0 !== shownMember }.map(\.id))
        for c in clientsAll where c.mon === m { c.isTabHidden = tabHidden.contains(c.id) }
        func tile(_ c: Client) -> CGRect {
            var f = c.geom   // not in mango: the layout engine's input
            let top = topBars(c, tabMember: strips.contains(c.id))
            f.origin.y -= top
            f.size.height += top
            return f
        }
        var layoutClients = fakeTiled.map { c in
            LayoutClient(id: c.id, currentFrame: tile(c), isfullscreen: c.isfullscreen, isMaximized: c.ismaximizescreen,
                         scrollerProportion: c.scrollerProportion, scrollerProportionSingle: c.scrollerProportionSingle,
                         masterInnerPer: c.masterInnerPer, stackInnerPer: c.stackInnerPer,
                         scrollerStackWeight: c.scrollerStackWeight, masterMfactPer: c.masterMfactPer,
                         gridColPer: c.gridColPer, gridRowPer: c.gridRowPer,
                         gridColIdx: c.gridColIdx, gridRowIdx: c.gridRowIdx)
        }
        let kind = m.layout
        let curtag = getMonCurtag(m)
        // not in mango: the layout engine's pertag settings and state, from the slot's
        var settings = PertagSettings(nmaster: Int(m.pertag.nmasters[curtag]), mfact: CGFloat(m.pertag.mfacts[curtag]),
                                      scrollerDefaultProportion: CGFloat(m.pertag.scrollerDefaultProportion[curtag]),
                                      scrollerDefaultProportionSingle: CGFloat(m.pertag.scrollerDefaultProportionSingle[curtag]),
                                      scrollerIgnoreProportionSingle: m.pertag.scrollerIgnoreProportionSingle[curtag])
        let state = TagLayoutState()
        state.scrollerState = m.pertag.scrollerState[curtag]
        state.dwindleRoot = m.pertag.dwindleRoot[curtag]
        var input = LayoutInput(workArea: work, monitorFrame: m.screen.frame, gaps: gaps, clients: layoutClients,
                                focusedID: m.sel, prevFocusedID: m.prevsel, pertag: settings,
                                config: config, cursor: system.pointer)
        input.enableGaps = enableGaps
        input.startDragWindow = startDragWindow
        if let p = m.prevsel.flatMap({ clientByIdAll($0) }) {
            input.prevFocusedScroll = (!p.isfloating && !p.isminimized && !p.isunglobal,
                                       p.scrollerProportion ?? CGFloat(m.pertag.scrollerDefaultProportion[getMonCurtag(m)]))
        }
        input.fullscreenInView = Set(visible.filter { $0.isfullscreen || $0.ismaximizescreen }.map(\.id))
        var result = LayoutEngine.arrange(kind, input: input, state: state)
        for (id, p) in result.gridPlaces {
            guard let c = clientByIdAll(id) else { continue }
            c.gridColPer = p.colPer; c.gridRowPer = p.rowPer; c.gridColIdx = p.colIdx; c.gridRowIdx = p.rowIdx
        }
        reserveTabStrip(&result.frames, on: m)
        for c in tiled where clientWantsGroupBar(c) {
            let h = CGFloat(config.groupBarHeight)
            guard var f = result.frames[c.id], f.height > h else { continue }
            f.origin.y += h
            f.size.height -= h
            result.frames[c.id] = f
        }

        var raise: [Client] = []
        // not in mango: the boxes mango's setfloating, setfullscreen, setmaximizescreen and
        // reset_maximizescreen_size leave in c->geom, set here; our floatGeom is kept apart
        for c in visible where !c.isunglobal && dragTile?.client !== c {
            let bw = borderWidth(c, on: m)
            if SCRATCHPAD_SHOWN(c) {
                c.geom = system.keepOnDisplay(clientSetBounds(c, c.floatGeom, sceneGeometry), m).insetBy(dx: -bw, dy: -bw)   // not in mango: the port's side
                raise.append(c)
            } else if c.isfullscreen {
                c.geom = m.screen.frame
                raise.append(c)
            } else if c.ismaximizescreen {
                let noGap = config.monocleNoGap && kind == .monocle
                var box = work.insetBy(horizontal: noGap ? 0 : CGFloat(config.gappoh),
                                       vertical: noGap ? 0 : CGFloat(config.gappov))
                if clientWantsGroupBar(c) {
                    box.origin.y += CGFloat(config.groupBarHeight)
                    box.size.height -= CGFloat(config.groupBarHeight)
                }
                c.geom = box
                raise.append(c)
            } else if c.isfloating {
                c.geom = system.keepOnDisplay(clientSetBounds(c, c.floatGeom, sceneGeometry), m).insetBy(dx: -bw, dy: -bw)   // not in mango: the port's side
                if c.isoverlay { raise.append(c) }
            } else if c.isoverlay {
                raise.append(c)
            }
        }

        // pre_calculate_before_arrange's set_arrange_visible and set_arrange_hidden
        for c in clients where !c.iskilling && c.mon === m {
            if VISIBLEON(c, m) {
                if !c.isunglobal && dragTile?.client !== c { setArrangeVisible(m, c, wantAnimation) }   // not in mango: the tile being dragged stays where it is
            } else if specialKeepBgClient(m, c) {
                c.tagVisible = true
                clientUpdateVisibility(c)
                c.animation.running = false
                c.animation.tagining = false
                c.animation.tagouting = false
            } else if c !== grab?.client {
                setArrangeHidden(m, c, wantAnimation)
            }
        }

        // the layout's resize of each tiled client
        for c in visible where !c.isunglobal && dragTile?.client !== c && !c.isfloating && !c.isfullscreen
            && !c.ismaximizescreen && !SCRATCHPAD_SHOWN(c) {
            guard let box = result.frames[c.id] else { continue }
            resize(c, box, ResizeOpts())
        }
        if kind.isMonocleLike, let s = m.sel.flatMap({ clientByIdAll($0) }), !s.isfloating { raise.insert(s, at: 0) }

        let sel = m.sel.flatMap { clientByIdAll($0) }
        for c in raise where c !== sel {
            if let sel, sel.pid == c.pid { continue }
            system.raise(c)
        }
        if let sel, raise.contains(where: { $0 === sel }) { system.raise(sel) }

        specialUpdateDim(m)
        updateBorders()
        if config.tagGather { tagGatherApply(m) }
    }

    func clientCenterGeometry(_ c: Client?, _ tm: Monitor?, _ geom: CGRect, _ offsetX: Int = 0, _ offsetY: Int = 0) -> CGRect {
        let m: Monitor = tm ?? selectedMonitor
        let w = m.screen.workArea, full = m.screen.frame
        var box = geom
        if !(c?.noForceCenter ?? false) {
            box.origin.x = w.minX + ((w.width - geom.width) / 2).rounded(.towardZero)
            box.origin.y = w.minY + ((w.height - geom.height) / 2).rounded(.towardZero)
        }
        if offsetX != 0 {
            let len = ((w.width - box.width - 2 * CGFloat(m.gappoh)) / 2).rounded(.towardZero)
            box.origin.x += (len * CGFloat(offsetX) / 100).rounded(.towardZero)
            if box.minX < full.minX { box.origin.x = full.minX }
            if box.maxX > full.maxX { box.origin.x = full.maxX - box.width }
        }
        if offsetY != 0 {
            let len = ((w.height - box.height - 2 * CGFloat(m.gappov)) / 2).rounded(.towardZero)
            box.origin.y += (len * CGFloat(offsetY) / 100).rounded(.towardZero)
            if box.minY < full.minY { box.origin.y = full.minY }
            if box.maxY > full.maxY { box.origin.y = full.maxY - box.height }
        }
        return box
    }

/// mango client_center_geometry (manage/client.c). Not in mango: without offsets, in a work area.
    func clientCenterGeometry(_ c: Client, _ f: CGRect, in work: CGRect) -> CGRect {
        guard !c.noForceCenter else { return f }
        return CGRect(x: work.midX - f.width / 2, y: work.midY - f.height / 2, width: f.width, height: f.height)
    }

    func specialKeepBgClient(_ m: Monitor, _ c: Client) -> Bool {
        guard isSpecialActive(m), !c.isminimized, c.mon === m else { return false }
        return (m.pertag.prevtag > 0 && c.tags & (1 << UInt32(m.pertag.prevtag - 1)) != 0)
            || c.tags & (m.tagset[m.seltags ^ 1] & ~TAG0_MASK) != 0
    }

    func getMonitorActiveTagset(_ m: Monitor) -> UInt32 {
        guard isSpecialActive(m) else { return m.tagset[m.seltags] }
        let prev = m.tagset[m.seltags ^ 1] & ~TAG0_MASK
        return prev != 0 ? prev : (m.pertag.prevtag > 0 ? 1 << UInt32(m.pertag.prevtag - 1) : 1)
    }

    func toggleSpecialTagMon(_ m: Monitor) {
        guard !m.isoverview else { return }
        selectedMonitor = m
        if isSpecialActive(m) {
            clientViewOnMonitor(specialTagPreviousTagset(m), on: m, changeFocus: true)
        } else {
            specialTagPrepareTarget(m)
            clientViewOnMonitor(TAG0_MASK, on: m)
        }
    }

    package func isSpecialActive(_ m: Monitor) -> Bool {
        m.tagset[m.seltags] & TAG0_MASK != 0 && !m.isoverview
    }

    package func specialUpdateDim(_ m: Monitor) {
        guard drawsOverlays else { return }
        system.showSpecialDim(on: m, alpha: isSpecialActive(m) ? config.specialDim : nil,
                              over: Set(specialClients(m).map(\.id)))
    }

    var sceneGeometry: CGRect { monitors.map(\.screen.frame).reduce(CGRect.null) { $0.union($1) } }

    // not in mango: returns the frame instead of setting c->geom
    func clientSetBounds(_ c: Client, _ geom: CGRect, _ bbox: CGRect) -> CGRect {
        var g = geom
        let least = 1 + 2 * (c.mon.map { borderWidth(c, on: $0) } ?? 0)
        g.size.width = max(least, g.width)
        g.size.height = max(least, g.height)
        if g.minX >= bbox.maxX { g.origin.x = bbox.maxX - g.width }
        if g.minY >= bbox.maxY { g.origin.y = bbox.maxY - g.height }
        if g.maxX <= bbox.minX { g.origin.x = bbox.minX }
        if g.maxY <= bbox.minY { g.origin.y = bbox.minY }
        return g
    }

    /// Not in mango: a geometry helper.
    package static func frameDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }

    func getBorderColor(_ c: Client) -> RGBA {
        let isFocused = c.mon === selectedMonitor && selectedMonitor.sel == c.id
        if c.mon !== selectedMonitor { return config.bordercolor }
        if c.isurgent { return config.urgentcolor }
        guard isFocused else { return config.bordercolor }
        if c.isInScratchpad { return config.scratchpadcolor }
        if c.isglobal { return config.globalcolor }
        if c.isoverlay { return config.overlaycolor }
        if c.ismaximizescreen { return config.maximizescreencolor }
        return config.focuscolor
    }

    func checkHitNoBorder(_ c: Client) -> Bool {
        guard let m = c.mon, c.tags != 0 else { return false }
        let isoverview = m.isoverview
        var hitNoBorder = false
        if !renderBorder { hitNoBorder = true }
        if !isoverview && m.pertag.noRenderBorder[getClientTagIdx(c)] { hitNoBorder = true }
        if config.noBorderWhenSingle {
            let shown = visibleClients(m)
            let visible = shown.filter { !$0.isunglobal }.count
            let fakeTiling = shown.filter { !$0.isfloating && !$0.isminimized && !$0.isunglobal }.count
            if (!c.isfloating && !c.isminimized && !c.isunglobal && fakeTiling == 1) || visible == 1 {
                hitNoBorder = true
            }
        }
        if config.monocleNoBorder && !c.isfloating && !isoverview && m.layout == .monocle { hitNoBorder = true }
        return hitNoBorder
    }

    // not in mango: c->bw (no_border, fullscreen) as check_hit_no_border leaves it, in points
    func borderWidth(_ c: Client, on m: Monitor) -> CGFloat {
        guard config.borderpx > 0, !c.noBorder, !c.isfullscreen, !checkHitNoBorder(c) else { return 0 }
        return CGFloat(config.borderpx)
    }

    // not in mango: client_draw_border for every window at once; the port draws the borders in one overlay
    package func updateBorders() {
        tabRefreshBars()
        guard renderBorder, config.borderpx > 0 else { system.drawBorders([]); return }
        var specs: [BorderSpec] = []
        for m in monitors {
            let strip = tabChainFocus(tabMembers(m), on: m).flatMap { !$0.parked && !$0.isfullscreen && !$0.ismaximizescreen ? $0 : nil }
            let tiledCount = tiledClients(m).count
            for c in visibleClients(m) + specialClients(m) where !c.parked {
                let width = borderWidth(c, on: m)
                guard width > 0 else { continue }
                let focusedHere = m === selectedMonitor && m.sel == c.id
                if m.layout.isMonocleLike && !c.isfloating && m.sel != c.id && tiledCount > 1 {
                    if m.layout == .monocle { continue }
                }
                var f = animationCurrent(c).insetBy(dx: c.bw, dy: c.bw)
                let top = !barsInsideBorder ? 0
                    : (c === strip ? CGFloat(config.tabBarHeight) : 0) + (clientCheckTabNodeVisible(c, on: m) ? CGFloat(config.groupBarHeight) : 0)
                f = CGRect(x: f.minX, y: f.minY - top, width: f.width, height: f.height + top)
                let radius = clientNoRadiusActive(c) ? 0 : CGFloat(config.borderRadius)
                specs.append(BorderSpec(id: c.id, frame: f, color: getBorderColor(c), width: width, radius: radius,
                                        split: clientDrawSplitBorder(c, on: m)))
            }
        }
        if drawsOverlays { system.drawBorders(specs) }
    }

    func clientDrawSplitBorder(_ c: Client, on m: Monitor) -> (side: BorderSpec.SplitSide, color: RGBA)? {
        guard config.dwindleManualSplit, m.layout == .dwindle, !c.isfloating, !c.isfullscreen,
              tiledClients(m).contains(where: { $0 === c }),
              let horizontal = m.pertag.dwindleRoot[getMonCurtag(m)].leafSplitHorizontal(for: c.id) else { return nil }
        return (horizontal ? .right : .bottom, c.isurgent ? config.urgentcolor : config.splitcolor)
    }

    package func clientFocus(_ c: Client?, _ lift: Bool) {
        let oldKeyboardFocusSurface = system.keyboardFocusedSurface

        if let c, clientByIdAll(c.id) !== c { return }

        if let c, c.noFocus { return }

        // Not in mango here (client_active's step): a parked group member takes its group's
        // place first.
        if let c, c.groupParked { clientGroupSwapFocus(c) }

        /* Raise client in stacking order if requested */
        if let c, lift {
            clientRaiseGroup(c)
            clientRaiseTab(c)
        }

        if let c, oldKeyboardFocusSurface === c, selectedMonitor.sel != nil {
            return
        }

        if let c, let m = c.mon {
            selectedMonitor = m
            m.prevsel = m.sel
            m.sel = c.id
            // not in mango: isfocusing, tab_sync_focus, client_check_tab_node_visible, idle inhibit,
            // vrr and opacity; the port draws the bars from sel

            // decide whether need to re-arrange

            // change focus link position
            focusStack.removeAll { $0 == c.id }
            focusStack.insert(c.id, at: 0)

            func tagMatch(_ x: Client) -> Bool { x.mon === m && !x.isminimized && x.tags & m.tagset[m.seltags] != 0 }
            if let p = m.prevsel.flatMap({ clientByIdAll($0) }), tagMatch(p), tagMatch(c), !c.isfloating,
               m.layout.isScroller || m.layout == .monocle || tabMembers(m).contains(where: { $0 === c }) {
                arrange(m, false, false)
            } else {
                updateBorders()   // not in mango: the port's side
            }

            // change border color
            c.isurgent = false
        }

        /* Deactivate old client if focus is changing */
        if let old = oldKeyboardFocusSurface, c == nil || old !== c {
            // not in mango: no layer shell (exclusive_focus); client_wants_focus is X11's
            system.clientActivateSurface(old, false)
        }
        system.restack()   // not in mango: the port's side
        if let cm = c?.mon, cm.isoverview, cm.ovThumbnails {
            system.updateOverview(overlayCards(cm), on: cm)   // not in mango: the port's side
        }
        if c != nil { printstatus(.arrangge) }   // not in mango: with no client, after sel is cleared; the port's status reads it at once

        guard let c else {
            let sm: Monitor = selectedMonitor
            if let id = sm.sel, !(clientByIdAll(id)?.isVisible(on: sm) ?? false) {
                sm.sel = nil
            }
            printstatus(.arrangge)
            updateBorders()   // not in mango: the port's side

            system.keyboardNotifyClearFocus()
            pointerCheckConfineClient()
            return
        }

        /* Change cursor surface */
        // not in mango: of pointer_process_motion(0, …) only its resize cursor
        let p = system.pointer
        let pointed = clientAtPoint(p)
        pointerUpdateResizeCursor(pointed, surfaceAt(pointed, p), p)

        /* Have a client, so focus its top-level wlr_surface */
        system.clientNotifyEnter(c)

        /* Activate the new client */
        system.clientActivateSurface(c, true)

        pointerCheckConfineClient()
    }

    func clientRaiseGroup(_ c: Client) {
        if c.mon == nil { return }

        var cur: Client? = clientGroupHead(c)
        while let it = cur {
            // not in mango: the group bar is placed by the port's restack
            system.raise(it)
            cur = it.groupNext
        }
    }

    func clientRaiseTab(_ c: Client) {
        guard let m = c.mon, tabMembers(m).contains(where: { $0 === c }) else { return }

        for it in tabMembers(m) where it !== c && clientTargetLayer(it) == clientTargetLayer(c) {
            system.raise(c)
            // not in mango: the tab bar is placed by the port's restack
        }
    }

    func pointerWarpToClient(_ c: Client) {
        guard let m = c.mon else { return }
        // not in mango: in the overview mango's geom is the card; ours is the window under it
        let g = (m.isoverview ? m.ovCards[c.id] : nil) ?? c.geom
        if m.screen.frame.contains(g) { system.warp(to: g.center) }
    }

    func pointerWarpToMonitor(_ m: Monitor) {
        system.warp(to: m.screen.workArea.center)
    }

    package func printstatus(_ type: IPCWatchType) {
        publishGlobalKeys()
        ipc?.notifyChanged(type)
        onStateChange?()   // the boundary, not in mango: the port's status change
    }

    package func handleClientMap(_ c: Client) {
        guard clientByIdAll(c.id) == nil else { return }
        clientAddJumpLabelNode(c)
        c.mon = nil
        clientInsertTilingOrder(c)
        focusStack.insert(c.id, at: 0)
        clientSetRules(c)
        if let cm = c.mon { arrange(cm, false, false) }
        printstatus(.arrangge)
    }

    // not in mango: `mapped` false is mango's surface not mapped yet, the rules alone; the port's
    // windows found mapped already (at start, back after sleep) are placed by the port
    @discardableResult
    package func clientSetRules(_ c: Client, mapped: Bool = true) -> (mon: Monitor, tags: UInt32) {
        var mon: Monitor = selectedMonitor
        var newtags: UInt32 = 0
        c.isfloating = clientIsFloatType(c)

        for i in config.windowRules.indices {
            let r = config.windowRules[i]
            guard r.isWindowRuleMatches(appId: c.bundleId, appName: c.appName, title: c.title) else { continue }
            if r.once && r.isOnceApplied { continue }
            if r.once { config.windowRules[i].isOnceApplied = true }

            applyRuleProperties(c, r)

            if let t = r.tags, t != 0 { newtags |= t }

            if let spec = r.monitor {
                for m in monitors where spec.matchMonitorSpec(name: m.screen.name) { mon = m }
            }

            if c.isnamedscratchpad { c.isfloating = true }

            let full = mon.screen.frame
            if let w = r.width, w > 1 { c.floatGeom.size.width = CGFloat(w) } else if let w = r.width, w > 0 { c.floatGeom.size.width = (full.width * CGFloat(w)).rounded() }
            if let h = r.height, h > 1 { c.floatGeom.size.height = CGFloat(h) } else if let h = r.height, h > 0 { c.floatGeom.size.height = (full.height * CGFloat(h)).rounded() }
            if (r.width ?? 0) > 0 || (r.height ?? 0) > 0 { c.iscustomsize = true }

            let ox = r.offsetX ?? 0, oy = r.offsetY ?? 0
            if ox != 0 || oy != 0 {
                c.iscustompos = true
                c.floatGeom = clientCenterGeometry(c, mon, c.floatGeom, ox, oy)
            }
        }

        if newtags == 0 && isSpecialActive(mon) { newtags = TAG0_MASK }

        setSizePer(mon, c)

        if !c.iscustompos {
            c.floatGeom = clientCenterGeometry(c, mon, c.floatGeom)
        }
        // Not in mango: a floating window off its monitor (there when mango started, or
        // no_force_center) is centred on it.
        if c.isfloating, !mon.screen.frame.intersects(c.floatGeom) {
            let w = mon.screen.workArea
            c.floatGeom = CGRect(x: w.midX - c.floatGeom.width / 2, y: w.midY - c.floatGeom.height / 2,
                                 width: c.floatGeom.width, height: c.floatGeom.height)
        }

        if !mapped { return (mon, newtags) }

        let shouldInitGetFocus = !c.isopensilent
            && (!c.istagsilent || newtags == 0 || newtags & mon.tagset[mon.seltags] != 0)
        if !shouldInitGetFocus {
            focusStack.removeAll { $0 == c.id }
            focusStack.append(c.id)
        }

        layoutStateInsert(c, on: mon)
        clientSetMonitor(c, mon, newtags, focus: shouldInitGetFocus)

        if let cm = c.mon, !(cm === selectedMonitor && c.tags & cm.tagset[cm.seltags] != 0),
           !c.isopensilent, !c.istagsilent {
            clientViewOnMonitor(c.tags, on: cm, changeFocus: true)
        }

        if let cm = c.mon, !c.isfloating {
            for fc in clients where fc !== c && c.tags & fc.tags != 0 && VISIBLEON(fc, cm)
                && (fc.isfullscreen || fc.ismaximizescreen) {
                clearFullscreenFlag(fc)
                arrange(cm, false, false)
            }
        }

        if c.isfloating && !c.iscustompos && !c.isnamedscratchpad {
            clients.removeAll { $0 === c }
            clients.append(c)
            setFloatMalposition(c)
        }

        if c.isnamedscratchpad { applyNamedScratchpad(c) }
        return (mon, newtags)
    }

    func applyRuleProperties(_ c: Client, _ r: ConfigWinRule) {
        if let v = r.noFocus { c.noFocus = v }
        if let v = r.confinePointer { c.confinePointer = v }
        if let v = r.noForceCenter { c.noForceCenter = v }
        if let v = r.isfloating { c.isfloating = v }
        if let v = r.isfullscreen { c.isfullscreen = v }
        if let v = r.isfakefullscreen { c.isfakefullscreen = v }
        if let v = r.noBorder { c.noBorder = v }
        if let v = r.noAnimation { c.noAnimation = v }
        if let v = r.noSizeHint { c.noSizeHint = v }
        if let v = r.isopensilent { c.isopensilent = v }
        if let v = r.istagsilent { c.istagsilent = v }
        if let v = r.isnamedscratchpad { c.isnamedscratchpad = v }
        if let v = r.isglobal { c.isglobal = v }
        if let v = r.isoverlay { c.isoverlay = v }
        if let v = r.ignoreMinimize { c.ignoreMinimize = v }
        if let v = r.isUnmanagedGlobal { c.isunglobal = v }
        if let v = r.scrollerProportion, v > 0 { c.scrollerProportion = CGFloat(v); c.iscustomScrollerProportion = true }
        if let v = r.scrollerProportionSingle, v > 0 { c.scrollerProportionSingle = CGFloat(v); c.iscustomScrollerProportionSingle = true }
        if let v = r.animationTypeOpen { c.animationTypeOpen = v }
    }

    /// Not in mango: the port's per-tag layout state (scroller columns, dwindle tree) takes
    /// a new window next to the focused one before focus moves to it.
    package func layoutStateInsert(_ c: Client, on m: Monitor) {
        m.pertag.scrollerState[getMonCurtag(m)].insert(c.id, afterFocused: m.sel)
        m.pertag.dwindleRoot[getMonCurtag(m)].dwindleInsertWithConfig(c.id, nextTo: m.sel, config: config, cursor: system.pointer)
    }

    func clientAdaptGeometryToMonitor(_ c: Client, _ oldmon: Monitor) {
        guard let cm = c.mon else { return }
        let from = oldmon.screen.workArea, to = cm.screen.workArea
        guard from.width > 0, from.height > 0, to.width > 0, to.height > 0 else { return }

        c.floatGeom.size = CGSize(width: (c.floatGeom.width * to.width / from.width).rounded(.towardZero),
                                  height: (c.floatGeom.height * to.height / from.height).rounded(.towardZero))
        c.floatGeom = clientCenterGeometry(c, cm, c.floatGeom)
    }

    func clientSetMonitorAdapted(_ c: Client, _ m: Monitor, _ newtags: UInt32, focus: Bool) -> Bool {
        guard let oldmon = c.mon, oldmon !== m else { return false }

        clientSetMonitor(c, m, newtags, focus: focus)
        if c.mon !== m { return false }

        clientUpdateOldmonnameRecord(c, m)
        c.parked = false   // not in mango: the system places it on the new display
        clientAdaptGeometryToMonitor(c, oldmon)
        return true
    }

    func monitorCopyTagLayout(_ target: Monitor, _ source: Monitor, _ tag: UInt32) {
        if tag >= PERTAG_SLOTS { return }

        let dst = target.pertag
        let src = source.pertag

        dst.nmasters[tag] = src.nmasters[tag]
        dst.mfacts[tag] = src.mfacts[tag]
        dst.noHide[tag] = src.noHide[tag]
        dst.noRenderBorder[tag] = src.noRenderBorder[tag]
        dst.openAsFloating[tag] = src.openAsFloating[tag]
        dst.scrollerDefaultProportion[tag] = src.scrollerDefaultProportion[tag]
        dst.scrollerDefaultProportionSingle[tag] = src.scrollerDefaultProportionSingle[tag]
        dst.scrollerIgnoreProportionSingle[tag] = src.scrollerIgnoreProportionSingle[tag]
        dst.ltidxs[tag] = src.ltidxs[tag]

        /* Layout trees and scroller nodes are monitor-owned and rebuilt on the
         * target after the clients have moved. */
    }

    package func clientSetMonitor(_ c: Client, _ m: Monitor?, _ newtags: UInt32, focus: Bool) {
        let oldmon = c.mon
        if oldmon === m { return }
        if let oldmon, oldmon.sel == c.id { oldmon.sel = nil }
        if let oldmon, oldmon.prevsel == c.id { oldmon.prevsel = nil }
        c.mon = m
        if let oldmon { arrange(oldmon, false, false) }
        if c.groupParked { return }
        if let m {
            clientResetMonTags(c, m, newtags)
            checkMatchTagFloatingRule(c, m)
            clientSetFloating(c, c.isfloating)
            clientSetFullscreen(c, c.isfullscreen, rearrange: true)
        }
        if focus { clientFocus(clientFocusTop(selectedMonitor), true) }
    }

    package func clientResetMonTags(_ c: Client, _ mon: Monitor, _ newtags: UInt32) {
        if newtags == 0 && !mon.isoverview {
            c.tags = mon.tagset[mon.seltags]
        } else if newtags == 0 && mon.isoverview {
            c.tags = mon.ovbkCurrentTagset
        } else if newtags != 0 {
            let masked = (newtags & TAG0_MASK) != 0 ? TAG0_MASK : (newtags & TAGMASK)
            c.tags = masked != 0 ? masked : mon.tagset[mon.seltags]
        } else {
            c.tags = mon.tagset[mon.seltags]
        }
    }

    package func checkMatchTagFloatingRule(_ c: Client, _ mon: Monitor) {
        if c.tags != 0 && !c.isfloating, mon.pertag.openAsFloating[getTagsFirstTagNum(c.tags)] {
            c.isfloating = true
        }
    }

    func clientIsFloatType(_ c: Client) -> Bool { c.platform.isFloatType }

    func clientUpdateOldmonnameRecord(_ c: Client, _ m: Monitor) {
        // not in mango: no iskilling or mapped test; every Client is a mapped window.
        c.oldmonname = m.screen.displayID
    }

    func clearFullscreenFlag(_ c: Client) {
        guard let m = c.mon else { return }
        let layout = m.pertag.ltidxs[getClientTagIdx(c)]
        if !c.isfloating && (layout.isScroller || (layout == .monocle && config.monocleTabMode)) { return }
        if c.isfullscreen { clientSetFullscreen(c, false, rearrange: true) }
        if c.ismaximizescreen { clientSetMaximizeScreen(c, false, rearrange: true) }
    }

    func clearFullscreenAndMaximizedState(_ m: Monitor) {
        for fc in clients where VISIBLEON(fc, m) && (fc.isfullscreen || fc.ismaximizescreen) {
            clearFullscreenFlag(fc)
        }
    }

    func clientSetFloating(_ c: Client, _ floating: Bool) {
        let oldFloatingState = c.isfloating
        c.isfloating = floating
        guard let m = c.mon else { return }
        if floating && grab?.client !== c {
            if c.isfullscreen { system.clientNotifyFullscreen(c, false) }
            c.isfullscreen = false
            c.ismaximizescreen = false
            exitScrollerStack(c)
            let w = m.screen.workArea
            var outOfRange = false
            if c.floatGeom.width >= w.width - CGFloat(config.gappoh) {
                c.floatGeom.size.width = (w.width * 0.9).rounded(.towardZero)
                outOfRange = true
            }
            if c.floatGeom.height >= w.height - CGFloat(config.gappov) {
                c.floatGeom.size.height = (w.height * 0.9).rounded(.towardZero)
                outOfRange = true
            }
            if outOfRange { c.floatGeom = clientCenterGeometry(c, m, c.floatGeom) }
            // Not in mango: a floating place off the monitor (a window that was there when
            // mango started, parked or on a display that went away) is centred on it.
            if !w.intersects(c.floatGeom) { c.floatGeom = clientCenterGeometry(c, m, c.floatGeom) }
        } else if !floating {
            c.isInScratchpad = false
            c.isnamedscratchpad = false
            setSizePer(m, c)
            for fc in clients where fc !== c && VISIBLEON(fc, m) && c.tags & fc.tags != 0
                && (fc.isfullscreen || fc.ismaximizescreen) && oldFloatingState {
                clearFullscreenFlag(fc)
            }
        }
        arrange(m, false, false)
        printstatus(.arrangge)
    }

    func clientSetFullscreen(_ c: Client, _ fullscreen: Bool, rearrange: Bool) {
        guard let m = c.mon, grab?.client !== c else { return }
        if m.isoverview { return }
        c.isfullscreen = fullscreen
        system.clientNotifyFullscreen(c, fullscreen)
        if fullscreen {
            c.ismaximizescreen = false
            exitScrollerStack(c)
            c.isfakefullscreen = false
        } else if c.isfloating {
            clientSetFloating(c, true)
        }
        if rearrange { arrange(m, false, false) }
    }

    func clientSetFakeFullscreen(_ c: Client, _ fakefullscreen: Bool) {
        c.isfakefullscreen = fakefullscreen
        guard c.mon != nil else { return }
        if c.isfullscreen { clientSetFullscreen(c, false, rearrange: true) }
    }

    func clientSetMaximizeScreen(_ c: Client, _ maximizescreen: Bool, rearrange: Bool) {
        guard let m = c.mon, grab?.client !== c else { return }
        if m.isoverview { return }
        c.ismaximizescreen = maximizescreen
        if maximizescreen {
            if c.isfullscreen { system.clientNotifyFullscreen(c, false) }
            c.isfullscreen = false
            exitScrollerStack(c)
        } else if c.isfloating {
            clientSetFloating(c, true)
        }
        if rearrange { arrange(m, false, false) }
    }

    // scene layer a client belongs to; only clients actually tagged with tag 0
    // belong to the special layers
    public func clientTargetLayer(_ c: Client) -> Lyr {
        let specialOverlay = c.tags & TAG0_MASK != 0

        if c.isoverlay {
            return specialOverlay ? .specialOverlay : .overlay
        }

        if config.floatFullToTop {
            if specialOverlay {
                return c.isfloating || c.isfullscreen ? .top
                    : c.ismaximizescreen ? .specialMaximize
                    : .specialTile
            }

            if let m = c.mon, isSpecialActive(m) {
                return c.isfullscreen ? .fullscreen
                    : c.isfloating ? .float
                    : c.ismaximizescreen ? .maximize
                    : .tile
            }

            return c.isfloating || c.isfullscreen ? .top
                : c.ismaximizescreen ? .maximize
                : .tile
        }

        if specialOverlay {
            return c.isfullscreen ? .specialFullscreen
                : c.isfloating ? .specialFloat
                : c.ismaximizescreen ? .specialMaximize
                : .specialTile
        }

        return c.isfullscreen ? .fullscreen
            : c.isfloating ? .float
            : c.ismaximizescreen ? .maximize
            : .tile
    }

/// Not in mango: the port keeps the scroller's column order in the tag's state.
    func exitScrollerStack(_ c: Client) {
        guard let m = c.mon else { return }
        m.pertag.scrollerState[getClientTagIdx(c)].exitScrollerStack(c.id)
    }

    package func clientInsertTilingOrder(_ c: Client) {
        let m: Monitor = selectedMonitor
        let scrollTiled = visibleClients(m).filter { !$0.isfloating && !$0.isminimized && !$0.isunglobal && $0 !== c }
        var at: Client?
        if config.newIsMaster && !m.layout.isScroller {
            clients.insert(c, at: 0)
            return
        } else if m.layout.isScroller && !scrollTiled.isEmpty {
            if let sel = m.sel.flatMap({ clientById($0) }), scrollTiled.contains(where: { $0 === sel }) {
                at = m.pertag.scrollerState[getMonCurtag(m)].column(of: sel.id).last.flatMap { clientById($0) } ?? sel
            } else {
                at = centerTiledSelect(m, among: scrollTiled)
            }
        }
        if let at, let i = clients.firstIndex(where: { $0 === at }) { clients.insert(c, at: i + 1) } else { clients.append(c) }
    }

    func setFloatMalposition(_ tc: Client) {
        guard let m = tc.mon else { return }
        let w = m.screen.workArea
        let offset = min(w.width / 20, w.height / 20).rounded(.towardZero)
        var x = tc.floatGeom.minX, y = tc.floatGeom.minY
        var xreverse: CGFloat = 1, yreverse: CGFloat = 1
        for c in clients where c.isfloating && c !== tc && VISIBLEON(c, m)
            && abs(x - c.floatGeom.minX) < offset && abs(y - c.floatGeom.minY) < offset {
            x = c.floatGeom.minX + offset * xreverse
            y = c.floatGeom.minY + offset * yreverse
            if x < w.minX { x += offset; xreverse = 1 }
            if y < w.minY { y += offset; yreverse = 1 }
            if x + tc.floatGeom.width > w.maxX { x -= offset; xreverse = -1 }
            if y + tc.floatGeom.height > w.maxY { y -= offset; yreverse = -1 }
        }
        tc.floatGeom.origin = CGPoint(x: x, y: y)
    }

    func centerTiledSelect(_ m: Monitor, among tiled: [Client]) -> Client? {
        let w = m.screen.workArea
        let d = tiled.map { c -> CGFloat in
            let g = c.geom
            return pow(g.midX - w.midX, 2) + pow(g.midY - w.midY, 2)
        }
        return d.indices.min { d[$0] < d[$1] }.map { tiled[$0] }
    }

    package func handleClientUnmap(_ c: Client) {
        let id = c.id
        guard clientByIdAll(id) === c else { return }
        var stackNext: Client?, stackPrev: Client?
        if let cm = c.mon, VISIBLEON(c, cm) {
            let col = cm.pertag.scrollerState[getMonCurtag(cm)].column(of: id)
            if let i = col.firstIndex(of: id) {
                stackNext = i + 1 < col.count ? clientByIdAll(col[i + 1]) : nil
                stackPrev = i > 0 ? clientByIdAll(col[i - 1]) : nil
            }
        }
        // Port extension: not in mango. Its group and its place in the order, for when the
        // window comes back (macOS reports windows gone and back around sleep).
        let group = c.isGroupMember ? groupMembers(c) : []

        if let label = c.jumpLabelNode {
            label.destroy()
            c.jumpLabelNode = nil
        }

        if c.isGroupMember {
            if c.isGroupFocus, let r = c.groupNext ?? c.groupPrev {
                r.mon = c.mon
                clientReplace(r, c, isGroupChangeMember: false)
            }
            clientGroupDetach(c)
        }
        let order = clients.map(\.id)
        clients.removeAll { $0 === c }
        portHooks.windowLeaving?(self, c, group.map(\.id), group.first { $0.isGroupFocus }?.id, order)   // Port extension
        focusStack.removeAll { $0 == id }
        switcherRemoveClient(id)
        if grab?.client === c { grab = nil }
        if dragTile?.client === c { dragTile = nil; system.showDropArea(nil, color: config.dropcolor) }
        for m in monitors {
            for st in m.pertag.scrollerState { st.scrollerNodeRemove(id) }
            for root in m.pertag.dwindleRoot { root.dwindleRemove(id, config: config) }
            if m.sel == id { m.sel = nil }
            if m.prevsel == id { m.prevsel = nil }
        }
        guard let m = c.mon else { return }
        arrange(m, false, false)
        if m === selectedMonitor {
            var next = stackNext ?? stackPrev ?? clientFocusTop(m)
            if let n = next, !VISIBLEON(n, m) { next = clientFocusTop(m) }
            if let next { clientFocus(next, true) } else if selectedMonitor.isoverview { toggleOverview() }
        }
        printstatus(.arrangge)
    }

    package func handleClientDestroy(_ c: Client) {
        switcherRemoveClient(c.id)
    }

    package func handleClientActivationRequest(_ c: Client) {
        guard clientByIdAll(c.id) === c else { return }
        if config.focusOnActivate && !c.istagsilent && c.id != selectedMonitor.sel {
            if c.tags & TAG0_MASK != 0, let m = c.mon {
                if isSpecialActive(m) {
                    clientFocus(c, true)
                } else {
                    toggleSpecialTagMon(m)
                }
                return
            }
            clientActive(c)
        } else if c !== clientFocusTop(selectedMonitor) {
            c.isurgent = true
            updateBorders()
            printstatus(.arrangge)
        }
    }

    package func handleClientRequestMinimize(_ c: Client, _ minimized: Bool) {
        guard clientByIdAll(c.id) === c, c.mon != nil, !c.isminimized, !c.groupParked else { return }
// not in mango: no client_set_minimized; the port has done the Dock's part.
        if minimized && !c.ignoreMinimize {
            setMinimized(c)
        }
    }

    package func handleClientSetTitle(_ c: Client) {
        guard clientByIdAll(c.id) === c else { return }
        tabRefreshBars()
        titleMessageBarUpdateTitle(c)
        if let m = c.mon, c === clientFocusTop(m) { printstatus(.arrangge) }
    }
}
