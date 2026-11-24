import Foundation
import CoreGraphics
import QuartzCore

// not in mango: the port's own version
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
    // not in mango: clients with the group members the port has parked (mango keeps all in clients)
    public var clientsAll: [Client] {
        var out: [Client] = []
        for c in clients {
            if clientIsGroupMember(c) { out += groupMembers(c).filter { m in m === c || m.groupParked } } else { out.append(c) }
        }
        return out
    }
    public package(set) var focusStack: [ClientID] = []
    public package(set) var selectedMonitor: Monitor!
    public var keyMode = "default" { didSet { publishInputState() } }

    var ipc: IPCServer?

    var tabMemberCount: Int32 = 0   // not in mango: tab.c's static tab_member_count
    package var enableGaps = true
    package var renderBorder = true
    package var drawsOverlays = false   // not in mango: whether the port draws (off in tests)
    package internal(set) var started = false   // not in mango: the port has found its windows
    public var cliDebugLog = false

    package var tagCombo = false { didSet { if tagCombo != oldValue { publishInputState() } } }
    /// mango switcher_state (switcher/switcher.c)
    package var switcherState = SwitcherState() {
        didSet { if switcherState.tree != oldValue.tree { publishInputState() } }   // not in mango: the event tap's snapshot
    }
    var publishedGlobalKeys = false
    package var cursorMode = CurNormal
    package var grabClient: Client? {
        didSet { if (oldValue == nil) != (grabClient == nil) { publishInputState() } }   // not in mango: the event tap's snapshot
    }
    var grabOffsetX: CGFloat = 0, grabOffsetY: CGFloat = 0
    var grabPointerX: CGFloat = 0, grabPointerY: CGFloat = 0
    var grabIsBorderResize = false
    var resizeEdge: WlrEdges = []
    package var dropClient: Client?
    package var dropToGroup = false
    var startDragWindow = false
    var confinePointerLast: Client?
    var dragBeginCursor: CGPoint = .zero
    package var system: WindowSystem!
    /// Port extension: not in mango. Where the port's extensions join (PortHooks.swift).
    package var portHooks = PortHooks()
    package var groupBarDragPending = false
    var groupBarDragClient: Client?
    var groupBarDragX: CGFloat = 0, groupBarDragY: CGFloat = 0
    var cursorHidden = false
    var hideCursorSource: EventSource?
    package var hoverResizeEdge: WlrEdges = []
    var hoverResizeFloating = false
    var swipeDrive = SwipeDrive()
    var swipeActive = false
    var swipeLocked = false
    var swipeHorizontal = false
    var swipeDx = 0.0
    var swipeDy = 0.0
    var swipeFingers: UInt32 = 0
    var gestureDriveMon: Monitor?
    var gestureDriveActive = false
    // mango's static locked_horizontal_node and locked_vertical_node (layout/dwindle.c)
    weak var dwindleLockedHorizontalNode: DwindleNode?
    weak var dwindleLockedVerticalNode: DwindleNode?
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
        // not in mango: no init_baked_points; find_animation_curve_at solves the curve
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

        hideCursorSource = system.eventLoop.addTimer { [weak self] in self?.pointerHideCursor() }
        let server = IPCServer(server: self, loop: system.eventLoop)
        do { try server.ipcInit(); ipc = server } catch { wlrLog(.error, "IPC server failed: \(error)") }   // not in mango: ipc_init's failures thrown
        configWatcherInit(system.eventLoop)
        configErrorNagInit()

        // not in mango: run's part of the start, in setup
        setEnvDisplay()
        /* At this point the outputs are initialized, choose initial
         * selected_monitor based on cursor position, and set default cursor image
         */
        if let m = monitorAtPoint(system.pointer) { setSelectedMonitor(m) }   // not in mango: kept when the pointer is on no monitor
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

    package func clientNoRadiusActive(_ c: Client) -> Bool {
        guard let m = c.mon else { return false }

        if c.isfullscreen || (config.noRadiusWhenSingle && m.visibleTilingClients == 1) {
            return true
        }

        return config.monocleNoRadius && ISFAKETILED(c) && !m.isoverview && isMonocleLayout(m)
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

    // not in mango: selected_monitor->sel as a client
    package var focused: Client? { selectedMonitor?.sel.flatMap { clientByIdAll($0) } }


    /// Not in mango: arrange on every monitor.
    package func arrangeAll(_ wantAnimation: Bool) {
        for m in monitors { arrange(m, wantAnimation, false) }
    }


/// mango client_center_geometry (manage/client.c). Not in mango: without offsets, in a work area.
    func clientCenterGeometry(_ c: Client, _ f: CGRect, in work: CGRect) -> CGRect {
        guard !c.noForceCenter else { return f }
        return CGRect(x: work.midX - f.width / 2, y: work.midY - f.height / 2, width: f.width, height: f.height)
    }


    var sceneGeometry: CGRect { monitors.map(\.m).reduce(CGRect.null) { $0.union($1) } }

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



    // not in mango: c->bw (no_border, fullscreen) as check_hit_no_border leaves it, in points
    func borderWidth(_ c: Client, on m: Monitor) -> CGFloat {
        guard config.borderpx > 0, !c.noBorder, !c.isfullscreen, !checkHitNoBorder(c) else { return 0 }
        return CGFloat(config.borderpx)
    }

    // not in mango: client_draw_border for every window at once; the port draws the borders in one overlay
    package func updateBorders() {
        drawBars()
        guard renderBorder, config.borderpx > 0 else { system.drawBorders([]); return }
        var specs: [BorderSpec] = []
        for m in monitors {
            for c in clients where c.mon === m && c.platform.sceneNodeEnabled {
                let width = borderWidth(c, on: m)
                guard width > 0 else { continue }
                var f = c.animation.current.insetBy(dx: c.bw, dy: c.bw)
                let top = !barsInsideBorder ? 0
                    : (c.isTabFocus && c.tabBarEnabled ? CGFloat(config.tabBarHeight) : 0) + (clientCheckTabNodeVisible(c, on: m) ? CGFloat(config.groupBarHeight) : 0)
                f = CGRect(x: f.minX, y: f.minY - top, width: f.width, height: f.height + top)
                let radius = clientNoRadiusActive(c) ? 0 : CGFloat(config.borderRadius)
                // not in mango: compute_edge_offsets as a clip to the monitor, which the port applies
                specs.append(BorderSpec(id: c.id, frame: f, color: getBorderColor(c), width: width, radius: radius,
                                        split: clientDrawSplitBorder(c, on: m),
                                        clip: clientIsIgnoreOutputClip(c) ? nil : m.m))
            }
        }
        if drawsOverlays { system.drawBorders(specs) }
    }

    // not in mango: client_draw_split_border's choice of side; the port draws it in the border's overlay
    func clientDrawSplitBorder(_ c: Client, on m: Monitor) -> (side: BorderSpec.SplitSide, color: RGBA)? {
        let tag = getClientTagIdx(c)
        let layout = m.pertag.ltidxs[tag]
        if !ISTILED(c) || layout != .dwindle || !config.dwindleManualSplit || c.isfullscreen { return nil }
        guard let dnode = dwindleFindLeaf(m.pertag.dwindleRoot[tag], c) else { return nil }
        return (dnode.customLeafSplitH ? .right : .bottom, config.splitcolor)
    }



































}
