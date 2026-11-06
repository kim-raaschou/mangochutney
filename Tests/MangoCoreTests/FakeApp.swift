import XCTest
import ApplicationServices
@testable import Mango
@testable import Port

/// A fake app for the engine's writes: it keeps each window's real frame and answers the
/// way real apps do (takes the frame, clamps it to a minimum size, does not answer, or
/// moves a hidden window back into view).
final class FakeApp: WindowWriter {
    struct Write: Equatable {
        var id: CGWindowID
        var frame: CGRect
        var setSize: Bool
    }

    /// The windows' real frames.
    var frames: [CGWindowID: CGRect] = [:]
    var writes: [Write] = []
    var minSize: [CGWindowID: CGSize] = [:]
    /// Busy: writes are not applied and read-backs get no answer.
    var busy = false
    /// After each write to this window, the app puts it back here (Arc with a video).
    var movesBackTo: [CGWindowID: CGRect] = [:]
    /// The app takes a write and applies it this many seconds later (Electron: Claude,
    /// VS Code); read-backs before that get the old frame.
    var appliesAfter: TimeInterval = 0
    private var elements: [(AXUIElement, CGWindowID)] = []

    /// A distinct element per window.
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
        guard !busy else { return }
        var f = frame
        if !setSize, let old = frames[id] { f.size = old.size }
        if let m = minSize[id] {
            f.size.width = max(f.width, m.width)
            f.size.height = max(f.height, m.height)
        }
        if appliesAfter > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + appliesAfter) { [self] in frames[id] = movesBackTo[id] ?? f }
            return
        }
        frames[id] = movesBackTo[id] ?? f
        if let written {
            let applied = frames[id]!
            DispatchQueue.main.async { MainActor.assumeIsolated { written(applied) } }
        }
    }

    func readBack(_ element: AXUIElement, completion: @escaping @MainActor (CGRect?) -> Void) {
        let f = busy ? nil : id(of: element).flatMap { frames[$0] }
        DispatchQueue.main.async { MainActor.assumeIsolated { completion(f) } }
    }

    func raise(_ element: AXUIElement) {}
    func async(_ body: @escaping () -> Void) { body() }
    func restoreAppSettings() {}
}

/// The system a test runs on: windows written to the fake app as on macOS, but never the
/// user's pointer, keys or permissions.
@MainActor
final class FakeWindowSystem: MacWindowSystem {
    var fakePointer = CGPoint(x: 1, y: 1)
    var fakeModifiers: Modifiers = []
    var quits = 0
    var asked = 0
    /// Windows asked to close (never the real app's).
    var closed: [ClientID] = []
    override func clientSendClose(_ c: Client) { closed.append(c.id) }
    override var pointer: CGPoint { fakePointer }
    override var modifiers: Modifiers { fakeModifiers }
    /// Not the user's mouse: no button held.
    override var mouseButtons: Int { 0 }
    /// Never the user's keyboard, mouse or trackpad.
    override func startInput() {}
    override func watchGestures(_ on: Bool) {}
    override var canCapture: Bool { false }
    override func quit() { quits += 1 }
    override func askToCapture() { asked += 1 }
    /// Native focus and warps are recorded, never done: the test's own process owns the
    /// fake windows, and the pointer is the user's.
    var focused: [(id: ClientID, raise: Bool)] = []
    var warps: [CGPoint] = []
    override func focus(_ c: Client, raise: Bool) { focused.append((c.id, raise)) }
    override func warp(to p: CGPoint) { warps.append(p) }
    /// A swipe's driven animation, recorded, never run (fakeAnimating: the dispatcher started one).
    var fakeAnimating = false
    var animationProgress: [Double] = [], resumedFrom: [Double] = [], letGo = 0
    override var animationsActive: Bool { fakeAnimating }
    override func holdAnimations() {}
    override func setAnimationProgress(_ p: Double) { animationProgress.append(p) }
    override func resumeAnimations(from p: Double) { resumedFrom.append(p) }
    override func letGoAnimations() { letGo += 1 }
    /// The borders mango asked for last; never drawn.
    var borderSpecs: [BorderSpec] = []
    override func drawBorders(_ specs: [BorderSpec]) { borderSpecs = specs }
    var tabStrips: [TabStrip] = [], groupStrips: [TabStrip] = []
    override func drawTabBars(_ strips: [TabStrip], style: TabStripStyle) { tabStrips = strips }
    override func drawGroupBars(_ strips: [TabStrip], style: TabStripStyle) { groupStrips = strips }
    /// The overlays mango asked for; none is drawn, the pointer is never hidden.
    var overviewCards: [OverviewCard]?, jumpLabelCount = 0, switcherTiles: [SwitcherTile]?
    var titleMessageBar: String?, specialDimAlpha: Double?, shownDropArea: CGRect?, nagArgv: [String]?, nagInput = "", cursorHidden = false
    override func showOverview(_ cards: [OverviewCard], on m: Monitor, look: OverviewLook) { overviewCards = cards }
    override func updateOverview(_ cards: [OverviewCard]) { overviewCards = cards }
    override func captureOverviewCards(scale: CGFloat) {}
    override func closeOverview() { overviewCards = nil }
    override func showJumpLabels(_ labels: [(String, CGRect)], look: DecorateStyle) { jumpLabelCount = labels.count }
    override func closeJumpLabels() { jumpLabelCount = 0 }
    override func showSwitcher(panel: CGRect, tiles: [SwitcherTile], look: SwitcherLook, scale: CGFloat) { switcherTiles = tiles }
    override func highlightSwitcher(_ tiles: [SwitcherTile]) { switcherTiles = tiles }
    override func closeSwitcherPanel() { switcherTiles = nil }
    override func showTitleMessageBar(frame: CGRect, title: String, appid: String, look: DecorateStyle) { titleMessageBar = title }
    override func hideTitleMessageBar() { titleMessageBar = nil }
    override func showSpecialDim(on m: Monitor, alpha: Double?, over: Set<ClientID>) { specialDimAlpha = alpha }
    override func showDropArea(_ area: CGRect?, color: RGBA) { shownDropArea = area }
    override func nagSpawn(_ argv: [String], input: String) { nagArgv = argv; nagInput = input }
    override func nagKill() { nagArgv = nil }
    override func setCursorHidden(_ hidden: Bool) { cursorHidden = hidden }
    /// The cursor mango asked for last (never set); `.some(nil)`: given back to the window.
    var cursorName: String??
    override func setCursor(_ name: String?) { cursorName = .some(name) }
    /// The window under a point: the topmost fake window, or `surfaceOverride` (a popup).
    var surfaceOverride: ClientID?
    override func surfaceAt(_ p: CGPoint) -> ClientID? {
        surfaceOverride ?? server.clientsAll.first { !$0.parked && $0.frame.contains(p) }?.id
    }
    /// xkb_rules_options as mango applied them; the keyboard is never touched.
    var keyboardOptions: String?
    override func setKeyboardOptions(_ options: String) { keyboardOptions = options }
    /// Commands and config watching mango asked for; nothing is run or watched.
    var spawned: [String] = [], shelled: [String] = [], watchedConfig: [URL] = []
    override func spawn(_ command: String) { spawned.append(command) }
    override func spawnShell(_ command: String) { spawned.append(command); shelled.append(command) }
    override func watchConfig(_ files: [URL]) { watchedConfig = files }
}

/// An engine with one screen, no animations, borders or focus, writing to `app`.
@MainActor
final class EngineRig {
    let server = MangoServer(configURL: URL(fileURLWithPath: "/nonexistent/mango.conf"))
    let app = FakeApp()
    let screen = Screen(displayID: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                        workArea: CGRect(x: 0, y: 37, width: 1728, height: 1080), scale: 2, isMain: true)

    init() {
        keepConfigErrorsInTests()
        server.config.animations = false
        server.renderBorder = false   // mango's render_border off: frames are the tiles
        server.rebuildMonitors(screens: [screen])
        let app = app
        server.system = FakeWindowSystem(server)
        server.mac.memory.layoutURL = nil   // no saved layout of the user's
        server.mac.writerOverride = { _ in app }
        server.mac.windowServerOverride = { [app] id in app.frames[id] }   // it knows frames without asking the app
        server.mac.stackingOverride = { [] }
        server.started = true   // arrange does nothing before start
        server.registerPortExtensions()   // as start() does
    }

    var monitor: Monitor { server.monitors[0] }

    /// A managed window on `tags`, at `frame` in the fake app.
    @discardableResult
    func window(_ id: CGWindowID, tags: UInt32 = 1, floating: Bool = false,
                frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600)) -> Client {
        let w = DiscoveredWindow(id: id, pid: getpid(), element: app.element(for: id), bundleId: "test", appName: "Test",
                                 title: "t\(id)", subrole: "AXStandardWindow", isDialog: false, frame: frame, isMinimized: false, isFullscreen: false, isAppHidden: false)
        let c = Client(window: w, monitor: monitor, tags: tags)
        c.isFloating = floating
        c.isPendingOpenAnimation = false
        app.frames[id] = frame
        server.clients.append(c)
        server.focusStack.insert(id, at: 0)   // mango mapnotify
        return c
    }

    /// A window the system finds now: mapped through mango's handle_client_map, as a new
    /// window is.
    @discardableResult
    func map(_ id: CGWindowID, frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600)) -> Client {
        app.frames[id] = frame
        server.mac.windowDiscovered(DiscoveredWindow(
            id: id, pid: getpid(), element: app.element(for: id), bundleId: "test", appName: "Test", title: "t\(id)",
            subrole: "AXStandardWindow", isDialog: false, frame: frame, isMinimized: false,
            isFullscreen: false, isAppHidden: false))
        return server.clientByIdAll(id)!
    }

    /// Lets the fake app's answers (main-queue blocks) arrive.
    func settle(_ seconds: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}


