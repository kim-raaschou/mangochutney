import Foundation
import CoreGraphics
import QuartzCore

public let mangoVersion = "0.0.3-20261105-beta"

package enum ArrangeAnimation {
    case none
    case move
    case tag(forward: Bool)
}

@MainActor
public final class MangoServer {
    public internal(set) var config = Config()
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
    var execOnceDone = false

    package var overviewState: OverviewState? { didSet { publishInputState() } }
    package var tagCombo = false { didSet { if tagCombo != oldValue { publishInputState() } } }
    var switcherState: SwitcherState? { didSet { publishInputState() } }
    var publishedGlobalKeys = false
    package var grab: Grab?
    var startDragWindow = false
    var confinePointerLast: ClientID?
    var dragBeginCursor: CGPoint = .zero
    var lastApplyDragTime: UInt32 = 0
    package var dragTile: DragTile?
    package var system: WindowSystem!
    /// Port extension: not in mango. Where the port's extensions join (PortHooks.swift).
    package var portHooks = PortHooks()
    package var groupBarDrag: (client: Client, start: CGPoint)?
    var cursorHidden = false
    var cursorHideTimerArmed = false
    var lastPointerActivity: CFTimeInterval = 0
    var swipeDrive: SwipeDrive?
    var swipeDriving: (binding: GestureBinding, monitor: Monitor, startSel: ClientID?,
                       panFrames: [ClientID: CGRect], dragStart: CGPoint)?
    var scrollerFocusLock = false

    public var onStateChange: (() -> Void)?

    public init(configURL: URL? = nil) {
        self.configURL = configURL ?? ConfigParser.defaultConfigURL()
    }

    public func setup() {
        drawsOverlays = true
        system.prepare()
        parseConfig()
        resetOption(initial: true)
        configWatcherUpdate()
        rebuildMonitors()
        portHooks.restoreLayout?(self)   // Port extension: not in mango (the layout kept across a restart)
        system.startWatching()
        publishInputState()
        system.startInput()
        system.watchGestures(!config.gestureBindings.isEmpty)
        pointerCursorActivity()

        let server = IPCServer(server: self, loop: system.eventLoop, version: mangoVersion)
        do { try server.ipcInit(); ipc = server } catch { Log.error("IPC server failed: \(error)") }

        started = true
        arrangeAll(.none)
        printstatus()
        Log.info("mango \(mangoVersion) started: \(monitors.count) monitor(s)")
    }

    public func cleanup() {
        // not in mango: the pointer shown again, as macOS keeps it hidden after mango
        if cursorHidden { cursorHidden = false; system.setCursorHidden(false) }
        system.drawBorders([])
        portHooks.saveLayout?(self, true)   // Port extension: not in mango (written before anything moves)
        system.shutdown()
        ipc?.ipcCleanup()
    }

    // not in mango: the server's side of parse_config, the config read and the nag (config_error_nag_update)
    func parseConfig() {
        let parsed = ConfigParser.parseConfig(fileAt: configURL)
        config = parsed.config
        configErrors = parsed.errors
        configFiles = parsed.sourcedFiles
        for e in parsed.errors { Log.error("config: \(e)") }
        system.showConfigErrors(parsed.errors, configURL: configURL)
    }

    func configWatcherUpdate() {
        system.watchConfig(config.autoReloadConfig ? [configURL] + configFiles : [])
    }

    func resetOption(initial: Bool = false) {
        system.setKeyboardOptions(config.xkbRulesOptions)
        for (k, v) in config.envVars { setenv(k, (v as NSString).expandingTildeInPath, 1) }
        publishInputState()
        // Port extension: not in mango. The port takes its own options (chutney_ignore_apps).
        for loaded in portHooks.configLoaded { loaded(self) }
        if !initial {
            for m in monitors {
                m.gaps = Gaps(ih: CGFloat(config.gappih), iv: CGFloat(config.gappiv),
                              oh: CGFloat(config.gappoh), ov: CGFloat(config.gappov))
                m.specialGaps = Gaps(ih: CGFloat(config.specialGappih), iv: CGFloat(config.specialGappiv),
                                     oh: CGFloat(config.specialGappoh), ov: CGFloat(config.specialGappov))
                m.parseTagrule(config: config, clients: clientsAll)
            }
            system.watchGestures(!config.gestureBindings.isEmpty)
        }
        for cmd in config.exec { system.spawnShell(cmd) }
        publishInputState()
        pointerCursorActivity()
        if !execOnceDone {
            execOnceDone = true
            for cmd in config.execOnce { system.spawnShell(cmd) }
        }
        if !initial { arrangeAll(.move) }
    }

    public func reloadConfig() {
        Log.info("reloading config")
        let oldTagNum = config.tagNum
        parseConfig()
        resetTag(oldTagNum)
        resetOption()
        printstatus()
        configWatcherUpdate()
    }

    func resetTag(_ oldTagNum: Int) {
        guard config.tagNum != oldTagNum else { return }
        let tagmask = TagMask.mask(forTagNum: config.tagNum)
        let last: UInt32 = 1 << UInt32(config.tagNum - 1)
        for c in clientsAll where c.tags & ~tagmask != 0 {
            c.tags = last
            c.oldTags = last
        }
        for m in monitors {
            m.tagset[0] &= tagmask
            m.tagset[1] &= tagmask
            if m.tagset[m.seltags] == 0 { m.tagset[m.seltags] = last }
            if m.curtag > config.tagNum { m.curtag = config.tagNum }
            if m.prevTag > config.tagNum { m.prevTag = config.tagNum }
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
                newMonitors.append(Monitor(screen: s, config: config))
            }
        }
        guard !newMonitors.isEmpty else { return }
        let removed = monitors.filter { m in !newMonitors.contains { $0 === m } }
        let added = newMonitors.filter { m in !monitors.contains { $0 === m } }
        if let ov = overviewState, removed.contains(where: { $0 === ov.monitor }) { leaveOverview(select: nil) }
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
        if started && (!removed.isEmpty || !added.isEmpty) { clientFocus(clientFocusTop(selectedMonitor)) }
    }

    func clientChangeMon(_ c: Client, to m: Monitor, focus: Bool = true) {
        clientSetMonitor(c, m, c.tags, focus: focus)
        c.parked = false   // not in mango: the system places it on the new display
        if c.isFloating {
            c.floatGeom = clientCenterGeometry(c, m, c.floatGeom)
        }
    }

    public func handleOutputLayoutChange() {
        rebuildMonitors()
        arrangeAll(.none)
        printstatus()
    }

    package func monitorAtPoint(_ p: CGPoint) -> Monitor? {
        if let m = monitors.first(where: { $0.screen.frame.contains(p) }) { return m }
        return monitors.min { a, b in a.screen.frame.center.distance(to: p) < b.screen.frame.center.distance(to: p) }
    }

    /// Not in mango: the VISIBLEON filter as a list.
    func visibleClients(_ m: Monitor) -> [Client] {
        clients.filter { $0.isVisible(on: m) }
    }

    /// Not in mango: the VISIBLEON and ISTILED filter as a list.
    package func tiledClients(_ m: Monitor) -> [Client] {
        visibleClients(m).filter {
            !$0.isUnglobal && !$0.isFloating && !$0.isFullscreen && !$0.isMaximizeScreen && !$0.scratchpadShown && !$0.isMinimized
        }
    }

    /// Not in mango: the special tag's windows as a list.
    func specialClients(_ m: Monitor) -> [Client] {
        guard m.tagset[m.seltags] & TagMask.special != 0 else { return [] }
        return clients.filter {
            $0.mon === m && $0.tags & TagMask.special != 0 && !$0.isMinimized
        }
    }

    package var focused: Client? { selectedMonitor.sel.flatMap { clientByIdAll($0) } }

    package func clientFocusTop(_ m: Monitor) -> Client? {
        for id in focusStack {
            if let c = clientByIdAll(id), !c.isUnglobal, c.isVisible(on: m) { return c }
        }
        return nil
    }

    func dragRefreshIntervalMs(_ m: Monitor?) -> UInt32 {
        var refreshMhz = m?.screen.refresh ?? 0
        if refreshMhz <= 0 { refreshMhz = 60000 }
        let ms = Int32(1000.0 / (Double(refreshMhz) / 1000.0))
        return ms > 0 ? UInt32(ms) : 1
    }

    /// Not in mango: arrange on every monitor.
    package func arrangeAll(_ anim: ArrangeAnimation) {
        for m in monitors { arrange(m, anim) }
    }

    package func arrange(_ m: Monitor, _ anim: ArrangeAnimation = .move) {
        guard started else { return }
        if let ov = overviewState, ov.monitor === m {
            if !ov.thumbnails { overview(ov); return }
// not in mango: the pictures are the cards; the real windows stay under them.
            return
        }
        if m.sel == nil { m.sel = clientFocusTop(m)?.id }
        if isSpecialActive(m) && specialClients(m).isEmpty {
            if case .tag = anim { m.specialEmptyView = true }
            else if !m.specialEmptyView { toggleSpecialTagMon(m); return }
        } else {
            m.specialEmptyView = false
        }
        for c in clientsAll where c.mon === m && (c.isGlobal || c.isUnglobal) { c.tags = m.tagset[m.seltags] }

        let visible = visibleClients(m)
        let tiled = tiledClients(m)
        let work = m.screen.workArea
        let monGaps = isSpecialActive(m) ? m.specialGaps : m.gaps
        // Port extension: not in mango. The gaps in the screen's pixels (chutney_physical_pixels).
        let px = portHooks.pixelScale?(self, m) ?? 1
        let gaps = enableGaps ? Gaps(ih: monGaps.ih * px, iv: monGaps.iv * px, oh: monGaps.oh * px, ov: monGaps.ov * px)
            : .zero
        let fakeTiled = visible.filter { !$0.isFloating && !$0.isMinimized && !$0.isUnglobal }

        // not in mango: pre_calculate_before_arrange's weights, here in arrange
        let nmasters = m.current.settings.nmaster
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
                    c.isLeftStack = false
                    totalRight += c.stackSizeWeight
                } else {
                    c.isLeftStack = true
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
            let bw = borderWidth(c, on: m)
            var f = (c.geom ?? c.frame).insetBy(dx: -bw, dy: -bw)
            let top = topBars(c, tabMember: strips.contains(c.id))
            f.origin.y -= top
            f.size.height += top
            return f
        }
        var layoutClients = fakeTiled.map { c in
            LayoutClient(id: c.id, currentFrame: tile(c), isFullscreen: c.isFullscreen, isMaximized: c.isMaximizeScreen,
                         scrollerProportion: c.scrollerProportion, scrollerProportionSingle: c.scrollerProportionSingle,
                         masterInnerPer: c.masterInnerPer, stackInnerPer: c.stackInnerPer,
                         scrollerStackWeight: c.scrollerStackWeight, masterMfactPer: c.masterMfactPer,
                         gridColPer: c.gridColPer, gridRowPer: c.gridRowPer,
                         gridColIdx: c.gridColIdx, gridRowIdx: c.gridRowIdx)
        }
        let kind = m.layout
        var settings = m.current.settings
        var input = LayoutInput(workArea: work, monitorFrame: m.screen.frame, gaps: gaps, clients: layoutClients,
                                focusedID: m.sel, prevFocusedID: m.prevsel, pertag: settings,
                                config: config, cursor: system.pointer)
        input.enableGaps = enableGaps
        input.startDragWindow = startDragWindow
        if let p = m.prevsel.flatMap({ clientByIdAll($0) }) {
            input.prevFocusedScroll = (!p.isFloating && !p.isMinimized && !p.isUnglobal,
                                       p.scrollerProportion ?? m.current.settings.scrollerDefaultProportion)
        }
        input.fullscreenInView = Set(visible.filter { $0.isFullscreen || $0.isMaximizeScreen }.map(\.id))
        var result = LayoutEngine.arrange(kind, input: input, state: m.current.state)
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
        var placements: [(Client, CGRect)] = []
        for c in visible where !c.isUnglobal && dragTile?.client !== c {
            var target: CGRect?
            var park = false
            if c.scratchpadShown {
                target = system.keepOnDisplay(clientApplyBounds(c, c.floatGeom, sceneGeometry), m)   // not in mango: the port's side
                raise.append(c)
            } else if c.isFullscreen {
                target = m.screen.frame
                raise.append(c)
            } else if c.isMaximizeScreen {
                let bw = borderWidth(c, on: m)
                let noGap = config.monocleNoGap && kind == .monocle
                // Port extension: not in mango. In the screen's pixels (chutney_physical_pixels).
                var box = work.insetBy(horizontal: noGap ? 0 : CGFloat(config.gappoh) * px,
                                       vertical: noGap ? 0 : CGFloat(config.gappov) * px)
                if clientWantsGroupBar(c) {
                    box.origin.y += CGFloat(config.groupBarHeight)
                    box.size.height -= CGFloat(config.groupBarHeight)
                }
                target = box.insetBy(dx: bw, dy: bw)
                raise.append(c)
            } else if c.isFloating {
                target = system.keepOnDisplay(clientApplyBounds(c, c.floatGeom, sceneGeometry), m)   // not in mango: the port's side
                if c.isOverlay { raise.append(c) }
            } else if let f = result.frames[c.id] {
                let bw = borderWidth(c, on: m)
                target = f.insetBy(dx: bw, dy: bw)
                if c.isOverlay { raise.append(c) }
                if (result.hidden.contains(c.id) && !kind.isMonocleLike) || tabHidden.contains(c.id) { park = true }
            } else {
                target = c.geom ?? c.frame
            }
            if park {
                c.geom = target
                system.hide(c)
            } else if let t = target {
                placements.append((c, t))
            }
        }
        if kind.isMonocleLike, let s = m.sel.flatMap({ clientByIdAll($0) }), !s.isFloating { raise.insert(s, at: 0) }
// not in mango: raised now, or by macOS as it focuses it: never taken as covered.
        system.resize(placements, anim, rising: Set(raise.map(\.id) + (m.sel.map { [$0] } ?? [])))

        for c in clientsAll where c.mon === m {
            if !c.isVisible(on: m) && !specialKeepBgClient(m, c) { setArrangeHidden(m, c, anim) }
        }

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
            let len = ((w.width - box.width - 2 * m.gaps.oh) / 2).rounded(.towardZero)
            box.origin.x += (len * CGFloat(offsetX) / 100).rounded(.towardZero)
            if box.minX < full.minX { box.origin.x = full.minX }
            if box.maxX > full.maxX { box.origin.x = full.maxX - box.width }
        }
        if offsetY != 0 {
            let len = ((w.height - box.height - 2 * m.gaps.ov) / 2).rounded(.towardZero)
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
        guard isSpecialActive(m), !c.isMinimized, c.mon === m else { return false }
        return (m.prevTag > 0 && c.tags & (1 << UInt32(m.prevTag - 1)) != 0)
            || c.tags & (m.tagset[m.seltags ^ 1] & ~TagMask.special) != 0
    }

    func getMonitorActiveTagset(_ m: Monitor) -> UInt32 {
        guard isSpecialActive(m) else { return m.tagset[m.seltags] }
        let prev = m.tagset[m.seltags ^ 1] & ~TagMask.special
        return prev != 0 ? prev : (m.prevTag > 0 ? 1 << UInt32(m.prevTag - 1) : 1)
    }

    func toggleSpecialTagMon(_ m: Monitor) {
        guard overviewState?.monitor !== m else { return }
        selectedMonitor = m
        if isSpecialActive(m) {
            clientViewOnMonitor(getMonitorActiveTagset(m), on: m)
        } else {
            clientViewOnMonitor(TagMask.special, on: m)
        }
    }

    package func isSpecialActive(_ m: Monitor) -> Bool {
        m.tagset[m.seltags] & TagMask.special != 0 && overviewState?.monitor !== m
    }

    package func specialUpdateDim(_ m: Monitor) {
        guard drawsOverlays else { return }
        system.showSpecialDim(on: m, alpha: isSpecialActive(m) ? config.specialDim : nil,
                              over: Set(specialClients(m).map(\.id)))
    }

    var sceneGeometry: CGRect { monitors.map(\.screen.frame).reduce(CGRect.null) { $0.union($1) } }

    // not in mango: returns the frame instead of setting c->geom
    func clientApplyBounds(_ c: Client, _ geom: CGRect, _ bbox: CGRect) -> CGRect {
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
        // Port extension: not in mango. A colour of the port's own (chutney_floating_color).
        if let color = portHooks.borderColor?(self, c) { return color }
        let isFocused = c.mon === selectedMonitor && selectedMonitor.sel == c.id
        if c.mon !== selectedMonitor { return config.bordercolor }
        if c.isUrgent { return config.urgentcolor }
        guard isFocused else { return config.bordercolor }
        if c.isInScratchpad { return config.scratchpadcolor }
        if c.isGlobal { return config.globalcolor }
        if c.isOverlay { return config.overlaycolor }
        if c.isMaximizeScreen { return config.maximizescreencolor }
        return config.focuscolor
    }

    func checkHitNoBorder(_ c: Client) -> Bool {
        guard let m = c.mon, c.tags != 0 else { return false }
        let isoverview = overviewState?.monitor === m
        var hitNoBorder = false
        if !renderBorder { hitNoBorder = true }
        if !isoverview && m.pertag[c.tags & TagMask.special != 0 ? 0 : (TagMask.getTagsFirstTagNum(c.tags) ?? 0)].noRenderBorder { hitNoBorder = true }
        if config.noBorderWhenSingle {
            let shown = visibleClients(m)
            let visible = shown.filter { !$0.isUnglobal }.count
            let fakeTiling = shown.filter { !$0.isFloating && !$0.isMinimized && !$0.isUnglobal }.count
            if (!c.isFloating && !c.isMinimized && !c.isUnglobal && fakeTiling == 1) || visible == 1 {
                hitNoBorder = true
            }
        }
        if config.monocleNoBorder && !c.isFloating && !isoverview && m.layout == .monocle { hitNoBorder = true }
        return hitNoBorder
    }

    // not in mango: c->bw (no_border, fullscreen) as check_hit_no_border leaves it, in points
    func borderWidth(_ c: Client, on m: Monitor) -> CGFloat {
        guard config.borderpx > 0, !c.noBorder, !c.isFullscreen, !checkHitNoBorder(c) else { return 0 }
        // Port extension: not in mango. border_px in the screen's pixels (chutney_physical_pixels).
        return CGFloat(config.borderpx) * (portHooks.pixelScale?(self, m) ?? 1)
    }

    // not in mango: client_draw_border for every window at once; the port draws the borders in one overlay
    package func updateBorders(animating: [ClientID: CGRect] = [:]) {
        tabRefreshBars(animating: animating)
        guard renderBorder, config.borderpx > 0 else { system.drawBorders([]); return }
        var specs: [BorderSpec] = []
        for m in monitors {
            let strip = tabChainFocus(tabMembers(m), on: m).flatMap { !$0.parked && !$0.isFullscreen && !$0.isMaximizeScreen ? $0 : nil }
            let tiledCount = tiledClients(m).count
            for c in visibleClients(m) + specialClients(m) where !c.parked {
                let width = borderWidth(c, on: m)
                guard width > 0 else { continue }
                let focusedHere = m === selectedMonitor && m.sel == c.id
                // Port extension: not in mango. Only the focused window's border (chutney_border_unfocused off).
                if portHooks.focusedBorderOnly?(self) == true && !focusedHere { continue }
                if m.layout.isMonocleLike && !c.isFloating && m.sel != c.id && tiledCount > 1 {
                    if m.layout == .monocle { continue }
                }
                var f = shownFrame(c, animating: animating)
                let top = !barsInsideBorder ? 0
                    : (c === strip ? CGFloat(config.tabBarHeight) : 0) + (clientCheckTabNodeVisible(c, on: m) ? CGFloat(config.groupBarHeight) : 0)
                f = CGRect(x: f.minX, y: f.minY - top, width: f.width, height: f.height + top)
                // Port extension: not in mango. The ring may follow macOS's window corners (chutney_style).
                let radius = portHooks.borderRadius?(self, c)
                    ?? (c.isFullscreen || (config.noRadiusWhenSingle && tiledClients(m).count == 1) ? 0 : CGFloat(config.borderRadius))
                specs.append(BorderSpec(id: c.id, frame: f, color: getBorderColor(c), width: width, radius: radius,
                                        split: clientDrawSplitBorder(c, on: m)))
            }
        }
        if drawsOverlays { system.drawBorders(specs) }
    }

    func clientDrawSplitBorder(_ c: Client, on m: Monitor) -> (side: BorderSpec.SplitSide, color: RGBA)? {
        guard config.dwindleManualSplit, m.layout == .dwindle, !c.isFloating, !c.isFullscreen,
              tiledClients(m).contains(where: { $0 === c }),
              let horizontal = m.current.state.dwindleRoot.leafSplitHorizontal(for: c.id) else { return nil }
        return (horizontal ? .right : .bottom, c.isUrgent ? config.urgentcolor : config.splitcolor)
    }

    /// Not in mango: where an animating window is on screen.
    func shownFrame(_ c: Client, animating: [ClientID: CGRect]) -> CGRect {
        animating[c.id] ?? system.animatedFrame(c.id) ?? c.frame
    }

    package func clientDrawFrame(_ frames: [ClientID: CGRect]) {
        updateBorders(animating: frames)
    }

/// Not in mango: `raise` and `makeKey` for macOS's keyboard focus and window order (mango's lift).
    package func clientFocus(_ c: Client?, raise: Bool = true, makeKey: Bool = false) {
        defer { pointerCheckConfineClient() }
        guard let c else {
            let sm: Monitor = selectedMonitor
            if !(sm.sel.flatMap { clientByIdAll($0) }?.isVisible(on: sm) ?? false) { sm.sel = nil }
            updateBorders()
            printstatus()
            return
        }
        if c.noFocus { return }
        // Not in mango here (client_active's step): a parked group member takes its group's
        // place first.
        if c.groupParked { clientGroupSwapFocus(c) }
        guard let m = c.mon else { return }
        if m.sel != c.id {
            m.prevsel = m.sel
            m.sel = c.id
        }
        selectedMonitor = m
        focusStack.removeAll { $0 == c.id }
        focusStack.insert(c.id, at: 0)
        portHooks.clientFocused?(self, c)   // Port extension: not in mango (chutney_focus_app's "used last")
        c.isUrgent = false
        if raise || makeKey { system.focus(c, raise: raise) }
        func tagMatch(_ x: Client) -> Bool { x.mon === m && !x.isMinimized && x.tags & m.tagset[m.seltags] != 0 }
        if let p = m.prevsel.flatMap({ clientByIdAll($0) }), tagMatch(p), tagMatch(c), !c.isFloating,
           m.layout.isScroller || m.layout == .monocle || tabMembers(m).contains(where: { $0 === c }) {
            arrange(m, .move)
        } else {
            updateBorders()
        }
        system.restack()
        if let ov = overviewState, ov.thumbnails, ov.monitor === m {
            system.updateOverview(overlayCards(ov, focused: ov.circle ? (ov.circleFocus ?? c.id) : c.id))
        }
        printstatus()
    }

    func pointerWarpToClient(_ c: Client) {
        guard let m = c.mon else { return }
        let g = c.geom ?? c.frame
        if m.screen.frame.contains(g) { system.warp(to: g.center) }
    }

    func pointerWarpToMonitor(_ m: Monitor) {
        system.warp(to: m.screen.workArea.center)
    }

    package func printstatus() {
        publishGlobalKeys()
        ipc?.notifyChanged()
        onStateChange?()
        portHooks.saveLayout?(self, false)   // Port extension: not in mango (the layout kept across a restart)
    }

    package func handleClientMap(_ c: Client) {
        guard clientByIdAll(c.id) == nil else { return }
        c.mon = nil
        clientInsertTilingOrder(c)
        focusStack.insert(c.id, at: 0)
        clientApplyRules(c)
        Log.debug("new window \(c.id) \(c.appid) '\(c.title)' floating=\(c.isFloating) dialog=\(clientIsFloatType(c))")
        if let cm = c.mon { arrange(cm, .move) }
        printstatus()
    }

    // not in mango: `mapped` false is mango's surface not mapped yet, the rules alone; the port's
    // windows found mapped already (at start, back after sleep) are placed by the port
    @discardableResult
    package func clientApplyRules(_ c: Client, mapped: Bool = true) -> (mon: Monitor, tags: UInt32) {
        var mon: Monitor = selectedMonitor
        var newtags: UInt32 = 0
        c.isFloating = clientIsFloatType(c)

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

            if c.isNamedScratchpad { c.isFloating = true }

            let full = mon.screen.frame
            if let w = r.width, w > 1 { c.floatGeom.size.width = CGFloat(w) } else if let w = r.width, w > 0 { c.floatGeom.size.width = (full.width * CGFloat(w)).rounded() }
            if let h = r.height, h > 1 { c.floatGeom.size.height = CGFloat(h) } else if let h = r.height, h > 0 { c.floatGeom.size.height = (full.height * CGFloat(h)).rounded() }
            if (r.width ?? 0) > 0 || (r.height ?? 0) > 0 { c.isCustomSize = true }

            let ox = r.offsetX ?? 0, oy = r.offsetY ?? 0
            if ox != 0 || oy != 0 {
                c.isCustomPos = true
                c.floatGeom = clientCenterGeometry(c, mon, c.floatGeom, ox, oy)
            }
        }

        if newtags == 0 && isSpecialActive(mon) { newtags = TagMask.special }

        setSizePer(mon, c)

        if !c.isCustomPos {
            c.floatGeom = clientCenterGeometry(c, mon, c.floatGeom)
        }
        // Not in mango: a floating window off its monitor (there when mango started, or
        // no_force_center) is centred on it.
        if c.isFloating, !mon.screen.frame.intersects(c.floatGeom) {
            let w = mon.screen.workArea
            c.floatGeom = CGRect(x: w.midX - c.floatGeom.width / 2, y: w.midY - c.floatGeom.height / 2,
                                 width: c.floatGeom.width, height: c.floatGeom.height)
        }

        if !mapped { return (mon, newtags) }

        let shouldInitGetFocus = !c.isOpenSilent
            && (!c.isTagSilent || newtags == 0 || newtags & mon.tagset[mon.seltags] != 0)
        if !shouldInitGetFocus {
            focusStack.removeAll { $0 == c.id }
            focusStack.append(c.id)
        }

        layoutStateInsert(c, on: mon)
        clientSetMonitor(c, mon, newtags, focus: shouldInitGetFocus)

        if let cm = c.mon, !(cm === selectedMonitor && c.tags & cm.tagset[cm.seltags] != 0),
           !c.isOpenSilent, !c.isTagSilent {
            clientViewOnMonitor(c.tags, on: cm, changeFocus: true)
        }

        if let cm = c.mon, !c.isFloating {
            for fc in clients where fc !== c && c.tags & fc.tags != 0 && fc.isVisible(on: cm)
                && (fc.isFullscreen || fc.isMaximizeScreen) {
                clearFullscreenFlag(fc)
                arrange(cm)
            }
        }

        if c.isFloating && !c.isCustomPos && !c.isNamedScratchpad {
            clients.removeAll { $0 === c }
            clients.append(c)
            setFloatMalposition(c)
        }

        if c.isNamedScratchpad { applyNamedScratchpad(c) }
        return (mon, newtags)
    }

    func applyRuleProperties(_ c: Client, _ r: WindowRule) {
        if let v = r.noFocus { c.noFocus = v }
        if let v = r.confinePointer { c.confinePointer = v }
        if let v = r.noForceCenter { c.noForceCenter = v }
        if let v = r.isFloating { c.isFloating = v }
        if let v = r.isFullscreen { c.isFullscreen = v }
        if let v = r.isFakeFullscreen { c.isFakeFullscreen = v }
        if let v = r.noBorder { c.noBorder = v }
        if let v = r.noAnimation { c.noAnimation = v }
        if let v = r.isOpenSilent { c.isOpenSilent = v }
        if let v = r.isTagSilent { c.isTagSilent = v }
        if let v = r.isNamedScratchpad { c.isNamedScratchpad = v }
        if let v = r.isGlobal { c.isGlobal = v }
        if let v = r.isOverlay { c.isOverlay = v }
        if let v = r.ignoreMinimize { c.ignoreMinimize = v }
        if let v = r.isUnmanagedGlobal { c.isUnglobal = v }
        if let v = r.scrollerProportion { c.scrollerProportion = CGFloat(v); if v > 0 { c.isCustomScrollerProportion = true } }
        if let v = r.scrollerProportionSingle { c.scrollerProportionSingle = CGFloat(v); if v > 0 { c.isCustomScrollerProportionSingle = true } }
        if let v = r.animationTypeOpen { c.animationTypeOpen = v }
    }

    /// Not in mango: the port's per-tag layout state (scroller columns, dwindle tree) takes
    /// a new window next to the focused one before focus moves to it.
    package func layoutStateInsert(_ c: Client, on m: Monitor) {
        let st = m.current.state
        st.scrollerState.insert(c.id, afterFocused: m.sel)
        st.dwindleRoot.dwindleInsertWithConfig(c.id, nextTo: m.sel, config: config, cursor: system.pointer)
    }

    package func clientSetMonitor(_ c: Client, _ m: Monitor?, _ newtags: UInt32, focus: Bool) {
        let oldmon = c.mon
        if oldmon === m { return }
        if let oldmon, oldmon.sel == c.id { oldmon.sel = nil }
        if let oldmon, oldmon.prevsel == c.id { oldmon.prevsel = nil }
        c.mon = m
        if let oldmon { arrange(oldmon) }
        if c.groupParked { return }
        if let m {
            clientResetMonTags(c, m, newtags)
            checkMatchTagFloatingRule(c, m)
            clientSetFloating(c, c.isFloating)
            clientApplyFullscreen(c, c.isFullscreen, rearrange: true)
        }
        if focus { clientFocus(clientFocusTop(selectedMonitor)) }
    }

/// Not in mango: the port's overview leaves the tags in view, so the overview backup is the tagset.
    package func clientResetMonTags(_ c: Client, _ mon: Monitor, _ newtags: UInt32) {
        if newtags == 0 {
            let inOverview = overviewState.map { $0.monitor === mon } ?? false
            c.tags = inOverview ? mon.ovbkCurrentTagset : mon.tagset[mon.seltags]
        } else {
            let masked = newtags & TagMask.special != 0 ? TagMask.special : normalizeTagMask(newtags) & ~TagMask.special
            c.tags = masked != 0 ? masked : mon.tagset[mon.seltags]
        }
    }

    package func checkMatchTagFloatingRule(_ c: Client, _ mon: Monitor) {
        if c.tags != 0 && !c.isFloating, let t = TagMask.getTagsFirstTagNum(c.tags), mon.pertag[t].openAsFloating {
            c.isFloating = true
        }
    }

    func clientIsFloatType(_ c: Client) -> Bool { c.platform.isFloatType }

    func clientUpdateOldmonnameRecord(_ c: Client, _ m: Monitor) {
        // not in mango: no iskilling or mapped test; every Client is a mapped window.
        c.oldmonname = m.screen.displayID
    }

    func clearFullscreenFlag(_ c: Client) {
        guard let m = c.mon else { return }
        let layout = m.pertag[TagMask.getTagsFirstTagNum(c.tags) ?? m.getMonCurtag].layout
        if !c.isFloating && (layout.isScroller || (layout == .monocle && config.monocleTabMode)) { return }
        if c.isFullscreen { clientApplyFullscreen(c, false, rearrange: true) }
        if c.isMaximizeScreen { clientSetMaximizeScreen(c, false, rearrange: true) }
    }

    func clearFullscreenAndMaximizedState(_ m: Monitor) {
        for fc in clients where fc.isVisible(on: m) && (fc.isFullscreen || fc.isMaximizeScreen) {
            clearFullscreenFlag(fc)
        }
    }

    func clientSetFloating(_ c: Client, _ floating: Bool) {
        let oldFloatingState = c.isFloating
        c.isFloating = floating
        guard let m = c.mon else { return }
        if floating && grab?.client !== c {
            c.isFullscreen = false
            c.isMaximizeScreen = false
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
            c.isNamedScratchpad = false
            setSizePer(m, c)
            for fc in clients where fc !== c && fc.isVisible(on: m) && c.tags & fc.tags != 0
                && (fc.isFullscreen || fc.isMaximizeScreen) && oldFloatingState {
                clearFullscreenFlag(fc)
            }
        }
        arrange(m)
        printstatus()
    }

    func clientApplyFullscreen(_ c: Client, _ fullscreen: Bool, rearrange: Bool) {
        guard let m = c.mon, grab?.client !== c else { return }
        if overviewState?.monitor === m { return }
        c.isFullscreen = fullscreen
        if fullscreen {
            c.isMaximizeScreen = false
            exitScrollerStack(c)
            c.isFakeFullscreen = false
        } else if c.isFloating {
            clientSetFloating(c, true)
        }
        if rearrange { arrange(m) }
    }

    func clientSetFakeFullscreen(_ c: Client, _ fakefullscreen: Bool) {
        c.isFakeFullscreen = fakefullscreen
        guard c.mon != nil else { return }
        if c.isFullscreen { clientApplyFullscreen(c, false, rearrange: true) }
    }

    func clientSetMaximizeScreen(_ c: Client, _ maximizescreen: Bool, rearrange: Bool) {
        guard let m = c.mon, grab?.client !== c else { return }
        if overviewState?.monitor === m { return }
        c.isMaximizeScreen = maximizescreen
        if maximizescreen {
            c.isFullscreen = false
            exitScrollerStack(c)
        } else if c.isFloating {
            clientSetFloating(c, true)
        }
        if rearrange { arrange(m) }
    }

/// Not in mango: the port keeps the scroller's column order in the tag's state.
    func exitScrollerStack(_ c: Client) {
        guard let m = c.mon else { return }
        m.pertag[TagMask.getTagsFirstTagNum(c.tags) ?? m.getMonCurtag].state.scrollerState.exitScrollerStack(c.id)
    }

    package func clientInsertTilingOrder(_ c: Client) {
        let m: Monitor = selectedMonitor
        let scrollTiled = visibleClients(m).filter { !$0.isFloating && !$0.isMinimized && !$0.isUnglobal && $0 !== c }
        var at: Client?
        if config.newIsMaster && !m.layout.isScroller {
            clients.insert(c, at: 0)
            return
        } else if m.layout.isScroller && !scrollTiled.isEmpty {
            if let sel = m.sel.flatMap({ clientById($0) }), scrollTiled.contains(where: { $0 === sel }) {
                at = m.current.state.scrollerState.column(of: sel.id).last.flatMap { clientById($0) } ?? sel
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
        for c in clients where c.isFloating && c !== tc && c.isVisible(on: m)
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
            let g = c.geom ?? c.frame
            return pow(g.midX - w.midX, 2) + pow(g.midY - w.midY, 2)
        }
        return d.indices.min { d[$0] < d[$1] }.map { tiled[$0] }
    }

    package func handleClientUnmap(_ c: Client) {
        let id = c.id
        guard clientByIdAll(id) === c else { return }
        var stackNext: Client?, stackPrev: Client?
        if let cm = c.mon, c.isVisible(on: cm) {
            let col = cm.current.state.scrollerState.column(of: id)
            if let i = col.firstIndex(of: id) {
                stackNext = i + 1 < col.count ? clientByIdAll(col[i + 1]) : nil
                stackPrev = i > 0 ? clientByIdAll(col[i - 1]) : nil
            }
        }
        // Port extension: not in mango. Its group and its place in the order, for when the
        // window comes back (macOS reports windows gone and back around sleep).
        let group = c.isGroupMember ? groupMembers(c) : []
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
        system.cancelAnimation(id)
        for m in monitors {
            for p in m.pertag {
                p.state.scrollerState.scrollerNodeRemove(id)
                p.state.dwindleRoot.dwindleRemove(id, config: config)
            }
            if m.sel == id { m.sel = nil }
            if m.prevsel == id { m.prevsel = nil }
        }
        guard let m = c.mon else { return }
        arrange(m, .move)
        if m === selectedMonitor {
            var next = stackNext ?? stackPrev ?? clientFocusTop(m)
            if let n = next, !n.isVisible(on: m) { next = clientFocusTop(m) }
            if let next { clientFocus(next) } else if overviewState?.monitor === m { leaveOverview(select: nil) }
        }
        printstatus()
    }

    package func handleClientDestroy(_ c: Client) {
        switcherRemoveClient(c.id)
    }

    package func handleClientActivationRequest(_ c: Client) {
        guard clientByIdAll(c.id) === c else { return }
        if config.focusOnActivate && !c.isTagSilent && c.id != selectedMonitor.sel {
            if let m = c.mon, !(m === selectedMonitor && c.tags & m.tagset[m.seltags] != 0) {
                clientViewOnMonitor(c.tags, on: m, changeFocus: true)
            }
            clientFocus(c)
        } else if c !== clientFocusTop(selectedMonitor) {
            c.isUrgent = true
            updateBorders()
            printstatus()
        }
    }

    package func handleClientRequestMinimize(_ c: Client, _ minimized: Bool) {
        guard clientByIdAll(c.id) === c, c.mon != nil, !c.isMinimized, !c.groupParked else { return }
// not in mango: no client_set_minimized; the port has done the Dock's part.
        if minimized && !c.ignoreMinimize {
            setMinimized(c)
        }
    }

    package func handleClientSetTitle(_ c: Client) {
        guard clientByIdAll(c.id) === c else { return }
        tabRefreshBars()
        titleMessageBarUpdateTitle(c)
        if let m = c.mon, c === clientFocusTop(m) { printstatus() }
    }
}
