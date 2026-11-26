import XCTest
import ApplicationServices
@testable import Mango
@testable import Port

final class FakeApp: WindowWriter {
    struct Write: Equatable {
        var id: CGWindowID
        var frame: CGRect
        var setSize: Bool
    }

    var frames: [CGWindowID: CGRect] = [:]
    var writes: [Write] = []
    var minSize: [CGWindowID: CGSize] = [:]
    var busy = false
    var movesBackTo: [CGWindowID: CGRect] = [:]
    var appliesAfter: TimeInterval = 0
    /// The port's clock: an answer after appliesAfter comes on it.
    weak var clock: TestClock?
    private var elements: [(AXUIElement, CGWindowID)] = []

    func element(for id: CGWindowID) -> AXUIElement {
        if let e = elements.first(where: { $0.1 == id }) { return e.0 }
        let e = AXUIElementCreateApplication(pid_t(id))
        elements.append((e, id))
        return e
    }

    private func id(of element: AXUIElement) -> CGWindowID? {
        elements.first { CFEqual($0.0, element) }?.1
    }

    func write(_ element: AXUIElement, id: CGWindowID, frame: CGRect, setSize: Bool, animating: Bool,
               written: (@MainActor (CGRect) -> Void)?) {
        writes.append(Write(id: id, frame: frame, setSize: setSize))
        // the AX call returns, applied or not: written is told either way
        let report = { (f: CGRect?) in
            guard let written, let f else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { written(f) } }
        }
        guard !busy else { report(frame); return }
        var f = frame
        if !setSize, let old = frames[id] { f.size = old.size }
        if let m = minSize[id] {
            f.size.width = max(f.width, m.width)
            f.size.height = max(f.height, m.height)
        }
        if appliesAfter > 0, let clock {
            MainActor.assumeIsolated {
                clock.after(appliesAfter) { [self] in
                    frames[id] = movesBackTo[id] ?? f
                    report(frames[id])
                }
            }
            return
        }
        frames[id] = movesBackTo[id] ?? f
        report(frames[id])
    }

    func readBack(_ element: AXUIElement, completion: @escaping @MainActor (CGRect?) -> Void) {
        let f = busy ? nil : id(of: element).flatMap { frames[$0] }
        DispatchQueue.main.async { MainActor.assumeIsolated { completion(f) } }
    }

    func raise(_ element: AXUIElement) {}
    func async(_ body: @escaping () -> Void) { body() }
    func restoreAppSettings() {}
}

/// mango's MangoBarDecoration as the tests see it.
@MainActor
final class FakeBar: MangoBarDecoration {
    var enabled = true
    var lastText: String?
    var lastScale = 0.0
    var frame = CGRect.zero
    var data: DecorateDrawData
    var updates = 0, raises = 0, destroyed = false
    init(_ data: DecorateDrawData) { self.data = data }
    func setEnabled(_ enabled: Bool) { self.enabled = enabled }
    func setPosition(_ x: CGFloat, _ y: CGFloat) { frame.origin = CGPoint(x: x, y: y) }
    func raiseToTop() { raises += 1 }
    func update(_ text: String, _ scale: Double) { lastText = text; lastScale = scale; updates += 1 }
    func setSize(_ width: CGFloat, _ height: CGFloat) { frame.size = CGSize(width: width, height: height) }
    func setFocus(_ focused: Bool) {}
    func setCenterSecondaryLine(_ center: Bool) {}
    func applyConfig(_ data: DecorateDrawData) { self.data = data }
    func destroy() { destroyed = true }
}

/// mango's MangoJumpLabel as the tests see it.
@MainActor
final class FakeJumpLabel: MangoJumpLabel {
    var enabled = false
    var logicalWidth: CGFloat = 0
    var logicalHeight: CGFloat = 0
    var text: String?
    var position = CGPoint.zero
    var data: DecorateDrawData
    var destroyed = false
    init(_ data: DecorateDrawData) { self.data = data }
    func setEnabled(_ enabled: Bool) { self.enabled = enabled }
    func setPosition(_ x: CGFloat, _ y: CGFloat) { position = CGPoint(x: x, y: y) }
    func raiseToTop() {}
    func update(_ text: String, _ scale: Double) { self.text = text; logicalWidth = 40; logicalHeight = 40 }
    func applyConfig(_ data: DecorateDrawData) { self.data = data }
    func destroy() { destroyed = true }
}

/// The borders the port shows, drawn nowhere.
@MainActor
final class FakeBorders: BorderDrawing {
    var shown: [BorderSpec] = []
    func update(_ specs: [BorderSpec]) { shown = specs }
    func forget(_ id: CGWindowID) { shown.removeAll { $0.id == id } }
    func restack(_ ids: Set<CGWindowID>?, inPlace: (CGWindowID, CGWindowID) -> Bool) {}
}

/// The tab or group bars the port shows, drawn nowhere.
@MainActor
final class FakeBars: BarDrawing {
    var onSelect: ((CGWindowID) -> Void)?
    var onClose: ((CGWindowID) -> Void)?
    var onRightClick: ((CGWindowID) -> Void)?
    var shown: [TabStrip] = []
    func update(_ strips: [TabStrip], style: TabStripStyle, keyFocus: CGWindowID?) { shown = strips }
    func restack(_ ids: Set<CGWindowID>?, inPlace: (CGWindowID, CGWindowID) -> Bool) {}
}

/// The tests' panels (PortPanels): nothing is drawn, what the port asked is kept.
@MainActor
final class FakePanels: PortPanels {
    var plates: [ClientID: CGRect] = [:]
    var overviewCards: [OverviewCard]?, switcherTiles: [SwitcherTilePicture]?
    var bars: [FakeBar] = []
    var jumpLabels: [ClientID: FakeJumpLabel] = [:]
    var specialDimAlpha: Double?, shownDropArea: CGRect?, nagArgv: [String]?, nagInput = ""
    var fitNotification: (title: String, body: String, fit: Bool)?
    var cursorHidden = false
    var cursorName: String??
    var scenePanels: [FakeScenePanel] = []

    /// The plate's box is kept, on its monitor.
    func showEdgePlate(_ c: Client, box: CGRect, monitor: CGRect, border: EdgePlates.Border) {
        plates[c.windowID] = box.intersection(monitor)
    }
    func setEdgePlateBorder(_ id: ClientID, _ border: EdgePlates.Border) {}
    func hideEdgePlate(_ id: ClientID) { plates[id] = nil }
    func hideAllEdgePlates() { plates = [:] }
    func showOverview(_ cards: [OverviewCard], on m: Monitor, look: OverviewLook) { overviewCards = cards }
    func updateOverview(_ cards: [OverviewCard], on m: Monitor) { overviewCards = cards }
    func captureOverviewCards(on m: Monitor, scale: CGFloat) {}
    func closeOverview(on m: Monitor) { overviewCards = nil }
    var overviewShown: Bool { overviewCards != nil }
    func showSwitcher(panel: CGRect, tiles: [SwitcherTilePicture], look: SwitcherLook, scale: CGFloat) { switcherTiles = tiles }
    func switcherApplyHighlight(_ tiles: [SwitcherTilePicture]) { switcherTiles = tiles }
    func closeSwitcher() { switcherTiles = nil }
    func barDecoration(_ m: Monitor, _ data: DecorateDrawData, _ width: CGFloat, _ height: CGFloat) -> MangoBarDecoration? {
        let bar = FakeBar(data)
        bars.append(bar)
        return bar
    }
    func jumpLabel(_ c: Client, _ data: DecorateDrawData) -> MangoJumpLabel? {
        let label = FakeJumpLabel(data)
        jumpLabels[c.windowID] = label
        return label
    }
    func showSpecialDim(on m: Monitor, alpha: Float?, below: CGWindowID?) { specialDimAlpha = alpha.map(Double.init) }
    func showDropArea(_ area: CGRect?, color: RGBA) { shownDropArea = area }
    func nagSpawn(_ argv: [String], input: String, selected: CGDirectDisplayID?, macOS: Bool) { nagArgv = argv; nagInput = input }
    func nagKill() { nagArgv = nil }
    func postFitNotification(title: String, body: String, fit: Bool) { fitNotification = (title, body, fit) }
    func removeFitNotification() { fitNotification = nil }
    func setCursorHidden(_ hidden: Bool) { cursorHidden = hidden }
    func setCursor(_ name: String?) { cursorName = .some(name) }
    func scenePanel(frame: CGRect, look: SceneDrawing.Look,
                    capture: @escaping ([ClientID], @escaping (ClientID, CGImage) -> Void) -> Void,
                    icon: @escaping (ClientID) -> NSImage?,
                    layoutIcon: @escaping (LayoutKind) -> CGImage?,
                    windowSizes: @escaping (ClientID) -> SceneDrawing.WindowSize?) -> any ScenePanelDrawing {
        let panel = FakeScenePanel(frame: frame, look: look, windowSizes: windowSizes)
        scenePanels.append(panel)
        return panel
    }
}

/// A scene panel with no window: it keeps SceneDrawing's draw list of the last frame.
@MainActor
final class FakeScenePanel: ScenePanelDrawing {
    let frame: CGRect
    let look: SceneDrawing.Look
    let windowSizes: (ClientID) -> SceneDrawing.WindowSize?
    var badges: [SceneDrawing.Badge] = []
    private(set) var list = SceneDrawing.DrawList()
    private(set) var closed = false
    init(frame: CGRect, look: SceneDrawing.Look, windowSizes: @escaping (ClientID) -> SceneDrawing.WindowSize?) {
        self.frame = frame; self.look = look; self.windowSizes = windowSizes
    }
    func draw(_ tree: WlrSceneTree, badges: [SceneDrawing.Badge]?) {
        if let badges { self.badges = badges }
        list = SceneDrawing.draw(tree, at: CGPoint(x: CGFloat(tree.x) - frame.minX, y: CGFloat(tree.y) - frame.minY),
                                 look: look, badges: self.badges, windows: windowSizes)
    }
    func close() { closed = true }
    func covers(_ p: CGPoint) -> Bool { frame.contains(p) }
    func scenePoint(_ p: CGPoint) -> CGPoint {
        let q = SceneDrawing.Geometry(size: look.size, inset: look.inset).scenePoint(CGPoint(x: p.x - frame.minX, y: p.y - frame.minY))
        return CGPoint(x: frame.minX + q.x, y: frame.minY + q.y)
    }
    var badgeHits: [(box: CGRect, tag: UInt32)] { [] }
}

/// The tests' macOS windows (NativeWindows): nothing reaches an app, what the port asked is kept, and the
/// answers are the test's.
@MainActor
final class FakeNativeWindows: NativeWindows {
    var closed: [ClientID] = []
    var focused: [(id: ClientID, raise: Bool)] = []
    var raised: [ClientID] = []
    var axFullscreen: (ClientID) -> Bool? = { _ in false }
    var onScreen: (CGWindowID) -> Bool = { _ in true }
    var anchored = 0
    /// The fullscreen written to each window, and whether the app takes it.
    var fullscreenWrites: [(ClientID, Bool)] = []
    var takesFullscreen: (ClientID) -> Bool = { _ in true }
    var focusAsked: [ClientID] = []
    /// The app's answer to which window has the keys.
    var onAskFocus: (ClientID) -> Void = { _ in }
    var surfaceOverride: ClientID?
    /// The window under a point where no override is set.
    var windowAt: (CGPoint) -> ClientID? = { _ in nil }

    func fullscreenNow(_ c: Client) -> Bool? { axFullscreen(c.windowID) }
    func windowOnScreen(_ id: CGWindowID) -> Bool { onScreen(id) }
    func surfaceAt(_ p: CGPoint) -> ClientID? { surfaceOverride ?? windowAt(p) }
    func askFocus(_ c: Client) { focusAsked.append(c.windowID); onAskFocus(c.windowID) }
    func sendNativeFocus(_ c: Client, raise: Bool) { focused.append((c.windowID, raise)) }
    func sendNativeRaise(_ c: Client) { raised.append(c.windowID) }
    func clientSendClose(_ c: Client) { closed.append(c.windowID) }
    func setNativeFullscreen(_ c: Client, _ fullscreen: Bool, _ done: @escaping @MainActor (Bool) -> Void) {
        fullscreenWrites.append((c.windowID, fullscreen))
        done(takesFullscreen(c.windowID))
    }
    func focusSpaceAnchor(_ m: Monitor) { anchored += 1 }
}

/// The tests' machine (HostSystem): no hardware is read, nothing is started or spawned; what the port
/// asked is kept, and the answers are the test's.
@MainActor
final class FakeHostSystem: HostSystem {
    var pointer = CGPoint(x: 1, y: 1)
    var modifiers: Modifiers = []
    var quits = 0
    var asked = 0
    var rescans = 0
    var canCapture = false
    var warps: [CGPoint] = []
    var keyboardOptions: String?
    var inputDevices: [InputDevice] = []
    var spawned: [String] = [], shelled: [String] = []

    func warp(to p: CGPoint) { warps.append(p); pointer = p }
    func keyboardHardModifiers() -> Modifiers { modifiers }
    var mouseButtons: Int { 0 }
    func setKeyboardOptions(_ options: String) { keyboardOptions = options }
    /// A fixed keymap: a letter's key code is its place in the alphabet.
    func findKeycodesForKeysym(_ keysym: Character) -> MultiKeycode {
        guard let a = keysym.lowercased().first?.asciiValue, a >= 97, a <= 122 else { return MultiKeycode() }
        return MultiKeycode(keycode1: UInt16(a - 97))
    }
    func startInput() {}
    func watchGestures(_ on: Bool) {}
    func askToCapture() { asked += 1 }
    func spawn(_ command: String) { spawned.append(command) }
    func spawnShell(_ command: String) { spawned.append(command); shelled.append(command) }
    /// The tests reach no real app: the watcher does not scan them.
    func rescan() { rescans += 1 }
    func quit() { quits += 1 }
}

@MainActor
final class FakeWindowSystem: MacWindowSystem {
    init(_ server: MangoServer) {
        super.init(server, borders: FakeBorders(), tabBars: FakeBars(), groupBars: FakeBars())
        panels = fakePanels
        native = fakeNative
        host = fakeHost
        // the app answers which window has the keys: this one; the window under a point is the topmost shown
        fakeNative.onAskFocus = { [unowned self] id in windowFocused(id: id) }
        fakeNative.windowAt = { [unowned self] p in server.clientsAll.first { !$0.parked && $0.frame.contains(p) }?.windowID }
    }

    /// What the port asked of macOS about the windows (NativeWindows).
    let fakeNative = FakeNativeWindows()
    var closed: [ClientID] { get { fakeNative.closed } set { fakeNative.closed = newValue } }
    var focused: [(id: ClientID, raise: Bool)] { get { fakeNative.focused } set { fakeNative.focused = newValue } }
    var raised: [ClientID] { get { fakeNative.raised } set { fakeNative.raised = newValue } }
    var axFullscreen: (ClientID) -> Bool? { get { fakeNative.axFullscreen } set { fakeNative.axFullscreen = newValue } }
    var onScreen: (CGWindowID) -> Bool { get { fakeNative.onScreen } set { fakeNative.onScreen = newValue } }
    var anchored: Int { get { fakeNative.anchored } set { fakeNative.anchored = newValue } }
    var fullscreenWrites: [(ClientID, Bool)] { get { fakeNative.fullscreenWrites } set { fakeNative.fullscreenWrites = newValue } }
    var takesFullscreen: (ClientID) -> Bool { get { fakeNative.takesFullscreen } set { fakeNative.takesFullscreen = newValue } }
    var focusAsked: [ClientID] { get { fakeNative.focusAsked } set { fakeNative.focusAsked = newValue } }
    var surfaceOverride: ClientID? { get { fakeNative.surfaceOverride } set { fakeNative.surfaceOverride = newValue } }

    /// What the port asked of its panels (PortPanels).
    let fakePanels = FakePanels()
    var plates: [ClientID: CGRect] { get { fakePanels.plates } set { fakePanels.plates = newValue } }
    var overviewCards: [OverviewCard]? { get { fakePanels.overviewCards } set { fakePanels.overviewCards = newValue } }
    var switcherTiles: [SwitcherTilePicture]? { get { fakePanels.switcherTiles } set { fakePanels.switcherTiles = newValue } }
    var bars: [FakeBar] { get { fakePanels.bars } set { fakePanels.bars = newValue } }
    var jumpLabels: [ClientID: FakeJumpLabel] { get { fakePanels.jumpLabels } set { fakePanels.jumpLabels = newValue } }
    var specialDimAlpha: Double? { get { fakePanels.specialDimAlpha } set { fakePanels.specialDimAlpha = newValue } }
    var shownDropArea: CGRect? { get { fakePanels.shownDropArea } set { fakePanels.shownDropArea = newValue } }
    var nagArgv: [String]? { get { fakePanels.nagArgv } set { fakePanels.nagArgv = newValue } }
    var nagInput: String { get { fakePanels.nagInput } set { fakePanels.nagInput = newValue } }
    var fitNotification: (title: String, body: String, fit: Bool)? { get { fakePanels.fitNotification } set { fakePanels.fitNotification = newValue } }
    var cursorHidden: Bool { get { fakePanels.cursorHidden } set { fakePanels.cursorHidden = newValue } }
    var cursorName: String?? { get { fakePanels.cursorName } set { fakePanels.cursorName = newValue } }

    /// What the port asked of the machine (HostSystem).
    let fakeHost = FakeHostSystem()
    var fakePointer: CGPoint { get { fakeHost.pointer } set { fakeHost.pointer = newValue } }
    var fakeModifiers: Modifiers { get { fakeHost.modifiers } set { fakeHost.modifiers = newValue } }
    var quits: Int { get { fakeHost.quits } set { fakeHost.quits = newValue } }
    var asked: Int { get { fakeHost.asked } set { fakeHost.asked = newValue } }
    var rescans: Int { get { fakeHost.rescans } set { fakeHost.rescans = newValue } }
    var fakeCanCapture: Bool { get { fakeHost.canCapture } set { fakeHost.canCapture = newValue } }
    var warps: [CGPoint] { get { fakeHost.warps } set { fakeHost.warps = newValue } }
    var keyboardOptions: String? { get { fakeHost.keyboardOptions } set { fakeHost.keyboardOptions = newValue } }
    var fakeInputDevices: [InputDevice] { get { fakeHost.inputDevices } set { fakeHost.inputDevices = newValue } }
    var spawned: [String] { get { fakeHost.spawned } set { fakeHost.spawned = newValue } }
    var shelled: [String] { get { fakeHost.shelled } set { fakeHost.shelled = newValue } }

    /// The borders and bars as mango hands them to the port; the port then draws them as it does.
    var borderSpecs: [BorderSpec] = []
    /// How many times mango has drawn the borders.
    var bordersDrawn = 0
    override func drawBorders(_ specs: [BorderSpec]) { borderSpecs = specs; bordersDrawn += 1; super.drawBorders(specs) }
    var tabStrips: [TabStrip] = [], groupStrips: [TabStrip] = []
    override func drawTabBars(_ strips: [TabStrip], style: TabStripStyle) { tabStrips = strips; super.drawTabBars(strips, style: style) }
    override func drawGroupBars(_ strips: [TabStrip], style: TabStripStyle) { groupStrips = strips; super.drawGroupBars(strips, style: style) }
    /// The borders and bars as the port shows them.
    var shownBorderSpecs: [BorderSpec] { (borders as! FakeBorders).shown }
    var shownTabStrips: [TabStrip] { (tabBars as! FakeBars).shown }
    var shownGroupStrips: [TabStrip] { (groupBars as! FakeBars).shown }
}

@MainActor
final class EngineRig {
    let server = MangoServer(configURL: URL(fileURLWithPath: "/nonexistent/mango.conf"))
    let app = FakeApp()
    /// The port's time: it moves as the test settles or runs.
    let clock = TestClock()
    let screen = Screen(displayID: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                        workArea: CGRect(x: 0, y: 37, width: 1728, height: 1080), scale: 2, isMain: true)

    init() {
        keepConfigErrorsInTests()
        wsov = WsovState()   // mango's workspace overview is a global, one per process
        server.config.animations = false
        server.renderBorder = false
        server.rebuildMonitors(screens: [screen])
        let app = app
        server.system = FakeWindowSystem(server)
        server.mac.clock = clock
        app.clock = clock
        server.mac.frameClock.manual = true
        server.mac.memory.layoutURL = nil
        server.mac.writerOverride = { _ in app }
        server.mac.windowServerOverride = { [app] id in app.frames[id] }
        server.mac.stackingOverride = { [] }
        server.started = true
        server.registerPortExtensions()
    }

    var monitor: Monitor { server.monitors.first { $0.screen.displayID == screen.displayID } ?? server.monitors[0] }

    @discardableResult
    func window(_ id: CGWindowID, tags: UInt32 = 1, floating: Bool = false,
                frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600)) -> Client {
        let w = DiscoveredWindow(id: id, pid: getpid(), element: app.element(for: id), bundleId: "test", appName: "Test",
                                 title: "t\(id)", subrole: "AXStandardWindow", isDialog: false, frame: frame, isminimized: false, isfullscreen: false, isAppHidden: false)
        let c = Client(window: w, monitor: monitor, tags: tags)
        c.isfloating = floating
        c.isPendingOpenAnimation = false
        // the scroller's proportions as set_size_per gives a mapped window
        c.scrollerProportion = monitor.pertag.scrollerDefaultProportion[getMonCurtag(monitor)]
        c.scrollerProportionSingle = monitor.pertag.scrollerDefaultProportionSingle[getMonCurtag(monitor)]
        app.frames[id] = frame
        c.id = server.generateClientId()
        server.clients.append(c)
        server.focusStack.insert(c, at: 0)
        return c
    }

    @discardableResult
    func map(_ id: CGWindowID, frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600),
             dialog: Bool = false) -> Client {
        app.frames[id] = frame
        server.mac.windowDiscovered(DiscoveredWindow(
            id: id, pid: getpid(), element: app.element(for: id), bundleId: "test", appName: "Test", title: "t\(id)",
            subrole: dialog ? "AXDialog" : "AXStandardWindow", isDialog: dialog, frame: frame, isminimized: false,
            isfullscreen: false, isAppHidden: false))
        return server.clientByWindowID(id)!
    }

    /// One output frame: what mango changed in the scene is shown (the tests' display link).
    func frame() { server.mac.frameClock.fire() }

    /// The display's next refresh, whether or not mango changed anything (the pointer moved): a new frame_serial.
    func nextFrame() {
        server.system.outputScheduleFrame(monitor)
        frame()
    }

    /// mango's arrange, and the frame that shows it.
    func arrange() {
        server.arrange(monitor, false, false)
        frame()
    }

    /// Steps as settle, until `done` holds, at most `seconds` of the port's time.
    func settle(until done: () -> Bool, atMost seconds: TimeInterval = 2) {
        var left = seconds
        while !done() && left > 0 {
            step()
            left -= Self.stepTime
        }
    }

    /// `seconds` of the port's time in steps of 16 ms, each with the run loop and an output frame (the
    /// tests' display link); then on while windows leaving still wait for those coming back (at most
    /// mango's 100 ms).
    func settle(_ seconds: TimeInterval = 0.05) {
        run(seconds)
        settle(until: { server.mac.placing.parkWhenArrived.isEmpty })
    }

    /// Exactly `seconds` of the port's time, in steps as settle: for a test that looks at the wait itself.
    func run(_ seconds: TimeInterval) {
        var left = seconds
        repeat {
            step()
            left -= Self.stepTime
        } while left > 1e-9
    }

    private static let stepTime: TimeInterval = 0.016

    /// The run loop for a step, the port's clock on by as much, and an output frame.
    private func step() {
        RunLoop.main.run(until: Date().addingTimeInterval(Self.stepTime))
        clock.advance(by: Self.stepTime)
        server.mac.frameClock.fire()
    }
}


extension MangoServer {
    /// Any monitor in overview.
    var anyOverview: Bool { monitors.contains { $0.isoverview } }
}
