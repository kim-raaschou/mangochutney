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
    package var system: WindowSystem!   // the boundary, not in mango: wlroots and the display server
    public package(set) var clients: [Client] = []    /* tiling order */
    public package(set) var focusStack: [Client] = [] /* focus order */
    package var cursorMode = CurNormal
    /* Drag / resize */
    package var grabClient: Client? {
        didSet { if (oldValue == nil) != (grabClient == nil) { publishInputState() } }   // not in mango: the event tap's snapshot
    }
    package var dropClient: Client?
    var resizeEdge: WlrEdges = []
    package var hoverResizeEdge: WlrEdges = []
    var hoverResizeFloating = false
    var grabIsBorderResize = false               /* grab started by a border click */
    var grabOffsetX: CGFloat = 0, grabOffsetY: CGFloat = 0   /* client-relative */
    var grabPointerX: CGFloat = 0, grabPointerY: CGFloat = 0 /* pointer at grab start */
    var dragBeginCursorX: Int32 = 0, dragBeginCursorY: Int32 = 0 /* client-relative */
    var startDragWindow = false
    package var groupBarDragPending = false
    var groupBarDragClient: Client?
    var groupBarDragX: CGFloat = 0, groupBarDragY: CGFloat = 0
    package var dropToGroup = false
    /* Outputs / monitors */
    public internal(set) var monitors: [Monitor] = []
    public package(set) var selectedMonitor: Monitor!
    /* Layout / gestures */
    package var enableGaps = true /* enables gaps; used by toggle_gaps */
    var scrollerFocusLock = false
    var gestureDriveMon: Monitor?
    var gestureDriveActive = false
    var swipeFingers: UInt32 = 0
    var swipeDx = 0.0
    var swipeDy = 0.0
    package var renderBorder = true
    /* Other runtime state */
    var cursorHidden = false
    package var tagCombo = false { didSet { if tagCombo != oldValue { publishInputState() } } }
    public var cliDebugLog = false
    var tagmask: UInt32 = (1 << 9) - 1 /* default 9 tags; updated with config.tag_num */
    var nextClientId: UInt32 = 0
    /* Pre-baked animation curves */
    var bakedPointsMove: [DVec2] = []
    var bakedPointsOpen: [DVec2] = []
    var bakedPointsTag: [DVec2] = []
    var bakedPointsClose: [DVec2] = []
    var bakedPointsFocus: [DVec2] = []
    /* Cursor hiding / input keep-alive */
    var hideCursorSource: EventSource?
    /* Key mode / IPC print-status signal */
    public var keyMode = "default" { didSet { publishInputState() } }

    // not in mango's struct MangoServer: mango's globals and its files' statics, kept on the server
    public internal(set) var config = Config()
    public var configURL: URL
    public internal(set) var configErrors: [ConfigError] = []
    var configFiles: [URL] = []
    var ipc: IPCServer?
    var tabMemberCount: Int32 = 0   // tab.c's static tab_member_count
    /// mango switcher_state (switcher/switcher.c)
    package var switcherState = SwitcherState() {
        didSet { if switcherState.tree != oldValue.tree { publishInputState() } }   // not in mango: the event tap's snapshot
    }
    var confinePointerLast: Client?
    var swipeDrive = SwipeDrive()
    var swipeActive = false
    var swipeLocked = false
    var swipeHorizontal = false
    // mango's static locked_horizontal_node and locked_vertical_node (layout/dwindle.c)
    weak var dwindleLockedHorizontalNode: DwindleNode?
    weak var dwindleLockedVerticalNode: DwindleNode?
    var watchTimer: EventSource?
    var watchedFiles: [WatchedFile] = []
    var watcherActive = false
    var kqueueFd: Int32 = -1
    var kqueueSource: EventSource?

    // not in mango: the port's
    /// Port extension: not in mango. Where the port's extensions join (PortHooks.swift).
    package var portHooks = PortHooks()
    var publishedGlobalKeys = false
    package var drawsOverlays = false   // not in mango: whether the port draws (off in tests)
    package internal(set) var started = false   // not in mango: the port has found its windows
    var bordersDirty = false   // not in mango: a border changed; the port draws them all at once
    // not in mango: clients with the group members the port has parked (mango keeps all in clients)
    public var clientsAll: [Client] {
        var out: [Client] = []
        for c in clients {
            if clientIsGroupMember(c) { out += groupMembers(c).filter { m in m === c || clientIsParked(m) } } else { out.append(c) }
        }
        return out
    }

    /// The boundary, not in mango: the port's status change, which printstatus gives.
    public var onStateChange: (() -> Void)?

    public init(configURL: URL? = nil) {
        self.configURL = configURL ?? ConfigParser.defaultConfigURL()
        initBakedPoints()   // not in mango: baked for a server that is not set up too (the tests)
    }

    public func setup() {
        drawsOverlays = true
        system.prepare()   // not in mango: the port's side
        parseConfig()
        if cliDebugLog {
            config.logLevel = .debug
        }
        initBakedPoints()
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
    package var focused: Client? { selectedMonitor?.sel }


    /// Not in mango: arrange on every monitor.
    package func arrangeAll(_ wantAnimation: Bool) {
        for m in monitors { arrange(m, wantAnimation, false) }
    }


    // not in mango: server.scene_geometry, wlr_output_layout_get_box over the monitors' boxes
    var sceneGeometry: CGRect { monitors.map(\.m).reduce(CGRect.null) { $0.union($1) } }

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
                specs.append(BorderSpec(id: c.windowID, frame: f, color: getBorderColor(c), width: width, radius: radius,
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
